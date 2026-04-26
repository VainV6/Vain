--[[
    UI/Window.lua  –  Vain hub window.

    Inspired by the original VainUI layout: narrow dark sidebar with text category
    buttons, flat compact module rows with toggle + settings-expand icon, ultra-dark
    palette (#0A0A0A / #121212 / #181818).
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local Theme      = require(script.Parent.Parent.Theme)
local Components = require(script.Parent.Components)
local Toast      = require(script.Parent.Toast)

-- ── Design constants ──────────────────────────────────────────────────────────
local C_BASE    = Color3.fromRGB(14, 14, 14)   -- content background
local C_SIDEBAR = Color3.fromRGB(9,  9,  9)    -- sidebar (darkest)
local C_HEADER  = Color3.fromRGB(9,  9,  9)    -- header bar
local C_ROW     = Color3.fromRGB(19, 19, 19)   -- module row background
local C_HOVER   = Color3.fromRGB(24, 24, 24)   -- row hover
local C_WIN_BDR = Color3.fromRGB(52, 52, 52)   -- outer window border
local C_SEP     = Color3.fromRGB(22, 22, 22)   -- thin separators
local C_BORDER  = Color3.fromRGB(30, 30, 30)   -- subtle row borders
local C_MUTED   = Color3.fromRGB(68, 68, 68)   -- inactive text / labels
local C_DIM     = Color3.fromRGB(42, 42, 42)   -- chevron / icon color

local WIN_W  = 680
local WIN_H  = 420
local HEAD_H = 36
local SIDE_W = 118
local PAD    = 8
local MOD_H  = 36
local SRCH_H = 28

local R6    = UDim.new(0, 6)
local R4    = UDim.new(0, 4)
local RFULL = UDim.new(1, 0)

local Window  = {}
Window.__index = Window

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function tw(obj, info, props) return TweenService:Create(obj, info, props) end

local function mkCorner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or R6
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
    self._sidebar          = nil
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
    shadow.Size                     = UDim2.fromOffset(WIN_W + 22, WIN_H + 22)
    shadow.AnchorPoint              = Vector2.new(0.5, 0.5)
    shadow.Position                 = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3         = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency   = 0.5
    shadow.BorderSizePixel          = 0
    shadow.Visible                  = false
    shadow.Parent                   = gui
    mkCorner(shadow, UDim.new(0, 12))
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
    mkCorner(outer, UDim.new(0, 8))
    self._mainFrame = outer

    local inner                    = Instance.new("Frame")
    inner.Name                     = "WindowInner"
    inner.Size                     = UDim2.new(1, -2, 1, -2)
    inner.AnchorPoint              = Vector2.new(0.5, 0.5)
    inner.Position                 = UDim2.fromScale(0.5, 0.5)
    inner.BackgroundColor3         = C_BASE
    inner.BorderSizePixel          = 0
    inner.ClipsDescendants         = true
    inner.Parent                   = outer
    mkCorner(inner, UDim.new(0, 7))

    -- Tooltip
    local ttFrame                  = Instance.new("Frame")
    ttFrame.Name                   = "Tooltip"
    ttFrame.Size                   = UDim2.fromOffset(4, 22)
    ttFrame.AutomaticSize          = Enum.AutomaticSize.X
    ttFrame.BackgroundColor3       = Color3.fromRGB(14, 14, 14)
    ttFrame.BorderSizePixel        = 0
    ttFrame.Visible                = false
    ttFrame.ZIndex                 = 500
    ttFrame.Parent                 = gui
    mkCorner(ttFrame, UDim.new(0, 4))
    mkStroke(ttFrame, Color3.fromRGB(40, 40, 40), 1)

    local ttPad                    = Instance.new("UIPadding")
    ttPad.PaddingLeft              = UDim.new(0, 7)
    ttPad.PaddingRight             = UDim.new(0, 7)
    ttPad.Parent                   = ttFrame

    local ttLabel                  = Instance.new("TextLabel")
    ttLabel.Size                   = UDim2.new(0, 0, 1, 0)
    ttLabel.AutomaticSize          = Enum.AutomaticSize.X
    ttLabel.BackgroundTransparency = 1
    ttLabel.Text                   = ""
    ttLabel.Font                   = Theme.Font
    ttLabel.TextSize               = 11
    ttLabel.TextColor3             = Color3.fromRGB(140, 140, 140)
    ttLabel.ZIndex                 = 501
    ttLabel.Parent                 = ttFrame
    self._tooltipFrame = ttFrame
    self._tooltipLabel = ttLabel

    self:_buildHeader(inner)
    self:_buildSidebar(inner)
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
    header.BackgroundColor3   = C_HEADER
    header.BorderSizePixel    = 0
    header.Parent             = parent
    mkCorner(header, UDim.new(0, 7))

    -- Square off header bottom corners
    local sq                  = Instance.new("Frame")
    sq.Size                   = UDim2.new(1, 0, 0, 7)
    sq.Position               = UDim2.new(0, 0, 1, -7)
    sq.BackgroundColor3       = C_HEADER
    sq.BorderSizePixel        = 0
    sq.Parent                 = header
    self._header = header

    -- Accent pip
    local pip                 = Instance.new("Frame")
    pip.Size                  = UDim2.fromOffset(2, HEAD_H - 16)
    pip.Position              = UDim2.fromOffset(12, 8)
    pip.BackgroundColor3      = accent
    pip.BorderSizePixel       = 0
    pip.Parent                = header
    mkCorner(pip, RFULL)
    self._pip = pip

    -- Title
    local title               = Instance.new("TextLabel")
    title.Size                = UDim2.new(1, -120, 1, 0)
    title.Position            = UDim2.fromOffset(20, 0)
    title.BackgroundTransparency = 1
    title.Text                = self._config.Title or "Vain"
    title.Font                = Theme.FontBold
    title.TextSize            = 13
    title.TextColor3          = Theme.Text
    title.TextXAlignment      = Enum.TextXAlignment.Left
    title.Parent              = header

    -- FPS counter
    local fps                 = Instance.new("TextLabel")
    fps.Size                  = UDim2.fromOffset(60, HEAD_H)
    fps.AnchorPoint           = Vector2.new(1, 0)
    fps.Position              = UDim2.new(1, -8, 0, 0)
    fps.BackgroundTransparency = 1
    fps.Text                  = ""
    fps.Font                  = Theme.Font
    fps.TextSize              = 10
    fps.TextColor3            = C_MUTED
    fps.TextXAlignment        = Enum.TextXAlignment.Right
    fps.Visible               = false
    fps.Parent                = header
    self._fpsLabel = fps
    self:_addTooltip(fps, "Frames per second")

    -- Bottom separator
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

-- ── Sidebar ───────────────────────────────────────────────────────────────────

function Window:_buildSidebar(parent)
    local sidebar              = Instance.new("Frame")
    sidebar.Name               = "Sidebar"
    sidebar.Size               = UDim2.new(0, SIDE_W, 1, -HEAD_H)
    sidebar.Position           = UDim2.fromOffset(0, HEAD_H)
    sidebar.BackgroundColor3   = C_SIDEBAR
    sidebar.BorderSizePixel    = 0
    sidebar.Parent             = parent

    -- Right divider
    local div                  = Instance.new("Frame")
    div.Size                   = UDim2.new(0, 1, 1, -HEAD_H)
    div.Position               = UDim2.new(0, SIDE_W, 0, HEAD_H)
    div.BackgroundColor3       = C_SEP
    div.BorderSizePixel        = 0
    div.Parent                 = parent

    local catList              = Instance.new("Frame")
    catList.Name               = "CategoryList"
    catList.Size               = UDim2.fromScale(1, 1)
    catList.BackgroundTransparency = 1
    catList.BorderSizePixel    = 0
    catList.Parent             = sidebar

    local layout               = Instance.new("UIListLayout")
    layout.FillDirection       = Enum.FillDirection.Vertical
    layout.Padding             = UDim.new(0, 2)
    layout.SortOrder           = Enum.SortOrder.LayoutOrder
    layout.Parent              = catList

    local p                    = Instance.new("UIPadding")
    p.PaddingLeft              = UDim.new(0, 6)
    p.PaddingRight             = UDim.new(0, 6)
    p.PaddingTop               = UDim.new(0, 8)
    p.Parent                   = catList

    self._sidebar = catList
end

-- ── Content area ─────────────────────────────────────────────────────────────

function Window:_buildContent(parent)
    local content              = Instance.new("Frame")
    content.Name               = "Content"
    content.Size               = UDim2.new(1, -SIDE_W, 1, -HEAD_H)
    content.Position           = UDim2.new(0, SIDE_W, 0, HEAD_H)
    content.BackgroundTransparency = 1
    content.ClipsDescendants   = true
    content.Parent             = parent

    -- Search bar
    local searchWrap           = Instance.new("Frame")
    searchWrap.Size            = UDim2.new(1, -(PAD * 2), 0, SRCH_H)
    searchWrap.Position        = UDim2.fromOffset(PAD, PAD)
    searchWrap.BackgroundColor3 = C_ROW
    searchWrap.BorderSizePixel  = 0
    searchWrap.Parent          = content
    mkCorner(searchWrap, R4)
    local searchStroke = mkStroke(searchWrap, C_BORDER, 1)
    self:_addTooltip(searchWrap, "Filter modules by name")

    local searchIcon           = Instance.new("TextLabel")
    searchIcon.Size            = UDim2.fromOffset(24, SRCH_H)
    searchIcon.Position        = UDim2.fromOffset(5, 0)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text            = "⌕"
    searchIcon.TextSize        = 13
    searchIcon.TextColor3      = C_MUTED
    searchIcon.Parent          = searchWrap

    local searchBox            = Instance.new("TextBox")
    searchBox.Size             = UDim2.new(1, -32, 1, 0)
    searchBox.Position         = UDim2.fromOffset(26, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.PlaceholderText  = "Search..."
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

    local scrollTop            = PAD + SRCH_H + 5
    local scroll               = Instance.new("ScrollingFrame")
    scroll.Name                = "ModuleScroll"
    scroll.Size                = UDim2.new(1, 0, 1, -scrollTop)
    scroll.Position            = UDim2.fromOffset(0, scrollTop)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel     = 0
    scroll.ScrollBarThickness  = 2
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.ScrollBarImageTransparency = 0.5
    scroll.CanvasSize          = UDim2.fromScale(1, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent              = content
    self._moduleScroll         = scroll

    local layout               = Instance.new("UIListLayout")
    layout.FillDirection       = Enum.FillDirection.Vertical
    layout.Padding             = UDim.new(0, 3)
    layout.Parent              = scroll

    local scrollPad            = Instance.new("UIPadding")
    scrollPad.PaddingLeft      = UDim.new(0, PAD)
    scrollPad.PaddingRight     = UDim.new(0, PAD)
    scrollPad.PaddingTop       = UDim.new(0, 4)
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
        btn.Size               = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3   = active and C_ROW or C_SIDEBAR
        btn.BackgroundTransparency = active and 0 or 1
        btn.BorderSizePixel    = 0
        btn.AutoButtonColor    = false
        btn.Font               = active and Theme.FontSemi or Theme.Font
        btn.TextSize           = 12
        btn.TextColor3         = active and Theme.Text or C_MUTED
        btn.Text               = cat.name
        btn.TextXAlignment     = Enum.TextXAlignment.Left
        btn.LayoutOrder        = i
        btn.Parent             = self._sidebar
        mkCorner(btn, R4)

        local bPad             = Instance.new("UIPadding")
        bPad.PaddingLeft       = UDim.new(0, 10)
        bPad.Parent            = btn

        -- Left accent indicator bar
        local ind              = Instance.new("Frame")
        ind.Size               = UDim2.fromOffset(2, 16)
        ind.Position           = UDim2.fromOffset(0, 7)
        ind.BackgroundColor3   = accent
        ind.BackgroundTransparency = active and 0 or 1
        ind.BorderSizePixel    = 0
        ind.Parent             = btn
        mkCorner(ind, RFULL)

        self._catBtns[i] = { btn = btn, ind = ind }

        local idx = i
        btn.MouseButton1Click:Connect(function() self:_selectCategory(idx) end)
        btn.MouseEnter:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, TweenInfo.new(0.12), {
                    BackgroundColor3       = C_ROW,
                    BackgroundTransparency = 0,
                    TextColor3             = Theme.Text,
                }):Play()
            end
        end)
        btn.MouseLeave:Connect(function()
            if idx ~= self._activeCat then
                tw(btn, TweenInfo.new(0.12), {
                    BackgroundTransparency = 1,
                    TextColor3             = C_MUTED,
                }):Play()
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
            BackgroundColor3       = active and C_ROW or C_SIDEBAR,
            BackgroundTransparency = active and 0 or 1,
            TextColor3             = active and Theme.Text or C_MUTED,
        }):Play()
        tw(entry.ind, Theme.TweenFast, {
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
    local expandPad   = 8
    local totalExpand = expandH + expandPad * 2
    local expanded    = false

    local TG        = Theme.Toggle
    local dotTravel = TG.TrackWidth - TG.DotSize - 4
    local dotY      = (TG.TrackHeight - TG.DotSize) / 2
    local dotXOff   = 2
    local dotXOn    = 2 + dotTravel

    -- Row card
    local row              = Instance.new("Frame")
    row.Name               = module.Name
    row.Size               = UDim2.new(1, 0, 0, MOD_H)
    row.BackgroundColor3   = C_ROW
    row.BorderSizePixel    = 0
    row.ClipsDescendants   = true
    row.Parent             = self._moduleScroll
    mkCorner(row, R4)
    mkStroke(row, C_BORDER, 1)
    table.insert(self._moduleRows, { name = module.Name:lower(), frame = row })

    -- Left enable indicator
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

    -- Module name
    local nameL                = Instance.new("TextLabel")
    nameL.Size                 = UDim2.new(1, -120, 1, 0)
    nameL.Position             = UDim2.fromOffset(10, 0)
    nameL.BackgroundTransparency = 1
    nameL.Text                 = module.Name
    nameL.Font                 = module.Enabled and Theme.FontSemi or Theme.Font
    nameL.TextSize             = 12
    nameL.TextColor3           = module.Enabled and Theme.Text or C_MUTED
    nameL.TextXAlignment       = Enum.TextXAlignment.Left
    nameL.Parent               = strip

    -- Keybind label
    if module.Keybind then
        local kb               = Instance.new("TextLabel")
        kb.Size                = UDim2.fromOffset(28, MOD_H)
        kb.AnchorPoint         = Vector2.new(1, 0)
        kb.Position            = UDim2.new(1, hasSettings and -62 or -44, 0, 0)
        kb.BackgroundTransparency = 1
        kb.Text                = "[" .. module.Keybind.Name:sub(1, 3):upper() .. "]"
        kb.Font                = Theme.Font
        kb.TextSize            = 10
        kb.TextColor3          = C_MUTED
        kb.TextXAlignment      = Enum.TextXAlignment.Right
        kb.Parent              = strip
    end

    local rightOff = hasSettings and -28 or -8

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
        runBtn.Size            = UDim2.fromOffset(38, 20)
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
        mkCorner(runBtn, R4)
        self:_addTooltip(runBtn, "Execute " .. module.Name)

        runBtn.MouseEnter:Connect(function()
            tw(runBtn, TweenInfo.new(0.12), {BackgroundColor3 = Theme.AccentHover}):Play()
        end)
        runBtn.MouseLeave:Connect(function()
            tw(runBtn, TweenInfo.new(0.12), {BackgroundColor3 = accent}):Play()
        end)
        runBtn.MouseButton1Down:Connect(function()
            tw(runBtn, TweenInfo.new(0.07), {BackgroundColor3 = Theme.AccentPress}):Play()
        end)
        runBtn.MouseButton1Up:Connect(function()
            tw(runBtn, TweenInfo.new(0.12), {BackgroundColor3 = accent}):Play()
        end)
        runBtn.MouseButton1Click:Connect(function()
            module:Trigger()
            Toast.show(module.Name .. " executed", { Variant = "info", Duration = 1.5 })
        end)

        module:OnStateChange(function()
            tw(indBar, Theme.TweenFast, {BackgroundTransparency = 0}):Play()
            task.delay(0.35, function()
                tw(indBar, Theme.Tween, {BackgroundTransparency = 1}):Play()
            end)
        end)
    end

    -- Settings expand
    if hasSettings then
        local chev             = Instance.new("TextLabel")
        chev.Size              = UDim2.fromOffset(20, MOD_H)
        chev.AnchorPoint       = Vector2.new(1, 0)
        chev.Position          = UDim2.new(1, -6, 0, 0)
        chev.BackgroundTransparency = 1
        chev.Text              = "›"
        chev.Font              = Theme.FontBold
        chev.TextSize          = 13
        chev.TextColor3        = C_DIM
        chev.TextXAlignment    = Enum.TextXAlignment.Center
        chev.Rotation          = 90
        chev.Parent            = strip

        local sep              = Instance.new("Frame")
        sep.Size               = UDim2.new(1, -12, 0, 1)
        sep.Position           = UDim2.new(0, 6, 0, MOD_H)
        sep.BackgroundColor3   = C_BORDER
        sep.BackgroundTransparency = 1
        sep.BorderSizePixel    = 0
        sep.Parent             = row

        local settingsPanel    = Instance.new("Frame")
        settingsPanel.Size     = UDim2.new(1, -12, 0, totalExpand)
        settingsPanel.Position = UDim2.new(0, 6, 0, MOD_H + 4)
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
        expandBtn.Size         = UDim2.fromOffset(26, MOD_H)
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
    rowBtn.Size                = UDim2.new(1, hasSettings and -26 or 0, 0, MOD_H)
    rowBtn.BackgroundTransparency = 1
    rowBtn.Text                = ""
    rowBtn.ZIndex              = 2
    rowBtn.Parent              = strip

    rowBtn.MouseEnter:Connect(function()
        tw(row, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundColor3 = C_HOVER}):Play()
        if self._tooltipFrame then
            self._tooltipLabel.Text = ttText
            local mp = UserInputService:GetMouseLocation()
            self._tooltipFrame.Position = UDim2.fromOffset(mp.X + 12, mp.Y + 18)
            self._tooltipFrame.Visible  = true
        end
    end)
    rowBtn.MouseLeave:Connect(function()
        tw(row, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundColor3 = C_ROW}):Play()
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
    self._shadow.Size       = UDim2.fromOffset(WIN_W + 22, HEAD_H + 22)
    tw(self._mainFrame, Theme.TweenSpring, {Size = UDim2.fromOffset(WIN_W, WIN_H)}):Play()
    tw(self._shadow,    Theme.TweenSpring, {Size = UDim2.fromOffset(WIN_W + 22, WIN_H + 22)}):Play()
    self._visible = true
end

function Window:Hide()
    if self._tooltipFrame then self._tooltipFrame.Visible = false end
    tw(self._mainFrame, Theme.Tween, {Size = UDim2.fromOffset(WIN_W, HEAD_H)}):Play()
    tw(self._shadow,    Theme.Tween, {Size = UDim2.fromOffset(WIN_W + 22, HEAD_H + 22)}):Play()
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
        if entry.ind then entry.ind.BackgroundColor3 = color end
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
