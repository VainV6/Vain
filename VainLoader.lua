--[[
    VainLoader.lua  –  Entry point LocalScript for the Vain hub.

    ── Roblox placement ─────────────────────────────────────────────────────────
    Place this script as a LocalScript under StarterPlayerScripts (or run it
    from an executor).  All ModuleScripts live inside a Folder called
    "VainModules" that must be a direct child of this script:

        LocalScript  VainLoader
        └── Folder   VainModules
            ├── ModuleScript   Theme
            ├── ModuleScript   Registry
            ├── ModuleScript   InputHandler
            ├── ModuleScript   VainFramework
            ├── Folder         Classes
            │   ├── ModuleScript   Module
            │   └── ModuleScript   Setting
            └── Folder         UI
                ├── ModuleScript   Window
                ├── ModuleScript   Components
                └── ModuleScript   LoadingScreen

    ── Keys ─────────────────────────────────────────────────────────────────────
        RightControl  –  toggle the hub window open / closed
        K             –  toggle KillAura
        R             –  toggle Reach
        B             –  toggle Bhop
        L             –  execute SuperJump
        E             –  toggle ESP
--]]

local Modules       = script:WaitForChild("VainModules")
local LoadingScreen = require(Modules.UI.LoadingScreen)
local VainFramework = require(Modules.VainFramework)

-- ── Loading animation → then initialise ──────────────────────────────────────

