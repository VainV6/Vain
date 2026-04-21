--[[
    UI/Window.lua  –  The Vain hub's main window.

    Layout (560 × 400)
    ┌────────────────────────────────────────────┐
    │  ▌ VAIN  hub                        [−][×] │  ← Header (draggable)
    ├──────────┬─────────────────────────────────┤
    │ Combat   │  [●] KillAura             [K]   │
    │ Movement │  ├─ Range ─────────────── 10st  │  ← expanded settings
    │ Visuals  │  ├─ Through Walls         [off] │
    │ Misc     │  └─ Priority        Closest ▾   │
    │          │  [ ] Reach                [R]   │
    └──────────┴─────────────────────────────────┘

    API:
        Window.new(config, registry)  →  Window
        window:Show()
        window:Hide()
        window:Toggle()
        window:PopulateFromRegistry()   – call once after all modules are added
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")

local Theme      = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Components)

local W = Theme.Window   -- layout constants

local Window  = {}
Window.__index = Window

-- ── Internal helpers ─────────────────────────────────────────────────────────

local function tw(obj, info, props)
    return TweenService:Create(obj, info, props)
end

local function corner(parent, r)
    local c        = Instance.new("UICorner")
    c.CornerRadius = r or Theme.Radius
    c.Parent       = parent
    return c
end

local function stroke(parent, color, thickness)
    local s              = Instance.new("UIStroke")
    s.Color              = color or Theme.Border
    s.Thickness          = thickness or 1
    s.ApplyStrokeMode    = Enum.ApplyStrokeMode.Border
    s.Parent             = parent
    return s
end

local function pad(parent, l, r, t, b)
    local p         = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.PaddingRight  = UDim.new(0, r or 0)
    p.PaddingTop    = UDim.new(0, t or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.Parent        = parent
end

-- ── Constructor ──────────────────────────────────────────────────────────────

function Window.new(config, registry)
    local self         = setmetatable({}, Window)
    self._registry     = registry
    self._config       = config
    self._visible      = false
    self._activeCat    = 1
    self._catBtns      = {}
    self._gui          = nil
    self._mainFrame    = nil
    self._sidebar      = nil
    self._moduleScroll = nil

    self:_build()
    return self
end

-- ── Build skeleton ────────────────────────────────────────────────────────────

function Window:_build()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local gui              = Instance.new("ScreenGui")
    gui.Name               = "VainHub"
    gui.ResetOnSpawn       = false
    gui.IgnoreGuiInset     = true
    gui.DisplayOrder       = 100
    gui.ZIndexBehavior     = Enum.ZIndexBehavior.Sibling
    gui.Parent             = playerGui
    self._gui              = gui

    -- Drop-shadow (sits behind the window, slightly larger)
    local shadow           = Instance.new("Frame")
    shadow.Size            = UDim2.fromOffset(W.Width + 16, W.Height + 16)
    shadow.AnchorPoint     = Vector2.new(0.5, 0.5)
    shadow.Position        = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.65
    shadow.BorderSizePixel = 0
    shadow.Visible         = false
    shadow.Parent          = gui
    corner(shadow, UDim.new(0, 14))
    self._shadow           = shadow

    -- Main window frame
    local main             = Instance.new("Frame")
    main.Name              = "Window"
    main.Size              = UDim2.fromOffset(W.Width, W.Height)
    main.AnchorPoint       = Vector2.new(0.5, 0.5)
    main.Position          = UDim2.fromScale(0.5, 0.5)
    main.BackgroundColor3  = Theme.Background
    main.BorderSizePixel   = 0
    main.Visible           = false
    main.Parent            = gui
    corner(main, Theme.RadiusLG)
    stroke(main, Theme.Border, 1)
    self._mainFrame        = main

    self:_buildHeader(main)
    self:_buildSidebar(main)
    self:_buildContent(main)
    self:_setupDrag(main)
end

-- ── Header ────────────────────────────────────────────────────────────────────

function Window:_buildHeader(parent)
    local accent = self._config.AccentColor or Theme.Accent

    local header           = Instance.new("Frame")
    header.Name            = "Header"
    header.Size            = UDim2.new(1, 0, 0, W.HeaderH)
    header.BackgroundColor3 = Theme.Surface
    header.BorderSizePixel = 0
    header.Parent          = parent
    corner(header, Theme.RadiusLG)

    -- Square off the two bottom corners of the header
    local squareFill       = Instance.new("Frame")
    squareFill.Size        = UDim2.new(1, 0, 0, Theme.RadiusLG.Offset)
    squareFill.Position    = UDim2.new(0, 0, 1, -Theme.RadiusLG.Offset)
    squareFill.BackgroundColor3 = Theme.Surface
    squareFill.BorderSizePixel  = 0
    squareFill.Parent      = header

    -- Left accent bar
    local bar              = Instance.new("Frame")
    bar.Size               = UDim2.fromOffset(3, W.HeaderH - 18)
    bar.Position           = UDim2.fromOffset(12, 9)
    bar.BackgroundColor3   = accent
    bar.BorderSizePixel    = 0
    bar.Parent             = header
    corner(bar, UDim.new(0, 2))

    -- Title
    local title            = Instance.new("TextLabel")
    title.Size             = UDim2.new(0, 80, 1, 0)
    title.Position         = UDim2.fromOffset(24, 0)
    title.BackgroundTransparency = 1
    title.Text             = self._config.Title or "Vain"
    title.Font             = Theme.FontBold
    title.TextSize         = Theme.FontSize.XL
    title.TextColor3       = Theme.Text
    title.TextXAlignment   = Enum.TextXAlignment.Left
    title.Parent           = header

    -- Subtitle
    local sub              = Instance.new("TextLabel")
    sub.Size               = UDim2.new(0, 60, 1, 0)
    sub.Position           = UDim2.new(0, 65, 0, 3)
    sub.BackgroundTransparency = 1
    sub.Text               = self._config.Subtitle or "hub"
    sub.Font               = Theme.Font
    sub.TextSize           = Theme.FontSize.MD
    sub.TextColor3         = Theme.TextMuted
    sub.TextXAlignment     = Enum.TextXAlignment.Left
    sub.Parent             = header

    -- Separator line under header
    local sep              = Instance.new("Frame")
    sep.Size               = UDim2.new(1, 0, 0, 1)
    sep.Position           = UDim2.new(0, 0, 1, -1)
    sep.BackgroundColor3   = Theme.Border
    sep.BorderSizePixel    = 0
    sep.Parent             = header

    -- Control buttons (close / minimize)
    self:_makeHeaderBtn(header, "×", UDim2.new(1, -10, 0.5, 0), function()
        self:Hide()
    end, Theme.Danger)

    local minimized = false
    self:_makeHeaderBtn(header, "−", UDim2.new(1, -38, 0.5, 0), function()
        minimized = not minimized
        if minimized then
            tw(self._mainFrame, Theme.Tween, {Size = UDim2.fromOffset(W.Width, W.HeaderH)}):Play()
            tw(self._shadow,    Theme.Tween, {Size = UDim2.fromOffset(W.Width + 16, W.HeaderH + 16)}):Play()
        else
            tw(self._mainFrame, Theme.Tween, {Size = UDim2.fromOffset(W.Width, W.Height)}):Play()
            tw(self._shadow,    Theme.Tween, {Size = UDim2.fromOffset(W.Width + 16, W.Height + 16)}):Play()
        end
    end, Theme.Warning)
end

function Window:_makeHeaderBtn(parent, glyph, anchoredPos, onClick, hoverColor)
    local btn              = Instance.new("TextButton")
    btn.Size               = UDim2.fromOffset(24, 24)
    btn.AnchorPoint        = Vector2.new(1, 0.5)
    btn.Position           = anchoredPos
    btn.BackgroundColor3   = Theme.Surface3
    btn.BorderSizePixel    = 0
    btn.Font               = Theme.FontBold
    btn.TextSize           = Theme.FontSize.LG
    btn.TextColor3         = Theme.TextMuted
    btn.Text               = glyph
    btn.Parent             = parent
    corner(btn, Theme.RadiusFull)

    btn.MouseEnter:Connect(function()
        tw(btn, Theme.TweenFast, {BackgroundColor3 = hoverColor, TextColor3 = Theme.Text}):Play()
    end)
    btn.MouseLeave:Connect(function()
        tw(btn, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3, TextColor3 = Theme.TextMuted}):Play()
    end)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

-- ── Sidebar ───────────────────────────────────────────────────────────────────

function Window:_buildSidebar(parent)
    local sidebar          = Instance.new("Frame")
    sidebar.Name           = "Sidebar"
    sidebar.Size           = UDim2.new(0, W.SidebarW, 1, -W.HeaderH)
    sidebar.Position       = UDim2.fromOffset(0, W.HeaderH)
    sidebar.BackgroundColor3 = Theme.Surface
    sidebar.BorderSizePixel = 0
    sidebar.ClipsDescendants = true
    sidebar.Parent         = parent
    corner(sidebar, Theme.RadiusLG)

    -- Fill that squares off the top-right and bottom-right corners
    local rightFill        = Instance.new("Frame")
    rightFill.Size         = UDim2.new(0, Theme.RadiusLG.Offset, 1, 0)
    rightFill.Position     = UDim2.new(1, -Theme.RadiusLG.Offset, 0, 0)
    rightFill.BackgroundColor3 = Theme.Surface
    rightFill.BorderSizePixel  = 0
    rightFill.Parent       = sidebar

    local topFill          = Instance.new("Frame")
    topFill.Size           = UDim2.new(1, 0, 0, Theme.RadiusLG.Offset)
    topFill.BackgroundColor3 = Theme.Surface
    topFill.BorderSizePixel  = 0
    topFill.Parent         = sidebar

    -- Vertical separator
    local divider          = Instance.new("Frame")
    divider.Size           = UDim2.fromOffset(1, W.Height - W.HeaderH)
    divider.Position       = UDim2.new(0, W.SidebarW - 1, 0, W.HeaderH)
    divider.BackgroundColor3 = Theme.Border
    divider.BorderSizePixel  = 0
    divider.Parent         = parent

    -- Layout for category buttons
    local layout           = Instance.new("UIListLayout")
    layout.FillDirection   = Enum.FillDirection.Vertical
    layout.Padding         = UDim.new(0, 2)
    layout.Parent          = sidebar

    pad(sidebar, 6, 6, 10, 6)

    self._sidebar = sidebar
end

-- ── Content area ──────────────────────────────────────────────────────────────

function Window:_buildContent(parent)
    local content          = Instance.new("Frame")
    content.Name           = "Content"
    content.Size           = UDim2.new(1, -W.SidebarW, 1, -W.HeaderH)
    content.Position       = UDim2.new(0, W.SidebarW, 0, W.HeaderH)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    content.Parent         = parent
    self._content          = content

    local scroll           = Instance.new("ScrollingFrame")
    scroll.Name            = "ModuleScroll"
    scroll.Size            = UDim2.fromScale(1, 1)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.ScrollBarImageTransparency = 0.4
    scroll.CanvasSize      = UDim2.fromScale(1, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent          = content
    self._moduleScroll     = scroll

    local layout           = Instance.new("UIListLayout")
    layout.FillDirection   = Enum.FillDirection.Vertical
    layout.Padding         = UDim.new(0, 3)
    layout.Parent          = scroll

    pad(scroll, W.Padding, W.Padding, W.Padding, W.Padding)
end

-- ── Category population ───────────────────────────────────────────────────────

function Window:PopulateFromRegistry()
    -- Clear any previous category buttons
    for _, btn in ipairs(self._catBtns) do
        if btn.btn and btn.btn.Parent then
            btn.btn:Destroy()
        end
    end
    self._catBtns = {}

    local categories = self._registry:GetCategories()

    for i, cat in ipairs(categories) do
        local isActive = (i == self._activeCat)

        local btn          = Instance.new("TextButton")
        btn.Size           = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = isActive and Theme.Surface3 or Theme.Surface
        btn.BackgroundTransparency = isActive and 0 or 1
        btn.BorderSizePixel = 0
        btn.Font           = isActive and Theme.FontSemi or Theme.Font
        btn.TextSize       = Theme.FontSize.SM
        btn.TextColor3     = isActive and Theme.Text or Theme.TextMuted
        btn.Text           = cat.name
        btn.Parent         = self._sidebar
        corner(btn, Theme.RadiusSM)

        -- Active indicator pill (left edge)
        local ind          = Instance.new("Frame")
        ind.Size           = UDim2.fromOffset(3, 14)
        ind.Position       = UDim2.fromOffset(0, 8)
        ind.BackgroundColor3 = Theme.Accent
        ind.BorderSizePixel  = 0
        ind.Visible        = isActive
        ind.Parent         = btn
        corner(ind, UDim.new(0, 2))

        self._catBtns[i]   = { btn = btn, ind = ind }

        local idx = i
        btn.MouseButton1Click:Connect(function()
            self:_selectCategory(idx)
        end)
        btn.MouseEnter:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, Theme.TweenFast, {BackgroundTransparency = 0.4, BackgroundColor3 = Theme.Surface3, TextColor3 = Theme.Text}):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, Theme.TweenFast, {BackgroundTransparency = 1, TextColor3 = Theme.TextMuted}):Play()
            end
        end)
    end

    if #categories > 0 then
        self:_selectCategory(self._activeCat)
    end
