--[[
    UI/Window.lua  –  Vain hub window.

    Visual design mirrors the rogue-tower-defense component library:
      • Header  – accent pip, title, FPS readout, collapse chevron
      • Sidebar – category buttons with Lighten hover + active indicator bar
      • Content – search bar, scrolling module list
      • Module rows – SliderToggle pill, RUN button with Flash animation, Toast on toggle

    Public API:
        Window.new(config, registry) → Window
        window:Show() / :Hide() / :Toggle()
        window:PopulateFromRegistry()
        window:SetFPSVisible(bool)
        window:Destroy()
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local Theme      = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Components)
local Toast      = require(script.Parent.Toast)

local W  = Theme.Window
local BT = Theme.Button
local TG = Theme.Toggle

local Window  = {}
Window.__index = Window

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function tw(obj, info, props) return TweenService:Create(obj, info, props) end

local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or Theme.Radius
    c.Parent = parent
end

local function stroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color           = color or Theme.Border
    s.Thickness       = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
end

local function pad(parent, l, r, t, b)
    local p         = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.PaddingRight  = UDim.new(0, r or 0)
    p.PaddingTop    = UDim.new(0, t or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.Parent = parent
end

-- Lighten-style hover for a TextButton (matches rogue-tower-defense Button hover)
local function addButtonHover(btn, bgNormal, bgHover)
    btn.MouseEnter:Connect(function()
        tw(btn, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {BackgroundColor3 = bgHover}):Play()
    end)
    btn.MouseLeave:Connect(function()
        tw(btn, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {BackgroundColor3 = bgNormal}):Play()
    end)
end

-- ── Constructor ───────────────────────────────────────────────────────────────

function Window.new(config, registry)
    local self        = setmetatable({}, Window)
    self._registry    = registry
    self._config      = config
    self._visible     = false
    self._collapsed   = false
    self._activeCat   = 1
    self._catBtns     = {}
    self._moduleRows  = {}
    self._fpsConn     = nil
    self._fpsLabel    = nil
    self._searchBox   = nil
    self._gui         = nil
    self._mainFrame   = nil
    self._shadow      = nil
    self._sidebar     = nil
    self._moduleScroll = nil

    self:_build()
    return self
end

-- ── Build skeleton ────────────────────────────────────────────────────────────

function Window:_build()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local gui             = Instance.new("ScreenGui")
    gui.Name              = "VainHub"
    gui.ResetOnSpawn      = false
    gui.IgnoreGuiInset    = true
    gui.DisplayOrder      = 100
    gui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
    gui.Parent            = playerGui
    self._gui             = gui

    -- Drop shadow (behind, slightly larger)
    local shadow          = Instance.new("Frame")
    shadow.Size           = UDim2.fromOffset(W.Width + 24, W.Height + 24)
    shadow.AnchorPoint    = Vector2.new(0.5, 0.5)
    shadow.Position       = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.65
    shadow.BorderSizePixel = 0
    shadow.Visible        = false
    shadow.Parent         = gui
    corner(shadow, UDim.new(0, Theme.RadiusLG.Offset + 6))
    self._shadow          = shadow

    -- Main window frame
    local main            = Instance.new("Frame")
    main.Name             = "Window"
    main.Size             = UDim2.fromOffset(W.Width, W.Height)
    main.AnchorPoint      = Vector2.new(0.5, 0.5)
    main.Position         = UDim2.fromScale(0.5, 0.5)
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel  = 0
    main.Visible          = false
    main.ClipsDescendants = true
    main.Parent           = gui
    corner(main, Theme.RadiusLG)
    stroke(main, Theme.Border, 1)
    self._mainFrame       = main

    self:_buildHeader(main)
    self:_buildSidebar(main)
    self:_buildContent(main)
    self:_setupDrag(main)
    self:_setupFPS()
end

-- ── Header ────────────────────────────────────────────────────────────────────

function Window:_buildHeader(parent)
    local accent = self._config.AccentColor or Theme.Accent

    local header          = Instance.new("Frame")
    header.Name           = "Header"
    header.Size           = UDim2.new(1, 0, 0, W.HeaderH)
    header.BackgroundColor3 = Theme.Surface
    header.BorderSizePixel = 0
    header.Parent         = parent
    corner(header, Theme.RadiusLG)

    -- Square off the bottom of the header so it sits flush against content
    local hSquare         = Instance.new("Frame")
    hSquare.Size          = UDim2.new(1, 0, 0, Theme.RadiusLG.Offset)
    hSquare.Position      = UDim2.new(0, 0, 1, -Theme.RadiusLG.Offset)
    hSquare.BackgroundColor3 = Theme.Surface
    hSquare.BorderSizePixel  = 0
    hSquare.Parent        = header

    -- Left accent pip  (same style as rogue-tower-defense window chrome)
    local pip             = Instance.new("Frame")
    pip.Size              = UDim2.fromOffset(3, W.HeaderH - 22)
    pip.Position          = UDim2.fromOffset(14, 11)
    pip.BackgroundColor3  = accent
    pip.BorderSizePixel   = 0
    pip.Parent            = header
    corner(pip, Theme.RadiusFull)

    -- Title
    local title           = Instance.new("TextLabel")
    title.Size            = UDim2.new(0, 110, 1, 0)
    title.Position        = UDim2.fromOffset(26, 0)
    title.BackgroundTransparency = 1
    title.Text            = self._config.Title or "Vain"
    title.Font            = Theme.FontBold
    title.TextSize        = Theme.FontSize.XL
    title.TextColor3      = Theme.Text
    title.TextXAlignment  = Enum.TextXAlignment.Left
    title.Parent          = header

    -- Subtitle
    local sub             = Instance.new("TextLabel")
    sub.Size              = UDim2.new(0, 50, 1, 0)
    sub.Position          = UDim2.new(0, 76, 0, 4)
    sub.BackgroundTransparency = 1
    sub.Text              = self._config.Subtitle or "hub"
    sub.Font              = Theme.Font
    sub.TextSize          = Theme.FontSize.SM
    sub.TextColor3        = Theme.TextMuted
    sub.TextXAlignment    = Enum.TextXAlignment.Left
    sub.Parent            = header

    -- FPS counter
    local fps             = Instance.new("TextLabel")
    fps.Size              = UDim2.fromOffset(72, W.HeaderH)
    fps.AnchorPoint       = Vector2.new(1, 0)
    fps.Position          = UDim2.new(1, -44, 0, 0)
    fps.BackgroundTransparency = 1
    fps.Text              = ""
    fps.Font              = Theme.Font
    fps.TextSize          = Theme.FontSize.XS
    fps.TextColor3        = Theme.TextDim
    fps.TextXAlignment    = Enum.TextXAlignment.Right
    fps.Parent            = header
    self._fpsLabel        = fps

    -- Collapse chevron (TextButton so it captures input without affecting drag)
    local chev            = Instance.new("TextButton")
    chev.Size             = UDim2.fromOffset(36, W.HeaderH)
    chev.AnchorPoint      = Vector2.new(1, 0)
    chev.Position         = UDim2.new(1, -4, 0, 0)
    chev.BackgroundTransparency = 1
    chev.Text             = "▾"
    chev.Font             = Theme.FontBold
    chev.TextSize         = Theme.FontSize.LG
    chev.TextColor3       = Theme.TextDim
    chev.Parent           = header

    chev.MouseEnter:Connect(function()
        tw(chev, Theme.TweenFast, {TextColor3 = Theme.Text}):Play()
    end)
    chev.MouseLeave:Connect(function()
        tw(chev, Theme.TweenFast, {TextColor3 = Theme.TextDim}):Play()
    end)
    chev.MouseButton1Click:Connect(function()
        self._collapsed = not self._collapsed
        if self._collapsed then
            tw(self._mainFrame, Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width, W.HeaderH)}):Play()
            tw(self._shadow,    Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width + 24, W.HeaderH + 24)}):Play()
            chev.Text = "▸"
        else
            tw(self._mainFrame, Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width, W.Height)}):Play()
            tw(self._shadow,    Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width + 24, W.Height + 24)}):Play()
            chev.Text = "▾"
        end
    end)

    -- Separator line
    local sep             = Instance.new("Frame")
    sep.Size              = UDim2.new(1, 0, 0, 1)
    sep.Position          = UDim2.new(0, 0, 1, -1)
    sep.BackgroundColor3  = Theme.Border
    sep.BorderSizePixel   = 0
    sep.Parent            = header
