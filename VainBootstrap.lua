--[[
    VainBootstrap.lua  –  Executor-compatible entry point for Vain.

    Usage (paste into executor):
        loadstring(game:HttpGet("https://raw.githubusercontent.com/VainV6/Vain/main/VainBootstrap.lua"))()
--]]

local RAW = "https://raw.githubusercontent.com/VainV6/Vain/main/src/"

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer

-- ── HTTP helper ────────────────────────────────────────────────────────────────
local function fetch(url)
    return game:HttpGet(url, true)
end

-- ── Fake-instance path resolver ────────────────────────────────────────────────
local function inst(path)
    return setmetatable({ _p = path }, {
        __index = function(t, key)
            if key == "Parent" then
                return inst(t._p:match("^(.+)/[^/]*$") or "")
            end
            local child = (t._p == "") and key or (t._p .. "/" .. key)
            return inst(child)
        end,
    })
end

-- ── Module registry + loader ────────────────────────────────────────────────────
local cache  = {}
local loadMod

local function customRequire(obj)
    if type(obj) == "table" and type(obj._p) == "string" then
        return loadMod(obj._p)
    end
    return require(obj)
end

loadMod = function(path)
    if cache[path] ~= nil then return cache[path] end
    cache[path] = false

    local ok, body = pcall(fetch, RAW .. path .. ".lua")
    assert(ok, ("[Vain] HTTP fetch failed for '%s': %s"):format(path, tostring(body)))

    local fn, err = loadstring(body, "@Vain/" .. path)
    assert(fn, ("[Vain] Parse error in '%s': %s"):format(path, tostring(err)))

    local env = setmetatable({ script = inst(path), require = customRequire }, { __index = getfenv(0) })
    setfenv(fn, env)

    local result = fn()
    cache[path]  = result
    return result
end

-- ── Shared state ────────────────────────────────────────────────────────────────
local State = {
    AimAssist = { Enabled = false, Reach = 20,  Angle = 90, Speed = 0.15 },
    MetalESP  = { Enabled = false, Highlight = true, Beams = false, Distance = true,
                  MaxDistance = 500, AutoCollect = false, CollectRadius = 10,
                  Color = Color3.fromRGB(200, 200, 200) },
    StarESP   = { Enabled = false, Highlight = true, Beams = false, Distance = true, MaxDistance = 500 },
    BeeESP    = { Enabled = false, Highlight = true, Beams = false, Distance = true, MaxDistance = 500 },
    TreeESP   = { Enabled = false, Highlight = true, Beams = false, Distance = true, MaxDistance = 500 },
}

-- ── ESP infrastructure ─────────────────────────────────────────────────────────
local ESPObjects     = {}
local ESPConnections = {}

local function clearESP(tag)
    if ESPObjects[tag] then
        for _, obj in ipairs(ESPObjects[tag]) do pcall(function() obj:Destroy() end) end
        ESPObjects[tag] = nil
    end
    if ESPConnections[tag] then
        for _, c in ipairs(ESPConnections[tag]) do pcall(function() c:Disconnect() end) end
        ESPConnections[tag] = nil
    end
end

local function addESPObj(tag, obj)  ESPObjects[tag] = ESPObjects[tag] or {};     table.insert(ESPObjects[tag], obj) end
local function addESPConn(tag, c)   ESPConnections[tag] = ESPConnections[tag] or {}; table.insert(ESPConnections[tag], c) end

local function getRoot(obj)
    if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart") end
    return obj
end

local function distTo(part)
    local char = LocalPlayer.Character
    if not char then return math.huge end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root or not part then return math.huge end
    return (root.Position - part.Position).Magnitude
end

local function makeHighlight(adornee, color)
    local hi = Instance.new("Highlight")
    hi.FillColor            = color
    hi.OutlineColor         = color
    hi.FillTransparency     = 0.65
    hi.OutlineTransparency  = 0
    hi.Adornee              = adornee
    hi.Parent               = adornee
    return hi
end

local function makeBeam(target, color)
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp or not target or not target.Parent then return nil end

    local a0 = Instance.new("Attachment"); a0.Parent = hrp
    local a1 = Instance.new("Attachment"); a1.Parent = target
    local beam         = Instance.new("Beam")
    beam.Attachment0   = a0
    beam.Attachment1   = a1
    beam.Color         = ColorSequence.new(color)
    beam.Width0        = 0.06
    beam.Width1        = 0.06
    beam.FaceCamera    = true
    beam.Transparency  = NumberSequence.new(0.4)
    beam.Parent        = hrp
    return {beam, a0, a1}
