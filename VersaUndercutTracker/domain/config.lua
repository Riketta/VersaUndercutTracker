-- VUT - settings model: defaults, clamps, untrusted-blob
-- coercion. The SavedVariables blob is NEVER trusted: coerce() rebuilds every
-- field from scratch, defaults what is absent, clamps what is out of range,
-- and never aliases input tables.

local V = _G.VUT or {}
_G.VUT = V
V.domain = V.domain or {}

local Config = {}

--- Alert kinds the system knows. Channel routing and cooldowns key on these.
Config.KINDS = { "undercut", "tied", "sold", "expired", "canceled", "lowqty", "noactive", "recovered" }

--- Item competitor-data channel: "auto" = refresh-probe first, degrading
--- to passive when the gate refuses (no UI interference); "passive" = only
--- opportunistic reads while the user browses; "click" = opt-in summary
--- click rotation (moves the Auctions tab selection); "off" = unmonitored.
Config.ITEM_CHANNELS = { auto = true, passive = true, click = true, off = true }

---@param n number|nil
---@param lo number
---@param hi number
---@param def number
---@return number
local function clampNum(n, lo, hi, def)
    if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
        return def
    end
    return math.min(hi, math.max(lo, n))
end

---@param s any
---@param def string
---@return string
local function channelOf(s, def)
    if type(s) == "string" and Config.ITEM_CHANNELS[s] then
        return s
    end
    return def
end

--- The default channel matrix per kind: chat always; sound/flash for the
--- states that need pulling eyes back to the screen; toast for everything
--- except canceled (noise).
local DEFAULT_CHANNELS = {
    undercut = { chat = true, sound = true, flash = true, toast = true },
    tied = { chat = true, sound = false, flash = false, toast = true },
    sold = { chat = true, sound = false, flash = false, toast = true },
    expired = { chat = true, sound = false, flash = false, toast = true },
    canceled = { chat = false, sound = false, flash = false, toast = false },
    lowqty = { chat = true, sound = true, flash = false, toast = true },
    noactive = { chat = true, sound = true, flash = true, toast = true },
    recovered = { chat = true, sound = false, flash = false, toast = false },
}

local DEFAULT_COOLDOWNS = {
    undercut = 120,
    tied = 300,
    sold = 20,
    expired = 20,
    canceled = 0,
    lowqty = 600,
    noactive = 600,
    recovered = 0,
}

--- A fully-defaulted settings table.
---@return Settings
function Config.defaults()
    local channels = {}
    local cooldowns = {}
    for _, kind in ipairs(Config.KINDS) do
        local row = DEFAULT_CHANNELS[kind]
        channels[kind] = { chat = row.chat, sound = row.sound, flash = row.flash, toast = row.toast }
        cooldowns[kind] = DEFAULT_COOLDOWNS[kind]
    end
    ---@class Settings
    ---@field ownedPollSeconds number owned-list refresh cadence (5..120)
    ---@field commodityPollSeconds number per-item commodity rotation beat (5..300)
    ---@field itemChannel string auto|passive|click|off
    ---@field itemRotationSeconds number item rotation beat (10..600)
    ---@field lowQuantityPct number alert when remaining <= this % of first-seen (0 = off, 0..100)
    ---@field cooldownSeconds table<string, number> per-kind alert cooldown seconds
    ---@field channels table<string, table<string, boolean>> kind -> channel -> enabled
    ---@field soundKit string SOUNDKIT symbolic name (resolved at play time)
    ---@field soundFile string|nil custom media path (wins over soundKit when set)
    ---@field flashSeconds number screen-flash duration (0.5..5)
    ---@field toastSeconds number toast lifetime (2..15)
    return {
        ownedPollSeconds = 10,
        commodityPollSeconds = 8,
        itemChannel = "auto",
        itemRotationSeconds = 30,
        lowQuantityPct = 25,
        cooldownSeconds = cooldowns,
        channels = channels,
        soundKit = "AUCTION_WINDOW_OPEN",
        soundFile = nil,
        flashSeconds = 1.5,
        toastSeconds = 6,
    }
end

---@param untrusted any raw SavedVariables settings blob
---@return Settings
function Config.coerce(untrusted)
    local out = Config.defaults()
    if type(untrusted) ~= "table" then
        return out
    end
    out.ownedPollSeconds = clampNum(untrusted.ownedPollSeconds, 5, 120, out.ownedPollSeconds)
    out.commodityPollSeconds = clampNum(untrusted.commodityPollSeconds, 5, 300, out.commodityPollSeconds)
    out.itemRotationSeconds = clampNum(untrusted.itemRotationSeconds, 10, 600, out.itemRotationSeconds)
    out.itemChannel = channelOf(untrusted.itemChannel, out.itemChannel)
    out.lowQuantityPct = clampNum(untrusted.lowQuantityPct, 0, 100, out.lowQuantityPct)
    out.soundKit = "AUCTION_WINDOW_OPEN"
    if type(untrusted.soundKit) == "string" and #untrusted.soundKit > 0 then
        out.soundKit = untrusted.soundKit
    end
    if type(untrusted.soundFile) == "string" and #untrusted.soundFile > 0 then
        out.soundFile = untrusted.soundFile
    end
    out.flashSeconds = clampNum(untrusted.flashSeconds, 0.5, 5, out.flashSeconds)
    out.toastSeconds = clampNum(untrusted.toastSeconds, 2, 15, out.toastSeconds)
    if type(untrusted.cooldownSeconds) == "table" then
        for _, kind in ipairs(Config.KINDS) do
            out.cooldownSeconds[kind] =
                math.floor(clampNum(untrusted.cooldownSeconds[kind], 0, 86400, out.cooldownSeconds[kind]) + 0.5)
        end
    end
    if type(untrusted.channels) == "table" then
        for _, kind in ipairs(Config.KINDS) do
            local row = untrusted.channels[kind]
            if type(row) == "table" then
                for _, channel in ipairs({ "chat", "sound", "flash", "toast" }) do
                    if type(row[channel]) == "boolean" then
                        out.channels[kind][channel] = row[channel]
                    end
                end
            end
        end
    end
    return out
end

V.domain.Config = Config
return Config
