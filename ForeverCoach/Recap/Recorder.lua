-- Fight recorder (stage 3): the player's presses against the hints the addon showed, idle
-- pauses, the player's debuffs on the target and procs. Everything comes from the player's own
-- casts and the hints; the combat log is closed to addons in Forever, so no damage is read.
-- A fight is one stretch of combat (PLAYER_REGEN_DISABLED .. ENABLED). Fights shorter than the
-- setting (10 s) or without a single press are dropped; the last 10 are kept per character.
local ADDON, ns = ...
local L, API, Data, Events = ns.L, ns.API, ns.Data, ns.Events
local Metrics = ns.RecapMetrics

local Recorder = {
    fight = nil,     -- the fight being recorded
    seen = {},       -- action -> last time it was shown as a hint (main, gated, defense, cooldown)
    hint = nil,      -- the main hint now: { action, id, reason, arg }
    casting = {},    -- castGUID -> true: the cast is already counted as a press
    started = {},    -- spellID -> when its cast started (for clients without cast GUIDs)
    lastShot = nil,  -- the wand's last shot (auto-repeat reports every shot)
    autoRepeat = false,
    session = nil,   -- the current session (saved)
}
ns.Recorder = Recorder

local now = GetTime
local WAND_GAP = 3 -- a wand press counts again only after this long without a shot

-- Roles that are part of a rotation; summons, buffs and stones in combat are not judged.
local JUDGED = { filler = true, dot = true, curse = true, drain = true, execute = true, cc = true, defense = true,
                 cooldown = true, pet = true, wand = true, aoe = true }

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------

function Recorder.Store()
    local db = ns.db
    db.recap = db.recap or {}
    local r = db.recap
    r.fights = r.fights or {}
    r.sessions = r.sessions or {}
    r.records = r.records or {}
    return r
end

