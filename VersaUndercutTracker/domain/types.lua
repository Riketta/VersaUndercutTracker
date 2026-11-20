-- VUT - domain types, boundary validators, identity, money.
-- Pure Lua: no game API (CI-enforced). Adapters sanitize raw game payloads
-- into these shapes before anything enters the core; anything that fails a
-- validator is dropped at the boundary, never repaired inside.

local V = _G.VUT or {}
_G.VUT = V
V.domain = V.domain or {}

local Types = {}

-- ===== identity ==============================================================

--- True when `v` is a well-formed wire item key.
---@param v any
---@return boolean
function Types.isItemKey(v)
    if type(v) ~= "table" then
        return false
    end
    local id, ilvl, suffix, species = v.itemID, v.itemLevel, v.itemSuffix, v.battlePetSpeciesID
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then
        return false
    end
    for _, n in ipairs({ ilvl, suffix, species }) do
        if type(n) ~= "number" or n < 0 or n % 1 ~= 0 then
            return false
        end
    end
    return true
end

--- Canonical domain identity of an item key: "i:<id>:<ilvl>:<suffix>:<species>".
---@param itemKey table validated key
---@return string
function Types.keyString(itemKey)
    return ("i:%d:%d:%d:%d"):format(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix, itemKey.battlePetSpeciesID)
end

-- ===== numbers ===============================================================

---@param n any
---@return boolean
local function isCount(n)
    return type(n) == "number" and n >= 0 and n % 1 == 0 and n < math.huge
end

---@param n any
---@return boolean
local function isMoney(n)
    return n == nil or (type(n) == "number" and n >= 0 and n < math.huge)
end

-- ===== sanitized shapes ======================================================

--- One own auction record, sanitized from OwnedAuctionInfo. `status` follows
--- the wire enum (0 = Active, 1 = Sold/closed ledger record). `unitPrice`:
--- commodities carry the unit price in buyoutAmount (verified in game);
--- item stacks are divided (stack semantics still to verify in game).
---@class OwnLot
---@field auctionID number
---@field keyString string
---@field itemID number
---@field itemLevel number
---@field itemSuffix number
---@field battlePetSpeciesID number
---@field quantity number
---@field status number 0|1
---@field buyoutRaw number|nil
---@field unitPrice number|nil
---@field isCommodity boolean|nil
---@field timeLeftSeconds number|nil
---@field itemLink string|nil
---@field seenAt number|nil session clock stamp of the snapshot that carried it

--- Sanitizes one raw OwnedAuctionInfo-shaped table.
---@param raw any
---@param commodity boolean|nil resolved commodity-ness (adapter concern)
---@return OwnLot|nil
function Types.sanitizeOwnLot(raw, commodity)
    if type(raw) ~= "table" then
        return nil
    end
    if not Types.isItemKey(raw.itemKey) then
        return nil
    end
    if not isCount(raw.auctionID) or raw.auctionID <= 0 then
        return nil
    end
    if not isCount(raw.quantity) or raw.quantity <= 0 then
        return nil
    end
    if raw.status ~= 0 and raw.status ~= 1 then
        return nil
    end
    if not isMoney(raw.buyoutAmount) then
        return nil
    end
    if not isMoney(raw.timeLeftSeconds) then
        return nil
    end
    local buyout = raw.buyoutAmount
    local unitPrice = nil
    if buyout ~= nil then
        if commodity then
            unitPrice = buyout
        elseif raw.quantity > 0 then
            unitPrice = math.floor(buyout / raw.quantity + 0.5)
        else
            unitPrice = buyout
        end
    end
    local key = raw.itemKey
    return {
        auctionID = raw.auctionID,
        keyString = Types.keyString(key),
        itemID = key.itemID,
        itemLevel = key.itemLevel,
        itemSuffix = key.itemSuffix,
        battlePetSpeciesID = key.battlePetSpeciesID,
        quantity = raw.quantity,
        status = raw.status,
        buyoutRaw = buyout,
        unitPrice = unitPrice,
        isCommodity = commodity,
        timeLeftSeconds = raw.timeLeftSeconds,
        itemLink = type(raw.itemLink) == "string" and raw.itemLink or nil,
    }
end

--- One competitor row of a commodity search, sanitized. Rows arrive in MATCH
--- order: unitPrice ASC, newest-first within a price tier (verified in game;
--- ties resolve to the newest listing - the cancel/repost jump-the-queue
--- behavior).
---@class MarketRow
---@field auctionID number
---@field unitPrice number
---@field quantity number
---@field ownUnits number
---@field isOwn boolean
---@field ownersCount number

---@param raw any
---@return MarketRow|nil
function Types.sanitizeMarketRow(raw)
    if type(raw) ~= "table" then
        return nil
    end
    if not isCount(raw.auctionID) or raw.auctionID <= 0 then
        return nil
    end
    if not isCount(raw.unitPrice) or raw.unitPrice <= 0 then
        return nil
    end
    if not isCount(raw.quantity) or raw.quantity <= 0 then
        return nil
    end
    local ownUnits = isCount(raw.numOwnerItems) and raw.numOwnerItems or 0
    return {
        auctionID = raw.auctionID,
        unitPrice = raw.unitPrice,
        quantity = raw.quantity,
        ownUnits = ownUnits,
        isOwn = raw.containsOwnerItem == true and ownUnits > 0,
        ownersCount = isCount(raw.totalNumberOfOwners) and raw.totalNumberOfOwners or 1,
    }
end

--- One competitor listing of an item (non-commodity) search, sanitized.
---@class ItemRow
---@field auctionID number
---@field unitPrice number|nil per-unit buyout (total/quantity)
---@field buyoutTotal number|nil
---@field quantity number
---@field isOwn boolean

---@param raw any
---@return ItemRow|nil
function Types.sanitizeItemRow(raw)
    if type(raw) ~= "table" then
        return nil
    end
    if not isCount(raw.auctionID) or raw.auctionID <= 0 then
        return nil
    end
    if not isCount(raw.quantity) or raw.quantity <= 0 then
        return nil
    end
    if not isMoney(raw.buyoutAmount) then
        return nil
    end
    local total = raw.buyoutAmount
    local unit = nil
    if total ~= nil then
        unit = math.floor(total / raw.quantity + 0.5)
    end
    return {
        auctionID = raw.auctionID,
        unitPrice = unit,
        buyoutTotal = total,
        quantity = raw.quantity,
        isOwn = raw.containsOwnerItem == true,
    }
end

-- ===== money =================================================================

--- Formats copper as the compact gold/silver/copper string ("12g 34s 56c";
--- zero-value segments dropped; zero formats as "0c").
---@param copper number
---@return string
function Types.money(copper)
    if type(copper) ~= "number" or copper < 0 or copper ~= math.floor(copper) then
        return "?"
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rem = copper % 100
    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = gold .. "g"
    end
    if gold > 0 or silver > 0 then
        parts[#parts + 1] = silver .. "s"
    end
    if rem > 0 or #parts == 0 then
        parts[#parts + 1] = rem .. "c"
    end
    return table.concat(parts, " ")
end

V.domain.Types = Types
return Types
