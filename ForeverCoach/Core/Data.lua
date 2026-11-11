-- Data registry: spells, profiles, builds and quests live in Data/*.lua as plain tables.
-- Only the player's class is built and kept in memory; tools and tests set Data.loadAll = true.
--
-- Spell definition (Data/Spells/<Class>.lua):
--   key = {
--     ranks = { {spellID, level, source?}, ... },  -- ascending; source overrides spell.source
--     source = "trainer" | "quest" | "talent" | "class" | "book",
--     role = "filler" | "dot" | "curse" | "drain" | "execute" | "cc" | "defense" | "cooldown"
--            | "pet" | "buff" | "summon" | "utility" | "wand" | "aoe",
--     cast = seconds (fallback, the client's own value wins), channel = true,
--     duration = seconds or {per rank} (debuff on the target -> tracked as debuff.<key>),
--     cooldown = seconds, gcd = false (off the global cooldown),
--     buff = "buffKey" (cast puts this buff on the player), consumes = "buffKey",
--     requires = "debuffKey" (only castable while that debuff is up),
--     consumesDebuff = "debuffKey" (the cast removes that debuff from the target),
--     keepsDebuff = { talent, rank } (with this talent rank the debuff stays),
--     talent = "talentKey" (needs that talent), pet = true (demon ability), petFamily = "voidwalker",
--     harmful = false (no hostile target needed; default true for damage roles)
--   }
local ADDON, ns = ...

local Data = {
    classes = {},   -- token -> class definition
    profiles = {},  -- id -> profile
    builds = {},    -- Talents Forever builds (Data/Builds.lua)
    quests = {},    -- class quests (Data/Quests.lua)
    trainers = {},  -- class trainers (Data/Trainers.lua)
    loadAll = false,
}
ns.Data = Data

Data.playerClass = UnitClass and select(2, UnitClass("player")) or nil

local HARMFUL_ROLES = {
    filler = true, dot = true, curse = true, drain = true, execute = true, cc = true, wand = true, aoe = true,
}

function Data:Wants(class)
    return self.loadAll or class == self.playerClass
end

local function index(def)
    def.byId = {}        -- spellID -> { key, rank }
    def.debuffById = {}  -- aura spellID -> debuff key
    def.buffById = {}    -- aura spellID -> buff key
    def.itemById = {}    -- itemID -> item key
    for key, sp in pairs(def.spells) do
        sp.key = key
        if sp.harmful == nil then sp.harmful = HARMFUL_ROLES[sp.role] or false end
        for i, r in ipairs(sp.ranks) do
            def.byId[r[1]] = { key = key, rank = i }
            if sp.duration then def.debuffById[r[1]] = key end
        end
    end
    for key, b in pairs(def.buffs or {}) do
        b.key = key
        for _, id in ipairs(b.ids) do def.buffById[id] = key end
    end
    -- A spell that puts a buff on the player (Demon Armor) is recognised by its own IDs too.
    for _, sp in pairs(def.spells) do
        if sp.buff and def.buffs and def.buffs[sp.buff] then
            for _, r in ipairs(sp.ranks) do def.buffById[r[1]] = sp.buff end
        end
    end
    for key, item in pairs(def.items or {}) do
        item.key = key
        for _, id in ipairs(item.ids) do def.itemById[id] = key end
    end
end

-- Data/Spells/<Class>.lua calls this. builder() runs only for the player's class.
function Data:DefineClass(token, builder)
    if not self:Wants(token) then return end
    local def = builder()
    def.token = token
    index(def)
    self.classes[token] = def
    if token == self.playerClass then self.class = def end
end

-- Data/Profiles/<Class>_<Build>_<Mode>.lua calls this.
function Data:DefineProfile(token, builder)
    if not self:Wants(token) then return end
    local p = builder()
    p.class = token
    self.profiles[p.id] = p
end

function Data:DefineBuilds(meta, list)
    self.buildsMeta = meta
    for _, b in ipairs(list) do
        if self:Wants(b.class) then self.builds[#self.builds + 1] = b end
    end
end

function Data:DefineQuests(meta, list)
    self.questsMeta = meta
    for _, q in ipairs(list) do
        if self:Wants(q.class) then self.quests[#self.quests + 1] = q end
    end
end

function Data:DefineTrainers(meta, list)
    self.trainersMeta = meta
    for _, t in ipairs(list) do
        if self:Wants(t.class) then self.trainers[#self.trainers + 1] = t end
    end
end

function Data:ProfilesFor(token)
    local out = {}
    for _, p in pairs(self.profiles) do
        if p.class == token then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- A value that is either a number or a per-rank table (the last entry covers higher ranks).
local function perRank(v, rank)
    if type(v) == "table" then return v[rank or 1] or v[#v] end
    return v
end
Data.PerRank = perRank

function Data.Duration(sp, rank) return perRank(sp.duration, rank) end

-- The debuff a cast removes from the target, given the player's talents (nil: none).
function Data.ConsumedDebuff(sp, talents)
    local key = sp.consumesDebuff
    if not key then return nil end
    local keep = sp.keepsDebuff
    if keep and ((talents or {})[keep.talent] or 0) >= (keep.rank or 1) then return nil end
    return key
end
function Data.Cast(sp, rank) return perRank(sp.cast, rank) or 0 end

-- Highest known rank of every spell: out[key] = spellID, outRank[key] = rank index.
function Data.ResolveKnown(def, isKnown, out, outRank)
    ns.wipe(out)
    ns.wipe(outRank)
    for key, sp in pairs(def.spells) do
        for i = #sp.ranks, 1, -1 do
            local id = sp.ranks[i][1]
            if isKnown(id, sp.pet) then
                out[key] = id
                outRank[key] = i
                break
            end
        end
    end
    return out, outRank
end

-- How many ranks are waiting at the trainer for this level.
-- Ranks below the highest known one don't count (nobody buys old ranks).
function Data.CountTrainable(def, level, knownRank, talents)
    local n = 0
    for key, sp in pairs(def.spells) do
        if not sp.talent or (talents[sp.talent] or 0) > 0 then
            for i = (knownRank[key] or 0) + 1, #sp.ranks do
                local r = sp.ranks[i]
                if r[2] <= level and (r[3] or sp.source) == "trainer" then n = n + 1 end
            end
        end
    end
    return n
end

-- "1.60.1" vs "1.60.2" -> -1, 0, 1
function Data.CompareVersions(a, b)
    local function parts(s)
        local t = {}
        for num in tostring(s):gmatch("%d+") do t[#t + 1] = tonumber(num) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x < y then return -1 elseif x > y then return 1 end
    end
    return 0
end

-- Tell the player once per data version if the client is newer than the data.
function Data:CheckVersion(db)
    local client = ns.API.ClientVersion()
    local def = self.class
    if not client or not def or not def.patch then return end
    if Data.CompareVersions(client, def.patch) > 0 then
        local key = def.token .. "@" .. def.version
        if not db.warnedData[key] then
            db.warnedData[key] = true
            ns.Print(ns.L.DATA_OUTDATED, def.patch, client)
        end
    end
end
