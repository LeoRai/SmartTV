-- Game state: one snapshot of everything the engine needs, rebuilt up to 10 times a second.
--   Rarely changing things (known spells and ranks, talents, bag items) are rescanned on events.
--   Fast things (health, mana, auras, cooldowns, cast, enemies) are read on every refresh.
-- A value the client hides in combat gets a safe fallback (FALLBACK) and is listed in
-- snapshot.hidden, so /fc debug can say "health hidden, assumed 100".
local ADDON, ns = ...
local API, Data, Events, Timers, TTD = ns.API, ns.Data, ns.Events, ns.Timers, ns.TTD
local wipe = ns.wipe

local State = {
    known = {},      -- spell key -> highest known rank spellID
    knownRank = {},  -- spell key -> rank index
    castTime = {},   -- spell key -> seconds (client value, data fallback)
    talents = {},    -- talent key -> rank
    treePoints = nil,
    trainer = 0,     -- ranks waiting at the trainer
    itemCounts = {}, -- item key -> { id = best owned, count = total }
    knownDirty = true,
    itemsDirty = true,
    auraConfirmed = false, -- the client has shown one of our debuffs since the combat started
    aurasBlocked = false,  -- the client refuses aura reads in this combat (Forever): stop asking
    traits = {},           -- talent spellID -> rank from the trait system
    signature = "",
    talentSignature = "",
}
ns.State = State

-- What the engine assumes when the client hides a value. Chosen so that a hidden value never
-- triggers an alarm: full health (no defensive), full mana, long-living target, one enemy.
State.FALLBACK = {
    ["player.hp_pct"] = 100,
    ["player.mana_pct"] = 100,
    ["target.hp_pct"] = 100,
    ["target.ttd"] = 999,
    ["pet.hp_pct"] = 100,
}
local FALLBACK = State.FALLBACK

local GCD_SPELL = 61304 -- the client's global cooldown spell (if present)

-- The snapshot table is reused: no garbage at 10 updates per second.
local s = {
    player = {}, target = {}, pet = {},
    debuffs = {}, buffs = {}, cds = {}, items = {},
    usable = {}, noMana = {}, inRange = {}, hidden = {}, opt = {},
}
State.snapshot = s

local function hide(path, holder, field)
    s.hidden[path] = true
    holder[field] = FALLBACK[path]
end

---------------------------------------------------------------------------
-- Rescans (on events)
---------------------------------------------------------------------------

