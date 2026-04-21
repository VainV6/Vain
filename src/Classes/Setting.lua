--[[
    Classes/Setting.lua  –  Pure-data class for a single module setting.

    This class is intentionally decoupled from the UI layer; Components.lua
    reads the data here and calls :Set() / :OnChanged() to stay in sync.

    Supported types:  "Slider" | "Toggle" | "Input" | "List"

    API:
        Setting.new(type, config)  →  Setting
        setting:Set(value)         –  validate, store, fire listeners + callback
        setting:OnChanged(fn)      →  disconnect()   (returns cleanup fn)
--]]

local Setting = {}
Setting.__index = Setting

-- ── Constructor ──────────────────────────────────────────────────────────────

function Setting.new(settingType, config)
    assert(type(config.Name) == "string" and config.Name ~= "",
        "[Vain:Setting] 'Name' is required")

    local self      = setmetatable({}, Setting)
    self.Type       = settingType
    self.Name       = config.Name
    self.Callback   = config.Callback or function() end
    self._listeners = {}

    if settingType == "Slider" then
        self.Min    = config.Min    or 0
        self.Max    = config.Max    or 100
        self.Step   = config.Step   or 1
        self.Suffix = config.Suffix or ""
        self.Value  = math.clamp(config.Default or self.Min, self.Min, self.Max)

    elseif settingType == "Toggle" then
        self.Value  = config.Default == true

    elseif settingType == "Input" then
        self.Value       = config.Default   or ""
        self.Placeholder = config.Placeholder or "Enter value..."
        self.IsKeybind   = config.IsKeybind == true
        self.MaxLength   = config.MaxLength or 64

    elseif settingType == "List" then
        assert(type(config.Options) == "table" and #config.Options > 0,
            "[Vain:Setting] List '" .. config.Name .. "' requires Options = {...}")
        self.Options = config.Options
        self.Value   = config.Default or config.Options[1]

    else
        error("[Vain:Setting] Unknown type '" .. tostring(settingType) .. "'")
    end

    return self
end

-- ── Public API ───────────────────────────────────────────────────────────────

function Setting:Set(value)
    -- Type-specific validation and snapping
    if self.Type == "Slider" then
        value = math.clamp(value, self.Min, self.Max)
        if self.Step and self.Step > 0 then
            value = math.floor(value / self.Step + 0.5) * self.Step
            -- Re-clamp after snap to avoid floating-point overshoot
            value = math.clamp(value, self.Min, self.Max)
        end

    elseif self.Type == "Toggle" then
        value = value == true

    elseif self.Type == "Input" then
        value = tostring(value):sub(1, self.MaxLength)

    elseif self.Type == "List" then
        local valid = false
        for _, opt in ipairs(self.Options) do
            if opt == value then valid = true; break end
        end
        if not valid then return end
    end

    self.Value = value
    self.Callback(value)

    for _, fn in ipairs(self._listeners) do
        fn(value)
    end
end

-- Register a change listener; returns a cleanup function
function Setting:OnChanged(fn)
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

return Setting
