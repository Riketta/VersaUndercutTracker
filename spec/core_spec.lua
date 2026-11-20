require("VersaUndercutTracker.domain.types")
require("VersaUndercutTracker.domain.config")
require("VersaUndercutTracker.domain.ownlist")
require("VersaUndercutTracker.domain.queue")
require("VersaUndercutTracker.domain.alerts")
local Core = require("VersaUndercutTracker.domain.core")

local function makeRow(unitPrice, quantity, ownUnits)
    return {
        auctionID = unitPrice * 100000 + quantity,
        unitPrice = unitPrice,
        quantity = quantity,
        ownUnits = ownUnits or 0,
        isOwn = (ownUnits or 0) > 0,
        ownersCount = 1,
    }
end

local function copyOf(record)
    local out = {}
    for key, value in pairs(record) do
        out[key] = value
    end
    return out
end

local function ownedRecord(auctionID, quantity, status, opts)
    opts = opts or {}
    return {
        auctionID = auctionID,
        keyString = "i:13935:55:0:0",
        itemID = 13935,
        itemLevel = 55,
        itemSuffix = 0,
        battlePetSpeciesID = 0,
        quantity = quantity,
        status = status,
        buyoutRaw = opts.buyout,
        unitPrice = opts.unit or 954,
        isCommodity = true,
        timeLeftSeconds = opts.timeLeft or 7200,
        itemLink = nil,
    }
end

