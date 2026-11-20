-- VUT - match-order verdicts from market rows.
--
-- Commodity rows arrive in MATCH order (verified in game): unitPrice ASC, and
-- within a price tier the NEWEST listing sells first - the delivered row order
-- IS the buy order, no reversal. Rows can merge several owners into one row
-- (own units ride inside via numOwnerItems), so positions are row-granular:
-- "FIRST" means the first row containing own units is the very first row.
-- Items have no server-side queue: buyers pick a listing; the verdict reduces
-- to cheapest-unit comparison.

local V = _G.VUT or {}
_G.VUT = V
V.domain = V.domain or {}

local Queue = {}

--- Commodity verdict for one owned itemID.
--- Returned states: "FIRST" (own units sit in the first row), "TIED" (own
--- price is the market min but other units are ahead), "UNDERCUT" (cheaper
--- competitor rows exist), "GONE" (no rows or no own rows - stale view or the
--- lot closed; the owned layer owns that classification).
---@param rows MarketRow[] sanitized rows in delivered (match) order
---@return table verdict {state: string, cheapest?: number, ownMin?: number, by?: number, unitsAhead?: number, tierUnits?: number}
function Queue.commodity(rows)
    if type(rows) ~= "table" or #rows == 0 then
        return { state = "GONE" }
    end
    local cheapest = rows[1].unitPrice
    local ownMin = nil
    local firstOwnIdx = nil
    for i, row in ipairs(rows) do
        if row.isOwn then
            firstOwnIdx = firstOwnIdx or i
            if ownMin == nil or row.unitPrice < ownMin then
                ownMin = row.unitPrice
            end
        end
    end
    if ownMin == nil then
        return { state = "GONE", cheapest = cheapest }
    end
    if cheapest < ownMin then
        return { state = "UNDERCUT", cheapest = cheapest, ownMin = ownMin, by = ownMin - cheapest }
    end
    local unitsAhead = 0
    for i = 1, firstOwnIdx - 1 do
        unitsAhead = unitsAhead + rows[i].quantity
    end
    local tierUnits = 0
    for _, row in ipairs(rows) do
        if row.unitPrice == ownMin then
            tierUnits = tierUnits + row.quantity
        end
    end
    if unitsAhead == 0 then
        return { state = "FIRST", cheapest = cheapest, ownMin = ownMin, tierUnits = tierUnits }
    end
    return { state = "TIED", cheapest = cheapest, ownMin = ownMin, unitsAhead = unitsAhead, tierUnits = tierUnits }
end

--- Item verdict for one owned item key.
--- States: "FIRST" (own listing is the unique cheapest), "TIED" (own unit
--- price ties the cheapest with foreign listings), "UNDERCUT", "GONE".
---@param rows ItemRow[] sanitized rows
---@return table verdict {state: string, cheapest?: number, ownMin?: number, by?: number, cheaperCount?: number, tiedCount?: number}
function Queue.item(rows)
    if type(rows) ~= "table" or #rows == 0 then
        return { state = "GONE" }
    end
    local cheapest = nil
    local ownMin = nil
    for _, row in ipairs(rows) do
        local unit = row.unitPrice
        if unit ~= nil then
            if cheapest == nil or unit < cheapest then
                cheapest = unit
            end
            if row.isOwn and (ownMin == nil or unit < ownMin) then
                ownMin = unit
            end
        end
    end
    if ownMin == nil or cheapest == nil then
        return { state = "GONE", cheapest = cheapest }
    end
    if cheapest < ownMin then
        local cheaperCount = 0
        for _, row in ipairs(rows) do
            if row.unitPrice ~= nil and row.unitPrice < ownMin then
                cheaperCount = cheaperCount + 1
            end
        end
        return {
            state = "UNDERCUT",
            cheapest = cheapest,
            ownMin = ownMin,
            by = ownMin - cheapest,
            cheaperCount = cheaperCount,
        }
    end
    local tiedCount = 0
    for _, row in ipairs(rows) do
        if not row.isOwn and row.unitPrice ~= nil and row.unitPrice == ownMin then
            tiedCount = tiedCount + 1
        end
    end
    if tiedCount > 0 then
        return { state = "TIED", cheapest = cheapest, ownMin = ownMin, tiedCount = tiedCount }
    end
    return { state = "FIRST", cheapest = cheapest, ownMin = ownMin }
end

V.domain.Queue = Queue
return Queue
