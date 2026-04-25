--[[
    UI/Components.lua  –  Setting-component builders for the Vain settings panel.

    Visual specs mirror the rogue-tower-defense component library exactly:
      • Slider  – 6px track, 20px dot with Grow hover (26px) and Shrink press (14px)
      • Toggle  – SliderToggle style: 44×24 track, 18px dot, 0.18s Quad transition
      • Input   – TextBox / keybind button with focus-ring stroke
      • List    – Dropdown with background-highlight option rows
      • ColorPicker – Always-expanded HSV sliders

    Public:
        Components.Build(setting) → Frame
        Components.Slider(setting) → Frame
        Components.Toggle(setting) → Frame
        Components.Input(setting) → Frame
        Components.List(setting) → Frame
        Components.ColorPicker(setting) → Frame
--]]

local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)

local Components = {}

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
    return s
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
-- Exact port of rogue-tower-defense Slider:
--   track = 6px, pill-shaped, dark blue-slate (#1A1F2E)
--   fill  = accent (#3A6FD8), pill-shaped
--   dot   = 20px circle, accent color
--   hover → dot grows to 26px (Back easing)
--   press → dot shrinks to 14px; release → restores to 20px
--   wide hitbox above/below track for easy clicking

function Components.Slider(setting)
    local S    = Theme.Slider
    local h    = Theme.SettingH.Slider
    local pct0 = (setting.Value - setting.Min) / (setting.Max - setting.Min)

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, h)
    container.BackgroundTransparency = 1

    -- Name / value labels
    local nameL = lbl(container, setting.Name)
    nameL.Size     = UDim2.new(1, -58, 0, 16)
    nameL.Position = UDim2.fromOffset(0, 4)

    local valueL = lbl(container, "", Theme.FontSemi, Theme.FontSize.SM, Theme.Accent, Enum.TextXAlignment.Right)
    valueL.Size     = UDim2.fromOffset(56, 16)
    valueL.Position = UDim2.new(1, -56, 0, 4)

    local function fmtVal(v)
        return string.format((setting.Step % 1 == 0) and "%d" or "%.2f", v) .. (setting.Suffix or "")
    end
    valueL.Text = fmtVal(setting.Value)

    -- Track (centered at Y=30 inside the 52px container)
    local track = Instance.new("Frame")
    track.Name         = "Track"
    track.Size         = UDim2.new(1, 0, 0, S.TrackHeight)
    track.AnchorPoint  = Vector2.new(0, 0.5)
    track.Position     = UDim2.fromOffset(0, 30)
    track.BackgroundColor3 = S.Track
    track.BorderSizePixel  = 0
    track.Parent = container
    corner(track, Theme.RadiusFull)

    -- Fill
    local fill = Instance.new("Frame")
    fill.Size            = UDim2.fromScale(pct0, 1)
    fill.BackgroundColor3 = S.Fill
    fill.BorderSizePixel  = 0
    fill.Parent = track
    corner(fill, Theme.RadiusFull)

    -- Dot (child of track so position is relative to track)
    local dot = Instance.new("Frame")
    dot.Name         = "Dot"
    dot.Size         = UDim2.fromOffset(S.DotSize, S.DotSize)
    dot.AnchorPoint  = Vector2.new(0.5, 0.5)
    dot.Position     = UDim2.fromScale(pct0, 0.5)
    dot.BackgroundColor3 = S.Dot
    dot.BorderSizePixel  = 0
    dot.ZIndex = 3
    dot.Parent = track
    corner(dot, Theme.RadiusFull)

    -- Wide hitbox for easy clicking (same height as DotSize + margin, like rogue-tower-defense)
    local hitbox = Instance.new("TextButton")
    hitbox.AnchorPoint = Vector2.new(0, 0.5)
    hitbox.Position    = UDim2.fromScale(0, 0.5)
    hitbox.Size        = UDim2.new(1, 0, 0, S.DotSize + 10)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.ZIndex = 2
    hitbox.Parent = track

    local dragging = false

    local function applyX(screenX)
        local pct = math.clamp((screenX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        setting:Set(setting.Min + pct * (setting.Max - setting.Min))
    end

    -- Hover: Grow  (matches rogue-tower-defense DotHoverAnimation = "Grow")
    hitbox.MouseEnter:Connect(function()
        if not dragging then
            tw(dot, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
                Size = UDim2.fromOffset(S.DotSizeHover, S.DotSizeHover),
            }):Play()
        end
    end)
    hitbox.MouseLeave:Connect(function()
        if not dragging then
            tw(dot, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
                Size = UDim2.fromOffset(S.DotSize, S.DotSize),
            }):Play()
        end
    end)

    -- Press: Shrink  (matches rogue-tower-defense DotClickAnimation = "Shrink")
    hitbox.MouseButton1Down:Connect(function()
        dragging = true
        tw(dot, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(S.DotSizePress, S.DotSizePress),
        }):Play()
        applyX(UserInputService:GetMouseLocation().X)
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
            if dragging then
                dragging = false
                tw(dot, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
                    Size = UDim2.fromOffset(S.DotSize, S.DotSize),
                }):Play()
            end
        end
    end)

    setting:OnChanged(function(val)
        local p = (val - setting.Min) / (setting.Max - setting.Min)
        tw(fill, Theme.TweenFast, {Size = UDim2.fromScale(p, 1)}):Play()
        tw(dot,  Theme.TweenFast, {Position = UDim2.fromScale(p, 0.5)}):Play()
        valueL.Text = fmtVal(val)
    end)

    return container
