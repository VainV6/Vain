--[[
    UI/Components.lua  –  Factory functions that turn Setting objects into
                          interactive UI frames.

    Each factory returns a Frame sized for UIListLayout.
    All interaction logic is wired to setting:Set() so the data layer stays
    authoritative; visuals react via setting:OnChanged().

    Public API:
        Components.Build(setting)  →  Frame   (dispatches by setting.Type)
        Components.Slider(setting) →  Frame
        Components.Toggle(setting) →  Frame
        Components.Input(setting)  →  Frame
        Components.List(setting)   →  Frame
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)

local Components = {}

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

local function padding(parent, left, right, top, bottom)
    local p           = Instance.new("UIPadding")
    p.PaddingLeft     = UDim.new(0, left   or 0)
    p.PaddingRight    = UDim.new(0, right  or 0)
    p.PaddingTop      = UDim.new(0, top    or 0)
    p.PaddingBottom   = UDim.new(0, bottom or 0)
    p.Parent          = parent
end

local function label(parent, text, font, size, color, xAlign)
    local l              = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text               = text
    l.Font               = font  or Theme.Font
    l.TextSize           = size  or Theme.FontSize.SM
    l.TextColor3         = color or Theme.TextMuted
    l.TextXAlignment     = xAlign or Enum.TextXAlignment.Left
    l.Parent             = parent
    return l
end

-- ── Slider ───────────────────────────────────────────────────────────────────

function Components.Slider(setting)
    local h    = Theme.SettingH.Slider
    local pct0 = (setting.Value - setting.Min) / (setting.Max - setting.Min)

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, h)
    container.BackgroundTransparency = 1

    -- Name label
    local nameL = label(container, setting.Name)
    nameL.Size  = UDim2.new(1, -52, 0, 16)
    nameL.Position = UDim2.fromOffset(0, 2)

    -- Live value display
    local valueL = label(container, "", Theme.FontSemi, Theme.FontSize.SM, Theme.Accent, Enum.TextXAlignment.Right)
    valueL.Size     = UDim2.fromOffset(50, 16)
    valueL.Position = UDim2.new(1, -50, 0, 2)

    local function fmtVal(v)
        local fmt = (setting.Step % 1 == 0) and "%d" or "%.1f"
        return string.format(fmt, v) .. setting.Suffix
    end
    valueL.Text = fmtVal(setting.Value)

    -- Track background
    local track = Instance.new("Frame")
    track.Size              = UDim2.new(1, 0, 0, 4)
    track.Position          = UDim2.fromOffset(0, 24)
    track.BackgroundColor3  = Theme.Surface3
    track.BorderSizePixel   = 0
    track.Parent            = container
    corner(track, UDim.new(0, 2))

    -- Fill
    local fill = Instance.new("Frame")
    fill.Size              = UDim2.new(pct0, 0, 1, 0)
    fill.BackgroundColor3  = Theme.Accent
    fill.BorderSizePixel   = 0
    fill.Parent            = track
    corner(fill, UDim.new(0, 2))

    -- Thumb knob
    local knob = Instance.new("Frame")
    knob.Size             = UDim2.fromOffset(14, 14)
    knob.AnchorPoint      = Vector2.new(0.5, 0.5)
    knob.Position         = UDim2.new(pct0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    knob.ZIndex           = 3
    knob.Parent           = track
    corner(knob, Theme.RadiusFull)

    -- Drag logic
    local dragging = false

    local function applyX(inputX)
        local abs  = track.AbsolutePosition.X
        local sz   = track.AbsoluteSize.X
        local pct  = math.clamp((inputX - abs) / sz, 0, 1)
        local raw  = setting.Min + pct * (setting.Max - setting.Min)
        setting:Set(raw)
    end

    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            applyX(inp.Position.X)
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if not dragging then return end
        if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then
            applyX(inp.Position.X)
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Sync visuals to data
    setting:OnChanged(function(val)
        local p = (val - setting.Min) / (setting.Max - setting.Min)
        tw(fill, Theme.TweenFast, {Size = UDim2.new(p, 0, 1, 0)}):Play()
        tw(knob, Theme.TweenFast, {Position = UDim2.new(p, 0, 0.5, 0)}):Play()
        valueL.Text = fmtVal(val)
    end)

    return container
end

-- ── Toggle ────────────────────────────────────────────────────────────────────

function Components.Toggle(setting)
    local on0 = setting.Value == true

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.Toggle)
    container.BackgroundTransparency = 1

    local nameL  = label(container, setting.Name)
    nameL.Size   = UDim2.new(1, -50, 1, 0)

    -- Pill
    local pill   = Instance.new("Frame")
    pill.Size    = UDim2.fromOffset(36, 18)
    pill.AnchorPoint  = Vector2.new(1, 0.5)
    pill.Position     = UDim2.new(1, 0, 0.5, 0)
    pill.BackgroundColor3 = on0 and Theme.Accent or Theme.Surface3
    pill.BorderSizePixel  = 0
    pill.Parent      = container
    corner(pill, Theme.RadiusFull)

    -- Knob
    local knob   = Instance.new("Frame")
    knob.Size    = UDim2.fromOffset(12, 12)
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Position    = on0
        and UDim2.new(1, -15, 0.5, 0)
        or  UDim2.new(0, 3,  0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    knob.Parent  = pill
    corner(knob, Theme.RadiusFull)

    -- Invisible click region over the whole row
    local btn = Instance.new("TextButton")
    btn.Size  = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text  = ""
    btn.Parent = container

    btn.MouseButton1Click:Connect(function()
        setting:Set(not setting.Value)
    end)

    setting:OnChanged(function(val)
        tw(pill, Theme.TweenFast, {BackgroundColor3 = val and Theme.Accent or Theme.Surface3}):Play()
        tw(knob, Theme.TweenFast, {
            Position = val and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        }):Play()
    end)

    return container
end

-- ── Input (text / keybind) ────────────────────────────────────────────────────

function Components.Input(setting)
    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.Input)
    container.BackgroundTransparency = 1

    local nameL    = label(container, setting.Name)
    nameL.Size     = UDim2.new(1, 0, 0, 16)
    nameL.Position = UDim2.fromOffset(0, 2)

    if setting.IsKeybind then
        -- Keybind: click to enter listen mode, then press any key
        local btn   = Instance.new("TextButton")
        btn.Size    = UDim2.new(1, 0, 0, 24)
        btn.Position = UDim2.fromOffset(0, 20)
        btn.BackgroundColor3 = Theme.Surface3
        btn.BorderSizePixel  = 0
        btn.Font   = Theme.Font
        btn.TextSize  = Theme.FontSize.SM
        btn.TextColor3 = setting.Value ~= "" and Theme.Text or Theme.TextDim
        btn.Text  = setting.Value ~= "" and "[" .. setting.Value .. "]" or "Click to bind..."
        btn.Parent = container
        corner(btn, Theme.RadiusSM)

        local listening = false

        btn.MouseButton1Click:Connect(function()
            listening = true
            btn.Text  = "..."
            btn.TextColor3 = Theme.TextMuted
        end)

        UserInputService.InputBegan:Connect(function(inp, processed)
            if not listening then return end
            if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
            listening  = false
            local name = inp.KeyCode.Name
            btn.Text   = "[" .. name .. "]"
            btn.TextColor3 = Theme.Text
            setting:Set(name)
        end)

        setting:OnChanged(function(val)
            btn.Text = val ~= "" and "[" .. val .. "]" or "Click to bind..."
            btn.TextColor3 = val ~= "" and Theme.Text or Theme.TextDim
        end)
    else
        -- Regular text input
        local box   = Instance.new("TextBox")
        box.Size    = UDim2.new(1, 0, 0, 24)
        box.Position = UDim2.fromOffset(0, 20)
        box.BackgroundColor3 = Theme.Surface3
        box.BorderSizePixel  = 0
        box.Font   = Theme.Font
        box.TextSize  = Theme.FontSize.SM
        box.TextColor3 = Theme.Text
        box.PlaceholderText = setting.Placeholder
        box.PlaceholderColor3 = Theme.TextDim
        box.Text   = tostring(setting.Value)
        box.ClearTextOnFocus = false
        box.Parent = container
        corner(box, Theme.RadiusSM)
        padding(box, 7, 7, 0, 0)

        -- Commit on Enter or focus lost
        box.FocusLost:Connect(function(enterPressed)
            if enterPressed or true then
                setting:Set(box.Text)
            end
        end)

        -- Keep focused border hint
        box.Focused:Connect(function()
            tw(box, Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
        end)
        box.FocusLost:Connect(function()
            tw(box, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
        end)

        setting:OnChanged(function(val)
            if not box:IsFocused() then
                box.Text = tostring(val)
            end
        end)
    end

    return container
end

-- ── List (dropdown) ────────────────────────────────────────────────────────────

function Components.List(setting)
    local ROW_H = 22

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.List)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false

    local nameL   = label(container, setting.Name)
    nameL.Size    = UDim2.new(0.46, 0, 1, 0)

    -- Select button
    local selBtn  = Instance.new("TextButton")
    selBtn.Size   = UDim2.new(0.52, 0, 0, 22)
    selBtn.AnchorPoint = Vector2.new(1, 0.5)
    selBtn.Position    = UDim2.new(1, 0, 0.5, 0)
    selBtn.BackgroundColor3 = Theme.Surface3
    selBtn.BorderSizePixel  = 0
    selBtn.Font    = Theme.FontSemi
    selBtn.TextSize = Theme.FontSize.SM
    selBtn.TextColor3 = Theme.Text
    selBtn.Text    = setting.Value .. "  ▾"
    selBtn.Parent  = container
    corner(selBtn, Theme.RadiusSM)

    -- Dropdown panel (initially hidden / zero-height)
    local panel   = Instance.new("Frame")
    panel.Size    = UDim2.new(0.52, 0, 0, 0)
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position    = UDim2.new(1, 0, 1, 3)
    panel.BackgroundColor3 = Theme.Surface2
    panel.BorderSizePixel  = 0
    panel.ClipsDescendants = true
    panel.ZIndex  = 20
    panel.Visible = false
    panel.Parent  = container
    corner(panel, Theme.RadiusSM)

    local layout  = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.Padding       = UDim.new(0, 0)
    layout.Parent        = panel

    local isOpen  = false
    local totalH  = #setting.Options * ROW_H

    for _, opt in ipairs(setting.Options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size  = UDim2.new(1, 0, 0, ROW_H)
        optBtn.BackgroundTransparency = 1
        optBtn.Font  = Theme.Font
        optBtn.TextSize = Theme.FontSize.SM
        optBtn.TextColor3 = opt == setting.Value and Theme.Accent or Theme.TextMuted
        optBtn.Text  = opt
        optBtn.ZIndex = 21
        optBtn.Parent = panel

        optBtn.MouseEnter:Connect(function()
            if opt ~= setting.Value then
                tw(optBtn, Theme.TweenFast, {TextColor3 = Theme.Text}):Play()
            end
        end)
        optBtn.MouseLeave:Connect(function()
            if opt ~= setting.Value then
                tw(optBtn, Theme.TweenFast, {TextColor3 = Theme.TextMuted}):Play()
            end
        end)

        optBtn.MouseButton1Click:Connect(function()
            setting:Set(opt)
            isOpen = false
            tw(panel, Theme.TweenFast, {Size = UDim2.new(0.52, 0, 0, 0)}):Play()
            task.delay(0.15, function() panel.Visible = false end)
        end)
    end

    -- Sync option highlight to selected value
    setting:OnChanged(function(val)
        selBtn.Text = val .. "  ▾"
        for _, child in ipairs(panel:GetChildren()) do
            if child:IsA("TextButton") then
                child.TextColor3 = child.Text == val and Theme.Accent or Theme.TextMuted
            end
        end
    end)

    selBtn.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        if isOpen then
            panel.Visible = true
            tw(panel, Theme.TweenFast, {Size = UDim2.new(0.52, 0, 0, totalH)}):Play()
        else
            tw(panel, Theme.TweenFast, {Size = UDim2.new(0.52, 0, 0, 0)}):Play()
            task.delay(0.15, function() panel.Visible = false end)
        end
    end)

    return container
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

function Components.Build(setting)
    local builders = {
        Slider = Components.Slider,
        Toggle = Components.Toggle,
        Input  = Components.Input,
        List   = Components.List,
    }
    local builder = builders[setting.Type]
    if builder then
        return builder(setting)
    end
    warn("[Vain:Components] Unknown setting type '" .. tostring(setting.Type) .. "'")
end

return Components
