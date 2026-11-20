-- VUTProbe - raw auction house payload dump probe for VUT R&D.
--
-- Passive diagnostic: registers auction house events, serializes the raw
-- C_AuctionHouse tables behind the Auctions tab panes, prints to chat.
-- Read-only: no Blizzard frame writes, no hooks, no protected calls.
--
-- Slash: /vp help

local VP = _G.VUTProbe or {}
_G.VUTProbe = VP

VP.enabled = true
VP.syslog = false

-- ===== chat emission ========================================================

local PREFIX = "|cff33ccff[VP]|r "

--- Chat lines cap near 255 chars; split long serialized blobs into chunks.
---@param line any
local function emit(line)
    line = tostring(line)
    if line == "" then
        print(PREFIX)
        return
    end
    local offset = 1
    while offset <= #line do
        print(PREFIX .. line:sub(offset, offset + 219))
        offset = offset + 220
    end
end

-- ===== value serializer =====================================================

---@param s string
---@return string
local function fmtString(s)
    local escaped = s:gsub("[\\\"\n\r\t]", {
        ["\\"] = "\\\\",
        ["\""] = "\\\"",
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\t"] = "\\t",
    })
    return "\"" .. escaped .. "\""
end

---@param value any
---@param depth number remaining table depth
---@return string
local function serialize(value, depth)
    local kind = type(value)
    if kind == "string" then
        return fmtString(value)
    elseif kind == "number" then
        return string.format("%.14g", value)
    elseif kind == "table" and depth > 0 then
        local count = #value
        local parts = {}
        for i = 1, count do
            parts[#parts + 1] = serialize(value[i], depth - 1)
        end
        local extras = {}
        for key in pairs(value) do
            local isSequenceIndex = type(key) == "number" and key >= 1 and key <= count and key % 1 == 0
            if not isSequenceIndex then
                extras[#extras + 1] = "[" .. serialize(key, depth - 1) .. "]=" .. serialize(value[key], depth - 1)
            end
        end
        if #extras > 0 then
            table.sort(extras)
            parts[#parts + 1] = table.concat(extras, ", ")
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif kind == "table" then
        return "{...}"
    end
    return tostring(value)
end

-- ===== debounce =============================================================

--- Collapses event bursts into one dump scheduled `seconds` after the last.
---@param seconds number
---@param fn function
---@return fun(...)
local function debouncer(seconds, fn)
    local handle = nil
    return function(...)
        local args = { ... }
        if handle and handle.Cancel then
            handle:Cancel()
        end
        handle = C_Timer.After(seconds, function()
            handle = nil
            fn(unpack(args))
        end)
    end
end

-- ===== dump bodies ==========================================================

local pendingQueryOwnedAt = nil
local pendingBrowseQueryAt = nil

local function dumpOwnedNow()
    local okN, num = pcall(C_AuctionHouse.GetNumOwnedAuctions)
    if not okN or type(num) ~= "number" then
        emit("GetNumOwnedAuctions failed: " .. serialize(num, 2))
        return
    end
    local okF, full = pcall(C_AuctionHouse.HasFullOwnedAuctionResults)
    local okT, types = pcall(C_AuctionHouse.GetNumOwnedAuctionTypes)
    emit(
        ("OWNED num=%d hasFull=%s numTypes=%s"):format(
            num,
            okF and tostring(full) or "?",
            (okT and type(types) == "number") and tostring(types) or "?"
        )
    )
    for i = 1, num do
        local ok, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, i)
        emit(("  [%d] %s"):format(i, ok and serialize(info, 4) or ("error: " .. serialize(info, 2))))
    end
end

local function dumpTypesNow()
    local okN, num = pcall(C_AuctionHouse.GetNumOwnedAuctionTypes)
    if not okN or type(num) ~= "number" then
        emit("GetNumOwnedAuctionTypes failed: " .. serialize(num, 2))
        return
    end
    emit("OWNED TYPES num=" .. num)
    for i = 1, num do
        local ok, key = pcall(C_AuctionHouse.GetOwnedAuctionType, i)
        emit(("  type[%d] %s"):format(i, ok and serialize(key, 3) or ("error: " .. serialize(key, 2))))
    end
end

local function dumpItemRowsNow(itemKey)
    emit("ITEM ROWS key=" .. serialize(itemKey, 3))
    local okN, num = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not okN or type(num) ~= "number" then
        emit("  GetNumItemSearchResults failed: " .. serialize(num, 2))
        return
    end
    local okQ, qty = pcall(C_AuctionHouse.GetItemSearchResultsQuantity, itemKey)
    local okF, full = pcall(C_AuctionHouse.HasFullItemSearchResults, itemKey)
    emit(("  num=%d totalQty=%s hasFull=%s"):format(num, okQ and tostring(qty) or "?", okF and tostring(full) or "?"))
    for i = 1, num do
        local ok, row = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        emit(("  [%d] %s"):format(i, ok and serialize(row, 4) or ("error: " .. serialize(row, 2))))
    end
end

local function dumpCommodityRowsNow(itemID)
    emit("COMMODITY ROWS itemID=" .. serialize(itemID, 2))
    local okN, num = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not okN or type(num) ~= "number" then
        emit("  GetNumCommoditySearchResults failed: " .. serialize(num, 2))
        return
    end
    local okQ, qty = pcall(C_AuctionHouse.GetCommoditySearchResultsQuantity, itemID)
    local okF, full = pcall(C_AuctionHouse.HasFullCommoditySearchResults, itemID)
    emit(("  num=%d totalQty=%s hasFull=%s"):format(num, okQ and tostring(qty) or "?", okF and tostring(full) or "?"))
    for i = 1, num do
        local ok, row = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        emit(("  [%d] %s"):format(i, ok and serialize(row, 4) or ("error: " .. serialize(row, 2))))
    end
end

local function dumpBrowseNow()
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then
        emit("GetBrowseResults failed: " .. serialize(results, 2))
        return
    end
    local own = {}
    for i = 1, #results do
        local row = results[i]
        if type(row) == "table" and row.containsOwnerItem then
            own[#own + 1] = row
        end
    end
    local okF, full = pcall(C_AuctionHouse.HasFullBrowseResults)
    emit(("BROWSE rows=%d ownRows=%d hasFull=%s"):format(#results, #own, okF and tostring(full) or "?"))
    for i = 1, math.min(#own, 20) do
        emit("  own[" .. i .. "] " .. serialize(own[i], 4))
    end
end

local function dumpRawBrowse(limit)
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then
        emit("GetBrowseResults failed: " .. serialize(results, 2))
        return
    end
    emit(("RAW BROWSE rows=%d showing first %d"):format(#results, math.min(limit, #results)))
    for i = 1, math.min(limit, #results) do
        emit(("  [%d] %s"):format(i, serialize(results[i], 4)))
    end
end

-- ===== shared state =========================================================

--- The most recent ITEM_SEARCH_RESULTS_UPDATED key, kept for /vp queuei.
local lastItemKey = nil

-- ===== queue position prototypes =============================================

--- Commodity match order on this fork: unitPrice ASC, and within a price
--- tier the NEWEST listing sells first (user-verified: "last placed item
--- will be sold first" - the cancel/repost-jump-the-queue behavior). That is
--- exactly the delivered row order (auctionID DESC within a tier), so the
--- queue walk consumes rows AS DELIVERED - no reversal.
local function cmdQueueCommodity(itemID)
    if type(itemID) ~= "number" then
        emit("usage: /vp queue <itemID> (click the commodity in the Auctions summary first)")
        return
    end
    local okN, num = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not okN or type(num) ~= "number" or num == 0 then
        emit("no commodity results held for itemID " .. itemID .. " - click it in the left summary pane first")
        return
    end
    local rows = {}
    for i = 1, num do
        local ok, row = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if ok and type(row) == "table" then
            rows[#rows + 1] = row
        end
    end
    local fifo = rows
    emit(
        ("QUEUE itemID=%d rows=%d (match order = price asc, newest first within tier, as delivered)"):format(
            itemID,
            #rows
        )
    )
    local ahead = 0
    local found = 0
    local ownMin = nil
    for _, row in ipairs(fifo) do
        if row.containsOwnerItem then
            found = found + 1
            ownMin = math.min(ownMin or row.unitPrice, row.unitPrice)
            emit(
                ("  own #%d: auctionID=%s unitPrice=%s qty=%s numOwnerItems=%s unitsAhead=%d"):format(
                    found,
                    serialize(row.auctionID, 1),
                    serialize(row.unitPrice, 1),
                    serialize(row.quantity, 1),
                    serialize(row.numOwnerItems, 1),
                    ahead
                )
            )
        end
        ahead = ahead + (row.quantity or 0)
    end
    if found == 0 then
        emit("  no own lots in results")
        return
    end
    local cheapest = type(rows[1]) == "table" and rows[1].unitPrice or nil
    if ownMin and cheapest then
        if ownMin < cheapest then
            emit(("  VERDICT: FIRST (own %s < market %s)"):format(serialize(ownMin, 1), serialize(cheapest, 1)))
        elseif ownMin == cheapest then
            emit(("  VERDICT: TIED-CHEAPEST - see unitsAhead (market min %s)"):format(serialize(cheapest, 1)))
        else
            emit(
                ("  VERDICT: UNDERCUT by %s (own %s vs market %s)"):format(
                    serialize(ownMin - cheapest, 1),
                    serialize(ownMin, 1),
                    serialize(cheapest, 1)
                )
            )
        end
    end
    emit("  note: row-granular - own units inside a merged multi-owner row share that row's position")
end

local function cmdQueueItem()
    if type(lastItemKey) ~= "table" then
        emit("no item search seen yet - click an item row in the Auctions summary first")
        return
    end
    local okN, num = pcall(C_AuctionHouse.GetNumItemSearchResults, lastItemKey)
    if not okN or type(num) ~= "number" or num == 0 then
        emit("no item results held for " .. serialize(lastItemKey, 2))
        return
    end
    emit("QUEUE (item) key=" .. serialize(lastItemKey, 3))
    local ownMin = nil
    local cheapest = nil
    for i = 1, num do
        local ok, row = pcall(C_AuctionHouse.GetItemSearchResultInfo, lastItemKey, i)
        if ok and type(row) == "table" then
            local unit = row.quantity > 0 and math.floor(row.buyoutAmount / row.quantity + 0.5) or row.buyoutAmount
            cheapest = cheapest or unit
            local own = ""
            if row.containsOwnerItem then
                ownMin = math.min(ownMin or unit, unit)
                own = " <= OWN"
            end
            emit(
                ("  [%d] auctionID=%s unit=%s qty=%s owners=%s%s"):format(
                    i,
                    serialize(row.auctionID, 1),
                    serialize(unit, 1),
                    serialize(row.quantity, 1),
                    serialize(row.owners, 2),
                    own
                )
            )
        end
    end
    if ownMin == nil then
        emit("  no own lots in results")
    elseif ownMin < cheapest then
        emit("  VERDICT: FIRST")
    elseif ownMin == cheapest then
        emit("  VERDICT: TIED-CHEAPEST (buyers see all tied rows; no server queue for items)")
    else
        emit(("  VERDICT: UNDERCUT by %s"):format(serialize(ownMin - cheapest, 1)))
    end
end

local function dumpActiveOwned()
    local okN, num = pcall(C_AuctionHouse.GetNumOwnedAuctions)
    if not okN or type(num) ~= "number" then
        emit("GetNumOwnedAuctions failed: " .. serialize(num, 2))
        return
    end
    local active = 0
    local sold = 0
    for i = 1, num do
        local ok, info = pcall(C_AuctionHouse.GetOwnedAuctionInfo, i)
        if ok and type(info) == "table" then
            if info.status == 0 then
                active = active + 1
                emit(
                    ("  active[%d] auctionID=%s itemID=%s qty=%s buyout=%s unit=%s tl=%ss itemLink=%s"):format(
                        active,
                        serialize(info.auctionID, 1),
                        serialize(type(info.itemKey) == "table" and info.itemKey.itemID or "?", 1),
                        serialize(info.quantity, 1),
                        serialize(info.buyoutAmount, 1),
                        serialize(
                            (info.quantity or 0) > 0 and info.buyoutAmount and math.floor(info.buyoutAmount) or "?",
                            1
                        ),
                        serialize(info.timeLeftSeconds, 1),
                        serialize(info.itemLink, 1)
                    )
                )
            else
                sold = sold + 1
            end
        end
    end
    emit(("OWNED ACTIVE: %d active, %d non-active (sold) records"):format(active, sold))
end

-- ===== script-context gate probes ===========================================

local function fireQueryOwned()
    local sorts = {}
    if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
        sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    end
    emit("firing QueryOwnedAuctions from script context...")
    local ok, err = pcall(C_AuctionHouse.QueryOwnedAuctions, sorts)
    if not ok then
        emit("  pcall FAILED: " .. serialize(err, 2))
        return
    end
    emit("  pcall ok - watching for OWNED_AUCTIONS_UPDATED (timeout 5s)")
    pendingQueryOwnedAt = GetTime()
    C_Timer.After(5, function()
        if pendingQueryOwnedAt then
            pendingQueryOwnedAt = nil
            emit("  TIMEOUT: no OWNED_AUCTIONS_UPDATED in 5s - script-side query is gated")
        end
    end)
end

local function fireBrowseQuery()
    emit("firing empty SendBrowseQuery from script context...")
    local ok, err = pcall(C_AuctionHouse.SendBrowseQuery, {
        searchString = "",
        sorts = {},
        filters = {},
        itemClassFilters = {},
    })
    if not ok then
        emit("  pcall FAILED: " .. serialize(err, 2))
        return
    end
    emit("  pcall ok - watching browse rows (timeout 10s)")
    pendingBrowseQueryAt = GetTime()
    C_Timer.After(10, function()
        if pendingBrowseQueryAt then
            pendingBrowseQueryAt = nil
            emit("  TIMEOUT: no browse rows in 10s - browse enumeration is gated")
        end
    end)
end

-- ===== event wiring =========================================================

local dumpOwned = debouncer(0.4, dumpOwnedNow)
local dumpBrowse = debouncer(1.0, dumpBrowseNow)

local itemDumpers = {}
local function dumperFor(itemKey)
    local id = serialize(itemKey, 2)
    local d = itemDumpers[id]
    if not d then
        d = debouncer(0.5, dumpItemRowsNow)
        itemDumpers[id] = d
    end
    return d
end

local commodityDumpers = {}
local function commodityDumperFor(itemID)
    local d = commodityDumpers[itemID]
    if not d then
        d = debouncer(0.5, dumpCommodityRowsNow)
        commodityDumpers[itemID] = d
    end
    return d
end

--- One-line event note with serialized payload.
local function note(event, ...)
    local count = select("#", ...)
    local parts = {}
    for i = 1, count do
        parts[i] = serialize((select(i, ...)), 3)
    end
    local payload = table.concat(parts, ", ")
    emit("EVENT " .. event .. (payload ~= "" and (" " .. payload) or ""))
end

local eventFrame = CreateFrame("Frame")
local EVENTS = {
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "OWNED_AUCTIONS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_SEARCH_RESULTS_RECEIVED",
    "COMMODITY_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_FAILURE",
    "COMMODITY_PURCHASED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_AUCTIONS_EXPIRED",
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_CANCELED",
    "AUCTION_HOUSE_NEW_BID_RECEIVED",
    "OWNED_AUCTION_BIDDER_INFO_RECEIVED",
    "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
    "ITEM_PURCHASED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "CHAT_MSG_SYSTEM",
}
for _, event in ipairs(EVENTS) do
    eventFrame:RegisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        if VP.syslog then
            note(event, ...)
        end
        return
    end
    if not VP.enabled then
        return
    end
    if event == "OWNED_AUCTIONS_UPDATED" then
        if pendingQueryOwnedAt then
            emit(("QueryOwnedAuctions answered after %.2fs"):format(GetTime() - pendingQueryOwnedAt))
            pendingQueryOwnedAt = nil
        end
        dumpOwned()
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        note(event, ...)
        local itemKey = ...
        if type(itemKey) == "table" then
            lastItemKey = itemKey
            dumperFor(itemKey)(itemKey)
        end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = ...
        if type(itemID) == "number" then
            commodityDumperFor(itemID)(itemID)
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        if pendingBrowseQueryAt then
            emit(("SendBrowseQuery rows landed after %.2fs"):format(GetTime() - pendingBrowseQueryAt))
            pendingBrowseQueryAt = nil
        end
        dumpBrowse()
    else
        note(event, ...)
    end
end)

-- ===== slash commands =======================================================

SLASH_VUTPROBE1 = "/vp"
SLASH_VUTPROBE2 = "/versaprobe"
SlashCmdList["VUTPROBE"] = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "help" then
        emit(
            "commands: owned | active | types | browse | rawbrowse <n> | queue <itemID> | queuei | queryowned | browsequery | sys | on | off"
        )
        emit("  owned       dump GetOwnedAuctionInfo rows (left pane source)")
        emit("  active      dump only status=Active owned lots (the live inventory)")
        emit("  types       dump owned auction types (summary list groups)")
        emit("  browse      browse rows summary + rows containing own listings")
        emit("  rawbrowse   first N raw BrowseResultInfo rows (default 5)")
        emit("  queue       match-order position of own commodity lots (click item first)")
        emit("  queuei      item variant: per-listing positions for the last seen item")
        emit("  queryowned  gate test: QueryOwnedAuctions from script, watch the event")
        emit("  browsequery gate test: empty SendBrowseQuery from script")
        emit("  sys         toggle CHAT_MSG_SYSTEM logging (sold/expired system lines)")
        emit("  on/off      passive event dumps master switch")
    elseif cmd == "owned" then
        dumpOwnedNow()
    elseif cmd == "active" then
        dumpActiveOwned()
    elseif cmd == "types" then
        dumpTypesNow()
    elseif cmd == "browse" then
        dumpBrowseNow()
    elseif cmd == "rawbrowse" then
        dumpRawBrowse(tonumber(arg) or 5)
    elseif cmd == "queue" then
        cmdQueueCommodity(tonumber(arg))
    elseif cmd == "queuei" then
        cmdQueueItem()
    elseif cmd == "queryowned" then
        fireQueryOwned()
    elseif cmd == "browsequery" then
        fireBrowseQuery()
    elseif cmd == "sys" then
        VP.syslog = not VP.syslog
        emit("syslog=" .. tostring(VP.syslog))
    elseif cmd == "on" then
        VP.enabled = true
        emit("passive dumps enabled")
    elseif cmd == "off" then
        VP.enabled = false
        emit("passive dumps disabled (slash commands still work)")
    else
        emit("unknown command: " .. cmd .. " (try /vp help)")
    end
end

emit("VUTProbe 0.1.0 loaded - /vp help (passive dumps " .. tostring(VP.enabled) .. ")")