end

local function makeBillboard(target, color)
    local bg          = Instance.new("BillboardGui")
    bg.Size           = UDim2.fromOffset(80, 20)
    bg.StudsOffset    = Vector3.new(0, 3, 0)
    bg.AlwaysOnTop    = true
    bg.Adornee        = target
    bg.Parent         = target

    local lbl                       = Instance.new("TextLabel")
    lbl.Size                        = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency      = 1
    lbl.TextColor3                  = color
    lbl.TextStrokeColor3            = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency      = 0
    lbl.Font                        = Enum.Font.GothamBold
    lbl.TextSize                    = 13
    lbl.Parent                      = bg

    local conn = RunService.RenderStepped:Connect(function()
        if not bg.Parent or not target.Parent then return end
        lbl.Text = math.floor(distTo(target)) .. " st"
    end)
    return bg, conn
end

local function enableESP(tag, namePattern, s, color)
    clearESP(tag)

    local function applyToEntity(entity)
        local root = getRoot(entity)
        if not root then return end
        if distTo(root) > s.MaxDistance then return end

        if s.Highlight then
            addESPObj(tag, makeHighlight(entity, color))
        end
        if s.Beams then
            local parts = makeBeam(root, color)
            if parts then for _, p in ipairs(parts) do addESPObj(tag, p) end end
        end
        if s.Distance then
            local bb, conn = makeBillboard(root, color)
            addESPObj(tag, bb)
            addESPConn(tag, conn)
        end
    end

    for _, v in ipairs(Workspace:GetDescendants()) do
        if (v:IsA("BasePart") or v:IsA("Model")) and v.Name:lower():find(namePattern:lower()) then
            applyToEntity(v)
        end
    end

    addESPConn(tag, Workspace.DescendantAdded:Connect(function(v)
        if (v:IsA("BasePart") or v:IsA("Model")) and v.Name:lower():find(namePattern:lower()) then
            task.wait()
            applyToEntity(v)
        end
    end))
end

-- Helper: refresh a running ESP after a settings toggle
local function refreshESP(tag, namePattern, s, color)
    if s.Enabled then
        clearESP(tag)
        enableESP(tag, namePattern, s, color)
    end
end

-- ── AimAssist ──────────────────────────────────────────────────────────────────
local aimConn
local Camera = Workspace.CurrentCamera

local function enableAimAssist()
    if aimConn then aimConn:Disconnect() end
    aimConn = RunService.RenderStepped:Connect(function()
        if not State.AimAssist.Enabled then return end
        if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end

        local char = LocalPlayer.Character
        if not char then return end
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        local best, bestDist = nil, State.AimAssist.Reach

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local tHrp = p.Character:FindFirstChild("HumanoidRootPart")
                local hum  = p.Character:FindFirstChildOfClass("Humanoid")
                if tHrp and hum and hum.Health > 0 then
                    local sp, onScreen = Camera:WorldToScreenPoint(tHrp.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - screenCenter).Magnitude
                        if d < bestDist then bestDist = d; best = tHrp end
                    end
                end
            end
        end

        if best then
            Camera.CFrame = Camera.CFrame:Lerp(
                CFrame.lookAt(Camera.CFrame.Position, best.Position),
                State.AimAssist.Speed)
        end
    end)
end

local function disableAimAssist()
    if aimConn then aimConn:Disconnect(); aimConn = nil end
end

-- ── Boot sequence ──────────────────────────────────────────────────────────────
local LoadingScreen = loadMod("UI/LoadingScreen")
local VainFramework = loadMod("VainFramework")

