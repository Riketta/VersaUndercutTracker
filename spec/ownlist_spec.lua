local OwnList = require("VersaUndercutTracker.domain.ownlist")

local KEY = "i:13935:55:0:0"

local function lot(auctionID, quantity, status, opts)
    opts = opts or {}
    return {
        auctionID = auctionID,
        keyString = opts.keyString or KEY,
        itemID = opts.itemID or 13935,
        itemLevel = 55,
        itemSuffix = 0,
        battlePetSpeciesID = 0,
        quantity = quantity,
        status = status,
        buyoutRaw = opts.buyout,
        unitPrice = opts.unitPrice or 954,
        isCommodity = opts.isCommodity ~= false,
        timeLeftSeconds = opts.timeLeft or 3600,
        itemLink = nil,
    }
end

describe("domain ownlist", function()
    it("emits created for first-seen actives and records the baseline", function()
        local list = OwnList.new()
        local events = list:ingest({ lot(1, 60, 0) }, 100)
        assert.equals(1, #events)
        assert.equals("created", events[1].type)
        assert.equals(60, list.baselines[1])
    end)

    it("emits partial on quantity drops and keeps the baseline", function()
        local list = OwnList.new()
        list:ingest({ lot(1, 60, 0) }, 100)
        local events = list:ingest({ lot(1, 49, 0) }, 200)
        assert.equals(1, #events)
        assert.equals("partial", events[1].type)
        assert.equals(11, events[1].soldQty)
        assert.equals(60, list.baselines[1])
        assert.equals(49, list.active[1].quantity)
    end)

    it("classifies closures: cancel hint wins, then expiry, else sold", function()
        local list = OwnList.new()
        list:ingest({ lot(1, 5, 0), lot(2, 5, 0, { timeLeft = 30 }), lot(3, 5, 0) }, 100)
        list:markCancelRequested(1)
        list:markExpiredHint(3)
        local events = list:ingest({}, 5000)
        assert.equals(3, #events)
        local reasons = {}
        for _, event in ipairs(events) do
            reasons[event.lot.auctionID] = event.reason
        end
        assert.equals("canceled", reasons[1])
        -- lot 2: last seen at t=100 with 30s left; closure at t=5000 is far
        -- past the expiry horizon -> expired
        assert.equals("expired", reasons[2])
        -- lot 3 had the explicit expiry hint
        assert.equals("expired", reasons[3])
    end)

    it("classifies a fresh disappearance as sold", function()
        local list = OwnList.new()
        list:ingest({ lot(7, 3, 0, { timeLeft = 7200 }) }, 100)
        local events = list:ingest({}, 200)
        assert.equals(1, #events)
        assert.equals("closed", events[1].type)
        assert.equals("sold", events[1].reason)
    end)

    it("emits sale ledger records once per signature", function()
        local list = OwnList.new()
        local record = lot(42, 11, 1, { buyout = 10494 })
        local events = list:ingest({ record }, 100)
        assert.equals(1, #events)
        assert.equals("sale", events[1].type)
        assert.equals(11, events[1].quantity)
        assert.equals(10494, events[1].gold)
        assert.equals(KEY, events[1].keyString)
        -- same record again: silent
        assert.equals(0, #list:ingest({ record }, 200))
        -- a second, bigger sale on the same auctionID: a new event
        local events2 = list:ingest({ lot(42, 14, 1, { buyout = 13356 }) }, 300)
        assert.equals(1, #events2)
        assert.equals(14, events2[1].quantity)
    end)

    it("aggregates per-key quantity vs baseline across lots", function()
        local list = OwnList.new()
        list:ingest({ lot(1, 60, 0), lot(2, 40, 0, { keyString = "i:13759:45:0:0", itemID = 13759 }) }, 100)
        list:ingest({ lot(1, 30, 0), lot(2, 40, 0, { keyString = "i:13759:45:0:0", itemID = 13759 }) }, 200)
        local summary = list:keySummary()
        assert.equals(30, summary[KEY].quantity)
        assert.equals(60, summary[KEY].baseline)
        assert.equals(40, summary["i:13759:45:0:0"].quantity)
        assert.equals(1, summary[KEY].lots)
    end)
end)
