--[[
    Theme.lua  –  Global visual configuration for the Vain framework.
    Accent, surfaces, and radii all live here.  Override Theme.Accent at
    runtime (or pass AccentColor to VainFramework.new) to re-skin everything.
--]]

local Theme = {}

-- ── Accent ───────────────────────────────────────────────────────────────────
Theme.Accent         = Color3.fromRGB(0, 120, 255)

-- ── Backgrounds (darkest → lightest) ─────────────────────────────────────────
Theme.Background     = Color3.fromRGB(15,  15,  15)
Theme.Surface        = Color3.fromRGB(22,  22,  22)
Theme.Surface2       = Color3.fromRGB(28,  28,  28)
Theme.Surface3       = Color3.fromRGB(36,  36,  36)

-- ── Borders ──────────────────────────────────────────────────────────────────
Theme.Border         = Color3.fromRGB(50,  50,  50)
Theme.BorderLight    = Color3.fromRGB(72,  72,  72)

-- ── Text ─────────────────────────────────────────────────────────────────────
Theme.Text           = Color3.fromRGB(255, 255, 255)
Theme.TextMuted      = Color3.fromRGB(160, 160, 160)
Theme.TextDim        = Color3.fromRGB(88,  88,  88)

-- ── Status ───────────────────────────────────────────────────────────────────
Theme.Success        = Color3.fromRGB(0,   200, 80)
Theme.Warning        = Color3.fromRGB(255, 180, 0)
Theme.Danger         = Color3.fromRGB(220, 50,  50)

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

-- ── Geometry  (rounder than v1) ───────────────────────────────────────────────
Theme.Radius         = UDim.new(0, 10)    -- standard element
Theme.RadiusSM       = UDim.new(0, 7)     -- small detail
Theme.RadiusLG       = UDim.new(0, 16)    -- main window / cards
Theme.RadiusFull     = UDim.new(1,  0)    -- pills / dots

-- ── Tweens ───────────────────────────────────────────────────────────────────
Theme.Tween          = TweenInfo.new(0.25, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
Theme.TweenFast      = TweenInfo.new(0.14, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
Theme.TweenSlow      = TweenInfo.new(0.45, Enum.EasingStyle.Cubic,  Enum.EasingDirection.Out)
Theme.TweenSpring    = TweenInfo.new(0.55, Enum.EasingStyle.Back,   Enum.EasingDirection.Out)
Theme.TweenBounce    = TweenInfo.new(0.60, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)

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

-- Per-setting rendered heights (used in module row expand calculation)
Theme.SettingH = {
    Slider      = 48,
    Toggle      = 32,
    Input       = 48,
    List        = 32,
    ColorPicker = 126,   -- always fully expanded (label + 3 HSV sliders)
}

return Theme
