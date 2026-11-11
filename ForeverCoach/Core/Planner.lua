-- Planner (stage 2): everything the chosen build's rotation still needs, by status:
--   trainer  a rank or spell waiting at the trainer (with its price)
--   talent   the next talent point of the build, or a rotation spell its talents give
--   quest    comes from a class quest (now: the level is there; later: not yet)
--   nobar    learned, but not on the action bars
--   level    opens at a later level
-- plus the trainer summary, class quests and a preview of the rotation at another level.
local ADDON, ns = ...
local API, Data, Events, L = ns.API, ns.Data, ns.Events, ns.L

local Planner = {}
ns.Planner = Planner

-- What to do now first (buy, spend a point, take a quest, put on the bars), then what comes later.
Planner.ORDER = { trainer = 1, talent = 2, quest = 3, nobar = 4, level = 5, questLater = 6 }
function Planner.Rank(item) return Planner.ORDER[item.later and "questLater" or item.status] end
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

-- The next level at which the trainer has something new (nil at the top).
function Planner.NextTrainerLevel(def, level, knownRank, talents)
    local best
    for key, sp in pairs(def.spells) do
        if not sp.talent or (talents[sp.talent] or 0) > 0 then
            for i = (knownRank[key] or 0) + 1, #sp.ranks do
                local r = sp.ranks[i]
                if r[2] > level and srcOf(sp, r) == "trainer" and (not best or r[2] < best) then best = r[2] end
            end
        end
    end
    return best
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
-- buildTalents: talent keys the build takes (a spell of another talent is not the player's plan).
function Planner.Needs(def, profile, s, level, onBars, nextTalent, buildTalents)
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
                if buildTalents and buildTalents[sp.talent] then
                    item = { key = key, status = "talent", id = first[1], level = first[2] }
                end
            elseif first[2] > level then
                item = { key = key, status = src == "quest" and "quest" or "level", id = first[1], level = first[2],
                         later = src == "quest" or nil }
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
            out[#out + 1] = { key = q.gives, status = "quest", id = sp and sp.ranks[1][1], level = q.level, quest = q.key,
                              later = not q.available or nil }
        end
    end
    local seen, unique = {}, {}
    for _, it in ipairs(out) do
        if not seen[it.key] then seen[it.key] = true; unique[#unique + 1] = it end
    end
    table.sort(unique, function(a, b)
        local oa, ob = Planner.Rank(a), Planner.Rank(b)
        if oa ~= ob then return oa < ob end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        return a.key < b.key
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

-- The chosen build's talent points from now up to level `at`, in the order the site places
-- them (Builds.GuessOrder), skipping the points the player already has. By talent, in order:
-- { { spellID, name, from, to, max, level (when it reaches `to`), now }, ... }, and the number
-- of points. unspent: free points from the client (nil: counted from the level).
Planner.MAX_POINTS = 51
function Planner.TalentsAt(def, buildRanks, playerRanks, level, at, unspent)
    local TF = ns.TalentsForever
    local layout = TF and TF.Layout(def.token)
    if not (layout and buildRanks) then return {}, 0 end
    playerRanks = playerRanks or {}
    local spent = 0
    for _, r in pairs(playerRanks) do spent = spent + r end
    if unspent == nil then unspent = math.max(0, level - 9 - spent) end
    local counted, byId, out, points = {}, {}, {}, 0
    for _, o in ipairs(ns.Builds.GuessOrder(layout, buildRanks)) do
        local t = o.talent
        local id = t.spell
        counted[id] = (counted[id] or 0) + 1
        if counted[id] > (playerRanks[id] or 0) then
            local pointLevel = points < unspent and level or level + (points + 1 - unspent)
            if pointLevel > at or spent + points >= Planner.MAX_POINTS then break end
            points = points + 1
            local e = byId[id]
            if not e then
                e = { spellID = id, name = API.SpellName(id) or t.name, from = playerRanks[id] or 0, max = t.max or 1,
                      first = pointLevel }
                byId[id] = e
                out[#out + 1] = e
            end
            e.to, e.level, e.now = counted[id], pointLevel, pointLevel <= level
        end
    end
    return out, points
end

-- The level at which each of our talent keys gets its first point in the plan (now: `level`).
local function talentLevels(def, current, plan, level)
    local out = {}
    for key, rank in pairs(current or {}) do
        if rank > 0 then out[key] = level end
    end
    for _, e in ipairs(plan or {}) do
        for key, t in pairs(def.talents or {}) do
            if t.ids[1] == e.spellID and not out[key] then out[key] = e.first end
        end
    end
    return out
end

-- A profile compiled once (the update loop's cache).
function Planner.Prepared(profile, def)
    if not profile then return nil end
    local cache = ns.Loop.prepared
    local p = cache[profile.id]
    if not p then
        p = ns.Engine.Prepare(profile, def)
        cache[profile.id] = p
    end
    return p
end

-- What joins a build's rotation later, and at which level: the lines of the profile's main row
-- the player cannot use yet. A spell comes at its first rank's level (trainer data); a talent's
-- spell, or a line whose condition needs a talent (talent.x > 0), when the build's plan takes
-- that talent; a proc when the build takes the proc's talent.
-- Returns { { key, id, level, proc, kind = "aoe" | "execute" | nil } } sorted by level.
function Planner.Upcoming(def, profile, s, level, buildRanks)
    local plan = buildRanks and Planner.TalentsAt(def, buildRanks, ns.State.traits or {}, level, 60) or {}
    local talentAt = talentLevels(def, s.talents, plan, level)
    local out, seen = {}, {}
    local function add(item)
        if item.level > level and not seen[item.key] then
            seen[item.key] = true
            out[#out + 1] = item
        end
    end
    for _, entry in ipairs(profile and profile.main or {}) do
        local key = entry[1]
        local sp = def.spells[key]
        -- talents the line's own condition asks for: the line joins when the build has them all
        local needAt, skip = 0, false
        for t in tostring(entry[2] or ""):gmatch("talent%.([%w_]+)") do
            if talentAt[t] then needAt = math.max(needAt, talentAt[t]) else skip = true end
        end
        if sp and not sp.pet and not sp.wand and not skip then
            local kind = (entry.gate and entry.gate.unit == "target" and "execute") or (sp.role == "aoe" and "aoe") or nil
            if entry.glow then
                -- a proc: comes with the talent that gives it
                for bkey, b in pairs(def.buffs or {}) do
                    if b.glow == key and b.talent and talentAt[b.talent] then
                        add({ key = "proc:" .. bkey, id = sp.ranks[1][1], level = talentAt[b.talent], proc = true })
                    end
                end
            elseif not s.known[key] or needAt > level then
                local first = sp.ranks[1]
                local at = s.known[key] and level or first[2]
                if sp.talent then
                    local t = talentAt[sp.talent]
                    if t then
                        at = (first[3] or sp.source) == "talent" and t or math.max(at, t)
                    else
                        at = nil -- the build does not take it
                    end
                end
                if at then add({ key = key, id = first[1], level = math.max(at, needAt), kind = kind }) end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.key < b.key
    end)
    return out
end

-- The rotation on a fresh target with what the player has right now (learned spells, taken
-- talents): what the live hint will suggest when the next fight starts.
function Planner.RotationNow(def, prepared, s, depth)
    return Planner.RotationAt(def, prepared, s.player.level, s, depth, nil, true)
end

-- The distinct actions of a rotation, in order (a sequence repeats the filler).
function Planner.Distinct(rot)
    local out, seen = {}, {}
    for _, r in ipairs(rot) do
        if not seen[r.key] then
            seen[r.key] = true
            out[#out + 1] = r
        end
    end
    return out
end

-- Talent ranks (our keys) the player will have at level `at` with the build's plan.
function Planner.TalentKeysAt(def, current, planned)
    local out = {}
    for key, rank in pairs(current or {}) do out[key] = rank end
    for _, e in ipairs(planned or {}) do
        for key, t in pairs(def.talents or {}) do
            if t.ids[1] == e.spellID and (out[key] or 0) < e.to then out[key] = e.to end
        end
    end
    return out
end

-- The rotation the engine would suggest at another level: a fresh fight on a healthy target, all
-- trainer ranks up to that level, the talents (current, or `talents` planned for that level) and
-- demon. Uses its own engine instance.
-- actual = true: the spells actually learned and the talents actually taken instead, the same
-- data the live hint uses (Planner.RotationNow).
local previewEngine = {}
function Planner.RotationAt(def, prepared, at, s, depth, talents, actual)
    if not prepared then return {} end
    talents = talents or s.talents
    local known, knownRank, castTime = {}, {}, {}
    if actual then
        known, knownRank, castTime, talents = s.known, s.knownRank, s.castTime, s.talents
    end
    for key, sp in pairs(actual and {} or def.spells) do
        for i = #sp.ranks, 1, -1 do
            local r = sp.ranks[i]
            local src = srcOf(sp, r)
            local ok = r[2] <= at and src ~= "book" and not sp.pet
            if sp.talent then
                -- a talent's spell: from the talent on, when the talents for that level have it
                ok = ok and (talents[sp.talent] or 0) > 0
            elseif src == "talent" then
                ok = (s.knownRank[key] or 0) >= i
            end
            if ok then
                known[key], knownRank[key] = r[1], i
                castTime[key] = s.castTime and s.castTime[key] or Data.Cast(sp, i)
                break
            end
        end
    end
    local snap = {
        now = 0, def = def, known = known, knownRank = knownRank, castTime = castTime, talents = talents,
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
