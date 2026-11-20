-- VUT - machine API adapter. Publishes the /run VUT.*
-- surface and owns the setting-application rules (every write goes through
-- Config.coerce on a candidate copy, then mutates the shared settings table
-- in place and persists). The slash adapter and any future GUI drive THIS,
-- never the core directly.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local Config = V.domain.Config

---@class ConsoleAdapter
---@field core table ControlPort implementor
---@field settings Settings the shared live settings table
---@field persist PersistencePort|nil
---@field onSettingsChanged fun()|nil
local Console = {}
Console.__index = Console

---@param deps table {core, settings, persist?, onSettingsChanged?}
---@return ConsoleAdapter
function Console.new(deps)
    return setmetatable({
        core = deps.core,
        settings = deps.settings,
        persist = deps.persist,
        onSettingsChanged = deps.onSettingsChanged,
    }, Console)
end

local function shallowCopy(settings)
    local copy = {}
    for key, value in pairs(settings) do
        if type(value) == "table" then
            local inner = {}
            for k, v in pairs(value) do
                if type(v) == "table" then
                    local inner2 = {}
                    for k2, v2 in pairs(v) do
                        inner2[k2] = v2
                    end
                    inner[k] = inner2
                else
                    inner[k] = v
                end
            end
            copy[key] = inner
        else
            copy[key] = value
        end
    end
    return copy
end

--- Applies one top-level setting. Value may be raw (number/string/boolean).
--- Returns ok plus a readable summary.
---@param key string
---@param value any
---@return boolean ok
---@return string message
function Console:set(key, value)
    local candidate = shallowCopy(self.settings)
    candidate[key] = value
    local coerced = Config.coerce(candidate)
    for k, v in pairs(coerced) do
        self.settings[k] = v
    end
    self:commit()
    return true, ("%s = %s"):format(key, tostring(self.settings[key]))
end

--- Sets one per-kind cooldown.
---@param kind string
---@param seconds number
---@return boolean ok
---@return string message
function Console:setCooldown(kind, seconds)
    if type(self.settings.cooldownSeconds[kind]) ~= "number" then
        return false, "unknown kind: " .. tostring(kind)
    end
    local candidate = shallowCopy(self.settings)
    candidate.cooldownSeconds[kind] = seconds
    local coerced = Config.coerce(candidate)
    self.settings.cooldownSeconds = coerced.cooldownSeconds
    self:commit()
    return true, ("cooldown.%s = %d"):format(kind, self.settings.cooldownSeconds[kind])
end

--- Toggles one channel of one alert kind.
---@param kind string
---@param channel string chat|sound|flash|toast
---@param enabled boolean
---@return boolean ok
---@return string message
function Console:setChannel(kind, channel, enabled)
    if type(self.settings.channels[kind]) ~= "table" then
        return false, "unknown kind: " .. tostring(kind)
    end
    if self.settings.channels[kind][channel] == nil then
        return false, "unknown channel: " .. tostring(channel)
    end
    self.settings.channels[kind][channel] = enabled and true or false
    self:commit()
    return true, ("channel %s.%s = %s"):format(kind, channel, tostring(enabled and true or false))
end

function Console:commit()
    if self.persist then
        self.persist:save(self.settings)
    end
    if self.onSettingsChanged then
        self.onSettingsChanged()
    end
end

function Console:status()
    return self.core:status()
end

function Console:scanNow()
    self.core:scanNow()
    return true, "scan fired"
end

function Console:pause()
    self.core:pause()
    return true, "paused"
end

function Console:resume()
    self.core:resume()
    return true, "resumed"
end

function Console:test(kind)
    if V.domain.Alerts.SEVERITY[kind] == nil then
        return false, "unknown kind: " .. tostring(kind)
    end
    self.core:testAlert(kind)
    return true, "test alert dispatched"
end

--- Re-runs the item refresh-probe on the next item beat.
function Console:probe()
    self.core.itemProbe = { state = "unknown", at = 0, itemID = nil }
    return true, "item probe re-armed (fires on the next item beat)"
end

V.adapters.ConsoleAdapter = Console
return Console
