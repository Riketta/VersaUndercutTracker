-- Wire facts pinned here (verified in game, 2026-11):
--   * commodity rows arrive in MATCH order: unitPrice ASC, NEWEST first
--     within a tier ("last placed sells first" - the delivered order IS the
--     buy order, no reversal);
--   * rows can merge several owners; own units ride inside via ownUnits;
--   * item rows are per-listing with per-unit prices derived from totals;
--   * item display order = delivered row order, and buyers buy top-down, so
--     the position inside the cheapest tier is the delivered index.

local Queue = require("VersaUndercutTracker.domain.queue")

local function row(unitPrice, quantity, ownUnits)
    return {
        auctionID = math.floor(unitPrice * 1000 + quantity),
        unitPrice = unitPrice,
        quantity = quantity,
        ownUnits = ownUnits or 0,
        isOwn = (ownUnits or 0) > 0,
        ownersCount = 1,
    }
end

describe("domain queue", function()
    it("GONE on empty rows or when no own row is present", function()
        assert.equals("GONE", Queue.commodity({}).state)
        local verdict = Queue.commodity({ row(954, 3), row(955, 462) })
        assert.equals("GONE", verdict.state)
        assert.equals(954, verdict.cheapest)
    end)

    it("FIRST when the first row already contains own units (merged row)", function()
        -- The real 13935 dump shape: one merged 954 row, 615 units, 60 ours.
        local verdict = Queue.commodity({ row(954, 615, 60), row(955, 462), row(2899, 10) })
        assert.equals("FIRST", verdict.state)
        assert.equals(954, verdict.ownMin)
        assert.equals(615, verdict.tierUnits)
    end)

    it("TIED with unitsAhead when newer sellers share the price", function()
        -- Delivered order: newest 954 row first (match order), ours behind.
        local verdict = Queue.commodity({ row(954, 3), row(954, 60, 60), row(955, 462) })
        assert.equals("TIED", verdict.state)
        assert.equals(3, verdict.unitsAhead)
        assert.equals(63, verdict.tierUnits)
    end)

    it("UNDERCUT when a cheaper competitor tier exists", function()
        local verdict = Queue.commodity({ row(950, 100), row(954, 60, 60) })
        assert.equals("UNDERCUT", verdict.state)
        assert.equals(954, verdict.ownMin)
        assert.equals(950, verdict.cheapest)
        assert.equals(4, verdict.by)
    end)

    it("item verdicts: first / tied / undercut from per-listing rows", function()
        local function irow(unit, own, qty)
            return {
                auctionID = unit,
                unitPrice = unit,
                buyoutTotal = unit,
                quantity = qty or 1,
                isOwn = own == true,
            }
        end
        assert.equals("FIRST", Queue.item({ irow(17700, true), irow(18000) }).state)
        -- own listing at the TOP of the tied tier: first in display order
        assert.equals("FIRST", Queue.item({ irow(17700, true), irow(17700) }).state)
        -- foreign ties displayed ABOVE own: own is behind them
        local tied = Queue.item({ irow(17700), irow(17700, true) })
        assert.equals("TIED", tied.state)
        assert.equals(1, tied.tiedCount)
        assert.equals(1, tied.rowsAhead)
        assert.equals(1, tied.unitsAhead)
        -- stacked listing ahead: one row, its whole quantity sells first
        local stacked = Queue.item({ irow(17700, false, 20), irow(17700, true) })
        assert.equals("TIED", stacked.state)
        assert.equals(1, stacked.rowsAhead)
        assert.equals(20, stacked.unitsAhead)
        local under = Queue.item({ irow(15000), irow(17700, true) })
        assert.equals("UNDERCUT", under.state)
        assert.equals(2700, under.by)
        assert.equals(1, under.cheaperCount)
        assert.equals("GONE", Queue.item({}).state)
    end)
end)
