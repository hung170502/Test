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
    local Movement = deps.Movement

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

    local function runWithPluginIdentity(fn)
        if type(fn) ~= "function" then
            return false
        end

        local previous

        if type(getthreadidentity) == "function" then
            local identityOk, identity = pcall(getthreadidentity)

            if identityOk then
                previous = identity
            end
        end

        if type(setthreadidentity) == "function" then
            pcall(setthreadidentity, 8)
        end

        local ok, result = pcall(fn)

        if type(setthreadidentity) == "function" and previous ~= nil then
            pcall(setthreadidentity, previous)
        end

        if not ok then
            warn("[FIGGY] UI callback failed: " .. tostring(result))
            return false, result
        end

        return true, result
    end

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

    local buildPages

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

        text(header, "VENYX", 20, colors.text, UDim2.fromOffset(24, 10), UDim2.new(0.45, 0, 0, 26))
        text(header, "Steal An Egg · v1.19", 11, colors.muted, UDim2.fromOffset(24, 36), UDim2.new(0.45, 0, 0, 16))

        local search = Instance.new("TextBox")
        search.Name = "Search"
        search.AnchorPoint = Vector2.new(1, 0.5)
        search.Position = UDim2.new(1, -92, 0.5, 0)
        search.Size = UDim2.fromOffset(190, 34)
        search.BackgroundColor3 = colors.panel2
        search.BorderSizePixel = 0
        search.PlaceholderText = "Search"
        search.Text = ""
        search.Font = Enum.Font.GothamSemibold
        search.TextSize = 12
        search.TextColor3 = colors.text
        search.PlaceholderColor3 = colors.muted
        search.ClearTextOnFocus = false
        corner(search, 8)
        stroke(search, colors.border, 1, 0.5)
        search.Parent = header

        search:GetPropertyChangedSignal("Text"):Connect(function()
            local query = tostring(search.Text):lower()
            for _, page in pairs(pageBuilders.pages or {}) do
                if page:IsA("ScrollingFrame") then
                    for _, descendant in ipairs(page:GetDescendants()) do
                        if descendant:IsA("TextButton") or descendant:IsA("Frame") then
                            local height = descendant.AbsoluteSize.Y
                            if height >= 58 and height <= 68 then
                                local found = ""
                                for _, child in ipairs(descendant:GetChildren()) do
                                    if child:IsA("TextLabel") then
                                        found = found .. " " .. child.Text
                                    end
                                end
                                descendant.Visible = query == "" or found:lower():find(query, 1, true) ~= nil
                            end
                        end
                    end
                end
            end
        end)

        local minimize = Instance.new("TextButton")
        minimize.AnchorPoint = Vector2.new(1, 0.5)
        minimize.Position = UDim2.new(1, -54, 0.5, 0)
        minimize.Size = UDim2.fromOffset(30, 30)
        minimize.BackgroundColor3 = colors.panel2
        minimize.BorderSizePixel = 0
        minimize.Text = "—"
        minimize.Font = Enum.Font.GothamBold
        minimize.TextSize = 13
        minimize.TextColor3 = colors.text
        minimize.Parent = header
        corner(minimize, 8)
        minimize.Activated:Connect(function()
            runWithPluginIdentity(function()
                window.Visible = false
                visible = false
                runtime.hubVisible = false
            end)
        end)

        local close = Instance.new("TextButton")
        close.AnchorPoint = Vector2.new(1, 0.5)
        close.Position = UDim2.new(1, -16, 0.5, 0)
        close.Size = UDim2.fromOffset(30, 30)
        close.BackgroundColor3 = colors.panel2
        close.BorderSizePixel = 0
        close.Text = "×"
        close.Font = Enum.Font.GothamBold
        close.TextSize = 16
        close.TextColor3 = colors.text
        close.Parent = header
        corner(close, 8)
        close.Activated:Connect(function()
            runWithPluginIdentity(function()
                window.Visible = false
                visible = false
                runtime.hubVisible = false
            end)
        end)

        do
            local draggingWindow = false
            local dragStart = nil
            local windowStart = nil

            header.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    draggingWindow = true
                    dragStart = input.Position
                    windowStart = window.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            draggingWindow = false
                        end
                    end)
                end
            end)

            header.InputChanged:Connect(function(input)
                if draggingWindow and input.UserInputType == Enum.UserInputType.MouseMovement and dragStart and windowStart then
                    local delta = input.Position - dragStart
                    pcall(function()
                        window.Position = UDim2.new(windowStart.X.Scale, windowStart.X.Offset + delta.X, windowStart.Y.Scale, windowStart.Y.Offset + delta.Y)
                    end)
                end
            end)
        end

        local statusCard = Instance.new("Frame")
        statusCard.Name = "Status"
        statusCard.AnchorPoint = Vector2.new(1, 0.5)
        statusCard.Position = UDim2.new(1, -300, 0.5, 0)
        statusCard.Size = UDim2.fromOffset(190, 38)
        statusCard.BackgroundColor3 = colors.panel2
        statusCard.BorderSizePixel = 0
        statusCard.Parent = header
        corner(statusCard, 8)

        local statusText = text(statusCard, "Loading status...", 10, colors.muted, UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0))
        statusText.TextWrapped = true

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
            {id = "Home", label = "Home", icon = "⌂"},
            {id = "Steal", label = "Steal", icon = "◉"},
            {id = "AutoHop", label = "Auto Hop", icon = "⇄"},
            {id = "Player", label = "Player", icon = "♙"},
            {id = "Settings", label = "Settings", icon = "⚙"},
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
            button.BackgroundColor3 = tab.id == "Steal" and colors.accent or colors.panel2
            button.BackgroundTransparency = tab.id == "Steal" and 0 or 0.45
            button.BorderSizePixel = 0
            button.Text = ""
            button.Parent = nav
            corner(button, 10)

            text(button, tab.icon, 16, colors.text, UDim2.fromOffset(14, 0), UDim2.fromOffset(28, 48))
            text(button, tab.label, 13, tab.id == "Steal" and colors.text or colors.muted, UDim2.fromOffset(44, 0), UDim2.new(1, -48, 1, 0))

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
            page.Visible = tab.id == "Steal"
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

    local function methodButton(parent, title, options, getValue, setValue)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 58)
        b.BackgroundColor3 = colors.panel2
        b.BorderSizePixel = 0
        b.Text = ""
        b.AutoButtonColor = false
        b.Parent = parent
        corner(b, 9)

        text(b, title, 12, colors.text, UDim2.fromOffset(14, 8), UDim2.new(0.55, 0, 0, 20))
        local valueLabel = text(b, tostring(getValue()), 12, colors.accent, UDim2.new(0.55, 0, 0, 0), UDim2.new(0.45, -14, 1, 0))
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right

        b.Activated:Connect(function()
            runWithPluginIdentity(function()
                local current = tostring(getValue())
                local index = 1

                for i, option in ipairs(options) do
                    if option == current then
                        index = i
                        break
                    end
                end

                local nextIndex = (index % #options) + 1
                setValue(options[nextIndex])
                valueLabel.Text = tostring(options[nextIndex])
            end)
        end)

        return b
    end

    local function multiSelect(parent, title, options, getValues, setValues)
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 58)
        row.BackgroundColor3 = colors.panel2
        row.BorderSizePixel = 0
        row.Text = ""
        row.AutoButtonColor = false
        row.Parent = parent
        corner(row, 9)

        text(row, title, 12, colors.text, UDim2.fromOffset(14, 8), UDim2.new(0.55, 0, 0, 20))
        local valueLabel = text(row, "0 selected", 11, colors.accent, UDim2.new(0.55, 0, 0, 0), UDim2.new(0.45, -14, 1, 0))
        valueLabel.TextXAlignment = Enum.TextXAlignment.Right

        local open = false
        local menu

        local function refresh()
            local values = getValues() or {}
            local count = 0
            for _ in pairs(values) do count = count + 1 end
            valueLabel.Text = count == 0 and "All" or tostring(count) .. " selected"
        end

        row.Activated:Connect(function()
            runWithPluginIdentity(function()
                open = not open
                if menu then menu:Destroy() menu = nil end
                if not open then refresh() return end

                menu = Instance.new("Frame")
                menu.Name = title .. "Menu"
                menu.AnchorPoint = Vector2.new(1, 0)
                menu.Position = UDim2.new(1, -6, 1, 6)
                menu.Size = UDim2.fromOffset(math.min(220, row.AbsoluteSize.X), math.max(44 * #options, 44))
                menu.BackgroundColor3 = colors.panel
                menu.BorderSizePixel = 0
                menu.ZIndex = 30
                menu.Parent = row
                corner(menu, 8)
                stroke(menu, colors.border, 1, 0.2)

                local layout = Instance.new("UIListLayout")
                layout.Padding = UDim.new(0, 4)
                layout.SortOrder = Enum.SortOrder.LayoutOrder
                layout.Parent = menu

                local pad = Instance.new("UIPadding")
                pad.PaddingTop = UDim.new(0, 6)
                pad.PaddingBottom = UDim.new(0, 6)
                pad.PaddingLeft = UDim.new(0, 6)
                pad.PaddingRight = UDim.new(0, 6)
                pad.Parent = menu

                for _, option in ipairs(options) do
                    local item = Instance.new("TextButton")
                    item.Size = UDim2.new(1, 0, 0, 36)
                    item.BackgroundColor3 = colors.panel2
                    item.BorderSizePixel = 0
                    item.Text = ""
                    item.ZIndex = 31
                    item.Parent = menu
                    corner(item, 6)

                    local selected = getValues()[option] == true
                    local dot = Instance.new("Frame")
                    dot.Position = UDim2.new(0, 10, 0.5, -7)
                    dot.Size = UDim2.fromOffset(14, 14)
                    dot.BackgroundColor3 = selected and colors.accent or Color3.fromRGB(58, 62, 88)
                    dot.BorderSizePixel = 0
                    dot.ZIndex = 32
                    dot.Parent = item
                    corner(dot, 7)
                    text(item, option, 12, colors.text, UDim2.fromOffset(34, 0), UDim2.new(1, -40, 1, 0)).ZIndex = 32

                    item.Activated:Connect(function()
                        local values = getValues() or {}
                        values[option] = not (values[option] == true)
                        setValues(values)
                        dot.BackgroundColor3 = values[option] and colors.accent or Color3.fromRGB(58, 62, 88)
                        refresh()
                    end)
                end
            end)
        end)

        refresh()
        return row
    end

    buildPages = function()
        local home = pageBuilders.pages.Home
        local homeLeft = section(home, "OVERVIEW", UDim2.new(0.5, -8, 0, 0))
        homeLeft.Position = UDim2.fromOffset(0, 0)
        button(homeLeft, "Start Auto Steal", "Start the configured auto-farm workflow", function()
            runtime.autoFarmEnabled = true
            if callbacks.onAutoFarmStart then callbacks.onAutoFarmStart() end
        end)
        button(homeLeft, "Stop Auto Steal", "Stop movement and automation", function()
            runtime.autoFarmEnabled = false
            if callbacks.onAutoFarmStop then callbacks.onAutoFarmStop() end
        end)

        local homeRight = section(home, "STATUS", UDim2.new(0.5, -8, 0, 0))
        homeRight.Position = UDim2.new(0.5, 8, 0, 0)
        toggle(homeRight, "Automation", "Enable the selected workflow", function() return runtime.autoFarmEnabled == true end, function(v)
            runtime.autoFarmEnabled = v
            if v and callbacks.onAutoFarmStart then callbacks.onAutoFarmStart()
            elseif not v and callbacks.onAutoFarmStop then callbacks.onAutoFarmStop() end
        end)

        local steal = pageBuilders.pages.Steal
        local stealLayout = Instance.new("UIListLayout")
        stealLayout.FillDirection = Enum.FillDirection.Horizontal
        stealLayout.Padding = UDim.new(0, 16)
        stealLayout.SortOrder = Enum.SortOrder.LayoutOrder
        stealLayout.Parent = steal

        local left = section(steal, "AUTO STEAL", UDim2.new(0.5, -8, 0, 0))
        left.Position = UDim2.fromOffset(0, 0)
        toggle(left, "Auto Steal", "Auto farm and return eggs", function() return runtime.autoFarmEnabled == true end, function(v)
            runtime.autoFarmEnabled = v
            if v and callbacks.onAutoFarmStart then callbacks.onAutoFarmStart()
            elseif not v and callbacks.onAutoFarmStop then callbacks.onAutoFarmStop() end
        end)
        methodButton(left, "Move to Egg", {"Teleport", "Walk"}, function() return runtime.moveToEggMethod or "Teleport" end, function(v) runtime.moveToEggMethod = v end)
        methodButton(left, "Delivery Method", {"Fast Tween", "Quick Steps"}, function() return runtime.deliveryMethod or "Fast Tween" end, function(v) runtime.deliveryMethod = v end)
        methodButton(left, "Teleport Zones", {"Volcano", "Alien", "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest"}, function() return "Steal First" end, function() warn("[FIGGY] Teleport zone routing is a placeholder") end)
        toggle(left, "Steal Missing Index Eggs", "Placeholder: no confirmed game API", function() return false end, function(_) warn("[FIGGY] Missing-index egg mode has no confirmed game API") end)
        toggle(left, "Steal from Other Players", "Placeholder: server action API required", function() return false end, function(_) warn("[FIGGY] Player stealing API is not implemented") end)
        toggle(left, "Anti Guard", "Use guard-zone movement", function() return runtime.guardZoneForceWalk == true end, function(v) runtime.guardZoneForceWalk = v; if PathService then PathService.Invalidate() end end)
        toggle(left, "Drop Eggs at Safe Zone", "Placeholder until safe-zone API is confirmed", function() return false end, function(_) warn("[FIGGY] Safe-zone dropping API is not implemented") end)

        local right = section(steal, "FILTER", UDim2.new(0.5, -8, 0, 0))
        right.Position = UDim2.new(0.5, 8, 0, 0)
        methodButton(right, "Filter Zones", {"Alien", "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest", "Cosmic", "Stormlands", "Prehistoric", "Abyss Ocean", "Volcano", "Snow", "Jungle", "Desert", "Lake", "Forest"}, function() return "All Zones" end, function(v) warn("[FIGGY] Zone filter placeholder: " .. tostring(v)) end)
        methodButton(right, "Steal First", {"Best value", "Lowest value", "Best rarity", "Best mutation", "Biggest", "Closest"}, function() return "Highest Earnings" end, function(v) runtime.autoFarmPriority = v end)
        multiSelect(right, "Mutations", {"None", "Silver", "Rainbow", "Golden"}, function()
            local values = runtime.uiMutationSelection or {}
            return values
        end, function(values)
            runtime.uiMutationSelection = values
            runtime.autoFarmMutantOnly = values.Mutant == true
            runtime.autoFarmInfestedOnly = values.Infested == true
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)
        multiSelect(right, "Rarities", {"Divine", "Enternal", "Secret", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"}, function()
            local values = runtime.uiRaritySelection or {}
            return values
        end, function(values)
            runtime.uiRaritySelection = values
            if FarmFilters and FarmFilters.SetRarityEnabled then
                for key, enabled in pairs(values) do
                    for _, option in ipairs(FarmFilters.GetRarityOptions and FarmFilters.GetRarityOptions() or {}) do
                        if tostring(option.label or option.key):lower():find(key:lower(), 1, true) then
                            FarmFilters.SetRarityEnabled(option.key, enabled)
                        end
                    end
                end
            end
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)
        methodButton(right, "Only These Eggs", {"Any Egg", "Selected Eggs"}, function() return "Any Egg" end, function(v) warn("[FIGGY] Egg-name whitelist placeholder: " .. tostring(v)) end)
        slider(right, "Min Value/s", function() return runtime.autoFarmMinValuePerSecond or 0 end, function(v) runtime.autoFarmMinValuePerSecond = v end, 0, 2000, 25, "/s")
        slider(right, "Min KG", function() return runtime.autoFarmMinWeight or 0 end, function(v) runtime.autoFarmMinWeight = v end, 0, 200, 5, " kg")
        toggle(right, "Sell Cheapest Egg When Bag Is Full", "Placeholder until sell policy is selected", function() return runtime.autoSellEnabled == true end, function(v) runtime.autoSellEnabled = v end)
        slider(right, "Only Below /s", function() return runtime.autoFarmBelowValuePerSecond or 0 end, function(v) runtime.autoFarmBelowValuePerSecond = v end, 0, 2000, 25, "/s")

        if FarmFilters and FarmFilters.GetRarityOptions then
            local raritySection = section(right, "MIN VALUE PER RARITY", UDim2.new(1, 0, 0, 0))
            for _, option in ipairs(FarmFilters.GetRarityOptions()) do
                toggle(raritySection, option.label or option.key, "0 means no minimum", function() return false end, function(_) warn("[FIGGY] Per-rarity minimum API is not implemented") end)
            end
        end

        local autoHop = pageBuilders.pages.AutoHop
        local hopLeft = section(autoHop, "AUTO HOP", UDim2.new(0.5, -8, 0, 0))
        hopLeft.Position = UDim2.fromOffset(0, 0)
        toggle(hopLeft, "Enable Auto Hop", "Placeholder until TeleportService server logic is confirmed", function() return runtime.autoHopEnabled == true end, function(v) runtime.autoHopEnabled = v end)
        slider(hopLeft, "Delay", function() return runtime.autoHopDelay or 30 end, function(v) runtime.autoHopDelay = v end, 5, 300, 5, " sec")
        button(hopLeft, "Start", "Start Auto Hop placeholder", function() warn("[FIGGY] Auto Hop Start requires confirmed TeleportService logic") end)
        button(hopLeft, "Stop", "Stop Auto Hop placeholder", function() runtime.autoHopEnabled = false end)

        local hopRight = section(autoHop, "SERVER RULES", UDim2.new(0.5, -8, 0, 0))
        hopRight.Position = UDim2.new(0.5, 8, 0, 0)
        methodButton(hopRight, "Hop Mode", {"Lowest Player Count", "Same Region", "Random Server"}, function() return "Lowest Player Count" end, function(v) warn("[FIGGY] Hop mode placeholder: " .. tostring(v)) end)

        local player = pageBuilders.pages.Player
        local playerSection = section(player, "PLAYER", UDim2.new(1, 0, 0, 0))
        button(playerSection, "Set Standby Here", "Use the local HumanoidRootPart position", function()
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root then runtime.standbyPosition = root.Position; if PathService then PathService.Invalidate() end end
        end)
        toggle(playerSection, "Walk Guard Zone", "Use slower guard-zone movement", function() return runtime.guardZoneForceWalk == true end, function(v) runtime.guardZoneForceWalk = v end)
        slider(playerSection, "Tween Speed", function() return runtime.tweenSpeed or 700 end, function(v) runtime.tweenSpeed = v end, 300, 1000, 50, "")
        button(playerSection, "Reset Character Motion", "Cancel active tween and walking", function()
            if Movement and Movement.Reset then Movement.Reset() end
        end)

        local settings = pageBuilders.pages.Settings
        local settingsLeft = section(settings, "DISPLAY", UDim2.new(0.5, -8, 0, 0))
        settingsLeft.Position = UDim2.fromOffset(0, 0)
        methodButton(settingsLeft, "Theme", {"Dark", "Midnight", "System"}, function() return runtime.uiTheme or "Dark" end, function(v) runtime.uiTheme = v end)
        methodButton(settingsLeft, "Language", {"English", "Vietnamese"}, function() return runtime.uiLanguage or "English" end, function(v) runtime.uiLanguage = v end)
        slider(settingsLeft, "UI Scale", function() return runtime.uiScale or 100 end, function(v) runtime.uiScale = v end, 75, 125, 5, "%")
        toggle(settingsLeft, "FPS Display", "Placeholder performance display", function() return runtime.showFps == true end, function(v) runtime.showFps = v end)
        toggle(settingsLeft, "Performance Mode", "Reduce UI refresh work", function() return runtime.performanceMode == true end, function(v) runtime.performanceMode = v end)

        local settingsRight = section(settings, "CONFIGURATION", UDim2.new(0.5, -8, 0, 0))
        settingsRight.Position = UDim2.new(0.5, 8, 0, 0)
        button(settingsRight, "Save Configuration", "Placeholder: local config storage", function() warn("[FIGGY] Save Configuration requires writefile support") end)
        button(settingsRight, "Load Configuration", "Placeholder: local config storage", function() warn("[FIGGY] Load Configuration requires readfile support") end)
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
                        local statusCard = window:FindFirstChild("Status", true)
                        if statusCard then
                            for _, child in ipairs(statusCard:GetChildren()) do
                                if child:IsA("TextLabel") then
                                    child.Text = formatStatus()
                                    break
                                end
                            end
                        end
                    end
                end)
                task.wait(runtime.hubStatusRefreshInterval or 1)
            end
        end)
    end

    local function stopStatusLoop()
        statusRunning = false
    end

    local inputConnection
    local attachKeybind

    local function SetVisible(value)
        runtime.hubVisible = value == true
        visible = runtime.hubVisible

        if window then
            local ok = pcall(function()
                window.Visible = visible
            end)

            if not ok then
                warn("[FIGGY] Cannot change window visibility")
            end
        end
    end

    local function ToggleVisible()
        SetVisible(not visible)
        return visible
    end

    local function start()
        local ok, err = runWithPluginIdentity(function()
            makeWindow()
            attachKeybind()
            SetVisible(runtime.hubVisible ~= false)
        end)

        if not ok then
            warn("[FIGGY] Start fallback: " .. tostring(err))

            local fallbackOk = pcall(function()
                makeWindow()
            end)

            if fallbackOk then
                SetVisible(runtime.hubVisible ~= false)
                attachKeybind()
            end
        end

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

    attachKeybind = function()
        if inputConnection then return end
        inputConnection = game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
            if not processed and input.KeyCode == (runtime.hubToggleKey or Enum.KeyCode.G) then
                ToggleVisible()
            end
        end)
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
