-- VUT - clock adapter (GetTime).

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

---@class ClockAdapter : ClockPort
---@field now fun(self: any): number
local Clock = {}
Clock.__index = Clock

---@return ClockAdapter
function Clock.new()
    return setmetatable({}, Clock)
end

---@return number
function Clock:now()
    return GetTime()
end

V.adapters.ClockAdapter = Clock
return Clock
