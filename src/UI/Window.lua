--[[
    UI/Window.lua  –  Vain hub window. Redesigned with rogue-tower-defense design
    language: ultra-dark palette, horizontal category tabs, card-style module rows,
    left-edge enable indicator bars, and smooth spring animations throughout.
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local Theme      = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Components)
local Toast      = require(script.Parent.Toast)

-- ── Local design constants ─────────────────────────────────────────────────────
local C_BG         = Color3.fromRGB(11,  11,  11)
local C_PANEL      = Color3.fromRGB(16,  16,  16)
local C_CARD       = Color3.fromRGB(20,  20,  20)
local C_CARD_HOVER = Color3.fromRGB(26,  26,  26)
local C_WIN_BDR    = Color3.fromRGB(58,  58,  58)
local C_SEP        = Color3.fromRGB(26,  26,  26)
local C_BORDER     = Color3.fromRGB(34,  34,  34)
local C_MUTED      = Color3.fromRGB(72,  72,  72)
local C_DIM        = Color3.fromRGB(46,  46,  46)

local WIN_W  = 720
local WIN_H  = 460
local HEAD_H = 46
local TAB_H  = 38
local CONT_Y = HEAD_H + TAB_H
local PAD    = 10
local MOD_H  = 40
local SRCH_H = 32

local R8    = UDim.new(0, 8)
local R5    = UDim.new(0, 5)
local RFULL = UDim.new(1, 0)

local Window  = {}
Window.__index = Window

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function tw(obj, info, props) return TweenService:Create(obj, info, props) end

local function mkCorner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or R8
    c.Parent = parent
end

local function mkStroke(parent, color, thick)
    local s = Instance.new("UIStroke")
    s.Color           = color or C_BORDER
    s.Thickness       = thick or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent          = parent
    return s
end

-- ── Constructor ───────────────────────────────────────────────────────────────

function Window.new(config, registry)
    local self             = setmetatable({}, Window)
    self._registry         = registry
    self._config           = config
    self._visible          = false
    self._activeCat        = 1
    self._catBtns          = {}
    self._moduleRows       = {}
    self._fpsConn          = nil
    self._fpsLabel         = nil
    self._searchBox        = nil
    self._gui              = nil
    self._mainFrame        = nil
    self._shadow           = nil
    self._header           = nil
    self._tabBar           = nil
    self._moduleScroll     = nil
    self._tooltipFrame     = nil
    self._tooltipLabel     = nil
    self._pip              = nil
    self:_build()
    return self
end

-- ── Build ─────────────────────────────────────────────────────────────────────

function Window:_build()
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    local gui          = Instance.new("ScreenGui")
    gui.Name           = "VainHub"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 100
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent         = playerGui
    self._gui          = gui

    local shadow                    = Instance.new("Frame")
    shadow.Size                     = UDim2.fromOffset(WIN_W + 24, WIN_H + 24)
    shadow.AnchorPoint              = Vector2.new(0.5, 0.5)
    shadow.Position                 = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3         = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency   = 0.55
    shadow.BorderSizePixel          = 0
    shadow.Visible                  = false
    shadow.Parent                   = gui
    mkCorner(shadow, UDim.new(0, 14))
    self._shadow = shadow

    local outer                    = Instance.new("Frame")
    outer.Name                     = "WindowOuter"
    outer.Size                     = UDim2.fromOffset(WIN_W, WIN_H)
    outer.AnchorPoint              = Vector2.new(0.5, 0.5)
    outer.Position                 = UDim2.fromScale(0.5, 0.5)
    outer.BackgroundColor3         = C_WIN_BDR
    outer.BackgroundTransparency   = 0
    outer.BorderSizePixel          = 0
    outer.Visible                  = false
    outer.Parent                   = gui
    mkCorner(outer, UDim.new(0, 10))
    self._mainFrame = outer

    local inner                    = Instance.new("Frame")
    inner.Name                     = "WindowInner"
    inner.Size                     = UDim2.new(1, -4, 1, -4)
    inner.AnchorPoint              = Vector2.new(0.5, 0.5)
    inner.Position                 = UDim2.fromScale(0.5, 0.5)
    inner.BackgroundColor3         = C_BG
    inner.BorderSizePixel          = 0
    inner.ClipsDescendants         = true
    inner.Parent                   = outer
    mkCorner(inner, R8)

    local ttFrame                  = Instance.new("Frame")
    ttFrame.Name                   = "Tooltip"
    ttFrame.Size                   = UDim2.fromOffset(4, 24)
    ttFrame.AutomaticSize          = Enum.AutomaticSize.X
    ttFrame.BackgroundColor3       = Color3.fromRGB(17, 17, 17)
    ttFrame.BorderSizePixel        = 0
    ttFrame.Visible                = false
    ttFrame.ZIndex                 = 500
    ttFrame.Parent                 = gui
    mkCorner(ttFrame, UDim.new(0, 4))
    mkStroke(ttFrame, Color3.fromRGB(44, 44, 44), 1)

    local ttPad                    = Instance.new("UIPadding")
    ttPad.PaddingLeft              = UDim.new(0, 8)
    ttPad.PaddingRight             = UDim.new(0, 8)
    ttPad.Parent                   = ttFrame

    local ttLabel                  = Instance.new("TextLabel")
    ttLabel.Size                   = UDim2.new(0, 0, 1, 0)
    ttLabel.AutomaticSize          = Enum.AutomaticSize.X
    ttLabel.BackgroundTransparency = 1
    ttLabel.Text                   = ""
    ttLabel.Font                   = Theme.Font
    ttLabel.TextSize               = 11
    ttLabel.TextColor3             = Color3.fromRGB(150, 150, 150)
    ttLabel.ZIndex                 = 501
    ttLabel.Parent                 = ttFrame
    self._tooltipFrame = ttFrame
    self._tooltipLabel = ttLabel

    self:_buildHeader(inner)
    self:_buildTabBar(inner)
    self:_buildContent(inner)
    self:_setupDrag(outer)
    self:_setupTooltipTracking()
    self:_setupFPS()
end

-- ── Tooltip ───────────────────────────────────────────────────────────────────

function Window:_addTooltip(element, text)
    element.MouseEnter:Connect(function()
        if not self._tooltipFrame then return end
        self._tooltipLabel.Text = text
        local mp = UserInputService:GetMouseLocation()
        self._tooltipFrame.Position = UDim2.fromOffset(mp.X + 12, mp.Y + 18)
        self._tooltipFrame.Visible  = true
    end)
    element.MouseLeave:Connect(function()
        if self._tooltipFrame then self._tooltipFrame.Visible = false end
    end)
end

function Window:_setupTooltipTracking()
    UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if self._tooltipFrame and self._tooltipFrame.Visible then
            self._tooltipFrame.Position =
                UDim2.fromOffset(inp.Position.X + 12, inp.Position.Y + 18)
        end
    end)
