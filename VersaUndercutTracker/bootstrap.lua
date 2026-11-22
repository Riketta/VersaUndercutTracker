-- VUT - composition root. The ONLY place that instantiates
-- adapters and injects ports; everything else depends on contracts.
--
-- Construction is deferred to ADDON_LOADED: SavedVariables only exist then,
-- and the store must anchor to the real global table or writes land on an
-- orphan WoW never persists.

local V = _G.VUT or {}
_G.VUT = V

local function build()
    -- SavedVariables anchor (account-wide, settings only).
    VUTDB = VUTDB or {}

    local persist = V.adapters.SavedVarsAdapter.new(VUTDB)
    local settings = persist:load()
    local clock = V.adapters.ClockAdapter.new()
    local itemInfo = V.adapters.ItemInfoAdapter.new()
    local owned = V.adapters.OwnedAdapter.new(itemInfo)
    local market = V.adapters.MarketAdapter.new()
    local bus = V.adapters.NotifierBus.new({
        { name = "chat", adapter = V.adapters.ChatNotifier.new() },
        { name = "sound", adapter = V.adapters.SoundNotifier.new(settings) },
        { name = "flash", adapter = V.adapters.FlashNotifier.new(settings) },
        { name = "toast", adapter = V.adapters.ToastNotifier.new(settings) },
    })
    local core = V.domain.Core.new({
        settings = settings,
        ownedPort = owned,
        marketPort = market,
        notify = bus,
        clock = clock,
        itemInfo = itemInfo,
        persist = persist,
    })
    local driver = V.adapters.TimerDriver.new()

    -- Machine API + slash share the console adapter; settings writes restart
    -- the beat timers (cadence knobs take effect immediately). Built before
    -- the events adapter so its AUCTION_HOUSE_SHOW hook can reach it.
    local console = V.adapters.ConsoleAdapter.new({
        core = core,
        settings = settings,
        persist = persist,
        onSettingsChanged = function()
            driver:restart(core, settings)
        end,
    })
    V.adapters.SlashAdapter.register(console)
    V.api = console

    V.adapters.EventsAdapter.new(core, driver, settings, {
        -- The pause button lives in the AH frame chrome; the frame is
        -- LoadOnDemand, so attach when it certainly exists (AH open). Guarded:
        -- a missing UI module must never break the event handler.
        onAhOpen = function()
            local pauseButton = V.ui and V.ui.PauseButton
            if pauseButton then
                pauseButton.attach(console)
            end
        end,
    })

    print("|cff33ccffVUT|r 0.1.0 loaded - /vut help")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "VersaUndercutTracker" then
        loader:UnregisterEvent("ADDON_LOADED")
        build()
    end
end)
