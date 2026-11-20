-- VUT - screen-flash notification channel. An OWN overlay
-- frame (never a Blizzard frame, never a shared fade/flash table): a full-
-- screen dark red texture whose alpha pulses on our own OnUpdate, then hides.
-- Cosmetic writes only - combat-safe by construction.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

---@class FlashNotifier
---@field settings Settings live settings reference
---@field frame table|nil lazy-built overlay
local Flash = {}
Flash.__index = Flash

---@param settings Settings
---@return FlashNotifier
function Flash.new(settings)
    return setmetatable({ settings = settings, frame = nil }, Flash)
end

local function buildFrame()
    ---@type table
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(9999)
    frame:EnableMouse(false)
    frame:SetAlpha(0)
    frame:Hide()
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(frame)
    texture:SetColorTexture(0.55, 0, 0, 1)
    return frame
end

---@param _ AlertEvent ignored: the flash renders only
function Flash:notify(_)
    local frame = self.frame
    if not frame then
        frame = buildFrame()
        self.frame = frame
    end
    local duration = self.settings.flashSeconds or 1.5
    local startedAt = GetTime()
    frame:Show()
    frame:SetScript("OnUpdate", function()
        local elapsed = GetTime() - startedAt
        if elapsed >= duration then
            frame:SetAlpha(0)
            frame:Hide()
            frame:SetScript("OnUpdate", nil)
            return
        end
        -- Pulse: two bright beats per second, fading with the remaining time.
        local fade = 1 - (elapsed / duration)
        local pulse = math.abs(math.sin(elapsed * math.pi * 2))
        frame:SetAlpha(0.08 + 0.22 * pulse * fade)
    end)
end

V.adapters.FlashNotifier = Flash
return Flash
