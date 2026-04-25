--[[
    InputHandler.lua  –  Bridges UserInputService keyboard events to modules
                         and the global UI toggle key.

    API:
        InputHandler.new(registry)
        handler:SetUIToggleKey(Enum.KeyCode)
        handler:SetUIToggleFn(fn)    –  called when toggle key is pressed
        handler:Start()              –  begin listening
        handler:Stop()               –  disconnect listener
        handler:BindKey(keyCode, fn) –  register a one-off custom keybind
--]]

local UserInputService = game:GetService("UserInputService")

local InputHandler  = {}
InputHandler.__index = InputHandler

function InputHandler.new(registry)
    local self           = setmetatable({}, InputHandler)
    self._registry       = registry
    self._connection     = nil
    self._uiToggleFn     = nil
    self._uiToggleKey    = Enum.KeyCode.RightControl
    self._customBinds    = {}   -- { keyCode → fn }
    return self
end

-- ── Configuration ────────────────────────────────────────────────────────────

function InputHandler:SetUIToggleKey(keyCode)
    self._uiToggleKey = keyCode
end

function InputHandler:SetUIToggleFn(fn)
    self._uiToggleFn = fn
end

-- Register a custom keybind independent of modules
function InputHandler:BindKey(keyCode, fn)
    self._customBinds[keyCode] = fn
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

function InputHandler:Start()
    self._connection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        local key = input.KeyCode

        -- 1. Global UI toggle — fires even when chat/gui has focus
        if key == self._uiToggleKey then
            if self._uiToggleFn then self._uiToggleFn() end
            return
        end

        -- Remaining binds respect gameProcessed (don't fire while typing)
        if gameProcessed then return end

        -- 2. Custom binds
        if self._customBinds[key] then
            self._customBinds[key]()
            return
        end

        -- 3. Module keybinds (first match wins)
        for _, mod in ipairs(self._registry:GetAllModules()) do
            if mod.Keybind and mod.Keybind == key then
                mod:Trigger()
                break
            end
        end
    end)
end

function InputHandler:Stop()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

return InputHandler
