--[[
    Roblox MCP Bridge - Potassium collector (v3.0.0)

    Run this in Potassium while in a game. It connects out to the MCP server
    (ws://127.0.0.1:8790 by default), pushes game state, and answers requests.

    Transport
      Primary  : WebSocket. Nothing on disk is needed.
      Fallback : JSON files under <potassium workspace>/mcp_bridge, polled both
                 ways. Used automatically when the socket cannot be opened.

    Files written when mirroring is on (default):
      mcp_bridge/snapshot.json         light per-tick state
      mcp_bridge/explorer.json         full scan: index, scripts, remotes, trees, gui, assets
      mcp_bridge/console_log.json      client output buffer
      mcp_bridge/remote_traffic.json   captured remote calls
      mcp_bridge/heartbeat.json        liveness
      mcp_bridge/bridge_request.json   <- written by the MCP server (fallback mode)
      mcp_bridge/bridge_response.json  -> written by this script (fallback mode)
]]

local CONFIG = {
    -- Set WS_URL to pin one endpoint (e.g. "ws://192.168.1.50:8790" for a
    -- bridged emulator or a second machine). Left empty, the bridge probes
    -- WS_HOSTS in order and remembers whichever answers.
    WS_URL = "",
    WS_PORT = 8790,
    WS_HOSTS = {
        "127.0.0.1", -- same machine
        "10.0.2.2", -- Android Studio AVD -> host loopback
        "10.0.3.2", -- Genymotion / VirtualBox -> host loopback
    },
    -- How long to wait after connecting before believing an endpoint. Only
    -- applies while more than one candidate is in play.
    WS_VERIFY_DELAY = 0.75,
    WS_RECONNECT_DELAY = 3,
    WS_MAX_RECONNECT_DELAY = 30,

    SNAPSHOT_INTERVAL = 0.5,
    EXPLORER_INTERVAL = 30,
    LOG_FLUSH_INTERVAL = 1,
    FILE_POLL_INTERVAL = 0.4,
    FILE_MIRROR_INTERVAL = 1,

    OUT_DIR = "mcp_bridge",
    -- Mirror state to JSON files whenever the socket is unavailable.
    MIRROR_FILES = true,

    -- scan limits
    MAX_SCAN_INSTANCES = 60000,
    MAX_INDEX = 8000,
    MAX_REMOTES = 1500,
    MAX_SCRIPTS = 3000,
    MAX_ASSETS = 5000,
    SCAN_YIELD_EVERY = 2500,

    -- source
    SCAN_SOURCE_PREVIEW = 2000,
    SOURCE_CHUNK_MAX = 200000,

    -- Potassium's own decompile() returns "-- Failed to decompile" on most
    -- scripts. When it does, fall back to Konstant, fetched and executed at
    -- runtime. That is third-party remote code running with full executor
    -- privileges and its contents can change at any time; set this to false to
    -- keep the bridge to the native decompiler only.
    ALLOW_REMOTE_DECOMPILER = true,
    REMOTE_DECOMPILER_URL = "https://raw.githubusercontent.com/infyiff/backup/refs/heads/main/konstant.lua",
    -- Potassium's own decompile() answers "-- Failed to decompile" on this
    -- game's scripts, so it is skipped entirely. Flip to true to try it first
    -- again; the code path is intact behind this flag.
    USE_NATIVE_DECOMPILER = false,

    -- trees
    MAX_TREE_NODES = 700,
    MAX_TREE_DEPTH = 5,
    MAX_TREE_CHILDREN = 60,
    MAX_GUI_NODES = 2500,
    MAX_GUI_DEPTH = 8,

    -- character
    MAX_CHARACTER_CHILDREN = 80,
    MAX_BALL_DESCENDANTS = 40,

    -- buffers
    LOG_BUFFER_SIZE = 500,
    TRAFFIC_BUFFER_SIZE = 500,
    LOG_DEDUPE_WINDOW = 0.5,

    -- exec
    EXEC_MAX_SOURCE = 60000,
    EXEC_MAX_OUTPUT = 60000,

    -- remote traffic hook
    HOOK_ON_START = false,
    TRAFFIC_MAX_ARGS = 8,
    TRAFFIC_STRING_MAX = 200,
    TRAFFIC_DEPTH = 3,

    -- Periodic full getinstances() rescan. Disable during normal hub play.
    PERIODIC_RESCAN = true,
}

local function applyBridgePerfOverrides()
    local genv = (type(getgenv) == "function" and getgenv()) or _G
    local perf = genv.__MCP_BRIDGE_PERF

    if type(perf) ~= "table" then
        return
    end

    for key, value in pairs(perf) do
        CONFIG[key] = value
    end
end

applyBridgePerfOverrides()

local BRIDGE_VERSION = "3.0.1-local"
local PROTOCOL_VERSION = 3

local FILES = {
    SNAPSHOT = CONFIG.OUT_DIR .. "/snapshot.json",
    EXPLORER = CONFIG.OUT_DIR .. "/explorer.json",
    CONSOLE = CONFIG.OUT_DIR .. "/console_log.json",
    TRAFFIC = CONFIG.OUT_DIR .. "/remote_traffic.json",
    HEARTBEAT = CONFIG.OUT_DIR .. "/heartbeat.json",
    REQUEST = CONFIG.OUT_DIR .. "/bridge_request.json",
    RESPONSE = CONFIG.OUT_DIR .. "/bridge_response.json",
    WS_HOST = CONFIG.OUT_DIR .. "/ws_endpoint.txt",
}

-- ---------------------------------------------------------------------------
-- single-instance guard
-- ---------------------------------------------------------------------------

local genv = (type(getgenv) == "function" and getgenv()) or _G
local GENERATION = (tonumber(genv.__MCP_BRIDGE_GENERATION) or 0) + 1
genv.__MCP_BRIDGE_GENERATION = GENERATION

local function isCurrent()
    return genv.__MCP_BRIDGE_GENERATION == GENERATION
end

-- ---------------------------------------------------------------------------
-- services and shared state
-- ---------------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local printOriginals = genv.__MCP_PRINT_ORIGINALS
if type(printOriginals) ~= "table" then
    printOriginals = { print = print, warn = warn }
    genv.__MCP_PRINT_ORIGINALS = printOriginals
end
local originalPrint = printOriginals.print
local originalWarn = printOriginals.warn

local logBuffer = {}
local logPending = {}
local logDedupe = {}
local logDedupeCount = 0
local activeCollectors = genv.__MCP_COLLECTORS
if type(activeCollectors) ~= "table" then
    activeCollectors = {}
    genv.__MCP_COLLECTORS = activeCollectors
end

local trafficBuffer = {}
local trafficPending = {}

-- Kept in the shared executor env: re-running this script must not stack a
-- second __namecall hook on top of the first.
local hookState = genv.__MCP_HOOK_STATE
if type(hookState) ~= "table" then
    hookState = {
        installed = false,
        enabled = false,
        error = nil,
        captured = 0,
    }
    genv.__MCP_HOOK_STATE = hookState
end

local explorerCache = nil
local explorerCapturedAt = 0
local scanInProgress = false
local loopTick = 0

local socket = nil
local socketReady = false
local socketGeneration = 0
local activeUrl = nil
local lastFileRequestId = nil

-- Forward declarations so handlers can reference each other regardless of order.
local sanitizeValue
local captureNode
local runFullScan
local sendMessage

-- ---------------------------------------------------------------------------
-- small utilities
-- ---------------------------------------------------------------------------

local function safe(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function bridgePrint(...)
    return originalPrint("[MCP]", ...)
end

local function bridgeWarn(...)
    return originalWarn("[MCP]", ...)
end

local function cleanString(value)
    if value == nil then return nil end
    local s = tostring(value)
    if s == "" then return s end
    return (s:gsub("[%z\1-\8\11\12\14-\31\127]", ""))
end

local function safeStr(value)
    if value == nil then return nil end
    return cleanString(value)
end

local function safeNum(value)
    local n = tonumber(value)
    if not n then return nil end
    if n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function trimString(value, maxLen)
    if value == nil then return nil, false end
    local s = tostring(value)
    if #s <= maxLen then return s, false end
    return s:sub(1, maxLen), true
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function className(inst)
    if inst == nil then return nil end
    return safeStr(safe(function() return inst.ClassName end))
end

local function instName(inst)
    if inst == nil then return nil end
    return safeStr(safe(function() return inst.Name end))
end

local function fullName(inst)
    if inst == nil then return nil end
    local name = safe(function() return inst:GetFullName() end)
    if name and name ~= "" then return safeStr(name) end
    return instName(inst)
end

local function isA(inst, class)
    if inst == nil then return false end
    return safe(function() return inst:IsA(class) end) == true
end

--- True when the current thread belongs to the executor (us), not the game.
local function isOurThread()
    if type(isourthread) == "function" then
        local ok, result = pcall(isourthread, coroutine.running())
        if ok then return result == true end
    end
    if type(checkcaller) == "function" then
        local ok, result = pcall(checkcaller)
        if ok then return result == true end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- JSON encoding
--
-- HttpService:JSONEncode rejects mixed tables, NaN and userdata, all of which
-- turn up constantly in property dumps. Encode by hand instead.
-- ---------------------------------------------------------------------------

local ESCAPES = {
    ["\\"] = "\\\\",
    ['"'] = '\\"',
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
}

local function escapeHighBytes(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local b = string.byte(s, i)
        if b < 0x80 then
            out[#out + 1] = string.sub(s, i, i)
            i = i + 1
        else
            local extra = nil
            if b >= 0xC2 and b <= 0xDF then
                extra = 1
            elseif b >= 0xE0 and b <= 0xEF then
                extra = 2
            elseif b >= 0xF0 and b <= 0xF4 then
                extra = 3
            end

            local valid = extra ~= nil and (i + extra) <= n
            if valid then
                for k = 1, extra do
                    local cb = string.byte(s, i + k)
                    if cb < 0x80 or cb > 0xBF then
                        valid = false
                        break
                    end
                end
            end

            if valid then
                out[#out + 1] = string.sub(s, i, i + extra)
                i = i + extra + 1
            else
                out[#out + 1] = string.format("\\u%04x", b)
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

local function escapeJson(text)
    local s = tostring(text)
    s = s:gsub('[%c\\"]', function(c)
        local mapped = ESCAPES[c]
        if mapped then return mapped end
        return string.format("\\u%04x", string.byte(c))
    end)
    if s:find("[\128-\255]") then
        s = escapeHighBytes(s)
    end
    return s
end

local encodeJson

local function encodeArray(value, out, depth)
    out[#out + 1] = "["
    local count = #value
    for i = 1, count do
        if i > 1 then out[#out + 1] = "," end
        encodeJson(value[i], out, depth + 1)
    end
    out[#out + 1] = "]"
end

local function encodeObject(value, out, depth)
    out[#out + 1] = "{"
    local first = true
    for key, item in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            if not first then out[#out + 1] = "," end
            first = false
            out[#out + 1] = '"'
            out[#out + 1] = escapeJson(key)
            out[#out + 1] = '":'
            encodeJson(item, out, depth + 1)
        end
    end
    out[#out + 1] = "}"
end

function encodeJson(value, out, depth)
    depth = depth or 0
    if depth > 32 then
        out[#out + 1] = '"<depth limit>"'
        return
    end

    local valueType = type(value)
    if value == nil then
        out[#out + 1] = "null"
    elseif valueType == "boolean" then
        out[#out + 1] = value and "true" or "false"
    elseif valueType == "number" then
        local n = safeNum(value)
        out[#out + 1] = n and tostring(n) or "null"
    elseif valueType == "string" then
        out[#out + 1] = '"'
        out[#out + 1] = escapeJson(value)
        out[#out + 1] = '"'
    elseif valueType == "table" then
        local isArray = true
        for key in pairs(value) do
            if type(key) ~= "number" then
                isArray = false
                break
            end
        end
        if isArray and #value > 0 then
            encodeArray(value, out, depth)
        elseif isArray and next(value) == nil then
            -- Ambiguous: empty tables are emitted as arrays, which is what
            -- every list field in this protocol wants.
            out[#out + 1] = "[]"
        else
            encodeObject(value, out, depth)
        end
    else
        out[#out + 1] = '"'
        out[#out + 1] = escapeJson(tostring(value))
        out[#out + 1] = '"'
    end
end

local function toJson(data)
    local out = {}
    local ok, err = pcall(encodeJson, data, out, 0)
    if not ok then
        return '{"status":"error","error":"encode_failed","detail":"' .. escapeJson(tostring(err)) .. '"}'
    end
    return table.concat(out)
end

local HttpService = game:GetService("HttpService")

local function fromJson(text)
    if type(text) ~= "string" or text == "" then return nil end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(text) end)
    if ok then return decoded end
    return nil
end

-- ---------------------------------------------------------------------------
-- value sanitising (properties, remote args, env dumps)
-- ---------------------------------------------------------------------------

local function vec3(value)
    if value == nil then return nil end
    local x = safeNum(safe(function() return value.X end))
    local y = safeNum(safe(function() return value.Y end))
    local z = safeNum(safe(function() return value.Z end))
    if x == nil and y == nil and z == nil then return nil end
    return { x = x or 0, y = y or 0, z = z or 0 }
end

function sanitizeValue(value, depth)
    depth = depth or 0
    local luauType = (typeof and typeof(value)) or type(value)

    if value == nil then return nil end
    if luauType == "string" then
        local text, truncated = trimString(cleanString(value), CONFIG.TRAFFIC_STRING_MAX * 4)
        if truncated then return text .. "..." end
        return text
    end
    if luauType == "number" then return safeNum(value) end
    if luauType == "boolean" then return value end

    if luauType == "Instance" then
        return { __instance = fullName(value), className = className(value) }
    end
    if luauType == "Vector3" or luauType == "Vector3int16" then
        return vec3(value)
    end
    if luauType == "Vector2" then
        return {
            x = safeNum(safe(function() return value.X end)) or 0,
            y = safeNum(safe(function() return value.Y end)) or 0,
        }
    end
    if luauType == "CFrame" then
        return { position = vec3(safe(function() return value.Position end)), lookVector = vec3(safe(function() return value.LookVector end)) }
    end
    if luauType == "Color3" then
        return {
            r = safeNum(safe(function() return value.R end)) or 0,
            g = safeNum(safe(function() return value.G end)) or 0,
            b = safeNum(safe(function() return value.B end)) or 0,
        }
    end
    if luauType == "UDim2" or luauType == "UDim" or luauType == "Rect"
        or luauType == "BrickColor" or luauType == "NumberRange"
        or luauType == "EnumItem" or luauType == "Enum" or luauType == "Enums"
        or luauType == "TweenInfo" or luauType == "Ray" or luauType == "Region3" then
        return safeStr(tostring(value))
    end
    if luauType == "function" then
        return "<function>"
    end
    if luauType == "thread" then
        return "<thread>"
    end

    if luauType == "table" then
        if depth >= CONFIG.TRAFFIC_DEPTH then return "<table>" end
        local out = {}
        local count = 0
        local isArray = #value > 0
        for key, item in pairs(value) do
            count = count + 1
            if count > 64 then
                out["__truncated"] = true
                break
            end
            local cleanedKey = (type(key) == "string" or type(key) == "number") and key or tostring(key)
            local cleaned = sanitizeValue(item, depth + 1)
            if cleaned ~= nil then out[cleanedKey] = cleaned end
        end
        if isArray then
            local list = {}
            for i = 1, math.min(#value, 64) do
                list[i] = sanitizeValue(value[i], depth + 1)
            end
            return list
        end
        return out
    end

    return safeStr(tostring(value))
end

-- ---------------------------------------------------------------------------
-- console capture
-- ---------------------------------------------------------------------------

local function formatArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    return cleanString(table.concat(parts, "\t"))
end

local function pushLog(level, message, source)
    message = cleanString(message)
    if message == nil or message == "" then return end

    local now = os.clock()
    local key = level .. "\0" .. message
    local seenAt = logDedupe[key]
    if seenAt and (now - seenAt) < CONFIG.LOG_DEDUPE_WINDOW then
        return
    end
    logDedupe[key] = now

    -- One entry per distinct message would grow without bound over a long
    -- session, so drop anything past the dedupe window.
    logDedupeCount = logDedupeCount + 1
    if logDedupeCount >= 500 then
        logDedupeCount = 0
        for seenKey, seenTime in pairs(logDedupe) do
            if (now - seenTime) > CONFIG.LOG_DEDUPE_WINDOW then
                logDedupe[seenKey] = nil
            end
        end
    end

    local entry = { t = os.time(), level = level, message = message, source = source }
    logBuffer[#logBuffer + 1] = entry
    logPending[#logPending + 1] = entry
    if #logBuffer > CONFIG.LOG_BUFFER_SIZE then
        table.remove(logBuffer, 1)
    end
end

local function pushCollector(level, message)
    message = cleanString(message)
    if message == nil or message == "" then return end
    if #activeCollectors == 0 then return end

    local entry = { t = os.time(), level = level, message = message, source = "exec" }
    for _, collector in ipairs(activeCollectors) do
        if #collector < 400 then
            collector[#collector + 1] = entry
        end
    end
end

genv.__MCP_PUSH_COLLECTOR = pushCollector
genv.__MCP_PUSH_LOG = pushLog

--- Wrap print/warn once, permanently. Restoring them would race with any
--- concurrent execution, which is exactly how the older bridge lost output.
local function installPrintHooks()
    if genv.__MCP_PRINT_WRAPPED then return end

    local function relay(level, ...)
        local message = formatArgs(...)
        if isOurThread() then
            local collect = genv.__MCP_PUSH_COLLECTOR
            if type(collect) == "function" then pcall(collect, level, message) end
        end
        if not genv.__MCP_LOGSERVICE_OK then
            local push = genv.__MCP_PUSH_LOG
            if type(push) == "function" then
                pcall(push, level, message, isOurThread() and "exec" or "game")
            end
        end
    end

    local wrappedPrint = function(...)
        relay("print", ...)
        return originalPrint(...)
    end
    local wrappedWarn = function(...)
        relay("warn", ...)
        return originalWarn(...)
    end

    -- A protected global table makes these assignments throw; capturing output
    -- is a nice-to-have, so never let it stop the bridge from booting.
    pcall(function()
        print = wrappedPrint
        warn = wrappedWarn
    end)
    if genv ~= _G then
        pcall(function()
            genv.print = wrappedPrint
            genv.warn = wrappedWarn
        end)
    end
    genv.__MCP_PRINT_WRAPPED = true
end

local MESSAGE_LEVELS = {
    [Enum.MessageType.MessageOutput] = "print",
    [Enum.MessageType.MessageInfo] = "info",
    [Enum.MessageType.MessageWarning] = "warn",
    [Enum.MessageType.MessageError] = "error",
}

local function installLogService()
    local ok, err = pcall(function()
        LogService.MessageOut:Connect(function(message, messageType)
            if not isCurrent() then return end
            pushLog(MESSAGE_LEVELS[messageType] or "print", message, "logservice")
        end)
    end)
    if ok then
        genv.__MCP_LOGSERVICE_OK = true
    else
        genv.__MCP_LOGSERVICE_OK = false
        bridgeWarn("LogService capture unavailable:", err)
    end
end

-- ---------------------------------------------------------------------------
-- instance path resolution
-- ---------------------------------------------------------------------------

local function splitPath(path)
    local parts = {}
    for part in tostring(path):gmatch("[^%.]+") do
        local cleaned = trim(part)
        if cleaned ~= "" then parts[#parts + 1] = cleaned end
    end
    return parts
end

local function findByFullName(path)
    local wanted = trim(path):lower()
    if wanted == "" then return nil end

    local pools = {}
    if type(getinstances) == "function" then
        pools[#pools + 1] = safe(getinstances) or {}
    end
    if type(getnilinstances) == "function" then
        pools[#pools + 1] = safe(getnilinstances) or {}
    end

    for _, pool in ipairs(pools) do
        for _, inst in ipairs(pool) do
            local name = fullName(inst)
            if name and name:lower() == wanted then
                return inst
            end
        end
    end
    return nil
end

local function getServiceByName(name)
    if name == "game" or name == "Game" or name == "DataModel" then return game end
    local svc = safe(function() return game:GetService(name) end)
    if svc then return svc end
    svc = safe(function() return game:FindFirstChild(name) end)
    if svc then return svc end
    if name == "Workspace" then return workspace end
    return nil
end

--- Resolve "ReplicatedStorage.Modules.Foo" / "Players.LocalPlayer.PlayerGui.X".
--- Falls back to a GetFullName() sweep, which also finds nil-parented objects.
local function resolveInstance(path)
    if type(path) ~= "string" then return nil, "invalid_path" end
    local cleaned = trim(path)
    if cleaned == "" then return nil, "empty_path" end
    if cleaned == "game" or cleaned == "Game" then return game end

    local normalized = cleaned:gsub("^[Gg]ame%.", "")
    local parts = splitPath(normalized)
    if #parts == 0 then return nil, "empty_path" end

    local current = getServiceByName(parts[1])
    if current then
        for i = 2, #parts do
            local part = parts[i]
            local nextInst = safe(function() return current:FindFirstChild(part) end)
            if not nextInst and part == "LocalPlayer" then
                nextInst = Players.LocalPlayer
            end
            if not nextInst then
                current = nil
                break
            end
            current = nextInst
        end
        if current then return current end
    end

    local found = findByFullName(cleaned)
    if found then return found end
    return nil, "instance_not_found"
end

-- ---------------------------------------------------------------------------
-- remote traffic hook (__namecall)
-- ---------------------------------------------------------------------------

local REMOTE_CLASSES = {
    RemoteEvent = true,
    RemoteFunction = true,
    BindableEvent = true,
    BindableFunction = true,
    UnreliableRemoteEvent = true,
}

local TRACKED_METHODS = {
    FireServer = true,
    fireServer = true,
    InvokeServer = true,
    invokeServer = true,
    Fire = true,
    Invoke = true,
}

local inHook = false

local function pushTraffic(entry)
    trafficBuffer[#trafficBuffer + 1] = entry
    trafficPending[#trafficPending + 1] = entry
    hookState.captured = hookState.captured + 1
    if #trafficBuffer > CONFIG.TRAFFIC_BUFFER_SIZE then
        table.remove(trafficBuffer, 1)
    end
end

local function recordCall(target, method, ...)
    local argCount = select("#", ...)
    local args = {}
    local previews = {}
    for i = 1, math.min(argCount, CONFIG.TRAFFIC_MAX_ARGS) do
        local value = select(i, ...)
        args[i] = sanitizeValue(value, 0)
        local preview = tostring(value)
        if #preview > CONFIG.TRAFFIC_STRING_MAX then
            preview = preview:sub(1, CONFIG.TRAFFIC_STRING_MAX) .. "..."
        end
        previews[i] = preview
    end

    pushTraffic({
        t = os.time(),
        clock = math.floor(os.clock() * 1000) / 1000,
        path = fullName(target),
        name = instName(target),
        className = className(target),
        method = method,
        argCount = argCount,
        args = args,
        argsPreview = table.concat(previews, ", "),
        fromExecutor = isOurThread(),
    })
end

-- The installed hook is shared across reruns, so it must reach the newest
-- generation's recorder rather than the closure it was created with.
genv.__MCP_RECORD_CALL = recordCall

local function installNamecallHook()
    if hookState.installed then return true end
    if type(hookmetamethod) ~= "function" then
        hookState.error = "hookmetamethod_unavailable"
        return false, hookState.error
    end

    local original
    local ok, err = pcall(function()
        local hook = function(self, ...)
            if hookState.enabled and not inHook then
                local method = type(getnamecallmethod) == "function" and getnamecallmethod() or nil
                if method and TRACKED_METHODS[method] then
                    inHook = true
                    local cls = className(self)
                    if cls and REMOTE_CLASSES[cls] then
                        local recorder = genv.__MCP_RECORD_CALL
                        if type(recorder) == "function" then
                            pcall(recorder, self, method, ...)
                        end
                    end
                    inHook = false
                end
            end
            return original(self, ...)
        end

        if type(newcclosure) == "function" then
            local wrapped = newcclosure(hook)
            original = hookmetamethod(game, "__namecall", wrapped)
        else
            original = hookmetamethod(game, "__namecall", hook)
        end
    end)

    if not ok or type(original) ~= "function" then
        hookState.error = tostring(err or "hook_returned_no_original")
        return false, hookState.error
    end

    hookState.installed = true
    hookState.error = nil
    return true
end

-- ---------------------------------------------------------------------------
-- capture: properties and trees
-- ---------------------------------------------------------------------------

local GUI_PROP_CLASSES = {
    Frame = true,
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ImageLabel = true,
    ImageButton = true,
    ScrollingFrame = true,
    ScreenGui = true,
    BillboardGui = true,
    SurfaceGui = true,
    CanvasGroup = true,
    VideoFrame = true,
}

local SCRIPT_CLASSES = {
    Script = true,
    LocalScript = true,
    ModuleScript = true,
}

local function captureProps(inst)
    local props = {}
    local cls = className(inst)
    if not cls then return props end

    if isA(inst, "BasePart") then
        props.size = vec3(safe(function() return inst.Size end))
        props.position = vec3(safe(function() return inst.Position end))
        props.transparency = safeNum(safe(function() return inst.Transparency end))
        props.canCollide = safe(function() return inst.CanCollide end)
        props.anchored = safe(function() return inst.Anchored end)
    elseif GUI_PROP_CLASSES[cls] or isA(inst, "GuiObject") then
        props.visible = safe(function() return inst.Visible end)
        props.absolutePosition = safe(function()
            local p = inst.AbsolutePosition
            return { x = safeNum(p.X) or 0, y = safeNum(p.Y) or 0 }
        end)
        props.absoluteSize = safe(function()
            local s = inst.AbsoluteSize
            return { x = safeNum(s.X) or 0, y = safeNum(s.Y) or 0 }
        end)
        props.text = safeStr(safe(function() return inst.Text end))
        props.image = safeStr(safe(function() return inst.Image end))
        props.active = safe(function() return inst.Active end)
        props.zIndex = safeNum(safe(function() return inst.ZIndex end))
    elseif SCRIPT_CLASSES[cls] then
        props.disabled = safe(function() return inst.Disabled end)
        props.enabled = safe(function() return inst.Enabled end)
    elseif cls == "Sound" then
        props.soundId = safeStr(safe(function() return inst.SoundId end))
        props.playing = safe(function() return inst.Playing end)
    elseif cls == "StringValue" or cls == "NumberValue" or cls == "BoolValue" or cls == "IntValue" then
        props.value = sanitizeValue(safe(function() return inst.Value end), 2)
    end

    return props
end

local nodeBudget = 0

function captureNode(inst, depth, maxDepth, maxChildren)
    if nodeBudget <= 0 then return nil end
    nodeBudget = nodeBudget - 1

    local node = {
        name = instName(inst),
        className = className(inst),
        path = fullName(inst),
        props = captureProps(inst),
        children = {},
    }

    if depth >= maxDepth then
        local childCount = #(safe(function() return inst:GetChildren() end) or {})
        if childCount > 0 then node.childCount = childCount end
        return node
    end

    local children = safe(function() return inst:GetChildren() end) or {}
    local limit = math.min(#children, maxChildren)
    if #children > limit then node.childrenTruncated = #children end

    for i = 1, limit do
        local child = captureNode(children[i], depth + 1, maxDepth, maxChildren)
        if child then node.children[#node.children + 1] = child end
        if nodeBudget <= 0 then break end
    end

    return node
end

local function captureTree(root, maxDepth, maxChildren, budget)
    if root == nil then return nil end
    nodeBudget = budget
    local tree = captureNode(root, 0, maxDepth, maxChildren)
    return { root = tree, nodeCount = budget - nodeBudget }
end

-- ---------------------------------------------------------------------------
-- capture: gui
-- ---------------------------------------------------------------------------

local function captureGui()
    local localPlayer = Players.LocalPlayer
    local result = {}

    local playerGui = localPlayer and safe(function() return localPlayer:FindFirstChildOfClass("PlayerGui") end)
    if playerGui then
        result.playerGui = captureTree(playerGui, CONFIG.MAX_GUI_DEPTH, CONFIG.MAX_TREE_CHILDREN, CONFIG.MAX_GUI_NODES)
    else
        result.playerGui = { error = "no_player_gui" }
    end

    if type(gethui) == "function" then
        local hidden = safe(gethui)
        if hidden then
            result.hiddenGui = captureTree(hidden, CONFIG.MAX_GUI_DEPTH, CONFIG.MAX_TREE_CHILDREN, 400)
        end
    end

    local inset = safe(function()
        local top, bottom = GuiService:GetGuiInset()
        return {
            top = { x = safeNum(top.X) or 0, y = safeNum(top.Y) or 0 },
            bottom = { x = safeNum(bottom.X) or 0, y = safeNum(bottom.Y) or 0 },
        }
    end)
    result.guiInset = inset

    return result
end

-- ---------------------------------------------------------------------------
-- capture: assets
-- ---------------------------------------------------------------------------

local ASSET_PROPS_BY_CLASS = {
    ImageLabel = { "Image" },
    ImageButton = { "Image", "HoverImage", "PressedImage" },
    Decal = { "Texture" },
    Texture = { "Texture" },
    Sound = { "SoundId" },
    MeshPart = { "MeshId", "TextureID" },
    SpecialMesh = { "MeshId", "TextureId" },
    ParticleEmitter = { "Texture" },
    Beam = { "Texture" },
    Trail = { "Texture" },
    Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" },
    Animation = { "AnimationId" },
    VideoFrame = { "Video" },
    ShirtGraphic = { "Graphic" },
    Shirt = { "ShirtTemplate" },
    Pants = { "PantsTemplate" },
    CharacterMesh = { "MeshId", "BaseTextureId", "OverlayTextureId" },
    SurfaceAppearance = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" },
}

local function normalizeAssetUri(raw)
    if raw == nil then return nil, nil end
    local s = tostring(raw)
    if s == "" then return nil, nil end
    local id = s:match("rbxassetid://(%d+)")
        or s:match("rbxasset://.-(%d+)")
        or s:match("[%?&]id=(%d+)")
    if not id or #id < 5 then return nil, nil end
    return "rbxassetid://" .. id, id
end

local function escapeLabel(text)
    return (tostring(text or ""):gsub("\\", "\\\\"):gsub('"', '\\"'))
end

local function assetDisplayName(inst, cls, propName)
    local name = instName(inst) or "Unknown"
    if cls == "TextLabel" or cls == "TextButton" then
        local text = safeStr(safe(function() return inst.Text end))
        if text and text ~= "" then return text end
    elseif propName == "Image" or propName == "Texture" or propName == "Graphic" then
        local parent = safe(function() return inst.Parent end)
        if parent then
            local sibling = safe(function()
                for _, child in ipairs(parent:GetChildren()) do
                    if child ~= inst and (child:IsA("TextLabel") or child:IsA("TextButton")) then
                        local text = child.Text
                        if text and text ~= "" then return text end
                    end
                end
                return nil
            end)
            if sibling and sibling ~= "" then return safeStr(sibling) end
        end
    end
    return name
end

local function collectAssets(inst, assets, seen)
    if #assets >= CONFIG.MAX_ASSETS then return end
    local cls = className(inst)
    if not cls then return end

    local propNames = ASSET_PROPS_BY_CLASS[cls]
    if not propNames then return end

    local path = fullName(inst)
    for _, propName in ipairs(propNames) do
        local raw = safe(function() return inst[propName] end)
        local uri, id = normalizeAssetUri(raw)
        if uri then
            local key = uri .. "|" .. propName .. "|" .. tostring(path)
            if not seen[key] then
                seen[key] = true
                local name = assetDisplayName(inst, cls, propName)
                assets[#assets + 1] = {
                    name = name,
                    property = propName,
                    assetId = id,
                    uri = uri,
                    path = path,
                    className = cls,
                    label = string.format('Name = "%s", %s = "%s"', escapeLabel(name), propName, uri),
                }
            end
        end
    end
end

local function collectAssetsFromSource(source, path, name, assets, seen)
    if type(source) ~= "string" or source == "" then return end
    for id in source:gmatch("rbxassetid://(%d+)") do
        local uri = "rbxassetid://" .. id
        local key = uri .. "|Source|" .. tostring(path)
        if not seen[key] and #assets < CONFIG.MAX_ASSETS then
            seen[key] = true
            assets[#assets + 1] = {
                name = name or "Script",
                property = "Source",
                assetId = id,
                uri = uri,
                path = path,
                className = "ScriptReference",
                label = string.format('Name = "%s", Source = "%s"', escapeLabel(name or "Script"), uri),
            }
        end
    end
end

-- ---------------------------------------------------------------------------
-- capture: scripts
-- ---------------------------------------------------------------------------

-- The decompiler reports failure in-band, as a comment in the returned string.
-- Treating that as source would hand the model a useless one-line "script".
local DECOMPILE_FAILURE_MARKERS = {
    "^%s*%-%-%s*Failed to decompile",
    "^%s*%-%-%s*Decompilation failed",
    "^%s*%-%-%s*decompiler",
}

local function isDecompileFailure(text)
    if type(text) ~= "string" or #text == 0 then return true end

    for _, pattern in ipairs(DECOMPILE_FAILURE_MARKERS) do
        if text:match(pattern) then return true end
    end

    -- Any real script has at least one line that is not a comment.
    for line in text:gmatch("[^\r\n]+") do
        local stripped = line:match("^%s*(.-)%s*$")
        if stripped ~= "" and not stripped:find("^%-%-") then
            return false
        end
    end
    return true
end

-- Captured before a remote decompiler can overwrite the global.
local decompilerState = {
    native = type(decompile) == "function" and decompile or nil,
    remote = nil,
    remoteTried = false,
    remoteError = nil,
    remoteName = nil,
}

local function httpGetText(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 0 then return body end

    if type(httpget) == "function" then
        ok, body = pcall(httpget, url)
        if ok and type(body) == "string" and #body > 0 then return body end
    end

    if type(request) == "function" then
        local reqOk, response = pcall(request, { Url = url, Method = "GET" })
        if reqOk and type(response) == "table" and type(response.Body) == "string" and #response.Body > 0 then
            return response.Body
        end
    end

    return nil, "http_failed"
end

--- Fetch and run Konstant once, then keep whatever decompiler it installs.
local function loadRemoteDecompiler()
    if decompilerState.remoteTried then return decompilerState.remote end
    decompilerState.remoteTried = true

    if not CONFIG.ALLOW_REMOTE_DECOMPILER then
        decompilerState.remoteError = "disabled_in_config"
        return nil
    end
    if type(getscriptbytecode) ~= "function" then
        decompilerState.remoteError = "getscriptbytecode_unavailable"
        return nil
    end

    local body, httpErr = httpGetText(CONFIG.REMOTE_DECOMPILER_URL)
    if not body then
        decompilerState.remoteError = httpErr or "http_failed"
        return nil
    end

    local loadFn = loadstring or load
    if type(loadFn) ~= "function" then
        decompilerState.remoteError = "loadstring_unavailable"
        return nil
    end

    local chunk, compileErr = loadFn(body, "=konstant")
    if not chunk then
        decompilerState.remoteError = "compile_failed: " .. tostring(compileErr)
        return nil
    end

    local ok, result = pcall(chunk)
    if not ok then
        decompilerState.remoteError = "run_failed: " .. tostring(result)
        return nil
    end

    -- Konstant either returns the function or installs a global.
    local candidate = nil
    if type(result) == "function" then
        candidate = result
    elseif type(result) == "table" then
        candidate = result.decompile or result.Decompile
    end
    if type(candidate) ~= "function" then
        local installed = rawget(genv, "decompile")
        if type(installed) == "function" and installed ~= decompilerState.native then
            candidate = installed
        elseif type(decompile) == "function" and decompile ~= decompilerState.native then
            candidate = decompile
        end
    end

    if type(candidate) ~= "function" then
        decompilerState.remoteError = "no_decompile_function_after_load"
        return nil
    end

    decompilerState.remote = candidate
    decompilerState.remoteName = "konstant"
    bridgePrint("remote decompiler loaded (konstant)")
    return candidate
end

--- The client never receives bytecode for server-side scripts, so trying to
--- decompile them only burns a request and returns a failure comment.
local function isViableDecompileScript(inst)
    if isA(inst, "ModuleScript") then return true end

    local runContext = safe(function() return inst.RunContext end)
    local clientContext = safe(function() return Enum.RunContext.Client end)
    local legacyContext = safe(function() return Enum.RunContext.Legacy end)

    if isA(inst, "LocalScript") then
        if runContext == nil then return true end
        return runContext == clientContext or runContext == legacyContext
    end
    if isA(inst, "Script") then
        return runContext ~= nil and runContext == clientContext
    end
    return false
end

--- Konstant only, unless CONFIG.USE_NATIVE_DECOMPILER re-enables the built-in
--- one. Returns source, method, error.
local function runDecompilers(inst)
    local attempts = {}

    if not CONFIG.USE_NATIVE_DECOMPILER then
        attempts[#attempts + 1] = "native:skipped_by_config"
    elseif decompilerState.native then
        local ok, result = pcall(decompilerState.native, inst)
        if ok and not isDecompileFailure(result) then
            return result, "decompiled:native"
        end
        attempts[#attempts + 1] = "native:" .. (ok and "unusable_output" or tostring(result))
    else
        attempts[#attempts + 1] = "native:unavailable"
    end

    local remote = loadRemoteDecompiler()
    if remote then
        local ok, result = pcall(remote, inst)
        if ok and not isDecompileFailure(result) then
            return result, "decompiled:" .. (decompilerState.remoteName or "remote")
        end
        attempts[#attempts + 1] = "remote:" .. (ok and "unusable_output" or tostring(result))
    else
        attempts[#attempts + 1] = "remote:" .. tostring(decompilerState.remoteError)
    end

    return nil, "none", table.concat(attempts, " | ")
end

local function readSource(inst, allowDecompile)
    local source = safe(function() return inst.Source end)
    if type(source) == "string" and #source > 0 then
        return source, "source"
    end

    if not allowDecompile then
        return nil, "none", "source_empty"
    end
    if not isViableDecompileScript(inst) then
        return nil, "none", "server_script_not_decompilable"
    end

    return runDecompilers(inst)
end

local function serviceOfInstance(inst)
    local current = inst
    for _ = 1, 64 do
        local parent = safe(function() return current.Parent end)
        if parent == nil then
            return "nil-parented", false
        end
        if parent == game then
            return instName(current) or "unknown", true
        end
        current = parent
    end
    return "unknown", false
end

-- ---------------------------------------------------------------------------
-- full scan
-- ---------------------------------------------------------------------------

local ALWAYS_INDEX_SERVICES = {
    ReplicatedStorage = true,
    ReplicatedFirst = true,
    Players = true,
    Lighting = true,
    Teams = true,
    SoundService = true,
    StarterGui = true,
    StarterPack = true,
    MaterialService = true,
    ["nil-parented"] = true,
}

local INDEX_CLASSES = {
    Folder = true,
    Model = true,
    Configuration = true,
    Tool = true,
    Humanoid = true,
    Animation = true,
    Sound = true,
    Team = true,
    ProximityPrompt = true,
    ClickDetector = true,
    Attachment = false,
    StringValue = true,
    NumberValue = true,
    BoolValue = true,
    IntValue = true,
    ObjectValue = true,
    CFrameValue = true,
    Vector3Value = true,
    ScreenGui = true,
    Frame = true,
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ImageLabel = true,
    ImageButton = true,
    ScrollingFrame = true,
    BillboardGui = true,
    SurfaceGui = true,
    ProximityPromptService = true,
    SpawnLocation = true,
}

local SKIP_PATH_HINTS = {
    "HumanoidDescription",
    "BodyPartDescription",
}

local function shouldIndex(cls, service, parented, path)
    if SCRIPT_CLASSES[cls] or REMOTE_CLASSES[cls] then return true end
    if INDEX_CLASSES[cls] then return true end
    if ALWAYS_INDEX_SERVICES[service] then
        if path then
            for _, hint in ipairs(SKIP_PATH_HINTS) do
                if path:find(hint, 1, true) then return false end
            end
        end
        return true
    end
    return false
end

local SERVICE_TREE_NAMES = {
    "Workspace",
    "ReplicatedStorage",
    "ReplicatedFirst",
    "Lighting",
    "Teams",
    "SoundService",
    "StarterGui",
    "StarterPack",
}

local function captureServiceTrees()
    local trees = {}

    for _, name in ipairs(SERVICE_TREE_NAMES) do
        local svc = getServiceByName(name)
        if svc then
            trees[name] = captureTree(svc, CONFIG.MAX_TREE_DEPTH, CONFIG.MAX_TREE_CHILDREN, CONFIG.MAX_TREE_NODES)
        end
    end

    local localPlayer = Players.LocalPlayer
    if localPlayer then
        trees["Players.LocalPlayer"] = captureTree(localPlayer, 3, CONFIG.MAX_TREE_CHILDREN, 300)
        for _, childName in ipairs({ "PlayerScripts", "PlayerGui", "Backpack" }) do
            local child = safe(function() return localPlayer:FindFirstChild(childName) end)
            if child then
                trees["Players.LocalPlayer." .. childName] =
                    captureTree(child, CONFIG.MAX_TREE_DEPTH, CONFIG.MAX_TREE_CHILDREN, 400)
            end
        end
        local character = safe(function() return localPlayer.Character end)
        if character then
            trees["Players.LocalPlayer.Character"] = captureTree(character, 2, CONFIG.MAX_TREE_CHILDREN, 200)
        end
    end

    return trees
end

local function buildScriptEntries()
    local entries = {}
    local byInstance = {}
    local running = {}

    if type(getrunningscripts) == "function" then
        for _, scr in ipairs(safe(getrunningscripts) or {}) do
            running[scr] = true
        end
    end

    local function add(inst, isLoadedModule)
        if inst == nil or byInstance[inst] then return end
        if #entries >= CONFIG.MAX_SCRIPTS then return end
        local cls = className(inst)
        if not cls or not SCRIPT_CLASSES[cls] then return end

        byInstance[inst] = true
        local service, parented = serviceOfInstance(inst)
        local entry = {
            service = service,
            parented = parented,
            path = fullName(inst),
            name = instName(inst),
            className = cls,
            running = running[inst] == true,
            loadedModule = isLoadedModule == true,
            hasSource = false,
            sourceLength = 0,
        }

        local source, method = readSource(inst, false)
        if source then
            entry.hasSource = true
            entry.sourceMethod = method
            entry.sourceLength = #source
            local preview, truncated = trimString(source, CONFIG.SCAN_SOURCE_PREVIEW)
            entry.sourcePreview = preview
            entry.sourceTruncated = truncated
        end

        entries[#entries + 1] = entry
    end

    if type(getscripts) == "function" then
        for _, inst in ipairs(safe(getscripts) or {}) do
            add(inst, false)
        end
    end
    if type(getloadedmodules) == "function" then
        for _, inst in ipairs(safe(getloadedmodules) or {}) do
            add(inst, true)
        end
    end

    return entries
end

--- One pass over getinstances() feeding the index, remote list and asset list.
local function scanInstances()
    local index = {}
    local remotes = {}
    local assets = {}
    local assetSeen = {}
    local classCounts = {}
    local serviceCounts = {}
    local processed = 0
    local truncated = false

    local pools = {}
    if type(getinstances) == "function" then
        pools[#pools + 1] = safe(getinstances) or {}
    else
        pools[#pools + 1] = safe(function() return game:GetDescendants() end) or {}
    end
    if type(getnilinstances) == "function" then
        pools[#pools + 1] = safe(getnilinstances) or {}
    end

    for _, pool in ipairs(pools) do
        for _, inst in ipairs(pool) do
            processed = processed + 1
            if processed > CONFIG.MAX_SCAN_INSTANCES then
                truncated = true
                break
            end
            if processed % CONFIG.SCAN_YIELD_EVERY == 0 then
                task.wait()
                if not isCurrent() then return nil end
            end

            local cls = className(inst)
            if cls then
                classCounts[cls] = (classCounts[cls] or 0) + 1

                local service, parented = serviceOfInstance(inst)
                local path = fullName(inst)

                if REMOTE_CLASSES[cls] and #remotes < CONFIG.MAX_REMOTES then
                    remotes[#remotes + 1] = {
                        service = service,
                        parented = parented,
                        path = path,
                        name = instName(inst),
                        className = cls,
                    }
                end

                if #index < CONFIG.MAX_INDEX and shouldIndex(cls, service, parented, path) then
                    index[#index + 1] = {
                        service = service,
                        path = path,
                        name = instName(inst),
                        className = cls,
                    }
                    serviceCounts[service] = (serviceCounts[service] or 0) + 1
                end

                collectAssets(inst, assets, assetSeen)
            end
        end
        if truncated then break end
    end

    return {
        index = index,
        remotes = remotes,
        assets = assets,
        assetSeen = assetSeen,
        classCounts = classCounts,
        serviceCounts = serviceCounts,
        processed = processed,
        truncated = truncated,
    }
end

function runFullScan()
    if scanInProgress then
        return explorerCache, "already_running"
    end
    scanInProgress = true

    local started = os.clock()
    local ok, result = pcall(function()
        local scanned = scanInstances()
        if scanned == nil then return nil end

        local scripts = buildScriptEntries()
        for _, entry in ipairs(scripts) do
            collectAssetsFromSource(entry.sourcePreview, entry.path, entry.name, scanned.assets, scanned.assetSeen)
        end

        table.sort(scanned.assets, function(a, b)
            local an, bn = tostring(a.name or ""):lower(), tostring(b.name or ""):lower()
            if an == bn then return tostring(a.uri or "") < tostring(b.uri or "") end
            return an < bn
        end)

        local explorer = {
            schema = "roblox-potassium-bridge/explorer/3",
            capturedAt = os.time(),
            durationSeconds = math.floor((os.clock() - started) * 100) / 100,
            index = scanned.index,
            scripts = scripts,
            remotes = scanned.remotes,
            assets = scanned.assets,
            services = captureServiceTrees(),
            gui = captureGui(),
            classCounts = scanned.classCounts,
            serviceCounts = scanned.serviceCounts,
            counts = {
                index = #scanned.index,
                scripts = #scripts,
                remotes = #scanned.remotes,
                assets = #scanned.assets,
                instancesProcessed = scanned.processed,
            },
            limits = {
                instancesTruncated = scanned.truncated,
                maxScanInstances = CONFIG.MAX_SCAN_INSTANCES,
                maxIndex = CONFIG.MAX_INDEX,
                maxAssets = CONFIG.MAX_ASSETS,
            },
            unavailableServices = {
                "ServerStorage",
                "ServerScriptService",
                "StarterPlayer.StarterPlayerScripts",
            },
        }
        return explorer
    end)

    scanInProgress = false

    if not ok then
        bridgeWarn("scan failed:", result)
        return explorerCache, tostring(result)
    end
    if result == nil then
        return explorerCache, "superseded"
    end

    explorerCache = result
    explorerCapturedAt = os.clock()
    return result, nil
end

-- ---------------------------------------------------------------------------
-- capture: players and character
-- ---------------------------------------------------------------------------

local function capturePlayers()
    local localPlayer = Players.LocalPlayer
    local list = {}
    for _, plr in ipairs(safe(function() return Players:GetPlayers() end) or {}) do
        local char = safe(function() return plr.Character end)
        local hrp = char and safe(function() return char:FindFirstChild("HumanoidRootPart") end)
        local hum = char and safe(function() return char:FindFirstChildOfClass("Humanoid") end)
        list[#list + 1] = {
            name = instName(plr),
            userId = safeNum(safe(function() return plr.UserId end)),
            team = safeStr(safe(function() return plr.Team and plr.Team.Name end)),
            health = hum and safeNum(safe(function() return hum.Health end)) or nil,
            maxHealth = hum and safeNum(safe(function() return hum.MaxHealth end)) or nil,
            isLocal = plr == localPlayer,
            position = hrp and vec3(safe(function() return hrp.Position end)) or nil,
        }
    end
    return list
end

local function captureAttributes(inst)
    local attrs = {}
    local raw = safe(function() return inst:GetAttributes() end)
    if type(raw) == "table" then
        for key, value in pairs(raw) do
            attrs[tostring(key)] = sanitizeValue(value, 1)
        end
    end
    return attrs
end

local function partSummary(part)
    if not isA(part, "BasePart") then return nil end
    return {
        name = instName(part),
        className = className(part),
        path = fullName(part),
        position = vec3(safe(function() return part.Position end)),
        velocity = vec3(safe(function() return part.AssemblyLinearVelocity end)),
        size = vec3(safe(function() return part.Size end)),
        canCollide = safe(function() return part.CanCollide end),
        attributes = captureAttributes(part),
    }
end

local function isBallLike(name)
    return name ~= nil and tostring(name):find("[Bb]all") ~= nil
end

local function characterChild(inst)
    local name = instName(inst)
    local entry = {
        name = name,
        className = className(inst),
        path = fullName(inst),
        ballLike = isBallLike(name),
    }

    if isA(inst, "BasePart") then
        entry.position = vec3(safe(function() return inst.Position end))
        entry.velocity = vec3(safe(function() return inst.AssemblyLinearVelocity end))
        entry.size = vec3(safe(function() return inst.Size end))
        entry.canCollide = safe(function() return inst.CanCollide end)
    elseif isA(inst, "Tool") then
        entry.tool = true
        local handle = safe(function() return inst:FindFirstChild("Handle") end)
        if handle then entry.handle = partSummary(handle) end
    end

    local attrs = captureAttributes(inst)
    if next(attrs) then entry.attributes = attrs end
    return entry
end

local function humanoidState(hum)
    local state = safe(function() return hum:GetState() end)
    if state == nil then return nil end
    local text = tostring(state)
    return text:match("%.([^%.]+)$") or text
end

local function captureCharacterState(plr, referenceHrp)
    if plr == nil then return { error = "no_player" } end

    local char = safe(function() return plr.Character end)
    if char == nil then
        return {
            name = instName(plr),
            userId = safeNum(safe(function() return plr.UserId end)),
            team = safeStr(safe(function() return plr.Team and plr.Team.Name end)),
            hasCharacter = false,
        }
    end

    local hrp = safe(function() return char:FindFirstChild("HumanoidRootPart") end)
    local hum = safe(function() return char:FindFirstChildOfClass("Humanoid") end)
    local head = safe(function() return char:FindFirstChild("Head") end)

    local children = {}
    local ballLikeChildren = {}
    for i, child in ipairs(safe(function() return char:GetChildren() end) or {}) do
        if i > CONFIG.MAX_CHARACTER_CHILDREN then break end
        local entry = characterChild(child)
        children[#children + 1] = entry
        if entry.ballLike then ballLikeChildren[#ballLikeChildren + 1] = entry end
    end

    local ballDescendants = {}
    for _, inst in ipairs(safe(function() return char:GetDescendants() end) or {}) do
        if #ballDescendants >= CONFIG.MAX_BALL_DESCENDANTS then break end
        if isA(inst, "BasePart") and isBallLike(instName(inst)) then
            ballDescendants[#ballDescendants + 1] = partSummary(inst)
        end
    end

    local hrpPos = hrp and vec3(safe(function() return hrp.Position end)) or nil
    local distance = nil
    if referenceHrp and hrpPos then
        local refPos = vec3(safe(function() return referenceHrp.Position end))
        if refPos then
            local dx, dy, dz = hrpPos.x - refPos.x, hrpPos.y - refPos.y, hrpPos.z - refPos.z
            distance = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) * 100) / 100
        end
    end

    return {
        name = instName(plr),
        userId = safeNum(safe(function() return plr.UserId end)),
        team = safeStr(safe(function() return plr.Team and plr.Team.Name end)),
        teamColor = safeStr(safe(function() return tostring(plr.TeamColor) end)),
        hasCharacter = true,
        humanoidRootPart = hrp and partSummary(hrp) or nil,
        head = head and partSummary(head) or nil,
        humanoid = hum and {
            health = safeNum(safe(function() return hum.Health end)),
            maxHealth = safeNum(safe(function() return hum.MaxHealth end)),
            state = humanoidState(hum),
            walkSpeed = safeNum(safe(function() return hum.WalkSpeed end)),
            jumpPower = safeNum(safe(function() return hum.JumpPower end)),
            jumpHeight = safeNum(safe(function() return hum.JumpHeight end)),
            moveDirection = vec3(safe(function() return hum.MoveDirection end)),
            sit = safe(function() return hum.Sit end),
            platformStand = safe(function() return hum.PlatformStand end),
        } or nil,
        attributes = captureAttributes(char),
        children = children,
        ballLikeChildren = ballLikeChildren,
        ballDescendants = ballDescendants,
        distanceFromLocalHrp = distance,
    }
end

-- ---------------------------------------------------------------------------
-- snapshot
-- ---------------------------------------------------------------------------

local function buildSnapshot()
    local localPlayer = Players.LocalPlayer
    local camera = safe(function() return workspace.CurrentCamera end)

    return {
        schema = "roblox-potassium-bridge/snapshot/3",
        meta = {
            timestamp = os.time(),
            loopTick = loopTick,
            bridgeVersion = BRIDGE_VERSION,
            scanInProgress = scanInProgress,
            explorerAgeSeconds = explorerCache and math.floor((os.clock() - explorerCapturedAt) * 10) / 10 or nil,
        },
        place = {
            name = safeStr(safe(function() return game.Name end)),
            placeId = safeNum(safe(function() return game.PlaceId end)),
            gameId = safeNum(safe(function() return game.GameId end)),
            jobId = safeStr(safe(function() return game.JobId end)),
            loaded = safe(function() return game:IsLoaded() end),
        },
        localPlayer = localPlayer and {
            name = instName(localPlayer),
            userId = safeNum(safe(function() return localPlayer.UserId end)),
            team = safeStr(safe(function() return localPlayer.Team and localPlayer.Team.Name end)),
        } or nil,
        players = capturePlayers(),
        camera = camera and {
            fov = safeNum(safe(function() return camera.FieldOfView end)),
            position = vec3(safe(function() return camera.CFrame.Position end)),
            lookVector = vec3(safe(function() return camera.CFrame.LookVector end)),
        } or nil,
        counts = explorerCache and explorerCache.counts or nil,
        hookState = {
            installed = hookState.installed,
            enabled = hookState.enabled,
            captured = hookState.captured,
            error = hookState.error,
        },
    }
end

-- ---------------------------------------------------------------------------
-- op handlers
-- ---------------------------------------------------------------------------

local function decodeArg(value)
    if type(value) ~= "table" then return value end
    if value.__instance then
        return (resolveInstance(value.__instance))
    end
    if value.__vector3 then
        local v = value.__vector3
        return Vector3.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
    end
    if value.__cframe then
        local v = value.__cframe
        return CFrame.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
    end
    if value.__color3 then
        local v = value.__color3
        return Color3.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
    end
    if value.__enum then
        local parts = splitPath(value.__enum)
        if #parts >= 2 then
            local ok, result = pcall(function() return Enum[parts[1]][parts[2]] end)
            if ok then return result end
        end
        return value.__enum
    end

    local out = {}
    for key, item in pairs(value) do
        out[key] = decodeArg(item)
    end
    return out
end

local function runLua(source, collector)
    local loadFn = loadstring or load
    if type(loadFn) ~= "function" then
        return false, "loadstring_unavailable"
    end

    local chunk, compileErr = loadFn(source, "=mcp_exec")
    if not chunk then
        return false, tostring(compileErr or "compile_failed")
    end

    activeCollectors[#activeCollectors + 1] = collector
    local ok, result = pcall(chunk)
    for i = #activeCollectors, 1, -1 do
        if activeCollectors[i] == collector then
            table.remove(activeCollectors, i)
            break
        end
    end

    if not ok then
        return false, tostring(result)
    end
    return true, nil, result
end

local ops = {}

ops.exec = function(params)
    local source = params.source
    if type(source) ~= "string" then
        return { status = "error", error = "invalid_source" }
    end
    if #source > CONFIG.EXEC_MAX_SOURCE then
        return { status = "error", error = "source_too_large", limit = CONFIG.EXEC_MAX_SOURCE }
    end

    if params.mode == "spawn" then
        task.spawn(function()
            local collector = {}
            local ok, err = runLua(source, collector)
            if not ok then bridgeWarn("spawned exec error:", err) end
        end)
        return { status = "ok", mode = "spawn", logs = {}, note = "Spawned. Read output with roblox_get_console_log." }
    end

    local collector = {}
    local ok, err, result = runLua(source, collector)
    if not ok then
        local message = trimString(err, CONFIG.EXEC_MAX_OUTPUT)
        return { status = "error", error = message, logs = collector }
    end

    local encoded = toJson(sanitizeValue(result, 0))
    local body, truncated = trimString(encoded, CONFIG.EXEC_MAX_OUTPUT)
    return {
        status = "ok",
        mode = "exec",
        logs = collector,
        returnValue = sanitizeValue(result, 0),
        returnValueJson = body,
        returnValueTruncated = truncated,
    }
end

ops.decompile = function(params)
    local inst, err = resolveInstance(params.path)
    if not inst then
        return { status = "error", error = err or "instance_not_found", path = params.path }
    end
    if not SCRIPT_CLASSES[className(inst) or ""] then
        return { status = "error", error = "not_a_script", path = fullName(inst), className = className(inst) }
    end

    local source, method, failure = readSource(inst, params.decompile ~= false)
    if not source then
        return {
            status = "error",
            error = failure or "no_source",
            path = fullName(inst),
            className = className(inst),
            decompilers = {
                native = decompilerState.native ~= nil,
                remote = decompilerState.remote ~= nil,
                remoteName = decompilerState.remoteName,
                remoteError = decompilerState.remoteError,
            },
        }
    end

    local total = #source
    local offset = math.max(0, tonumber(params.offset) or 0)
    local limit = math.min(tonumber(params.limit) or 60000, CONFIG.SOURCE_CHUNK_MAX)
    local slice = source:sub(offset + 1, offset + limit)

    return {
        status = "ok",
        path = fullName(inst),
        name = instName(inst),
        className = className(inst),
        sourceMethod = method,
        sourceLength = total,
        offset = offset,
        returned = #slice,
        hasMore = (offset + #slice) < total,
        nextOffset = (offset + #slice) < total and (offset + #slice) or nil,
        source = slice,
    }
end

ops.rescan = function()
    local explorer, err = runFullScan()
    if not explorer then
        return { status = "error", error = err or "scan_failed" }
    end
    sendMessage({ type = "explorer", data = explorer })
    return { status = "ok", counts = explorer.counts, durationSeconds = explorer.durationSeconds, error = err }
end

ops.asset_scan = function()
    local explorer, err = runFullScan()
    if not explorer then
        return { status = "error", error = err or "scan_failed" }
    end
    sendMessage({ type = "explorer", data = explorer })
    return { status = "ok", count = #explorer.assets }
end

ops.character_state = function(params)
    local localPlayer = Players.LocalPlayer
    if not localPlayer then
        return { status = "error", error = "no_local_player" }
    end

    local response = {
        status = "ok",
        timestamp = os.time(),
        localPlayer = captureCharacterState(localPlayer, nil),
    }

    local targetName = params.player
    if type(targetName) == "string" and trim(targetName) ~= "" then
        local wanted = trim(targetName):lower()
        local target = nil
        for _, plr in ipairs(safe(function() return Players:GetPlayers() end) or {}) do
            if (instName(plr) or ""):lower() == wanted then
                target = plr
                break
            end
        end

        if target then
            local char = safe(function() return localPlayer.Character end)
            local localHrp = char and safe(function() return char:FindFirstChild("HumanoidRootPart") end)
            response.targetPlayer = captureCharacterState(target, localHrp)
            response.targetName = instName(target)
        else
            response.targetError = "player_not_found"
            response.targetName = trim(targetName)
        end
    end

    return response
end

ops.fire_remote = function(params)
    local inst, err = resolveInstance(params.path)
    if not inst then
        return { status = "error", error = err or "instance_not_found", path = params.path }
    end

    local cls = className(inst)
    if not REMOTE_CLASSES[cls or ""] then
        return { status = "error", error = "not_a_remote", className = cls, path = fullName(inst) }
    end

    local method = params.method
    if type(method) ~= "string" or method == "" then
        if cls == "RemoteFunction" then
            method = "InvokeServer"
        elseif cls == "BindableFunction" then
            method = "Invoke"
        elseif cls == "BindableEvent" then
            method = "Fire"
        else
            method = "FireServer"
        end
    end

    local decoded = {}
    local argCount = 0
    if type(params.args) == "table" then
        argCount = #params.args
        for i = 1, argCount do
            decoded[i] = decodeArg(params.args[i])
        end
    end

    local ok, result = pcall(function()
        return inst[method](inst, table.unpack(decoded, 1, argCount))
    end)

    if not ok then
        return { status = "error", error = tostring(result), path = fullName(inst), method = method }
    end

    return {
        status = "ok",
        path = fullName(inst),
        className = cls,
        method = method,
        argCount = argCount,
        returnValue = sanitizeValue(result, 0),
    }
end

local CLICK_SIGNALS = {
    "MouseButton1Click",
    "Activated",
    "MouseButton1Down",
    "MouseButton1Up",
}

ops.click_gui = function(params)
    local inst, err = resolveInstance(params.path)
    if not inst then
        return { status = "error", error = err or "instance_not_found", path = params.path }
    end
    if not isA(inst, "GuiObject") then
        return { status = "error", error = "not_a_gui_object", className = className(inst), path = fullName(inst) }
    end

    local method = params.method or "signal"
    local fired = {}

    if method == "mouse" then
        if type(mousemoveabs) ~= "function" or type(mouse1click) ~= "function" then
            return { status = "error", error = "mouse_api_unavailable" }
        end

        local ok, detail = pcall(function()
            local pos = inst.AbsolutePosition
            local size = inst.AbsoluteSize
            local insetTop = GuiService:GetGuiInset()
            -- AbsolutePosition excludes the topbar inset; the OS cursor does not.
            local cx = pos.X + size.X / 2
            local cy = pos.Y + size.Y / 2 + insetTop.Y
            mousemoveabs(math.floor(cx), math.floor(cy))
            task.wait(0.05)
            mouse1click()
            return { x = math.floor(cx), y = math.floor(cy) }
        end)

        if not ok then
            return { status = "error", error = tostring(detail) }
        end
        return {
            status = "ok",
            method = "mouse",
            path = fullName(inst),
            cursor = detail,
            note = "Requires the Roblox window to be focused.",
        }
    end

    for _, signalName in ipairs(CLICK_SIGNALS) do
        local signal = safe(function() return inst[signalName] end)
        if signal then
            if method == "connections" and type(getconnections) == "function" then
                local connections = safe(getconnections, signal) or {}
                local count = 0
                for _, connection in ipairs(connections) do
                    local ok = pcall(function() connection:Fire() end)
                    if ok then count = count + 1 end
                end
                if count > 0 then fired[#fired + 1] = signalName .. " x" .. count end
            elseif type(firesignal) == "function" then
                local ok = pcall(firesignal, signal)
                if ok then fired[#fired + 1] = signalName end
            end
        end
    end

    if #fired == 0 then
        return {
            status = "error",
            error = "no_signal_fired",
            path = fullName(inst),
            hint = "Try method=\"connections\" or method=\"mouse\".",
        }
    end

    return { status = "ok", method = method, path = fullName(inst), fired = fired }
end

ops.get_props = function(params)
    local inst, err = resolveInstance(params.path)
    if not inst then
        return { status = "error", error = err or "instance_not_found", path = params.path }
    end

    local props = {}
    local hidden = {}

    if type(getproperties) == "function" then
        local raw = safe(getproperties, inst)
        if type(raw) == "table" then
            for key, value in pairs(raw) do
                props[tostring(key)] = sanitizeValue(value, 1)
            end
        end
    end
    if next(props) == nil then
        props = captureProps(inst)
        props.__note = "getproperties unavailable; returning the curated subset."
    end

    if params.hidden == true and type(gethiddenproperties) == "function" then
        local raw = safe(gethiddenproperties, inst)
        if type(raw) == "table" then
            for key, value in pairs(raw) do
                hidden[tostring(key)] = sanitizeValue(value, 1)
            end
        end
    end

    return {
        status = "ok",
        path = fullName(inst),
        name = instName(inst),
        className = className(inst),
        attributes = captureAttributes(inst),
        properties = props,
        hiddenProperties = next(hidden) ~= nil and hidden or nil,
    }
end

ops.script_env = function(params)
    if type(getsenv) ~= "function" then
        return { status = "error", error = "getsenv_unavailable" }
    end

    local inst, err = resolveInstance(params.path)
    if not inst then
        return { status = "error", error = err or "instance_not_found", path = params.path }
    end

    local ok, env = pcall(getsenv, inst)
    if not ok or type(env) ~= "table" then
        return {
            status = "error",
            error = "getsenv_failed",
            detail = not ok and tostring(env) or "script is probably not running",
            path = fullName(inst),
        }
    end

    local limit = math.max(1, tonumber(params.limit) or 120)
    local keys = {}
    local count = 0
    local total = 0

    for key, value in pairs(env) do
        total = total + 1
        if count < limit then
            count = count + 1
            local valueType = (typeof and typeof(value)) or type(value)
            local preview = trimString(tostring(value), 160)
            keys[#keys + 1] = {
                key = tostring(key),
                type = valueType,
                preview = preview,
                value = (valueType ~= "function" and valueType ~= "thread") and sanitizeValue(value, 2) or nil,
            }
        end
    end

    table.sort(keys, function(a, b) return a.key < b.key end)

    return {
        status = "ok",
        path = fullName(inst),
        className = className(inst),
        totalKeys = total,
        returned = #keys,
        env = keys,
    }
end

ops.loaded_modules = function(params)
    if type(getloadedmodules) ~= "function" then
        return { status = "error", error = "getloadedmodules_unavailable" }
    end

    local query = type(params.query) == "string" and trim(params.query):lower() or ""
    local limit = math.max(1, tonumber(params.limit) or 200)
    local modules = {}
    local total = 0

    for _, inst in ipairs(safe(getloadedmodules) or {}) do
        local path = fullName(inst) or ""
        local name = instName(inst) or ""
        if query == "" or path:lower():find(query, 1, true) or name:lower():find(query, 1, true) then
            total = total + 1
            if #modules < limit then
                local service, parented = serviceOfInstance(inst)
                modules[#modules + 1] = {
                    path = path,
                    name = name,
                    className = className(inst),
                    service = service,
                    parented = parented,
                }
            end
        end
    end

    return { status = "ok", totalMatched = total, returned = #modules, modules = modules }
end

ops.hook_control = function(params)
    local action = params.action

    if action == "status" then
        return {
            status = "ok",
            installed = hookState.installed,
            enabled = hookState.enabled,
            captured = hookState.captured,
            buffered = #trafficBuffer,
            error = hookState.error,
        }
    end

    if action == "clear" then
        trafficBuffer = {}
        trafficPending = {}
        hookState.captured = 0
        sendMessage({ type = "traffic_clear" })
        return { status = "ok", cleared = true }
    end

    if action == "stop" then
        hookState.enabled = false
        return { status = "ok", enabled = false, installed = hookState.installed }
    end

    if action == "start" then
        local ok, err = installNamecallHook()
        if not ok then
            return { status = "error", error = err, hint = "Potassium exposes hookmetamethod; check the console for the failure." }
        end
        hookState.enabled = true
        return { status = "ok", enabled = true, installed = true, note = "Recording FireServer / InvokeServer / Fire / Invoke." }
    end

    return { status = "error", error = "unknown_action", action = tostring(action) }
end

ops.saveinstance = function(params)
    if type(saveinstance) ~= "function" then
        return { status = "error", error = "saveinstance_unavailable" }
    end

    local target = game
    if type(params.path) == "string" and trim(params.path) ~= "" then
        local inst, err = resolveInstance(params.path)
        if not inst then
            return { status = "error", error = err or "instance_not_found", path = params.path }
        end
        target = inst
    end

    local fileName = type(params.fileName) == "string" and trim(params.fileName) or ""
    if fileName == "" then
        fileName = (instName(target) or "place") .. (target == game and ".rbxl" or ".rbxm")
    end

    local started = os.clock()
    local ok, err = pcall(function()
        saveinstance(target, {
            FileName = fileName,
            Decompile = params.decompile ~= false,
            ShowStatus = false,
        })
    end)

    if not ok then
        return { status = "error", error = tostring(err), path = fullName(target), fileName = fileName }
    end

    return {
        status = "ok",
        path = fullName(target),
        fileName = fileName,
        durationSeconds = math.floor((os.clock() - started) * 10) / 10,
        note = "Written to the Potassium workspace folder.",
    }
end

ops.instance_children = function(params)
    local inst, err = resolveInstance(params.path)
    if not inst then
        return { status = "error", error = err or "instance_not_found", path = params.path }
    end

    local limit = math.max(1, tonumber(params.limit) or 100)
    local children = safe(function() return inst:GetChildren() end) or {}
    local rows = {}

    for i = 1, math.min(#children, limit) do
        local child = children[i]
        rows[#rows + 1] = {
            name = instName(child),
            className = className(child),
            path = fullName(child),
            childCount = #(safe(function() return child:GetChildren() end) or {}),
            props = captureProps(child),
        }
    end

    return {
        status = "ok",
        path = fullName(inst),
        className = className(inst),
        totalChildren = #children,
        returned = #rows,
        children = rows,
    }
end

-- ---------------------------------------------------------------------------
-- transport
-- ---------------------------------------------------------------------------

local function handleRequest(id, op, params)
    local handler = ops[op]
    if handler == nil then
        return { v = PROTOCOL_VERSION, type = "response", id = id, op = op, status = "error", error = "unknown_op" }
    end

    local ok, result = pcall(handler, params or {})
    if not ok then
        return {
            v = PROTOCOL_VERSION,
            type = "response",
            id = id,
            op = op,
            status = "error",
            error = "handler_failed",
            detail = trimString(tostring(result), 2000),
        }
    end

    local response = type(result) == "table" and result or { status = "ok", result = result }
    response.v = PROTOCOL_VERSION
    response.type = "response"
    response.id = id
    response.op = op
    response.status = response.status or "ok"
    return response
end

local function closeSocket(target)
    if target == nil then return end
    pcall(function() target:Close() end)
end

function sendMessage(message)
    if not socketReady or socket == nil then return false end
    message.v = message.v or PROTOCOL_VERSION
    local target = socket
    local ok = pcall(function()
        target:Send(toJson(message))
    end)
    if not ok then
        socketReady = false
        if socket == target then socket = nil end
        closeSocket(target)
        return false
    end
    return true
end

local function writeFileSafe(path, text)
    if not CONFIG.MIRROR_FILES then return end
    if type(writefile) ~= "function" then return end
    pcall(function()
        if type(isfolder) == "function" and not isfolder(CONFIG.OUT_DIR) and type(makefolder) == "function" then
            makefolder(CONFIG.OUT_DIR)
        end
        writefile(path, text)
    end)
end

local function readFileSafe(path)
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    local ok, exists = pcall(isfile, path)
    if not ok or not exists then return nil end
    local readOk, raw = pcall(readfile, path)
    if not readOk then return nil end
    return raw
end

--- The endpoint that worked last run. Cached so a probe costs one attempt
--- instead of walking the whole list on every launch.
local function readCachedHost()
    local raw = readFileSafe(FILES.WS_HOST)
    if type(raw) ~= "string" then return nil end
    return trim(raw)
end

local function writeCachedHost(url)
    if type(writefile) ~= "function" or type(url) ~= "string" then return end
    pcall(function()
        if type(isfolder) == "function" and not isfolder(CONFIG.OUT_DIR) and type(makefolder) == "function" then
            makefolder(CONFIG.OUT_DIR)
        end
        writefile(FILES.WS_HOST, url)
    end)
end

--- Endpoints that accepted a connection and then dropped it — a listener that
--- is not our server, or nothing at all behind a permissive connect().
local rejectedUrls = {}

--- Endpoints to try, best guess first: an explicit WS_URL, then whatever
--- answered last time, then the configured hosts.
local function candidateUrls()
    local urls, seen = {}, {}
    local function push(url)
        if type(url) ~= "string" or url == "" or seen[url] or rejectedUrls[url] then return end
        seen[url] = true
        urls[#urls + 1] = url
    end

    local function build()
        push(CONFIG.WS_URL)
        push(readCachedHost())
        for _, host in ipairs(CONFIG.WS_HOSTS) do
            push("ws://" .. host .. ":" .. tostring(CONFIG.WS_PORT))
        end
    end

    build()
    if #urls == 0 and next(rejectedUrls) ~= nil then
        -- Everything was ruled out; the server may have come up since. Start over.
        table.clear(rejectedUrls)
        build()
    end
    return urls
end

local function connectSocket()
    -- WebSocket may be exposed as a table or as userdata with __index, so probe
    -- the member instead of the container's type.
    local connect = nil
    pcall(function()
        if WebSocket ~= nil then
            connect = WebSocket.connect or WebSocket.new
        end
    end)
    if type(connect) ~= "function" then
        return false, "websocket_unavailable"
    end

    local previous = socket
    socket = nil
    socketReady = false
    closeSocket(previous)

    local candidates = candidateUrls()
    local result, failures = nil, {}
    for _, url in ipairs(candidates) do
        local ok, attempt = pcall(connect, url)
        if ok and attempt ~= nil then
            result = attempt
            activeUrl = url
            break
        end
        failures[#failures + 1] = url .. " -> " .. (ok and "nil" or tostring(attempt))
    end

    if result == nil then
        activeUrl = nil
        return false, table.concat(failures, " | ")
    end

    socketGeneration = socketGeneration + 1
    local myGeneration = socketGeneration
    socket = result
    socketReady = true

    local function isMine()
        return isCurrent() and myGeneration == socketGeneration
    end

    local function onMessage(raw)
        if not isMine() then return end
        local message = fromJson(raw)
        if type(message) ~= "table" then return end
        if message.type == "request" then
            task.spawn(function()
                local response = handleRequest(message.id, message.op, message.params)
                sendMessage(response)
            end)
        end
    end

    local function onClose()
        if not isMine() then return end
        socketReady = false
        socket = nil
    end

    -- Signal objects on most builds, plain assignable fields on a few.
    local connected = pcall(function() socket.OnMessage:Connect(onMessage) end)
    if not connected then
        pcall(function() socket.OnMessage = onMessage end)
    end

    local closeConnected = pcall(function() socket.OnClose:Connect(onClose) end)
    if not closeConnected then
        pcall(function() socket.OnClose = onClose end)
    end

    local executor, executorVersion = "unknown", "unknown"
    if type(identifyexecutor) == "function" then
        local idOk, name, version = pcall(identifyexecutor)
        if idOk then
            executor = tostring(name or "unknown")
            executorVersion = tostring(version or "unknown")
        end
    end

    sendMessage({
        type = "hello",
        bridgeVersion = BRIDGE_VERSION,
        executor = executor,
        executorVersion = executorVersion,
        caps = {
            decompile = type(decompile) == "function",
            hookmetamethod = type(hookmetamethod) == "function",
            getsenv = type(getsenv) == "function",
            getinstances = type(getinstances) == "function",
            getnilinstances = type(getnilinstances) == "function",
            getloadedmodules = type(getloadedmodules) == "function",
            getproperties = type(getproperties) == "function",
            gethiddenproperties = type(gethiddenproperties) == "function",
            firesignal = type(firesignal) == "function",
            getconnections = type(getconnections) == "function",
            saveinstance = type(saveinstance) == "function",
            gethui = type(gethui) == "function",
            mouseInput = type(mousemoveabs) == "function",
        },
    })

    -- Some builds hand back a socket object for an endpoint that is not
    -- listening, or one that is listening but is not our server; both drop the
    -- connection right after the handshake. Give OnClose a moment to fire
    -- before trusting this endpoint enough to cache it.
    local chosen = activeUrl
    if #candidates > 1 then
        task.wait(CONFIG.WS_VERIFY_DELAY)
        if not (isCurrent() and myGeneration == socketGeneration and socketReady) then
            rejectedUrls[chosen] = true
            activeUrl = nil
            return false, chosen .. " -> closed_after_connect"
        end
    end

    writeCachedHost(chosen)
    return true
end

--- Second request channel, polled even while the socket is up: more than one
--- MCP server can be running (one per Claude surface) and only one of them can
--- own the port. The loser talks to us through files.
local function pollFileRequest()
    local raw = readFileSafe(FILES.REQUEST)
    if raw == nil then return end

    local request = fromJson(raw)
    if type(request) ~= "table" or type(request.id) ~= "string" then return end
    if request.id == lastFileRequestId then return end
    lastFileRequestId = request.id

    if type(delfile) == "function" then
        pcall(delfile, FILES.REQUEST)
    end

    task.spawn(function()
        local response = handleRequest(request.id, request.op, request.params)
        writeFileSafe(FILES.RESPONSE, toJson(response))
    end)
end

-- ---------------------------------------------------------------------------
-- boot
-- ---------------------------------------------------------------------------

if type(setthreadidentity) == "function" then
    pcall(setthreadidentity, 8)
end

installPrintHooks()
installLogService()

do
    local executor, version = "unknown", ""
    if type(identifyexecutor) == "function" then
        local ok, name, ver = pcall(identifyexecutor)
        if ok then
            executor = tostring(name or "unknown")
            version = tostring(ver or "")
        end
    end
    bridgePrint(string.format(
        "bridge v%s on %s %s | decompile:%s hookmetamethod:%s getsenv:%s",
        BRIDGE_VERSION,
        executor,
        version,
        tostring(type(decompile) == "function"),
        tostring(type(hookmetamethod) == "function"),
        tostring(type(getsenv) == "function")
    ))
end

if CONFIG.HOOK_ON_START then
    local ok, err = installNamecallHook()
    if ok then
        hookState.enabled = true
        bridgePrint("remote traffic hook active")
    else
        bridgeWarn("remote traffic hook failed:", err)
    end
end

-- With the native decompiler switched off, Konstant is the only one there is.
-- Fetch it up front so the first source request is not paying for an HTTP round
-- trip, and so a broken URL shows up in the console now rather than later.
if CONFIG.ALLOW_REMOTE_DECOMPILER and not CONFIG.USE_NATIVE_DECOMPILER then
    task.spawn(function()
        if loadRemoteDecompiler() == nil then
            bridgeWarn("remote decompiler unavailable:", tostring(decompilerState.remoteError))
        end
    end)
end

-- Wait for the client to finish loading before the first scan.
if not game:IsLoaded() then
    pcall(function() game.Loaded:Wait() end)
end
for _ = 1, 40 do
    if Players.LocalPlayer and #(safe(function() return ReplicatedStorage:GetChildren() end) or {}) > 0 then
        break
    end
    task.wait(0.25)
end

-- socket loop
task.spawn(function()
    local attempts = 0
    while isCurrent() do
        if not socketReady then
            attempts = attempts + 1
            local ok, err = connectSocket()
            if ok then
                if attempts <= 1 or attempts % 20 == 0 then
                    bridgePrint("connected to MCP server at " .. tostring(activeUrl))
                end
            elseif attempts == 1 or attempts % 20 == 0 then
                -- Retrying every few seconds is fine; saying so every few
                -- seconds is not.
                bridgeWarn(
                    "socket unavailable (" .. tostring(err) .. "), using file fallback in "
                        .. CONFIG.OUT_DIR .. " | attempts: " .. attempts
                )
            end
        else
            attempts = 0
        end

        local delay = CONFIG.WS_RECONNECT_DELAY
        if attempts > 2 then
            delay = math.min(delay * 2 ^ math.min(attempts - 2, 4), CONFIG.WS_MAX_RECONNECT_DELAY)
        end
        task.wait(delay)
    end
end)

-- first scan
task.spawn(function()
    local explorer, err = runFullScan()
    if explorer then
        bridgePrint(string.format(
            "scan complete | index:%d scripts:%d remotes:%d assets:%d in %ss",
            explorer.counts.index,
            explorer.counts.scripts,
            explorer.counts.remotes,
            explorer.counts.assets,
            tostring(explorer.durationSeconds)
        ))
        sendMessage({ type = "explorer", data = explorer })
        writeFileSafe(FILES.EXPLORER, toJson(explorer))
    else
        bridgeWarn("first scan failed:", err)
    end
end)

-- periodic rescan
if CONFIG.PERIODIC_RESCAN ~= false then
    task.spawn(function()
        while isCurrent() do
            task.wait(CONFIG.EXPLORER_INTERVAL)
            if isCurrent() and not scanInProgress then
                local explorer = runFullScan()
                if explorer then
                    sendMessage({ type = "explorer", data = explorer })
                    writeFileSafe(FILES.EXPLORER, toJson(explorer))
                end
            end
        end
    end)
end

-- log / traffic flush
task.spawn(function()
    while isCurrent() do
        task.wait(CONFIG.LOG_FLUSH_INTERVAL)
        -- Push increments over the socket, mirror the whole buffer to disk, so
        -- a file-mode server sees the same output as the socket-mode one.
        if #logPending > 0 then
            local batch = logPending
            logPending = {}
            sendMessage({ type = "logs", entries = batch })
            writeFileSafe(FILES.CONSOLE, toJson({
                schema = "roblox-potassium-bridge/console/3",
                meta = { timestamp = os.time(), count = #logBuffer },
                entries = logBuffer,
            }))
        end
        if #trafficPending > 0 then
            local batch = trafficPending
            trafficPending = {}
            sendMessage({ type = "remote_traffic", entries = batch })
            writeFileSafe(FILES.TRAFFIC, toJson({
                schema = "roblox-potassium-bridge/traffic/3",
                meta = { timestamp = os.time(), count = #trafficBuffer },
                entries = trafficBuffer,
            }))
        end
    end
end)

-- file request polling (skip when websocket is live)
task.spawn(function()
    while isCurrent() do
        if not socketReady then
            local ok, err = pcall(pollFileRequest)
            if not ok then
                bridgeWarn("file poll error:", err)
            end
        end
        task.wait(CONFIG.FILE_POLL_INTERVAL)
    end
end)

task.spawn(function()
    local lastMirror = 0
    while isCurrent() do
        loopTick = loopTick + 1

        local ok, err = pcall(function()
            local snapshot = buildSnapshot()
            sendMessage({ type = "snapshot", data = snapshot })

            -- Mirror unconditionally: a file-mode MCP server reports the bridge
            -- as disconnected until it can see a fresh snapshot.
            if (os.clock() - lastMirror) >= CONFIG.FILE_MIRROR_INTERVAL then
                lastMirror = os.clock()
                writeFileSafe(FILES.SNAPSHOT, toJson(snapshot))
                writeFileSafe(FILES.HEARTBEAT, toJson({
                    timestamp = os.time(),
                    loopTick = loopTick,
                    bridgeVersion = BRIDGE_VERSION,
                    socketConnected = socketReady,
                }))
            end
        end)

        if not ok then
            bridgeWarn("tick error:", err)
        end

        task.wait(CONFIG.SNAPSHOT_INTERVAL)
    end
    bridgePrint("bridge generation " .. GENERATION .. " retired")
end)

bridgePrint("bridge running. Keep this script alive while you use the MCP tools.")
