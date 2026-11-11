-- Own timers from the player's casts.
-- The fallback for everything the client may hide in combat: debuffs on the target, cooldowns,
-- the global cooldown and the current cast. Built from UNIT_SPELLCAST_* events of the player
-- and the known durations in Data/Spells. Misses resists and early removal: the client's own
-- values win whenever they are readable (Core/State.lua merges both).
local ADDON, ns = ...
local API, Data = ns.API, ns.Data

local Timers = {
    cast = nil,     -- { key, id, startTime, endTime, channel, guid }
    landing = nil,  -- a cast that just finished, until the game confirms (SUCCEEDED) or refuses it
    gcdEnd = 0,
    last = {},      -- key -> time of the last successful cast
    cd = {},        -- key -> ready at
    debuffs = {},   -- target GUID -> key -> expires
    applied = {},   -- target GUID -> key -> applied at
    buffs = {},     -- buff key -> expires
    glow = {},      -- spell key -> true while the client highlights it (proc)
    pet = nil,      -- demon family key
    targetGUID = nil,
    lastSent = nil, -- when the player last pressed a spell (it may still be queued)
}
ns.Timers = Timers

local MAX_TARGETS = 30
local now = GetTime

local function classDef() return Data.class end

local function lookup(spellID)
    local def = classDef()
    local id = API.Clean(spellID)
    if not def or type(id) ~= "number" then return nil end
    local info = def.byId[id]
    if not info then return nil end
    return info.key, info.rank, def.spells[info.key], def
end

local function guidKey(guid) return guid or "?" end

function Timers:Reset()
    self.cast, self.gcdEnd = nil, 0
    ns.wipe(self.last); ns.wipe(self.cd); ns.wipe(self.debuffs); ns.wipe(self.applied)
    ns.wipe(self.buffs); ns.wipe(self.glow)
end

-- Cast started (has a cast time) or channel started.
function Timers:OnCastStart(spellID, t, channel)
    local key, rank, sp, def = lookup(spellID)
    if not key then return end
    local castTime = API.CastTime(spellID) or Data.Cast(sp, rank)
    self.cast = {
        key = key, id = spellID, startTime = t, endTime = t + castTime, channel = channel,
        guid = self.targetGUID,
    }
    if sp.gcd ~= false then self.gcdEnd = t + (def.gcd or 1.5) end
end

-- How long a finished cast counts as landing while the game's confirmation is on its way.
-- Covers the server round trip: without it the hint shows the spell again for a moment
-- (player report: Immolate came back for a second right after it was cast).
Timers.LANDING_GRACE = 0.6

-- The cast bar ended. A cast that reached its end is landing until SUCCEEDED or FAILED arrives;
-- one stopped early is simply gone.
function Timers:OnCastStop(t)
    local c = self.cast
    self.cast = nil
    if c and not c.channel and t and t >= c.endTime - 0.2 then
        c.landingUntil = t + Timers.LANDING_GRACE
        self.landing = c
    end
end

-- FAILED / INTERRUPTED / CHANNEL_STOP: nothing lands.
function Timers:OnCastCancel()
    self.cast, self.landing = nil, nil
end

-- The cast to play forward at time t: the one in progress, else the one landing right now.
function Timers:Pending(t)
    local c = self.cast
    if c and (c.endTime > t or (not c.channel and t - c.endTime < Timers.LANDING_GRACE)) then return c end
    local l = self.landing
    if l and l.landingUntil > t then return l end
    return nil
end

