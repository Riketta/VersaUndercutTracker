local Types = require("VersaUndercutTracker.domain.types")

describe("domain types", function()
    it("validates wire item keys", function()
        assert.is_true(Types.isItemKey({ itemID = 13935, itemLevel = 55, itemSuffix = 0, battlePetSpeciesID = 0 }))
        assert.is_false(Types.isItemKey({ itemID = 0, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }))
        assert.is_false(Types.isItemKey({ itemID = "x", itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }))
        assert.is_false(Types.isItemKey(nil))
        assert.is_false(Types.isItemKey({ itemID = 1, itemLevel = -1, itemSuffix = 0, battlePetSpeciesID = 0 }))
    end)

    it("builds the canonical key string", function()
        assert.equals(
            "i:10123:57:14327:0",
            Types.keyString({ itemID = 10123, itemLevel = 57, itemSuffix = 14327, battlePetSpeciesID = 0 })
        )
    end)

    it("sanitizes own lots and computes unit prices per verified wire semantics", function()
        -- Active commodity record: buyoutAmount IS the unit price (verified).
        local lot = Types.sanitizeOwnLot({
            auctionID = 178364562,
            itemKey = { itemID = 13935, itemLevel = 55, itemSuffix = 0, battlePetSpeciesID = 0 },
            quantity = 60,
            status = 0,
            buyoutAmount = 954,
            timeLeftSeconds = 6876,
        }, true)
        assert.is_not_nil(lot)
        ---@cast lot OwnLot
        assert.equals(954, lot.unitPrice)
        assert.equals("i:13935:55:0:0", lot.keyString)

        -- Item record: unit price derived by dividing the stack total.
        local item = Types.sanitizeOwnLot({
            auctionID = 178228136,
            itemKey = { itemID = 10123, itemLevel = 57, itemSuffix = 14327, battlePetSpeciesID = 0 },
            quantity = 1,
            status = 0,
            buyoutAmount = 17700,
        }, false)
        ---@cast item OwnLot
        assert.equals(17700, item.unitPrice)

        -- Ledger (Sold) record: buyoutAmount is the sale total (qty * unit).
        local sale = Types.sanitizeOwnLot({
            auctionID = 178444927,
            itemKey = { itemID = 13935, itemLevel = 55, itemSuffix = 0, battlePetSpeciesID = 0 },
            quantity = 11,
            status = 1,
            buyoutAmount = 10494,
        }, true)
        assert.is_not_nil(sale)
        ---@cast sale OwnLot
        assert.equals(1, sale.status)
    end)

    it("drops malformed own records at the boundary", function()
        assert.is_nil(Types.sanitizeOwnLot(nil))
        assert.is_nil(Types.sanitizeOwnLot({ auctionID = 1 }))
        assert.is_nil(Types.sanitizeOwnLot({
            auctionID = 1,
            itemKey = { itemID = 13935, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
            quantity = 0,
            status = 0,
        }))
        assert.is_nil(Types.sanitizeOwnLot({
            auctionID = 1,
            itemKey = { itemID = 13935, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
            quantity = 1,
            status = 2,
        }))
    end)

    it("sanitizes market rows including the merged multi-owner shape", function()
        local row = Types.sanitizeMarketRow({
            auctionID = 178181589,
            unitPrice = 954,
            quantity = 615,
            containsOwnerItem = true,
            containsAccountItem = true,
            numOwnerItems = 60,
            totalNumberOfOwners = 5,
            owners = { "player", "A", "B" },
        })
        assert.is_not_nil(row)
        ---@cast row MarketRow
        assert.is_true(row.isOwn)
        assert.equals(60, row.ownUnits)
        assert.equals(615, row.quantity)

        assert.is_nil(Types.sanitizeMarketRow({ auctionID = 1, unitPrice = 0, quantity = 5 }))
        assert.is_nil(Types.sanitizeMarketRow("junk"))
    end)

    it("formats money", function()
        assert.equals("0c", Types.money(0))
        assert.equals("5s", Types.money(500))
        assert.equals("12g 34s 56c", Types.money(123456))
        assert.equals("?", Types.money(-1))
        assert.equals("?", Types.money(1.5))
    end)
end)