end

-- ── FPS tracker ───────────────────────────────────────────────────────────────

function Window:_setupFPS()
    local hist = {}
    local last = tick()
    self._fpsConn = RunService.RenderStepped:Connect(function()
        if not self._fpsLabel or not self._fpsLabel.Parent then return end
        local now = tick()
        table.insert(hist, 1 / math.max(now - last, 0.001))
        last = now
        if #hist > 20 then table.remove(hist, 1) end
        local sum = 0
        for _, v in ipairs(hist) do sum = sum + v end
        local avg = math.floor(sum / #hist)
        self._fpsLabel.Text       = avg .. " fps"
        self._fpsLabel.TextColor3 = avg >= 50 and Theme.Success
                                  or avg >= 30 and Theme.Warning
                                  or Theme.Danger
    end)
end

function Window:SetFPSVisible(visible)
    if self._fpsLabel then self._fpsLabel.Visible = visible end
end

-- ── Sidebar ───────────────────────────────────────────────────────────────────

function Window:_buildSidebar(parent)
    local sidebar         = Instance.new("Frame")
    sidebar.Name          = "Sidebar"
    sidebar.Size          = UDim2.new(0, W.SidebarW, 1, -W.HeaderH)
    sidebar.Position      = UDim2.fromOffset(0, W.HeaderH)
    sidebar.BackgroundColor3 = Theme.Surface
    sidebar.BorderSizePixel  = 0
    sidebar.ClipsDescendants = true
    sidebar.Parent        = parent
    corner(sidebar, Theme.RadiusLG)

    -- Fill right and top edges
    local rFill           = Instance.new("Frame")
    rFill.Size            = UDim2.new(0, Theme.RadiusLG.Offset, 1, 0)
    rFill.Position        = UDim2.new(1, -Theme.RadiusLG.Offset, 0, 0)
    rFill.BackgroundColor3 = Theme.Surface
    rFill.BorderSizePixel  = 0
    rFill.Parent          = sidebar

    local tFill           = Instance.new("Frame")
    tFill.Size            = UDim2.new(1, 0, 0, Theme.RadiusLG.Offset)
    tFill.BackgroundColor3 = Theme.Surface
    tFill.BorderSizePixel  = 0
    tFill.Parent          = sidebar

    -- 1px divider between sidebar and content area
    local divider         = Instance.new("Frame")
    divider.Size          = UDim2.fromOffset(1, W.Height - W.HeaderH)
    divider.Position      = UDim2.new(0, W.SidebarW - 1, 0, W.HeaderH)
    divider.BackgroundColor3 = Theme.Border
    divider.BorderSizePixel  = 0
    divider.Parent        = parent

    local layout          = Instance.new("UIListLayout")
    layout.FillDirection  = Enum.FillDirection.Vertical
    layout.Padding        = UDim.new(0, 3)
    layout.Parent         = sidebar
    pad(sidebar, 7, 7, 12, 8)

    self._sidebar = sidebar
end

-- ── Content (search bar + module scroll) ─────────────────────────────────────

function Window:_buildContent(parent)
    local content         = Instance.new("Frame")
    content.Name          = "Content"
    content.Size          = UDim2.new(1, -W.SidebarW, 1, -W.HeaderH)
    content.Position      = UDim2.new(0, W.SidebarW, 0, W.HeaderH)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    content.Parent        = parent

    -- Search bar  (styled like rogue-tower-defense NumberInput: bordered, focus ring)
    local searchWrap      = Instance.new("Frame")
    searchWrap.Size       = UDim2.new(1, -(W.Padding * 2), 0, W.SearchH)
    searchWrap.Position   = UDim2.fromOffset(W.Padding, W.Padding)
    searchWrap.BackgroundColor3 = Theme.Surface2
    searchWrap.BorderSizePixel  = 0
    searchWrap.Parent     = content
    corner(searchWrap, UDim.new(0, BT.CornerRadius))
    local searchStroke = stroke(searchWrap, Theme.Border, 1)

    local searchIcon      = Instance.new("TextLabel")
    searchIcon.Size       = UDim2.fromOffset(30, W.SearchH)
    searchIcon.Position   = UDim2.fromOffset(8, 0)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text       = "⌕"
    searchIcon.TextSize   = 16
    searchIcon.TextColor3 = Theme.TextDim
    searchIcon.Parent     = searchWrap

    local searchBox       = Instance.new("TextBox")
    searchBox.Size        = UDim2.new(1, -44, 1, 0)
    searchBox.Position    = UDim2.fromOffset(34, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.PlaceholderText  = "Search modules..."
    searchBox.PlaceholderColor3 = Theme.TextDim
    searchBox.Text        = ""
    searchBox.TextColor3  = Theme.Text
    searchBox.Font        = Theme.Font
    searchBox.TextSize    = Theme.FontSize.SM
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.Parent      = searchWrap
    self._searchBox       = searchBox

    searchBox.Focused:Connect(function()
        tw(searchStroke, Theme.TweenFast, {Color = Theme.Accent}):Play()
        tw(searchWrap,   Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
    end)
    searchBox.FocusLost:Connect(function()
        tw(searchStroke, Theme.TweenFast, {Color = Theme.Border}):Play()
        tw(searchWrap,   Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
    end)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local q = searchBox.Text:lower()
        for _, data in ipairs(self._moduleRows) do
            data.frame.Visible = (q == "" or data.name:find(q, 1, true) ~= nil)
        end
    end)

    -- Module scroll frame
    local scrollTop       = W.Padding + W.SearchH + 6
    local scroll          = Instance.new("ScrollingFrame")
    scroll.Name           = "ModuleScroll"
    scroll.Size           = UDim2.new(1, 0, 1, -scrollTop)
    scroll.Position       = UDim2.fromOffset(0, scrollTop)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.ScrollBarImageTransparency = 0.4
    scroll.CanvasSize     = UDim2.fromScale(1, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent         = content
    self._moduleScroll    = scroll

    local layout          = Instance.new("UIListLayout")
    layout.FillDirection  = Enum.FillDirection.Vertical
    layout.Padding        = UDim.new(0, 4)
    layout.Parent         = scroll
    pad(scroll, W.Padding, W.Padding, W.Padding / 2, W.Padding)
end

-- ── Category population ───────────────────────────────────────────────────────

function Window:PopulateFromRegistry()
    for _, entry in ipairs(self._catBtns) do
        if entry.btn and entry.btn.Parent then entry.btn:Destroy() end
    end
    self._catBtns = {}

    local cats = self._registry:GetCategories()
    for i, cat in ipairs(cats) do
        local active = (i == self._activeCat)
        local accent = self._config.AccentColor or Theme.Accent

        -- Category button  (Lighten hover animation matching rogue-tower-defense Button)
        local btn     = Instance.new("TextButton")
        btn.Size      = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = active and Theme.Surface2 or BT.Background
        btn.BackgroundTransparency = active and 0 or 1
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Font      = active and Theme.FontSemi or Theme.Font
        btn.TextSize  = Theme.FontSize.SM
        btn.TextColor3 = active and Theme.Text or Theme.TextMuted
        btn.Text      = cat.name
        btn.Parent    = self._sidebar
        corner(btn, UDim.new(0, BT.CornerRadius))

        -- Active indicator bar (left edge)
        local ind     = Instance.new("Frame")
        ind.Size      = UDim2.fromOffset(3, 16)
        ind.Position  = UDim2.fromOffset(0, 8)
        ind.BackgroundColor3 = accent
        ind.BorderSizePixel  = 0
        ind.Visible   = active
        ind.Parent    = btn
        corner(ind, Theme.RadiusFull)

        self._catBtns[i] = { btn = btn, ind = ind }

        local idx = i
        btn.MouseButton1Click:Connect(function() self:_selectCategory(idx) end)
        btn.MouseEnter:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
                    BackgroundTransparency = 0,
                    BackgroundColor3       = BT.Hover,
                    TextColor3             = Theme.Text,
                }):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {
                    BackgroundTransparency = 1,
                    TextColor3             = Theme.TextMuted,
                }):Play()
            end
        end)
    end

    if #cats > 0 then self:_selectCategory(self._activeCat) end
