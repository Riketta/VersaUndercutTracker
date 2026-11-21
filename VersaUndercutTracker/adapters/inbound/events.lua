-- VUT - game event adapter. The ONLY file that registers
-- auction house events; it forwards them to the core and the timer driver
-- over the inbound port contract. Event payloads are hints on this fork (the
-- owned-snapshot diff is the lifecycle truth) - see domain/ownlist.lua.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local EVENTS = {
    "PLAYER_LOGIN",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "OWNED_AUCTIONS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_RECEIVED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PURCHASED",
    "AUCTION_HOUSE_AUCTIONS_EXPIRED",
    "AUCTION_CANCELED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
}

---@class EventsAdapter
---@field core table ControlPort implementor
---@field driver table TimerDriver
---@field settings Settings
local Events = {}
Events.__index = Events

---@param core table
---@param driver table
---@param settings Settings
---@return EventsAdapter
function Events.new(core, driver, settings)
    local self = setmetatable({ core = core, driver = driver, settings = settings }, Events)
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        self:dispatch(event, ...)
    end)
    for _, event in ipairs(EVENTS) do
        frame:RegisterEvent(event)
    end
    -- Post-hook the cancel API so the owned-diff classifier can tell a user
    -- cancel from a sale (post-hooks only - never a replacement).
    if C_AuctionHouse and C_AuctionHouse.CancelAuction then
        hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID)
            if type(auctionID) == "number" then
                core:markCancelRequested(auctionID)
            end
        end)
    end
    return self
end

function Events:dispatch(event, ...)
    local core = self.core
    if event == "PLAYER_LOGIN" then
        core:onStartup()
    elseif event == "AUCTION_HOUSE_SHOW" then
        core:onAhOpen()
        self.driver:start(core, self.settings)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        core:onAhClose()
        self.driver:stop()
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        core:onOwnedUpdated()
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = ...
        if type(itemID) == "number" then
            core:onCommodityRows(itemID)
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_RECEIVED" then
        -- Payload-less on this fork: the core re-verdicts its last query.
        core:onCommodityReceived()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemKey = ...
        if type(itemKey) == "table" then
            core:onItemRows(itemKey)
        end
    elseif event == "COMMODITY_PURCHASED" then
        local itemID, quantity = ...
        if type(itemID) == "number" and type(quantity) == "number" then
            core:onCommodityPurchased(itemID, quantity)
        end
    elseif event == "AUCTION_HOUSE_AUCTIONS_EXPIRED" then
        local auctionID = ...
        if type(auctionID) == "number" then
            core:onExpiredHint(auctionID)
        end
    elseif event == "AUCTION_CANCELED" then
        -- Payload is NOT an auctionID on this fork (verified: garbage value);
        -- just pull a fresh owned snapshot - the diff classifies.
        core:onCanceledHint()
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        core:onThrottleDrop()
    end
end

V.adapters.EventsAdapter = Events
return Events
