--[[
    FIGGY Native Hub — custom Roblox UI with no VoidUI dependency.
]]

local EggHub = {}

function EggHub.create(deps)
    local Config = deps.Config
    local AutoFarm = deps.AutoFarm
    local SpeedBypass = deps.SpeedBypass
    local Diagnostics = deps.Diagnostics
    local PathService = deps.PathService
    local FarmFilters = deps.FarmFilters
    local EggData = deps.EggData
    local BasePenAutomation = deps.BasePenAutomation
    local InventoryManager = deps.InventoryManager
    local PetAutomation = deps.PetAutomation
    local LocalPlayer = deps.LocalPlayer or game:GetService("Players").LocalPlayer

    local runtime = Config.Runtime
    local callbacks = {}
    local gui
    local window
    local content
    local pageBuilders = {}
    local visible = runtime.hubVisible ~= false
    local statusTask
    local statusRunning = false

    local colors = {
        bg = Color3.fromRGB(10, 11, 24),
        sidebar = Color3.fromRGB(12, 14, 31),
        panel = Color3.fromRGB(18, 21, 44),
        panel2 = Color3.fromRGB(23, 27, 58),
        border = Color3.fromRGB(65, 71, 125),
        text = Color3.fromRGB(244, 246, 255),
        muted = Color3.fromRGB(148, 154, 190),
        accent = Color3.fromRGB(139, 92, 246),
        accent2 = Color3.fromRGB(99, 102, 241),
        good = Color3.fromRGB(52, 211, 153),
        red = Color3.fromRGB(244, 114, 182),
    }

    local function ensureGui()
        if gui and gui.Parent then
            return gui
        end

        gui = Instance.new("ScreenGui")
        gui.Name = "FIGGYHub"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 100
        pcall(function() gui.Parent = game:GetService("CoreGui") end)
        if not gui.Parent then
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
        return gui
    end

    local function corner(parent, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius or 10)
        c.Parent = parent
        return c
    end

    local function stroke(parent, color, thickness, transparency)
        local s = Instance.new("UIStroke")
        s.Color = color or colors.border
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.Parent = parent
        return s
    end

    local function text(parent, textValue, size, color, position, dimensions)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.GothamSemibold
        l.Text = textValue
        l.TextSize = size or 13
        l.TextColor3 = color or colors.text
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Center
        l.Position = position or UDim2.fromOffset(0, 0)
        l.Size = dimensions or UDim2.fromScale(1, 1)
        l.Parent = parent
        return l
    end

    local function makeWindow()
        if window and window.Parent then
            return window
        end

        ensureGui()

        window = Instance.new("Frame")
        window.Name = "Main"
        window.AnchorPoint = Vector2.new(1, 0)
        window.Position = UDim2.new(1, -18, 0, 18)
        window.Size = UDim2.fromOffset(980, 620)
        window.BackgroundColor3 = colors.bg
        window.BorderSizePixel = 0
        window.Visible = visible
        window.Parent = gui
        corner(window, 16)
        stroke(window, colors.border, 1, 0.25)

        local shadow = Instance.new("ImageLabel")
        shadow.Name = "Shadow"
        shadow.AnchorPoint = Vector2.new(0.5, 0.5)
        shadow.Position = UDim2.fromScale(0.5, 0.5)
        shadow.Size = UDim2.new(1, 30, 1, 30)
        shadow.BackgroundTransparency = 1
        shadow.Image = "rbxassetid://6015897843"
        shadow.ImageColor3 = Color3.new(0, 0, 0)
        shadow.ImageTransparency = 0.55
        shadow.ScaleType = Enum.ScaleType.Slice
        shadow.SliceCenter = Rect.new(10, 10, 118, 118)
        shadow.ZIndex = 0
        shadow.Parent = window

        local sidebar = Instance.new("Frame")
        sidebar.Name = "Sidebar"
        sidebar.Size = UDim2.new(0, 210, 1, 0)
        sidebar.BackgroundColor3 = colors.sidebar
        sidebar.BorderSizePixel = 0
        sidebar.Parent = window
        corner(sidebar, 16)

        local brand = Instance.new("Frame")
        brand.BackgroundTransparency = 1
        brand.Position = UDim2.fromOffset(18, 18)
        brand.Size = UDim2.new(1, -36, 0, 54)
        brand.Parent = sidebar

        local logo = Instance.new("TextLabel")
        logo.Size = UDim2.fromOffset(42, 42)
        logo.BackgroundColor3 = colors.accent
        logo.Font = Enum.Font.GothamBlack
        logo.Text = "F"
        logo.TextSize = 22
        logo.TextColor3 = Color3.new(1, 1, 1)
        logo.Parent = brand
        corner(logo, 12)

        text(brand, "FIGGY", 18, colors.text, UDim2.fromOffset(54, 2), UDim2.new(1, -54, 0, 24))
        text(brand, "Egg Automation", 11, colors.muted, UDim2.fromOffset(54, 25), UDim2.new(1, -54, 0, 18))

        content = Instance.new("Frame")
        content.Name = "Content"
        content.Position = UDim2.fromOffset(210, 0)
        content.Size = UDim2.new(1, -210, 1, 0)
        content.BackgroundColor3 = colors.bg
        content.BorderSizePixel = 0
        content.Parent = window

        local header = Instance.new("Frame")
        header.Size = UDim2.new(1, 0, 0, 72)
        header.BackgroundColor3 = colors.panel
        header.BorderSizePixel = 0
        header.Parent = content

        text(header, "Automation", 20, colors.text, UDim2.fromOffset(24, 14), UDim2.new(0.6, 0, 0, 26))
        text(header, "Steal An Egg", 11, colors.muted, UDim2.fromOffset(24, 40), UDim2.new(0.6, 0, 0, 16))

        local close = Instance.new("TextButton")
        close.Position = UDim2.new(1, -48, 0, 18)
        close.Size = UDim2.fromOffset(30, 30)
        close.BackgroundColor3 = colors.panel2
        close.Text = "×"
        close.Font = Enum.Font.GothamBold
        close.TextSize = 18
        close.TextColor3 = colors.text
        close.Parent = header
        corner(close, 8)
        close.Activated:Connect(function()
            runWithPluginIdentity(function()
                runtime.hubVisible = false
                visible = false
                window.Visible = false
            end)
        end)

        local pages = Instance.new("Frame")
        pages.Name = "Pages"
        pages.Position = UDim2.fromOffset(0, 72)
        pages.Size = UDim2.new(1, 0, 1, -72)
        pages.BackgroundTransparency = 1
        pages.Parent = content

        local nav = Instance.new("Frame")
        nav.Position = UDim2.fromOffset(18, 88)
        nav.Size = UDim2.new(1, -36, 1, -106)
        nav.BackgroundTransparency = 1
        nav.Parent = sidebar

        local tabs = {
            {id = "Eggs", label = "Eggs", icon = "◉"},
            {id = "Filters", label = "Filters", icon = "≡"},
            {id = "Manage", label = "Manage", icon = "▦"},
            {id = "Pet", label = "Pet", icon = "♙"},
            {id = "ESP", label = "Visuals", icon = "◈"},
            {id = "Misc", label = "Misc", icon = "⚙"},
        }

        local activePage
        local function showPage(id)
            for pageId, page in pairs(pageBuilders.pages or {}) do
                page.Visible = pageId == id
            end
        end

        pageBuilders.pages = {}
        pageBuilders.content = pages

        for index, tab in ipairs(tabs) do
            local button = Instance.new("TextButton")
            button.Position = UDim2.fromOffset(0, (index - 1) * 58)
            button.Size = UDim2.new(1, 0, 0, 48)
            button.BackgroundColor3 = tab.id == "Eggs" and colors.accent or colors.panel2
            button.BackgroundTransparency = tab.id == "Eggs" and 0 or 0.45
            button.BorderSizePixel = 0
            button.Text = ""
            button.Parent = nav
            corner(button, 10)

            text(button, tab.icon, 16, colors.text, UDim2.fromOffset(14, 0), UDim2.fromOffset(28, 48))
            text(button, tab.label, 13, tab.id == "Eggs" and colors.text or colors.muted, UDim2.fromOffset(44, 0), UDim2.new(1, -48, 1, 0))

            button.Activated:Connect(function()
                runWithPluginIdentity(function()
                    showPage(tab.id)
                    for _, child in ipairs(nav:GetChildren()) do
                        if child:IsA("TextButton") then
                            child.BackgroundColor3 = colors.panel2
                            child.BackgroundTransparency = 0.45
                            for _, label in ipairs(child:GetChildren()) do
                                if label:IsA("TextLabel") then
                                    label.TextColor3 = colors.muted
                                end
                            end
                        end
                    end
                    button.BackgroundColor3 = colors.accent
                    button.BackgroundTransparency = 0
                    for _, label in ipairs(button:GetChildren()) do
                        if label:IsA("TextLabel") then
                            label.TextColor3 = colors.text
                        end
                    end
                end)
            end)

            local page = Instance.new("ScrollingFrame")
            page.Name = tab.id
            page.Size = UDim2.new(1, -32, 1, -24)
            page.Position = UDim2.fromOffset(16, 12)
            page.BackgroundTransparency = 1
            page.BorderSizePixel = 0
            page.ScrollBarThickness = 4
            page.ScrollBarImageColor3 = colors.accent
            page.Visible = tab.id == "Eggs"
            page.CanvasSize = UDim2.fromOffset(0, 0)
            page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.Parent = pages
            pageBuilders.pages[tab.id] = page
        end

        buildPages()
        return window
    end

    local function section(parent, title, columnWidth)
        local f = Instance.new("Frame")
        f.BackgroundColor3 = colors.panel
        f.BorderSizePixel = 0
        f.Size = columnWidth or UDim2.new(1, 0, 0, 0)
        f.AutomaticSize = Enum.AutomaticSize.Y
        f.Parent = parent
        corner(f, 12)
        stroke(f, colors.border, 1, 0.5)

        text(f, title, 12, colors.accent, UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 18))

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 8)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.Parent = f

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 38)
        pad.PaddingBottom = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 12)
        pad.Parent = f
        return f
    end

    local function toggle(parent, title, desc, getValue, setValue)
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 58)
        row.BackgroundColor3 = colors.panel2
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Text = ""
        row.Parent = parent
        corner(row, 9)

        text(row, title, 13, colors.text, UDim2.fromOffset(14, 8), UDim2.new(1, -78, 0, 20))
        text(row, desc or "", 11, colors.muted, UDim2.fromOffset(14, 30), UDim2.new(1, -78, 0, 16))

        local track = Instance.new("Frame")
        track.Position = UDim2.new(1, -58, 0.5, -10)
        track.Size = UDim2.fromOffset(44, 20)
        track.BorderSizePixel = 0
        track.Parent = row
        corner(track, 10)

        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(16, 16)
        knob.Position = UDim2.fromOffset(2, 2)
        knob.BorderSizePixel = 0
        knob.Parent = track
        corner(knob, 8)

        local function update()
            runWithPluginIdentity(function()
                local enabled = getValue() == true
                track.BackgroundColor3 = enabled and colors.accent or Color3.fromRGB(58, 62, 88)
                knob.Position = enabled and UDim2.fromOffset(26, 2) or UDim2.fromOffset(2, 2)
            end)
        end

        update()
        row.Activated:Connect(function()
            runWithPluginIdentity(function()
                setValue(not (getValue() == true))
                update()
            end)
        end)
        return row
    end

    local function button(parent, title, desc, callback)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 58)
        b.BackgroundColor3 = colors.accent
        b.BorderSizePixel = 0
        b.Text = ""
        b.Parent = parent
        corner(b, 9)

        text(b, title, 13, colors.text, UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 20))
        text(b, desc or "", 11, Color3.fromRGB(225, 222, 255), UDim2.fromOffset(14, 30), UDim2.new(1, -28, 0, 16))
        b.Activated:Connect(function()
            runWithPluginIdentity(callback)
        end)
        return b
    end

    local function slider(parent, title, getValue, setValue, minValue, maxValue, step, suffix)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 68)
        row.BackgroundColor3 = colors.panel2
        row.BorderSizePixel = 0
        row.Parent = parent
        corner(row, 9)

        local valueLabel = text(row, title, 12, colors.text, UDim2.fromOffset(14, 8), UDim2.new(0.7, 0, 0, 18))
        local track = Instance.new("TextButton")
        track.Position = UDim2.fromOffset(14, 42)
        track.Size = UDim2.new(1, -28, 0, 8)
        track.BackgroundColor3 = Color3.fromRGB(58, 62, 88)
        track.BorderSizePixel = 0
        track.Text = ""
        track.AutoButtonColor = false
        track.Parent = row
        corner(track, 4)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(0, 1)
        fill.BackgroundColor3 = colors.accent
        fill.BorderSizePixel = 0
        fill.Parent = track
        corner(fill, 4)

        local dragging = false
        local function applyAt(position)
            local rel = math.clamp((position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local raw = minValue + rel * (maxValue - minValue)
            local stepped = math.floor((raw / step) + 0.5) * step
            stepped = math.clamp(stepped, minValue, maxValue)
            setValue(stepped)
            fill.Size = UDim2.fromScale((stepped - minValue) / (maxValue - minValue), 1)
            valueLabel.Text = string.format("%s: %s%s", title, tostring(stepped), suffix or "")
        end

        local function refresh()
            local value = math.clamp(getValue() or minValue, minValue, maxValue)
            fill.Size = UDim2.fromScale((value - minValue) / (maxValue - minValue), 1)
            valueLabel.Text = string.format("%s: %s%s", title, tostring(value), suffix or "")
        end

        refresh()
        runWithPluginIdentity(refresh)
        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                runWithPluginIdentity(function() applyAt(input.Position) end)
            end
        end)
        track.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                runWithPluginIdentity(function() applyAt(input.Position) end)
            end
        end)
        game:GetService("UserInputService").InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        return row
    end

    local function grid(parent)
        local g = Instance.new("UIGridLayout")
        g.CellPadding = UDim2.fromOffset(8, 8)
        g.CellSize = UDim2.new(0.5, -4, 0, 58)
        g.SortOrder = Enum.SortOrder.LayoutOrder
        g.Parent = parent
        return g
    end

    function buildPages()
        local eggs = pageBuilders.pages.Eggs
        local left = section(eggs, "AUTO STEAL", UDim2.new(0.5, -8, 0, 0))
        left.Position = UDim2.fromOffset(0, 0)

        toggle(left, "Auto Steal", "Farm and return eggs automatically", function() return runtime.autoFarmEnabled == true end, function(enabled)
            runtime.autoFarmEnabled = enabled
            if enabled and callbacks.onAutoFarmStart then callbacks.onAutoFarmStart() else if not enabled and callbacks.onAutoFarmStop then callbacks.onAutoFarmStop() end end
        end)
        toggle(left, "Wait For Day", "Pause while night reset is active", function() return runtime.waitForDayBeforeFarm ~= false end, function(v) runtime.waitForDayBeforeFarm = v end)
        toggle(left, "Mutant Only", "Only target mutant eggs", function() return runtime.autoFarmMutantOnly == true end, function(v) runtime.autoFarmMutantOnly = v; if EggData then EggData.InvalidateCache() end end)
        toggle(left, "Infested First", "Prioritize parasite eggs", function() return runtime.autoFarmInfestedFirst ~= false end, function(v) runtime.autoFarmInfestedFirst = v end)
        toggle(left, "Anti Guard", "Use guard-zone walking behavior", function() return runtime.guardZoneForceWalk == true end, function(v) runtime.guardZoneForceWalk = v; if PathService then PathService.Invalidate() end end)
        slider(left, "Tween Speed", function() return runtime.tweenSpeed or 700 end, function(v) runtime.tweenSpeed = v end, 300, 1000, 50, "")
        button(left, "Set Standby Here", "Use your current position", function()
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root then runtime.standbyPosition = root.Position; if PathService then PathService.Invalidate() end end
        end)

        local right = section(eggs, "FILTERS", UDim2.new(0.5, -8, 0, 0))
        right.Position = UDim2.new(0.5, 8, 0, 0)
        toggle(right, "Strict Filter", "Only use selected rarities and zones", function() return runtime.autoFarmFilterWhitelist ~= false end, function(v) runtime.autoFarmFilterWhitelist = v end)
        toggle(right, "Infested Only", "Ignore eggs without parasite", function() return runtime.autoFarmInfestedOnly == true end, function(v) runtime.autoFarmInfestedOnly = v end)
        slider(right, "Max Distance", function() return runtime.maxDistance or 200 end, function(v) runtime.maxDistance = v end, 50, 500, 10, " studs")

        local eggsLayout = Instance.new("UIListLayout")
        eggsLayout.FillDirection = Enum.FillDirection.Horizontal
        eggsLayout.Padding = UDim.new(0, 16)
        eggsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        eggsLayout.Parent = eggs

        local filters = pageBuilders.pages.Filters
        if FarmFilters and FarmFilters.GetRarityOptions then
            local rarity = section(filters, "RARITIES")
            local list = FarmFilters.GetRarityOptions()
            table.sort(list, function(a, b) return (a.tier or 0) > (b.tier or 0) end)
            for _, option in ipairs(list) do
                toggle(rarity, option.label or option.key, "Rarity filter", function() return FarmFilters.GetRarityEnabled(option.key) end, function(v) FarmFilters.SetRarityEnabled(option.key, v); if EggData then EggData.InvalidateCache() end end)
            end
        end
        if FarmFilters and FarmFilters.GetZoneOptions then
            local zones = section(filters, "ZONES")
            for _, option in ipairs(FarmFilters.GetZoneOptions()) do
                toggle(zones, option.label or option.id, "Zone filter", function() return FarmFilters.GetZoneEnabled(option.id) end, function(v) FarmFilters.SetZoneEnabled(option.id, v); if EggData then EggData.InvalidateCache() end end)
            end
        end

        local manage = pageBuilders.pages.Manage
        local inv = section(manage, "INVENTORY")
        toggle(inv, "Manage Inventory", "Place or sell eggs when inventory is full", function() return runtime.autoPlaceEnabled ~= false or runtime.autoSellEnabled == true end, function(v)
            if v then runtime.autoPlaceEnabled = true; if InventoryManager then InventoryManager.Start() end else if InventoryManager then InventoryManager.Stop() end end
        end)
        toggle(inv, "Auto Place", "Place unplaced eggs on the plot", function() return runtime.autoPlaceEnabled ~= false end, function(v) runtime.autoPlaceEnabled = v end)
        toggle(inv, "Auto Sell", "Sell selected egg rarities", function() return runtime.autoSellEnabled == true end, function(v) runtime.autoSellEnabled = v end)
        toggle(inv, "Dump Worst Eggs", "Sell a batch of low-priority eggs", function() return runtime.autoDumpWorstEggsEnabled ~= false end, function(v) runtime.autoDumpWorstEggsEnabled = v end)
        slider(inv, "Place Batch", function() return runtime.autoPlaceBatchSize or 5 end, function(v) runtime.autoPlaceBatchSize = v end, 1, 20, 1, "")
        slider(inv, "Place Interval", function() return runtime.autoPlaceInterval or 60 end, function(v) runtime.autoPlaceInterval = v end, 10, 600, 10, " sec")
        slider(inv, "Worst Egg Count", function() return runtime.autoDumpWorstEggCount or 10 end, function(v) runtime.autoDumpWorstEggCount = v end, 1, 50, 1, "")

        local pet = pageBuilders.pages.Pet
        local petSec = section(pet, "PET AUTOMATION")
        toggle(petSec, "Pet Care", "Master pet automation switch", function() return runtime.autoPetCareEnabled ~= false end, function(v) runtime.autoPetCareEnabled = v end)
        toggle(petSec, "Auto Hatch", "Open ready eggs", function() return runtime.autoHatchEnabled ~= false end, function(v) runtime.autoHatchEnabled = v end)
        toggle(petSec, "Auto Equip Best", "Equip the strongest pets", function() return runtime.autoEquipBest ~= false end, function(v) runtime.autoEquipBest = v end)
        toggle(petSec, "Auto Fuse", "Fuse duplicate pets", function() return runtime.autoFuseEnabled ~= false end, function(v) runtime.autoFuseEnabled = v end)

        local pen = section(pet, "BASE PEN")
        toggle(pen, "Auto Upgrade", "Buy the next base tier", function() return runtime.autoUpgradeBasePen ~= false end, function(v) runtime.autoUpgradeBasePen = v end)
        toggle(pen, "Auto Collect", "Collect pen and offline money", function() return runtime.autoCollectPenMoney ~= false end, function(v) runtime.autoCollectPenMoney = v end)

        local esp = pageBuilders.pages.ESP
        local espSec = section(esp, "VISUALS")
        toggle(espSec, "Treadmill ESP", "Show treadmills", function() return runtime.showTreadmill == true end, function(v) runtime.showTreadmill = v end)
        toggle(espSec, "Treadmill Bounds", "Show treadmill boundaries", function() return runtime.showTreadmillBounds == true end, function(v) runtime.showTreadmillBounds = v end)
        toggle(espSec, "Trap ESP", "Show traps", function() return runtime.showTraps == true end, function(v) runtime.showTraps = v end)
        toggle(espSec, "Trap Bounds", "Show trap boundaries", function() return runtime.showTrapBounds == true end, function(v) runtime.showTrapBounds = v end)
        toggle(espSec, "Avoid Own Traps", "Avoid own trap zones", function() return runtime.pathAvoidOwnTraps == true end, function(v) runtime.pathAvoidOwnTraps = v; if PathService then PathService.Invalidate() end end)

        local misc = pageBuilders.pages.Misc
        local miscSec = section(misc, "MOVEMENT")
        toggle(miscSec, "Speed Bypass", "Use the movement speed bypass", function() return SpeedBypass and SpeedBypass.IsEnabled() or false end, function(v) if SpeedBypass then if v then SpeedBypass.Enable() else SpeedBypass.Disable() end end end)
    end

    local function formatStatus()
        if not Diagnostics then return "Diagnostics unavailable" end
        local ok, diag = pcall(Diagnostics.Collect)
        if not ok or type(diag) ~= "table" then return "Loading diagnostics..." end
        local parts = {}
        if diag.autoFarm then
            table.insert(parts, string.format("Eggs %d/%d · %s", (diag.esp and diag.esp.eggsVisible or 0), (diag.esp and diag.esp.eggsTotal or 0), tostring(diag.autoFarm.phase or "Idle")))
            if diag.autoFarm.target then
                table.insert(parts, string.format("Target: %s (%dm)", tostring(diag.autoFarm.target.name or "Egg"), tonumber(diag.autoFarm.target.distance) or 0))
            end
        end
        if diag.inventory and diag.inventory.active then table.insert(parts, string.format("Inventory: %s", tostring(diag.inventory.detail or diag.inventory.phase))) end
        return table.concat(parts, "\n")
    end

    local function startStatusLoop()
        if statusRunning then return end
        statusRunning = true
        statusTask = task.spawn(function()
            while statusRunning do
                runWithPluginIdentity(function()
                    if gui and window then
                        local status = window:FindFirstChild("Status", true)
                        if status and status.SetText then status:SetText(formatStatus()) end
                    end
                end)
                task.wait(runtime.hubStatusRefreshInterval or 1)
            end
        end)
    end

    local function stopStatusLoop()
        statusRunning = false
    end

    local function SetVisible(value)
        runtime.hubVisible = value == true
        visible = runtime.hubVisible
        runWithPluginIdentity(function()
            if window then window.Visible = visible end
        end)
    end

    local function ToggleVisible()
        SetVisible(not visible)
        return visible
    end

    local function start()
        runWithPluginIdentity(function()
            makeWindow()
            attachKeybind()
            SetVisible(runtime.hubVisible ~= false)
        end)
        startStatusLoop()
    end

    local function stop()
        stopStatusLoop()
        SetVisible(false)
    end

    local function destroy()
        stopStatusLoop()
        if gui then gui:Destroy() end
        gui = nil
        window = nil
    end

    local inputConnection
    local function attachKeybind()
        if inputConnection then return end
        inputConnection = game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
            if not processed and input.KeyCode == (runtime.hubToggleKey or Enum.KeyCode.G) then
                ToggleVisible()
            end
        end)
    end

    local function runWithPluginIdentity(fn)
        local previous

        if type(getthreadidentity) == "function" then
            local ok, value = pcall(getthreadidentity)
            if ok then previous = value end
        end

        if type(setthreadidentity) == "function" then
            pcall(setthreadidentity, 8)
        end

        local results = table.pack(pcall(fn))

        if type(setthreadidentity) == "function" and previous ~= nil then
            pcall(setthreadidentity, previous)
        end

        if not results[1] then
            warn("[FIGGY] UI callback failed: " .. tostring(results[2]))
        end

        return table.unpack(results, 2, results.n)
    end

    return {
        Start = start,
        Stop = stop,
        Destroy = destroy,
        SetVisible = SetVisible,
        ToggleVisible = ToggleVisible,
        IsVisible = function() return visible end,
        SetCallbacks = function(v) callbacks = v or {} end,
        SetDiagnostics = function(v) Diagnostics = v end,
        AttachKeybind = attachKeybind,
        Render = function() end,
    }
end

return EggHub
