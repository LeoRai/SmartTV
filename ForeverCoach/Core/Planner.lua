-- Planner (stage 2): everything the chosen build's rotation still needs, by status:
--   trainer  a rank or spell waiting at the trainer (with its price)
--   talent   the next talent point of the build
--   nobar    learned, but not on the action bars
--   level    opens at a later level
--   quest    comes from a class quest
-- plus the trainer summary, class quests and a preview of the rotation at another level.
local ADDON, ns = ...
local API, Data, Events, L = ns.API, ns.Data, ns.Events, ns.L

local Planner = {}
ns.Planner = Planner

Planner.ORDER = { trainer = 1, talent = 2, nobar = 3, level = 4, quest = 5 }
Planner.PREVIEW_STEPS = { 0, 2, 6, 8, 12, 18 } -- levels shown in the preview, from the current one

local function srcOf(sp, r) return r[3] or sp.source end

-- Price in the client's coin format (icons), or plain gold/silver/copper.
function Planner.Money(copper)
    if not copper then return L.PRICE_UNKNOWN end
    if GetCoinTextureString then
        local ok, text = pcall(GetCoinTextureString, copper)
        if ok and text then return text end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. L.COIN_GOLD end
    if s > 0 then parts[#parts + 1] = s .. L.COIN_SILVER end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. L.COIN_COPPER end
    return table.concat(parts, " ")
end

-- Ranks waiting at the trainer now: { count, cost, unknownCost, list = { {key, rank, id, level, cost} } }.
function Planner.TrainerSummary(def, level, knownRank, talents)
    local out = { count = 0, cost = 0, unknownCost = false, list = {} }
    for key, sp in pairs(def.spells) do
        if not sp.talent or (talents[sp.talent] or 0) > 0 then
            for i = (knownRank[key] or 0) + 1, #sp.ranks do
                local r = sp.ranks[i]
                if r[2] <= level and srcOf(sp, r) == "trainer" then
                    local cost = def.costs and def.costs[r[1]]
                    out.count = out.count + 1
                    if cost then out.cost = out.cost + cost else out.unknownCost = true end
                    out.list[#out.list + 1] = { key = key, rank = i, id = r[1], level = r[2], cost = cost }
                end
            end
        end
    end
    table.sort(out.list, function(a, b) return a.level < b.level or (a.level == b.level and a.id < b.id) end)
    return out
end

-- Where to go: the trainer visited last, else the known one for the class and faction.
-- { npc, place, map, x, y } or nil.
function Planner.Trainer(def)
    local visit = ns.db and ns.db.trainerVisit
    if visit then return visit end
    local faction = UnitFactionGroup and API.Clean(UnitFactionGroup("player"))
    local locale = GetLocale and GetLocale() or "enUS"
    for _, t in ipairs(Data.trainers) do
        if t.class == def.token and (not faction or not t.faction or t.faction == faction) then
            local place
            if C_Map and C_Map.GetMapInfo then
                local info = C_Map.GetMapInfo(t.map)
                place = info and API.Clean(info.name)
            end
            return { npc = t.npc[locale] or t.npc.enUS, place = place, map = t.map, x = t.x, y = t.y }
        end
    end
    return nil
end

-- Class quests with their state: { key, level, gives, done, available }.
function Planner.Quests(def, known, level)
    local out = {}
    for _, q in ipairs(Data.quests) do
        if q.class == def.token then
            out[#out + 1] = { key = q.key, level = q.level, gives = q.gives,
                              done = known[q.gives] ~= nil, available = level >= q.level }
        end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

-- Spells the rotation of a profile uses (main, defense, cooldown rows; no items, no demon abilities).
local function profileSpells(def, profile)
    local keys, seen = {}, {}
    for _, row in ipairs({ "main", "defense", "cooldown" }) do
        for _, entry in ipairs(profile and profile[row] or {}) do
            local key = entry[1]
            local sp = def.spells[key]
            if sp and not sp.pet and not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    return keys
end

-- What the rotation still needs. s: the state (known, knownRank, talents), level, onBars(key).
function Planner.Needs(def, profile, s, level, onBars, nextTalent)
    local out = {}
    for _, key in ipairs(profileSpells(def, profile)) do
        local sp = def.spells[key]
        local have = s.knownRank[key] or 0
        local item
        if have > 0 then
            -- a newer rank waiting at the trainer?
            for i = #sp.ranks, have + 1, -1 do
                local r = sp.ranks[i]
                if r[2] <= level and srcOf(sp, r) == "trainer" then
                    item = { key = key, status = "trainer", rank = i, id = r[1], cost = def.costs and def.costs[r[1]] }
                    break
                end
            end
            if not item and onBars and not onBars(key) and sp.role ~= "wand" then
                item = { key = key, status = "nobar", id = s.known[key] }
            end
        else
            local first = sp.ranks[1]
            local src = srcOf(sp, first)
            if sp.talent and (s.talents[sp.talent] or 0) == 0 then
                item = { key = key, status = "talent", id = first[1], level = first[2] }
            elseif first[2] > level then
                item = { key = key, status = src == "quest" and "quest" or "level", id = first[1], level = first[2] }
            elseif src == "quest" then
                item = { key = key, status = "quest", id = first[1], level = first[2] }
            elseif src == "trainer" then
                item = { key = key, status = "trainer", rank = 1, id = first[1], cost = def.costs and def.costs[first[1]] }
            end
        end
        if item then out[#out + 1] = item end
    end
    if nextTalent then
        out[#out + 1] = { key = "talent:" .. nextTalent.spellID, status = "talent", id = nextTalent.spellID,
                          name = nextTalent.name, rank = nextTalent.rank, level = nextTalent.level, now = nextTalent.now }
    end
    -- class quests not done yet (the demons)
    for _, q in ipairs(Planner.Quests(def, s.known, level)) do
        if not q.done then
            local sp = def.spells[q.gives]
            out[#out + 1] = { key = q.gives, status = "quest", id = sp and sp.ranks[1][1], level = q.level, quest = q.key }
        end
    end
    local seen, unique = {}, {}
    for _, it in ipairs(out) do
        if not seen[it.key] then seen[it.key] = true; unique[#unique + 1] = it end
    end
    table.sort(unique, function(a, b)
        local oa, ob = Planner.ORDER[a.status], Planner.ORDER[b.status]
        if oa ~= ob then return oa < ob end
        return (a.level or 0) < (b.level or 0)
    end)
    return unique
end

-- Levels offered in the preview: the current one and a few ahead.
function Planner.PreviewLevels(level)
    local out = {}
    for _, step in ipairs(Planner.PREVIEW_STEPS) do
        local l = math.min(60, level + step)
        if out[#out] ~= l then out[#out + 1] = l end
    end
    return out
end

-- Ranks and spells that appear between the current level (exclusive) and `at` (inclusive).
function Planner.NewAt(def, level, at, talents)
    local out = {}
    for key, sp in pairs(def.spells) do
        for i, r in ipairs(sp.ranks) do
            local src = srcOf(sp, r)
            if r[2] > level and r[2] <= at and src ~= "book" and src ~= "talent" and not sp.pet
                and (not sp.talent or (talents[sp.talent] or 0) > 0) then
                out[#out + 1] = { key = key, rank = i, id = r[1], level = r[2], first = i == 1 }
            end
        end
    end
    table.sort(out, function(a, b) return a.level < b.level or (a.level == b.level and a.key < b.key) end)
    return out
end

-- The rotation the engine would suggest at another level: a fresh fight on a healthy target, all
-- trainer ranks up to that level, the current talents and demon. Uses its own engine instance.
local previewEngine = {}
function Planner.RotationAt(def, prepared, at, s, depth)
    if not prepared then return {} end
    local known, knownRank, castTime = {}, {}, {}
    for key, sp in pairs(def.spells) do
        for i = #sp.ranks, 1, -1 do
            local r = sp.ranks[i]
            local src = srcOf(sp, r)
            local ok = r[2] <= at and src ~= "book" and not sp.pet
            if sp.talent then ok = ok and (s.talents[sp.talent] or 0) > 0 end
            if src == "talent" then ok = (s.knownRank[key] or 0) >= i end
            if ok then
                known[key], knownRank[key] = r[1], i
                castTime[key] = s.castTime and s.castTime[key] or Data.Cast(sp, i)
                break
            end
        end
    end
    local snap = {
        now = 0, def = def, known = known, knownRank = knownRank, castTime = castTime, talents = s.talents,
        trainer = 0, mode = ns.Modes.current, last = {}, gcd = def.gcd or 1.5, gcdEnd = 0, opt = s.opt or {},
        player = { level = at, hp_pct = 100, mana_pct = 100, in_combat = true, oom = false },
        target = { exists = true, enemy = true, hp_pct = 100, ttd = 999, in_range = true },
        pet = { exists = s.pet and s.pet.exists, family = s.pet and s.pet.family, hp_pct = 100 },
        debuffs = {}, buffs = {}, cds = {}, items = {}, usable = {}, noMana = {}, inRange = {}, hidden = {},
        enemies = 1, shards = s.shards or 0, hasWand = true,
    }
    local r = ns.Engine.Recommend(previewEngine, snap, prepared, depth or 4)
    local out = {}
    for i = 1, r.mainCount do out[i] = { key = r.main[i].action, id = r.main[i].id } end
    return out
end

-- Remember the class trainer the player visits (name, city, coordinates).
Events:On("TRAINER_SHOW", Planner, function()
    if IsTradeskillTrainer and API.Clean(IsTradeskillTrainer()) then return end
    if not ns.db then return end
    local visit = { npc = UnitName and API.Clean(UnitName("npc")) }
    visit.place = GetSubZoneText and API.Clean(GetSubZoneText())
    if not visit.place or visit.place == "" then visit.place = GetRealZoneText and API.Clean(GetRealZoneText()) end
    if C_Map and C_Map.GetBestMapForUnit then
        pcall(function()
            local map = C_Map.GetBestMapForUnit("player")
            local pos = map and C_Map.GetPlayerMapPosition(map, "player")
            if pos then
                local x, y = pos:GetXY()
                visit.map, visit.x, visit.y = map, math.floor(x * 1000) / 10, math.floor(y * 1000) / 10
            end
        end)
    end
    ns.db.trainerVisit = visit
end)