describe("domain core", function()
    local core, clock, owned, market, notify

    before_each(function()
        clock = {
            t = 1000,
            now = function()
                return clock.t
            end,
        }
        owned = {
            refreshes = 0,
            records = {},
            full = true,
            refresh = function(self)
                self.refreshes = self.refreshes + 1
            end,
            hasFull = function(self)
                return self.full
            end,
            read = function(self)
                return self.records
            end,
        }
        market = {
            commodityQueries = {},
            queryCommodity = function(self, itemID)
                self.commodityQueries[#self.commodityQueries + 1] = itemID
                return true
            end,
            readCommodityRows = function(self, itemID)
                return self.rowsByItem and self.rowsByItem[itemID] or {}
            end,
            refreshItem = function()
                return true
            end,
            readItemRows = function()
                return {}
            end,
            supportsItemClick = function()
                return false
            end,
            clickItemScan = function()
                return false, "unsupported"
            end,
        }
        notify = {
            dispatched = {},
            dispatch = function(self, alert)
                self.dispatched[#self.dispatched + 1] = alert
            end,
        }
        core = Core.new({
            settings = require("VersaUndercutTracker.domain.config").defaults(),
            ownedPort = owned,
            marketPort = market,
            notify = notify,
            clock = clock,
            itemInfo = {
                name = function(_, itemID)
                    return "Item" .. itemID
                end,
            },
            persist = nil,
        })
    end)

    it("fires no market alerts on the first verdict (transition-only alerts)", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(954, 615, 60), makeRow(955, 462) } }
        core:onCommodityRows(13935)
        assert.equals(0, #notify.dispatched)
        -- commodity verdicts key on the bare market key (itemID view)
        assert.equals("FIRST", core.verdicts["i:13935:0:0:0"].state)
    end)

    it("alerts on the undercut transition, stays quiet while it holds, recovers", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        -- competitor undercuts
        market.rowsByItem = { [13935] = { makeRow(950, 100), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
        assert.equals("undercut", notify.dispatched[1].kind)
        -- still undercut: transition-only, no repeat
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
        -- competitor bought out: recovered
        market.rowsByItem = { [13935] = { makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
        assert.equals("recovered", notify.dispatched[2].kind)
    end)

    it("alerts tied when newer sellers share the price", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals("tied", notify.dispatched[1].kind)
        assert.is_true(notify.dispatched[1].text:find("3 units sell before yours") ~= nil)
    end)

    it("alerts sold from the sale ledger and dedups the matching closure", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178305292, 4, 0, { unit = 11000, buyout = 11000 }) }
        core:onOwnedUpdated()
        -- full sale: ledger record (4 x 11000) + lot gone in one snapshot.
        -- The sale alert carries the gold; the closure's sold alert dedups
        -- against it (same quantity tag); noactive fires as the restock
        -- reminder in the same cycle.
        owned.records = { ownedRecord(178305292, 4, 1, { buyout = 44000 }) }
        core:onOwnedUpdated()
        assert.equals(2, #notify.dispatched)
        assert.equals("sold", notify.dispatched[1].kind)
        assert.is_true(notify.dispatched[1].text:find("sold 4 for 4g 40s") ~= nil)
        assert.equals("noactive", notify.dispatched[2].kind)
        -- further empty snapshots stay quiet
        owned.records = {}
        core:onOwnedUpdated()
        assert.equals(2, #notify.dispatched)
    end)

    it("does not replay pre-session sale rows on the first snapshot", function()
        -- reload + open AH: the server still carries the old sale ledger
        core:onAhOpen()
        owned.records = { ownedRecord(178305292, 4, 1, { buyout = 44000 }) }
        core:onOwnedUpdated()
        assert.equals(0, #notify.dispatched)
        -- sales that happen AFTER the session baselined still alert
        clock.t = clock.t + 30
        table.insert(owned.records, copyOf(owned.records[1]))
        core:onOwnedUpdated()
        assert.equals(1, #notify.dispatched)
        assert.equals("sold", notify.dispatched[1].kind)
    end)

    it("alerts partial sales and low quantity", function()
        core.settings.lowQuantityPct = 25
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        clock.t = clock.t + 30
        owned.records = { ownedRecord(178364562, 10, 0) }
        core:onOwnedUpdated()
        assert.equals("sold", notify.dispatched[1].kind)
        assert.is_true(notify.dispatched[1].text:find("sold 50") ~= nil)
        assert.equals("lowqty", notify.dispatched[2].kind)
        assert.is_true(notify.dispatched[2].text:find("10 of 60 left") ~= nil)
    end)

    it("classifies user cancels quietly (default channels off)", function()
        core:onAhOpen()
        owned.records = { ownedRecord(1, 5, 0) }
        core:onOwnedUpdated()
        core:markCancelRequested(1)
        owned.records = {}
        core:onOwnedUpdated()
        assert.equals(1, #notify.dispatched)
        assert.equals("canceled", notify.dispatched[1].kind)
        assert.is_false(notify.dispatched[1].routing.chat)
    end)

    it("cancel window quiets unmatched-id cancels: no sold, no noactive", function()
        -- The wire cancel argument is garbage on this fork (verified: 110);
        -- only the window attributes the closure.
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        clock.t = clock.t + 30
        core:markCancelRequested(110)
        clock.t = clock.t + 2
        owned.records = {}
        core:onOwnedUpdated()
        assert.equals(1, #notify.dispatched)
        assert.equals("canceled", notify.dispatched[1].kind)
    end)

    it("ledger rows born in the cancel window never alert as sold", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        clock.t = clock.t + 30
        core:markCancelRequested(110)
        clock.t = clock.t + 2
        -- canceled lot leaves a status record + vanishes from actives
        owned.records = { ownedRecord(178364562, 60, 1, { buyout = 57240 }) }
        core:onOwnedUpdated()
        assert.equals(1, #notify.dispatched)
        assert.equals("canceled", notify.dispatched[1].kind)
    end)

    it("ignores partial owned snapshots; the first FULL snapshot baselines", function()
        -- reload + open AH: the first OWNED_AUCTIONS_UPDATED can fire while
        -- rows are still streaming; only a complete set may be ingested.
        core:onAhOpen()
        owned.full = false
        owned.records = { ownedRecord(178305292, 4, 1, { buyout = 44000 }) }
        core:onOwnedUpdated()
        assert.equals(0, #notify.dispatched)
        assert.is_false(core.ownlist.baselined)
        -- the same rows arrive again once the set is complete: silent baseline
        owned.full = true
        core:onOwnedUpdated()
        assert.equals(0, #notify.dispatched)
        assert.is_true(core.ownlist.baselined)
        -- growth after the full baseline is still a sale
        clock.t = clock.t + 30
        table.insert(owned.records, copyOf(owned.records[1]))
        core:onOwnedUpdated()
        assert.equals(1, #notify.dispatched)
        assert.equals("sold", notify.dispatched[1].kind)
    end)

    it("onStartup fires the early owned refresh before the AH opens", function()
        core:onStartup()
        assert.equals(1, owned.refreshes)
    end)

    it("skips channel beats during throttle backoff, resumes after", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        core:beatCommodities()
        assert.equals(1, #market.commodityQueries)
        core:onThrottleDrop()
        core:beatCommodities()
        assert.equals(1, #market.commodityQueries)
        clock.t = clock.t + 4
        core:beatCommodities()
        assert.equals(2, #market.commodityQueries)
    end)

    it("ignores item rows for keys it does not own", function()
        core:onAhOpen()
        core:onItemRows({ itemID = 99999, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
        assert.equals(0, #notify.dispatched)
        assert.is_nil(core.verdicts["i:99999:0:0:0"])
    end)
end)
