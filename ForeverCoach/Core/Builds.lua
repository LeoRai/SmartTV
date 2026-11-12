-- Builds (stage 2): the Talents Forever build chosen for each spec, the lists behind the Builds
-- window, and how the player's talents compare with a build.
--   chosen build per spec -> BuildMatcher takes its lead tree -> rotation profile
-- Spec 2 opens at level 40; the active spec is the client's active talent group (1 without one).
local ADDON, ns = ...
local API, Data, Events = ns.API, ns.Data, ns.Events

local Builds = {}
ns.Builds = Builds

Builds.TABS = { "all", "leveling", "group", "pvp" } -- "all" is the site's overall top list
Builds.SPEC2_LEVEL = 40
local POINTS_FROM = 10 -- first talent point at level 10

function Builds.ActiveSpec()
    local spec = API.ActiveSpecGroup()
    if spec ~= 2 then spec = 1 end
    return spec
end

local function store()
    local db = ns.db
    db.builds = db.builds or {}
    return db.builds
end

-- { code, mode, lead, pts, source = "tf" | "link" } or nil.
function Builds.Chosen(spec)
    return store()[spec or Builds.ActiveSpec()]
end

function Builds.Choose(build, spec)
    spec = spec or Builds.ActiveSpec()
    if build then
        store()[spec] = { code = build.code, mode = build.mode, lead = build.lead, pts = build.pts, source = build.source or "tf" }
    else
        store()[spec] = nil
    end
    Events:Fire("FC_BUILD_CHOSEN", spec)
end

local function leadOf(points, names)
    local best, bestPts = nil, -1
    for i, p in ipairs(points or {}) do
        if p > bestPts then best, bestPts = i, p end
    end
    return best and names[best] or nil
end

-- Builds of a tab, decoded and compared with the player's talents.
-- Each: { code, pts, lead, rank, saved, opened, variants, ranks, similarity, matched, yours, chosen }.
function Builds.List(tab, playerRanks)
    local TF = ns.TalentsForever
    local def = Data.class
    if not (TF and TF.Available() and def) then return {} end
    local mode = tab ~= "all" and tab or nil
    local chosen = Builds.Chosen()
    local list = TF.Builds(def.token, mode)
    local bestIdx, bestScore = nil, 0
    for i, b in ipairs(list) do
        b.mode = mode
        b.ranks = TF.Decode(def.token, b.code) or {}
        b.similarity, b.matched = TF.Similarity(playerRanks or {}, b.ranks)
        b.chosen = chosen ~= nil and chosen.code == b.code
        if b.similarity > bestScore then bestIdx, bestScore = i, b.similarity end
    end
    -- "Yours": the closest build, if most of the player's points agree with it.
    if bestIdx and bestScore >= 0.8 then list[bestIdx].yours = true end
    return list
end

-- A pasted Talents Forever link or code -> build, or nil + reason.
function Builds.FromLink(text)
    local TF = ns.TalentsForever
    local def = Data.class
    if not (TF and TF.Available() and def) then return nil, "no_tf" end
    local code = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    code = code:gsub("^https?://[^/]+/", ""):gsub("[?#].*$", "") -- the site's link mark (?a) is not part of the code
    local ranks, points = TF.Decode(def.token, code)
    if not ranks then return nil, "bad_code" end
    local layout = TF.Layout(def.token)
    return { code = code, pts = points, lead = leadOf(points, layout.names), ranks = ranks, source = "link" }
end

