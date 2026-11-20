-- VUT - owned-auctions adapter. Fires the script-side
-- QueryOwnedAuctions (verified to pass the fork's gate, ~0.1s answer) and
-- reads GetOwnedAuctionInfo rows into sanitized OwnLot records. The adapter
-- resolves commodity-ness through ItemInfoPort; unresolved lots enter with
-- isCommodity nil and re-resolve on later reads.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local Types = V.domain.Types

---@class OwnedAdapter : OwnedAuctionsPort
---@field itemInfo ItemInfoPort
local Owned = {}
Owned.__index = Owned

---@param itemInfo ItemInfoPort
---@return OwnedAdapter
function Owned.new(itemInfo)
    return setmetatable({ itemInfo = itemInfo }, Owned)
end

--- Fire the requery. Rows land asynchronously via OWNED_AUCTIONS_UPDATED
--- (the events adapter forwards it; the core then calls read()).
---@return boolean true when the send itself did not throw
function Owned:refresh()
    if not (C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions) then
        return false
    end
    local sorts = {}
    if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
        sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    end
    return (pcall(C_AuctionHouse.QueryOwnedAuctions, sorts))
end

--- Read the current owned snapshot into sanitized records. Never throws:
--- malformed rows are dropped at this boundary, never repaired inside.
---@return OwnLot[]
function Owned:read()
    local out = {}
    if not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctionInfo and C_AuctionHouse.GetNumOwnedAuctions) then
        return out
    end
    local okNum, num = pcall(C_AuctionHouse.GetNumOwnedAuctions)
    if not okNum or type(num) ~= "number" then
        return out
    end
    for i = 1, num do
        local okRaw, raw = pcall(C_AuctionHouse.GetOwnedAuctionInfo, i)
        if okRaw and type(raw) == "table" then
            local commodity = nil
            if type(raw.itemKey) == "table" and Types.isItemKey(raw.itemKey) then
                commodity = self.itemInfo:isCommodity(raw.itemKey)
            end
            local lot = Types.sanitizeOwnLot(raw, commodity)
            if lot then
                out[#out + 1] = lot
            end
        end
    end
    return out
end

V.adapters.OwnedAdapter = Owned
return Owned
