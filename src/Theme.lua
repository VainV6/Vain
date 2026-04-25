--[[
    Theme.lua  –  Global visual configuration for the Vain framework.
    Mirrors the rogue-tower-defense component token structure so that every
    UI element in Vain matches that design system exactly.
]]

local Theme = {}

-- ── Accent ───────────────────────────────────────────────────────────────────
Theme.Accent         = Color3.fromRGB(58,  111, 216)   -- #3A6FD8
Theme.AccentHover    = Color3.fromRGB(90,  143, 255)   -- #5A8FFF
Theme.AccentPress    = Color3.fromRGB(42,  79,  160)   -- #2A4FA0

-- ── Backgrounds ──────────────────────────────────────────────────────────────
Theme.Background     = Color3.fromRGB(26,  26,  26)    -- #1A1A1A
Theme.Surface        = Color3.fromRGB(30,  30,  30)    -- #1E1E1E
Theme.Surface2       = Color3.fromRGB(37,  37,  37)    -- #252525
Theme.Surface3       = Color3.fromRGB(42,  42,  42)    -- #2A2A2A

-- ── Borders ──────────────────────────────────────────────────────────────────
Theme.Border         = Color3.fromRGB(42,  42,  42)    -- #2A2A2A
Theme.BorderLight    = Color3.fromRGB(68,  68,  68)    -- #444444

-- ── Text ─────────────────────────────────────────────────────────────────────
Theme.Text           = Color3.fromRGB(236, 236, 236)   -- #ECECEC
Theme.TextMuted      = Color3.fromRGB(102, 102, 102)   -- #666666
Theme.TextDim        = Color3.fromRGB(68,  68,  68)    -- #444444

-- ── Status ───────────────────────────────────────────────────────────────────
Theme.Success        = Color3.fromRGB(46,  204, 113)   -- #2ECC71
Theme.Warning        = Color3.fromRGB(240, 165, 0)     -- #F0A500
Theme.Danger         = Color3.fromRGB(231, 76,  60)    -- #E74C3C

-- ── Typography ───────────────────────────────────────────────────────────────
Theme.Font           = Enum.Font.GothamMedium
Theme.FontSemi       = Enum.Font.GothamSemibold
Theme.FontBold       = Enum.Font.GothamBold
Theme.FontSize = {
    XS  = 10,
    SM  = 12,
    MD  = 13,
    LG  = 15,
    XL  = 18,
    XXL = 26,
}

-- ── Geometry ─────────────────────────────────────────────────────────────────
Theme.Radius         = UDim.new(0, 8)
Theme.RadiusSM       = UDim.new(0, 6)
Theme.RadiusLG       = UDim.new(0, 12)
Theme.RadiusFull     = UDim.new(1,  0)

-- ── Tweens ───────────────────────────────────────────────────────────────────
Theme.Tween          = TweenInfo.new(0.25, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
Theme.TweenFast      = TweenInfo.new(0.14, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
Theme.TweenSlow      = TweenInfo.new(0.45, Enum.EasingStyle.Cubic,  Enum.EasingDirection.Out)
Theme.TweenSpring    = TweenInfo.new(0.55, Enum.EasingStyle.Back,   Enum.EasingDirection.Out)
Theme.TweenBounce    = TweenInfo.new(0.60, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)

-- ── Component token tables (mirror rogue-tower-defense structure) ─────────────

Theme.Button = {
    Background   = Color3.fromRGB(26,  26,  26),   -- #1A1A1A
    Hover        = Color3.fromRGB(37,  37,  37),   -- #252525
    Active       = Color3.fromRGB(136, 136, 136),  -- #888888
    Text         = Color3.fromRGB(236, 236, 236),  -- #ECECEC
    FontSize     = 14,
    CornerRadius = 6,
}

Theme.Slider = {
    Track        = Color3.fromRGB(26,  31,  46),   -- #1A1F2E  (dark blue-slate track)
    Fill         = Color3.fromRGB(58,  111, 216),  -- #3A6FD8
    Dot          = Color3.fromRGB(58,  111, 216),  -- #3A6FD8
    DotHover     = Color3.fromRGB(90,  143, 255),  -- #5A8FFF
    DotPress     = Color3.fromRGB(42,  79,  160),  -- #2A4FA0
    TrackHeight  = 6,
    DotSize      = 20,
    DotSizeHover = 26,
    DotSizePress = 14,
}

Theme.Toggle = {
    TransitionTime = 0.18,
    CornerRadius   = 6,
    TrackOff     = Color3.fromRGB(42,  42,  42),   -- #2A2A2A
    TrackOn      = Color3.fromRGB(58,  111, 216),  -- #3A6FD8
    Dot          = Color3.fromRGB(255, 255, 255),
    TrackWidth   = 44,
    TrackHeight  = 24,
    DotSize      = 18,
}

Theme.Toast = {
    Background   = Color3.fromRGB(26,  26,  26),   -- #1A1A1A
    Border       = Color3.fromRGB(42,  42,  42),   -- #2A2A2A
    Text         = Color3.fromRGB(236, 236, 236),  -- #ECECEC
    TextMuted    = Color3.fromRGB(153, 153, 153),  -- #999999
    Info         = Color3.fromRGB(58,  111, 216),  -- #3A6FD8
    Success      = Color3.fromRGB(46,  204, 113),  -- #2ECC71
    Warning      = Color3.fromRGB(240, 165, 0),    -- #F0A500
    Error        = Color3.fromRGB(231, 76,  60),   -- #E74C3C
    FontSize     = 13,
    CornerRadius = 8,
    PaddingX     = 14,
    PaddingY     = 10,
    Duration     = 3.0,
}

-- ── Layout constants ─────────────────────────────────────────────────────────
Theme.Window = {
    Width      = 580,
    Height     = 430,
    SidebarW   = 132,
    HeaderH    = 50,
    ModuleH    = 40,
    Padding    = 10,
    SearchH    = 38,
}

Theme.SettingH = {
    Slider      = 52,
    Toggle      = 32,
    Input       = 52,
    List        = 32,
    ColorPicker = 130,
}

return Theme
