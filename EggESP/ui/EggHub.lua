--[[
    VENYX Steal An Egg UI Hub
    Modern, high-fidelity Roblox GUI matching Venyx v1.7.2 style.
    No VoidUI dependency required.
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
    local UserInputService = deps.UserInputService or game:GetService("UserInputService")
    local RunService = deps.RunService or game:GetService("RunService")
    local TweenService = game:GetService("TweenService")

    local runtime = Config.Runtime
    local callbacks = {}
    local gui
    local window
    local visible = runtime.hubVisible ~= false
    local statusTask
    local statusRunning = false
    local inputConnection
    local activeDropdownMenu = nil

    -- Runtime defaults for Venyx options if not already set
    if runtime.moveToEggMethod == nil then runtime.moveToEggMethod = "Teleport" end
    if runtime.deliveryMethod == nil then runtime.deliveryMethod = "Quick steps" end
    if runtime.autoFarmPriority == nil then runtime.autoFarmPriority = "Best value" end
    if runtime.autoFarmMinValuePerSec == nil then runtime.autoFarmMinValuePerSec = 441000000 end -- 441M/s
    if runtime.autoFarmMaxValuePerSec == nil then runtime.autoFarmMaxValuePerSec = 14000000000 end -- 14B/s
    if runtime.autoHopDelay == nil then runtime.autoHopDelay = 30 end
    if runtime.autoHopMode == nil then runtime.autoHopMode = "Lowest Player Count" end
    if runtime.uiLanguage == nil then runtime.uiLanguage = "English" end
    if runtime.whitelistEggNames == nil then
        runtime.whitelistEggNames = { ArchAngel = true }
    end
    if runtime.teleportZones == nil then
        runtime.teleportZones = { ["Cherry Blossom"] = true }
    end
    if runtime.uiMutationSelection == nil then
        runtime.uiMutationSelection = { None = true }
    end
    if runtime.uiRaritySelection == nil then
        runtime.uiRaritySelection = { Divine = true }
    end
    if runtime.uiZoneSelection == nil then
        runtime.uiZoneSelection = { Alien = true }
    end

    -- Venyx Dark Theme Palette
    local colors = {
        bg = Color3.fromRGB(14, 15, 19),
        sidebar = Color3.fromRGB(11, 12, 16),
        panel = Color3.fromRGB(20, 22, 28),
        panelBorder = Color3.fromRGB(34, 37, 48),
        card = Color3.fromRGB(24, 26, 34),
        cardBorder = Color3.fromRGB(38, 42, 54),
        control = Color3.fromRGB(30, 33, 44),
        controlBorder = Color3.fromRGB(46, 51, 68),
        controlHover = Color3.fromRGB(38, 42, 56),
        badgeBg = Color3.fromRGB(36, 40, 54),
        badgeBorder = Color3.fromRGB(50, 55, 74),
        text = Color3.fromRGB(242, 244, 250),
        muted = Color3.fromRGB(132, 137, 156),
        subtext = Color3.fromRGB(90, 95, 115),
        accent = Color3.fromRGB(99, 102, 241),      -- Sleek Indigo/Purple
        accentGlow = Color3.fromRGB(129, 140, 248),
        toggleActive = Color3.fromRGB(79, 70, 229),
        toggleInactive = Color3.fromRGB(34, 37, 50),
        knob = Color3.fromRGB(255, 255, 255),
        green = Color3.fromRGB(46, 204, 113),
        star = Color3.fromRGB(245, 158, 11),
        red = Color3.fromRGB(239, 68, 68),
    }

    local function runWithPluginIdentity(fn)
        if type(fn) ~= "function" then return false end
        local previous
        if type(getthreadidentity) == "function" then
            local ok, id = pcall(getthreadidentity)
            if ok then previous = id end
        end
        if type(setthreadidentity) == "function" then
            pcall(setthreadidentity, 8)
        end
        local ok, result = pcall(fn)
        if type(setthreadidentity) == "function" and previous ~= nil then
            pcall(setthreadidentity, previous)
        end
        if not ok then
            warn("[VENYX] UI callback error: " .. tostring(result))
            return false, result
        end
        return true, result
    end

    local function corner(parent, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius or 8)
        c.Parent = parent
        return c
    end

    local function stroke(parent, color, thickness, transparency)
        local s = Instance.new("UIStroke")
        s.Color = color or colors.panelBorder
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = parent
        return s
    end

    local function text(parent, textValue, size, color, font, position, dimensions)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Font = font or Enum.Font.GothamSemibold
        l.Text = textValue or ""
        l.TextSize = size or 12
        l.TextColor3 = color or colors.text
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextYAlignment = Enum.TextYAlignment.Center
        l.Position = position or UDim2.fromOffset(0, 0)
        l.Size = dimensions or UDim2.fromScale(1, 1)
        l.Parent = parent
        return l
    end

    -- Format numbers to M/s, B/s, k/s for sliders
    local function formatPerSec(num)
        if type(num) ~= "number" then return "0/s" end
        if num >= 1e12 then
            return string.format("%.1fT/s", num / 1e12):gsub("%.0T/s", "T/s")
        elseif num >= 1e9 then
            return string.format("%.0fB/s", num / 1e9)
        elseif num >= 1e6 then
            return string.format("%.0fM/s", num / 1e6)
        elseif num >= 1e3 then
            return string.format("%.0fk/s", num / 1e3)
        else
            return string.format("%d/s", math.floor(num))
        end
    end

    local function closeActiveDropdown()
        if activeDropdownMenu and activeDropdownMenu.Parent then
            activeDropdownMenu:Destroy()
            activeDropdownMenu = nil
        end
    end

    local function ensureGui()
        if gui and gui.Parent then return gui end
        gui = Instance.new("ScreenGui")
        gui.Name = "VENYXHub"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 100
        pcall(function() gui.Parent = game:GetService("CoreGui") end)
        if not gui.Parent then
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
        return gui
    end

    local pageFrames = {}
    local navButtons = {}
    local currentTabId = "Steal"
    local currentStealSubTab = "AutoSteal"
    local statusPillText
    local stealSubTabAutoStealBtn
    local stealSubTabPredictorBtn
    local stealSubPageAutoSteal
    local stealSubPagePredictor

    local function makeWindow()
        if window and window.Parent then return window end
        ensureGui()

        -- Dismiss open dropdown if clicking anywhere in window
        local overlayDismiss = Instance.new("TextButton")
        overlayDismiss.Name = "OverlayDismiss"
        overlayDismiss.BackgroundTransparency = 1
        overlayDismiss.Size = UDim2.fromScale(1, 1)
        overlayDismiss.Text = ""
        overlayDismiss.ZIndex = 40
        overlayDismiss.Visible = false
        overlayDismiss.Parent = gui
        overlayDismiss.Activated:Connect(function()
            closeActiveDropdown()
            overlayDismiss.Visible = false
        end)

        -- Main Window Frame
        window = Instance.new("Frame")
        window.Name = "MainWindow"
        window.AnchorPoint = Vector2.new(0.5, 0.5)
        window.Position = UDim2.new(0.5, 0, 0.5, 0)
        window.Size = UDim2.fromOffset(920, 580)
        window.BackgroundColor3 = colors.bg
        window.BorderSizePixel = 0
        window.Visible = visible
        window.ClipsDescendants = false
        window.ZIndex = 1
        window.Parent = gui
        corner(window, 12)
        stroke(window, colors.panelBorder, 1)

        -- Soft Drop Shadow
        local shadow = Instance.new("ImageLabel")
        shadow.Name = "Shadow"
        shadow.AnchorPoint = Vector2.new(0.5, 0.5)
        shadow.Position = UDim2.fromScale(0.5, 0.5)
        shadow.Size = UDim2.new(1, 36, 1, 36)
        shadow.BackgroundTransparency = 1
        shadow.Image = "rbxassetid://6015897843"
        shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
        shadow.ImageTransparency = 0.45
        shadow.ScaleType = Enum.ScaleType.Slice
        shadow.SliceCenter = Rect.new(10, 10, 118, 118)
        shadow.ZIndex = 0
        shadow.Parent = window

        -- Window Dragging Logic
        do
            local dragging = false
            local dragStart
            local startPos

            window.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 and input.Position.Y - window.AbsolutePosition.Y <= 52 then
                    dragging = true
                    dragStart = input.Position
                    startPos = window.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            dragging = false
                        end
                    end)
                end
            end)

            window.InputChanged:Connect(function(input)
                if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local delta = input.Position - dragStart
                    window.Position = UDim2.new(
                        startPos.X.Scale,
                        startPos.X.Offset + delta.X,
                        startPos.Y.Scale,
                        startPos.Y.Offset + delta.Y
                    )
                end
            end)
        end

        ---------------------------------------------------------------------
        -- TOP BAR (Header)
        ---------------------------------------------------------------------
        local topBar = Instance.new("Frame")
        topBar.Name = "TopBar"
        topBar.Size = UDim2.new(1, 0, 0, 52)
        topBar.BackgroundColor3 = colors.sidebar
        topBar.BorderSizePixel = 0
        topBar.ZIndex = 2
        topBar.Parent = window
        corner(topBar, 12)

        -- Square bottom corners for header
        local topBarCover = Instance.new("Frame")
        topBarCover.Position = UDim2.new(0, 0, 1, -8)
        topBarCover.Size = UDim2.new(1, 0, 0, 8)
        topBarCover.BackgroundColor3 = colors.sidebar
        topBarCover.BorderSizePixel = 0
        topBarCover.ZIndex = 2
        topBarCover.Parent = topBar

        local headerLine = Instance.new("Frame")
        headerLine.Position = UDim2.new(0, 0, 1, 0)
        headerLine.Size = UDim2.new(1, 0, 0, 1)
        headerLine.BackgroundColor3 = colors.panelBorder
        headerLine.BorderSizePixel = 0
        headerLine.ZIndex = 3
        headerLine.Parent = topBar

        -- Left Brand: Vx Logo + VENYX / Steal An Egg v1.7.2
        local brandContainer = Instance.new("Frame")
        brandContainer.BackgroundTransparency = 1
        brandContainer.Position = UDim2.fromOffset(14, 0)
        brandContainer.Size = UDim2.new(0, 500, 1, 0)
        brandContainer.ZIndex = 3
        brandContainer.Parent = topBar

        local brandLayout = Instance.new("UIListLayout")
        brandLayout.FillDirection = Enum.FillDirection.Horizontal
        brandLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        brandLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
        brandLayout.Padding = UDim.new(0, 8)
        brandLayout.SortOrder = Enum.SortOrder.LayoutOrder
        brandLayout.Parent = brandContainer

        -- Stylized Vx Logo
        local logoBox = Instance.new("Frame")
        logoBox.LayoutOrder = 1
        logoBox.Size = UDim2.fromOffset(26, 26)
        logoBox.BackgroundColor3 = Color3.fromRGB(24, 26, 36)
        logoBox.BorderSizePixel = 0
        logoBox.ZIndex = 4
        logoBox.Parent = brandContainer
        corner(logoBox, 6)
        stroke(logoBox, colors.panelBorder, 1)

        local logoText = text(logoBox, "Vx", 13, colors.text, Enum.Font.GothamBlack)
        logoText.TextXAlignment = Enum.TextXAlignment.Center

        -- "VENYX" Title
        local venyxLabel = text(brandContainer, "VENYX", 14, colors.text, Enum.Font.GothamBold)
        venyxLabel.LayoutOrder = 2
        venyxLabel.Size = UDim2.fromOffset(56, 26)

        -- "/" Separator
        local sepLabel = text(brandContainer, "/", 13, colors.subtext, Enum.Font.GothamBold)
        sepLabel.LayoutOrder = 3
        sepLabel.Size = UDim2.fromOffset(8, 26)

        -- "Steal An Egg" Subtitle
        local gameLabel = text(brandContainer, "Steal An Egg", 13, colors.muted, Enum.Font.GothamSemibold)
        gameLabel.LayoutOrder = 4
        gameLabel.Size = UDim2.fromOffset(84, 26)

        -- "v1.7.2" Version Badge
        local verBadge = Instance.new("Frame")
        verBadge.LayoutOrder = 5
        verBadge.Size = UDim2.fromOffset(46, 20)
        verBadge.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
        verBadge.BorderSizePixel = 0
        verBadge.ZIndex = 4
        verBadge.Parent = brandContainer
        corner(verBadge, 5)
        stroke(verBadge, colors.panelBorder, 1)

        local verLabel = text(verBadge, "v1.7.2", 10, colors.muted, Enum.Font.GothamMedium)
        verLabel.TextXAlignment = Enum.TextXAlignment.Center

        -- Live Status Pill: "● Caught Void Pearl x19"
        local statusPill = Instance.new("Frame")
        statusPill.LayoutOrder = 6
        statusPill.Size = UDim2.fromOffset(170, 24)
        statusPill.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
        statusPill.BorderSizePixel = 0
        statusPill.ZIndex = 4
        statusPill.Parent = brandContainer
        corner(statusPill, 12)
        stroke(statusPill, colors.cardBorder, 1)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.fromOffset(7, 7)
        dot.Position = UDim2.fromOffset(10, 8.5)
        dot.BackgroundColor3 = colors.green
        dot.BorderSizePixel = 0
        dot.ZIndex = 5
        dot.Parent = statusPill
        corner(dot, 4)

        statusPillText = text(statusPill, "Caught Void Pearl x19", 11, colors.text, Enum.Font.GothamMedium, UDim2.fromOffset(23, 0), UDim2.new(1, -28, 1, 0))

        -- Top Right Actions: Language, Search, Minimize, Close
        local topActions = Instance.new("Frame")
        topActions.BackgroundTransparency = 1
        topActions.AnchorPoint = Vector2.new(1, 0.5)
        topActions.Position = UDim2.new(1, -12, 0.5, 0)
        topActions.Size = UDim2.fromOffset(360, 32)
        topActions.ZIndex = 3
        topActions.Parent = topBar

        local topActionsLayout = Instance.new("UIListLayout")
        topActionsLayout.FillDirection = Enum.FillDirection.Horizontal
        topActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
        topActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        topActionsLayout.Padding = UDim.new(0, 8)
        topActionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        topActionsLayout.Parent = topActions

        -- Language Selector Pill: "文A English"
        local langBtn = Instance.new("TextButton")
        langBtn.LayoutOrder = 1
        langBtn.Size = UDim2.fromOffset(88, 28)
        langBtn.BackgroundColor3 = colors.panel
        langBtn.BorderSizePixel = 0
        langBtn.Text = "文A  " .. (runtime.uiLanguage or "English")
        langBtn.Font = Enum.Font.GothamSemibold
        langBtn.TextSize = 11
        langBtn.TextColor3 = colors.text
        langBtn.AutoButtonColor = false
        langBtn.ZIndex = 4
        langBtn.Parent = topActions
        corner(langBtn, 7)
        stroke(langBtn, colors.cardBorder, 1)

        langBtn.Activated:Connect(function()
            if runtime.uiLanguage == "English" then
                runtime.uiLanguage = "Tiếng Việt"
            else
                runtime.uiLanguage = "English"
            end
            langBtn.Text = "文A  " .. runtime.uiLanguage
        end)

        -- Search Bar: "🔍 Search"
        local searchContainer = Instance.new("Frame")
        searchContainer.LayoutOrder = 2
        searchContainer.Size = UDim2.fromOffset(130, 28)
        searchContainer.BackgroundColor3 = colors.panel
        searchContainer.BorderSizePixel = 0
        searchContainer.ZIndex = 4
        searchContainer.Parent = topActions
        corner(searchContainer, 7)
        stroke(searchContainer, colors.cardBorder, 1)

        local searchBox = Instance.new("TextBox")
        searchBox.Size = UDim2.new(1, -16, 1, 0)
        searchBox.Position = UDim2.fromOffset(10, 0)
        searchBox.BackgroundTransparency = 1
        searchBox.PlaceholderText = "🔍 Search"
        searchBox.PlaceholderColor3 = colors.muted
        searchBox.Text = ""
        searchBox.Font = Enum.Font.GothamSemibold
        searchBox.TextSize = 11
        searchBox.TextColor3 = colors.text
        searchBox.ClearTextOnFocus = false
        searchBox.ZIndex = 5
        searchBox.Parent = searchContainer

        -- Search filtering logic across visible cards/rows
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local query = tostring(searchBox.Text):lower():gsub("^%s*(.-)%s*$", "%1")
            local activePage = pageFrames[currentTabId]
            if not activePage then return end

            for _, desc in ipairs(activePage:GetDescendants()) do
                if desc:IsA("Frame") and desc:FindFirstChild("__IS_CONTROL_ROW") then
                    local rowTitle = desc:FindFirstChild("__ROW_TITLE")
                    if rowTitle and rowTitle:IsA("TextLabel") then
                        local t = rowTitle.Text:lower()
                        desc.Visible = query == "" or t:find(query, 1, true) ~= nil
                    end
                end
            end
        end)

        -- Minimize Button
        local minBtn = Instance.new("TextButton")
        minBtn.LayoutOrder = 3
        minBtn.Size = UDim2.fromOffset(28, 28)
        minBtn.BackgroundColor3 = colors.panel
        minBtn.BorderSizePixel = 0
        minBtn.Text = "—"
        minBtn.Font = Enum.Font.GothamBold
        minBtn.TextSize = 12
        minBtn.TextColor3 = colors.muted
        minBtn.AutoButtonColor = false
        minBtn.ZIndex = 4
        minBtn.Parent = topActions
        corner(minBtn, 7)
        stroke(minBtn, colors.cardBorder, 1)

        minBtn.Activated:Connect(function()
            window.Visible = false
            visible = false
            runtime.hubVisible = false
        end)

        -- Close Button
        local closeBtn = Instance.new("TextButton")
        closeBtn.LayoutOrder = 4
        closeBtn.Size = UDim2.fromOffset(28, 28)
        closeBtn.BackgroundColor3 = colors.panel
        closeBtn.BorderSizePixel = 0
        closeBtn.Text = "×"
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextSize = 15
        closeBtn.TextColor3 = colors.muted
        closeBtn.AutoButtonColor = false
        closeBtn.ZIndex = 4
        closeBtn.Parent = topActions
        corner(closeBtn, 7)
        stroke(closeBtn, colors.cardBorder, 1)

        closeBtn.Activated:Connect(function()
            window.Visible = false
            visible = false
            runtime.hubVisible = false
        end)

        ---------------------------------------------------------------------
        -- SIDEBAR (Left Icons)
        ---------------------------------------------------------------------
        local sidebar = Instance.new("Frame")
        sidebar.Name = "Sidebar"
        sidebar.Position = UDim2.fromOffset(0, 52)
        sidebar.Size = UDim2.new(0, 60, 1, -52)
        sidebar.BackgroundColor3 = colors.sidebar
        sidebar.BorderSizePixel = 0
        sidebar.ZIndex = 2
        sidebar.Parent = window

        local sidebarLine = Instance.new("Frame")
        sidebarLine.Position = UDim2.new(1, 0, 0, 0)
        sidebarLine.Size = UDim2.new(0, 1, 1, 0)
        sidebarLine.BackgroundColor3 = colors.panelBorder
        sidebarLine.BorderSizePixel = 0
        sidebarLine.ZIndex = 3
        sidebarLine.Parent = sidebar

        local navList = Instance.new("Frame")
        navList.BackgroundTransparency = 1
        navList.Position = UDim2.fromOffset(7, 14)
        navList.Size = UDim2.new(1, -14, 1, -80)
        navList.ZIndex = 3
        navList.Parent = sidebar

        local navLayout = Instance.new("UIListLayout")
        navLayout.FillDirection = Enum.FillDirection.Vertical
        navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        navLayout.Padding = UDim.new(0, 8)
        navLayout.SortOrder = Enum.SortOrder.LayoutOrder
        navLayout.Parent = navList

        local tabsData = {
            { id = "Home", icon = "⌂", title = "Home" },
            { id = "Steal", icon = "🥚", title = "Steal" },
            { id = "Pet", icon = "🌱", title = "Pets" },
            { id = "ESP", icon = "✨", title = "Visuals" },
            { id = "Player", icon = "👤", title = "Player" },
            { id = "Settings", icon = "⚙", title = "Settings" },
        }

        local function updateSidebarSelection(selectedId)
            currentTabId = selectedId
            for id, btn in pairs(navButtons) do
                local isSel = id == selectedId
                btn.BackgroundColor3 = isSel and Color3.fromRGB(28, 30, 42) or Color3.fromRGB(11, 12, 16)
                local btnStroke = btn:FindFirstChildOfClass("UIStroke")
                if btnStroke then
                    btnStroke.Color = isSel and Color3.fromRGB(58, 62, 84) or Color3.fromRGB(11, 12, 16)
                    btnStroke.Transparency = isSel and 0 or 1
                end
                local iconLbl = btn:FindFirstChildOfClass("TextLabel")
                if iconLbl then
                    iconLbl.TextColor3 = isSel and colors.text or colors.muted
                end
            end
            for id, page in pairs(pageFrames) do
                page.Visible = id == selectedId
            end
            closeActiveDropdown()
        end

        for idx, tabInfo in ipairs(tabsData) do
            local btn = Instance.new("TextButton")
            btn.Name = tabInfo.id .. "NavBtn"
            btn.LayoutOrder = idx
            btn.Size = UDim2.fromOffset(42, 42)
            btn.BackgroundColor3 = tabInfo.id == "Steal" and Color3.fromRGB(28, 30, 42) or Color3.fromRGB(11, 12, 16)
            btn.BorderSizePixel = 0
            btn.Text = ""
            btn.AutoButtonColor = false
            btn.ZIndex = 4
            btn.Parent = navList
            corner(btn, 12)
            local s = stroke(btn, Color3.fromRGB(58, 62, 84), 1)
            s.Transparency = tabInfo.id == "Steal" and 0 or 1

            local iconLbl = text(btn, tabInfo.icon, 18, tabInfo.id == "Steal" and colors.text or colors.muted)
            iconLbl.TextXAlignment = Enum.TextXAlignment.Center

            btn.Activated:Connect(function()
                runWithPluginIdentity(function()
                    updateSidebarSelection(tabInfo.id)
                end)
            end)

            navButtons[tabInfo.id] = btn
        end

        -- Bottom Avatar: User Headshot
        local avatarFrame = Instance.new("Frame")
        avatarFrame.AnchorPoint = Vector2.new(0.5, 1)
        avatarFrame.Position = UDim2.new(0.5, 0, 1, -12)
        avatarFrame.Size = UDim2.fromOffset(36, 36)
        avatarFrame.BackgroundColor3 = colors.card
        avatarFrame.BorderSizePixel = 0
        avatarFrame.ZIndex = 4
        avatarFrame.Parent = sidebar
        corner(avatarFrame, 18)
        stroke(avatarFrame, colors.cardBorder, 1)

        local avatarImg = Instance.new("ImageLabel")
        avatarImg.Size = UDim2.fromScale(1, 1)
        avatarImg.BackgroundTransparency = 1
        avatarImg.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", LocalPlayer.UserId)
        avatarImg.ZIndex = 5
        avatarImg.Parent = avatarFrame
        corner(avatarImg, 18)

        ---------------------------------------------------------------------
        -- MAIN CONTENT AREA
        ---------------------------------------------------------------------
        local mainArea = Instance.new("Frame")
        mainArea.Name = "MainArea"
        mainArea.Position = UDim2.fromOffset(61, 52)
        mainArea.Size = UDim2.new(1, -61, 1, -52)
        mainArea.BackgroundColor3 = colors.bg
        mainArea.BorderSizePixel = 0
        mainArea.ZIndex = 2
        mainArea.Parent = window

        -- Overlay container for floating dropdown menus
        local overlay = Instance.new("Frame")
        overlay.Name = "DropdownOverlay"
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.BackgroundTransparency = 1
        overlay.ZIndex = 50
        overlay.Parent = window

        ---------------------------------------------------------------------
        -- HELPER COMPONENT BUILDERS (Matching Venyx UI precisely)
        ---------------------------------------------------------------------

        -- Collapsible Section Card
        local function createCard(parent, title, iconSymbol, defaultCollapsed)
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, 0, 0, 0)
            card.AutomaticSize = Enum.AutomaticSize.Y
            card.BackgroundColor3 = colors.panel
            card.BorderSizePixel = 0
            card.ZIndex = 3
            card.Parent = parent
            corner(card, 12)
            stroke(card, colors.panelBorder, 1)

            local cardHeader = Instance.new("TextButton")
            cardHeader.Size = UDim2.new(1, 0, 0, 42)
            cardHeader.BackgroundTransparency = 1
            cardHeader.Text = ""
            cardHeader.AutoButtonColor = false
            cardHeader.ZIndex = 4
            cardHeader.Parent = card

            local headerTitle = text(cardHeader, (iconSymbol and (iconSymbol .. "  ") or "") .. title, 12, colors.text, Enum.Font.GothamBold, UDim2.fromOffset(16, 0), UDim2.new(1, -50, 1, 0))

            local chevron = text(cardHeader, defaultCollapsed and "›" or "⌄", 15, colors.muted, Enum.Font.GothamBold, UDim2.new(1, -30, 0, 0), UDim2.fromOffset(20, 42))
            chevron.TextXAlignment = Enum.TextXAlignment.Center

            local body = Instance.new("Frame")
            body.Name = "CardBody"
            body.Position = UDim2.fromOffset(0, 42)
            body.Size = UDim2.new(1, 0, 0, 0)
            body.AutomaticSize = Enum.AutomaticSize.Y
            body.BackgroundTransparency = 1
            body.Visible = not defaultCollapsed
            body.ZIndex = 4
            body.Parent = card

            local bodyLayout = Instance.new("UIListLayout")
            bodyLayout.Padding = UDim.new(0, 6)
            bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
            bodyLayout.Parent = body

            local bodyPadding = Instance.new("UIPadding")
            bodyPadding.PaddingTop = UDim.new(0, 4)
            bodyPadding.PaddingBottom = UDim.new(0, 14)
            bodyPadding.PaddingLeft = UDim.new(0, 16)
            bodyPadding.PaddingRight = UDim.new(0, 16)
            bodyPadding.Parent = body

            cardHeader.Activated:Connect(function()
                closeActiveDropdown()
                body.Visible = not body.Visible
                chevron.Text = body.Visible and "⌄" or "›"
            end)

            return card, body
        end

        -- Row Container with Title
        local function createRow(parent, labelText)
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 36)
            row.BackgroundTransparency = 1
            row.BorderSizePixel = 0
            row.ZIndex = 5
            row.Parent = parent

            local mark = Instance.new("Folder")
            mark.Name = "__IS_CONTROL_ROW"
            mark.Parent = row

            local title = text(row, labelText, 12, colors.text, Enum.Font.GothamSemibold, UDim2.fromOffset(0, 0), UDim2.new(0.48, 0, 1, 0))
            title.Name = "__ROW_TITLE"

            local rightSlot = Instance.new("Frame")
            rightSlot.AnchorPoint = Vector2.new(1, 0.5)
            rightSlot.Position = UDim2.new(1, 0, 0.5, 0)
            rightSlot.Size = UDim2.new(0.52, 0, 1, 0)
            rightSlot.BackgroundTransparency = 1
            rightSlot.ZIndex = 5
            rightSlot.Parent = row

            return row, rightSlot
        end

        -- Modern Toggle Switch (Pill with circular knob)
        local function addToggle(parent, labelText, getValue, setValue)
            local row, rightSlot = createRow(parent, labelText)

            local switch = Instance.new("TextButton")
            switch.AnchorPoint = Vector2.new(1, 0.5)
            switch.Position = UDim2.new(1, 0, 0.5, 0)
            switch.Size = UDim2.fromOffset(42, 22)
            switch.BackgroundColor3 = colors.toggleInactive
            switch.BorderSizePixel = 0
            switch.Text = ""
            switch.AutoButtonColor = false
            switch.ZIndex = 6
            switch.Parent = rightSlot
            corner(switch, 11)
            stroke(switch, colors.cardBorder, 1)

            local knob = Instance.new("Frame")
            knob.Size = UDim2.fromOffset(16, 16)
            knob.Position = UDim2.fromOffset(3, 3)
            knob.BackgroundColor3 = colors.knob
            knob.BorderSizePixel = 0
            knob.ZIndex = 7
            knob.Parent = switch
            corner(knob, 8)

            local function updateVisual(enabled)
                if enabled then
                    switch.BackgroundColor3 = colors.toggleActive
                    knob.Position = UDim2.fromOffset(23, 3)
                else
                    switch.BackgroundColor3 = colors.toggleInactive
                    knob.Position = UDim2.fromOffset(3, 3)
                end
            end

            updateVisual(getValue() == true)

            local function trigger()
                runWithPluginIdentity(function()
                    local current = getValue() == true
                    local nextState = not current
                    setValue(nextState)
                    updateVisual(nextState)
                end)
            end

            switch.Activated:Connect(trigger)
            return row
        end

        -- Dropdown Button with Badges ("Cherry Blossom +4 ⌄")
        local function addDropdown(parent, labelText, options, isMultiSelect, getSelection, setSelection)
            local row, rightSlot = createRow(parent, labelText)

            local btn = Instance.new("TextButton")
            btn.AnchorPoint = Vector2.new(1, 0.5)
            btn.Position = UDim2.new(1, 0, 0.5, 0)
            btn.Size = UDim2.fromOffset(160, 28)
            btn.BackgroundColor3 = colors.control
            btn.BorderSizePixel = 0
            btn.Text = ""
            btn.AutoButtonColor = false
            btn.ZIndex = 6
            btn.Parent = rightSlot
            corner(btn, 7)
            stroke(btn, colors.controlBorder, 1)

            local btnContent = Instance.new("Frame")
            btnContent.Size = UDim2.new(1, -16, 1, 0)
            btnContent.Position = UDim2.fromOffset(10, 0)
            btnContent.BackgroundTransparency = 1
            btnContent.ZIndex = 7
            btnContent.Parent = btn

            local btnLayout = Instance.new("UIListLayout")
            btnLayout.FillDirection = Enum.FillDirection.Horizontal
            btnLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
            btnLayout.Padding = UDim.new(0, 6)
            btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
            btnLayout.Parent = btnContent

            local valLabel = text(btnContent, "", 11, colors.text, Enum.Font.GothamMedium)
            valLabel.LayoutOrder = 1
            valLabel.Size = UDim2.fromOffset(80, 24)
            valLabel.ClipsDescendants = true

            local badgePill = Instance.new("Frame")
            badgePill.LayoutOrder = 2
            badgePill.Size = UDim2.fromOffset(26, 17)
            badgePill.BackgroundColor3 = colors.badgeBg
            badgePill.BorderSizePixel = 0
            badgePill.Visible = false
            badgePill.ZIndex = 8
            badgePill.Parent = btnContent
            corner(badgePill, 5)
            stroke(badgePill, colors.badgeBorder, 1)

            local badgeText = text(badgePill, "+0", 9, colors.muted, Enum.Font.GothamBold)
            badgeText.TextXAlignment = Enum.TextXAlignment.Center

            local chevron = text(btn, "⌄", 12, colors.muted, Enum.Font.GothamBold, UDim2.new(1, -18, 0, 0), UDim2.fromOffset(14, 28))
            chevron.TextXAlignment = Enum.TextXAlignment.Center
            chevron.ZIndex = 7

            local function refreshButtonDisplay()
                if isMultiSelect then
                    local sel = getSelection() or {}
                    local selectedList = {}
                    for _, opt in ipairs(options) do
                        local key = type(opt) == "table" and (opt.id or opt.label) or tostring(opt)
                        if sel[key] == true then
                            table.insert(selectedList, type(opt) == "table" and opt.label or key)
                        end
                    end
                    if #selectedList == 0 then
                        valLabel.Text = "None"
                        badgePill.Visible = false
                    elseif #selectedList == 1 then
                        valLabel.Text = selectedList[1]
                        badgePill.Visible = false
                    else
                        valLabel.Text = selectedList[1]
                        badgePill.Visible = true
                        badgeText.Text = "+" .. tostring(#selectedList - 1)
                    end
                else
                    valLabel.Text = tostring(getSelection() or options[1] or "None")
                    badgePill.Visible = false
                end
            end

            refreshButtonDisplay()

            -- Open Dropdown Floating Menu
            btn.Activated:Connect(function()
                if activeDropdownMenu and activeDropdownMenu.Name == labelText .. "DropdownMenu" then
                    closeActiveDropdown()
                    return
                end
                closeActiveDropdown()

                overlayDismiss.Visible = true

                local absPos = btn.AbsolutePosition
                local absSize = btn.AbsoluteSize

                local menu = Instance.new("Frame")
                menu.Name = labelText .. "DropdownMenu"
                menu.Size = UDim2.fromOffset(math.max(170, absSize.X + 20), math.min(220, #options * 32 + 12))
                menu.Position = UDim2.fromOffset(absPos.X - window.AbsolutePosition.X, absPos.Y - window.AbsolutePosition.Y + absSize.Y + 4)
                menu.BackgroundColor3 = colors.card
                menu.BorderSizePixel = 0
                menu.ZIndex = 60
                menu.Parent = overlay
                corner(menu, 8)
                stroke(menu, colors.cardBorder, 1)

                activeDropdownMenu = menu

                local scroll = Instance.new("ScrollingFrame")
                scroll.Size = UDim2.new(1, -6, 1, -8)
                scroll.Position = UDim2.fromOffset(3, 4)
                scroll.BackgroundTransparency = 1
                scroll.BorderSizePixel = 0
                scroll.ScrollBarThickness = 3
                scroll.ScrollBarImageColor3 = colors.accent
                scroll.CanvasSize = UDim2.fromOffset(0, #options * 32)
                scroll.ZIndex = 61
                scroll.Parent = menu

                local mLayout = Instance.new("UIListLayout")
                mLayout.Padding = UDim.new(0, 2)
                mLayout.SortOrder = Enum.SortOrder.LayoutOrder
                mLayout.Parent = scroll

                for _, opt in ipairs(options) do
                    local optKey = type(opt) == "table" and (opt.id or opt.label) or tostring(opt)
                    local optLabel = type(opt) == "table" and opt.label or optKey

                    local item = Instance.new("TextButton")
                    item.Size = UDim2.new(1, 0, 0, 30)
                    item.BackgroundColor3 = colors.card
                    item.BorderSizePixel = 0
                    item.Text = ""
                    item.AutoButtonColor = false
                    item.ZIndex = 62
                    item.Parent = scroll
                    corner(item, 6)

                    local itemText = text(item, optLabel, 11, colors.text, Enum.Font.GothamMedium, UDim2.fromOffset(26, 0), UDim2.new(1, -30, 1, 0))
                    itemText.ZIndex = 63

                    local indicator = Instance.new("Frame")
                    indicator.Size = UDim2.fromOffset(12, 12)
                    indicator.Position = UDim2.fromOffset(8, 9)
                    indicator.BackgroundColor3 = colors.control
                    indicator.BorderSizePixel = 0
                    indicator.ZIndex = 63
                    indicator.Parent = item
                    corner(indicator, isMultiSelect and 3 or 6)

                    local function isChecked()
                        if isMultiSelect then
                            local sel = getSelection() or {}
                            return sel[optKey] == true
                        else
                            return tostring(getSelection()) == optKey
                        end
                    end

                    local function updateItemVisual()
                        local checked = isChecked()
                        indicator.BackgroundColor3 = checked and colors.accent or colors.control
                    end

                    updateItemVisual()

                    item.Activated:Connect(function()
                        runWithPluginIdentity(function()
                            if isMultiSelect then
                                local sel = getSelection() or {}
                                sel[optKey] = not (sel[optKey] == true)
                                setSelection(sel)
                                updateItemVisual()
                                refreshButtonDisplay()
                            else
                                setSelection(optKey)
                                refreshButtonDisplay()
                                closeActiveDropdown()
                                overlayDismiss.Visible = false
                            end
                        end)
                    end)
                end
            end)

            return row
        end

        -- Slider with Knob and Value Pill ("441M/s", "14B/s")
        local function addSlider(parent, labelText, getValue, setValue, minVal, maxVal, stepVal, isValuePerSec)
            local row, rightSlot = createRow(parent, labelText)

            local sliderContainer = Instance.new("Frame")
            sliderContainer.Size = UDim2.fromScale(1, 1)
            sliderContainer.BackgroundTransparency = 1
            sliderContainer.ZIndex = 6
            sliderContainer.Parent = rightSlot

            local valueBadge = Instance.new("Frame")
            valueBadge.AnchorPoint = Vector2.new(1, 0.5)
            valueBadge.Position = UDim2.new(1, 0, 0.5, 0)
            valueBadge.Size = UDim2.fromOffset(66, 24)
            valueBadge.BackgroundColor3 = colors.control
            valueBadge.BorderSizePixel = 0
            valueBadge.ZIndex = 7
            valueBadge.Parent = sliderContainer
            corner(valueBadge, 6)
            stroke(valueBadge, colors.controlBorder, 1)

            local valueText = text(valueBadge, "0", 10, colors.text, Enum.Font.GothamBold)
            valueText.TextXAlignment = Enum.TextXAlignment.Center
            valueText.ZIndex = 8

            local trackWidth = 110
            local track = Instance.new("TextButton")
            track.AnchorPoint = Vector2.new(1, 0.5)
            track.Position = UDim2.new(1, -74, 0.5, 0)
            track.Size = UDim2.fromOffset(trackWidth, 6)
            track.BackgroundColor3 = colors.toggleInactive
            track.BorderSizePixel = 0
            track.Text = ""
            track.AutoButtonColor = false
            track.ZIndex = 7
            track.Parent = sliderContainer
            corner(track, 3)

            local fill = Instance.new("Frame")
            fill.Size = UDim2.fromScale(0, 1)
            fill.BackgroundColor3 = colors.knob
            fill.BorderSizePixel = 0
            fill.ZIndex = 8
            fill.Parent = track
            corner(fill, 3)

            local knob = Instance.new("Frame")
            knob.AnchorPoint = Vector2.new(0.5, 0.5)
            knob.Position = UDim2.new(0, 0, 0.5, 0)
            knob.Size = UDim2.fromOffset(14, 14)
            knob.BackgroundColor3 = colors.knob
            knob.BorderSizePixel = 0
            knob.ZIndex = 9
            knob.Parent = track
            corner(knob, 7)

            local function formatVal(v)
                if isValuePerSec then
                    return formatPerSec(v)
                else
                    return tostring(v)
                end
            end

            local function refreshVisual()
                local val = math.clamp(getValue() or minVal, minVal, maxVal)
                local frac = (val - minVal) / math.max(1, maxVal - minVal)
                fill.Size = UDim2.fromScale(frac, 1)
                knob.Position = UDim2.new(frac, 0, 0.5, 0)
                valueText.Text = formatVal(val)
            end

            refreshVisual()

            local dragging = false
            local function updateDrag(posX)
                local rel = math.clamp((posX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                local raw = minVal + rel * (maxVal - minVal)
                local stepped = math.floor((raw / stepVal) + 0.5) * stepVal
                stepped = math.clamp(stepped, minVal, maxVal)
                runWithPluginIdentity(function()
                    setValue(stepped)
                end)
                fill.Size = UDim2.fromScale(rel, 1)
                knob.Position = UDim2.new(rel, 0, 0.5, 0)
                valueText.Text = formatVal(stepped)
            end

            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    updateDrag(input.Position.X)
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                    updateDrag(input.Position.X)
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = false
                end
            end)

            return row
        end

        ---------------------------------------------------------------------
        -- PAGE 1: STEAL (The Venyx Primary Interface shown in screenshot)
        ---------------------------------------------------------------------
        local stealPage = Instance.new("Frame")
        stealPage.Name = "StealPage"
        stealPage.Size = UDim2.fromScale(1, 1)
        stealPage.BackgroundTransparency = 1
        stealPage.Visible = true
        stealPage.ZIndex = 3
        stealPage.Parent = mainArea
        pageFrames["Steal"] = stealPage

        -- Header Bar inside Steal Page
        local stealHeader = Instance.new("Frame")
        stealHeader.Name = "StealHeader"
        stealHeader.Size = UDim2.new(1, 0, 0, 64)
        stealHeader.BackgroundTransparency = 1
        stealHeader.ZIndex = 4
        stealHeader.Parent = stealPage

        local stealTitle = text(stealHeader, "Steal", 22, colors.text, Enum.Font.GothamBold, UDim2.fromOffset(20, 10), UDim2.fromOffset(120, 26))

        local autoStealSubLabel = text(stealHeader, "AUTO STEAL", 10, colors.muted, Enum.Font.GothamBold, UDim2.fromOffset(20, 38), UDim2.fromOffset(120, 16))

        -- Sub-Tabs: "Auto Steal" & "Egg Predictor" on top right
        local subTabsBar = Instance.new("Frame")
        subTabsBar.AnchorPoint = Vector2.new(1, 0.5)
        subTabsBar.Position = UDim2.new(1, -20, 0.5, 0)
        subTabsBar.Size = UDim2.fromOffset(220, 32)
        subTabsBar.BackgroundTransparency = 1
        subTabsBar.ZIndex = 5
        subTabsBar.Parent = stealHeader

        local subTabsLayout = Instance.new("UIListLayout")
        subTabsLayout.FillDirection = Enum.FillDirection.Horizontal
        subTabsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        subTabsLayout.Padding = UDim.new(0, 8)
        subTabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        subTabsLayout.Parent = subTabsBar

        stealSubTabAutoStealBtn = Instance.new("TextButton")
        stealSubTabAutoStealBtn.LayoutOrder = 1
        stealSubTabAutoStealBtn.Size = UDim2.fromOffset(92, 30)
        stealSubTabAutoStealBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
        stealSubTabAutoStealBtn.BorderSizePixel = 0
        stealSubTabAutoStealBtn.Text = "Auto Steal"
        stealSubTabAutoStealBtn.Font = Enum.Font.GothamBold
        stealSubTabAutoStealBtn.TextSize = 11
        stealSubTabAutoStealBtn.TextColor3 = colors.text
        stealSubTabAutoStealBtn.AutoButtonColor = false
        stealSubTabAutoStealBtn.ZIndex = 6
        stealSubTabAutoStealBtn.Parent = subTabsBar
        corner(stealSubTabAutoStealBtn, 8)
        stroke(stealSubTabAutoStealBtn, Color3.fromRGB(50, 54, 72), 1)

        stealSubTabPredictorBtn = Instance.new("TextButton")
        stealSubTabPredictorBtn.LayoutOrder = 2
        stealSubTabPredictorBtn.Size = UDim2.fromOffset(108, 30)
        stealSubTabPredictorBtn.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
        stealSubTabPredictorBtn.BorderSizePixel = 0
        stealSubTabPredictorBtn.Text = "Egg Predictor"
        stealSubTabPredictorBtn.Font = Enum.Font.GothamSemibold
        stealSubTabPredictorBtn.TextSize = 11
        stealSubTabPredictorBtn.TextColor3 = colors.muted
        stealSubTabPredictorBtn.AutoButtonColor = false
        stealSubTabPredictorBtn.ZIndex = 6
        stealSubTabPredictorBtn.Parent = subTabsBar
        corner(stealSubTabPredictorBtn, 8)

        -- Scrollable Body Container for Steal
        local stealScroll = Instance.new("ScrollingFrame")
        stealScroll.Position = UDim2.fromOffset(20, 64)
        stealScroll.Size = UDim2.new(1, -40, 1, -74)
        stealScroll.BackgroundTransparency = 1
        stealScroll.BorderSizePixel = 0
        stealScroll.ScrollBarThickness = 4
        stealScroll.ScrollBarImageColor3 = colors.accent
        stealScroll.CanvasSize = UDim2.fromOffset(0, 0)
        stealScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        stealScroll.ZIndex = 4
        stealScroll.Parent = stealPage

        -- Sub-page 1: Two-Column Auto Steal View (The Screenshot Interface)
        stealSubPageAutoSteal = Instance.new("Frame")
        stealSubPageAutoSteal.Size = UDim2.new(1, 0, 0, 0)
        stealSubPageAutoSteal.AutomaticSize = Enum.AutomaticSize.Y
        stealSubPageAutoSteal.BackgroundTransparency = 1
        stealSubPageAutoSteal.Visible = true
        stealSubPageAutoSteal.ZIndex = 4
        stealSubPageAutoSteal.Parent = stealScroll

        local stealColumnsLayout = Instance.new("UIListLayout")
        stealColumnsLayout.FillDirection = Enum.FillDirection.Horizontal
        stealColumnsLayout.Padding = UDim.new(0, 16)
        stealColumnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
        stealColumnsLayout.Parent = stealSubPageAutoSteal

        -- LEFT COLUMN (Auto Steal Controls + Auto Hop Server)
        local leftCol = Instance.new("Frame")
        leftCol.LayoutOrder = 1
        leftCol.Size = UDim2.new(0.5, -8, 0, 0)
        leftCol.AutomaticSize = Enum.AutomaticSize.Y
        leftCol.BackgroundTransparency = 1
        leftCol.ZIndex = 4
        leftCol.Parent = stealSubPageAutoSteal

        local leftColLayout = Instance.new("UIListLayout")
        leftColLayout.Padding = UDim.new(0, 12)
        leftColLayout.SortOrder = Enum.SortOrder.LayoutOrder
        leftColLayout.Parent = leftCol

        -- Card 1: ⚡ AUTO STEAL
        local autoStealCard, autoStealBody = createCard(leftCol, "AUTO STEAL", "⚡", false)

        -- Row 1: Auto steal
        addToggle(autoStealBody, "Auto steal", function()
            return runtime.autoFarmEnabled == true
        end, function(v)
            runtime.autoFarmEnabled = v
            if v and callbacks.onAutoFarmStart then
                callbacks.onAutoFarmStart()
            elseif not v and callbacks.onAutoFarmStop then
                callbacks.onAutoFarmStop()
            end
        end)

        -- Row 2: Move to egg
        addDropdown(autoStealBody, "Move to egg", {"Teleport", "Walk", "Fast Tween"}, false, function()
            return runtime.moveToEggMethod or "Teleport"
        end, function(v)
            runtime.moveToEggMethod = v
        end)

        -- Row 3: Delivery method
        addDropdown(autoStealBody, "Delivery method", {"Quick steps", "Fast Tween", "Walk"}, false, function()
            return runtime.deliveryMethod or "Quick steps"
        end, function(v)
            runtime.deliveryMethod = v
        end)

        -- Row 4: Teleport zones (Multi-select)
        local availableZones = {
            "Cherry Blossom", "Alien", "Volcano", "Titan Temple", "Light Dark", "Enchanted Forest"
        }
        addDropdown(autoStealBody, "Teleport zones", availableZones, true, function()
            return runtime.teleportZones or {}
        end, function(v)
            runtime.teleportZones = v
        end)

        -- Row 5: Steal missing index eggs
        addToggle(autoStealBody, "Steal missing index eggs", function()
            return runtime.stealMissingIndexEggs == true
        end, function(v)
            runtime.stealMissingIndexEggs = v
        end)

        -- Row 6: Steal from other players
        addToggle(autoStealBody, "Steal from other players", function()
            return runtime.stealFromPlayers == true
        end, function(v)
            runtime.stealFromPlayers = v
        end)

        -- Row 7: Anti guard
        addToggle(autoStealBody, "Anti guard", function()
            return runtime.guardZoneForceWalk == true
        end, function(v)
            runtime.guardZoneForceWalk = v
            if PathService then PathService.Invalidate() end
        end)

        -- Row 8: Drop eggs at safe zone
        addToggle(autoStealBody, "Drop eggs at safe zone", function()
            return runtime.dropEggsAtSafeZone == true
        end, function(v)
            runtime.dropEggsAtSafeZone = v
        end)

        -- Card 2: ⊟ AUTO HOP SERVER (Collapsible, default collapsed)
        local autoHopCard, autoHopBody = createCard(leftCol, "AUTO HOP SERVER", "⊟", true)

        addToggle(autoHopBody, "Enable Auto Hop", function()
            return runtime.autoHopEnabled == true
        end, function(v)
            runtime.autoHopEnabled = v
        end)

        addSlider(autoHopBody, "Hop Delay", function()
            return runtime.autoHopDelay or 30
        end, function(v)
            runtime.autoHopDelay = v
        end, 5, 300, 5, false)

        addDropdown(autoHopBody, "Hop Mode", {"Lowest Player Count", "Same Region", "Random Server"}, false, function()
            return runtime.autoHopMode or "Lowest Player Count"
        end, function(v)
            runtime.autoHopMode = v
        end)

        -- RIGHT COLUMN (Filter Controls + Min Value Per Rarity)
        local rightCol = Instance.new("Frame")
        rightCol.LayoutOrder = 2
        rightCol.Size = UDim2.new(0.5, -8, 0, 0)
        rightCol.AutomaticSize = Enum.AutomaticSize.Y
        rightCol.BackgroundTransparency = 1
        rightCol.ZIndex = 4
        rightCol.Parent = stealSubPageAutoSteal

        local rightColLayout = Instance.new("UIListLayout")
        rightColLayout.Padding = UDim.new(0, 12)
        rightColLayout.SortOrder = Enum.SortOrder.LayoutOrder
        rightColLayout.Parent = rightCol

        -- Card 3: 🎯 FILTER
        local filterCard, filterBody = createCard(rightCol, "FILTER", "🎯", false)

        -- Row 1: Zones (Multi-select)
        local zoneOptions = {
            "Alien", "Cherry Blossom", "Volcano", "Titan Temple", "Light Dark", "Enchanted Forest"
        }
        if FarmFilters and FarmFilters.GetZoneOptions then
            local dynamicZones = FarmFilters.GetZoneOptions()
            if #dynamicZones > 0 then
                zoneOptions = {}
                for _, z in ipairs(dynamicZones) do
                    table.insert(zoneOptions, { id = z.id, label = z.label })
                end
            end
        end

        addDropdown(filterBody, "Zones", zoneOptions, true, function()
            return runtime.uiZoneSelection or {}
        end, function(v)
            runtime.uiZoneSelection = v
            if FarmFilters and FarmFilters.SetZoneEnabled then
                for _, z in ipairs(zoneOptions) do
                    local zId = type(z) == "table" and z.id or z
                    if v[zId] ~= nil then
                        FarmFilters.SetZoneEnabled(zId, v[zId] == true)
                    end
                end
            end
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)

        -- Row 2: Steal first
        addDropdown(filterBody, "Steal first", {
            "Best value", "Lowest value", "Best rarity", "Best mutation", "Biggest", "Closest"
        }, false, function()
            return runtime.autoFarmPriority or "Best value"
        end, function(v)
            runtime.autoFarmPriority = v
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)

        -- Row 3: Mutations (Multi-select)
        addDropdown(filterBody, "Mutations", {
            "None", "Silver", "Rainbow", "Golden", "Infested", "Mutant"
        }, true, function()
            return runtime.uiMutationSelection or {}
        end, function(v)
            runtime.uiMutationSelection = v
            runtime.autoFarmMutantOnly = v.Mutant == true
            runtime.autoFarmInfestedOnly = v.Infested == true
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)

        -- Row 4: Rarities (Multi-select)
        local rarityOptions = {
            "Divine", "Eternal", "Secret", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"
        }
        if FarmFilters and FarmFilters.GetRarityOptions then
            local dynamicRarities = FarmFilters.GetRarityOptions()
            if #dynamicRarities > 0 then
                rarityOptions = {}
                for _, r in ipairs(dynamicRarities) do
                    table.insert(rarityOptions, { id = r.key, label = r.label })
                end
            end
        end

        addDropdown(filterBody, "Rarities", rarityOptions, true, function()
            return runtime.uiRaritySelection or {}
        end, function(v)
            runtime.uiRaritySelection = v
            if FarmFilters and FarmFilters.SetRarityEnabled then
                for _, r in ipairs(rarityOptions) do
                    local rKey = type(r) == "table" and r.id or r
                    if v[rKey] ~= nil then
                        FarmFilters.SetRarityEnabled(rKey, v[rKey] == true)
                    end
                end
            end
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)

        -- Row 5: Only these eggs (Multi-select)
        local commonEggNames = {
            "ArchAngel", "Void Pearl", "Golden Goose", "Dragon Egg", "Cosmic Egg", "Phoenix Egg", "Titan Egg", "Gorilla King"
        }
        addDropdown(filterBody, "Only these eggs", commonEggNames, true, function()
            return runtime.whitelistEggNames or {}
        end, function(v)
            runtime.whitelistEggNames = v
            if EggData and EggData.InvalidateCache then EggData.InvalidateCache() end
        end)

        -- Row 6: Min value /s
        addSlider(filterBody, "Min value /s", function()
            return runtime.autoFarmMinValuePerSec or 441000000
        end, function(v)
            runtime.autoFarmMinValuePerSec = v
        end, 0, 1000000000, 10000000, true)

        -- Row 7: Sell cheapest egg when bag is full
        addToggle(filterBody, "Sell cheapest egg when bag is full", function()
            return runtime.autoDumpWorstEggsEnabled ~= false
        end, function(v)
            runtime.autoDumpWorstEggsEnabled = v
            runtime.autoSellEnabled = v
        end)

        -- Row 8: Only below /s
        addSlider(filterBody, "Only below /s", function()
            return runtime.autoFarmMaxValuePerSec or 14000000000
        end, function(v)
            runtime.autoFarmMaxValuePerSec = v
        end, 1000000000, 50000000000, 1000000000, true)

        -- Card 4: ☆ MIN VALUE PER RARITY (Collapsible, default collapsed)
        local minValCard, minValBody = createCard(rightCol, "MIN VALUE PER RARITY", "☆", true)

        if runtime.minValPerRarity == nil then runtime.minValPerRarity = {} end

        local rarityList = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Divine" }
        for _, rName in ipairs(rarityList) do
            addSlider(minValBody, rName .. " Min", function()
                return runtime.minValPerRarity[rName] or 0
            end, function(v)
                runtime.minValPerRarity[rName] = v
            end, 0, 1000000000, 10000000, true)
        end

        -- Sub-page 2: Egg Predictor View
        stealSubPagePredictor = Instance.new("Frame")
        stealSubPagePredictor.Size = UDim2.new(1, 0, 0, 0)
        stealSubPagePredictor.AutomaticSize = Enum.AutomaticSize.Y
        stealSubPagePredictor.BackgroundTransparency = 1
        stealSubPagePredictor.Visible = false
        stealSubPagePredictor.ZIndex = 4
        stealSubPagePredictor.Parent = stealScroll

        local predCard, predBody = createCard(stealSubPagePredictor, "EGG PREDICTOR", "🔮", false)
        local predStatusLabel = text(predBody, "Scanning field egg cycles and probability...", 12, colors.muted, Enum.Font.GothamMedium, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 30))

        local predTableContainer = Instance.new("Frame")
        predTableContainer.Size = UDim2.new(1, 0, 0, 220)
        predTableContainer.BackgroundColor3 = colors.card
        predTableContainer.BorderSizePixel = 0
        predTableContainer.ZIndex = 5
        predTableContainer.Parent = predBody
        corner(predTableContainer, 8)
        stroke(predTableContainer, colors.cardBorder, 1)

        local predHeaderRow = Instance.new("Frame")
        predHeaderRow.Size = UDim2.new(1, 0, 0, 32)
        predHeaderRow.BackgroundColor3 = colors.control
        predHeaderRow.BorderSizePixel = 0
        predHeaderRow.ZIndex = 6
        predHeaderRow.Parent = predTableContainer
        corner(predHeaderRow, 8)

        text(predHeaderRow, "Zone", 11, colors.muted, Enum.Font.GothamBold, UDim2.fromOffset(16, 0), UDim2.new(0.3, 0, 1, 0))
        text(predHeaderRow, "Next Egg", 11, colors.muted, Enum.Font.GothamBold, UDim2.new(0.3, 0, 0, 0), UDim2.new(0.3, 0, 1, 0))
        text(predHeaderRow, "Rarity / Value", 11, colors.muted, Enum.Font.GothamBold, UDim2.new(0.6, 0, 0, 0), UDim2.new(0.25, 0, 1, 0))
        text(predHeaderRow, "Timer", 11, colors.muted, Enum.Font.GothamBold, UDim2.new(0.85, 0, 0, 0), UDim2.new(0.15, 0, 1, 0))

        local predList = Instance.new("ScrollingFrame")
        predList.Position = UDim2.fromOffset(0, 34)
        predList.Size = UDim2.new(1, 0, 1, -34)
        predList.BackgroundTransparency = 1
        predList.BorderSizePixel = 0
        predList.ScrollBarThickness = 3
        predList.ZIndex = 6
        predList.Parent = predTableContainer

        local predListLayout = Instance.new("UIListLayout")
        predListLayout.Padding = UDim.new(0, 2)
        predListLayout.Parent = predList

        local mockSpawns = {
            { zone = "Alien", egg = "Void Pearl", rarity = "Secret (14.2B/s)", timer = "00:42" },
            { zone = "Cherry Blossom", egg = "ArchAngel", rarity = "Divine (28.5B/s)", timer = "01:15" },
            { zone = "Volcano", egg = "Molten Titan", rarity = "Cosmic (8.1B/s)", timer = "02:08" },
            { zone = "Titan Temple", egg = "Gorilla King", rarity = "Mythic (3.2B/s)", timer = "02:50" },
            { zone = "Light Dark", egg = "Eclipse Core", rarity = "Divine (32.0B/s)", timer = "03:30" },
        }

        for _, item in ipairs(mockSpawns) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 28)
            row.BackgroundTransparency = 1
            row.ZIndex = 7
            row.Parent = predList

            text(row, item.zone, 11, colors.text, Enum.Font.GothamMedium, UDim2.fromOffset(16, 0), UDim2.new(0.3, 0, 1, 0))
            text(row, item.egg, 11, colors.accentGlow, Enum.Font.GothamSemibold, UDim2.new(0.3, 0, 0, 0), UDim2.new(0.3, 0, 1, 0))
            text(row, item.rarity, 11, colors.muted, Enum.Font.GothamMedium, UDim2.new(0.6, 0, 0, 0), UDim2.new(0.25, 0, 1, 0))
            text(row, item.timer, 11, colors.green, Enum.Font.GothamBold, UDim2.new(0.85, 0, 0, 0), UDim2.new(0.15, 0, 1, 0))
        end

        -- Sub-tab switching between Auto Steal & Egg Predictor
        stealSubTabAutoStealBtn.Activated:Connect(function()
            currentStealSubTab = "AutoSteal"
            stealSubTabAutoStealBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
            stealSubTabAutoStealBtn.TextColor3 = colors.text
            local bStroke = stealSubTabAutoStealBtn:FindFirstChildOfClass("UIStroke")
            if bStroke then bStroke.Transparency = 0 end

            stealSubTabPredictorBtn.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
            stealSubTabPredictorBtn.TextColor3 = colors.muted
            local pStroke = stealSubTabPredictorBtn:FindFirstChildOfClass("UIStroke")
            if pStroke then pStroke.Transparency = 1 end

            stealSubPageAutoSteal.Visible = true
            stealSubPagePredictor.Visible = false
            autoStealSubLabel.Text = "AUTO STEAL"
        end)

        stealSubTabPredictorBtn.Activated:Connect(function()
            currentStealSubTab = "EggPredictor"
            stealSubTabPredictorBtn.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
            stealSubTabPredictorBtn.TextColor3 = colors.text
            local pStroke = stealSubTabPredictorBtn:FindFirstChildOfClass("UIStroke")
            if not pStroke then pStroke = stroke(stealSubTabPredictorBtn, Color3.fromRGB(50, 54, 72), 1) end
            pStroke.Transparency = 0

            stealSubTabAutoStealBtn.BackgroundColor3 = Color3.fromRGB(18, 19, 25)
            stealSubTabAutoStealBtn.TextColor3 = colors.muted
            local bStroke = stealSubTabAutoStealBtn:FindFirstChildOfClass("UIStroke")
            if bStroke then bStroke.Transparency = 1 end

            stealSubPageAutoSteal.Visible = false
            stealSubPagePredictor.Visible = true
            autoStealSubLabel.Text = "EGG PREDICTOR"
        end)

        ---------------------------------------------------------------------
        -- OTHER SIDEBAR PAGES (Home, Pets, Visuals, Player, Settings)
        ---------------------------------------------------------------------

        local function createGenericPage(pageId, pageTitleText, subtitleText)
            local page = Instance.new("Frame")
            page.Name = pageId .. "Page"
            page.Size = UDim2.fromScale(1, 1)
            page.BackgroundTransparency = 1
            page.Visible = false
            page.ZIndex = 3
            page.Parent = mainArea
            pageFrames[pageId] = page

            local pHeader = Instance.new("Frame")
            pHeader.Size = UDim2.new(1, 0, 0, 64)
            pHeader.BackgroundTransparency = 1
            pHeader.ZIndex = 4
            pHeader.Parent = page

            text(pHeader, pageTitleText, 22, colors.text, Enum.Font.GothamBold, UDim2.fromOffset(20, 10), UDim2.fromOffset(200, 26))
            text(pHeader, subtitleText or pageTitleText:upper(), 10, colors.muted, Enum.Font.GothamBold, UDim2.fromOffset(20, 38), UDim2.fromOffset(200, 16))

            local pScroll = Instance.new("ScrollingFrame")
            pScroll.Position = UDim2.fromOffset(20, 64)
            pScroll.Size = UDim2.new(1, -40, 1, -74)
            pScroll.BackgroundTransparency = 1
            pScroll.BorderSizePixel = 0
            pScroll.ScrollBarThickness = 4
            pScroll.ScrollBarImageColor3 = colors.accent
            pScroll.CanvasSize = UDim2.fromOffset(0, 0)
            pScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            pScroll.ZIndex = 4
            pScroll.Parent = page

            local pLayout = Instance.new("UIListLayout")
            pLayout.Padding = UDim.new(0, 14)
            pLayout.SortOrder = Enum.SortOrder.LayoutOrder
            pLayout.Parent = pScroll

            return page, pScroll
        end

        -- PAGE: HOME
        local _, homeScroll = createGenericPage("Home", "Dashboard", "OVERVIEW & LIVE STATUS")
        local homeCard1, homeBody1 = createCard(homeScroll, "QUICK CONTROLS", "⚡", false)
        addToggle(homeBody1, "Auto Steal Active", function() return runtime.autoFarmEnabled == true end, function(v)
            runtime.autoFarmEnabled = v
            if v and callbacks.onAutoFarmStart then callbacks.onAutoFarmStart()
            elseif not v and callbacks.onAutoFarmStop then callbacks.onAutoFarmStop() end
        end)
        addToggle(homeBody1, "Wait For Day Cycle", function() return runtime.waitForDayBeforeFarm ~= false end, function(v)
            runtime.waitForDayBeforeFarm = v
        end)

        local homeCard2, homeBody2 = createCard(homeScroll, "SESSION TELEMETRY", "📊", false)
        local telemetryText = text(homeBody2, "Loading telemetry stats...", 11, colors.muted, Enum.Font.GothamMedium, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 48))
        telemetryText.TextWrapped = true

        -- PAGE: PET (🌱)
        local _, petScroll = createGenericPage("Pet", "Pet Automation", "PETS & BASE PEN")
        local petCard, petBody = createCard(petScroll, "PET CARE", "🌱", false)
        addToggle(petBody, "Auto Pet Care", function() return runtime.autoPetCareEnabled ~= false end, function(v) runtime.autoPetCareEnabled = v end)
        addToggle(petBody, "Auto Hatch", function() return runtime.autoHatchEnabled ~= false end, function(v) runtime.autoHatchEnabled = v end)
        addToggle(petBody, "Auto Equip Best Pets", function() return runtime.autoEquipBest ~= false end, function(v) runtime.autoEquipBest = v end)
        addToggle(petBody, "Auto Fuse Duplicates", function() return runtime.autoFuseEnabled ~= false end, function(v) runtime.autoFuseEnabled = v end)

        local penCard, penBody = createCard(petScroll, "BASE PEN", "🏰", false)
        addToggle(penBody, "Auto Upgrade Base Pen", function() return runtime.autoUpgradeBasePen ~= false end, function(v) runtime.autoUpgradeBasePen = v end)
        addToggle(penBody, "Auto Collect Pen Money", function() return runtime.autoCollectPenMoney ~= false end, function(v) runtime.autoCollectPenMoney = v end)

        -- PAGE: ESP (✨)
        local _, espScroll = createGenericPage("ESP", "Visuals & ESP", "FIELD DISPLAY SETTINGS")
        local espCard, espBody = createCard(espScroll, "ESP TOGGLES", "✨", false)
        addToggle(espBody, "Egg ESP", function() return runtime.showEggs ~= false end, function(v) runtime.showEggs = v end)
        addToggle(espBody, "Treadmill ESP", function() return runtime.showTreadmill == true end, function(v) runtime.showTreadmill = v end)
        addToggle(espBody, "Trap ESP", function() return runtime.showTraps == true end, function(v) runtime.showTraps = v end)
        addToggle(espBody, "Avoid Own Traps", function() return runtime.pathAvoidOwnTraps == true end, function(v)
            runtime.pathAvoidOwnTraps = v
            if PathService then PathService.Invalidate() end
        end)
        addSlider(espBody, "Max ESP Distance", function() return runtime.maxDistance or 200 end, function(v) runtime.maxDistance = v end, 50, 800, 25, false)

        -- PAGE: PLAYER (👤)
        local _, playerScroll = createGenericPage("Player", "Player Character", "MOVEMENT & STANDBY")
        local playerCard, playerBody = createCard(playerScroll, "STANDBY POSITION", "📍", false)

        local standbyRow, standbySlot = createRow(playerBody, "Current Standby")
        local standbyBtn = Instance.new("TextButton")
        standbyBtn.AnchorPoint = Vector2.new(1, 0.5)
        standbyBtn.Position = UDim2.new(1, 0, 0.5, 0)
        standbyBtn.Size = UDim2.fromOffset(140, 26)
        standbyBtn.BackgroundColor3 = colors.accent
        standbyBtn.BorderSizePixel = 0
        standbyBtn.Text = "Set Standby Here"
        standbyBtn.Font = Enum.Font.GothamBold
        standbyBtn.TextSize = 11
        standbyBtn.TextColor3 = colors.text
        standbyBtn.AutoButtonColor = false
        standbyBtn.ZIndex = 6
        standbyBtn.Parent = standbySlot
        corner(standbyBtn, 6)

        standbyBtn.Activated:Connect(function()
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                runtime.standbyPosition = root.Position
                if PathService then PathService.Invalidate() end
                standbyBtn.Text = "Standby Updated!"
                task.delay(1.5, function() standbyBtn.Text = "Set Standby Here" end)
            end
        end)

        local moveCard, moveBody = createCard(playerScroll, "MOVEMENT TWEAKS", "⚡", false)
        addSlider(moveBody, "Tween Speed", function() return runtime.tweenSpeed or 700 end, function(v) runtime.tweenSpeed = v end, 300, 1000, 50, false)
        addToggle(moveBody, "Walk In Guard Zone", function() return runtime.guardZoneForceWalk == true end, function(v) runtime.guardZoneForceWalk = v end)

        local resetRow, resetSlot = createRow(moveBody, "Cancel Motion")
        local resetBtn = Instance.new("TextButton")
        resetBtn.AnchorPoint = Vector2.new(1, 0.5)
        resetBtn.Position = UDim2.new(1, 0, 0.5, 0)
        resetBtn.Size = UDim2.fromOffset(140, 26)
        resetBtn.BackgroundColor3 = colors.card
        resetBtn.BorderSizePixel = 0
        resetBtn.Text = "Reset Character Motion"
        resetBtn.Font = Enum.Font.GothamSemibold
        resetBtn.TextSize = 10
        resetBtn.TextColor3 = colors.muted
        resetBtn.AutoButtonColor = false
        resetBtn.ZIndex = 6
        resetBtn.Parent = resetSlot
        corner(resetBtn, 6)
        stroke(resetBtn, colors.cardBorder, 1)

        resetBtn.Activated:Connect(function()
            if Movement and Movement.Reset then Movement.Reset() end
        end)

        -- PAGE: SETTINGS (⚙)
        local _, settingsScroll = createGenericPage("Settings", "Settings & Config", "PREFERENCES & KEYBINDS")
        local setCard, setBody = createCard(settingsScroll, "DISPLAY & LOCALE", "⚙", false)
        addDropdown(setBody, "Language", { "English", "Tiếng Việt" }, false, function()
            return runtime.uiLanguage or "English"
        end, function(v)
            runtime.uiLanguage = v
            langBtn.Text = "文A  " .. v
        end)

        local keyRow, keySlot = createRow(setBody, "Hub Toggle Key")
        local keyBtn = Instance.new("TextButton")
        keyBtn.AnchorPoint = Vector2.new(1, 0.5)
        keyBtn.Position = UDim2.new(1, 0, 0.5, 0)
        keyBtn.Size = UDim2.fromOffset(60, 26)
        keyBtn.BackgroundColor3 = colors.control
        keyBtn.BorderSizePixel = 0
        keyBtn.Text = (runtime.hubToggleKey or Enum.KeyCode.G).Name
        keyBtn.Font = Enum.Font.GothamBold
        keyBtn.TextSize = 11
        keyBtn.TextColor3 = colors.text
        keyBtn.AutoButtonColor = false
        keyBtn.ZIndex = 6
        keyBtn.Parent = keySlot
        corner(keyBtn, 6)
        stroke(keyBtn, colors.controlBorder, 1)

        local listeningForKey = false
        keyBtn.Activated:Connect(function()
            if listeningForKey then return end
            listeningForKey = true
            keyBtn.Text = "..."
            local conn
            conn = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    runtime.hubToggleKey = input.KeyCode
                    keyBtn.Text = input.KeyCode.Name
                    listeningForKey = false
                    conn:Disconnect()
                end
            end)
        end)

        return window
    end

    -------------------------------------------------------------------------
    -- STATUS REFRESH LOOP
    -------------------------------------------------------------------------
    local function formatLiveStatus()
        if not Diagnostics then return "Caught Void Pearl x19" end
        local ok, diag = pcall(Diagnostics.Collect)
        if not ok or type(diag) ~= "table" then return "Caught Void Pearl x19" end

        if diag.autoFarm then
            if diag.autoFarm.isCarrying and diag.autoFarm.target then
                return string.format("Carrying: %s", tostring(diag.autoFarm.target.name or "Egg"))
            elseif diag.autoFarm.target then
                return string.format("Target: %s (%dm)", tostring(diag.autoFarm.target.name or "Egg"), math.floor(diag.autoFarm.target.distance or 0))
            elseif diag.autoFarm.phase and diag.autoFarm.phase ~= "Idle" then
                return string.format("Phase: %s", tostring(diag.autoFarm.phase))
            end
        end

        local eggsCount = diag.esp and diag.esp.eggsVisible or 0
        if eggsCount > 0 then
            return string.format("Field Eggs: %d visible", eggsCount)
        end

        return "Caught Void Pearl x19"
    end

    local function startStatusLoop()
        if statusRunning then return end
        statusRunning = true
        statusTask = task.spawn(function()
            while statusRunning do
                runWithPluginIdentity(function()
                    if statusPillText and statusPillText.Parent then
                        statusPillText.Text = formatLiveStatus()
                    end
                end)
                task.wait(runtime.hubStatusRefreshInterval or 1.5)
            end
        end)
    end

    local function stopStatusLoop()
        statusRunning = false
    end

    local function SetVisible(val)
        runtime.hubVisible = val == true
        visible = runtime.hubVisible
        if window then
            pcall(function() window.Visible = visible end)
            if not visible then
                closeActiveDropdown()
            end
        end
    end

    local function ToggleVisible()
        SetVisible(not visible)
        return visible
    end

    local function attachKeybind()
        if inputConnection then return end
        inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
            if not processed and input.KeyCode == (runtime.hubToggleKey or Enum.KeyCode.G) then
                ToggleVisible()
            end
        end)
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
        if inputConnection then
            inputConnection:Disconnect()
            inputConnection = nil
        end
        if gui then gui:Destroy() end
        gui = nil
        window = nil
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
