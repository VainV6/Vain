--[[
    Theme.lua  –  Global visual configuration for the Vain framework.

    Change Theme.Accent here to instantly re-skin the entire hub.
    VainFramework.new() also accepts an AccentColor override that writes
    directly into this table, so per-instance theming works at runtime.
--]]

local Theme = {}

-- ── Accent ──────────────────────────────────────────────────────────────────
Theme.Accent         = Color3.fromRGB(120, 87, 255)   -- purple by default

-- ── Background layers (darkest → lightest) ──────────────────────────────────
Theme.Background     = Color3.fromRGB(10,  10,  16)   -- window base
Theme.Surface        = Color3.fromRGB(16,  16,  26)   -- header / sidebar
Theme.Surface2       = Color3.fromRGB(22,  22,  34)   -- module rows
Theme.Surface3       = Color3.fromRGB(30,  30,  46)   -- inactive pills / tracks

-- ── Borders ──────────────────────────────────────────────────────────────────
Theme.Border         = Color3.fromRGB(38,  38,  58)
Theme.BorderLight    = Color3.fromRGB(56,  56,  82)

-- ── Text ─────────────────────────────────────────────────────────────────────
Theme.Text           = Color3.fromRGB(230, 230, 242)   -- primary
Theme.TextMuted      = Color3.fromRGB(130, 130, 158)   -- labels
Theme.TextDim        = Color3.fromRGB(70,  70,  100)   -- keybinds / hints

-- ── Status ───────────────────────────────────────────────────────────────────
Theme.Success        = Color3.fromRGB(72,  198, 120)
Theme.Warning        = Color3.fromRGB(220, 175, 50)
Theme.Danger         = Color3.fromRGB(215, 65,  65)

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
    XXL = 24,
}

-- ── Geometry ─────────────────────────────────────────────────────────────────
Theme.Radius         = UDim.new(0, 6)
Theme.RadiusSM       = UDim.new(0, 4)
Theme.RadiusLG       = UDim.new(0, 10)
Theme.RadiusFull     = UDim.new(1, 0)

-- ── Tweens ───────────────────────────────────────────────────────────────────
Theme.Tween          = TweenInfo.new(0.22, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
Theme.TweenFast      = TweenInfo.new(0.12, Enum.EasingStyle.Quad,   Enum.EasingDirection.Out)
Theme.TweenSlow      = TweenInfo.new(0.40, Enum.EasingStyle.Cubic,  Enum.EasingDirection.Out)
Theme.TweenSpring    = TweenInfo.new(0.50, Enum.EasingStyle.Back,   Enum.EasingDirection.Out)

-- ── Layout constants ─────────────────────────────────────────────────────────
Theme.Window = {
    Width      = 560,
    Height     = 400,
    SidebarW   = 128,
    HeaderH    = 44,
    ModuleH    = 38,       -- collapsed module row height
    Padding    = 8,
}

-- Per-setting-type rendered heights (used for expand calculations)
Theme.SettingH = {
    Slider  = 46,
    Toggle  = 30,
    Input   = 46,
    List    = 30,
}

return Theme
