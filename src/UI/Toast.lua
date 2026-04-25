--[[
    UI/Toast.lua  –  Imperative notification system. Ported from the
    rogue-tower-defense Toast component with corrected right-side positioning.

    Setup (once, done automatically by VainFramework):
        Toast.mount(playerGui)

    Usage:
        local id = Toast.show("AimAssist enabled",  { Variant = "success" })
        local id = Toast.show("Module disabled",    { Variant = "info" })
        local id = Toast.show("Warning!",           { Variant = "warning", Duration = 5 })
        Toast.dismiss(id)

    Variants: "info" | "success" | "warning" | "error"
--]]

local TweenService = game:GetService("TweenService")

local Theme      = require(script.Parent.Parent.Theme)
local T          = Theme.Toast

local SLIDE_TIME = 0.22
local STACK_GAP  = 6
local TOAST_W    = 280
local SCREEN_PAD = 16

local toastContainer = nil
local nextId         = 0
local activeToasts   = {}   -- { id, frame, height, timer, progressTween }
local toastsEnabled  = true

local Toast = {}

function Toast.setEnabled(v)
    toastsEnabled = v
end

function Toast.unmount()
    for _, entry in ipairs(activeToasts) do
        if entry.timer then pcall(task.cancel, entry.timer) end
        if entry.progressTween then pcall(function() entry.progressTween:Cancel() end) end
        if entry.frame and entry.frame.Parent then entry.frame:Destroy() end
    end
    activeToasts = {}
    if toastContainer then
        local gui = toastContainer.Parent
        toastContainer:Destroy()
        toastContainer = nil
        if gui and gui.Parent then gui:Destroy() end
    end
end

local function nextToastId()
    nextId += 1
    return nextId
end

-- Restack all active toasts from the top-right
local function restack()
    local y = SCREEN_PAD
    for _, entry in ipairs(activeToasts) do
        if entry.frame and entry.frame.Parent then
            TweenService:Create(entry.frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
                -- right edge of screen minus toast width minus padding
                Position = UDim2.new(1, -(TOAST_W + SCREEN_PAD), 0, y),
            }):Play()
            y += entry.height + STACK_GAP
        end
    end
end

local function dismiss(id)
    for i, entry in ipairs(activeToasts) do
        if entry.id == id then
            if entry.timer then pcall(task.cancel, entry.timer) end
            if entry.progressTween then pcall(function() entry.progressTween:Cancel() end) end

            local frame = entry.frame
            table.remove(activeToasts, i)

            -- Slide out to the right (off-screen)
            local t = TweenService:Create(frame,
                TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                { Position = UDim2.new(1, SCREEN_PAD, 0, frame.Position.Y.Offset) }
            )
            t:Play()
            t.Completed:Connect(function()
                if frame and frame.Parent then frame:Destroy() end
                restack()
            end)
            return
        end
    end
end