end

function Window:_selectCategory(idx)
    if self._searchBox then self._searchBox.Text = "" end
    self._moduleRows = {}

    local accent = self._config.AccentColor or Theme.Accent
    for i, entry in ipairs(self._catBtns) do
        local active = (i == idx)
        entry.ind.Visible = active
        entry.btn.Font = active and Theme.FontSemi or Theme.Font
        tw(entry.btn, Theme.TweenFast, {
            BackgroundTransparency = active and 0 or 1,
            BackgroundColor3       = Theme.Surface2,
            TextColor3             = active and Theme.Text or Theme.TextMuted,
        }):Play()
        entry.ind.BackgroundColor3 = accent
    end
    self._activeCat = idx

    for _, child in ipairs(self._moduleScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local cat = self._registry:GetCategories()[idx]
    if not cat then return end
    for _, mod in ipairs(cat.modules) do
        self:_buildModuleRow(mod)
    end
end

-- ── Module row ────────────────────────────────────────────────────────────────
-- Toggle pill uses exact SliderToggle specs from Theme.Toggle.
-- RUN button uses rogue-tower-defense Button Flash animation.
-- Toggling a module fires a Toast notification.

function Window:_buildModuleRow(module)
    local hasSettings = #module.Settings > 0
    local accent      = self._config.AccentColor or Theme.Accent

    local expandH = 0
    for _, s in ipairs(module.Settings) do
        expandH = expandH + (Theme.SettingH[s.Type] or 32) + 4
    end
    local expandPad   = 12
    local totalExpand = expandH + expandPad * 2
    local expanded    = false

    -- SliderToggle dot travel calc
    local dotTravel = TG.TrackWidth - TG.DotSize - 4
    local dotY      = (TG.TrackHeight - TG.DotSize) / 2
    local dotXOff   = 2
    local dotXOn    = 2 + dotTravel

    -- Row container
    local row         = Instance.new("Frame")
    row.Name          = module.Name
    row.Size          = UDim2.new(1, 0, 0, W.ModuleH)
    row.BackgroundColor3 = BT.Background
    row.BorderSizePixel  = 0
    row.ClipsDescendants = true
    row.Parent        = self._moduleScroll
    corner(row, UDim.new(0, BT.CornerRadius))
    stroke(row, Theme.Border, 1)

    table.insert(self._moduleRows, { name = module.Name:lower(), frame = row })

    -- ── Top strip ─────────────────────────────────────────────────────────────
    local strip       = Instance.new("Frame")
    strip.Size        = UDim2.new(1, 0, 0, W.ModuleH)
    strip.BackgroundTransparency = 1
    strip.Parent      = row

    -- Status dot (8px, accent when enabled)
    local dot         = Instance.new("Frame")
    dot.Size          = UDim2.fromOffset(8, 8)
    dot.Position      = UDim2.fromOffset(12, (W.ModuleH - 8) / 2)
    dot.BackgroundColor3 = module.Enabled and accent or Theme.Surface3
    dot.BorderSizePixel  = 0
    dot.Parent        = strip
    corner(dot, Theme.RadiusFull)

    -- Module name
    local nameL       = Instance.new("TextLabel")
    nameL.Size        = UDim2.new(1, -130, 1, 0)
    nameL.Position    = UDim2.fromOffset(28, 0)
    nameL.BackgroundTransparency = 1
    nameL.Text        = module.Name
    nameL.Font        = module.Enabled and Theme.FontSemi or Theme.Font
    nameL.TextSize    = Theme.FontSize.MD
    nameL.TextColor3  = module.Enabled and Theme.Text or Theme.TextMuted
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.Parent      = strip

    -- Keybind hint
    if module.Keybind then
        local kb      = Instance.new("TextLabel")
        kb.Size       = UDim2.fromOffset(36, W.ModuleH)
        kb.AnchorPoint = Vector2.new(1, 0)
        kb.Position   = UDim2.new(1, hasSettings and -62 or -44, 0, 0)
        kb.BackgroundTransparency = 1
        kb.Text       = "[" .. module.Keybind.Name:sub(1, 3):upper() .. "]"
        kb.Font       = Theme.Font
        kb.TextSize   = Theme.FontSize.XS
        kb.TextColor3 = Theme.TextDim
        kb.TextXAlignment = Enum.TextXAlignment.Right
        kb.Parent     = strip
    end

    local rightOff = hasSettings and -30 or -10

    if module.Behavior == "Toggleable" then
        -- SliderToggle pill (exact rogue-tower-defense SliderToggle)
        local pill    = Instance.new("TextButton")
        pill.Size     = UDim2.fromOffset(TG.TrackWidth, TG.TrackHeight)
        pill.AnchorPoint = Vector2.new(1, 0.5)
        pill.Position = UDim2.new(1, rightOff, 0.5, 0)
        pill.BackgroundColor3 = module.Enabled and accent or TG.TrackOff
        pill.BorderSizePixel  = 0
        pill.Text    = ""
        pill.AutoButtonColor = false
        pill.Parent  = strip
        corner(pill, UDim.new(0, TG.CornerRadius))

        local knob    = Instance.new("Frame")
        knob.Size     = UDim2.fromOffset(TG.DotSize, TG.DotSize)
        knob.Position = UDim2.fromOffset(module.Enabled and dotXOn or dotXOff, dotY)
        knob.BackgroundColor3 = TG.Dot
        knob.BorderSizePixel  = 0
        knob.Parent  = pill
        corner(knob, UDim.new(0, TG.CornerRadius))

        local tweenInfo = TweenInfo.new(TG.TransitionTime, Enum.EasingStyle.Quad)

        pill.MouseButton1Click:Connect(function()
            module:Trigger()
        end)

        module:OnStateChange(function(state)
            local on = state == true
            tw(pill,  tweenInfo, {BackgroundColor3 = on and accent or TG.TrackOff}):Play()
            tw(knob,  tweenInfo, {Position = UDim2.fromOffset(on and dotXOn or dotXOff, dotY)}):Play()
            tw(dot,   Theme.TweenFast, {BackgroundColor3 = on and accent or Theme.Surface3}):Play()
            tw(nameL, Theme.TweenFast, {TextColor3 = on and Theme.Text or Theme.TextMuted}):Play()
            nameL.Font = on and Theme.FontSemi or Theme.Font
            -- Toast notification matching rogue-tower-defense style
            Toast.show(module.Name .. (on and " enabled" or " disabled"), {
                Variant = on and "success" or "info",
                Duration = 2,
            })
        end)

    else
        -- RUN button with rogue-tower-defense Flash animation
        local execBtn = Instance.new("TextButton")
        execBtn.Size  = UDim2.fromOffset(40, 22)
        execBtn.AnchorPoint = Vector2.new(1, 0.5)
        execBtn.Position    = UDim2.new(1, rightOff, 0.5, 0)
        execBtn.BackgroundColor3 = accent
        execBtn.BorderSizePixel  = 0
        execBtn.AutoButtonColor  = false
        execBtn.Font  = Theme.FontBold
        execBtn.TextSize = Theme.FontSize.XS
        execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        execBtn.Text  = "RUN"
        execBtn.Parent = strip
        corner(execBtn, UDim.new(0, BT.CornerRadius))

        -- Flash animation on click (rogue-tower-defense Button ClickAnimation = "Flash")
        execBtn.MouseButton1Down:Connect(function()
            tw(execBtn, TweenInfo.new(0.08, Enum.EasingStyle.Sine), {BackgroundColor3 = Theme.Success}):Play()
        end)
        execBtn.MouseButton1Up:Connect(function()
            tw(execBtn, TweenInfo.new(0.22, Enum.EasingStyle.Sine), {BackgroundColor3 = accent}):Play()
        end)
        execBtn.MouseButton1Click:Connect(function()
            module:Trigger()
            Toast.show(module.Name .. " executed", { Variant = "info", Duration = 1.5 })
        end)

        addButtonHover(execBtn, accent, Theme.AccentHover)

        module:OnStateChange(function()
            tw(dot, Theme.TweenFast, {BackgroundColor3 = accent}):Play()
            task.delay(0.4, function()
                tw(dot, Theme.Tween, {BackgroundColor3 = Theme.Surface3}):Play()
            end)
        end)
    end

    -- ── Settings panel + expand chevron ──────────────────────────────────────
    if hasSettings then
        local chev    = Instance.new("TextLabel")
        chev.Size     = UDim2.fromOffset(22, W.ModuleH)
        chev.AnchorPoint = Vector2.new(1, 0)
        chev.Position = UDim2.new(1, -8, 0, 0)
        chev.BackgroundTransparency = 1
        chev.Text     = "›"
        chev.Font     = Theme.FontBold
        chev.TextSize = Theme.FontSize.LG
        chev.TextColor3 = Theme.TextDim
        chev.TextXAlignment = Enum.TextXAlignment.Center
        chev.Rotation = 90
        chev.Parent   = strip

        local settingsPanel = Instance.new("Frame")
        settingsPanel.Size  = UDim2.new(1, -16, 0, totalExpand)
        settingsPanel.Position = UDim2.new(0, 8, 0, W.ModuleH + 4)
        settingsPanel.BackgroundTransparency = 1
        settingsPanel.Parent = row

        local sLayout = Instance.new("UIListLayout")
        sLayout.FillDirection = Enum.FillDirection.Vertical
        sLayout.Padding       = UDim.new(0, 4)
        sLayout.Parent        = settingsPanel

        local sPad = Instance.new("UIPadding")
        sPad.PaddingTop    = UDim.new(0, expandPad)
        sPad.PaddingBottom = UDim.new(0, expandPad)
        sPad.Parent        = settingsPanel

        for _, setting in ipairs(module.Settings) do
            local comp = Components.Build(setting)
            if comp then comp.Parent = settingsPanel end
        end

        local sep   = Instance.new("Frame")
        sep.Size    = UDim2.new(1, -16, 0, 1)
        sep.Position = UDim2.new(0, 8, 0, W.ModuleH)
        sep.BackgroundColor3 = Theme.Border
        sep.BackgroundTransparency = 1
        sep.BorderSizePixel = 0
        sep.Parent  = row

        local expandBtn = Instance.new("TextButton")
        expandBtn.Size  = UDim2.fromOffset(30, W.ModuleH)
        expandBtn.AnchorPoint = Vector2.new(1, 0)
        expandBtn.Position    = UDim2.new(1, 0, 0, 0)
        expandBtn.BackgroundTransparency = 1
        expandBtn.Text  = ""
        expandBtn.ZIndex = 3
        expandBtn.Parent = strip

        expandBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            local targetH = expanded and (W.ModuleH + totalExpand + 4) or W.ModuleH
            tw(row,  Theme.TweenSlow, {Size = UDim2.new(1, 0, 0, targetH)}):Play()
            tw(chev, Theme.TweenFast, {
                Rotation   = expanded and 270 or 90,
                TextColor3 = expanded and accent or Theme.TextDim,
            }):Play()
            tw(sep, Theme.TweenFast, {BackgroundTransparency = expanded and 0 or 1}):Play()
        end)
    end

    -- ── Row hover + click (row-wide toggle area) ──────────────────────────────
    local rowBtn  = Instance.new("TextButton")
    rowBtn.Size   = UDim2.new(1, hasSettings and -30 or 0, 0, W.ModuleH)
    rowBtn.BackgroundTransparency = 1
    rowBtn.Text   = ""
    rowBtn.ZIndex = 2
    rowBtn.Parent = strip

    rowBtn.MouseEnter:Connect(function()
        tw(row, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {BackgroundColor3 = BT.Hover}):Play()
    end)
    rowBtn.MouseLeave:Connect(function()
        tw(row, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {BackgroundColor3 = BT.Background}):Play()
    end)
    rowBtn.MouseButton1Click:Connect(function()
        if module.Behavior == "Toggleable" then module:Trigger() end
    end)

    return row