-- The order points go into a build while leveling (a build code carries only the final ranks).
-- The talents that change the build's hints (keyIds, Builds.KeyTalentIds of its profile: Nightfall,
-- Siphon Life, Conflagrate...) take their points as soon as the tree allows; the other points fill
-- rows on the way to the next of them, the lead tree first, in the tree's own order. The rules of the tree: a row opens with 5
-- points per row above it in that tree, a talent with a prerequisite (req: its index in the tree)
-- waits until that one is full. Returns { { tree, talent, key = true|nil }, ... } per point.
function Builds.LevelingOrder(layout, buildRanks, keyIds)
    keyIds = keyIds or {}
    local placed, rowPts, pts, trees, left = {}, {}, {}, {}, 0
    for ti, talents in ipairs(layout.talents) do
        placed[ti], rowPts[ti], pts[ti], trees[ti] = {}, {}, 0, ti
        for _, t in ipairs(talents) do pts[ti] = pts[ti] + (buildRanks[t.spell] or 0) end
        left = left + pts[ti]
    end
    table.sort(trees, function(a, b)
        if pts[a] ~= pts[b] then return pts[a] > pts[b] end
        return a < b
    end)
    local function want(ti, i, t) return (buildRanks[t.spell] or 0) - (placed[ti][i] or 0) end
    local function open(ti, i, t)
        if want(ti, i, t) <= 0 then return false end
        local row, above = t.row or 1, 0
        for r = 1, row - 1 do above = above + (rowPts[ti][r] or 0) end
        if above < (row - 1) * 5 then return false end
        local pre = t.req and layout.talents[ti][t.req]
        return not pre or (placed[ti][t.req] or 0) >= (pre.max or 1)
    end
    -- the first talent (by row, then trees by points, then the tree's order) that passes `ok`
    local function first(ok, onlyTree)
        local best
        for _, ti in ipairs(trees) do
            if not onlyTree or onlyTree == ti then
                for i, t in ipairs(layout.talents[ti]) do
                    if ok(ti, i, t) and (not best or (t.row or 1) < best.row) then
                        best = { tree = ti, i = i, row = t.row or 1 }
                    end
                end
            end
        end
        return best
    end
    local order = {}
    while left > 0 do
        -- 1. a talent that changes the rotation and can take its point now
        local pick = first(function(ti, i, t) return keyIds[t.spell] and open(ti, i, t) end)
        if not pick then
            -- 2. a point toward the next one, the lead tree's first: in its tree, the tree's own order
            local target
            for _, ti in ipairs(trees) do
                target = target or first(function(tj, i, t) return keyIds[t.spell] and want(tj, i, t) > 0 end, ti)
            end
            for _, ti in ipairs(target and { target.tree, unpack(trees) } or trees) do
                if not pick then
                    for i, t in ipairs(layout.talents[ti]) do
                        if not pick and open(ti, i, t) then pick = { tree = ti, i = i } end
                    end
                end
            end
        end
        if not pick then break end -- a build the rules cannot place: the rest is left out
        local t = layout.talents[pick.tree][pick.i]
        placed[pick.tree][pick.i] = (placed[pick.tree][pick.i] or 0) + 1
        rowPts[pick.tree][t.row or 1] = (rowPts[pick.tree][t.row or 1] or 0) + 1
        left = left - 1
        order[#order + 1] = { tree = pick.tree, talent = t, key = keyIds[t.spell] or nil }
    end
    return order
end

-- The profile whose hints a build gets: the one of its lead tree (the tree with most points), as
-- BuildMatcher picks it for a chosen build. nil without Talents Forever data.
function Builds.ProfileFor(def, buildRanks)
    local TF = ns.TalentsForever
    local pts = TF and def and buildRanks and TF.TreePoints(def.token, buildRanks)
    if not pts then return nil end
    local lead = ns.BuildMatcher.DominantTree(pts, def.trees)
    return (ns.BuildMatcher.Select(def, Data.profiles, pts, {}, ns.Modes.current, lead))
end

-- The talents that change a profile's hints and the rank they need: { [spellID] = rank }.
-- A spell that needs a talent, talent.x in a condition ("> 0": rank 1, ">= 5": rank 5), the talent
-- behind a proc, the talent that keeps a debuff (keepsDebuff.rank). Without a profile: every
-- profile of the class.
local keyCache = setmetatable({}, { __mode = "k" })
function Builds.KeyTalentIds(def, profile)
    if not def then return {} end
    local cacheKey = profile or def
    if keyCache[cacheKey] then return keyCache[cacheKey] end
    local keys = {}
    local function mark(talent, rank)
        local t = talent and def.talents and def.talents[talent]
        if t then
            local id = t.ids[1]
            rank = math.max(1, rank or 1)
            keys[id] = keys[id] and math.min(keys[id], rank) or rank
        end
    end
    local function scan(p)
        for _, row in ipairs({ "main", "defense", "cooldown" }) do
            for _, entry in ipairs(p[row] or {}) do
                local sp = def.spells[entry[1]]
                if sp then
                    mark(sp.talent)
                    if sp.keepsDebuff then mark(sp.keepsDebuff.talent, sp.keepsDebuff.rank) end
                end
                for _, need in ipairs(Data.TalentNeeds(entry[2])) do mark(need.talent, need.rank) end
                if entry.glow then
                    for _, b in pairs(def.buffs or {}) do
                        if b.glow == entry[1] then mark(b.talent) end
                    end
                end
            end
        end
    end
    if profile then
        scan(profile)
    else
        for _, p in pairs(Data.profiles) do
            if p.class == def.token then scan(p) end
        end
    end
    keyCache[cacheKey] = keys
    return keys
end

-- How the player's talents compare with a build, and where the next point goes.
-- unspent: free talent points from the client (nil: counted from the level).
-- Returns { spent, matched, all (every spent point agrees), done (nothing left to take),
--           next = { spellID, name, rank, tree, level, now } }.
function Builds.Compare(buildRanks, playerRanks, level, unspent)
    local TF = ns.TalentsForever
    local def = Data.class
    local layout = TF and def and TF.Layout(def.token)
    local out = { spent = 0, matched = 0 }
    playerRanks = playerRanks or {}
    for spellID, r in pairs(playerRanks) do
        out.spent = out.spent + r
        out.matched = out.matched + math.min(r, buildRanks[spellID] or 0)
    end
    out.all = out.spent == out.matched
    if not layout then return out end

    -- Next point: the first one of the leveling order the player does not have yet.
    local counted, best = {}, nil
    local keys = Builds.KeyTalentIds(def, Builds.ProfileFor(def, buildRanks))
    for _, o in ipairs(Builds.LevelingOrder(layout, buildRanks, keys)) do
        local id = o.talent.spell
        counted[id] = (counted[id] or 0) + 1
        if counted[id] > (playerRanks[id] or 0) then
            best = { spellID = id, rank = counted[id], tree = o.tree, en = o.talent.name }
            break
        end
    end
    out.done = best == nil
    if best then
        level = level or POINTS_FROM
        if unspent == nil then unspent = math.max(0, level - POINTS_FROM + 1 - out.spent) end
        best.now = unspent > 0
        best.level = best.now and level or math.max(POINTS_FROM, level + 1)
        best.name = API.SpellName(best.spellID) or best.en
        out.next = best
    end
    return out
end

Events:On("FC_BUILD_CHOSEN", Builds, function()
    ns.BuildMatcher:Update()
    Events:Fire("FC_DIRTY")
end)
