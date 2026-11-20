local Config = require("VersaUndercutTracker.domain.config")

describe("domain config", function()
    it("defaults every knob inside its clamp range", function()
        local s = Config.defaults()
        assert.equals(10, s.ownedPollSeconds)
        assert.equals(8, s.commodityPollSeconds)
        assert.equals("auto", s.itemChannel)
        assert.equals(25, s.lowQuantityPct)
        for _, kind in ipairs(Config.KINDS) do
            assert.is_not_nil(s.channels[kind])
            assert.is_not_nil(s.cooldownSeconds[kind])
        end
        assert.is_true(s.channels.undercut.sound)
        assert.is_true(s.channels.undercut.flash)
        assert.is_false(s.channels.tied.sound)
    end)

    it("coerces an untrusted blob: clamps, whitelists, defaults", function()
        local s = Config.coerce({
            ownedPollSeconds = 9999,
            commodityPollSeconds = "junk",
            itemChannel = " nonsense ",
            lowQuantityPct = -5,
            soundFile = "",
            cooldownSeconds = { undercut = -100 },
            channels = { undercut = { sound = false, bogus = true }, junkkind = { chat = false } },
        })
        assert.equals(120, s.ownedPollSeconds)
        assert.equals(8, s.commodityPollSeconds)
        assert.equals("auto", s.itemChannel)
        assert.equals(0, s.lowQuantityPct)
        assert.is_nil(s.soundFile)
        assert.equals(0, s.cooldownSeconds.undercut)
        assert.is_false(s.channels.undercut.sound)
        assert.is_nil(s.channels.junkkind)
        -- untouched kinds keep defaults
        assert.is_true(s.channels.noactive.flash)
    end)

    it("coerces the sound kit to a symbolic name, rejecting junk", function()
        local s = Config.coerce({ soundKit = 8960 })
        assert.equals("AUCTION_WINDOW_OPEN", s.soundKit)
        s = Config.coerce({ soundKit = "LOOT_WINDOW_COIN_SOUND" })
        assert.equals("LOOT_WINDOW_COIN_SOUND", s.soundKit)
        s = Config.coerce({ soundKit = "" })
        assert.equals("AUCTION_WINDOW_OPEN", s.soundKit)
    end)

    it("coerces total junk into pure defaults without aliasing", function()
        local junk = { channels = "no" }
        local s = Config.coerce(junk)
        assert.equals(10, s.ownedPollSeconds)
        assert.is_not_nil(s.channels.undercut)
        junk.ownedPollSeconds = 1
        assert.equals(10, s.ownedPollSeconds)
    end)
end)
