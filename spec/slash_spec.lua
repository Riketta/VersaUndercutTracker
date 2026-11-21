-- luacheck: globals SlashCmdList SLASH_VUT1
require("VersaUndercutTracker.domain.types")
require("VersaUndercutTracker.domain.config")
local Slash = require("VersaUndercutTracker.adapters.inbound.slash")

describe("slash adapter (pure parsing)", function()
    local calls, handler

    before_each(function()
        calls = {}
        local console = {
            setChannel = function(_, kind, channel, enabled)
                calls[#calls + 1] = { "channel", kind, channel, enabled }
                return true, ("channel %s.%s = %s"):format(kind, channel, tostring(enabled))
            end,
            setCooldown = function(_, kind, seconds)
                calls[#calls + 1] = { "cooldown", kind, seconds }
                return true, ("cooldown.%s = %s"):format(kind, tostring(seconds))
            end,
        }
        SlashCmdList = {}
        ---@diagnostic disable-next-line: assign-type-mismatch
        Slash.register(console)
        handler = SlashCmdList.VUT
    end)

    it("registers the /vut slash command", function()
        assert.is_not_nil(handler)
        assert.equals("/vut", SLASH_VUT1)
    end)

    it("splits kind.channel on the literal dot", function()
        -- regression: the pattern used a bare . (wildcard) and parsed
        -- "tied.sound" as kind "tied.sou" + channel "d" -> "unknown kind"
        handler("channel tied.sound on")
        assert.equals(1, #calls)
        assert.equals("channel", calls[1][1])
        assert.equals("tied", calls[1][2])
        assert.equals("sound", calls[1][3])
        assert.is_true(calls[1][4])
    end)

    it("parses every channel toggle shape", function()
        handler("channel tied.flash on")
        handler("channel undercut.chat off")
        assert.equals(2, #calls)
        assert.equals("tied", calls[1][2])
        assert.equals("flash", calls[1][3])
        assert.is_true(calls[1][4])
        assert.equals("undercut", calls[2][2])
        assert.equals("chat", calls[2][3])
        assert.is_false(calls[2][4])
    end)

    it("rejects malformed channel args without touching the console", function()
        handler("channel tied sound on")
        handler("channel tied.sound maybe")
        handler("channel sound on")
        assert.equals(0, #calls)
    end)

    it("parses cooldown commands", function()
        handler("cooldown tied 120")
        assert.equals(1, #calls)
        assert.equals("cooldown", calls[1][1])
        assert.equals("tied", calls[1][2])
        assert.equals(120, calls[1][3])
    end)
end)
