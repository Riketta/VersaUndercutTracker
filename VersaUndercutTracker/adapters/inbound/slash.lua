-- VUT - slash adapter. Pure text parsing over the console
-- adapter's machine API; no logic of its own.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local Config = V.domain.Config

local Slash = {}

local function reply(text)
    print("|cff33ccffVUT|r " .. text)
end

local function parseValue(text)
    if text == "true" or text == "on" then
        return true
    elseif text == "false" or text == "off" then
        return false
    end
    return tonumber(text) or text
end

local function help()
    reply("commands:")
    reply("  status                       session, lots, verdicts, channel state")
    reply("  scan                         refresh owned + poll every commodity now")
    reply("  pause | resume               stop/resume monitoring beats")
    reply("  probe                        re-run the item refresh gate probe")
    reply("  set <key> <value>            owned|commodity|rotation|lowpct|sound|soundfile|flash|toast|items")
    reply("  cooldown <kind> <seconds>    per-kind alert cooldown")
    reply("  channel <kind> <ch> on|off   ch: chat|sound|flash|toast")
    reply("  test <kind>                  dispatch a test alert through the bus")
    reply("kinds: " .. table.concat(Config.KINDS, ", "))
end

local function status(console)
    local s = console:status()
    reply(
        ("session=%s paused=%s baseline=%s lots=%d keys=%d"):format(
            tostring(s.session),
            tostring(s.paused),
            tostring(s.ownedBaseline),
            s.activeLots,
            s.activeKeys
        )
    )
    reply(("items: channel=%s probe=%s"):format(s.itemChannel, s.itemProbe))
    if s.lastCommodityQuery then
        reply(("last commodity query: #%d (%ds ago)"):format(s.lastCommodityQuery.itemID, s.lastCommodityQuery.age))
    end
    local any = false
    local keys = {}
    for keyString in pairs(s.verdicts) do
        keys[#keys + 1] = keyString
    end
    table.sort(keys)
    for _, keyString in ipairs(keys) do
        any = true
        reply(("  %s -> %s (%ds ago)"):format(keyString, s.verdicts[keyString], s.verdictAges[keyString] or 0))
    end
    if not any then
        reply("  no verdicts yet (open the auction house)")
    end
end

---@param console ConsoleAdapter
function Slash.register(console)
    SLASH_VUT1 = "/vut"
    SlashCmdList["VUT"] = function(msg)
        local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
        local a, b = rest:match("^(%S*)%s*(.*)$")
        cmd = cmd:lower()
        if cmd == "" or cmd == "help" then
            help()
        elseif cmd == "status" then
            status(console)
        elseif cmd == "scan" then
            reply((select(2, console:scanNow())))
        elseif cmd == "pause" then
            reply((select(2, console:pause())))
        elseif cmd == "resume" then
            reply((select(2, console:resume())))
        elseif cmd == "probe" then
            reply((select(2, console:probe())))
        elseif cmd == "set" then
            if a == "" or b == "" then
                reply("usage: set <key> <value>")
            else
                local ok, text = console:set(a, parseValue(b))
                reply((ok and text) or ("error: " .. text))
            end
        elseif cmd == "cooldown" then
            local seconds = tonumber(b)
            if a == "" or seconds == nil then
                reply("usage: cooldown <kind> <seconds>")
            else
                reply((select(2, console:setCooldown(a, seconds))))
            end
        elseif cmd == "channel" then
            -- %. is a LITERAL dot: kind and channel split on it (a bare . is a
            -- wildcard and parsed "tied.sound" as kind "tied.sou", channel "d")
            local kind, channel = a:match("^(%S+)%.(%S+)$")
            if kind and channel and (b == "on" or b == "off") then
                reply((select(2, console:setChannel(kind, channel, b == "on"))))
            else
                reply("usage: channel <kind>.<chat|sound|flash|toast> on|off")
            end
        elseif cmd == "test" then
            if a == "" then
                reply("usage: test <kind>")
            else
                reply((select(2, console:test(a))))
            end
        else
            reply("unknown command: " .. cmd .. " (try /vut help)")
        end
    end
end

V.adapters.SlashAdapter = Slash
return Slash
