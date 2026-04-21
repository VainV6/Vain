--[[
    VainBootstrap.lua  –  Executor-compatible entry point for Vain.

    Fetches every module directly from GitHub raw and boots the framework
    without needing any Roblox Instance hierarchy (no script.Parent chains).

    Usage (paste into executor):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/VainV6/Vain/main/VainBootstrap.lua"))()
--]]

local RAW = "https://raw.githubusercontent.com/VainV6/Vain/main/src/"

-- ── HTTP helper (works across most executors) ─────────────────────────────────
local function fetch(url)
    return game:HttpGet(url, true)
end

-- ── Fake-instance path resolver ───────────────────────────────────────────────
-- Modules call require(script.Parent.Sibling) or require(script.Parent.Parent.X).
-- We model the script hierarchy as a table that chains path segments, so those
-- calls resolve to the right "src/..." path string.

local function inst(path)
    return setmetatable({ _p = path }, {
        __index = function(t, key)
            if key == "Parent" then
                -- strip last path segment  (e.g. "UI/Components" → "UI", "UI" → "")
                return inst(t._p:match("^(.+)/[^/]*$") or "")
            end
            -- descend into a child  (e.g. inst("") + "Theme" → inst("Theme"))
            local child = (t._p == "") and key or (t._p .. "/" .. key)
            return inst(child)
        end,
    })
end

-- ── Module registry + loader ──────────────────────────────────────────────────

local cache = {}

local loadMod   -- forward-declared so customRequire can reference it

local function customRequire(obj)
    -- Our fake instances carry a ._p field; everything else goes to real require
    if type(obj) == "table" and rawget(getmetatable(obj) or {}, "__index") ~= nil
    and type(obj._p) == "string" then
        return loadMod(obj._p)
    end
    return require(obj)
end

loadMod = function(path)
    if cache[path] ~= nil then return cache[path] end

    -- Sentinel prevents infinite loops on circular requires
    cache[path] = false

    local ok, body = pcall(fetch, RAW .. path .. ".lua")
    assert(ok, ("[Vain] HTTP fetch failed for '%s': %s"):format(path, tostring(body)))

    local fn, err = loadstring(body, "@Vain/" .. path)
    assert(fn, ("[Vain] Parse error in '%s': %s"):format(path, tostring(err)))

    -- Each module gets its own env where script and require are intercepted
    local env = setmetatable({
        script  = inst(path),
        require = customRequire,
    }, { __index = getfenv(0) })

    setfenv(fn, env)

    local result = fn()
    cache[path]  = result
    return result
end

-- ── Boot sequence ─────────────────────────────────────────────────────────────

local LoadingScreen = loadMod("UI/LoadingScreen")
local VainFramework = loadMod("VainFramework")

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
        Name      = "KillAura",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.K,
        OnEnable  = function() print("[KillAura] on")  end,
        OnDisable = function() print("[KillAura] off") end,
    })
    KillAura:AddSetting("Slider", { Name = "Range",           Min = 0,  Max = 100, Default = 10,  Suffix = " st", Callback = function(v) end })
    KillAura:AddSetting("Toggle", { Name = "Through Walls",   Default = false,                                    Callback = function(v) end })
    KillAura:AddSetting("List",   { Name = "Target Priority", Options = {"Closest","Lowest HP","Random"}, Default = "Closest", Callback = function(v) end })
    KillAura:AddSetting("Slider", { Name = "Hit Delay",       Min = 0,  Max = 500, Default = 100, Suffix = " ms", Callback = function(v) end })

    local Reach = Combat:AddModule({
        Name      = "Reach",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.R,
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    Reach:AddSetting("Slider", { Name = "Distance", Min = 5, Max = 60, Default = 12, Suffix = " st", Callback = function(v) end })

    -- ── Movement ──────────────────────────────────────────────────────────────
    local Movement = Vain:NewCategory("Movement", "rbxassetid://6031225819")

    local Bhop = Movement:AddModule({
        Name      = "Bhop",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.B,
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    Bhop:AddSetting("Slider", { Name = "Speed Multiplier", Min = 1, Max = 5,   Default = 2,   Step = 0.1, Callback = function(v) end })
    Bhop:AddSetting("Toggle", { Name = "Auto-Strafe",       Default = true,                               Callback = function(v) end })

    local SuperJump = Movement:AddModule({
        Name      = "SuperJump",
        Behavior  = "Executable",
        Keybind   = Enum.KeyCode.L,
        OnExecute = function()
            local char = game.Players.LocalPlayer.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    hrp.AssemblyLinearVelocity.X, 150,
                    hrp.AssemblyLinearVelocity.Z)
            end
        end,
    })
    SuperJump:AddSetting("Slider", { Name = "Force", Min = 50, Max = 500, Default = 150, Suffix = " N", Callback = function(v) end })

    -- ── Visuals ───────────────────────────────────────────────────────────────
    local Visuals = Vain:NewCategory("Visuals", "rbxassetid://6031096740")

    local ESP = Visuals:AddModule({
        Name      = "ESP",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.E,
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    ESP:AddSetting("Toggle", { Name = "Show Names",   Default = true,                                       Callback = function(v) end })
    ESP:AddSetting("Toggle", { Name = "Show Health",  Default = true,                                       Callback = function(v) end })
    ESP:AddSetting("List",   { Name = "Box Style",    Options = {"Corner Box","Full Box","None"}, Default = "Corner Box", Callback = function(v) end })
    ESP:AddSetting("Slider", { Name = "Max Distance", Min = 50, Max = 2000, Default = 500, Suffix = " st", Callback = function(v) end })

    -- ── Misc ──────────────────────────────────────────────────────────────────
    local Misc = Vain:NewCategory("Misc", "rbxassetid://6031234656")

    local Notifications = Misc:AddModule({
        Name      = "Notifications",
        Behavior  = "Toggleable",
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    Notifications:AddSetting("Toggle", { Name = "Kill Feed", Default = true, Callback = function(v) end })

    local ChatPrefix = Misc:AddModule({
        Name      = "Chat Commands",
        Behavior  = "Toggleable",
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    ChatPrefix:AddSetting("Input", { Name = "Prefix Character", Default = "!", Placeholder = "e.g. !",  Callback = function(v) end })
    ChatPrefix:AddSetting("Input", { Name = "Fly Keybind",      Default = "",  IsKeybind = true,        Callback = function(v) end })

    -- ── Open ──────────────────────────────────────────────────────────────────
    Vain:Show()
end)
