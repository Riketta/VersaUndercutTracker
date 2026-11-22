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
    local itemID = opts.itemID or 13935
    local itemLevel = opts.itemLevel or 55
    local itemSuffix = opts.itemSuffix or 0
    return {
        auctionID = auctionID,
        keyString = ("i:%d:%d:%d:0"):format(itemID, itemLevel, itemSuffix),
        itemID = itemID,
        itemLevel = itemLevel,
        itemSuffix = itemSuffix,
        battlePetSpeciesID = 0,
        quantity = quantity,
        status = status,
        buyoutRaw = opts.buyout,
        unitPrice = opts.unit or 954,
        isCommodity = opts.commodity ~= false,
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
            readItemRows = function(self, itemKey)
                return self.itemRowsByItemID and self.itemRowsByItemID[itemKey.itemID] or {}
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

    it("re-alerts when the tie deepens, not when it eases", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
        assert.equals("tied", notify.dispatched[1].kind)
        -- more units jump ahead of the existing tie: re-alert (cooldown passed)
        clock.t = clock.t + 301
        market.rowsByItem = { [13935] = { makeRow(954, 61), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
        assert.equals("tied", notify.dispatched[2].kind)
        assert.is_true(notify.dispatched[2].text:find("61 units sell before yours") ~= nil)
        -- the tie eases or holds: quiet
        clock.t = clock.t + 301
        market.rowsByItem = { [13935] = { makeRow(954, 30), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        clock.t = clock.t + 301
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
    end)

    it("alerts a fresh tie after a cancel/repost cycle reaches FIRST", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        -- cycle one: competitor ties ahead -> alert, tied stamp set
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals("tied", notify.dispatched[1].kind)
        -- user cancels (own rows gone) and reposts cheaper: GONE then FIRST;
        -- recovered stays quiet from GONE, but the cycle-end must clear stamps
        market.rowsByItem = { [13935] = {} }
        core:onCommodityRows(13935)
        assert.equals("GONE", core.verdicts["i:13935:0:0:0"].state)
        market.rowsByItem = { [13935] = { makeRow(940, 60, 60), makeRow(954, 3) } }
        core:onCommodityRows(13935)
        assert.equals("FIRST", core.verdicts["i:13935:0:0:0"].state)
        assert.equals(1, #notify.dispatched)
        -- cycle two: competitor ties the NEW price 30s later - inside the
        -- 300s tied cooldown inherited from cycle one, but the stamps were
        -- reset at FIRST, so the fresh tie must alert
        clock.t = clock.t + 30
        market.rowsByItem = { [13935] = { makeRow(940, 25), makeRow(940, 60, 60), makeRow(954, 3) } }
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
        assert.equals("tied", notify.dispatched[2].kind)
        assert.is_true(notify.dispatched[2].text:find("25 units sell before yours") ~= nil)
    end)

    it("alerts a fresh tie after a direct recovery to FIRST", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals("tied", notify.dispatched[1].kind)
        -- the tying competitor sells out: direct TIED -> FIRST recovery
        market.rowsByItem = { [13935] = { makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
        assert.equals("recovered", notify.dispatched[2].kind)
        -- a NEW competitor re-ties 30s later, inside the tied cooldown
        clock.t = clock.t + 30
        market.rowsByItem = { [13935] = { makeRow(954, 12), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(3, #notify.dispatched)
        assert.equals("tied", notify.dispatched[3].kind)
        assert.is_true(notify.dispatched[3].text:find("12 units sell before yours") ~= nil)
    end)

    it("re-alerts when the undercut deepens", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(950, 100), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
        assert.equals("undercut", notify.dispatched[1].kind)
        clock.t = clock.t + 121
        market.rowsByItem = { [13935] = { makeRow(900, 100), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
        assert.equals("undercut", notify.dispatched[2].kind)
    end)

    it("re-alerts when more item listings tie ahead of own", function()
        core:onAhOpen()
        owned.records = {
            ownedRecord(178228136, 1, 0, { itemID = 10123, itemLevel = 57, itemSuffix = 14327, commodity = false }),
        }
        core:onOwnedUpdated()
        local key = { itemID = 10123, itemLevel = 57, itemSuffix = 14327, battlePetSpeciesID = 0 }
        local function irow(unit, own)
            return { auctionID = unit, unitPrice = unit, buyoutTotal = unit, quantity = 1, isOwn = own == true }
        end
        market.itemRowsByItemID = { [10123] = { irow(17700), irow(17700, true) } }
        core:onItemRows(key)
        assert.equals(1, #notify.dispatched)
        assert.equals("tied", notify.dispatched[1].kind)
        assert.is_true(notify.dispatched[1].text:find("1 listings sell before yours") ~= nil)
        -- a second seller ties ahead of own: re-alert past the tied cooldown
        clock.t = clock.t + 301
        market.itemRowsByItemID = { [10123] = { irow(17700), irow(17700), irow(17700, true) } }
        core:onItemRows(key)
        assert.equals(2, #notify.dispatched)
        assert.is_true(notify.dispatched[2].text:find("2 listings sell before yours") ~= nil)
    end)

    it("pause freezes monitoring; resume re-baselines silently", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        -- establish a tie so verdicts and stamps hold live state
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
        -- PAUSE: user cancels/reposts; owned diffs, market answers and
        -- events all arrive - everything stays silent, verdicts untouched
        core:pause()
        clock.t = clock.t + 5
        owned.records = { ownedRecord(178364562, 40, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(900, 10), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        core:onCommodityReceived()
        assert.equals(1, #notify.dispatched)
        assert.equals("TIED", core.verdicts["i:13935:0:0:0"].state)
        -- RESUME: re-baseline query fired, verdicts and stamps cleared
        local refreshes = owned.refreshes
        core:resume()
        assert.is_true(owned.refreshes > refreshes)
        assert.is_nil(core.verdicts["i:13935:0:0:0"])
        -- the post-churn owned snapshot lands on a FRESH baseline: silent
        clock.t = clock.t + 1
        core:onOwnedUpdated()
        assert.equals(1, #notify.dispatched)
        -- a fresh tie 36s after the original alert (tied cooldown is 120s
        -- now) still alerts: the resume cleared the market stamps
        market.rowsByItem = { [13935] = { makeRow(954, 5), makeRow(954, 40, 40) } }
        core:onCommodityRows(13935)
        assert.equals(2, #notify.dispatched)
        assert.equals("tied", notify.dispatched[2].kind)
    end)

    it("resume while running is a no-op", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
        local refreshes = owned.refreshes
        core:resume()
        assert.equals(refreshes, owned.refreshes)
        assert.equals("TIED", core.verdicts["i:13935:0:0:0"].state)
        -- worsening inside the tied cooldown stays gated (stamps preserved)
        clock.t = clock.t + 30
        market.rowsByItem = { [13935] = { makeRow(954, 61), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        assert.equals(1, #notify.dispatched)
    end)

    it("status exposes the not-first set for the summary painter", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        -- tied item + first item: only the tied key lands in notFirst
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityRows(13935)
        owned.records = {
            ownedRecord(178364562, 60, 0),
            ownedRecord(178364563, 20, 0, { itemID = 13932, itemLevel = 45 }),
        }
        core:onOwnedUpdated()
        market.rowsByItem[13932] = { makeRow(954, 20, 20), makeRow(955, 100) }
        core:onCommodityRows(13932)
        local s = core:status()
        assert.is_true(s.notFirst["i:13935:0:0:0"])
        assert.is_nil(s.notFirst["i:13932:0:0:0"])
        -- recovery drops the key from the set
        market.rowsByItem[13935] = { makeRow(954, 60, 60) }
        core:onCommodityRows(13935)
        assert.is_nil(core:status().notFirst["i:13935:0:0:0"])
    end)

    it("re-verdicts the last queried commodity on RECEIVED (payload-less)", function()
        core:onAhOpen()
        owned.records = { ownedRecord(178364562, 60, 0) }
        core:onOwnedUpdated()
        core:beatCommodities()
        assert.equals(13935, core.lastCommodityQuery.itemID)
        market.rowsByItem = { [13935] = { makeRow(954, 3), makeRow(954, 60, 60) } }
        core:onCommodityReceived()
        assert.equals("TIED", core.verdicts["i:13935:0:0:0"].state)
        local s = core:status()
        assert.equals("TIED", s.verdicts["i:13935:0:0:0"])
        assert.equals("number", type(s.verdictAges["i:13935:0:0:0"]))
        assert.equals(13935, s.lastCommodityQuery.itemID)
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