end

-- ── Header ────────────────────────────────────────────────────────────────────

function Window:_buildHeader(parent)
    local accent = self._config.AccentColor or Theme.Accent

    local header              = Instance.new("Frame")
    header.Name               = "Header"
    header.Size               = UDim2.new(1, 0, 0, HEAD_H)
    header.BackgroundColor3   = C_PANEL
    header.BorderSizePixel    = 0
    header.Parent             = parent
    mkCorner(header, R8)

    local sq                  = Instance.new("Frame")
    sq.Size                   = UDim2.new(1, 0, 0, 8)
    sq.Position               = UDim2.new(0, 0, 1, -8)
    sq.BackgroundColor3       = C_PANEL
    sq.BorderSizePixel        = 0
    sq.Parent                 = header
    self._header = header

    local pip                 = Instance.new("Frame")
    pip.Size                  = UDim2.fromOffset(3, HEAD_H - 20)
    pip.Position              = UDim2.fromOffset(14, 10)
    pip.BackgroundColor3      = accent
    pip.BorderSizePixel       = 0
    pip.Parent                = header
    mkCorner(pip, RFULL)
    self._pip = pip

    local title               = Instance.new("TextLabel")
    title.Size                = UDim2.new(1, -140, 1, 0)
    title.Position            = UDim2.fromOffset(24, 0)
    title.BackgroundTransparency = 1
    title.Text                = self._config.Title or "Vain"
    title.Font                = Theme.FontBold
    title.TextSize            = 14
    title.TextColor3          = Theme.Text
    title.TextXAlignment      = Enum.TextXAlignment.Left
    title.Parent              = header

    local fps                 = Instance.new("TextLabel")
    fps.Size                  = UDim2.fromOffset(70, HEAD_H)
    fps.AnchorPoint           = Vector2.new(1, 0)
    fps.Position              = UDim2.new(1, -10, 0, 0)
    fps.BackgroundTransparency = 1
    fps.Text                  = ""
    fps.Font                  = Theme.Font
    fps.TextSize              = 11
    fps.TextColor3            = C_MUTED
    fps.TextXAlignment        = Enum.TextXAlignment.Right
    fps.Visible               = false
    fps.Parent                = header
    self._fpsLabel = fps
    self:_addTooltip(fps, "Frames per second")

    local sep                 = Instance.new("Frame")
    sep.Size                  = UDim2.new(1, 0, 0, 1)
    sep.Position              = UDim2.new(0, 0, 1, -1)
    sep.BackgroundColor3      = C_SEP
    sep.BorderSizePixel       = 0
    sep.Parent                = header
