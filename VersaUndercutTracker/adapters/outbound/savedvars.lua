-- VUT - settings persistence. Account-wide SavedVariables
-- (settings only - baselines, cooldown stamps and verdicts are session state
-- by design). The blob is untrusted: load() runs it through Config.coerce;
-- save() writes back a fresh, coerced shape.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local Config = V.domain.Config

---@class SavedVarsAdapter : PersistencePort
---@field db table the anchored SavedVariables global
local Store = {}
Store.__index = Store

--- The SavedVariables global only exists after ADDON_LOADED; the bootstrap
--- anchors it (VUTDB = VUTDB or {}) and
--- hands the table in.
---@param db table
---@return SavedVarsAdapter
function Store.new(db)
    return setmetatable({ db = db }, Store)
end

---@return Settings
function Store:load()
    self.db.schemaVersion = 1
    return Config.coerce(self.db.settings)
end

---@param settings Settings
function Store:save(settings)
    self.db.settings = Config.coerce(settings)
end

V.adapters.SavedVarsAdapter = Store
return Store