end

-- ── Toggle ────────────────────────────────────────────────────────────────────
-- Exact port of rogue-tower-defense SliderToggle:
--   track = 44×24, CornerRadius 6
--   dot   = 18×18, white, CornerRadius 6
--   dotTravel = TrackWidth - DotSize - 4  (2px margin each side)
--   transition = Quad, 0.18s

function Components.Toggle(setting)
    local T   = Theme.Toggle
    local on0 = setting.Value == true

    -- dotTravel: 44 - 18 - 4 = 22px; dot rests at x=2 (off) or x=24 (on)
    local dotTravel = T.TrackWidth - T.DotSize - 4
    local dotY      = (T.TrackHeight - T.DotSize) / 2
    local dotXOff   = 2
    local dotXOn    = 2 + dotTravel

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.Toggle)
    container.BackgroundTransparency = 1

    local nameL = lbl(container, setting.Name)
    nameL.Size  = UDim2.new(1, -(T.TrackWidth + 10), 1, 0)

    -- The pill is a TextButton (matches rogue-tower-defense SliderToggle)
    local pill = Instance.new("TextButton")
    pill.Size            = UDim2.fromOffset(T.TrackWidth, T.TrackHeight)
    pill.AnchorPoint     = Vector2.new(1, 0.5)
    pill.Position        = UDim2.new(1, 0, 0.5, 0)
    pill.BackgroundColor3 = on0 and T.TrackOn or T.TrackOff
    pill.BorderSizePixel  = 0
    pill.Text            = ""
    pill.AutoButtonColor = false
    pill.Parent = container
    corner(pill, UDim.new(0, T.CornerRadius))

    local knob = Instance.new("Frame")
    knob.Size            = UDim2.fromOffset(T.DotSize, T.DotSize)
    knob.Position        = UDim2.fromOffset(on0 and dotXOn or dotXOff, dotY)
    knob.BackgroundColor3 = T.Dot
    knob.BorderSizePixel  = 0
    knob.Parent = pill
    corner(knob, UDim.new(0, T.CornerRadius))

    pill.MouseButton1Click:Connect(function()
        setting:Set(not setting.Value)
    end)

    local tweenInfo = TweenInfo.new(T.TransitionTime, Enum.EasingStyle.Quad)
    setting:OnChanged(function(val)
        tw(pill, tweenInfo, {BackgroundColor3 = val and T.TrackOn or T.TrackOff}):Play()
        tw(knob, tweenInfo, {Position = UDim2.fromOffset(val and dotXOn or dotXOff, dotY)}):Play()
    end)

    return container
