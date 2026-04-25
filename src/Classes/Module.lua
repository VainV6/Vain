--[[
    Classes/Module.lua  –  OOP base class for all Vain hub modules.

    Behavior modes
        "Toggleable"  Has an Enabled/Disabled state (KillAura, Bhop, ESP…)
        "Executable"  Fires once per trigger, no persistent state (Jump, TP…)

    API:
        Module.new(config)           →  Module
        module:AddSetting(type, cfg) →  Setting   (chains on module)
        module:Trigger()             –  toggle or execute depending on Behavior
        module:SetEnabled(bool)      –  force-set state (Toggleable only)
        module:GetSetting(name)      →  Setting | nil
        module:OnStateChange(fn)     →  disconnect()
--]]

local Setting = require(script.Parent.Setting)

local Module  = {}
Module.__index = Module

-- ── Constructor ──────────────────────────────────────────────────────────────

function Module.new(config)
    assert(type(config.Name) == "string" and config.Name ~= "",
        "[Vain:Module] 'Name' is required")
    assert(
        config.Behavior == nil
        or config.Behavior == "Toggleable"
        or config.Behavior == "Executable",
        "[Vain:Module] Behavior must be 'Toggleable' or 'Executable'"
    )

    local self          = setmetatable({}, Module)
    self.Name           = config.Name
    self.Description    = config.Description or ""
    self.Category       = config.Category    or "Misc"
    self.Behavior       = config.Behavior    or "Toggleable"
    self.Keybind        = config.Keybind     -- Enum.KeyCode or nil
    self.Enabled        = false
    self.Settings       = {}
    self._listeners     = {}

    -- Lifecycle callbacks (all optional)
    self._onEnable      = config.OnEnable  or function() end
    self._onDisable     = config.OnDisable or function() end
    self._onExecute     = config.OnExecute or function() end

    -- Honour DefaultEnabled so modules can start in the ON state
    if config.DefaultEnabled == true then
        self.Enabled = true
        self._onEnable()
    end

    return self
end

-- ── Settings API ─────────────────────────────────────────────────────────────

-- Adds a typed setting and returns it (allows chaining / direct reference)
function Module:AddSetting(settingType, config)
    local s = Setting.new(settingType, config)
    table.insert(self.Settings, s)
    return s
end

function Module:GetSetting(name)
    for _, s in ipairs(self.Settings) do
        if s.Name == name then return s end
    end
    return nil
end

-- ── State API ────────────────────────────────────────────────────────────────

function Module:Trigger()
    if self.Behavior == "Toggleable" then
        self:SetEnabled(not self.Enabled)
    else
        self._onExecute()
        self:_fire(nil)   -- nil signals "executed" to UI listeners
    end
end

function Module:SetEnabled(state)
    if self.Behavior ~= "Toggleable" then return end
    if self.Enabled == state then return end
    self.Enabled = state
    if state then
        self._onEnable()
    else
        self._onDisable()
    end
    self:_fire(state)
end

-- Register a UI state listener; returns cleanup fn
function Module:OnStateChange(fn)
    table.insert(self._listeners, fn)
    return function()
        for i = #self._listeners, 1, -1 do
            if self._listeners[i] == fn then
                table.remove(self._listeners, i)
                break
            end
        end
    end
end

-- ── Private ──────────────────────────────────────────────────────────────────

function Module:_fire(state)
    for _, fn in ipairs(self._listeners) do
        fn(state)
    end
end

return Module
