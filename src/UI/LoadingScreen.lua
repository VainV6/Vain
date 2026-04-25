--[[
    UI/LoadingScreen.lua  –  Vain intro animation.

    Sequence
        0.00  Backdrop fades in (Quad, 0.35 s)
        0.35  "VAIN" slides up from +28 px AND fades in (Back Out, 0.55 s)
        0.70  Accent underline sweeps left→right (Quad Out, 0.42 s)
        0.90  Tagline fades in (Cubic Out, 0.38 s)
        1.00  Version fades in (0.30 s)
        1.10  Loading bar fills (Quad InOut, 1.25 s) + shimmer loops
        2.45  Short hold, then everything fades out (0.45 s)
        2.95  GUI destroyed; onComplete() fires
--]]

local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")

local Theme = require(script.Parent.Parent.Theme)

local LoadingScreen = {}

local function tw(obj, info, props) return TweenService:Create(obj, info, props) end
local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = r or Theme.RadiusSM; c.Parent = p end

function LoadingScreen:Show(onComplete)
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    -- Root
    local gui              = Instance.new("ScreenGui")
    gui.Name               = "VainLoader"
    gui.ResetOnSpawn       = false
    gui.IgnoreGuiInset     = true
    gui.DisplayOrder       = 9999
    gui.Parent             = playerGui

    -- Full-screen backdrop
    local backdrop         = Instance.new("Frame")
    backdrop.Size          = UDim2.fromScale(1, 1)
    backdrop.BackgroundColor3     = Theme.Background
    backdrop.BackgroundTransparency = 1
    backdrop.BorderSizePixel      = 0
    backdrop.Parent                = gui

    -- Centered card
    local card             = Instance.new("Frame")
    card.Size              = UDim2.fromOffset(360, 200)
    card.AnchorPoint       = Vector2.new(0.5, 0.5)
    card.Position          = UDim2.fromScale(0.5, 0.5)
    card.BackgroundTransparency = 1
    card.Parent            = backdrop

    -- ── "VAIN" logo ──────────────────────────────────────────────────────────
    local logo             = Instance.new("TextLabel")
    logo.Size              = UDim2.new(1, 0, 0, 90)
    logo.Position          = UDim2.fromOffset(0, 28)
    logo.BackgroundTransparency = 1
    logo.Text              = "VAIN"
    logo.Font              = Theme.FontBold
    logo.TextSize          = 88
    logo.TextColor3        = Theme.Text
    logo.TextTransparency  = 1
    logo.TextXAlignment    = Enum.TextXAlignment.Center
    logo.Parent            = card

    -- ── Accent underline ─────────────────────────────────────────────────────
    local ulWrap           = Instance.new("Frame")
    ulWrap.Size            = UDim2.new(0.72, 0, 0, 5)
    ulWrap.AnchorPoint     = Vector2.new(0.5, 0)
    ulWrap.Position        = UDim2.new(0.5, 0, 0, 98)
    ulWrap.BackgroundTransparency = 1
    ulWrap.ClipsDescendants = true
    ulWrap.Parent          = card

    local ul               = Instance.new("Frame")
    ul.Size                = UDim2.fromScale(1, 1)
    ul.Position            = UDim2.fromScale(-1, 0)
    ul.BackgroundColor3    = Theme.Accent
    ul.BorderSizePixel     = 0
    ul.Parent              = ulWrap
    corner(ul, Theme.RadiusFull)

    local ulGrad           = Instance.new("UIGradient")
    ulGrad.Color           = ColorSequence.new{
        ColorSequenceKeypoint.new(0,   Theme.AccentHover),
        ColorSequenceKeypoint.new(0.5, Theme.Accent),
        ColorSequenceKeypoint.new(1,   Theme.AccentHover),
    }
    ulGrad.Parent          = ul

    -- ── Tagline ───────────────────────────────────────────────────────────────
    local tagline          = Instance.new("TextLabel")
    tagline.Size           = UDim2.new(1, 0, 0, 20)
    tagline.Position       = UDim2.fromOffset(0, 114)
    tagline.BackgroundTransparency = 1
    tagline.Text           = "quality matters"
    tagline.Font           = Theme.Font
    tagline.TextSize       = Theme.FontSize.MD
    tagline.TextColor3     = Theme.TextMuted
    tagline.TextTransparency = 1
    tagline.TextXAlignment = Enum.TextXAlignment.Center
    tagline.Parent         = card

    -- ── Version ───────────────────────────────────────────────────────────────
    local version          = Instance.new("TextLabel")
    version.Size           = UDim2.new(1, 0, 0, 14)
    version.Position       = UDim2.fromOffset(0, 138)
    version.BackgroundTransparency = 1
    version.Text           = "v2.0"
    version.Font           = Theme.Font
    version.TextSize       = Theme.FontSize.XS
    version.TextColor3     = Theme.TextDim
    version.TextTransparency = 1
    version.TextXAlignment = Enum.TextXAlignment.Center
    version.Parent         = card

    -- ── Loading bar ───────────────────────────────────────────────────────────
    local barTrack         = Instance.new("Frame")
    barTrack.Size          = UDim2.new(0.78, 0, 0, 8)
    barTrack.AnchorPoint   = Vector2.new(0.5, 0)
    barTrack.Position      = UDim2.new(0.5, 0, 0, 165)
    barTrack.BackgroundColor3    = Theme.Surface3
    barTrack.BackgroundTransparency = 0
    barTrack.BorderSizePixel     = 0
    barTrack.Parent        = card
    corner(barTrack, Theme.RadiusFull)

    local barFill          = Instance.new("Frame")
    barFill.Size           = UDim2.fromScale(0, 1)
    barFill.BackgroundColor3    = Theme.Accent
    barFill.BorderSizePixel     = 0
    barFill.Parent         = barTrack
    corner(barFill, Theme.RadiusFull)

    local barGrad          = Instance.new("UIGradient")
    barGrad.Color          = ColorSequence.new{
        ColorSequenceKeypoint.new(0,    Theme.Accent),
        ColorSequenceKeypoint.new(0.45, Theme.AccentHover),
        ColorSequenceKeypoint.new(0.55, Theme.AccentHover),
        ColorSequenceKeypoint.new(1,    Theme.Accent),
    }
    barGrad.Parent         = barFill

    -- Shimmer sweep
    local shimmerDir       = true
    local shimmerConn      = RunService.RenderStepped:Connect(function(dt)
        local cur = barGrad.Offset.X
        local next = cur + (shimmerDir and dt * 0.9 or -dt * 0.9)
        if next >= 1 then shimmerDir = false
        elseif next <= -1 then shimmerDir = true end
        barGrad.Offset = Vector2.new(math.clamp(next, -1, 1), 0)
    end)

    -- ── Animation sequence ────────────────────────────────────────────────────

    -- 0.00  Backdrop in
    tw(backdrop, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0}):Play()
    task.wait(0.35)

    -- 0.35  Logo slides up + fades in
    tw(logo, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(0, 0), TextTransparency = 0}):Play()
    task.wait(0.35)

    -- 0.70  Underline sweeps in
    tw(ul, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromScale(0, 0)}):Play()
    task.wait(0.20)

    -- 0.90  Tagline
    tw(tagline, TweenInfo.new(0.38, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
        {TextTransparency = 0}):Play()
    task.wait(0.10)

    -- 1.00  Version
    tw(version, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {TextTransparency = 0}):Play()
    task.wait(0.10)

    -- 1.10  Bar fills
    tw(barFill, TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
        {Size = UDim2.fromScale(1, 1)}):Play()
    task.wait(1.40)

    -- 2.50  Fade out
    shimmerConn:Disconnect()
    local fadeOut = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    for _, obj in ipairs{backdrop, logo, tagline, version, ul, barTrack, barFill} do
        local props = obj:IsA("TextLabel")
            and {TextTransparency = 1, BackgroundTransparency = 1}
            or  {BackgroundTransparency = 1}
        tw(obj, fadeOut, props):Play()
    end
    task.wait(0.50)

    gui:Destroy()
    if onComplete then onComplete() end
end

return LoadingScreen
