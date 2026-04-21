--[[
    VainFramework.lua  –  Top-level Library class for the Vain hub.

    Wires together Registry, InputHandler, and Window into a single clean API
    that module authors interact with.

    Usage:
        local Vain = require(path.VainFramework)

        local hub = Vain.new({
            Title       = "Vain",
            Subtitle    = "hub",
            AccentColor = Color3.fromRGB(120, 87, 255),
            ToggleKey   = Enum.KeyCode.RightControl,
        })

        local Combat = hub:NewCategory("Combat", iconId)

        local KillAura = Combat:AddModule({
            Name      = "KillAura",
            Behavior  = "Toggleable",
            Keybind   = Enum.KeyCode.K,
            OnEnable  = function() ... end,
            OnDisable = function() ... end,
        })

        KillAura:AddSetting("Slider", {
            Name = "Range", Min = 0, Max = 100, Default = 10,
            Callback = function(val) ... end,
        })

        hub:Show()   -- populates UI and opens the window

    API:
        Vain.new(config)                →  hub
        hub:NewCategory(name, iconId)   →  categoryProxy
        categoryProxy:AddModule(config) →  Module
        hub:Show() / :Hide() / :Toggle()
        hub:GetModule(name)             →  Module | nil
        hub:Destroy()
--]]

local Registry     = require(script.Parent.Registry)
local InputHandler = require(script.Parent.InputHandler)
local Window       = require(script.Parent.UI.Window)
local Module       = require(script.Parent.Classes.Module)
local Theme        = require(script.Parent.Theme)

local VainFramework  = {}
VainFramework.__index = VainFramework

-- ── Constructor ──────────────────────────────────────────────────────────────

function VainFramework.new(config)
    config = config or {}

    -- Apply accent override to the shared Theme table so all components pick it up
    if config.AccentColor then
        Theme.Accent = config.AccentColor
    end

    local self        = setmetatable({}, VainFramework)
    self._config      = config
    self._registry    = Registry.new()
    self._input       = InputHandler.new(self._registry)
    self._window      = Window.new(config, self._registry)
    self._populated   = false

    -- Wire global UI toggle
    if config.ToggleKey then
        self._input:SetUIToggleKey(config.ToggleKey)
    end
    self._input:SetUIToggleFn(function()
        self._window:Toggle()
    end)

    self._input:Start()

    return self
end

-- ── Category / Module API ────────────────────────────────────────────────────

--[[
    Returns a lightweight proxy that exposes AddModule() scoped to this category.
    The proxy keeps a closure over the registry so callers never touch it directly.
--]]
function VainFramework:NewCategory(name, iconId)
    self._registry:AddCategory(name, iconId)

    local registry  = self._registry  -- closure capture
    local proxy     = {}

    function proxy:AddModule(config)
        local mod = Module.new(config)
        registry:Register(name, mod)
        return mod
    end

    return proxy
end

-- ── Visibility ────────────────────────────────────────────────────────────────

-- Populates the UI from the registry on the first call, then opens the window.
function VainFramework:Show()
    if not self._populated then
        self._window:PopulateFromRegistry()
        self._populated = true
    end
    self._window:Show()
end

function VainFramework:Hide()
    self._window:Hide()
end

function VainFramework:Toggle()
    if not self._populated then
        self._window:PopulateFromRegistry()
        self._populated = true
    end
    self._window:Toggle()
end

-- ── Utilities ────────────────────────────────────────────────────────────────

function VainFramework:GetModule(name)
    return self._registry:GetModule(name)
end

-- Re-registers a custom keybind not tied to any module (e.g. panic key)
function VainFramework:BindKey(keyCode, fn)
    self._input:BindKey(keyCode, fn)
end

function VainFramework:Destroy()
    self._input:Stop()
    if self._window._gui then
        self._window._gui:Destroy()
    end
end

return VainFramework
