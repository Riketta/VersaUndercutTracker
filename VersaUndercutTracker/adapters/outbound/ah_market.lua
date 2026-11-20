-- VUT - market competitor adapter.
--
-- Channel mechanics (fork-verified):
--   * Commodity queries: SendSearchQuery from script PASSES the gate. The
--     wire doc caps searches at 100/min - the rotation beats stay far below.
--   * Item queries: SendSearchQuery/QueryItem from script are REFUSED (empty
--     result sets). refreshItem tries RefreshItemSearchResults for keys the
--     client already holds (the core probes it once per session and falls
--     back); clickItemScan drives the Auctions summary row's own OnClick
--     handler - the proven gate-clean path for items (same mechanism as the
--     search button click).
-- Rows are read only after the corresponding *UPDATED events fire; this
-- adapter never parses rendered UI rows - the data APIs behind the panes are
-- the same the panes themselves read.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local Types = V.domain.Types

---@class MarketAdapter : MarketPort
local Market = {}
Market.__index = Market

---@return MarketAdapter
function Market.new()
    return setmetatable({}, Market)
end

local function bareKey(itemID)
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

--- Fire one commodity search. Rows land via COMMODITY_SEARCH_RESULTS_UPDATED.
---@param itemID number
---@return boolean
function Market:queryCommodity(itemID)
    if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery) then
        return false
    end
    return (pcall(C_AuctionHouse.SendSearchQuery, bareKey(itemID), {}, false, 0, 0))
end

--- Read the held commodity rows (sanitized, delivered/match order preserved).
---@param itemID number
---@return MarketRow[]
function Market:readCommodityRows(itemID)
    local out = {}
    if
        not (
            C_AuctionHouse
            and C_AuctionHouse.GetCommoditySearchResultInfo
            and C_AuctionHouse.GetNumCommoditySearchResults
        )
    then
        return out
    end
    local okNum, num = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not okNum or type(num) ~= "number" then
        return out
    end
    for i = 1, num do
        local okRaw, raw = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if okRaw then
            local row = Types.sanitizeMarketRow(raw)
            if row then
                out[#out + 1] = row
            end
        end
    end
    return out
end

--- Attempt a refresh of item search results the client already holds. May be
--- gate-refused for items; the core probes once per session and falls back.
---@param itemKey table full wire key (itemID + variant pins from the owned lot)
---@return boolean
function Market:refreshItem(itemKey)
    if not (C_AuctionHouse and C_AuctionHouse.RefreshItemSearchResults) then
        return false
    end
    if not Types.isItemKey(itemKey) then
        return false
    end
    return (pcall(C_AuctionHouse.RefreshItemSearchResults, itemKey))
end

--- Read the held item rows (sanitized).
---@param itemKey table
---@return ItemRow[]
function Market:readItemRows(itemKey)
    local out = {}
    if not (C_AuctionHouse and C_AuctionHouse.GetItemSearchResultInfo and C_AuctionHouse.GetNumItemSearchResults) then
        return out
    end
    if not Types.isItemKey(itemKey) then
        return out
    end
    local okNum, num = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not okNum or type(num) ~= "number" then
        return out
    end
    for i = 1, num do
        local okRaw, raw = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if okRaw then
            local row = Types.sanitizeItemRow(raw)
            if row then
                out[#out + 1] = row
            end
        end
    end
    return out
end

-- ===== click rotation (gate-clean item channel) ==============================

local function summaryList()
    local auctions = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    local list = auctions and auctions.SummaryList
    local scrollBox = list and list.ScrollBox
    if scrollBox and scrollBox.FindFrame then
        return auctions, scrollBox
    end
    return nil
end

local function auctionsIsVisible()
    local auctions = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    return auctions ~= nil and auctions:IsVisible() == true
end

--- True when the Auctions tab summary surface exists and is visible.
---@return boolean
function Market:supportsItemClick()
    if not summaryList() then
        return false
    end
    return auctionsIsVisible()
end

--- Clicks the Auctions summary row for one owned item key. The row button's
--- own OnClick handler runs the query (gate-clean, the SearchButton:Click
--- mechanism); nothing is called on Blizzard mixins directly from addon
--- context. ALL row is list index 1, owned type rows are typeIndex + 1.
---@param itemID number
---@return boolean ok
---@return string|nil refusal reason
function Market:clickItemScan(itemID)
    local auctions, scrollBox = summaryList()
    if not auctions or not scrollBox then
        return false, "summary-unavailable"
    end
    if not auctionsIsVisible() then
        return false, "auctions-tab-hidden"
    end
    local finder = scrollBox.FindFrame
    if type(finder) ~= "function" then
        return false, "surface-missing"
    end
    if not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctionType and C_AuctionHouse.GetNumOwnedAuctionTypes) then
        return false, "types-unavailable"
    end
    local okNum, numTypes = pcall(C_AuctionHouse.GetNumOwnedAuctionTypes)
    if not okNum or type(numTypes) ~= "number" or numTypes <= 0 then
        return false, "no-owned-types"
    end
    local listIndex = nil
    for typeIndex = 1, numTypes do
        local okKey, key = pcall(C_AuctionHouse.GetOwnedAuctionType, typeIndex)
        if okKey and type(key) == "table" and key.itemID == itemID then
            listIndex = typeIndex + 1
            break
        end
    end
    if not listIndex then
        return false, "item-not-in-summary"
    end
    -- Make sure the row is rendered before clicking (ScrollBox virtualizes;
    -- scrolling re-layouts synchronously enough that FindFrame hits).
    local scrollTo = scrollBox.ScrollToElementDataIndex
    if type(scrollTo) == "function" then
        pcall(scrollTo, scrollBox, listIndex)
    end
    local okFrame, button = pcall(finder, scrollBox, listIndex)
    if not okFrame or type(button) ~= "table" or type(button.Click) ~= "function" then
        return false, "row-not-rendered"
    end
    button:Click()
    return true
end

V.adapters.MarketAdapter = Market
return Market
