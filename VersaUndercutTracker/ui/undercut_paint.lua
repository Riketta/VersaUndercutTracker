-- VUT - paints the Auctions-tab summary rows (the left pane) red while the
-- item's own lot is not first in the buyout queue (verdict UNDERCUT/TIED).
--
-- Hook point: ScrollUtil.AddInitializedFrameCallback - the Blizzard-built
-- post-initialization access point for public addons (fires on every row
-- (re)bind: list refresh, scroll reuse, pooling). No mixin writes, no frame
-- method replacement; the only mutation is SetTextColor on the row's OWN
-- Text FontString, restored from a captured original when the item is fine.
--
-- Rows carry their list index; index > 1 maps through
-- C_AuctionHouse.GetOwnedAuctionType to the row's itemKey. Bids mode is
-- skipped (bid rows have no own-queue verdicts). Commodities verdict on the
-- zero-level market key, item lots on the full key - both candidates are
-- checked against the domain's notFirst set.

local V = _G.VUT or {}
_G.VUT = V
V.ui = V.ui or {}

local Types = V.domain.Types

---@class UndercutPaintAdapter
local UndercutPaint = {}
local installed = false
--- Original text colors per row frame (rows are pooled and reused); weak
--- keys so released rows can be collected.
local originalColors = setmetatable({}, { __mode = "k" })

---@param frame table summary line frame
---@param elementData any the list index (number; 1 = the "All" header line)
---@param notFirst table<string, boolean> keyString -> not first, from status()
local function paintRow(frame, elementData, notFirst)
    local text = frame and frame.Text
    if type(text) ~= "table" then
        return
    end
    local bad = false
    if type(elementData) == "number" and elementData > 1 then
        local auctionsFrame = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
        local bidsMode = auctionsFrame and auctionsFrame.IsDisplayingBids and auctionsFrame:IsDisplayingBids()
        if not bidsMode then
            local itemKey = C_AuctionHouse.GetOwnedAuctionType(elementData - 1)
            if type(itemKey) == "table" and Types.isItemKey(itemKey) then
                local candidates = {
                    Types.keyString(itemKey),
                    Types.keyString({
                        itemID = itemKey.itemID,
                        itemLevel = 0,
                        itemSuffix = 0,
                        battlePetSpeciesID = 0,
                    }),
                }
                for _, keyString in ipairs(candidates) do
                    if notFirst[keyString] then
                        bad = true
                        break
                    end
                end
            end
        end
    end
    if bad then
        if originalColors[frame] == nil then
            local r, g, b = text:GetTextColor()
            originalColors[frame] = { r, g, b }
        end
        text:SetTextColor(1, 0.15, 0.1)
    else
        local original = originalColors[frame]
        if original then
            text:SetTextColor(original[1], original[2], original[3])
        end
    end
end

--- Installs the paint callback on the summary list's ScrollBox, once per
--- session (the callback survives AH close/reopen; rows re-init on reopen).
---@param console ConsoleAdapter
---@return boolean enabled
function UndercutPaint.enable(console)
    if installed then
        return true
    end
    local auctionsFrame = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
    local summary = auctionsFrame and auctionsFrame.SummaryList
    local scrollBox = summary and summary.ScrollBox
    if
        not (scrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback)
        or not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctionType)
    then
        return false
    end
    ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, frame, elementData)
        paintRow(frame, elementData, console:status().notFirst or {})
    end, nil, true)
    installed = true
    return true
end

V.ui.UndercutPaint = UndercutPaint
return UndercutPaint
