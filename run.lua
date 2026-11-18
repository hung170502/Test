--[[
    Steal An Egg - remote executor entry point

    Execute:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/hung170502/Test/main/run.lua"))()
]]

local BASE_URL = "https://raw.githubusercontent.com/hung170502/Test/main/"

local FILES = {
    "hub_loader.lua",
    "EggESP.lua",
    "potassium_bridge.lua",
    "EggESP/init.lua",
    "EggESP/core/Config.lua",
    "EggESP/core/Diagnostics.lua",
    "EggESP/core/FarmFilters.lua",
    "EggESP/core/Loader.lua",
    "EggESP/core/Util.lua",
    "EggESP/automation/AutoFarm.lua",
    "EggESP/automation/BasePenAutomation.lua",
    "EggESP/automation/DayCycle.lua",
    "EggESP/automation/GuardZone.lua",
    "EggESP/automation/InventoryManager.lua",
    "EggESP/automation/Movement.lua",
    "EggESP/automation/Passthrough.lua",
    "EggESP/automation/PetAutomation.lua",
    "EggESP/automation/SpeedBypass.lua",
    "EggESP/navigation/Pathfinder.lua",
    "EggESP/esp/BoundingBoxPool.lua",
    "EggESP/esp/BoundingBoxRenderer.lua",
    "EggESP/esp/Controller.lua",
    "EggESP/esp/DataCollector.lua",
    "EggESP/esp/DrawingPool.lua",
    "EggESP/esp/EggData.lua",
    "EggESP/esp/ObstacleData.lua",
    "EggESP/esp/PathService.lua",
    "EggESP/esp/Renderer.lua",
    "EggESP/esp/StackLayout.lua",
    "EggESP/esp/TextLayout.lua",
    "EggESP/esp/TrapData.lua",
    "EggESP/esp/TreadmillData.lua",
    "EggESP/ui/FarmFilterUI.lua",
    "EggESP/ui/Hub.lua",
    "EggESP/ui/EggHub.lua",
    "EggESP/ui/VoidUI.lua",
    "EggESP/ui/VoidUIHub.lua",
    "EggESP/ui/void_build.lua",
}

local genv = (type(getgenv) == "function" and getgenv()) or _G
local virtualFiles = {}

local cacheToken = nil

local function httpGet(url)
    if game ~= nil then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and typeof(body) == "string" and #body > 0 then
            return body
        end
    end
    if type(httpget) == "function" then
        local ok, body = pcall(httpget, url)
        if ok and typeof(body) == "string" and #body > 0 then
            return body
        end
    end
    return nil
end

local function addFile(relativePath, source)
    virtualFiles[relativePath] = source
    virtualFiles["./" .. relativePath] = source
    virtualFiles["Steal-An-Egg/" .. relativePath] = source
end

local downloaded = 0
local failedFiles = {}
for _, relativePath in ipairs(FILES) do
    local source = httpGet(BASE_URL .. relativePath)

    if typeof(source) == "string" and #source > 0 then
        local trimmed = source:gsub("^%s+", "")
        local lower = trimmed:lower()
        if lower:sub(1, 9) == "<!doctype"
            or lower:sub(1, 5) == "<html"
            or trimmed:sub(1, 5) == "404: "
            or trimmed:sub(1, 9) == "not found" then
            table.insert(failedFiles, relativePath .. " (HTML/error page)")
        else
            addFile(relativePath, source)
            downloaded = downloaded + 1
        end
    else
        table.insert(failedFiles, relativePath)
    end
end

if downloaded == 0 then
    error("[Hub] Could not download repository files. Check HttpGet access and the GitHub URL.", 0)
end

if #failedFiles > 0 then
    warn("[Hub] Some remote files failed: " .. table.concat(failedFiles, ", "))
end

if not virtualFiles["hub_loader.lua"] then
    error("[Hub] run.lua: hub_loader.lua download failed", 0)
end

local originalReadfile = rawget(genv, "readfile") or readfile
local originalLoadfile = rawget(genv, "loadfile") or loadfile
local originalIsfile = rawget(genv, "isfile") or isfile

local function normalizePath(path)
    path = tostring(path):gsub("\\\\", "/")
    path = path:gsub("^./", "")
    return path
end

local function findVirtual(path)
    path = normalizePath(path)
    local direct = virtualFiles[path]
    if direct then return direct end

    if path:sub(1, 13) == "Steal-An-Egg/" then
        return virtualFiles[path:sub(14)]
    end

    return nil
end

local virtualReadfile = function(path)
    local source = findVirtual(path)
    if typeof(source) == "string" and #source > 0 then
        return source
    end
    if type(originalReadfile) == "function" then
        return originalReadfile(path)
    end
    error("File not found: " .. tostring(path), 0)
end

local virtualLoadfile = function(path)
    local source = findVirtual(path)
    if typeof(source) == "string" and #source > 0 then
        local chunk, err = loadstring(source, "@" .. tostring(path))
        if chunk then return chunk end
        return nil, err
    end
    if type(originalLoadfile) == "function" then
        return originalLoadfile(path)
    end
    return nil, "File not found: " .. tostring(path)
end

rawset(genv, "readfile", virtualReadfile)
rawset(genv, "loadfile", virtualLoadfile)
rawset(genv, "isfile", function(path)
    if findVirtual(path) then return true end
    if type(originalIsfile) == "function" then return originalIsfile(path) end
    return false
end)

local hubSource = virtualFiles["hub_loader.lua"]
local chunk, err = loadstring(hubSource, "@StealAnEggHub/hub_loader.lua")
if not chunk then
    error("[Hub] run.lua compile failed: " .. tostring(err), 0)
end

return chunk()