function Toast.show(message, options)
    if not toastsEnabled then return -1 end
    if not toastContainer then
        warn("[Vain:Toast] call Toast.mount() before Toast.show()")
        return -1
    end

    options = options or {}
    local variant  = options.Variant  or "info"
    local duration = options.Duration or T.Duration
    local id       = nextToastId()

    local accentColor = T.Info
    if variant == "success" then accentColor = T.Success
    elseif variant == "warning" then accentColor = T.Warning
    elseif variant == "error"   then accentColor = T.Error
    end

    local PROGRESS_H = 3
    local toastH = T.PaddingY * 2 + T.FontSize + PROGRESS_H + 6

    -- Frame starts off-screen to the right
    local frame = Instance.new("TextButton")
    frame.Size             = UDim2.fromOffset(TOAST_W, toastH)
    frame.Position         = UDim2.new(1, SCREEN_PAD, 0, SCREEN_PAD)
    frame.BackgroundColor3 = T.Background
    frame.BorderSizePixel  = 0
    frame.Text             = ""
    frame.AutoButtonColor  = false
    frame.ZIndex           = 100
    frame.Parent           = toastContainer

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, T.CornerRadius)
    c.Parent = frame

    local s = Instance.new("UIStroke")
    s.Color     = T.Border
    s.Thickness = 1
    s.Parent    = frame

    -- Left accent bar
    local accentBar = Instance.new("Frame")
    accentBar.Size             = UDim2.new(0, 3, 1, -(T.CornerRadius))
    accentBar.Position         = UDim2.fromOffset(0, T.CornerRadius / 2)
    accentBar.BackgroundColor3 = accentColor
    accentBar.BorderSizePixel  = 0
    accentBar.ZIndex = 101
    accentBar.Parent = frame

    local ac = Instance.new("UICorner")
    ac.CornerRadius = UDim.new(1, 0)
    ac.Parent = accentBar

    -- Message
    local label = Instance.new("TextLabel")
    label.Size               = UDim2.new(1, -(T.PaddingX * 2 + 6), 0, T.FontSize + T.PaddingY * 2)
    label.Position           = UDim2.fromOffset(T.PaddingX + 6, 0)
    label.BackgroundTransparency = 1
    label.Text               = message
    label.TextColor3         = T.Text
    label.Font               = Enum.Font.GothamMedium
    label.TextSize           = T.FontSize
    label.TextXAlignment     = Enum.TextXAlignment.Left
    label.TextWrapped        = true
    label.ZIndex = 101
    label.Parent = frame

    -- Progress bar track
    local progressTrack = Instance.new("Frame")
    progressTrack.Size             = UDim2.new(1, 0, 0, PROGRESS_H)
    progressTrack.Position         = UDim2.new(0, 0, 1, -PROGRESS_H)
    progressTrack.BackgroundColor3 = Theme.Surface3
    progressTrack.BorderSizePixel  = 0
    progressTrack.ZIndex = 101
    progressTrack.Parent = frame

    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(1, 0)
    pc.Parent = progressTrack

    local progressFill = Instance.new("Frame")
    progressFill.Size             = UDim2.fromScale(1, 1)
    progressFill.BackgroundColor3 = accentColor
    progressFill.BorderSizePixel  = 0
    progressFill.ZIndex = 102
    progressFill.Parent = progressTrack

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(1, 0)
    fc.Parent = progressFill

    local entry = { id = id, frame = frame, height = toastH, timer = nil, progressTween = nil }
    table.insert(activeToasts, entry)
    restack()   -- sets final position

    -- Slide in from right (after restack sets target position)
    task.defer(function()
        if not (frame and frame.Parent) then return end
        -- restack already set the target; slide in from the right side
        local targetY = frame.Position.Y.Offset
        frame.Position = UDim2.new(1, SCREEN_PAD, 0, targetY)
        TweenService:Create(frame,
            TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Position = UDim2.new(1, -(TOAST_W + SCREEN_PAD), 0, targetY) }
        ):Play()
    end)

    frame.MouseButton1Click:Connect(function()
        dismiss(id)
    end)

    if duration ~= math.huge then
        local progTween = TweenService:Create(progressFill,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { Size = UDim2.fromScale(0, 1) }
        )
        progTween:Play()
        entry.progressTween = progTween
        entry.timer = task.delay(duration, function() dismiss(id) end)
    else
        progressTrack.Visible = false
    end

    return id
end

function Toast.dismiss(id)
    dismiss(id)
end

function Toast.mount(playerGui)
    local gui = Instance.new("ScreenGui")
    gui.Name           = "VainToasts"
    gui.ResetOnSpawn   = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder   = 200
    gui.Parent         = playerGui

    toastContainer = Instance.new("Frame")
    toastContainer.Size                   = UDim2.fromScale(1, 1)
    toastContainer.BackgroundTransparency = 1
    toastContainer.ClipsDescendants       = false
    toastContainer.Parent                 = gui
end

return Toast
