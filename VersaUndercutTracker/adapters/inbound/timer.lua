-- VUT - timer driver. Owns the C_Timer tickers that drive
-- the core's beats while the auction house session is open; stopped on AH
-- close. Cadences read the live settings table at (re)start.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

---@class TimerDriver
---@field tickers table[] live C_Timer tickers
local TimerDriver = {}
TimerDriver.__index = TimerDriver

---@return TimerDriver
function TimerDriver.new()
    return setmetatable({ tickers = {} }, TimerDriver)
end

---@param seconds number
---@param fn function
local function startTicker(self, seconds, fn)
    if type(seconds) ~= "number" or seconds <= 0 then
        return
    end
    local ticker = C_Timer.NewTicker(seconds, fn)
    self.tickers[#self.tickers + 1] = ticker
end

---@param core table ControlPort implementor
---@param settings Settings
function TimerDriver:start(core, settings)
    self:stop()
    startTicker(self, settings.ownedPollSeconds, function()
        core:beatOwned()
    end)
    startTicker(self, settings.commodityPollSeconds, function()
        core:beatCommodities()
    end)
    startTicker(self, settings.itemRotationSeconds, function()
        core:beatItems()
    end)
end

function TimerDriver:stop()
    for _, ticker in ipairs(self.tickers) do
        if ticker and ticker.Cancel then
            ticker:Cancel()
        end
    end
    self.tickers = {}
end

---@param core table
---@param settings Settings
function TimerDriver:restart(core, settings)
    self:start(core, settings)
end

V.adapters.TimerDriver = TimerDriver
return TimerDriver
