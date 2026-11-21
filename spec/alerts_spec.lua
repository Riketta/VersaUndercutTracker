require("VersaUndercutTracker.domain.types")
local Alerts = require("VersaUndercutTracker.domain.alerts")

describe("domain alerts", function()
    it("gates repeats by per-kind cooldown and tag", function()
        local settings = { cooldownSeconds = { undercut = 120, sold = 20 } }
        local policy = Alerts.new(settings)
        assert.is_true(policy:gate("undercut", "i:1:0:0:0", 100))
        assert.is_false(policy:gate("undercut", "i:1:0:0:0", 150))
        assert.is_true(policy:gate("undercut", "i:1:0:0:0", 221))
        -- different key: independent
        assert.is_true(policy:gate("undercut", "i:2:0:0:0", 150))
        -- different tag: independent (sale dedup pairs on quantity)
        assert.is_true(policy:gate("sold", "i:1:0:0:0", 100, "11"))
        assert.is_false(policy:gate("sold", "i:1:0:0:0", 105, "11"))
        assert.is_true(policy:gate("sold", "i:1:0:0:0", 105, "14"))
    end)

    it("resetMarket clears only this key's undercut/tied stamps", function()
        local settings = { cooldownSeconds = { undercut = 120, tied = 300, sold = 20 } }
        local policy = Alerts.new(settings)
        assert.is_true(policy:gate("tied", "i:1:0:0:0", 100))
        assert.is_true(policy:gate("undercut", "i:1:0:0:0", 100))
        assert.is_true(policy:gate("tied", "i:2:0:0:0", 100))
        assert.is_true(policy:gate("sold", "i:1:0:0:0", 100, "5"))
        policy:resetMarket("i:1:0:0:0")
        -- cleared kinds on the reset key re-fire immediately
        assert.is_true(policy:gate("tied", "i:1:0:0:0", 105))
        assert.is_true(policy:gate("undercut", "i:1:0:0:0", 105))
        -- other keys and kinds keep their stamps
        assert.is_false(policy:gate("tied", "i:2:0:0:0", 105))
        assert.is_false(policy:gate("sold", "i:1:0:0:0", 105, "5"))
    end)

    it("builds messages for every kind", function()
        assert.equals(
            "[Copper Bar] undercut by 1g 23s 45c (market 9s 54c, yours 10g 77s 89c)",
            Alerts.text("undercut", "Copper Bar", { by = 12345, cheapest = 954, ownMin = 107789 })
        )
        assert.equals(
            "[Herb] tied at market min 9s 54c - 61 units sell before yours",
            Alerts.text("tied", "Herb", { ownMin = 954, unitsAhead = 61 })
        )
        -- item listings count rows, not units (one buyer takes one listing)
        assert.equals(
            "[Bracers] tied at market min 6g 33s - 2 listings sell before yours",
            Alerts.text("tied", "Bracers", { ownMin = 63300, rowsAhead = 2, unitsAhead = 2 })
        )
        assert.equals("[Herb] sold 11 for 1g 4s 94c", Alerts.text("sold", "Herb", { quantity = 11, gold = 10494 }))
        assert.equals("[Herb] sold 11", Alerts.text("sold", "Herb", { quantity = 11 }))
        assert.equals("[Herb] expired - relist?", Alerts.text("expired", "Herb", {}))
        assert.equals("[Herb] canceled", Alerts.text("canceled", "Herb", {}))
        assert.equals(
            "[Herb] low: 10 of 60 left (17%)",
            Alerts.text("lowqty", "Herb", { quantity = 10, baseline = 60, pct = 17 })
        )
        assert.equals("[Herb] sold out - no active lots", Alerts.text("noactive", "Herb", {}))
        assert.equals("[Herb] back to first in queue", Alerts.text("recovered", "Herb", {}))
    end)

    it("maps severities", function()
        assert.equals("alert", Alerts.SEVERITY.undercut)
        assert.equals("alert", Alerts.SEVERITY.noactive)
        assert.equals("warn", Alerts.SEVERITY.tied)
        assert.equals("info", Alerts.SEVERITY.sold)
    end)
end)
