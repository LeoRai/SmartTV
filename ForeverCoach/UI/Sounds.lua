-- Two short signals, each with its own switch and volume:
--   ready  "time to press": a soft neutral click when the global cooldown (or the cast) ends and
--          the suggested action is ready. Silent if the player already pressed in advance.
--   proc   an instant proc became the main hint: a bright chime, clearly louder than the click.
-- PlaySoundFile has no volume argument: Media/Sounds has every signal in 10 volume steps
-- (tools/make_sounds.py, CC0) and the closest one to the setting is played.
local ADDON, ns = ...

local Sounds = {
    waiting = false,   -- the main hint is waiting for the global cooldown or a cast
    waitStart = 0,     -- when that wait began
    pending = nil,     -- time to play the click (a short delay lets a queued press show up)
    lastGlow = false,
}
ns.Sounds = Sounds

local PATH = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Sounds\\"
local CLICK_DELAY = 0.1
local PRESS_GRACE = 0.15 -- presses this soon after the wait began started that wait

-- File for a signal at a volume (0..100): nil when muted.
function Sounds.File(kind, volume)
    if not volume or volume <= 0 then return nil end
    local step = math.floor(volume / 10 + 0.5) * 10
    if step < 10 then step = 10 elseif step > 100 then step = 100 end
    return PATH .. kind .. "_" .. step .. ".ogg"
end

-- Play a signal. preview = true ignores its on/off switch (the button in the settings).
function Sounds:Play(kind, preview)
    local db = ns.db
    local enabled, volume
    if kind == "proc" then
        enabled, volume = db.soundProc, db.soundProcVolume
    else
        enabled, volume = db.soundReady, db.soundReadyVolume
    end
    if not enabled and not preview then return false end
    local file = Sounds.File(kind, volume)
    if not file or not PlaySoundFile then return false end
    PlaySoundFile(file, "Master")
    return true
end

function Sounds:Reset()
    self.waiting, self.pending, self.lastGlow = false, nil, false
end

-- Called after every hint update.
function Sounds:Update(r, s, now)
    local main = r and r.main[1]
    if not (s and main and s.player.in_combat and ns.db.shown) then
        self:Reset()
        return
    end

    local glow = main.glow and true or false
    if glow and not self.lastGlow then
        self:Play("proc")
        self.pending = nil
    end
    self.lastGlow = glow

    if main.wait > 0.05 then
        if not self.waiting then self.waiting, self.waitStart = true, now end
        self.pending = nil -- a new wait began: the player pressed something
        return
    end
    if self.waiting then
        self.waiting = false
        if not glow then self.pending = now + CLICK_DELAY end
    end
    if self.pending and now >= self.pending then
        self.pending = nil
        local sent = ns.Timers.lastSent
        local pressedAhead = sent ~= nil and sent > self.waitStart + PRESS_GRACE
        if not pressedAhead then self:Play("ready") end
    end
end
