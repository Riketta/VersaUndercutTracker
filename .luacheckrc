# VUT lint + architecture boundary rules.
#
# Hexagonal boundary enforcement:
#   * VersaUndercutTracker/domain and VersaUndercutTracker/ports get NO game
#     globals beyond the namespace: any WoW API reference fails CI.
#   * VersaUndercutTracker/adapters and ui get the explicit WoW API allowlist.
#   * VUTProbe is a dev-only probe addon: same WoW allowlist plus its own
#     slash globals.
#   * spec files get the busted harness globals.

std = "lua51"
cache = true

max_line_length = 150
self = false

exclude_files = { "tools/**" }

globals = {
    "VUT",
    "VUTDB",
}

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
        unpack(wow_api),
    },
}

files["VersaUndercutTracker/ui"] = {
    globals = {
        "VUT",
        unpack(wow_api),
    },
}

files["VUTProbe"] = {
    globals = {
        "VUTProbe",
        "SLASH_VUTPROBE1",
        "SLASH_VUTPROBE2",
        "SlashCmdList",
        unpack(wow_api),
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
