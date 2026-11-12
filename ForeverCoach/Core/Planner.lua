-- Planner (stage 2): everything the chosen build's rotation still needs, by status:
--   trainer  a rank or spell waiting at the trainer (with its price)
--   talent   the next talent point of the build, or a rotation spell its talents give
--   quest    comes from a class quest (now: the level is there; later: not yet)
--   nobar    learned, but not on the action bars
--   level    opens at a later level
-- plus the trainer summary, class quests and how the build's rotation develops level by level
-- (Planner.Evolution).
local ADDON, ns = ...
local API, Data, Events, L = ns.API, ns.Data, ns.Events, ns.L

local Planner = {}
ns.Planner = Planner

-- What to do now first (buy, spend a point, take a quest, put on the bars), then what comes later.
Planner.ORDER = { trainer = 1, talent = 2, quest = 3, nobar = 4, level = 5, questLater = 6 }
function Planner.Rank(item) return Planner.ORDER[item.later and "questLater" or item.status] end

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

-- The chosen build's talent points from now up to level `at`, in the order the site places
-- them while leveling (Builds.LevelingOrder: the talents of the build's hints first), skipping the
-- points the player already has. By talent, in order:
-- { { spellID, name, from, to, max, first (its first point), level (when it reaches `to`), now,
--     key (the rank from which it changes the hints, nil: it does not), works (the level it gets
--     there; nil: not by `at`), talent (our key in def.talents) }, ... }, and the number of points.
-- unspent: free points from the client (nil: counted from the level).
Planner.MAX_POINTS = 51
function Planner.TalentsAt(def, buildRanks, playerRanks, level, at, unspent)
    local TF = ns.TalentsForever
    local layout = TF and TF.Layout(def.token)
    if not (layout and buildRanks) then return {}, 0 end
    playerRanks = playerRanks or {}
    local spent = 0
    for _, r in pairs(playerRanks) do spent = spent + r end
    if unspent == nil then unspent = math.max(0, level - 9 - spent) end
    local ourKey = {}
    for key, t in pairs(def.talents or {}) do ourKey[t.ids[1]] = key end
    local keys = ns.Builds.KeyTalentIds(def, ns.Builds.ProfileFor(def, buildRanks))
    local counted, byId, out, points = {}, {}, {}, 0
    for _, o in ipairs(ns.Builds.LevelingOrder(layout, buildRanks, keys)) do
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
                      first = pointLevel, key = o.key, talent = ourKey[id] }
                byId[id] = e
                out[#out + 1] = e
            end
            e.to, e.level, e.now = counted[id], pointLevel, pointLevel <= level
            e.ranks = e.ranks or {}
            e.ranks[counted[id]] = pointLevel
            if e.key and not e.works and e.from < e.key and counted[id] >= e.key then e.works = pointLevel end
        end
    end
    return out, points
end

-- The level from which one of our talent keys has `rank` (default 1) with the build's plan:
-- `level` when the player has it already, nil when the plan never gets there.
local function talentLevels(current, plan, level)
    local byKey = {}
    for _, e in ipairs(plan or {}) do
        if e.talent then byKey[e.talent] = e end
    end
    return function(key, rank)
        rank = rank or 1
        if ((current or {})[key] or 0) >= rank then return level end
        local e = byKey[key]
        return e and e.ranks and e.ranks[rank] or nil
    end
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

-- The situation a profile line is for (nil: the plain rotation on one target).
--   execute  the target is almost dead (a health gate on the target)
--   health   the player's health is low        mana    the player's mana is low
--   pet      the demon is hurt                  aoe     three or more enemies
--   second   a second enemy                     strong  an elite, a boss or a player
--   proc     an instant proc
local function kindOf(entry, row, sp)
    local cond = tostring(entry[2] or "")
    local g = entry.gate
    if g then
        if g.unit == "target" then return "execute" end
        if g.unit == "pet" then return "pet" end
        return g.power == "mana" and "mana" or "health"
    end
    if entry.glow then return "proc" end
    if sp.role == "aoe" or cond:find("enemies >= 3", 1, true) then return "aoe" end
    if cond:find("enemies = 2", 1, true) then return "second" end
    if row == "cooldown" or cond:find("target.elite", 1, true) or cond:find("target.boss", 1, true) then
        return "strong"
    end
    if row == "defense" then return "health" end
    return nil
end
Planner.KINDS = { "execute", "health", "mana", "aoe", "proc", "strong", "pet", "second" }

-- The free talent points the client reports (nil: counted from the level).
local function unspentPoints(def)
    local TF = ns.TalentsForever
    return TF and API.TalentPoints(TF.TreeID(def.token))
end

-- Every line of a profile with the level from which this build can use it:
-- { key, id, row, kind, level } (level nil: never for this build). A spell comes at its first
-- rank's level (trainer data); a talent's spell, a line whose condition needs a talent (at the rank
-- it asks: talent.x >= 5, Data.TalentNeeds) or a proc when the build's plan gets there; what the
-- player knows now, now.
function Planner.Lines(def, profile, s, level, buildRanks)
    local plan = buildRanks and Planner.TalentsAt(def, buildRanks, ns.State.traits or {}, level, 60, unspentPoints(def)) or {}
    local talentAt = talentLevels(s.talents, plan, level)
    local out = {}
    for _, row in ipairs({ "main", "defense", "cooldown" }) do
        for _, entry in ipairs(profile and profile[row] or {}) do
            local key = entry[1]
            local sp = def.spells[key]
            if sp and not sp.pet and not sp.wand then
                local at
                if s.known[key] then
                    at = level
                else
                    local first = sp.ranks[1]
                    at = first[2]
                    if sp.talent then
                        local t = talentAt(sp.talent)
                        at = t and ((first[3] or sp.source) == "talent" and t or math.max(at, t)) or nil
                    end
                end
                for _, need in ipairs(Data.TalentNeeds(entry[2])) do
                    local t = talentAt(need.talent, need.rank)
                    at = at and t and math.max(at, t) or nil
                end
                if entry.glow then
                    -- a proc comes with the talent that gives it
                    for _, b in pairs(def.buffs or {}) do
                        if b.glow == key and b.talent then at = talentAt(b.talent) end
                    end
                end
                out[#out + 1] = { key = key, id = s.known[key] or sp.ranks[1][1], row = row,
                                  kind = kindOf(entry, row, sp), level = at }
            end
        end
    end
    return out
end

-- What joins a build's rotation later, and at which level: { { key, id, level, kind } } sorted by
-- level, one per spell (its earliest line), only what the player cannot use yet.
function Planner.Upcoming(def, profile, s, level, buildRanks)
    local earliest, order = {}, {}
    for _, l in ipairs(Planner.Lines(def, profile, s, level, buildRanks)) do
        local id = l.kind == "proc" and ("proc:" .. l.key) or l.key
        if l.level then
            if not earliest[id] then order[#order + 1] = id end
            if not earliest[id] or l.level < earliest[id].level then earliest[id] = l end
        end
    end
    local out = {}
    for _, id in ipairs(order) do
        local l = earliest[id]
        if l.level > level then
            out[#out + 1] = { key = id, id = l.id, level = l.level, kind = l.kind, proc = l.kind == "proc" or nil }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.key < b.key
    end)
    return out
end

-- What the build uses only in a situation at level `at`, by kind (Planner.KINDS order):
-- { { kind, spells = { { key, id } } } }.
function Planner.Situational(def, profile, s, level, at, buildRanks)
    local byKind, seen = {}, {}
    for _, l in ipairs(Planner.Lines(def, profile, s, level, buildRanks)) do
        if l.kind and l.level and l.level <= at and not seen[l.kind .. l.key] then
            seen[l.kind .. l.key] = true
            byKind[l.kind] = byKind[l.kind] or {}
            table.insert(byKind[l.kind], { key = l.key, id = l.id })
        end
    end
    local out = {}
    for _, kind in ipairs(Planner.KINDS) do
        if byKind[kind] then out[#out + 1] = { kind = kind, spells = byKind[kind] } end
    end
    return out
end

-- The rotation on a fresh target with what the player has right now (learned spells, taken
-- talents): what the live hint will suggest when the next fight starts.
function Planner.RotationNow(def, prepared, s, depth)
    return Planner.RotationAt(def, prepared, s.player.level, s, depth, nil, true)
end

-- The rotation on one target as the preview shows it: distinct actions in priority order, then the
-- proc once the talent that gives it is there. { { key, id, proc } }, `count` at most (nil: all).
function Planner.RotationList(def, prepared, s, at, talents, actual, count)
    count = count or 99
    local procs = {}
    for _, b in pairs(def.buffs or {}) do
        local sp = b.glow and def.spells[b.glow]
        if sp and b.talent and ((talents or s.talents)[b.talent] or 0) > 0 then
            procs[#procs + 1] = { key = "proc:" .. b.glow, id = s.known[b.glow] or sp.ranks[1][1], proc = true }
        end
    end
    -- the procs always fit: the plain actions make room for them
    local out = {}
    for _, r in ipairs(Planner.Distinct(Planner.RotationAt(def, prepared, at, s, 8, talents, actual))) do
        if #out < count - #procs then out[#out + 1] = { key = r.key, id = r.id } end
    end
    for _, p in ipairs(procs) do out[#out + 1] = p end
    return out
end

-- How a build's rotation develops as it gets new spells and talents: the steps where its hints
-- change. Step 1 is now (what the player has); step 2 "after the trainer" when buying what waits
-- there and spending free points already changes something; then each level where a spell or a
-- talent joins. Every step: { level, now, trainer, rotation = { {key, id, proc, new} },
--   talents = { {name, talent, rank, max, shown, untracked} } (start changing the hints here, at that
--     rank; shown: its own spell is among the changes of the step; untracked: changes the play, not
--     the hints),
--   replaced = { {new, old} }, added = { {key, id, proc} },
--   removed = { {key, id} }, situations = { {kind, spells = { {key, id} }} } (new ones) }.
-- The rotation is the order on one target with the demon out; situations are the lines for a
-- finisher, low health or mana, 3+ enemies, a proc, a strong target... (Planner.Situational).
function Planner.Evolution(def, profile, prepared, s, level, buildRanks, maxSteps)
    maxSteps = maxSteps or math.huge
    -- whole rotations (no count): what changes is judged on all of it, the window shows the start
    local traits = ns.State.traits or {}
    local unspent = unspentPoints(def)
    local plan = buildRanks and Planner.TalentsAt(def, buildRanks, traits, level, 60, unspent) or {}

    -- the levels where something may change: a line of the profile or a talent of the plan
    local set = {}
    for _, l in ipairs(Planner.Lines(def, profile, s, level, buildRanks)) do
        if l.level and l.level > level then set[l.level] = true end
    end
    for _, e in ipairs(plan) do
        if e.works and e.works > level then set[e.works] = true end
    end
    -- talents that change how the build plays but not the hints (def.talents[x].untracked: Decimation
    -- and Soul Fire): named from the level both the talent and its spell are there
    local untracked = {}
    for _, e in ipairs(plan) do
        local t = e.talent and def.talents[e.talent]
        local sp = t and t.untracked and def.spells[t.untracked]
        if sp then
            local at = math.max(e.first, sp.ranks[1][2])
            untracked[#untracked + 1] = { at = at, name = e.name, talent = e.talent }
            if at > level then set[at] = true end
        end
    end
    local levels = {}
    for l in pairs(set) do levels[#levels + 1] = l end
    table.sort(levels)

    local function talentsAt(at)
        if not buildRanks then return nil end
        return Planner.TalentKeysAt(def, s.talents, Planner.TalentsAt(def, buildRanks, traits, level, at, unspent))
    end
    local function situationsAt(at)
        local out = {}
        for _, g in ipairs(Planner.Situational(def, profile, s, level, at, buildRanks)) do
            for _, sp in ipairs(g.spells) do out[g.kind .. ":" .. sp.key] = { kind = g.kind, key = sp.key, id = sp.id } end
        end
        return out
    end
    local function keysOf(list)
        local out = {}
        for _, r in ipairs(list) do out[r.key] = r end
        return out
    end

    local steps = {}
    local prevRot = Planner.RotationList(def, prepared, s, level, nil, true)
    local prevSit = {}
    -- now: what is learned; the situations only those the player can use already
    for k, v in pairs(situationsAt(level)) do
        if not v.key:find("^proc:") and (s.known[v.key] or v.kind == "proc") then prevSit[k] = v end
    end
    local first = { level = level, now = true, rotation = prevRot, situations = {} }
    local byKind = {}
    for _, v in pairs(prevSit) do
        byKind[v.kind] = byKind[v.kind] or {}
        table.insert(byKind[v.kind], { key = v.key, id = v.id })
    end
    for _, kind in ipairs(Planner.KINDS) do
        if byKind[kind] then first.situations[#first.situations + 1] = { kind = kind, spells = byKind[kind] } end
    end
    steps[1] = first

    local prevLevel = level
    local function step(at, trainer)
        local talents = talentsAt(at)
        local rot = Planner.RotationList(def, prepared, s, at, talents, false)
        local sit = situationsAt(at)
        local before, after = keysOf(prevRot), keysOf(rot)
        local added, removed = {}, {}
        for _, r in ipairs(rot) do
            r.new = before[r.key] == nil
            if r.new then added[#added + 1] = r end
        end
        for _, r in ipairs(prevRot) do
            if not after[r.key] then removed[#removed + 1] = r end
        end
        local replaced = {}
        if #added == 1 and #removed == 1 and not added[1].proc and not removed[1].proc then
            replaced[1] = { new = added[1], old = removed[1] }
            added, removed = {}, {}
        end
        local newSit, byKind2 = {}, {}
        for k, v in pairs(sit) do
            if not prevSit[k] and not after[v.key] and v.kind ~= "proc" then
                byKind2[v.kind] = byKind2[v.kind] or {}
                table.insert(byKind2[v.kind], { key = v.key, id = v.id })
            end
        end
        for _, kind in ipairs(Planner.KINDS) do
            if byKind2[kind] then
                table.sort(byKind2[kind], function(a, b) return a.key < b.key end)
                newSit[#newSit + 1] = { kind = kind, spells = byKind2[kind] }
            end
        end
        -- the talents that start changing the hints here (at the rank they need: Shadow and Flame 5/5);
        -- shown = the talent's own spell is among this step's changes (Siphon Life, Wrack...)
        local changed = {}
        for _, r in ipairs(added) do changed[r.key] = true end
        for _, r in ipairs(replaced) do changed[r.new.key] = true end
        for _, g in ipairs(newSit) do
            for _, sp in ipairs(g.spells) do changed[sp.key] = true end
        end
        local started = {}
        for _, e in ipairs(plan) do
            if e.works and ((e.works > prevLevel and e.works <= at) or (trainer and e.works == level)) then
                local shown = false
                for key, sp in pairs(def.spells) do
                    if sp.talent and sp.talent == e.talent and changed[key] then shown = true end
                end
                started[#started + 1] = { name = e.name, talent = e.talent, rank = e.key, max = e.max, shown = shown }
            end
        end
        for _, u in ipairs(untracked) do
            if (u.at > prevLevel and u.at <= at) or (trainer and u.at == level) then
                started[#started + 1] = { name = u.name, talent = u.talent, untracked = true }
            end
        end
        if #added + #removed + #replaced + #newSit + #started == 0 then return end
        steps[#steps + 1] = { level = at, trainer = trainer, rotation = rot, talents = started, replaced = replaced,
                              added = added, removed = removed, situations = newSit }
        prevRot, prevSit, prevLevel = rot, sit, at
    end
    step(level, true) -- buying what waits at the trainer and spending free points
    for _, at in ipairs(levels) do
        if #steps >= maxSteps then break end
        step(at, false)
    end
    return steps
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

-- The rotation the engine would suggest at another level: a fresh fight on a healthy target with
-- the demon out, all trainer ranks up to that level, the talents (current, or `talents` planned
-- for that level). Uses its own engine instance.
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
            -- a talent's own rank comes when the plan takes the talent (its level is only the earliest)
            local ok = (src == "talent" or r[2] <= at) and src ~= "book" and not sp.pet
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
        pet = { exists = true, family = (s.pet and s.pet.family) or (ns.db and ns.db.lastPet), hp_pct = 100 },
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