-- The spell went off: start cooldowns, debuffs and buffs.
function Timers:OnCastSucceeded(spellID, t, targetGUID)
    local key, rank, sp, def = lookup(spellID)
    if not key then return end
    local current = self.cast
    local wasCast = current and current.id == spellID
    if not wasCast and self.landing and self.landing.id == spellID then
        current, wasCast = self.landing, true -- the cast bar already stopped: same cast, confirmed now
    end
    if not wasCast and sp.gcd ~= false then
        self.gcdEnd = t + (def.gcd or 1.5) -- instant spell: no START event before this one
    end
    if wasCast and not current.channel then self.cast = nil end
    if wasCast then self.landing = nil end

    self.last[key] = t
    if sp.cooldown then self.cd[key] = t + sp.cooldown end
    if sp.duration and sp.harmful then
        local g = guidKey(targetGUID or (wasCast and current.guid) or self.targetGUID)
        self.debuffs[g] = self.debuffs[g] or {}
        self.applied[g] = self.applied[g] or {}
        self.debuffs[g][key] = t + (Data.Duration(sp, rank) or 0)
        self.applied[g][key] = t
    end
    if sp.buff and def.buffs and def.buffs[sp.buff] then
        self.buffs[sp.buff] = t + (def.buffs[sp.buff].duration or 0)
    end
    if sp.consumes then self.buffs[sp.consumes] = nil end
    if sp.role == "summon" and def.pets then
        for family, p in pairs(def.pets) do
            if p.summon == key then
                self.pet = family
                if ns.db then ns.db.lastPet = family end
            end
        end
    end
end

-- Own debuff timers on a target: key -> expires, key -> applied at (may be empty tables).
local EMPTY = {}
function Timers:DebuffsOn(guid)
    local g = guidKey(guid)
    return self.debuffs[g] or EMPTY, self.applied[g] or EMPTY
end

function Timers:OnTargetChanged(guid, t)
    self.targetGUID = guid
    -- Prune expired timers and keep the table small.
    local count = 0
    for g, list in pairs(self.debuffs) do
        local alive = false
        for key, expires in pairs(list) do
            if expires <= t then
                list[key] = nil
                if self.applied[g] then self.applied[g][key] = nil end
            else
                alive = true
            end
        end
        if not alive then
            self.debuffs[g], self.applied[g] = nil, nil
        else
            count = count + 1
        end
    end
    if count > MAX_TARGETS then ns.wipe(self.debuffs); ns.wipe(self.applied) end
end

-- Which demon is out: client family name first, last summon second.
function Timers:DetectPet()
    local def = classDef()
    if not def or not def.pets then return end
    if not API.UnitExists("pet") then
        self.pet = nil
        return
    end
    local family = UnitCreatureFamily and API.Clean(UnitCreatureFamily("pet"))
    if family then
        for key, p in pairs(def.pets) do
            for _, name in ipairs(p.names) do
                if name == family then
                    self.pet = key
                    if ns.db then ns.db.lastPet = key end
                    return
                end
            end
        end
    end
    self.pet = self.pet or (ns.db and ns.db.lastPet) or nil
end

-- Event wiring --------------------------------------------------------------

local Events = ns.Events

local function dirty() Events:Fire("FC_DIRTY") end

Events:On("UNIT_SPELLCAST_SENT", Timers, function(self)
    self.lastSent = now()
end, "player")
Events:On("UNIT_SPELLCAST_START", Timers, function(self, _, _, _, spellID)
    self:OnCastStart(spellID, now(), false); dirty()
end, "player")
Events:On("UNIT_SPELLCAST_CHANNEL_START", Timers, function(self, _, _, _, spellID)
    self:OnCastStart(spellID, now(), true)
    self:OnCastSucceeded(spellID, now(), self.targetGUID) -- channels report success at the start
    dirty()
end, "player")
Events:On("UNIT_SPELLCAST_STOP", Timers, function(self) self:OnCastStop(now()); dirty() end, "player")
for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    Events:On(event, Timers, function(self) self:OnCastCancel(); dirty() end, "player")
end
Events:On("UNIT_SPELLCAST_SUCCEEDED", Timers, function(self, _, _, _, spellID)
    local current = self.cast
    if current and current.channel and current.id == API.Clean(spellID) then return end
    self:OnCastSucceeded(spellID, now(), nil); dirty()
end, "player")
Events:On("PLAYER_TARGET_CHANGED", Timers, function(self)
    self:OnTargetChanged(API.GUID("target"), now()); dirty()
end)
Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", Timers, function(self, _, spellID)
    local key = lookup(spellID)
    if key then self.glow[key] = true; dirty() end
end)
Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", Timers, function(self, _, spellID)
    local key = lookup(spellID)
    if key then self.glow[key] = nil; dirty() end
end)
Events:On("UNIT_PET", Timers, function(self) self:DetectPet(); dirty() end, "player")
Events:On("FC_LOGIN", Timers, function(self) self:DetectPet() end)