end

-- ── FPS ───────────────────────────────────────────────────────────────────────

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

-- ── Tab bar ───────────────────────────────────────────────────────────────────

function Window:_buildTabBar(parent)
    local bar              = Instance.new("Frame")
    bar.Name               = "TabBar"
    bar.Size               = UDim2.new(1, 0, 0, TAB_H)
    bar.Position           = UDim2.fromOffset(0, HEAD_H)
    bar.BackgroundColor3   = C_PANEL
    bar.BorderSizePixel    = 0
    bar.Parent             = parent

    local layout           = Instance.new("UIListLayout")
    layout.FillDirection   = Enum.FillDirection.Horizontal
    layout.Padding         = UDim.new(0, 2)
    layout.SortOrder       = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent          = bar

    local padding          = Instance.new("UIPadding")
    padding.PaddingLeft    = UDim.new(0, PAD)
    padding.PaddingRight   = UDim.new(0, PAD)
    padding.Parent         = bar

    local sep              = Instance.new("Frame")
    sep.Size               = UDim2.new(1, 0, 0, 1)
    sep.Position           = UDim2.new(0, 0, 1, -1)
    sep.BackgroundColor3   = C_SEP
    sep.BorderSizePixel    = 0
    sep.Parent             = bar

    self._tabBar = bar
end

-- ── Content ───────────────────────────────────────────────────────────────────

