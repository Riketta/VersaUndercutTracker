-- VUT - sound notification channel. A custom media file
-- (settings.soundFile, an addon-relative or Interface path) wins over the
-- SOUNDKIT name when set. Kits are stored by SYMBOLIC name and resolved
-- through the client's SOUNDKIT table at play time - numeric ids are
-- build-specific and a wrong id fails silently. Both paths play on the
-- Master channel so alerts stay audible regardless of the Sound Effects
-- volume slider.

local V = _G.VUT or {}
_G.VUT = V
V.adapters = V.adapters or {}

---@class SoundNotifier
---@field settings Settings live settings reference
local Sound = {}
Sound.__index = Sound

---@param settings Settings
---@return SoundNotifier
function Sound.new(settings)
    return setmetatable({ settings = settings }, Sound)
end

---@param _ AlertEvent ignored: the sound renders only
function Sound:notify(_)
    if self.settings.soundFile then
        PlaySoundFile(self.settings.soundFile, "Master")
        return
    end
    local kitName = self.settings.soundKit
    if type(kitName) ~= "string" or kitName == "" then
        return
    end
    local kitId = SOUNDKIT and SOUNDKIT[kitName] or nil
    if type(kitId) ~= "number" then
        return
    end
    PlaySound(kitId, "Master")
end

V.adapters.SoundNotifier = Sound
return Sound