LoadingScreen:Show(function()

    local Vain = VainFramework.new({
        Title       = "Vain",
        Subtitle    = "hub",
        AccentColor = Color3.fromRGB(120, 87, 255),
        ToggleKey   = Enum.KeyCode.RightControl,
    })

    -- ── Combat ────────────────────────────────────────────────────────────────
    local Combat = Vain:NewCategory("Combat", "rbxassetid://6031090990")

    local KillAura = Combat:AddModule({
        Name        = "KillAura",
        Description = "Automatically attacks nearby players",
        Behavior    = "Toggleable",
        Keybind     = Enum.KeyCode.K,
        OnEnable    = function()
            -- TODO: connect your KillAura RunService loop here
            print("[KillAura] Enabled")
        end,
        OnDisable   = function()
            -- TODO: disconnect loop here
            print("[KillAura] Disabled")
        end,
    })
    KillAura:AddSetting("Slider", {
        Name     = "Range",
        Min      = 0,
        Max      = 100,
        Default  = 10,
        Suffix   = " st",
        Callback = function(val) print("[KillAura] Range →", val) end,
    })
    KillAura:AddSetting("Toggle", {
        Name     = "Through Walls",
        Default  = false,
        Callback = function(val) print("[KillAura] Through Walls →", val) end,
    })
    KillAura:AddSetting("List", {
        Name     = "Target Priority",
        Options  = { "Closest", "Lowest HP", "Highest HP", "Random" },
        Default  = "Closest",
        Callback = function(val) print("[KillAura] Priority →", val) end,
    })
    KillAura:AddSetting("Slider", {
        Name     = "Hit Delay",
        Min      = 0,
        Max      = 500,
        Default  = 100,
        Suffix   = " ms",
        Callback = function(val) print("[KillAura] Hit Delay →", val) end,
    })

    local Reach = Combat:AddModule({
        Name        = "Reach",
        Description = "Extend your melee hit distance",
        Behavior    = "Toggleable",
        Keybind     = Enum.KeyCode.R,
        OnEnable    = function() print("[Reach] Enabled") end,
        OnDisable   = function() print("[Reach] Disabled") end,
    })
    Reach:AddSetting("Slider", {
        Name     = "Distance",
        Min      = 5,
        Max      = 60,
        Default  = 12,
        Suffix   = " st",
        Callback = function(val) print("[Reach] Distance →", val) end,
    })

    -- ── Movement ──────────────────────────────────────────────────────────────
    local Movement = Vain:NewCategory("Movement", "rbxassetid://6031225819")

    local Bhop = Movement:AddModule({
        Name        = "Bhop",
        Description = "Auto-jump for bunny-hop movement",
        Behavior    = "Toggleable",
        Keybind     = Enum.KeyCode.B,
        OnEnable    = function() print("[Bhop] Enabled") end,
        OnDisable   = function() print("[Bhop] Disabled") end,
    })
    Bhop:AddSetting("Slider", {
        Name     = "Speed Multiplier",
        Min      = 1,
        Max      = 5,
        Default  = 2,
        Step     = 0.1,
        Callback = function(val) print("[Bhop] Speed →", val) end,
    })
    Bhop:AddSetting("Toggle", {
        Name     = "Auto-Strafe",
        Default  = true,
        Callback = function(val) print("[Bhop] Auto-Strafe →", val) end,
    })

    local SuperJump = Movement:AddModule({
        Name        = "SuperJump",
        Description = "Executes a single powerful jump",
        Behavior    = "Executable",
        Keybind     = Enum.KeyCode.L,
        OnExecute   = function()
            local char = game.Players.LocalPlayer.Character
            if not char then return end
            local hrp  = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            -- Replace with the actual force value from the setting at runtime
            hrp.AssemblyLinearVelocity = Vector3.new(
                hrp.AssemblyLinearVelocity.X,
                150,
                hrp.AssemblyLinearVelocity.Z
            )
        end,
    })
    SuperJump:AddSetting("Slider", {
        Name     = "Force",
        Min      = 50,
        Max      = 500,
        Default  = 150,
        Suffix   = " N",
        Callback = function(val) print("[SuperJump] Force →", val) end,
    })

    -- ── Visuals ───────────────────────────────────────────────────────────────
    local Visuals = Vain:NewCategory("Visuals", "rbxassetid://6031096740")

    local ESP = Visuals:AddModule({
        Name        = "ESP",
        Description = "Highlight players through walls",
        Behavior    = "Toggleable",
        Keybind     = Enum.KeyCode.E,
        OnEnable    = function() print("[ESP] Enabled") end,
        OnDisable   = function() print("[ESP] Disabled") end,
    })
    ESP:AddSetting("Toggle", {
        Name     = "Show Names",
        Default  = true,
        Callback = function(val) print("[ESP] Names →", val) end,
    })
    ESP:AddSetting("Toggle", {
        Name     = "Show Health",
        Default  = true,
        Callback = function(val) print("[ESP] Health →", val) end,
    })
    ESP:AddSetting("List", {
        Name     = "Box Style",
        Options  = { "Corner Box", "Full Box", "None" },
        Default  = "Corner Box",
        Callback = function(val) print("[ESP] Box Style →", val) end,
    })
    ESP:AddSetting("Slider", {
        Name     = "Max Distance",
        Min      = 50,
        Max      = 2000,
        Default  = 500,
        Suffix   = " st",
        Callback = function(val) print("[ESP] Max Dist →", val) end,
    })

    -- ── Misc ──────────────────────────────────────────────────────────────────
    local Misc = Vain:NewCategory("Misc", "rbxassetid://6031234656")

    local Notifications = Misc:AddModule({
        Name        = "Notifications",
        Description = "In-hub kill and event toasts",
        Behavior    = "Toggleable",
        OnEnable    = function() print("[Notifs] Enabled") end,
        OnDisable   = function() print("[Notifs] Disabled") end,
    })
    Notifications:AddSetting("Toggle", {
        Name     = "Kill Feed",
        Default  = true,
        Callback = function(val) print("[Notifs] Kill Feed →", val) end,
    })

    local ChatPrefix = Misc:AddModule({
        Name        = "Chat Commands",
        Description = "Use a prefix to run commands in chat",
        Behavior    = "Toggleable",
        OnEnable    = function() print("[ChatPrefix] Enabled") end,
        OnDisable   = function() print("[ChatPrefix] Disabled") end,
    })
    ChatPrefix:AddSetting("Input", {
        Name        = "Prefix Character",
        Default     = "!",
        Placeholder = "e.g.  !",
        Callback    = function(val) print("[ChatPrefix] Prefix →", val) end,
    })
    ChatPrefix:AddSetting("Input", {
        Name       = "Fly Keybind",
        Default    = "",
        IsKeybind  = true,
        Callback   = function(val) print("[ChatPrefix] Fly key →", val) end,
    })

    -- ── Open the hub ─────────────────────────────────────────────────────────
    Vain:Show()

end)
