-- VUT - notifier bus. Fans one alert out to the channel
-- adapters enabled by alert.routing (decided by the domain config); channel
-- adapters only render. This is the ONLY place channel composition happens.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

---@class NotifierBus : NotifierPort
---@field channels table<string, table>[] ordered {name, adapter} pairs
local Bus = {}
Bus.__index = Bus

---@param channels table[] list of {name: string, adapter: table}
---@return NotifierBus
function Bus.new(channels)
    return setmetatable({ channels = channels }, Bus)
end

---@param alert AlertEvent
function Bus:dispatch(alert)
    for _, entry in ipairs(self.channels) do
        if alert.routing[entry.name] then
            local ok, err = pcall(entry.adapter.notify, entry.adapter, alert)
            if not ok then
                -- A broken channel must never break the bus or the core.
                print("|cffff3333VUT|r channel '" .. entry.name .. "' failed: " .. tostring(err))
            end
        end
    end
end

V.adapters.NotifierBus = Bus
return Bus
