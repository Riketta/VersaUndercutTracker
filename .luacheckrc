-- VUT lint + architecture boundary rules.
--
-- Hexagonal boundary enforcement:
--   * VersaUndercutTracker/domain and VersaUndercutTracker/ports get NO game
--     globals beyond the namespace: any WoW API reference fails CI.
--   * VersaUndercutTracker/adapters and ui get the explicit WoW API allowlist.
--   * VUTProbe is a dev-only probe addon: same WoW allowlist plus its own
--     slash globals.
--   * spec files get the busted harness globals.

std = "lua51"
cache = true

max_line_length = 150
self = false

exclude_files = { "tools/**" }

globals = {
    "VUT",
    "VUTDB",
}

-- The config chunk itself runs under luacheck's host interpreter, which may
-- be 5.3+ where bare unpack no longer exists.
local expand = table.unpack or unpack

local wow_api = {
    "AuctionHouseFrame",
    "C_AuctionHouse",
    "C_Item",
    "C_Timer",
    "CreateFrame",
    "Enum",
    "GameTooltip",
    "GetTime",
    "hooksecurefunc",
    "PlaySound",
    "PlaySoundFile",
    "ScrollUtil",
    "SOUNDKIT",
    "UIParent",
    "time",
}

files["VersaUndercutTracker/domain"] = {
    globals = { "VUT" },
}

files["VersaUndercutTracker/ports"] = {
    globals = { "VUT" },
}

files["VersaUndercutTracker/adapters"] = {
    globals = {
        "VUT",
        "SLASH_VUT1",
        "SlashCmdList",
        expand(wow_api),
    },
}

files["VersaUndercutTracker/ui"] = {
    globals = {
        "VUT",
        expand(wow_api),
    },
}

-- The composition root sits outside adapters/ but builds the loader frame.
files["VersaUndercutTracker/bootstrap.lua"] = {
    globals = {
        "VUT",
        "CreateFrame",
    },
}

files["VUTProbe"] = {
    globals = {
        "VUTProbe",
        "SLASH_VUTPROBE1",
        "SLASH_VUTPROBE2",
        "SlashCmdList",
        expand(wow_api),
    },
}

files["scripts"] = {
    globals = {
        "assert",
        "describe",
        "it",
        "before_each",
        "after_each",
        "setup",
        "teardown",
    },
}

files["spec"] = {
    globals = {
        "describe",
        "it",
        "before_each",
        "after_each",
        "setup",
        "teardown",
    },
}
