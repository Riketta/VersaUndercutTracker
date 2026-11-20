-- VUT - item metadata adapter: display names + commodity-ness.
-- Name chain (AuctiMogger-proven on this fork): link-seeded cache first
-- (own lots carry itemLink - free, exact), then GetItemKeyInfo (this fork's
-- ItemKeyInfo field is `itemName`; the retail `name` spelling is accepted
-- too), then C_Item.GetItemInfo. A cold GetItemKeyInfo queues a server
-- request; late answers arrive via ITEM_KEY_ITEM_INFO_RECEIVED and re-resolve
-- pending ids. Never throws; nil until resolved - callers treat nil as the
-- "#id" fallback, never as a final answer.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local Types = V.domain.Types

---@class ItemInfoAdapter : ItemInfoPort
---@field nameCache table<number, string> itemID -> display name
---@field commodityCache table<string, boolean> keyString -> isCommodity
---@field pendingName table<number, boolean> itemIDs awaiting a late answer
---@field frame table|nil lazy frame for ITEM_KEY_ITEM_INFO_RECEIVED
local ItemInfo = {}
ItemInfo.__index = ItemInfo

---@return ItemInfoAdapter
function ItemInfo.new()
    return setmetatable({ nameCache = {}, commodityCache = {}, pendingName = {}, frame = nil }, ItemInfo)
end

local function bareKey(itemID)
    return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

local function probeName(itemID)
    if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, bareKey(itemID), false)
        if ok and type(info) == "table" then
            local name = info.itemName or info.name
            if type(name) == "string" and #name > 0 then
                return name
            end
        end
    end
    if C_Item and C_Item.GetItemInfo then
        local ok, name = pcall(C_Item.GetItemInfo, itemID)
        if ok and type(name) == "string" and #name > 0 then
            return name
        end
    end
    return nil
end

---@param itemID number
---@return string|nil
function ItemInfo:name(itemID)
    local cached = self.nameCache[itemID]
    if cached ~= nil then
        return cached
    end
    local name = probeName(itemID)
    if name then
        self.nameCache[itemID] = name
        self.pendingName[itemID] = nil
        return name
    end
    -- The cold probe already queued the server request; arm the late-answer
    -- retry instead of re-probing every beat (unpaced cold-cache probes are
    -- a server-request flood - AuctiMogger measured ~240 req/s before
    -- braking theirs).
    if not self.pendingName[itemID] then
        self.pendingName[itemID] = true
        self:armFrame()
    end
    return nil
end

--- Seeds an exact display name mined from an item link. Own item lots carry
--- the full hyperlink for free; the bracketed tail is the display name.
---@param itemID number
---@param itemLink string|nil
function ItemInfo:learnFromLink(itemID, itemLink)
    if self.nameCache[itemID] or type(itemLink) ~= "string" then
        return
    end
    local name = itemLink:match("%[(.-)%]")
    if type(name) == "string" and #name > 0 then
        self.nameCache[itemID] = name
        self.pendingName[itemID] = nil
    end
end

--- Lazy late-answer listener. Item-cache event, not an auction house event:
--- the events adapter remains the sole AH registrar (AGENTS.md).
function ItemInfo:armFrame()
    if self.frame then
        return
    end
    local frame = CreateFrame("Frame")
    self.frame = frame
    frame:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(_, event, itemID)
        if event == "ITEM_KEY_ITEM_INFO_RECEIVED" and self.pendingName[itemID] then
            local name = probeName(itemID)
            if name then
                self.nameCache[itemID] = name
                self.pendingName[itemID] = nil
            end
        end
    end)
end

---@param itemKey table
---@return boolean|nil
function ItemInfo:isCommodity(itemKey)
    if not Types.isItemKey(itemKey) then
        return nil
    end
    local key = Types.keyString(itemKey)
    local cached = self.commodityCache[key]
    if cached ~= nil then
        return cached
    end
    local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey, false)
    if ok and type(info) == "table" and type(info.isCommodity) == "boolean" then
        self.commodityCache[key] = info.isCommodity
        -- The same payload carries the name - cache it for free.
        local name = info.itemName or info.name
        if type(name) == "string" and #name > 0 then
            self.nameCache[itemKey.itemID] = name
            self.pendingName[itemKey.itemID] = nil
        end
        return info.isCommodity
    end
    return nil
end

V.adapters.ItemInfoAdapter = ItemInfo
return ItemInfo