end

-- ── Drag ──────────────────────────────────────────────────────────────────────

function Window:_setupDrag(frame)
    local header   = frame:FindFirstChild("Header")
    local dragSrc  = header or frame
    local dragging = false
    local startInput, startPos

    dragSrc.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging   = true
            startInput = Vector2.new(inp.Position.X, inp.Position.Y)
            startPos   = frame.AbsolutePosition
            frame.AnchorPoint      = Vector2.zero
            frame.Position         = UDim2.fromOffset(startPos.X, startPos.Y)
            self._shadow.AnchorPoint = Vector2.zero
            self._shadow.Position    = UDim2.fromOffset(startPos.X - 12, startPos.Y - 12)
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if not dragging or inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = Vector2.new(inp.Position.X, inp.Position.Y) - startInput
        local nx, ny = startPos.X + delta.X, startPos.Y + delta.Y
        frame.Position        = UDim2.fromOffset(nx, ny)
        self._shadow.Position = UDim2.fromOffset(nx - 12, ny - 12)
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- ── Visibility ────────────────────────────────────────────────────────────────

function Window:Show()
    self._mainFrame.Visible = true
    self._shadow.Visible    = true
    self._mainFrame.Size    = UDim2.fromOffset(W.Width, 8)
    self._shadow.Size       = UDim2.fromOffset(W.Width + 24, 32)
    tw(self._mainFrame, Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width, W.Height)}):Play()
    tw(self._shadow,    Theme.TweenSpring, {Size = UDim2.fromOffset(W.Width + 24, W.Height + 24)}):Play()
    self._visible = true
end

function Window:Hide()
    tw(self._mainFrame, Theme.Tween, {Size = UDim2.fromOffset(W.Width, 8)}):Play()
    tw(self._shadow,    Theme.Tween, {Size = UDim2.fromOffset(W.Width + 24, 32)}):Play()
    task.delay(Theme.Tween.Time + 0.05, function()
        if self._mainFrame then self._mainFrame.Visible = false end
        if self._shadow    then self._shadow.Visible    = false end
    end)
    self._visible = false
end

function Window:Toggle()
    if self._visible then self:Hide() else self:Show() end
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

function Window:Destroy()
    if self._fpsConn then
        self._fpsConn:Disconnect()
        self._fpsConn = nil
    end
    if self._gui then
        self._gui:Destroy()
        self._gui = nil
    end
end

return Window
