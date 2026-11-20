-- VUT - own-auction state machine. Ingests sanitized owned
-- snapshots and turns them into domain events: creations, closures (classified
-- sold/expired/canceled), partial sales, and sale-ledger records. The
-- owned-snapshot DIFF is the lifecycle source of truth on this fork: the
-- AUCTION_CANCELED payload is not an auctionID and AUCTION_HOUSE_AUCTION_CREATED
-- never fired in verification - events are hints only, never identity.

local V = _G.VUT or {}
_G.VUT = V
V.domain = V.domain or {}

---@class OwnList
---@field active table<number, OwnLot> auctionID -> last active record
---@field baselines table<number, number> auctionID -> first-seen quantity
---@field ledgerSeen table<string, boolean> auctionID:qty:gold signatures
---@field cancelRequested table<number, boolean>
---@field expiredHints table<number, boolean>
local OwnList = {}
OwnList.__index = OwnList

--- Extra grace past the predicted expiry before classifying a disappearance
--- as expired (snapshot jitter, client lag).
local EXPIRY_GRACE_SECONDS = 60

---@return OwnList
function OwnList.new()
    return setmetatable({
        active = {}, ---@type table<number, OwnLot> auctionID -> last active record
        baselines = {}, ---@type table<number, number> auctionID -> first-seen quantity
        ledgerSeen = {}, ---@type table<string, boolean> auctionID:qty:gold signatures
        cancelRequested = {}, ---@type table<number, boolean>
        expiredHints = {}, ---@type table<number, boolean>
    }, OwnList)
end

--- The user (or a future cancel port) requested cancellation of this auction.
---@param auctionID number
function OwnList:markCancelRequested(auctionID)
    if type(auctionID) == "number" then
        self.cancelRequested[auctionID] = true
    end
end

--- AUCTION_HOUSE_AUCTIONS_EXPIRED hint (payload is the real auctionID here).
---@param auctionID number
function OwnList:markExpiredHint(auctionID)
    if type(auctionID) == "number" then
        self.expiredHints[auctionID] = true
    end
end

--- Ingests one sanitized snapshot; returns the event list.
--- Event shapes (all fields domain-typed):
---   {type="created", lot}
---   {type="closed", lot, reason="sold"|"expired"|"canceled"}
---   {type="partial", lot, soldQty}
---   {type="sale", auctionID, keyString, itemID, quantity, gold}
---@param records OwnLot[] sanitized active+ledger records
---@param now number session clock seconds
---@return table[]
function OwnList:ingest(records, now)
    local events = {}
    local seenActive = {}
    for _, rec in ipairs(records) do
        if rec.status == 0 then
            seenActive[rec.auctionID] = true
            rec.seenAt = now
            local prev = self.active[rec.auctionID]
            if prev then
                if rec.quantity < prev.quantity then
                    events[#events + 1] = { type = "partial", lot = rec, soldQty = prev.quantity - rec.quantity }
                end
                self.active[rec.auctionID] = rec
            else
                self.baselines[rec.auctionID] = rec.quantity
                self.active[rec.auctionID] = rec
                self.cancelRequested[rec.auctionID] = nil
                self.expiredHints[rec.auctionID] = nil
                events[#events + 1] = { type = "created", lot = rec }
            end
        else
            local gold = rec.buyoutRaw
            local signature = table.concat({ rec.auctionID, rec.quantity, gold or -1 }, ":")
            if not self.ledgerSeen[signature] then
                self.ledgerSeen[signature] = true
                events[#events + 1] = {
                    type = "sale",
                    auctionID = rec.auctionID,
                    keyString = rec.keyString,
                    itemID = rec.itemID,
                    quantity = rec.quantity,
                    gold = gold,
                }
            end
        end
    end
    for auctionID, lot in pairs(self.active) do
        if not seenActive[auctionID] then
            self.active[auctionID] = nil
            local reason = "sold"
            if self.cancelRequested[auctionID] then
                reason = "canceled"
            elseif self.expiredHints[auctionID] then
                reason = "expired"
            elseif
                lot.seenAt
                and lot.timeLeftSeconds
                and (now - lot.seenAt) >= lot.timeLeftSeconds + EXPIRY_GRACE_SECONDS
            then
                reason = "expired"
            end
            self.cancelRequested[auctionID] = nil
            self.expiredHints[auctionID] = nil
            events[#events + 1] = { type = "closed", lot = lot, reason = reason }
        end
    end
    return events
end

--- Active lots as a flat list.
---@return OwnLot[]
function OwnList:activeLots()
    local out = {}
    for _, lot in pairs(self.active) do
        out[#out + 1] = lot
    end
    table.sort(out, function(a, b)
        return a.auctionID < b.auctionID
    end)
    return out
end

--- Per-key aggregate of the ACTIVE inventory: remaining quantity,
--- first-seen baseline quantity, lot count, commodity-ness, display id.
--- Drives low-quantity and no-active alerts.
---@class KeySummary
---@field quantity number remaining units across active lots
---@field baseline number first-seen units summed across active lots
---@field lots number active lot count
---@field isCommodity boolean|nil
---@field itemID number

---@return table<string, KeySummary>
function OwnList:keySummary()
    local out = {}
    for auctionID, lot in pairs(self.active) do
        local agg = out[lot.keyString]
        if not agg then
            agg = { quantity = 0, baseline = 0, lots = 0, isCommodity = lot.isCommodity, itemID = lot.itemID }
            out[lot.keyString] = agg
        end
        agg.quantity = agg.quantity + lot.quantity
        agg.baseline = agg.baseline + (self.baselines[auctionID] or lot.quantity)
        agg.lots = agg.lots + 1
        if lot.isCommodity ~= nil then
            agg.isCommodity = agg.isCommodity or lot.isCommodity
        end
    end
    return out
end

V.domain.OwnList = OwnList
return OwnList
