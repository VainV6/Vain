--[[
    UI/LoadingScreen.lua  –  Vain intro animation.

    Animation sequence
        0.00  Dark overlay fades in
        0.30  "VAIN" text materialises
        0.55  Accent underline sweeps left → right
        0.80  Tagline fades in
        0.90  Version fades in
        1.00  Loading bar fills over ~1.1 s
        2.20  Everything fades out
        2.75  ScreenGui destroyed; onComplete() fires

    API:
        LoadingScreen:Show(onComplete)   –  plays the animation then calls fn
--]]

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")

local Theme = require(script.Parent.Parent.Theme)

local LoadingScreen = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function tw(obj, info, props)
    return TweenService:Create(obj, info, props)
end

local function corner(parent, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or Theme.RadiusSM
    c.Parent = parent
    return c
end

-- ── Public ───────────────────────────────────────────────────────────────────

function LoadingScreen:Show(onComplete)
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    -- Root
    local gui             = Instance.new("ScreenGui")
    gui.Name              = "VainLoader"
    gui.ResetOnSpawn      = false
    gui.IgnoreGuiInset    = true
    gui.DisplayOrder      = 9999
    gui.Parent            = playerGui

    -- Full-screen backdrop
    local backdrop        = Instance.new("Frame")
    backdrop.Size         = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3     = Theme.Background
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel      = 0
    backdrop.Parent               = gui

    -- Centered card
    local card            = Instance.new("Frame")
    card.Size             = UDim2.fromOffset(320, 170)
    card.AnchorPoint      = Vector2.new(0.5, 0.5)
    card.Position         = UDim2.fromScale(0.5, 0.5)
    card.BackgroundTransparency = 1
    card.Parent           = backdrop

    -- ── "VAIN" logo ──────────────────────────────────────────────────────────
    local logo            = Instance.new("TextLabel")
    logo.Size             = UDim2.new(1, 0, 0, 70)
    logo.Position         = UDim2.fromOffset(0, 0)
    logo.BackgroundTransparency = 1
    logo.Text             = "VAIN"
    logo.Font             = Theme.FontBold
    logo.TextSize         = 68
    logo.TextColor3       = Theme.Text
    logo.TextTransparency = 1
    logo.TextXAlignment   = Enum.TextXAlignment.Center
    logo.Parent           = card

    -- ── Accent underline ─────────────────────────────────────────────────────
    local underlineWrap   = Instance.new("Frame")
    underlineWrap.Size    = UDim2.new(0.6, 0, 0, 3)
    underlineWrap.AnchorPoint  = Vector2.new(0.5, 0)
    underlineWrap.Position     = UDim2.new(0.5, 0, 0, 74)
    underlineWrap.BackgroundTransparency = 1
    underlineWrap.ClipsDescendants = true
    underlineWrap.Parent  = card

    local underline       = Instance.new("Frame")
    underline.Size        = UDim2.fromScale(1, 1)
    underline.Position    = UDim2.fromScale(-1, 0)   -- starts off-screen left
    underline.BackgroundColor3 = Theme.Accent
    underline.BorderSizePixel  = 0
    underline.Parent      = underlineWrap
    corner(underline, UDim.new(0, 2))

    -- Shimmer gradient on underline
    local shimmer         = Instance.new("UIGradient")
    shimmer.Color         = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Theme.Accent),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(255, 255, 255)),
    })
    shimmer.Parent        = underline

    -- ── Tagline ───────────────────────────────────────────────────────────────
    local tagline         = Instance.new("TextLabel")
    tagline.Size          = UDim2.new(1, 0, 0, 18)
    tagline.Position      = UDim2.fromOffset(0, 88)
    tagline.BackgroundTransparency = 1
    tagline.Text          = "quality matters"
    tagline.Font          = Theme.Font
    tagline.TextSize      = Theme.FontSize.SM
    tagline.TextColor3    = Theme.TextMuted
    tagline.TextTransparency = 1
    tagline.TextXAlignment = Enum.TextXAlignment.Center
    tagline.Parent        = card

    -- ── Version ───────────────────────────────────────────────────────────────
    local version         = Instance.new("TextLabel")
    version.Size          = UDim2.new(1, 0, 0, 14)
    version.Position      = UDim2.fromOffset(0, 110)
    version.BackgroundTransparency = 1
    version.Text          = "v1.0.0"
    version.Font          = Theme.Font
    version.TextSize      = Theme.FontSize.XS
    version.TextColor3    = Theme.TextDim
    version.TextTransparency = 1
    version.TextXAlignment = Enum.TextXAlignment.Center
    version.Parent        = card

    -- ── Loading bar ───────────────────────────────────────────────────────────
    local barTrack        = Instance.new("Frame")
    barTrack.Size         = UDim2.new(0.7, 0, 0, 2)
    barTrack.AnchorPoint  = Vector2.new(0.5, 0)
    barTrack.Position     = UDim2.new(0.5, 0, 0, 136)
    barTrack.BackgroundColor3    = Theme.Surface3
    barTrack.BackgroundTransparency = 0
    barTrack.BorderSizePixel     = 0
    barTrack.Parent       = card
    corner(barTrack, UDim.new(0, 1))

    local barFill         = Instance.new("Frame")
    barFill.Size          = UDim2.fromScale(0, 1)
    barFill.BackgroundColor3    = Theme.Accent
    barFill.BorderSizePixel     = 0
    barFill.Parent        = barTrack
    corner(barFill, UDim.new(0, 1))

    -- Glow layer on bar fill
    local barGlow         = Instance.new("UIGradient")
    barGlow.Color         = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Theme.Accent),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(180, 140, 255)),
    })
    barGlow.Parent        = barFill

    -- ── Animation sequence ────────────────────────────────────────────────────

    -- 0.00  Backdrop fade in
    tw(backdrop, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {BackgroundTransparency = 0}):Play()
    task.wait(0.30)

    -- 0.30  Logo appears
    tw(logo, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()
    task.wait(0.25)

    -- 0.55  Underline sweeps in
    tw(underline,
        TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromScale(0, 0)}
    ):Play()
    task.wait(0.25)

    -- 0.80  Tagline
    tw(tagline, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()
    task.wait(0.10)

    -- 0.90  Version
    tw(version, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()
    task.wait(0.10)

    -- 1.00  Fill bar
    tw(barFill,
        TweenInfo.new(1.10, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
        {Size = UDim2.fromScale(1, 1)}
    ):Play()
    task.wait(1.20)

    -- 2.20  Fade everything out
    local fadeOut = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    tw(backdrop,  fadeOut, {BackgroundTransparency = 1}):Play()
    tw(logo,      fadeOut, {TextTransparency = 1}):Play()
    tw(tagline,   fadeOut, {TextTransparency = 1}):Play()
    tw(version,   fadeOut, {TextTransparency = 1}):Play()
    tw(underline, fadeOut, {BackgroundTransparency = 1}):Play()
    tw(barTrack,  fadeOut, {BackgroundTransparency = 1}):Play()
    tw(barFill,   fadeOut, {BackgroundTransparency = 1}):Play()
    task.wait(0.50)

    -- 2.70  Cleanup → callback
    gui:Destroy()
    if onComplete then
        onComplete()
    end
end

return LoadingScreen
