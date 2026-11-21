-- VUT - alert policy: severity map, per-kind+key cooldowns,
-- message building. Pure domain: the core hands over structured facts, this
-- module owns wording and gating. Channel adapters only render.

local V = _G.VUT or {}
_G.VUT = V
V.domain = V.domain or {}

local Types = V.domain.Types

local Alerts = {}

--- Severity per kind. Sound/flash defaults in Config follow the same split:
--- "alert" pulls eyes back to the screen, "warn" informs, "info" records.
Alerts.SEVERITY = {
    undercut = "alert",
    tied = "warn",
    sold = "info",
    expired = "warn",
    canceled = "info",
    lowqty = "warn",
    noactive = "alert",
    recovered = "info",
}

--- Builds the human message for one alert. The item name is wrapped in
--- brackets per the game's item convention ([Rugged Leather], [#13935]).
---@param kind string one of Config.KINDS
---@param name string item display name or "#itemID" fallback
---@param facts table kind-specific fields
---@return string
function Alerts.text(kind, name, facts)
    name = "[" .. tostring(name) .. "]"
    if kind == "undercut" then
        return ("%s undercut by %s (market %s, yours %s)"):format(
            name,
            Types.money(facts.by or 0),
            Types.money(facts.cheapest or 0),
            Types.money(facts.ownMin or 0)
        )
    elseif kind == "tied" then
        if facts.rowsAhead ~= nil then
            -- item listings: one buyer takes one whole listing
            return ("%s tied at market min %s - %d listings sell before yours"):format(
                name,
                Types.money(facts.ownMin or 0),
                facts.rowsAhead
            )
        end
        return ("%s tied at market min %s - %d units sell before yours"):format(
            name,
            Types.money(facts.ownMin or 0),
            facts.unitsAhead or 0
        )
    elseif kind == "sold" then
        if facts.gold then
            return ("%s sold %d for %s"):format(name, facts.quantity or 0, Types.money(facts.gold))
        end
        return ("%s sold %d"):format(name, facts.quantity or 0)
    elseif kind == "expired" then
        return ("%s expired - relist?"):format(name)
    elseif kind == "canceled" then
        return ("%s canceled"):format(name)
    elseif kind == "lowqty" then
        return ("%s low: %d of %d left (%d%%)"):format(name, facts.quantity or 0, facts.baseline or 0, facts.pct or 0)
    elseif kind == "noactive" then
        return ("%s sold out - no active lots"):format(name)
    elseif kind == "recovered" then
        return ("%s back to first in queue"):format(name)
    end
    return name
end

---@class AlertPolicy
---@field settings Settings live settings reference (cooldowns read through)
---@field lastAt table<string, number> signature -> session seconds
local AlertPolicy = {}
AlertPolicy.__index = AlertPolicy

---@param settings Settings
---@return AlertPolicy
function Alerts.new(settings)
    return setmetatable({ settings = settings, lastAt = {} }, AlertPolicy)
end

--- Cooldown gate: true (and stamps) when this kind+key (optionally +dedup tag)
--- may fire now. Severity "info" kinds pass through with a tiny dedup window.
---@param kind string
---@param key string keyString or itemID string
---@param now number session clock seconds
---@param tag string|nil extra dedup tag (e.g. sold quantity)
---@return boolean
function AlertPolicy:gate(kind, key, now, tag)
    local signature = kind .. "|" .. key .. "|" .. (tag or "")
    local cooldown = (self.settings.cooldownSeconds[kind] or 0)
    local last = self.lastAt[signature]
    if last and (now - last) < cooldown then
        return false
    end
    self.lastAt[signature] = now
    return true
end

--- Clears this key's market-degradation stamps (undercut/tied). Called when
--- a verdict cycle ENDS (own lot back to FIRST, or no own rows): the next
--- undercut/tie is a fresh event and must alert immediately instead of
--- inheriting the previous cycle's cooldown window.
---@param key string keyString
function AlertPolicy:resetMarket(key)
    for _, kind in ipairs({ "undercut", "tied" }) do
        local prefix = kind .. "|" .. key .. "|"
        for signature in pairs(self.lastAt) do
            if signature:sub(1, #prefix) == prefix then
                self.lastAt[signature] = nil
            end
        end
    end
end

V.domain.Alerts = Alerts
return Alerts