end

function Window:_selectCategory(idx)
    -- Update sidebar button states
    for i, entry in ipairs(self._catBtns) do
        local active = (i == idx)
        entry.ind.Visible = active
        entry.btn.Font    = active and Theme.FontSemi or Theme.Font
        tw(entry.btn, Theme.TweenFast, {
            BackgroundTransparency = active and 0 or 1,
            BackgroundColor3       = Theme.Surface3,
            TextColor3             = active and Theme.Text or Theme.TextMuted,
        }):Play()
    end

    self._activeCat = idx

    -- Clear module list
    for _, child in ipairs(self._moduleScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    -- Repopulate
    local cat = self._registry:GetCategories()[idx]
    if not cat then return end

    for _, mod in ipairs(cat.modules) do
        self:_buildModuleRow(mod)
    end
end

-- ── Module row ────────────────────────────────────────────────────────────────

function Window:_buildModuleRow(module)
    local hasSettings = #module.Settings > 0

    -- Pre-compute expanded height
    local expandH = 0
    for _, s in ipairs(module.Settings) do
        expandH = expandH + (Theme.SettingH[s.Type] or 30) + 4
    end
    local expandPad    = 10
    local totalExpand  = expandH + expandPad * 2 + (hasSettings and 6 or 0)

    local expanded     = false

    -- Row container (height animates)
    local row          = Instance.new("Frame")
    row.Name           = module.Name
    row.Size           = UDim2.new(1, 0, 0, W.ModuleH)
    row.BackgroundColor3 = Theme.Surface2
    row.BorderSizePixel = 0
    row.ClipsDescendants = true
    row.Parent         = self._moduleScroll
    corner(row, Theme.RadiusSM)

    -- ── Top strip (always visible) ────────────────────────────────────────────
    local strip        = Instance.new("Frame")
    strip.Size         = UDim2.new(1, 0, 0, W.ModuleH)
    strip.BackgroundTransparency = 1
    strip.Parent       = row

    -- Status dot
    local dot          = Instance.new("Frame")
    dot.Size           = UDim2.fromOffset(6, 6)
    dot.Position       = UDim2.fromOffset(10, (W.ModuleH - 6) / 2)
    dot.BackgroundColor3 = module.Enabled and Theme.Accent or Theme.Surface3
    dot.BorderSizePixel  = 0
    dot.Parent         = strip
    corner(dot, Theme.RadiusFull)

    -- Module name
    local nameL        = Instance.new("TextLabel")
    nameL.Size         = UDim2.new(1, -120, 1, 0)
    nameL.Position     = UDim2.fromOffset(24, 0)
    nameL.BackgroundTransparency = 1
    nameL.Text         = module.Name
    nameL.Font         = module.Enabled and Theme.FontSemi or Theme.Font
    nameL.TextSize     = Theme.FontSize.MD
    nameL.TextColor3   = module.Enabled and Theme.Text or Theme.TextMuted
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Parent       = strip

    -- Keybind hint
    if module.Keybind then
        local kbHint   = Instance.new("TextLabel")
        kbHint.Size    = UDim2.fromOffset(32, W.ModuleH)
        kbHint.AnchorPoint = Vector2.new(1, 0)
        kbHint.Position    = UDim2.new(1, hasSettings and -56 or -38, 0, 0)
        kbHint.BackgroundTransparency = 1
        kbHint.Text    = "[" .. module.Keybind.Name:sub(1, 3):upper() .. "]"
        kbHint.Font    = Theme.Font
        kbHint.TextSize = Theme.FontSize.XS
        kbHint.TextColor3 = Theme.TextDim
        kbHint.TextXAlignment = Enum.TextXAlignment.Right
        kbHint.Parent  = strip
    end

    -- Right-side control: toggle pill (Toggleable) or RUN button (Executable)
    local rightOffset = hasSettings and -28 or -10

    if module.Behavior == "Toggleable" then
        local pill         = Instance.new("Frame")
        pill.Size          = UDim2.fromOffset(32, 16)
        pill.AnchorPoint   = Vector2.new(1, 0.5)
        pill.Position      = UDim2.new(1, rightOffset, 0.5, 0)
        pill.BackgroundColor3 = module.Enabled and Theme.Accent or Theme.Surface3
        pill.BorderSizePixel  = 0
        pill.Parent        = strip
        corner(pill, Theme.RadiusFull)

        local knob         = Instance.new("Frame")
        knob.Size          = UDim2.fromOffset(10, 10)
        knob.AnchorPoint   = Vector2.new(0, 0.5)
        knob.Position      = module.Enabled
            and UDim2.new(1, -13, 0.5, 0)
            or  UDim2.new(0, 3,  0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel  = 0
        knob.Parent        = pill
        corner(knob, Theme.RadiusFull)

        -- React to state changes from any source (keybind, etc.)
        module:OnStateChange(function(state)
            local on = state == true
            tw(pill, Theme.TweenFast, {BackgroundColor3 = on and Theme.Accent or Theme.Surface3}):Play()
            tw(knob, Theme.TweenFast, {Position = on and UDim2.new(1,-13,0.5,0) or UDim2.new(0,3,0.5,0)}):Play()
            tw(dot,  Theme.TweenFast, {BackgroundColor3 = on and Theme.Accent or Theme.Surface3}):Play()
            tw(nameL, Theme.TweenFast, {TextColor3 = on and Theme.Text or Theme.TextMuted}):Play()
            nameL.Font = on and Theme.FontSemi or Theme.Font
        end)

    else
        -- Executable: flash-on-trigger RUN badge
        local execBtn      = Instance.new("TextButton")
        execBtn.Size       = UDim2.fromOffset(38, 20)
        execBtn.AnchorPoint = Vector2.new(1, 0.5)
        execBtn.Position   = UDim2.new(1, rightOffset, 0.5, 0)
        execBtn.BackgroundColor3 = Theme.Accent
        execBtn.BorderSizePixel  = 0
        execBtn.Font       = Theme.FontBold
        execBtn.TextSize   = Theme.FontSize.XS
        execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        execBtn.Text       = "RUN"
        execBtn.Parent     = strip
        corner(execBtn, Theme.RadiusSM)

        execBtn.MouseButton1Click:Connect(function()
            module:Trigger()
            tw(execBtn, TweenInfo.new(0.08), {BackgroundColor3 = Theme.Success}):Play()
            task.delay(0.35, function()
                tw(execBtn, Theme.Tween, {BackgroundColor3 = Theme.Accent}):Play()
            end)
        end)

        -- Dim dot on execute flash
        module:OnStateChange(function()
            tw(dot, Theme.TweenFast, {BackgroundColor3 = Theme.Accent}):Play()
            task.delay(0.35, function()
                tw(dot, Theme.Tween, {BackgroundColor3 = Theme.Surface3}):Play()
            end)
        end)
    end

    -- ── Settings expand chevron ───────────────────────────────────────────────
    if hasSettings then
        local chev         = Instance.new("TextLabel")
        chev.Size          = UDim2.fromOffset(20, W.ModuleH)
        chev.AnchorPoint   = Vector2.new(1, 0)
        chev.Position      = UDim2.new(1, -8, 0, 0)
        chev.BackgroundTransparency = 1
        chev.Text          = "›"
        chev.Font          = Theme.FontBold
        chev.TextSize      = Theme.FontSize.LG
        chev.TextColor3    = Theme.TextDim
        chev.TextXAlignment = Enum.TextXAlignment.Center
        chev.Rotation      = 90    -- ›  rotated = ∨
        chev.Parent        = strip

        -- ── Settings panel ───────────────────────────────────────────────────
        local settingsPanel = Instance.new("Frame")
        settingsPanel.Size  = UDim2.new(1, -16, 0, totalExpand)
        settingsPanel.Position = UDim2.new(0, 8, 0, W.ModuleH + 4)
        settingsPanel.BackgroundTransparency = 1
        settingsPanel.Parent = row

        local settingsLayout = Instance.new("UIListLayout")
        settingsLayout.FillDirection = Enum.FillDirection.Vertical
        settingsLayout.Padding       = UDim.new(0, 4)
        settingsLayout.Parent        = settingsPanel

        local settingsPad = Instance.new("UIPadding")
        settingsPad.PaddingTop    = UDim.new(0, expandPad)
        settingsPad.PaddingBottom = UDim.new(0, expandPad)
        settingsPad.Parent        = settingsPanel

        for _, setting in ipairs(module.Settings) do
            local comp = Components.Build(setting)
            if comp then comp.Parent = settingsPanel end
        end

        -- Separator line between strip and settings
        local settingSep = Instance.new("Frame")
        settingSep.Size  = UDim2.new(1, -16, 0, 1)
        settingSep.Position = UDim2.new(0, 8, 0, W.ModuleH)
        settingSep.BackgroundColor3 = Theme.Border
        settingSep.BackgroundTransparency = 1
        settingSep.BorderSizePixel = 0
        settingSep.Parent = row

        -- Expand toggle button (covers right side of strip)
        local expandBtn    = Instance.new("TextButton")
        expandBtn.Size     = UDim2.fromOffset(28, W.ModuleH)
        expandBtn.AnchorPoint = Vector2.new(1, 0)
        expandBtn.Position = UDim2.new(1, 0, 0, 0)
        expandBtn.BackgroundTransparency = 1
        expandBtn.Text     = ""
        expandBtn.ZIndex   = 3
        expandBtn.Parent   = strip

        expandBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            local targetH = expanded
                and (W.ModuleH + totalExpand + 4)
                or  W.ModuleH
            tw(row,         Theme.Tween,    {Size = UDim2.new(1, 0, 0, targetH)}):Play()
            tw(chev,        Theme.TweenFast, {Rotation = expanded and 270 or 90}):Play()
            tw(settingSep,  Theme.TweenFast, {BackgroundTransparency = expanded and 0 or 1}):Play()
            tw(chev,        Theme.TweenFast, {TextColor3 = expanded and Theme.Accent or Theme.TextDim}):Play()
        end)
    end

    -- ── Main row click: toggle module (Toggleable) ────────────────────────────
    -- Covers everything except the expand button area on the right
    local rowBtn           = Instance.new("TextButton")
    rowBtn.Size            = UDim2.new(1, hasSettings and -28 or 0, 0, W.ModuleH)
    rowBtn.BackgroundTransparency = 1
    rowBtn.Text            = ""
    rowBtn.ZIndex          = 2
    rowBtn.Parent          = strip

    rowBtn.MouseEnter:Connect(function()
        tw(row, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
    end)
    rowBtn.MouseLeave:Connect(function()
        tw(row, Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
    end)
    rowBtn.MouseButton1Click:Connect(function()
        if module.Behavior == "Toggleable" then
            module:Trigger()
        end
        -- Executable modules are triggered by the RUN button, not the row
    end)

    return row
end

-- ── Drag ──────────────────────────────────────────────────────────────────────

function Window:_setupDrag(frame)
    local header   = frame:FindFirstChild("Header")
    local dragSrc  = header or frame
    local dragging = false
    local startPos, startInput

    dragSrc.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging   = true
            startInput = Vector2.new(inp.Position.X, inp.Position.Y)
            startPos   = frame.AbsolutePosition
            frame.AnchorPoint = Vector2.zero
            frame.Position    = UDim2.fromOffset(startPos.X, startPos.Y)
            self._shadow.AnchorPoint = Vector2.zero
            self._shadow.Position    = UDim2.fromOffset(startPos.X - 8, startPos.Y - 8)
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta  = Vector2.new(inp.Position.X, inp.Position.Y) - startInput
        local newX   = startPos.X + delta.X
        local newY   = startPos.Y + delta.Y
        frame.Position  = UDim2.fromOffset(newX, newY)
        self._shadow.Position = UDim2.fromOffset(newX - 8, newY - 8)
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

-- ── Visibility ────────────────────────────────────────────────────────────────

function Window:Show()
    self._mainFrame.Visible = true
    self._shadow.Visible    = true
    self._mainFrame.Size    = UDim2.fromOffset(W.Width, 10)
    self._shadow.Size       = UDim2.fromOffset(W.Width + 16, 26)
    tw(self._mainFrame, Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width, W.Height)}):Play()
    tw(self._shadow,    Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width + 16, W.Height + 16)}):Play()
    self._visible = true
end

function Window:Hide()
    tw(self._mainFrame, Theme.Tween, {Size = UDim2.fromOffset(W.Width, 10)}):Play()
    tw(self._shadow,    Theme.Tween, {Size = UDim2.fromOffset(W.Width + 16, 26)}):Play()
    task.delay(Theme.Tween.Time + 0.05, function()
        if self._mainFrame then self._mainFrame.Visible = false end
        if self._shadow    then self._shadow.Visible    = false end
    end)
    self._visible = false
end

function Window:Toggle()
    if self._visible then self:Hide() else self:Show() end
end

return Window
