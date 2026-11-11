-- Surprise journal: the main hint jumped to an action the queue did not show in time.
-- The player sees the main icon and the forecast after it, so a new main action should have been
-- on screen for a moment before it became the main one. When it was not (it was not in the
-- queue at all, or only flashed through it), the change is noted with the reason the engine gave
-- and the state around it. Notes stay in the saved variables (ForeverCoachCharDB.surprises):
-- /fc surprises prints them, and the player can send the file so the rotation data gets fixed.
local ADDON, ns = ...
local L, API, Data, Engine = ns.L, ns.API, ns.Data, ns.Engine

local Surprises = {
    seen = {},        -- action -> when it entered the shown queue (main icon + next icons)
    spare = {},       -- the same for the next update (two tables swap: no garbage per update)
    queue = {},       -- actions of the previous update, in order
    queueN = 0,
    target = nil,     -- target GUID of the previous update
    fightStart = nil,
}
ns.Surprises = Surprises

Surprises.NOTICE = 0.5 -- less time than this in the queue: the player could not see it coming
Surprises.KEEP = 30    -- notes kept per character
Surprises.SHOW = 10    -- notes printed by /fc surprises

local function round(v) return v and math.floor(v * 10 + 0.5) / 10 or nil end

local function store()
    local db = ns.db
    db.surprises = db.surprises or {}
    return db.surprises
end

function Surprises.List() return store() end
function Surprises.Clear() ns.wipe(store()) end

function Surprises:Reset()
    ns.wipe(self.seen)
    self.queueN, self.target = 0, nil
end

-- Spell name for chat, the data key if the client does not know it.
local function nameOf(key)
    local sp = Data.class and Data.class.spells[key]
    return sp and API.SpellName(sp.ranks[1][1]) or key
end

local function names(text)
    local out = {}
    for key in tostring(text or ""):gmatch("[^>]+") do out[#out + 1] = nameOf(key) end
    return table.concat(out, " > ")
end

function Surprises.Format(n)
    return string.format(L.SURPRISE_LINE, n.at or "?", n.fight or 0, nameOf(n.to), names(n.from), n.why or "")
end

function Surprises:Note(r, s, now, age)
    local queue = {}
    for i = 1, self.queueN do queue[i] = self.queue[i] end
    local rec, sent = r.main[1], ns.Timers.lastSent
    local note = {
        at = date and date("%H:%M:%S") or nil,
        fight = round(now - (self.fightStart or now)), -- seconds into the fight
        to = rec.action,
        from = table.concat(queue, ">"),               -- the queue the player saw before
        age = round(age),                              -- how long the new action was in it
        why = Engine.Explain(rec, s),                  -- the line and the values it saw (* = hidden)
        proc = rec.glow or nil,
        far = rec.outOfRange or nil,
        moving = s.player.moving or nil,
        aoe = r.aoe or nil,
        enemies = s.enemies,
        oom = s.player.oom or nil,
        cast = s.castKey,                              -- what the player is casting now
        pressed = sent and round(now - sent) or nil,   -- seconds since the last button press
        level = s.player.level,
        profile = ns.Loop.current and ns.Loop.current.id or nil,
    }
    local list = store()
    list[#list + 1] = note
    while #list > Surprises.KEEP do table.remove(list, 1) end
    if ns.db.debug then ns.Print(Surprises.Format(note)) end
    return note
end

-- Called after every update with the hint the player now sees.
function Surprises:Track(r, s, now)
    local db = ns.db
    if not (r and s and s.player.in_combat and db.shown and (db.nextIcons or 0) > 0) then
        if self.fightStart then
            self:Reset()
            self.fightStart = nil
        end
        return
    end
    self.fightStart = self.fightStart or now
    local n = r.mainCount or 0
    -- A new target or no hint at all: a fresh queue, nothing to compare with.
    local fresh = self.queueN == 0
    if n == 0 or s.target.guid ~= self.target then
        self:Reset()
        self.target, fresh = s.target.guid, true
        if n == 0 then return end
    end

    -- When each queued action first appeared on screen. The first queue of a fight or a target
    -- is the starting point: the block has just appeared, nothing in it is a jump.
    local seen, nextSeen = self.seen, self.spare
    local since = fresh and now - Surprises.NOTICE or now
    ns.wipe(nextSeen)
    for i = 1, n do
        local action = r.main[i].action
        if not nextSeen[action] then nextSeen[action] = seen[action] or since end
    end
    self.seen, self.spare = nextSeen, seen

    local main = r.main[1].action
    if self.queueN > 0 and main ~= self.queue[1] then
        local age = now - nextSeen[main]
        if age < Surprises.NOTICE then self:Note(r, s, now, age) end
    end

    for i = 1, n do self.queue[i] = r.main[i].action end
    for i = n + 1, self.queueN do self.queue[i] = nil end
    self.queueN = n
end