LoadingScreen:Show(function()

    local Vain = VainFramework.new({
        Title     = "Vain",
        Subtitle  = "hub",
        ToggleKey = Enum.KeyCode.RightControl,
    })

    -- ── Combat ─────────────────────────────────────────────────────────────────
    local Combat = Vain:NewCategory("Combat", "rbxassetid://6031090990")

    local AimAssist = Combat:AddModule({
        Name      = "AimAssist",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.Q,
        OnEnable  = function() State.AimAssist.Enabled = true;  enableAimAssist()  end,
        OnDisable = function() State.AimAssist.Enabled = false; disableAimAssist() end,
    })
    AimAssist:AddSetting("Slider", { Name = "Reach",  Min = 5,  Max = 400, Default = 20,  Suffix = " px",
        Callback = function(v) State.AimAssist.Reach = v end })
    AimAssist:AddSetting("Slider", { Name = "Angle",  Min = 10, Max = 360, Default = 90,  Suffix = "°",
        Callback = function(v) State.AimAssist.Angle = v end })
    AimAssist:AddSetting("Slider", { Name = "Speed",  Min = 1,  Max = 100, Default = 15,  Suffix = "%",
        Callback = function(v) State.AimAssist.Speed = v / 100 end })

    -- ── Visuals ────────────────────────────────────────────────────────────────
    local Visuals = Vain:NewCategory("Visuals", "rbxassetid://6031096740")

    -- MetalESP ─────────────────────────────────────────────────────────────────
    local MetalESP = Visuals:AddModule({
        Name      = "MetalESP",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.M,
        OnEnable  = function() State.MetalESP.Enabled = true;  enableESP("MetalESP", "Metal",     State.MetalESP, State.MetalESP.Color)    end,
        OnDisable = function() State.MetalESP.Enabled = false; clearESP("MetalESP") end,
    })
    MetalESP:AddSetting("Toggle",      { Name = "Highlight",      Default = true,
        Callback = function(v) State.MetalESP.Highlight = v;    refreshESP("MetalESP", "Metal", State.MetalESP, State.MetalESP.Color) end })
    MetalESP:AddSetting("Toggle",      { Name = "Beams",          Default = false,
        Callback = function(v) State.MetalESP.Beams = v;        refreshESP("MetalESP", "Metal", State.MetalESP, State.MetalESP.Color) end })
    MetalESP:AddSetting("Toggle",      { Name = "Distance",       Default = true,
        Callback = function(v) State.MetalESP.Distance = v;     refreshESP("MetalESP", "Metal", State.MetalESP, State.MetalESP.Color) end })
    MetalESP:AddSetting("Slider",      { Name = "Max Distance",   Min = 50, Max = 2000, Default = 500, Suffix = " st",
        Callback = function(v) State.MetalESP.MaxDistance = v end })
    MetalESP:AddSetting("Toggle",      { Name = "AutoCollect",    Default = false,
        Callback = function(v) State.MetalESP.AutoCollect = v end })
    MetalESP:AddSetting("Slider",      { Name = "Collect Radius", Min = 5, Max = 50, Default = 10, Suffix = " st",
        Callback = function(v) State.MetalESP.CollectRadius = v end })
    MetalESP:AddSetting("ColorPicker", { Name = "Color",          Default = Color3.fromRGB(200, 200, 200),
        Callback = function(v) State.MetalESP.Color = v;        refreshESP("MetalESP", "Metal", State.MetalESP, v) end })

    -- StarESP ──────────────────────────────────────────────────────────────────
    local STAR_COLOR = Color3.fromRGB(255, 220, 50)
    local StarESP = Visuals:AddModule({
        Name      = "StarESP",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.B,
        OnEnable  = function() State.StarESP.Enabled = true;  enableESP("StarESP", "Star",       State.StarESP,  STAR_COLOR) end,
        OnDisable = function() State.StarESP.Enabled = false; clearESP("StarESP") end,
    })
    StarESP:AddSetting("Toggle", { Name = "Highlight",    Default = true,
        Callback = function(v) State.StarESP.Highlight = v;   refreshESP("StarESP", "Star", State.StarESP, STAR_COLOR) end })
    StarESP:AddSetting("Toggle", { Name = "Beams",        Default = false,
        Callback = function(v) State.StarESP.Beams = v;       refreshESP("StarESP", "Star", State.StarESP, STAR_COLOR) end })
    StarESP:AddSetting("Toggle", { Name = "Distance",     Default = true,
        Callback = function(v) State.StarESP.Distance = v;    refreshESP("StarESP", "Star", State.StarESP, STAR_COLOR) end })
    StarESP:AddSetting("Slider", { Name = "Max Distance", Min = 50, Max = 2000, Default = 500, Suffix = " st",
        Callback = function(v) State.StarESP.MaxDistance = v end })

    -- BeeESP ───────────────────────────────────────────────────────────────────
    local BEE_COLOR = Color3.fromRGB(255, 170, 0)
    local BeeESP = Visuals:AddModule({
        Name      = "BeeESP",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.N,
        OnEnable  = function() State.BeeESP.Enabled = true;  enableESP("BeeESP", "Bee",         State.BeeESP,   BEE_COLOR) end,
        OnDisable = function() State.BeeESP.Enabled = false; clearESP("BeeESP") end,
    })
    BeeESP:AddSetting("Toggle", { Name = "Highlight",    Default = true,
        Callback = function(v) State.BeeESP.Highlight = v;   refreshESP("BeeESP", "Bee", State.BeeESP, BEE_COLOR) end })
    BeeESP:AddSetting("Toggle", { Name = "Beams",        Default = false,
        Callback = function(v) State.BeeESP.Beams = v;       refreshESP("BeeESP", "Bee", State.BeeESP, BEE_COLOR) end })
    BeeESP:AddSetting("Toggle", { Name = "Distance",     Default = true,
        Callback = function(v) State.BeeESP.Distance = v;    refreshESP("BeeESP", "Bee", State.BeeESP, BEE_COLOR) end })
    BeeESP:AddSetting("Slider", { Name = "Max Distance", Min = 50, Max = 2000, Default = 500, Suffix = " st",
        Callback = function(v) State.BeeESP.MaxDistance = v end })

    -- EldertreeESP ─────────────────────────────────────────────────────────────
    local TREE_COLOR = Color3.fromRGB(80, 200, 80)
    local TreeESP = Visuals:AddModule({
        Name      = "EldertreeESP",
        Behavior  = "Toggleable",
        Keybind   = Enum.KeyCode.O,
        OnEnable  = function() State.TreeESP.Enabled = true;  enableESP("TreeESP", "Eldertree",  State.TreeESP,  TREE_COLOR) end,
        OnDisable = function() State.TreeESP.Enabled = false; clearESP("TreeESP") end,
    })
    TreeESP:AddSetting("Toggle", { Name = "Highlight",    Default = true,
        Callback = function(v) State.TreeESP.Highlight = v;   refreshESP("TreeESP", "Eldertree", State.TreeESP, TREE_COLOR) end })
    TreeESP:AddSetting("Toggle", { Name = "Beams",        Default = false,
        Callback = function(v) State.TreeESP.Beams = v;       refreshESP("TreeESP", "Eldertree", State.TreeESP, TREE_COLOR) end })
    TreeESP:AddSetting("Toggle", { Name = "Distance",     Default = true,
        Callback = function(v) State.TreeESP.Distance = v;    refreshESP("TreeESP", "Eldertree", State.TreeESP, TREE_COLOR) end })
    TreeESP:AddSetting("Slider", { Name = "Max Distance", Min = 50, Max = 2000, Default = 500, Suffix = " st",
        Callback = function(v) State.TreeESP.MaxDistance = v end })

    -- ── Settings ────────────────────────────────────────────────────────────────
    local Settings = Vain:NewCategory("Settings", "rbxassetid://6031280882")

    local UITheme = Settings:AddModule({
        Name     = "UI Theme",
        Behavior = "Toggleable",
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    UITheme:AddSetting("ColorPicker", {
        Name = "Accent Color", Default = Color3.fromRGB(0, 120, 255),
        Callback = function(v) loadMod("Theme").Accent = v end,
    })

    local MenuKey = Settings:AddModule({
        Name     = "Menu Keybind",
        Behavior = "Toggleable",
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    MenuKey:AddSetting("Input", {
        Name = "Toggle Key", Default = "RightControl", IsKeybind = true,
        Callback = function(v)
            local kc = Enum.KeyCode[v]
            if kc then Vain:SetToggleKey(kc) end
        end,
    })

    local Notifs = Settings:AddModule({
        Name     = "Notifications",
        Behavior = "Toggleable",
        OnEnable  = function() end,
        OnDisable = function() end,
    })
    Notifs:AddSetting("Toggle", { Name = "Enabled", Default = true, Callback = function() end })

    Settings:AddModule({
        Name     = "FPS Counter",
        Behavior = "Toggleable",
        OnEnable  = function() Vain:SetFPSVisible(true)  end,
        OnDisable = function() Vain:SetFPSVisible(false) end,
    })

    Settings:AddModule({
        Name      = "Uninject",
        Behavior  = "Executable",
        OnExecute = function()
            for tag in pairs(ESPObjects) do clearESP(tag) end
            disableAimAssist()
            Vain:Destroy()
        end,
    })

    Vain:Show()
end)
