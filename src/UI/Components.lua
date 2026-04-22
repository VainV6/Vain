--[[
    UI/Components.lua  –  Factory functions that build interactive UI frames
                          from Setting data objects.

    Each builder returns a Frame sized for UIListLayout.
    All logic routes through setting:Set() so the data layer stays
    authoritative; visuals react via setting:OnChanged().

    Public:
        Components.Build(setting)        → Frame  (dispatch by type)
        Components.Slider(setting)       → Frame
        Components.Toggle(setting)       → Frame
        Components.Input(setting)        → Frame
        Components.List(setting)         → Frame
        Components.ColorPicker(setting)  → Frame  (always-expanded HSV picker)
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)

local Components = {}

-- ── Internal helpers ──────────────────────────────────────────────────────────

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

local function lbl(parent, text, font, size, color, xAlign)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text           = text
    l.Font           = font   or Theme.Font
    l.TextSize       = size   or Theme.FontSize.SM
    l.TextColor3     = color  or Theme.TextMuted
    l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    l.Parent         = parent
    return l
end

-- ── Slider ────────────────────────────────────────────────────────────────────

function Components.Slider(setting)
    local h    = Theme.SettingH.Slider
    local pct0 = (setting.Value - setting.Min) / (setting.Max - setting.Min)

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, h)
    container.BackgroundTransparency = 1

    local nameL = lbl(container, setting.Name)
    nameL.Size     = UDim2.new(1, -56, 0, 16)
    nameL.Position = UDim2.fromOffset(0, 2)

    local valueL = lbl(container, "", Theme.FontSemi, Theme.FontSize.SM, Theme.Accent, Enum.TextXAlignment.Right)
    valueL.Size     = UDim2.fromOffset(54, 16)
    valueL.Position = UDim2.new(1, -54, 0, 2)

    local function fmtVal(v)
        return string.format((setting.Step % 1 == 0) and "%d" or "%.1f", v) .. (setting.Suffix or "")
    end
    valueL.Text = fmtVal(setting.Value)

    local track = Instance.new("Frame")
    track.Size   = UDim2.new(1, 0, 0, 5)
    track.Position = UDim2.fromOffset(0, 26)
    track.BackgroundColor3 = Theme.Surface3
    track.BorderSizePixel  = 0
    track.Parent = container
    corner(track, UDim.new(0, 3))

    local fill = Instance.new("Frame")
    fill.Size   = UDim2.new(pct0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel  = 0
    fill.Parent = track
    corner(fill, UDim.new(0, 3))

    local knob = Instance.new("Frame")
    knob.Size   = UDim2.fromOffset(14, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position    = UDim2.new(pct0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    knob.ZIndex = 3
    knob.Parent = track
    corner(knob, Theme.RadiusFull)

    local dragging = false

    local function applyX(inputX)
        local pct = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        setting:Set(setting.Min + pct * (setting.Max - setting.Min))
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
        or inp.UserInputType == Enum.UserInputType.Touch then applyX(inp.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

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

    local nameL = lbl(container, setting.Name)
    nameL.Size  = UDim2.new(1, -52, 1, 0)

    local pill = Instance.new("Frame")
    pill.Size   = UDim2.fromOffset(36, 18)
    pill.AnchorPoint = Vector2.new(1, 0.5)
    pill.Position    = UDim2.new(1, 0, 0.5, 0)
    pill.BackgroundColor3 = on0 and Theme.Accent or Theme.Surface3
    pill.BorderSizePixel  = 0
    pill.Parent = container
    corner(pill, Theme.RadiusFull)

    local knob = Instance.new("Frame")
    knob.Size   = UDim2.fromOffset(12, 12)
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Position    = on0 and UDim2.new(1,-15,0.5,0) or UDim2.new(0,3,0.5,0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel  = 0
    knob.Parent = pill
    corner(knob, Theme.RadiusFull)

    local btn = Instance.new("TextButton")
    btn.Size  = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text  = ""
    btn.Parent = container
    btn.MouseButton1Click:Connect(function() setting:Set(not setting.Value) end)

    setting:OnChanged(function(val)
        tw(pill, Theme.TweenFast, {BackgroundColor3 = val and Theme.Accent or Theme.Surface3}):Play()
        tw(knob, Theme.TweenFast, {Position = val and UDim2.new(1,-15,0.5,0) or UDim2.new(0,3,0.5,0)}):Play()
    end)

    return container
end

-- ── Input / Keybind ───────────────────────────────────────────────────────────

function Components.Input(setting)
    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.Input)
    container.BackgroundTransparency = 1

    local nameL = lbl(container, setting.Name)
    nameL.Size     = UDim2.new(1, 0, 0, 16)
    nameL.Position = UDim2.fromOffset(0, 2)

    if setting.IsKeybind then
        local btn = Instance.new("TextButton")
        btn.Size  = UDim2.new(1, 0, 0, 26)
        btn.Position = UDim2.fromOffset(0, 20)
        btn.BackgroundColor3 = Theme.Surface3
        btn.BorderSizePixel  = 0
        btn.Font  = Theme.Font
        btn.TextSize = Theme.FontSize.SM
        btn.TextColor3 = setting.Value ~= "" and Theme.Text or Theme.TextDim
        btn.Text  = setting.Value ~= "" and "[" .. setting.Value .. "]" or "Click to bind..."
        btn.Parent = container
        corner(btn, Theme.RadiusSM)

        local listening = false
        btn.MouseButton1Click:Connect(function()
            listening  = true
            btn.Text   = "···"
            btn.TextColor3 = Theme.TextMuted
        end)
        UserInputService.InputBegan:Connect(function(inp, processed)
            if not listening then return end
            if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
            listening = false
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
        local box = Instance.new("TextBox")
        box.Size  = UDim2.new(1, 0, 0, 26)
        box.Position = UDim2.fromOffset(0, 20)
        box.BackgroundColor3 = Theme.Surface3
        box.BorderSizePixel  = 0
        box.Font  = Theme.Font
        box.TextSize = Theme.FontSize.SM
        box.TextColor3 = Theme.Text
        box.PlaceholderText   = setting.Placeholder
        box.PlaceholderColor3 = Theme.TextDim
        box.Text  = tostring(setting.Value)
        box.ClearTextOnFocus = false
        box.Parent = container
        corner(box, Theme.RadiusSM)

        local padInst = Instance.new("UIPadding")
        padInst.PaddingLeft  = UDim.new(0, 8)
        padInst.PaddingRight = UDim.new(0, 8)
        padInst.Parent = box

        box.Focused:Connect(function()
            tw(box, Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
        end)
        box.FocusLost:Connect(function()
            tw(box, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
            setting:Set(box.Text)
        end)
        setting:OnChanged(function(val)
            if not box:IsFocused() then box.Text = tostring(val) end
        end)
    end

    return container
end

-- ── List / Dropdown ───────────────────────────────────────────────────────────

function Components.List(setting)
    local ROW_H = 24

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.List)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false

    local nameL = lbl(container, setting.Name)
    nameL.Size  = UDim2.new(0.46, 0, 1, 0)

    local selBtn = Instance.new("TextButton")
    selBtn.Size  = UDim2.new(0.52, 0, 0, 24)
    selBtn.AnchorPoint = Vector2.new(1, 0.5)
    selBtn.Position    = UDim2.new(1, 0, 0.5, 0)
    selBtn.BackgroundColor3 = Theme.Surface3
    selBtn.BorderSizePixel  = 0
    selBtn.Font  = Theme.FontSemi
    selBtn.TextSize = Theme.FontSize.SM
    selBtn.TextColor3 = Theme.Text
    selBtn.Text  = setting.Value .. "  ▾"
    selBtn.Parent = container
    corner(selBtn, Theme.RadiusSM)

    local panel = Instance.new("Frame")
    panel.Size  = UDim2.new(0.52, 0, 0, 0)
    panel.AnchorPoint = Vector2.new(1, 0)
    panel.Position    = UDim2.new(1, 0, 1, 3)
    panel.BackgroundColor3 = Theme.Surface2
    panel.BorderSizePixel  = 0
    panel.ClipsDescendants = true
    panel.ZIndex = 20
    panel.Visible = false
    panel.Parent  = container
    corner(panel, Theme.RadiusSM)
    stroke(panel, Theme.Border, 1)

    Instance.new("UIListLayout", panel).FillDirection = Enum.FillDirection.Vertical

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
            if opt ~= setting.Value then tw(optBtn, Theme.TweenFast, {TextColor3 = Theme.Text}):Play() end
        end)
        optBtn.MouseLeave:Connect(function()
            if opt ~= setting.Value then tw(optBtn, Theme.TweenFast, {TextColor3 = Theme.TextMuted}):Play() end
        end)
        optBtn.MouseButton1Click:Connect(function()
            setting:Set(opt)
            isOpen = false
            tw(panel, Theme.TweenFast, {Size = UDim2.new(0.52, 0, 0, 0)}):Play()
            task.delay(0.15, function() panel.Visible = false end)
        end)
    end

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

-- ── ColorPicker (always-expanded HSV sliders) ─────────────────────────────────
-- Height = Theme.SettingH.ColorPicker = 126 (fixed, no collapse).
-- Three mini-tracks: Hue (0-360), Saturation (0-100), Value (0-100).

function Components.ColorPicker(setting)
    local h0, s0, v0 = setting.Value:ToHSV()
    local curH, curS, curV = h0, s0, v0

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.ColorPicker)
    container.BackgroundTransparency = 1

    -- Top row: label + colour swatch
    local nameL = lbl(container, setting.Name)
    nameL.Size     = UDim2.new(1, -52, 0, 20)
    nameL.Position = UDim2.fromOffset(0, 2)

    local swatch = Instance.new("Frame")
    swatch.Size   = UDim2.fromOffset(42, 20)
    swatch.AnchorPoint = Vector2.new(1, 0)
    swatch.Position    = UDim2.new(1, 0, 0, 2)
    swatch.BackgroundColor3 = setting.Value
    swatch.BorderSizePixel  = 0
    swatch.Parent = container
    corner(swatch, Theme.RadiusSM)
    stroke(swatch, Theme.Border, 1)

    -- Helper: one compact HSV track
    local function makeTrack(label_text, topY, initPct, hueMode)
        local row = Instance.new("Frame")
        row.Size  = UDim2.new(1, 0, 0, 28)
        row.Position = UDim2.fromOffset(0, topY)
        row.BackgroundTransparency = 1
        row.Parent = container

        local rowLbl = lbl(row, label_text, Theme.Font, Theme.FontSize.XS, Theme.TextDim)
        rowLbl.Size = UDim2.fromOffset(12, 28)

        local track = Instance.new("Frame")
        track.Size   = UDim2.new(1, -18, 0, 5)
        track.Position = UDim2.new(0, 16, 0.5, -2)
        track.BorderSizePixel = 0
        track.Parent = row

        if hueMode then
            -- Rainbow gradient for hue track background
            track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            local g = Instance.new("UIGradient")
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,    Color3.fromHSV(0,    1, 1)),
                ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167,1, 1)),
                ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333,1, 1)),
                ColorSequenceKeypoint.new(0.5,   Color3.fromHSV(0.5,  1, 1)),
                ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667,1, 1)),
                ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833,1, 1)),
                ColorSequenceKeypoint.new(1,     Color3.fromHSV(0,    1, 1)),
            })
            g.Parent = track
        else
            track.BackgroundColor3 = Theme.Surface3
        end
        corner(track, UDim.new(0, 3))

        local fill = Instance.new("Frame")
        fill.Size   = UDim2.new(initPct, 0, 1, 0)
        fill.BackgroundColor3 = hueMode and Color3.fromRGB(255,255,255) or Theme.Accent
        fill.BackgroundTransparency = hueMode and 1 or 0
        fill.BorderSizePixel = 0
        fill.Parent = track
        corner(fill, UDim.new(0, 3))

        local knob = Instance.new("Frame")
        knob.Size   = UDim2.fromOffset(12, 12)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position    = UDim2.new(initPct, 0, 0.5, 0)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel  = 0
        knob.ZIndex = 3
        knob.Parent = track
        corner(knob, Theme.RadiusFull)
        stroke(knob, Theme.Border, 1)

        local dragging = false

        local function applyX(x)
            local pct = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            tw(fill, Theme.TweenFast, {Size = UDim2.new(pct, 0, 1, 0)}):Play()
            tw(knob, Theme.TweenFast, {Position = UDim2.new(pct, 0, 0.5, 0)}):Play()
            return pct
        end

        track.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)

        return applyX, function(pct)   -- setFn updates visuals externally
            fill.Size = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, 0, 0.5, 0)
        end, dragging, function() return dragging end
    end

    local function fireUpdate()
        local color = Color3.fromHSV(curH, curS, curV)
        setting:Set(color)
        swatch.BackgroundColor3 = color
    end

    -- Hue track
    local applyH, setH, _, isDraggingH_fn = makeTrack("H", 28, curH, true)
    -- Saturation track
    local applyS, setS, _, isDraggingS_fn = makeTrack("S", 62, curS, false)
    -- Value track
    local applyV, setV, _, isDraggingV_fn = makeTrack("V", 96, curV, false)

    -- Wire mouse move to whichever track is dragging
    UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        if isDraggingH_fn() then curH = applyH(inp.Position.X); fireUpdate()
        elseif isDraggingS_fn() then curS = applyS(inp.Position.X); fireUpdate()
        elseif isDraggingV_fn() then curV = applyV(inp.Position.X); fireUpdate()
        end
    end)

    -- Wire click-start for each track to immediately read value
    -- (the applyX functions are called from InputChanged which fires on MouseButton1 too)
    -- We also need InputBegan on tracks to set the initial value
    -- This is handled by connecting InputBegan to call applyX directly.
    -- The makeTrack helper sets dragging but doesn't call the callback on click —
    -- we hook that up here via the returned applyX functions.

    setting:OnChanged(function(val)
        swatch.BackgroundColor3 = val
        local h, s, v = val:ToHSV()
        curH, curS, curV = h, s, v
        setH(h); setS(s); setV(v)
    end)

    return container
end

-- ── Dispatch ──────────────────────────────────────────────────────────────────

function Components.Build(setting)
    local builders = {
        Slider      = Components.Slider,
        Toggle      = Components.Toggle,
        Input       = Components.Input,
        List        = Components.List,
        ColorPicker = Components.ColorPicker,
    }
    local b = builders[setting.Type]
    if b then return b(setting) end
    warn("[Vain:Components] Unknown type '" .. tostring(setting.Type) .. "'")
end

return Components
