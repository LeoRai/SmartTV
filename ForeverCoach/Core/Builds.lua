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

-- The order points go into a build (a pasted link carries none; the site's own rule):
-- the tree with most points first; inside a tree, the first talent in the tree's order that
-- still wants a point, whose row is open (5 points per row in the rows above) and whose
-- prerequisite (req: its index in the tree) is full. Returns { { tree, talent }, ... } per point.
function Builds.GuessOrder(layout, buildRanks)
    local trees, pts = {}, {}
    for ti, talents in ipairs(layout.talents) do
        trees[ti], pts[ti] = ti, 0
        for _, t in ipairs(talents) do pts[ti] = pts[ti] + (buildRanks[t.spell] or 0) end
    end
    table.sort(trees, function(a, b)
        if pts[a] ~= pts[b] then return pts[a] > pts[b] end
        return a < b
    end)
    local order = {}
    for _, ti in ipairs(trees) do
        local talents = layout.talents[ti]
        local placed, rowPts, left = {}, {}, pts[ti]
        local function rowsAbove(row)
            local n = 0
            for r = 1, row - 1 do n = n + (rowPts[r] or 0) end
            return n
        end
        local function open(i, t)
            if (placed[i] or 0) >= (buildRanks[t.spell] or 0) then return false end
            if rowsAbove(t.row or 1) < ((t.row or 1) - 1) * 5 then return false end
            local pre = t.req and talents[t.req]
            return not pre or (placed[t.req] or 0) >= (pre.max or 1)
        end
        while left > 0 do
            local pick
            for i, t in ipairs(talents) do
                if open(i, t) then pick = i; break end
            end
            if not pick then break end -- a build the rules cannot place: the rest is left out
            local t = talents[pick]
            placed[pick] = (placed[pick] or 0) + 1
            rowPts[t.row or 1] = (rowPts[t.row or 1] or 0) + 1
            left = left - 1
            order[#order + 1] = { tree = ti, talent = t }
        end
    end
    return order
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

    -- Next point: the first one of the build's order the player does not have yet.
    local counted, best = {}, nil
    for _, o in ipairs(Builds.GuessOrder(layout, buildRanks)) do
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

-- The first distinct actions of the profile a build leads to: the rotation shown on its card.
function Builds.RotationOf(build, mode, count)
    local def = Data.class
    if not def then return {} end
    local profile = ns.BuildMatcher.Select(def, Data.profiles, nil, {}, mode or ns.Modes.current, build and build.lead)
    -- Plain rotation lines in order; procs go last ("on proc"); gated, wand, utility, AoE and
    -- early-level fallback lines (conditions with !known.) are left out.
    count = count or 5
    local out, procs, seen = {}, {}, {}
    for _, entry in ipairs(profile and profile.main or {}) do
        local key, cond = entry[1], entry[2] or ""
        local sp = def.spells[key]
        local skip = not sp or entry.gate or sp.role == "wand" or sp.role == "utility" or sp.role == "aoe"
            or cond:find("!known.", 1, true)
        if not skip and not seen[key] then
            seen[key] = true
            if entry.glow then procs[#procs + 1] = { key = key, proc = true } else out[#out + 1] = { key = key } end
        end
    end
    local plain = math.min(#out, count - math.min(#procs, 1))
    for i = #out, plain + 1, -1 do out[i] = nil end
    if procs[1] and #out < count then out[#out + 1] = procs[1] end
    return out
end

Events:On("FC_BUILD_CHOSEN", Builds, function()
    ns.BuildMatcher:Update()
    Events:Fire("FC_DIRTY")
end)
