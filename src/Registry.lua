--[[
    Registry.lua  –  Central store for all categories and modules.

    Categories are ordered (insertion order preserved).
    Modules are keyed by name for fast lookup.

    API:
        Registry.new()
        registry:AddCategory(name, iconId)  →  category table
        registry:Register(catName, module)
        registry:GetCategories()            →  { {name, icon, modules[]} }
        registry:GetModule(name)            →  Module | nil
        registry:GetAllModules()            →  Module[]
--]]

local Registry  = {}
Registry.__index = Registry

function Registry.new()
    local self         = setmetatable({}, Registry)
    self._categories   = {}   -- ordered list of { name, icon, modules }
    self._categoryMap  = {}   -- name → category table (fast lookup)
    self._moduleMap    = {}   -- moduleName → Module
    return self
end

-- ── Category management ──────────────────────────────────────────────────────

-- Returns existing category if already registered (idempotent)
function Registry:AddCategory(name, iconId)
    if self._categoryMap[name] then
        return self._categoryMap[name]
    end
    local cat = { name = name, icon = iconId or "", modules = {} }
    table.insert(self._categories, cat)
    self._categoryMap[name] = cat
    return cat
end

-- ── Module management ────────────────────────────────────────────────────────

function Registry:Register(categoryName, module)
    local cat = self._categoryMap[categoryName]
    assert(cat, "[Vain:Registry] Unknown category '" .. tostring(categoryName) .. "'")

    -- Prevent duplicate registration
    if self._moduleMap[module.Name] then
        warn("[Vain:Registry] Module '" .. module.Name .. "' already registered — skipping")
        return
    end

    module.Category = categoryName
    table.insert(cat.modules, module)
    self._moduleMap[module.Name] = module
end

-- ── Queries ──────────────────────────────────────────────────────────────────

function Registry:GetCategories()
    return self._categories
end

function Registry:GetModule(name)
    return self._moduleMap[name]
end

function Registry:GetAllModules()
    local all = {}
    for _, cat in ipairs(self._categories) do
        for _, mod in ipairs(cat.modules) do
            table.insert(all, mod)
        end
    end
    return all
end

return Registry
