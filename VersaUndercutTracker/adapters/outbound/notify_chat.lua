-- VUT - chat notification channel. Severity colors the tag;
-- the domain owns the message text.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local SEVERITY_COLORS = {
    alert = "ffff5555",
    warn = "ffffcc00",
    info = "ff33ccff",
}

---@class ChatNotifier
local Chat = {}
Chat.__index = Chat

---@return ChatNotifier
function Chat.new()
    return setmetatable({}, Chat)
end

---@param alert AlertEvent
function Chat:notify(alert)
    local color = SEVERITY_COLORS[alert.severity] or "ff33ccff"
    print(("|c%sVUT|r %s"):format(color, alert.text))
end

V.adapters.ChatNotifier = Chat
return Chat