function Window:_buildContent(parent)
    local content              = Instance.new("Frame")
    content.Name               = "Content"
    content.Size               = UDim2.new(1, 0, 1, -CONT_Y)
    content.Position           = UDim2.fromOffset(0, CONT_Y)
    content.BackgroundTransparency = 1
    content.ClipsDescendants   = true
    content.Parent             = parent

    local searchWrap           = Instance.new("Frame")
    searchWrap.Size            = UDim2.new(1, -(PAD * 2), 0, SRCH_H)
    searchWrap.Position        = UDim2.fromOffset(PAD, PAD)
    searchWrap.BackgroundColor3 = C_CARD
    searchWrap.BorderSizePixel  = 0
    searchWrap.Parent          = content
    mkCorner(searchWrap, R5)
    local searchStroke = mkStroke(searchWrap, C_BORDER, 1)
    self:_addTooltip(searchWrap, "Filter modules by name")

    local searchIcon           = Instance.new("TextLabel")
    searchIcon.Size            = UDim2.fromOffset(28, SRCH_H)
    searchIcon.Position        = UDim2.fromOffset(6, 0)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text            = "⌕"
    searchIcon.TextSize        = 15
    searchIcon.TextColor3      = C_MUTED
    searchIcon.Parent          = searchWrap

    local searchBox            = Instance.new("TextBox")
    searchBox.Size             = UDim2.new(1, -36, 1, 0)
    searchBox.Position         = UDim2.fromOffset(28, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.PlaceholderText  = "Search modules..."
    searchBox.PlaceholderColor3 = C_MUTED
    searchBox.Text             = ""
    searchBox.TextColor3       = Theme.Text
    searchBox.Font             = Theme.Font
    searchBox.TextSize         = 12
    searchBox.TextXAlignment   = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.Parent           = searchWrap
    self._searchBox            = searchBox

    searchBox.Focused:Connect(function()
        tw(searchStroke, Theme.TweenFast, {Color = Theme.Accent}):Play()
    end)
    searchBox.FocusLost:Connect(function()
        tw(searchStroke, Theme.TweenFast, {Color = C_BORDER}):Play()
    end)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local q = searchBox.Text:lower()
        for _, data in ipairs(self._moduleRows) do
            data.frame.Visible = (q == "" or data.name:find(q, 1, true) ~= nil)
        end
    end)

    local scrollTop            = PAD + SRCH_H + 6
    local scroll               = Instance.new("ScrollingFrame")
    scroll.Name                = "ModuleScroll"
    scroll.Size                = UDim2.new(1, 0, 1, -scrollTop)
    scroll.Position            = UDim2.fromOffset(0, scrollTop)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel     = 0
    scroll.ScrollBarThickness  = 3
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.ScrollBarImageTransparency = 0.4
    scroll.CanvasSize          = UDim2.fromScale(1, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent              = content
    self._moduleScroll         = scroll

    local layout               = Instance.new("UIListLayout")
    layout.FillDirection       = Enum.FillDirection.Vertical
    layout.Padding             = UDim.new(0, 4)
    layout.Parent              = scroll

    local scrollPad            = Instance.new("UIPadding")
    scrollPad.PaddingLeft      = UDim.new(0, PAD)
    scrollPad.PaddingRight     = UDim.new(0, PAD)
    scrollPad.PaddingTop       = UDim.new(0, 5)
    scrollPad.PaddingBottom    = UDim.new(0, PAD)
    scrollPad.Parent           = scroll
end

-- ── Category population ───────────────────────────────────────────────────────

function Window:PopulateFromRegistry()
    for _, entry in ipairs(self._catBtns) do
        if entry.btn and entry.btn.Parent then entry.btn:Destroy() end
    end
    self._catBtns = {}

    local cats   = self._registry:GetCategories()
    local accent = self._config.AccentColor or Theme.Accent

    for i, cat in ipairs(cats) do
        local active = (i == self._activeCat)

        local btn              = Instance.new("TextButton")
        btn.AutomaticSize      = Enum.AutomaticSize.X
        btn.Size               = UDim2.fromOffset(0, TAB_H - 8)
        btn.BackgroundTransparency = 1
        btn.BorderSizePixel    = 0
        btn.AutoButtonColor    = false
        btn.Font               = active and Theme.FontSemi or Theme.Font
        btn.TextSize           = 12
        btn.TextColor3         = active and Theme.Text or C_MUTED
        btn.Text               = cat.name
        btn.LayoutOrder        = i
        btn.Parent             = self._tabBar

        local bPad             = Instance.new("UIPadding")
        bPad.PaddingLeft       = UDim.new(0, 10)
        bPad.PaddingRight      = UDim.new(0, 10)
        bPad.Parent            = btn

        local underline        = Instance.new("Frame")
        underline.Size         = UDim2.new(1, 0, 0, 2)
        underline.Position     = UDim2.new(0, 0, 1, 2)
        underline.BackgroundColor3 = accent
        underline.BackgroundTransparency = active and 0 or 1
        underline.BorderSizePixel = 0
        underline.Parent       = btn

        self._catBtns[i] = { btn = btn, underline = underline }

        local idx = i
        btn.MouseButton1Click:Connect(function() self:_selectCategory(idx) end)
        btn.MouseEnter:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, TweenInfo.new(0.15), {TextColor3 = Theme.Text}):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, TweenInfo.new(0.15), {TextColor3 = C_MUTED}):Play()
            end
        end)
    end

    if #cats > 0 then self:_selectCategory(self._activeCat) end
end

function Window:_selectCategory(idx)
    if self._searchBox then self._searchBox.Text = "" end
    self._moduleRows = {}
    if self._tooltipFrame then self._tooltipFrame.Visible = false end

    local accent = self._config.AccentColor or Theme.Accent

    for i, entry in ipairs(self._catBtns) do
        local active = (i == idx)
        entry.btn.Font = active and Theme.FontSemi or Theme.Font
        tw(entry.btn, Theme.TweenFast, {
            TextColor3 = active and Theme.Text or C_MUTED,
        }):Play()
        tw(entry.underline, Theme.TweenFast, {
            BackgroundTransparency = active and 0 or 1,
            BackgroundColor3       = accent,
        }):Play()
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

