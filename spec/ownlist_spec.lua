local OwnList = require("VersaUndercutTracker.domain.ownlist")

local KEY = "i:13935:55:0:0"

local function copyOf(record)
    local out = {}
    for key, value in pairs(record) do
        out[key] = value
    end
    return out
end

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

    it("classifies closures inside the cancel window as canceled without id match", function()
        -- The fork's cancel payloads are NOT owned auctionIDs (verified:
        -- garbage value 110), so attribution must not rely on the argument.
        local list = OwnList.new()
        list:ingest({ lot(7, 3, 0, { timeLeft = 7200 }) }, 100)
        list:openCancelWindow(105, 10)
        local events = list:ingest({}, 110)
        assert.equals(1, #events)
        assert.equals("canceled", events[1].reason)
        -- after the window closes, disappearances are sales again
        list:ingest({ lot(8, 1, 0, { timeLeft = 7200 }) }, 200)
        local later = list:ingest({}, 300)
        assert.equals("sold", later[1].reason)
    end)

    it("marks ledger rows born in the cancel window and suppresses their gold", function()
        local list = OwnList.new()
        local record = lot(42, 11, 1, { buyout = 10494 })
        list:openCancelWindow(100, 10)
        local events = list:ingest({ record }, 105)
        assert.equals(1, #events)
        assert.equals("sale", events[1].type)
        assert.is_true(events[1].inCancelWindow)
        -- accounted: not re-emitted later
        assert.equals(0, #list:ingest({ record }, 300))
    end)

    it("counts identical-signature ledger rows as separate sales", function()
        -- Verified in game: one listing's repeat partial sales coexist as
        -- multiple rows with the SAME (auctionID, qty, gold) - signature
        -- GROWTH is the sale signal, not presence.
        local list = OwnList.new()
        local record = lot(178161993, 1, 1, { buyout = 11000 })
        local events = list:ingest({ record }, 100)
        assert.equals(1, #events)
        assert.equals("sale", events[1].type)
        assert.equals(1, events[1].quantity)
        assert.equals(11000, events[1].gold)
        assert.equals(KEY, events[1].keyString)
        -- a different-signature sale on the same listing also emits
        events = list:ingest({ record, lot(178161993, 2, 1, { buyout = 22000 }) }, 150)
        assert.equals(1, #events)
        assert.equals(2, events[1].quantity)
        -- a second identical row appears: one more sale
        events = list:ingest({ record, copyOf(record), lot(178161993, 2, 1, { buyout = 22000 }) }, 200)
        assert.equals(1, #events)
        -- same rows again: silent
        assert.equals(0, #list:ingest({ record, copyOf(record), lot(178161993, 2, 1, { buyout = 22000 }) }, 300))
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