local function signatureOf(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    table.sort(keys)
    return table.concat(keys, ",")
end

function State:ScanKnown()
    local def = Data.class
    if not def then return end
    Data.ResolveKnown(def, API.IsKnown, self.known, self.knownRank)

    wipe(self.castTime)
    for key, id in pairs(self.known) do
        local sp = def.spells[key]
        self.castTime[key] = API.CastTime(id) or Data.Cast(sp, self.knownRank[key])
        if sp.channel then self.castTime[key] = Data.Cast(sp, self.knownRank[key]) end
    end

    local traits = API.TraitRanks(self.traits)
    local byName
    for key, t in pairs(def.talents or {}) do
        local rank = traits and traits[t.ids[1]] or 0
        if rank == 0 then
            for i = #t.ids, 1, -1 do
                if API.IsKnown(t.ids[i]) then rank = i; break end
            end
        end
        if rank == 0 then
            byName = byName or API.TalentRanksByName()
            local name = API.SpellName(t.ids[1])
            if name and byName[name] then rank = byName[name] end
        end
        self.talents[key] = rank
    end
    -- Points per tree: the classic API is gone in Forever; the trait ranks are split into trees
    -- by the Talents Forever layout when that addon is installed.
    self.treePoints = API.TreePoints()
    if not self.treePoints and traits and ns.TalentsForever then
        self.treePoints = ns.TalentsForever.TreePoints(def.token, traits)
    end

    local level = API.UnitLevel("player") or 1
    self.trainer = Data.CountTrainable(def, level, self.knownRank, self.talents)

    local sig = signatureOf(self.known)
    if sig ~= self.signature then
        self.signature = sig
        Events:Fire("FC_SPELLS_CHANGED")
    end
    local tsig = signatureOf(self.talents) .. "|" .. (self.treePoints and table.concat(self.treePoints, "/") or "")
        .. "|" .. tostring(API.ActiveSpecGroup())
    if tsig ~= self.talentSignature then
        self.talentSignature = tsig
        Events:Fire("FC_TALENTS_CHANGED")
    end
    self.knownDirty = false
end

function State:ScanItems()
    local def = Data.class
    if not def then return end
    for key, item in pairs(def.items or {}) do
        local entry = self.itemCounts[key] or {}
        self.itemCounts[key] = entry
        entry.id, entry.count = nil, 0
        for _, id in ipairs(item.ids) do
            local c = API.ItemCount(id)
            if c > 0 then
                entry.count = entry.count + c
                entry.id = entry.id or id
            end
        end
    end
    self.itemsDirty = false
end

---------------------------------------------------------------------------
-- Refresh (every update)
---------------------------------------------------------------------------

local plates = {}

local function countEnemies(fillerID, targetEnemy, inCombat)
    local n, targetCounted = 0, false
    for _, unit in ipairs(API.NamePlateUnits(plates)) do
        if API.CanAttack(unit) and not API.IsDead(unit) and API.InCombat(unit) ~= false
            and (not fillerID or API.SpellInRange(fillerID, unit) ~= false) then
            n = n + 1
            if UnitIsUnit and API.Clean(UnitIsUnit(unit, "target")) then targetCounted = true end
        end
    end
    if targetEnemy and inCombat and not targetCounted then n = n + 1 end
    if n == 0 and targetEnemy then n = 1 end
    return n
end

-- Aura collectors (module level: no new closures on every refresh).
local curDef
local function collectDebuff(id, expires)
    local key = curDef.debuffById[id]
    if key then s.debuffs[key] = expires > 0 and expires or math.huge end
end
local function collectBuff(id, expires)
    local key = curDef.buffById[id]
    if key then s.buffs[key] = expires > 0 and expires or math.huge end
end

function State:Refresh(now)
    local def = Data.class
    if not def then return nil end
    curDef = def
    if self.knownDirty then self:ScanKnown() end
    if self.itemsDirty then self:ScanItems() end

    wipe(s.hidden)
    s.now = now
    s.def = def
    s.known, s.knownRank, s.castTime, s.talents = self.known, self.knownRank, self.castTime, self.talents
    s.trainer = self.trainer
    s.mode = ns.Modes.current
    s.last = Timers.last
    s.gcd = def.gcd or 1.5

    local db = ns.db or ns.Defaults
    local opt = s.opt
    opt.hp, opt.pet_hp, opt.shards = db.hpThreshold, db.petHpThreshold, db.shards

    -- Player ---------------------------------------------------------------
    local p = s.player
    p.level = API.UnitLevel("player") or p.level or 1
    p.dead = API.IsDead("player")
    local hp = API.HealthPct("player")
    if hp then p.hp_pct = hp else hide("player.hp_pct", p, "hp_pct") end
    local mana, manaMax = API.Mana("player")
    if mana and manaMax and manaMax > 0 then
        p.mana, p.mana_pct = mana, mana * 100 / manaMax
    else
        p.mana = nil
        hide("player.mana_pct", p, "mana_pct")
    end
    local combat = API.InCombat("player")
    if combat == nil then combat = InCombatLockdown and InCombatLockdown() or false end
    p.in_combat = combat and true or false
    p.moving = API.IsMoving() or false

    -- Current cast: the client first, own tracking second. A cast that just finished still counts
    -- until the game confirms it, so its effects are never missing for a moment.
    local castID, castEnd, channel, castStart = API.PlayerCast()
    s.castKey, s.castStart, s.castEnd, s.castChannel = nil, nil, nil, nil
    if castID and def.byId[castID] then
        s.castKey, s.castStart, s.castEnd, s.castChannel = def.byId[castID].key, castStart, castEnd, channel
    elseif not castID then
        local c = Timers:Pending(now)
        if c then
            s.castKey, s.castStart, s.castEnd, s.castChannel = c.key, c.startTime, math.max(c.endTime, now), c.channel
        end
    end
    p.casting = s.castKey ~= nil

    -- Global cooldown: the later of the client's and our own.
    local gStart, gDur = API.SpellCooldown(GCD_SPELL)
    local gcdEnd = (gStart and gDur and gDur > 0) and (gStart + gDur) or 0
    if Timers.gcdEnd > gcdEnd then gcdEnd = Timers.gcdEnd end
    s.gcdEnd = gcdEnd

    -- Target ---------------------------------------------------------------
    local t = s.target
    t.exists = API.UnitExists("target") and not API.IsDead("target")
    t.enemy = t.exists and API.CanAttack("target") or false
    t.guid = t.exists and API.GUID("target") or nil
    t.player = t.exists and API.IsPlayer("target") or false
    local class = t.exists and API.Classification("target") or nil
    local tlevel = t.exists and API.UnitLevel("target") or nil
    t.boss = class == "worldboss" or tlevel == -1
    t.elite = t.boss or class == "elite" or class == "rareelite"
    local fillerID = def.filler and self.known[def.filler]
    t.in_range = true
    if t.exists and fillerID then t.in_range = API.SpellInRange(fillerID, "target") ~= false end
    if t.exists then
        local thp = API.HealthPct("target")
        if thp then
            t.hp_pct = thp
            if t.enemy then TTD:Add(t.guid or "target", now, thp) end
            local ttd = TTD:Get(now)
            t.ttd = ttd or FALLBACK["target.ttd"]
        else
            hide("target.hp_pct", t, "hp_pct")
            hide("target.ttd", t, "ttd")
        end
    else
        t.hp_pct, t.ttd = 0, 0
    end

    -- Demon ----------------------------------------------------------------
    local pe = s.pet
    pe.exists = API.UnitExists("pet") and not API.IsDead("pet")
    pe.family = pe.exists and Timers.pet or nil
    if pe.exists then
        local php = API.HealthPct("pet")
        if php then pe.hp_pct = php else hide("pet.hp_pct", pe, "hp_pct") end
    else
        pe.hp_pct = 0
    end

    -- Own debuffs on the target: client auras, own timers when hidden ---------
    wipe(s.debuffs)
    if t.exists then
        local readable, why = false
        if not (self.aurasBlocked and p.in_combat) then
            readable, why = API.ForEachAura("target", "HARMFUL|PLAYER", collectDebuff)
            if why == "blocked" and p.in_combat then self.aurasBlocked = true end
        end
        if not readable then s.hidden["debuffs"] = true end
        local own, applied = Timers:DebuffsOn(t.guid)
        -- The client may also withhold auras without marking them secret (an empty list).
        -- Own timers are trusted until the client has shown one of our debuffs in this combat.
        if readable and not self.auraConfirmed then
            for key in pairs(own) do
                if s.debuffs[key] then self.auraConfirmed = true; break end
            end
        end
        local trustOwn = not readable or not self.auraConfirmed
        for key, expires in pairs(own) do
            if expires > now and s.debuffs[key] == nil then
                local fresh = now - (applied[key] or 0) < 1.0 -- cast landing, projectile in flight
                if trustOwn or fresh then
                    s.debuffs[key] = expires
                    if not fresh then s.hidden["debuffs"] = true end
                end
            end
        end
    end

    -- Buffs on the player --------------------------------------------------
    wipe(s.buffs)
    local readable, why = false
    if not (self.aurasBlocked and p.in_combat) then
        readable, why = API.ForEachAura("player", "HELPFUL", collectBuff)
        if why == "blocked" and p.in_combat then self.aurasBlocked = true end
    end
    if not readable then
        s.hidden["buffs"] = true
        for key, expires in pairs(Timers.buffs) do
            if expires > now then s.buffs[key] = expires end
        end
    end
    -- The client's own proc highlight on a spell is proof enough that the proc buff is up.
    for key, b in pairs(def.buffs or {}) do
        if b.glow and Timers.glow[b.glow] and not s.buffs[key] then s.buffs[key] = now + (b.duration or 10) end
    end

    -- Cooldowns ------------------------------------------------------------
    wipe(s.cds)
    for key, id in pairs(self.known) do
        local sp = def.spells[key]
        if sp.cooldown then
            local start, dur = API.SpellCooldown(id)
            if start and dur then
                if dur > s.gcd and start > 0 then s.cds[key] = start + dur end
            else
                s.hidden["cooldowns"] = true
                local ready = Timers.cd[key]
                if ready and ready > now then s.cds[key] = ready end
            end
        end
    end

    -- Usable right now (resource, requirements) ------------------------------
    wipe(s.usable); wipe(s.noMana); wipe(s.inRange)
    for key, id in pairs(self.known) do
        local usable, noMana = API.SpellUsable(id)
        s.usable[key], s.noMana[key] = usable, noMana
        if t.exists and def.spells[key].harmful then s.inRange[key] = API.SpellInRange(id, "target") end
    end
    p.oom = def.filler ~= nil and s.noMana[def.filler] == true
    local wand = API.HasWand()
    if wand == nil then wand = s.usable.shoot == true end
    s.hasWand = wand

    -- Items ----------------------------------------------------------------
    for key, entry in pairs(self.itemCounts) do
        local it = s.items[key] or {}
        s.items[key] = it
        it.id, it.count, it.readyAt = entry.id, entry.count, 0
        if entry.id then
            local start, dur = API.ItemCooldown(entry.id)
            if start and dur and dur > 0 then it.readyAt = start + dur end
        end
    end
    s.shards = s.items.soul_shard and s.items.soul_shard.count or 0

    -- Enemies near ---------------------------------------------------------
    s.enemies = countEnemies(fillerID, t.enemy, p.in_combat)

    return s
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function knownDirty()
    State.knownDirty = true
    Events:Fire("FC_DIRTY")
end
for _, event in ipairs({
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP",
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PET_BAR_UPDATE",
}) do
    Events:On(event, State, knownDirty)
end
Events:On("UNIT_PET", State, knownDirty, "player")
local function newCombat(self) self.auraConfirmed, self.aurasBlocked = false, false end
Events:On("PLAYER_REGEN_DISABLED", State, newCombat)
Events:On("PLAYER_REGEN_ENABLED", State, newCombat)
Events:On("PLAYER_ENTERING_WORLD", State, newCombat)
-- Class trainers the player visits: the preparation line names the last one ("· Brill").
-- Stage 2 adds the nearest trainer from Data/Trainers.lua.
Events:On("TRAINER_SHOW", State, function()
    if IsTradeskillTrainer and API.Clean(IsTradeskillTrainer()) then return end
    local place = GetSubZoneText and API.Clean(GetSubZoneText())
    if not place or place == "" then place = GetRealZoneText and API.Clean(GetRealZoneText()) end
    if place and place ~= "" and ns.db then ns.db.trainerPlace = place end
end)
Events:On("BAG_UPDATE_DELAYED", State, function(self)
    self.itemsDirty = true
    Events:Fire("FC_DIRTY")
end)
Events:On("FC_LOGIN", State, function(self)
    self.knownDirty, self.itemsDirty = true, true
end)