function Window:_buildModuleRow(module)
    local hasSettings = #module.Settings > 0
    local accent      = self._config.AccentColor or Theme.Accent

    local expandH = 0
    for _, s in ipairs(module.Settings) do
        expandH = expandH + (Theme.SettingH[s.Type] or 32) + 4
    end
    local expandPad   = 10
    local totalExpand = expandH + expandPad * 2
    local expanded    = false

    local TG        = Theme.Toggle
    local dotTravel = TG.TrackWidth - TG.DotSize - 4
    local dotY      = (TG.TrackHeight - TG.DotSize) / 2
    local dotXOff   = 2
    local dotXOn    = 2 + dotTravel

    local row              = Instance.new("Frame")
    row.Name               = module.Name
    row.Size               = UDim2.new(1, 0, 0, MOD_H)
    row.BackgroundColor3   = C_CARD
    row.BorderSizePixel    = 0
    row.ClipsDescendants   = true
    row.Parent             = self._moduleScroll
    mkCorner(row, R5)
    mkStroke(row, C_BORDER, 1)
    table.insert(self._moduleRows, { name = module.Name:lower(), frame = row })

    local indBar               = Instance.new("Frame")
    indBar.Size                = UDim2.new(0, 2, 1, 0)
    indBar.BackgroundColor3    = accent
    indBar.BackgroundTransparency = module.Enabled and 0 or 1
    indBar.BorderSizePixel     = 0
    indBar.ZIndex              = 2
    indBar.Parent              = row

    local strip                = Instance.new("Frame")
    strip.Size                 = UDim2.new(1, 0, 0, MOD_H)
    strip.BackgroundTransparency = 1
    strip.Parent               = row

    local nameL                = Instance.new("TextLabel")
    nameL.Size                 = UDim2.new(1, -130, 1, 0)
    nameL.Position             = UDim2.fromOffset(10, 0)
    nameL.BackgroundTransparency = 1
    nameL.Text                 = module.Name
    nameL.Font                 = module.Enabled and Theme.FontSemi or Theme.Font
    nameL.TextSize             = 12
    nameL.TextColor3           = module.Enabled and Theme.Text or C_MUTED
    nameL.TextXAlignment       = Enum.TextXAlignment.Left
    nameL.Parent               = strip

    if module.Keybind then
        local kb               = Instance.new("TextLabel")
        kb.Size                = UDim2.fromOffset(32, MOD_H)
        kb.AnchorPoint         = Vector2.new(1, 0)
        kb.Position            = UDim2.new(1, hasSettings and -66 or -48, 0, 0)
        kb.BackgroundTransparency = 1
        kb.Text                = "[" .. module.Keybind.Name:sub(1, 3):upper() .. "]"
        kb.Font                = Theme.Font
        kb.TextSize            = 10
        kb.TextColor3          = C_MUTED
        kb.TextXAlignment      = Enum.TextXAlignment.Right
        kb.Parent              = strip
    end

    local rightOff = hasSettings and -30 or -10

    if module.Behavior == "Toggleable" then
        local pill             = Instance.new("TextButton")
        pill.Size              = UDim2.fromOffset(TG.TrackWidth, TG.TrackHeight)
        pill.AnchorPoint       = Vector2.new(1, 0.5)
        pill.Position          = UDim2.new(1, rightOff, 0.5, 0)
        pill.BackgroundColor3  = module.Enabled and accent or TG.TrackOff
        pill.BorderSizePixel   = 0
        pill.Text              = ""
        pill.AutoButtonColor   = false
        pill.Parent            = strip
        mkCorner(pill, UDim.new(0, TG.CornerRadius))
        self:_addTooltip(pill, "Toggle " .. module.Name)

        local knob             = Instance.new("Frame")
        knob.Size              = UDim2.fromOffset(TG.DotSize, TG.DotSize)
        knob.Position          = UDim2.fromOffset(module.Enabled and dotXOn or dotXOff, dotY)
        knob.BackgroundColor3  = TG.Dot
        knob.BorderSizePixel   = 0
        knob.Parent            = pill
        mkCorner(knob, UDim.new(0, TG.CornerRadius))

        local ti = TweenInfo.new(TG.TransitionTime, Enum.EasingStyle.Quad)
        pill.MouseButton1Click:Connect(function() module:Trigger() end)

        module:OnStateChange(function(state)
            local on = state == true
            tw(pill,   ti,              {BackgroundColor3       = on and accent or TG.TrackOff}):Play()
            tw(knob,   ti,              {Position               = UDim2.fromOffset(on and dotXOn or dotXOff, dotY)}):Play()
            tw(indBar, Theme.TweenFast, {BackgroundTransparency = on and 0 or 1}):Play()
            tw(nameL,  Theme.TweenFast, {TextColor3             = on and Theme.Text or C_MUTED}):Play()
            nameL.Font = on and Theme.FontSemi or Theme.Font
            Toast.show(module.Name .. (on and " enabled" or " disabled"), {
                Variant = on and "success" or "info", Duration = 2,
            })
        end)

    else
        local runBtn           = Instance.new("TextButton")
        runBtn.Size            = UDim2.fromOffset(42, 22)
        runBtn.AnchorPoint     = Vector2.new(1, 0.5)
        runBtn.Position        = UDim2.new(1, rightOff, 0.5, 0)
        runBtn.BackgroundColor3 = accent
        runBtn.BorderSizePixel  = 0
        runBtn.AutoButtonColor  = false
        runBtn.Font            = Theme.FontBold
        runBtn.TextSize        = 10
        runBtn.TextColor3      = Color3.new(1, 1, 1)
        runBtn.Text            = "RUN"
        runBtn.Parent          = strip
        mkCorner(runBtn, R5)
        self:_addTooltip(runBtn, "Execute " .. module.Name)

        runBtn.MouseEnter:Connect(function()
            tw(runBtn, TweenInfo.new(0.15), {BackgroundColor3 = Theme.AccentHover}):Play()
        end)
        runBtn.MouseLeave:Connect(function()
            tw(runBtn, TweenInfo.new(0.15), {BackgroundColor3 = accent}):Play()
        end)
        runBtn.MouseButton1Down:Connect(function()
            tw(runBtn, TweenInfo.new(0.08), {BackgroundColor3 = Theme.AccentPress}):Play()
        end)
        runBtn.MouseButton1Up:Connect(function()
            tw(runBtn, TweenInfo.new(0.15), {BackgroundColor3 = accent}):Play()
        end)
        runBtn.MouseButton1Click:Connect(function()
            module:Trigger()
            Toast.show(module.Name .. " executed", { Variant = "info", Duration = 1.5 })
        end)

        module:OnStateChange(function()
            tw(indBar, Theme.TweenFast, {BackgroundTransparency = 0}):Play()
            task.delay(0.4, function()
                tw(indBar, Theme.Tween, {BackgroundTransparency = 1}):Play()
            end)
        end)
    end

    if hasSettings then
        local chev             = Instance.new("TextLabel")
        chev.Size              = UDim2.fromOffset(22, MOD_H)
        chev.AnchorPoint       = Vector2.new(1, 0)
        chev.Position          = UDim2.new(1, -6, 0, 0)
        chev.BackgroundTransparency = 1
        chev.Text              = "›"
        chev.Font              = Theme.FontBold
        chev.TextSize          = 14
        chev.TextColor3        = C_DIM
        chev.TextXAlignment    = Enum.TextXAlignment.Center
        chev.Rotation          = 90
        chev.Parent            = strip

        local sep              = Instance.new("Frame")
        sep.Size               = UDim2.new(1, -16, 0, 1)
        sep.Position           = UDim2.new(0, 8, 0, MOD_H)
        sep.BackgroundColor3   = C_BORDER
        sep.BackgroundTransparency = 1
        sep.BorderSizePixel    = 0
        sep.Parent             = row

        local settingsPanel    = Instance.new("Frame")
        settingsPanel.Size     = UDim2.new(1, -16, 0, totalExpand)
        settingsPanel.Position = UDim2.new(0, 8, 0, MOD_H + 4)
        settingsPanel.BackgroundTransparency = 1
        settingsPanel.Parent   = row

        local sLayout          = Instance.new("UIListLayout")
        sLayout.FillDirection  = Enum.FillDirection.Vertical
        sLayout.Padding        = UDim.new(0, 4)
        sLayout.Parent         = settingsPanel

        local sPad             = Instance.new("UIPadding")
        sPad.PaddingTop        = UDim.new(0, expandPad)
        sPad.PaddingBottom     = UDim.new(0, expandPad)
        sPad.Parent            = settingsPanel

        for _, setting in ipairs(module.Settings) do
            local comp = Components.Build(setting)
            if comp then comp.Parent = settingsPanel end
        end

        local expandBtn        = Instance.new("TextButton")
        expandBtn.Size         = UDim2.fromOffset(28, MOD_H)
        expandBtn.AnchorPoint  = Vector2.new(1, 0)
        expandBtn.Position     = UDim2.new(1, 0, 0, 0)
        expandBtn.BackgroundTransparency = 1
        expandBtn.Text         = ""
        expandBtn.ZIndex       = 3
        expandBtn.Parent       = strip
        self:_addTooltip(expandBtn, "Settings for " .. module.Name)

        expandBtn.MouseButton1Click:Connect(function()
            expanded = not expanded
            local targetH = expanded and (MOD_H + totalExpand + 4) or MOD_H
            tw(row,  Theme.TweenSlow, {Size = UDim2.new(1, 0, 0, targetH)}):Play()
            tw(chev, Theme.TweenFast, {
                Rotation   = expanded and 270 or 90,
                TextColor3 = expanded and accent or C_DIM,
            }):Play()
            tw(sep, Theme.TweenFast, {BackgroundTransparency = expanded and 0 or 1}):Play()
        end)
    end

    local ttText = module.Description ~= "" and module.Description
                   or (module.Behavior == "Toggleable" and "Toggle " .. module.Name
                                                       or "Execute " .. module.Name)

    local rowBtn               = Instance.new("TextButton")
    rowBtn.Size                = UDim2.new(1, hasSettings and -28 or 0, 0, MOD_H)
    rowBtn.BackgroundTransparency = 1
    rowBtn.Text                = ""
    rowBtn.ZIndex              = 2
    rowBtn.Parent              = strip

    rowBtn.MouseEnter:Connect(function()
        tw(row, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {BackgroundColor3 = C_CARD_HOVER}):Play()
        if self._tooltipFrame then
            self._tooltipLabel.Text = ttText
            local mp = UserInputService:GetMouseLocation()
            self._tooltipFrame.Position = UDim2.fromOffset(mp.X + 12, mp.Y + 18)
            self._tooltipFrame.Visible  = true
        end
    end)
    rowBtn.MouseLeave:Connect(function()
        tw(row, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {BackgroundColor3 = C_CARD}):Play()
        if self._tooltipFrame then self._tooltipFrame.Visible = false end
    end)
    rowBtn.MouseButton1Click:Connect(function()
        if module.Behavior == "Toggleable" then module:Trigger() end
    end)

    return row
