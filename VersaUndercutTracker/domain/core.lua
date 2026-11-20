-- VUT - core orchestration. Owns POLICY: what to poll, when
-- to alert, how verdicts map to alert kinds. Mechanics (wire sends, UI,
-- timers, persistence) live in adapters; this module is driven through its
-- inbound methods and drives its outbound ports.

local V = _G.VUT or {}
_G.VUT = V
V.domain = V.domain or {}

local Types = V.domain.Types
local Queue = V.domain.Queue
local Alerts = V.domain.Alerts
local OwnList = V.domain.OwnList

--- The core: driven beats + transitions over the outbound ports. The
--- method set doubles as the ControlPort contract (ports/inbound.lua).
---@class Core
---@field settings Settings
---@field ownedPort OwnedAuctionsPort
---@field marketPort MarketPort
---@field notify NotifierPort
---@field clock ClockPort
---@field itemInfo ItemInfoPort
---@field persist PersistencePort|nil
---@field ownlist OwnList
---@field alerts AlertPolicy
---@field sessionOpen boolean
---@field paused boolean
---@field throttleUntil number
---@field verdicts table<string, table>
---@field keyHadActive table<string, number>
---@field keyItemIDs table<string, number>
---@field commodityCursor number
---@field itemCursor number
---@field itemProbe table
local Core = {}
Core.__index = Core

--- Backoff after a throttle drop: skip channel beats for a few seconds.
local THROTTLE_BACKOFF_SECONDS = 3

--- How long the item refresh-probe waits for rows before declaring failure.
local ITEM_PROBE_TIMEOUT_SECONDS = 10

---@param deps table {settings, ownedPort, marketPort, notify, clock, itemInfo, persist?}
---@return Core
function Core.new(deps)
    return setmetatable({
        settings = deps.settings,
        ownedPort = deps.ownedPort,
        marketPort = deps.marketPort,
        notify = deps.notify,
        clock = deps.clock,
        itemInfo = deps.itemInfo,
        persist = deps.persist,
        ownlist = OwnList.new(),
        alerts = Alerts.new(deps.settings),
        sessionOpen = false,
        paused = false,
        throttleUntil = 0,
        verdicts = {}, ---@type table<string, table> keyString -> last verdict
        keyHadActive = {}, ---@type table<string, number> keyString -> itemID
        keyItemIDs = {}, ---@type table<string, number> keyString -> itemID (labels)
        commodityCursor = 0,
        itemCursor = 0,
        itemProbe = { state = "unknown", at = 0, itemID = nil },
    }, Core)
end

-- ===== helpers ===============================================================

---@param itemID number
---@return string
function Core:itemLabel(itemID)
    local name = self.itemInfo and self.itemInfo:name(itemID)
    if type(name) == "string" and #name > 0 then
        return name
    end
    return "#" .. itemID
end

--- Fires one alert through the policy gate and the notifier bus.
function Core:dispatch(kind, keyString, facts, label, tag)
    if self.alerts:gate(kind, keyString, self.clock:now(), tag) then
        self.notify:dispatch({
            kind = kind,
            severity = Alerts.SEVERITY[kind],
            text = Alerts.text(kind, label, facts),
            routing = self.settings.channels[kind] or {},
        })
    end
end

