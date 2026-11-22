-- VUT - pause button on the Blizzard auction house frame. Our OWN frame
-- (CreateFrame) parented into AuctionHouseFrame chrome: no Blizzard frame
-- writes, no shared containers, no protected operations (the auction house
-- cannot even be open in combat). Pausing mutes all VUT queries and alerts
-- so the user can cancel/repost lots quietly; resume re-baselines silently.
--
-- Anchor verified against the 1.60.1.70790 dump: the title strip (y -1..-21)
-- between the centered TitleContainer text and the CloseButton is empty
-- chrome - the interior below -22 is content (AuctionsFrame/DialogOverlay),
-- the bottom-left is MoneyFrameBorder, and the tabs hang below the frame.

local V = _G.VUT or {}
_G.VUT = V
V.ui = V.ui or {}

---@class PauseButtonAdapter
---@field button table|nil the single frame instance (created on first AH open)
local PauseButton = {}

--- Label + tint for the current state (color codes render in button text).
---@param paused boolean
---@return string
local function labelFor(paused)
    if paused then
        return "|cffff4444VUT: paused|r"
    end
    return "|cff33cc33VUT: on|r"
end

---@param button table our button frame (untyped CreateFrame result)
---@param console ConsoleAdapter
local function refresh(button, console)
    button:SetText(labelFor(console:status().paused == true))
end

--- Creates the button inside the auction house frame, once per session.
--- Called on every AUCTION_HOUSE_SHOW: AuctionHouseUI is LoadOnDemand, so
--- the frame may not exist until the first open - if so, retry briefly.
---@param console ConsoleAdapter
---@return boolean attached
function PauseButton.attach(console)
    if PauseButton.button then
        return true
    end
    local ah = AuctionHouseFrame
    if not ah then
        if (PauseButton.retries or 0) < 10 then
            PauseButton.retries = (PauseButton.retries or 0) + 1
            C_Timer.After(0.5, function()
                PauseButton.attach(console)
            end)
        end
        return false
    end
    PauseButton.retries = 0
    local button = CreateFrame("Button", nil, ah, "UIPanelButtonTemplate")
    -- Chrome level: above TitleContainer (510) / jump hints (515), below the
    -- modal DialogOverlay (1000) that should still cover everything.
    button:SetFrameLevel(600)
    button:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -70, -2)
    button:SetSize(96, 18)
    button:SetScript("OnClick", function()
        if console:status().paused then
            console:resume()
        else
            console:pause()
        end
        refresh(button, console)
    end)
    -- OnShow syncs state across AH re-opens; OnEnter keeps the label honest
    -- when pause was toggled through the slash command instead.
    button:SetScript("OnShow", function()
        refresh(button, console)
    end)
    button:SetScript("OnEnter", function()
        refresh(button, console)
        GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("VUT monitoring")
        GameTooltip:AddLine("Click to pause/resume scanning and alerts.", 1, 1, 1, true)
        GameTooltip:AddLine("Resume re-baselines quietly - no replay of", 1, 1, 1, true)
        GameTooltip:AddLine("cancels, reposts or sales made while paused.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    PauseButton.button = button
    refresh(button, console)
    return true
end

V.ui.PauseButton = PauseButton
return PauseButton