end

-- ── Drag (header only) ────────────────────────────────────────────────────────

function Window:_setupDrag(outer)
    local dragging   = false
    local dragOffset = Vector2.zero

    self._header.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging   = true
        local mp   = Vector2.new(inp.Position.X, inp.Position.Y)
        local center = outer.AbsolutePosition + outer.AbsoluteSize * 0.5
        dragOffset = center - mp
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if not dragging or inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local mp              = Vector2.new(inp.Position.X, inp.Position.Y)
        local newCenter       = mp + dragOffset
        outer.Position        = UDim2.fromOffset(newCenter.X, newCenter.Y)
        self._shadow.Position = UDim2.fromOffset(newCenter.X, newCenter.Y)
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
    self._mainFrame.Size    = UDim2.fromOffset(WIN_W, HEAD_H)
    self._shadow.Size       = UDim2.fromOffset(WIN_W + 24, HEAD_H + 24)
    tw(self._mainFrame, Theme.TweenSpring, {Size = UDim2.fromOffset(WIN_W, WIN_H)}):Play()
    tw(self._shadow,    Theme.TweenSpring, {Size = UDim2.fromOffset(WIN_W + 24, WIN_H + 24)}):Play()
    self._visible = true
end

function Window:Hide()
    if self._tooltipFrame then self._tooltipFrame.Visible = false end
    tw(self._mainFrame, Theme.Tween, {Size = UDim2.fromOffset(WIN_W, HEAD_H)}):Play()
    tw(self._shadow,    Theme.Tween, {Size = UDim2.fromOffset(WIN_W + 24, HEAD_H + 24)}):Play()
    task.delay(Theme.Tween.Time + 0.05, function()
        if self._mainFrame then self._mainFrame.Visible = false end
        if self._shadow    then self._shadow.Visible    = false end
    end)
    self._visible = false
end

function Window:Toggle()
    if self._visible then self:Hide() else self:Show() end
end

-- ── Accent refresh ────────────────────────────────────────────────────────────

function Window:RefreshAccent(color)
    self._config.AccentColor = color
    if self._pip          then self._pip.BackgroundColor3              = color end
    if self._moduleScroll then self._moduleScroll.ScrollBarImageColor3 = color end
    for _, entry in ipairs(self._catBtns) do
        if entry.underline then entry.underline.BackgroundColor3 = color end
    end
    if #self._catBtns > 0 then self:_selectCategory(self._activeCat) end
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