end

-- ── Input / Keybind ───────────────────────────────────────────────────────────
-- TextBox: styled like rogue-tower-defense NumberInput (bordered, focus-ring)
-- Keybind: styled as a button that lights up accent while listening

function Components.Input(setting)
    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.Input)
    container.BackgroundTransparency = 1

    local nameL = lbl(container, setting.Name)
    nameL.Size     = UDim2.new(1, 0, 0, 16)
    nameL.Position = UDim2.fromOffset(0, 4)

    local FIELD_H = 32

    if setting.IsKeybind then
        local btn = Instance.new("TextButton")
        btn.Size             = UDim2.new(1, 0, 0, FIELD_H)
        btn.Position         = UDim2.fromOffset(0, 22)
        btn.BackgroundColor3 = Theme.Surface2
        btn.BorderSizePixel  = 0
        btn.AutoButtonColor  = false
        btn.Font             = Theme.FontSemi
        btn.TextSize         = Theme.FontSize.SM
        btn.TextColor3       = setting.Value ~= "" and Theme.Text or Theme.TextDim
        btn.Text             = setting.Value ~= "" and "[" .. setting.Value .. "]" or "Click to bind..."
        btn.Parent = container
        corner(btn, UDim.new(0, Theme.Button.CornerRadius))
        local s = stroke(btn, Theme.Border, 1)

        local listening = false
        btn.MouseButton1Click:Connect(function()
            listening      = true
            btn.Text       = "···"
            btn.TextColor3 = Theme.TextMuted
            tw(s,   Theme.TweenFast, {Color = Theme.Accent}):Play()
            tw(btn, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
        end)
        UserInputService.InputBegan:Connect(function(inp)
            if not listening then return end
            if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
            listening      = false
            local name     = inp.KeyCode.Name
            btn.Text       = "[" .. name .. "]"
            btn.TextColor3 = Theme.Text
            tw(s,   Theme.TweenFast, {Color = Theme.Border}):Play()
            tw(btn, Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
            setting:Set(name)
        end)
        setting:OnChanged(function(val)
            btn.Text       = val ~= "" and "[" .. val .. "]" or "Click to bind..."
            btn.TextColor3 = val ~= "" and Theme.Text or Theme.TextDim
        end)

    else
        local box = Instance.new("TextBox")
        box.Size             = UDim2.new(1, 0, 0, FIELD_H)
        box.Position         = UDim2.fromOffset(0, 22)
        box.BackgroundColor3 = Theme.Surface2
        box.BorderSizePixel  = 0
        box.Font             = Theme.Font
        box.TextSize         = Theme.FontSize.SM
        box.TextColor3       = Theme.Text
        box.PlaceholderText  = setting.Placeholder or ""
        box.PlaceholderColor3 = Theme.TextDim
        box.Text             = tostring(setting.Value)
        box.ClearTextOnFocus = false
        box.Parent = container
        corner(box, UDim.new(0, Theme.Button.CornerRadius))
        local s = stroke(box, Theme.Border, 1)

        local padInst = Instance.new("UIPadding")
        padInst.PaddingLeft  = UDim.new(0, 10)
        padInst.PaddingRight = UDim.new(0, 10)
        padInst.Parent = box

        box.Focused:Connect(function()
            tw(box, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
            tw(s,   Theme.TweenFast, {Color = Theme.Accent}):Play()
        end)
        box.FocusLost:Connect(function()
            tw(box, Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
            tw(s,   Theme.TweenFast, {Color = Theme.Border}):Play()
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
    local ROW_H = 28

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.List)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false

    local nameL = lbl(container, setting.Name)
    nameL.Size  = UDim2.new(0.46, 0, 1, 0)

    local selBtn = Instance.new("TextButton")
    selBtn.Size            = UDim2.new(0.52, 0, 0, 26)
    selBtn.AnchorPoint     = Vector2.new(1, 0.5)
    selBtn.Position        = UDim2.new(1, 0, 0.5, 0)
    selBtn.BackgroundColor3 = Theme.Surface2
    selBtn.BorderSizePixel  = 0
    selBtn.AutoButtonColor  = false
    selBtn.Font            = Theme.FontSemi
    selBtn.TextSize        = Theme.FontSize.SM
    selBtn.TextColor3      = Theme.Text
    selBtn.Text            = setting.Value .. "  ▾"
    selBtn.Parent = container
    corner(selBtn, UDim.new(0, Theme.Button.CornerRadius))
    stroke(selBtn, Theme.Border, 1)

    selBtn.MouseEnter:Connect(function()
        tw(selBtn, Theme.TweenFast, {BackgroundColor3 = Theme.Surface3}):Play()
    end)
    selBtn.MouseLeave:Connect(function()
        tw(selBtn, Theme.TweenFast, {BackgroundColor3 = Theme.Surface2}):Play()
    end)

    local panel = Instance.new("Frame")
    panel.Size            = UDim2.new(0.52, 0, 0, 0)
    panel.AnchorPoint     = Vector2.new(1, 0)
    panel.Position        = UDim2.new(1, 0, 1, 4)
    panel.BackgroundColor3 = Theme.Surface
    panel.BorderSizePixel  = 0
    panel.ClipsDescendants = true
    panel.ZIndex  = 20
    panel.Visible = false
    panel.Parent  = container
    corner(panel, UDim.new(0, Theme.Button.CornerRadius))
    stroke(panel, Theme.BorderLight, 1)

    local panelPad = Instance.new("UIPadding")
    panelPad.PaddingTop    = UDim.new(0, 4)
    panelPad.PaddingBottom = UDim.new(0, 4)
    panelPad.PaddingLeft   = UDim.new(0, 4)
    panelPad.PaddingRight  = UDim.new(0, 4)
    panelPad.Parent = panel

    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Vertical
    listLayout.Padding       = UDim.new(0, 2)
    listLayout.Parent = panel

    local isOpen = false
    local totalH = #setting.Options * (ROW_H + 2) + 8  -- rows + gaps + padding

    for _, opt in ipairs(setting.Options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size             = UDim2.new(1, 0, 0, ROW_H)
        optBtn.BackgroundColor3 = Theme.Surface2
        optBtn.BackgroundTransparency = 1
        optBtn.BorderSizePixel  = 0
        optBtn.AutoButtonColor  = false
        optBtn.Font             = Theme.Font
        optBtn.TextSize         = Theme.FontSize.SM
        optBtn.TextColor3       = opt == setting.Value and Theme.Accent or Theme.TextMuted
        optBtn.Text             = opt
        optBtn.ZIndex = 21
        optBtn.Parent = panel
        corner(optBtn, UDim.new(0, 4))

        optBtn.MouseEnter:Connect(function()
            tw(optBtn, Theme.TweenFast, {BackgroundTransparency = 0, TextColor3 = Theme.Text}):Play()
        end)
        optBtn.MouseLeave:Connect(function()
            local isSelected = optBtn.Text == setting.Value
            tw(optBtn, Theme.TweenFast, {
                BackgroundTransparency = 1,
                TextColor3 = isSelected and Theme.Accent or Theme.TextMuted,
            }):Play()
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

function Components.ColorPicker(setting)
    local h0, s0, v0 = setting.Value:ToHSV()
    local curH, curS, curV = h0, s0, v0
    local S = Theme.Slider

    local container = Instance.new("Frame")
    container.Size  = UDim2.new(1, 0, 0, Theme.SettingH.ColorPicker)
    container.BackgroundTransparency = 1

    local nameL = lbl(container, setting.Name)
    nameL.Size     = UDim2.new(1, -52, 0, 20)
    nameL.Position = UDim2.fromOffset(0, 4)

    local swatch = Instance.new("Frame")
    swatch.Size        = UDim2.fromOffset(42, 20)
    swatch.AnchorPoint = Vector2.new(1, 0)
    swatch.Position    = UDim2.new(1, 0, 0, 4)
    swatch.BackgroundColor3 = setting.Value
    swatch.BorderSizePixel  = 0
    swatch.Parent = container
    corner(swatch, UDim.new(0, Theme.Button.CornerRadius))
    stroke(swatch, Theme.Border, 1)

    -- One compact HSV slider track
    local function makeTrack(labelText, topY, initPct, hueMode)
        local row = Instance.new("Frame")
        row.Size     = UDim2.new(1, 0, 0, 30)
        row.Position = UDim2.fromOffset(0, topY)
        row.BackgroundTransparency = 1
        row.Parent = container

        local rowLbl = lbl(row, labelText, Theme.Font, Theme.FontSize.XS, Theme.TextDim)
        rowLbl.Size = UDim2.fromOffset(12, 30)

        local track = Instance.new("Frame")
        track.Size     = UDim2.new(1, -18, 0, S.TrackHeight)
        track.Position = UDim2.new(0, 16, 0.5, -S.TrackHeight / 2)
        track.BorderSizePixel = 0
        track.Parent = row

        if hueMode then
            track.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            local g = Instance.new("UIGradient")
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,     Color3.fromHSV(0,     1, 1)),
                ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
                ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
                ColorSequenceKeypoint.new(0.5,   Color3.fromHSV(0.5,   1, 1)),
                ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
                ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
                ColorSequenceKeypoint.new(1,     Color3.fromHSV(0,     1, 1)),
            })
            g.Parent = track
        else
            track.BackgroundColor3 = S.Track
        end
        corner(track, Theme.RadiusFull)

        local fill = Instance.new("Frame")
        fill.Size   = UDim2.fromScale(initPct, 1)
        fill.BackgroundColor3 = hueMode and Color3.fromRGB(255, 255, 255) or S.Fill
        fill.BackgroundTransparency = hueMode and 1 or 0
        fill.BorderSizePixel = 0
        fill.Parent = track
        corner(fill, Theme.RadiusFull)

        local knob = Instance.new("Frame")
        knob.Size        = UDim2.fromOffset(14, 14)
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position    = UDim2.fromScale(initPct, 0.5)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel  = 0
        knob.ZIndex = 3
        knob.Parent = track
        corner(knob, Theme.RadiusFull)
        stroke(knob, Theme.Border, 1)

        local hitbox = Instance.new("TextButton")
        hitbox.AnchorPoint = Vector2.new(0, 0.5)
        hitbox.Position    = UDim2.fromScale(0, 0.5)
        hitbox.Size        = UDim2.new(1, 0, 0, 24)
        hitbox.BackgroundTransparency = 1
        hitbox.Text = ""
        hitbox.ZIndex = 2
        hitbox.Parent = track

        local dragging = false

        hitbox.MouseButton1Down:Connect(function()
            dragging = true
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)

        local function applyX(x)
            local pct = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            tw(fill, Theme.TweenFast, {Size = UDim2.fromScale(pct, 1)}):Play()
            tw(knob, Theme.TweenFast, {Position = UDim2.fromScale(pct, 0.5)}):Play()
            return pct
        end

        local function setVisual(pct)
            fill.Size = UDim2.fromScale(pct, 1)
            knob.Position = UDim2.fromScale(pct, 0.5)
        end

        return applyX, setVisual, function() return dragging end
    end

    local function fireUpdate()
        local color = Color3.fromHSV(curH, curS, curV)
        setting:Set(color)
        swatch.BackgroundColor3 = color
    end

    local applyH, setH, isDraggingH = makeTrack("H", 30,  curH, true)
    local applyS, setS, isDraggingS = makeTrack("S", 64,  curS, false)
    local applyV, setV, isDraggingV = makeTrack("V", 98, curV, false)

    UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement
        and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        if isDraggingH() then curH = applyH(inp.Position.X); fireUpdate()
        elseif isDraggingS() then curS = applyS(inp.Position.X); fireUpdate()
        elseif isDraggingV() then curV = applyV(inp.Position.X); fireUpdate()
        end
    end)

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
    warn("[Vain:Components] Unknown setting type '" .. tostring(setting.Type) .. "'")
end

return Components