function Recorder:StartSession()
    local store = Recorder.Store()
    self.session = { start = time and time() or 0, at = date and date("%d.%m %H:%M") or nil, fights = 0, accSum = 0,
                     blind = 0, blindAccSum = 0 }
    store.sessions[#store.sessions + 1] = self.session
    while #store.sessions > Metrics.SESSIONS_KEPT do table.remove(store.sessions, 1) end
end

---------------------------------------------------------------------------
-- Fight
---------------------------------------------------------------------------

function Recorder:StartFight(t)
    self.fight = {
        start = t, lastTick = t, presses = 0, matched = 0, reactSum = 0, reactN = 0, idle = 0, pauses = 0,
        debuffUp = 0, debuffTotal = 0, tracked = {}, procs = 0, missed = 0, procOpen = {}, procUsed = {},
        events = {}, errors = {}, targets = {}, at = date and date("%H:%M") or nil,
    }
    ns.wipe(self.seen)
    self.hint = nil
end

local function addError(f, e)
    if #f.errors < Metrics.MAX_ERRORS then f.errors[#f.errors + 1] = e end
end

-- An idle stretch ends: count it when it was long enough.
function Recorder:CloseIdle(t)
    local f = self.fight
    if not (f and f.idleStart) then return end
    local gap = t - f.idleStart
    if gap >= Metrics.IDLE_PAUSE then
        f.idle = f.idle + gap
        f.pauses = f.pauses + 1
        f.events[#f.events + 1] = "-"
        local h = f.idleHint
        addError(f, { t = f.idleStart - f.start, kind = "idle", gap = gap, hint = h and h.action, hintId = h and h.id })
    end
    f.idleStart, f.idleHint = nil, nil
end

-- The player started a spell (a cast, a channel, or an instant that went off).
function Recorder:OnPress(spellID, t)
    local f = self.fight
    local def = Data.class
    if not (f and def) then return end
    local info = def.byId[API.Clean(spellID) or 0]
    if not info then return end
    local key, sp = info.key, def.spells[info.key]
    local inProfile = ns.Loop.current and ns.Loop.current.uses and ns.Loop.current.uses[key]
    if not (JUDGED[sp.role] or inProfile) then return end

    self:CloseIdle(t)
    f.presses = f.presses + 1
    local shown = self.seen[key]
    local hint = self.hint
    if shown and shown >= t - Metrics.PRESS_WINDOW then
        f.matched = f.matched + 1
        f.events[#f.events + 1] = "o"
    else
        f.events[#f.events + 1] = "x"
        if hint then
            addError(f, { t = t - f.start, kind = "miss", pressed = key, pressedId = API.Clean(spellID), hint = hint.action,
                          hintId = hint.id, reason = hint.reason, arg = hint.arg })
        end
    end
    -- Reaction: from the moment the player could press to the press (0 when queued in advance).
    local react = f.readyAt and math.min(Metrics.REACT_CAP, math.max(0, t - f.readyAt)) or 0
    f.reactSum, f.reactN = f.reactSum + react, f.reactN + 1
    f.readyAt = nil
    if sp.consumes and f.procOpen[sp.consumes] then f.procUsed[sp.consumes] = true end
end

-- What a hint was about, for the error text: a missing debuff, a proc, mana, AoE or its reason.
local function reasonOf(rec, s, def)
    local sp = def.spells[rec.action]
    if rec.glow then return "proc" end
    if sp then
        if sp.restoresMana then return "mana" end
        if sp.role == "aoe" then return "aoe", s.enemies end
        if sp.duration and sp.harmful then
            local exp = s.debuffs[rec.action]
            if not exp or exp <= s.now then return "down" end
            return "low", exp - s.now
        end
    end
    return "why", rec.line and rec.line.why
end

local function inForecast(r, key)
    for i = 1, r.mainCount do
        if r.main[i].action == key then return true end
    end
    return false
end

local function isDebuff(def, key)
    local sp = def.spells[key]
    return sp and sp.duration and sp.harmful and (sp.role == "dot" or sp.role == "curse") or false
end

-- Every update (10 times a second in combat): hints on screen, idle time, debuffs, procs.
function Recorder:OnTick(r, s, t)
    local f, def = self.fight, Data.class
    if not (f and r and s and def) then return end
    local dt = math.max(0, math.min(0.5, t - f.lastTick))
    f.lastTick = t

    -- Hints on screen now.
    local main = r.mainCount > 0 and r.main[1] or nil
    if main then
        self.seen[main.action] = t
        local reason, arg = reasonOf(main, s, def)
        self.hint = { action = main.action, id = main.id, reason = reason, arg = arg }
    end
    for _, g in ipairs(r.gatedMains) do self.seen[g.action] = t end
    for _, g in ipairs(r.gatedDefense) do self.seen[g.action] = t end
    if r.hasDefense then self.seen[r.defense.action] = t end
    if r.hasCooldown then self.seen[r.cooldown.action] = t end

    -- Whom the fight was with: the target held longest.
    if s.target.enemy then
        local name = API.Clean(UnitName and UnitName("target"))
        if name then f.targets[name] = (f.targets[name] or 0) + dt end
    end

    -- Idle: the player could press the hint, but nothing is cast, no global cooldown, no wand.
    local wanding = self.autoRepeat or (self.lastShot ~= nil and t - self.lastShot < WAND_GAP)
    local busy = s.castKey ~= nil or s.gcdEnd > t + 0.05 or wanding
    local canAct = main ~= nil and s.target.enemy and not s.player.dead and not s.player.moving
        and not main.outOfRange and main.wait <= 0.1
    if canAct and not busy then
        f.readyAt = f.readyAt or t
        if not f.idleStart then f.idleStart, f.idleHint = t, { action = main.action, id = main.id } end
    else
        f.readyAt = nil
        self:CloseIdle(t)
    end

    -- Debuffs on the target: the profile's dots and curses the player knows, counted while up
    -- or while the hints ask for them (a curse the rotation does not use stays out).
    if not f.trackedReady and r.prepared then
        for key in pairs(r.prepared.uses or {}) do
            if isDebuff(def, key) and s.known[key] then f.tracked[key] = true end
        end
        f.trackedReady = true
    end
    if s.target.enemy then
        for key in pairs(f.tracked) do
            local up = (s.debuffs[key] or 0) > t
            if up or inForecast(r, key) then
                f.debuffTotal = f.debuffTotal + dt
                if up then f.debuffUp = f.debuffUp + dt end
            end
        end
    end

    -- Procs: a proc buff that ends without its spell being cast is a missed proc.
    for key, b in pairs(def.buffs or {}) do
        if b.glow then
            local up = (s.buffs[key] or 0) > t
            if up and not f.procOpen[key] then
                f.procOpen[key], f.procUsed[key] = t, false
                f.procs = f.procs + 1
            elseif not up and f.procOpen[key] then
                if not f.procUsed[key] then f.missed = f.missed + 1 end
                f.procOpen[key], f.procUsed[key] = nil, nil
            end
        end
    end
end

-- The talent that gives a proc, when the player does not have it yet: { key, id, level }.
local function missingProcTalent(def, talents)
    for _, b in pairs(def.buffs or {}) do
        if b.glow and b.talent and (talents[b.talent] or 0) == 0 then
            local t = def.talents and def.talents[b.talent]
            local id = t and t.ids[1]
            local level
            local TF = ns.TalentsForever
            local layout = TF and TF.Available() and TF.Layout(def.token)
            if layout and id then
                for _, tree in ipairs(layout.talents) do
                    for _, tal in ipairs(tree) do
                        if tal.spell == id and tal.row then level = 10 + (tal.row - 1) * 5 end
                    end
                end
            end
            return { key = b.talent, id = id, level = level }
        end
    end
    return nil
end

-- Combat ended: keep the fight if it was long enough and had presses.
function Recorder:EndFight(t)
    local f = self.fight
    if not f then return nil end
    self:CloseIdle(t)
    self.fight = nil
    -- Casts begun before combat (the pull) stay known through the fight; forget them now.
    ns.wipe(self.casting)
    ns.wipe(self.started)
    local dur = t - f.start
    local db = ns.db
    if dur < (db.recapMinFight or 10) or f.presses == 0 then return nil end
    local def = Data.class

    local target, best = nil, -1
    for name, secs in pairs(f.targets) do
        if secs > best then target, best = name, secs end
    end
    local s = ns.State.snapshot
    local rec = {
        at = f.at, dur = dur, target = target, presses = f.presses, matched = f.matched,
        reactSum = f.reactSum, reactN = f.reactN, idle = f.idle, pauses = f.pauses,
        debuffUp = f.debuffUp, debuffTotal = f.debuffTotal, procs = f.procs, missed = f.missed,
        events = table.concat(f.events), errors = f.errors, blind = db.noHints or nil,
        build = ns.BuildMatcher.build, mode = ns.Modes.current, level = s and s.player and s.player.level,
    }
    if f.procs == 0 and def then rec.procTalent = missingProcTalent(def, ns.State.talents or {}) end
    rec.score = Metrics.Score(rec)

    local store = Recorder.Store()
    table.insert(store.fights, 1, rec)
    while #store.fights > Metrics.FIGHTS_KEPT do table.remove(store.fights) end

    local session = self.session
    if session then
        local acc = Metrics.Accuracy(rec)
        session.fights = session.fights + 1
        session.accSum = session.accSum + acc
        if rec.blind then
            session.blind = session.blind + 1
            session.blindAccSum = session.blindAccSum + acc
        end
    end
    if db.training then self:TrainingResult(rec) end
    Events:Fire("FC_FIGHT_RECORDED", rec)
    return rec
end

-- Training: the score after every fight, the best one per build is its record.
function Recorder:TrainingResult(rec)
    local store = Recorder.Store()
    local key = (rec.build or "Generic") .. ":" .. (rec.mode or "leveling")
    local best = store.records[key]
    local acc = math.floor((Metrics.Accuracy(rec) or 0) * 100 + 0.5)
    local speed = math.floor(Metrics.Speed(Metrics.Reaction(rec)) * 100 + 0.5)
    if not best or rec.score > best.score then
        store.records[key] = { score = rec.score, accuracy = acc, speed = speed, at = date and date("%d.%m.%Y") or nil,
                               build = rec.build, mode = rec.mode }
        ns.Print(L.R_TRAINING_RECORD, rec.score, acc, speed)
    else
        ns.Print(L.R_TRAINING_RESULT, rec.score, acc, speed, best.score)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

Events:On("FC_LOGIN", Recorder, function(self) self:StartSession() end)
Events:On("PLAYER_REGEN_DISABLED", Recorder, function(self) self:StartFight(now()) end)
Events:On("PLAYER_REGEN_ENABLED", Recorder, function(self) self:EndFight(now()) end)
Events:On("FC_RECOMMENDATION", Recorder, function(self, _, r, s) self:OnTick(r, s, now()) end)

-- A press: the first sign that a spell started. Casts and channels report START, instants only
-- SUCCEEDED; a cast's own SUCCEEDED later is the same press (same cast GUID; without GUIDs, a
-- success of the spell whose cast started last).
local MAX_CAST = 15
local function begin(self, castGUID, spellID, success)
    local def = Data.class
    local id = API.Clean(spellID)
    local info = def and id and def.byId[id]
    if not info then return end
    local t = now()
    if def.spells[info.key].wand then
        -- Auto-repeat: every shot reports success. A press only when the wand was not shooting.
        local fresh = not self.autoRepeat and (not self.lastShot or t - self.lastShot >= WAND_GAP)
        self.lastShot = t
        if fresh then self:OnPress(id, t) end
        return
    end
    local guid = API.Clean(castGUID)
    if guid then
        if self.casting[guid] then return end
        self.casting[guid] = true
    elseif success then
        local started = self.started[id]
        self.started[id] = nil
        if started and t - started <= MAX_CAST then return end
    else
        self.started[id] = t
    end
    self:OnPress(id, t)
end

Events:On("UNIT_SPELLCAST_START", Recorder, function(self, _, _, castGUID, spellID)
    begin(self, castGUID, spellID, false)
end, "player")
Events:On("UNIT_SPELLCAST_CHANNEL_START", Recorder, function(self, _, _, castGUID, spellID)
    begin(self, castGUID, spellID, false)
end, "player")
Events:On("UNIT_SPELLCAST_SUCCEEDED", Recorder, function(self, _, _, castGUID, spellID)
    begin(self, castGUID, spellID, true)
end, "player")
-- A cast that did not go off: without GUIDs, its later success must not be taken for this one.
for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    Events:On(event, Recorder, function(self, _, _, _, spellID)
        local id = API.Clean(spellID)
        if id then self.started[id] = nil end
    end, "player")
end
Events:On("START_AUTOREPEAT_SPELL", Recorder, function(self) self.autoRepeat = true end)
Events:On("STOP_AUTOREPEAT_SPELL", Recorder, function(self) self.autoRepeat = false end)