--- Distinct owned commodity itemIDs and item keys (domain-shaped).
function Core:ownedItemSets()
    local commodityIDs = {}
    local itemKeys = {}
    for _, lot in ipairs(self.ownlist:activeLots()) do
        self.keyItemIDs[lot.keyString] = lot.itemID
        if lot.isCommodity then
            commodityIDs[#commodityIDs + 1] = lot.itemID
        else
            itemKeys[#itemKeys + 1] = {
                keyString = lot.keyString,
                itemID = lot.itemID,
                itemLevel = lot.itemLevel,
                itemSuffix = lot.itemSuffix,
                battlePetSpeciesID = lot.battlePetSpeciesID,
            }
        end
    end
    return commodityIDs, itemKeys
end

-- ===== session (driven by the events adapter) =================================

--- PLAYER_LOGIN: fire the owned query once, early, so the session baseline
--- settles BEFORE the auction house opens - sales landing between login and
--- the first AH visit then diff against a complete baseline instead of racing
--- the AH-open update stream. If the pre-AH query is refused, the AH-open
--- refresh is the fallback baseline moment.
function Core:onStartup()
    self.ownedPort:refresh()
end

function Core:onAhOpen()
    self.sessionOpen = true
    self.itemProbe = { state = "unknown", at = 0, itemID = nil }
    self.ownedPort:refresh()
end

function Core:onAhClose()
    self.sessionOpen = false
end

function Core:onThrottleDrop()
    self.throttleUntil = self.clock:now() + THROTTLE_BACKOFF_SECONDS
end

-- ===== owned layer ============================================================

--- Beat: refresh the owned list (rows land asynchronously in onOwnedUpdated).
function Core:beatOwned()
    if not self.sessionOpen or self.paused then
        return
    end
    self.ownedPort:refresh()
end

--- OWNED_AUCTIONS_UPDATED landed: read + diff + evaluate aggregates.
--- Partial snapshots are never ingested: the ledger baseline is only valid
--- when complete, or late-arriving pre-session rows replay as sold alerts.
function Core:onOwnedUpdated()
    if not self.ownedPort:hasFull() then
        return
    end
    local now = self.clock:now()
    local records = self.ownedPort:read()
    -- Seed exact display names from the records' own item links first - free,
    -- authoritative, and usually the only source needed for item lots.
    for _, record in ipairs(records) do
        if record.itemLink then
            self.itemInfo:learnFromLink(record.itemID, record.itemLink)
        end
    end
    local events = self.ownlist:ingest(records, now)
    local closedKeys = {} ---@type table<string, string> keyString -> close reason this cycle
    for _, event in ipairs(events) do
        local lot = event.lot
        if event.type == "sale" then
            self.keyItemIDs[event.keyString] = event.itemID
            -- Ledger rows born inside the cancel window belong to the canceled
            -- lot (the fork leaves status records for cancels too) - account
            -- them silently; only out-of-window rows are sale alerts.
            if not event.inCancelWindow then
                self:dispatch(
                    "sold",
                    event.keyString,
                    { quantity = event.quantity, gold = event.gold },
                    self:itemLabel(event.itemID),
                    tostring(event.quantity)
                )
            end
        elseif event.type == "partial" then
            self.keyItemIDs[lot.keyString] = lot.itemID
            self:dispatch(
                "sold",
                lot.keyString,
                { quantity = event.soldQty },
                self:itemLabel(lot.itemID),
                tostring(event.soldQty)
            )
        elseif event.type == "closed" then
            self.keyItemIDs[lot.keyString] = lot.itemID
            closedKeys[lot.keyString] = event.reason
            if event.reason == "sold" then
                -- Tag = the closed quantity so the sale-ledger record for the
                -- same full sale (same qty) dedups against this via cooldown,
                -- whichever lands first.
                self:dispatch(
                    "sold",
                    lot.keyString,
                    { quantity = lot.quantity },
                    self:itemLabel(lot.itemID),
                    tostring(lot.quantity)
                )
            elseif event.reason == "expired" then
                self:dispatch("expired", lot.keyString, {}, self:itemLabel(lot.itemID), nil)
            else
                self:dispatch("canceled", lot.keyString, {}, self:itemLabel(lot.itemID), nil)
            end
        end
    end
    self:evaluateAggregates(closedKeys)
end

--- Low-quantity and no-active transitions from the per-key aggregate. A key
--- that just closed as canceled/expired skips the noactive alert (the user
--- knows: they acted, or the expiry alert already fired); sold-out keeps it
--- (that is the restock reminder).
function Core:evaluateAggregates(closedKeys)
    local summary = self.ownlist:keySummary()
    for keyString, agg in pairs(summary) do
        self.keyItemIDs[keyString] = agg.itemID
        local pct = 100
        if agg.baseline > 0 then
            pct = math.floor(agg.quantity / agg.baseline * 100 + 0.5)
        end
        if self.settings.lowQuantityPct > 0 and pct <= self.settings.lowQuantityPct and agg.quantity > 0 then
            self:dispatch(
                "lowqty",
                keyString,
                { quantity = agg.quantity, baseline = agg.baseline, pct = pct },
                self:itemLabel(agg.itemID),
                nil
            )
        end
    end
    for keyString, itemID in pairs(self.keyHadActive) do
        if not summary[keyString] then
            local reason = closedKeys[keyString]
            if reason ~= "canceled" and reason ~= "expired" then
                self.keyHadActive[keyString] = nil
                self:dispatch("noactive", keyString, {}, self:itemLabel(itemID), nil)
            else
                self.keyHadActive[keyString] = nil
            end
        end
    end
    for keyString, agg in pairs(summary) do
        self.keyHadActive[keyString] = agg.itemID
    end
    now = now
end

-- ===== market layer ===========================================================

--- Beat: rotate one commodity query.
function Core:beatCommodities()
    if not self.sessionOpen or self.paused then
        return
    end
    if self.clock:now() < self.throttleUntil then
        return
    end
    local ids = (self:ownedItemSets())
    if #ids == 0 then
        return
    end
    self.commodityCursor = (self.commodityCursor % #ids) + 1
    self.marketPort:queryCommodity(ids[self.commodityCursor])
end

--- Beat: item channel per settings (probe -> refresh, or click rotation).
function Core:beatItems()
    if not self.sessionOpen or self.paused then
        return
    end
    local channel = self.settings.itemChannel
    if channel == "off" or channel == "passive" then
        return
    end
    local _, itemKeys = self:ownedItemSets()
    if #itemKeys == 0 then
        return
    end
    local now = self.clock:now()
    if channel == "auto" then
        if self.itemProbe.state == "unknown" then
            local first = itemKeys[1]
            self.itemProbe = { state = "pending", at = now, itemID = first.itemID }
            self.marketPort:refreshItem(first)
            return
        elseif self.itemProbe.state == "pending" then
            if now - self.itemProbe.at <= ITEM_PROBE_TIMEOUT_SECONDS then
                return
            end
            self.itemProbe.state = "failed"
        end
        if self.itemProbe.state == "ok" then
            self.itemCursor = (self.itemCursor % #itemKeys) + 1
            self.marketPort:refreshItem(itemKeys[self.itemCursor])
            return
        end
        -- Probe failed: script refresh is gate-refused. "auto" degrades to
        -- passive (opportunistic reads - no UI interference); the explicit
        -- "click" channel opts into the summary-row rotation.
        return
    end
    if channel == "click" and self.marketPort.supportsItemClick and self.marketPort:supportsItemClick() then
        self.itemCursor = (self.itemCursor % #itemKeys) + 1
        self.marketPort:clickItemScan(itemKeys[self.itemCursor].itemID)
    end
end

--- COMMODITY_SEARCH_RESULTS_UPDATED(itemID): read rows, verdict, transitions.
function Core:onCommodityRows(itemID)
    local rows = self.marketPort:readCommodityRows(itemID)
    local verdict = Queue.commodity(rows)
    self:applyVerdict(
        Types.keyString({ itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }),
        itemID,
        verdict
    )
end

--- ITEM_SEARCH_RESULTS_UPDATED(itemKey): read rows, verdict, transitions.
function Core:onItemRows(itemKey)
    if type(itemKey) ~= "table" or not Types.isItemKey(itemKey) then
        return
    end
    if self.itemProbe.state == "pending" and itemKey.itemID == self.itemProbe.itemID then
        self.itemProbe.state = "ok"
    end
    local keyString = Types.keyString(itemKey)
    local _, itemKeys = self:ownedItemSets()
    local owned = false
    for _, key in ipairs(itemKeys) do
        if key.keyString == keyString then
            owned = true
            break
        end
    end
    if not owned then
        return
    end
    local rows = self.marketPort:readItemRows(itemKey)
    self:applyVerdict(keyString, itemKey.itemID, Queue.item(rows))
end

--- Verdict state machine: alerts fire on transitions only.
function Core:applyVerdict(keyString, itemID, verdict)
    local now = self.clock:now()
    local prev = self.verdicts[keyString]
    verdict.at = now
    self.verdicts[keyString] = verdict
    if prev and prev.state == verdict.state then
        return
    end
    local label = self:itemLabel(itemID)
    if verdict.state == "UNDERCUT" then
        self:dispatch(
            "undercut",
            keyString,
            { by = verdict.by, cheapest = verdict.cheapest, ownMin = verdict.ownMin },
            label,
            nil
        )
    elseif verdict.state == "TIED" then
        self:dispatch("tied", keyString, {
            unitsAhead = verdict.unitsAhead,
            rowsAhead = verdict.rowsAhead,
            ownMin = verdict.ownMin,
        }, label, nil)
    elseif verdict.state == "FIRST" and prev and (prev.state == "UNDERCUT" or prev.state == "TIED") then
        self:dispatch("recovered", keyString, {}, label, nil)
    end
end

-- ===== lifecycle hints (events are hints; the owned diff is the truth) =======

function Core:markCancelRequested(auctionID)
    self.ownlist:markCancelRequested(auctionID)
    -- The wire argument is not a reliable owned auctionID on this fork - the
    -- window is the primary attribution; the id is a bonus when it matches.
    self.ownlist:openCancelWindow(self.clock:now(), 10)
end

function Core:onExpiredHint(auctionID)
    self.ownlist:markExpiredHint(auctionID)
    self.ownedPort:refresh()
end

function Core:onCanceledHint()
    self.ownlist:openCancelWindow(self.clock:now(), 10)
    self.ownedPort:refresh()
end

function Core:onCommodityPurchased(itemID, quantity)
    local keyString = Types.keyString({ itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    self.keyItemIDs[keyString] = itemID
    self:dispatch("sold", keyString, { quantity = quantity }, self:itemLabel(itemID), tostring(quantity))
    self.ownedPort:refresh()
end

-- ===== control port (slash / console / future GUI) ===========================

function Core:pause()
    self.paused = true
end

function Core:resume()
    self.paused = false
end

--- Immediate full pass: owned refresh + every commodity once + one item beat.
function Core:scanNow()
    self.ownedPort:refresh()
    local ids = (self:ownedItemSets())
    for _, itemID in ipairs(ids) do
        self.marketPort:queryCommodity(itemID)
    end
    self:beatItems()
end

--- Dispatches a test alert through the real bus, bypassing the cooldown gate.
function Core:testAlert(kind)
    self.notify:dispatch({
        kind = kind,
        severity = Alerts.SEVERITY[kind],
        text = "[test] " .. Alerts.text(kind, "Copper Bar", {
            by = 12345,
            cheapest = 954,
            ownMin = 13299,
            unitsAhead = 61,
            quantity = 7,
            gold = 6678,
            baseline = 60,
            pct = 12,
        }),
        routing = self.settings.channels[kind] or {},
    })
end

--- Status snapshot for the UI/API.
function Core:status()
    local summary = self.ownlist:keySummary()
    local activeKeys = 0
    for _ in pairs(summary) do
        activeKeys = activeKeys + 1
    end
    local verdictStates = {}
    for keyString, verdict in pairs(self.verdicts) do
        verdictStates[keyString] = verdict.state
    end
    return {
        session = self.sessionOpen,
        paused = self.paused,
        ownedBaseline = self.ownlist.baselined,
        activeLots = #self.ownlist:activeLots(),
        activeKeys = activeKeys,
        verdicts = verdictStates,
        itemChannel = self.settings.itemChannel,
        itemProbe = self.itemProbe.state,
    }
end

V.domain.Core = Core
return Core
