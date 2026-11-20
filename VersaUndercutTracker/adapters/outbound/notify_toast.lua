-- VUT - toast notification channel. An OWN frame stack at
-- top-center: up to five single-line toasts, newest on top, each fading out
-- over its last half second. Own frames only; cosmetic writes only.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

local MAX_TOASTS = 5
local TOAST_HEIGHT = 22

local SEVERITY_COLORS = {
    alert = "ffff5555",
    warn = "ffffcc00",
    info = "ff33ccff",
}

---@class ToastNotifier
---@field settings Settings live settings reference
---@field root table|nil lazy-built anchor frame
---@field active table[] live toasts {frame, text, startedAt}
local Toast = {}
Toast.__index = Toast

---@param settings Settings
---@return ToastNotifier
function Toast.new(settings)
    return setmetatable({ settings = settings, root = nil, active = {} }, Toast)
end

local function buildRoot()
    ---@type table
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(520, MAX_TOASTS * TOAST_HEIGHT)
    root:SetPoint("TOP", UIParent, "TOP", 0, -120)
    root:SetFrameStrata("HIGH")
    root:SetScript("OnUpdate", function()
        -- Driven by the root's single OnUpdate; toasts carry their state.
    end)
    return root
end

local function buildToast(root)
    local frame = CreateFrame("Frame", nil, root)
    frame:SetHeight(TOAST_HEIGHT)
    frame:SetWidth(520)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.65)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetAllPoints(frame)
    return { frame = frame, text = text }
end

---@param alert AlertEvent
function Toast:notify(alert)
    local root = self.root
    if not root then
        root = buildRoot()
        self.root = root
    end
    if #self.active >= MAX_TOASTS then
        local oldest = table.remove(self.active, 1)
        oldest.frame:Hide()
    end
    local toast = buildToast(self.root)
    local color = SEVERITY_COLORS[alert.severity] or "ff33ccff"
    toast.text:SetText(("|c%s%s|r"):format(color, alert.text))
    toast.startedAt = GetTime()
    toast.frame:Show()
    self.active[#self.active + 1] = toast
    self:layout()
    self:drive()
end

function Toast:layout()
    local root = self.root
    if not root then
        return
    end
    for i, toast in ipairs(self.active) do
        toast.frame:ClearAllPoints()
        local fromTop = (i - 1) * TOAST_HEIGHT
        toast.frame:SetPoint("TOP", root, "TOP", 0, -fromTop)
    end
end

function Toast:drive()
    local root = self.root
    if not root then
        return
    end
    local duration = self.settings.toastSeconds or 6
    local self2 = self
    root:SetScript("OnUpdate", function()
        local now = GetTime()
        local alive = {}
        for _, toast in ipairs(self2.active) do
            local elapsed = now - toast.startedAt
            if elapsed >= duration then
                toast.frame:Hide()
            else
                local remaining = duration - elapsed
                if remaining < 0.5 then
                    toast.frame:SetAlpha(remaining / 0.5)
                else
                    toast.frame:SetAlpha(1)
                end
                alive[#alive + 1] = toast
            end
        end
        self2.active = alive
        if #alive == 0 then
            root:SetScript("OnUpdate", nil)
        else
            self2:layout()
        end
    end)
end

V.adapters.ToastNotifier = Toast
return Toast
