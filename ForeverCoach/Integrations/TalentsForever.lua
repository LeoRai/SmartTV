-- Talents Forever (talentsforever.com, author baldwinbuilds, co-author of ForeverCoach).
-- With the author's permission builds are read straight from the Talents Forever addon
-- (folder TalentsForeverBook) when both are installed:
--   TalentsForeverBookData.classes[CLASS].trees[t].talents[i] = { spell, node, max, name, ... }
--   TalentsForeverBookData.popular[CLASS] = { builds, window, asOf, spec, top = {...},
--                                            fors = { leveling = {...}, pve = {...}, pvp = {...} } }
--   TalentsForeverBook.API = { GetPlan, GetPlanCode, GetShareURL, ImportCode, OnChange, Toggle }
-- Build code: "<class>/<level>/<tree1>-<tree2>-<tree3>[-legacy x3][-order]-<generation>", one rank
-- digit per talent in tree order, trailing zeros trimmed.
-- Everything here is optional: without Talents Forever the addon falls back to its own data.
local ADDON, ns = ...

local TF = {}
ns.TalentsForever = TF

-- Our modes -> Talents Forever lists.
TF.MODE_LIST = { leveling = "leveling", group = "pve", pvp = "pvp" }

function TF.Data()
    local d = _G.TalentsForeverBookData
    if type(d) == "table" and type(d.classes) == "table" then return d end
    return nil
end

function TF.Available() return TF.Data() ~= nil end

-- The class talent tree's ID in the client (C_Traits), or nil.
function TF.TreeID(class, d)
    d = d or TF.Data()
    local c = d and d.classes[class]
    return c and tonumber(c.tree) or nil
end

-- Talent layout of a class: spell -> tree, tree names, talents per tree.
local layouts = {}
function TF.Layout(class, d)
    d = d or TF.Data()
    local c = d and d.classes[class]
    if not c or type(c.trees) ~= "table" then return nil end
    local cached = layouts[class]
    if cached and cached.source == c then return cached end
    local layout = { source = c, bySpell = {}, byNode = {}, names = {}, talents = {} }
    for ti, tree in ipairs(c.trees) do
        layout.names[ti] = tree.name
        layout.talents[ti] = {}
        for i, t in ipairs(tree.talents or {}) do
            layout.talents[ti][i] = t
            if t.spell then layout.bySpell[t.spell] = ti end
            if t.node then layout.byNode[t.node] = ti end
        end
    end
    layouts[class] = layout
    return layout
end

-- Points per tree from talent ranks keyed by talent spellID ({ [spellID] = rank }).
function TF.TreePoints(class, ranksBySpell, d)
    local layout = TF.Layout(class, d)
    if not layout or not ranksBySpell then return nil end
    local points = {}
    for ti = 1, #layout.names do points[ti] = 0 end
    for spellID, rank in pairs(ranksBySpell) do
        local ti = layout.bySpell[spellID]
        if ti and rank > 0 then points[ti] = points[ti] + rank end
    end
    return points
end

-- A build code -> { [spellID] = rank }, points per tree, level. nil + reason when unreadable.
-- Codes of another talent generation go through the addon's own decoder, which carries them over.
function TF.Decode(class, code, d)
    d = d or TF.Data()
    local layout = TF.Layout(class, d)
    if not layout then return nil, "no data" end
    local cname, level, rest = tostring(code or ""):gsub("[?#].*$", ""):match("(%a+)/(%d+)/([%w%-]*)%s*$")
    if not cname then return nil, "not a code" end
    local segs = {}
    for s in (rest .. "-"):gmatch("([^%-]*)%-") do segs[#segs + 1] = s end
    local nt = #layout.names
    local generation = #segs > nt and segs[#segs] or nil

    local perTree
    if generation == tostring(d.codeVersion) then
        perTree = {}
        for ti = 1, nt do
            perTree[ti] = {}
            local s = segs[ti] or ""
            for i = 1, #s do perTree[ti][i] = tonumber(s:sub(i, i)) or 0 end
        end
    else
        local book = _G.TalentsForeverBook
        local ok, plan = false, nil
        if book and book.Decode then ok, plan = pcall(book.Decode, code) end
        if not ok or type(plan) ~= "table" or type(plan.ranks) ~= "table" then return nil, "old code" end
        perTree = plan.ranks
    end

    local ranks, points = {}, {}
    for ti = 1, nt do
        points[ti] = 0
        for i, t in ipairs(layout.talents[ti]) do
            local r = math.min(t.max or 5, (perTree[ti] and perTree[ti][i]) or 0)
            if r > 0 and t.spell then
                ranks[t.spell] = r
                points[ti] = points[ti] + r
            end
        end
    end
    return ranks, points, tonumber(level)
end

-- Popular builds for a mode, best first: { code, pts, lead, rank, saved, opened, variants, tags }.
function TF.Builds(class, mode, d)
    d = d or TF.Data()
    local pop = d and d.popular and d.popular[class]
    if not pop then return {} end
    -- A mode without its own list has no builds (the overall top list is the "all" tab).
    local list
    if mode then
        list = pop.fors and pop.fors[TF.MODE_LIST[mode] or mode] or {}
    else
        list = pop.top or {}
    end
    local out = {}
    for i, b in ipairs(list) do
        local lead = b.lead
        if type(lead) == "table" then lead = lead[1] end
        out[i] = {
            code = b.code, pts = b.pts, lead = lead, rank = b.rank or i, saved = b.saved, opened = b.opened,
            variants = b.variants, shared = b.shared, tags = b.tags, close = b.close,
        }
    end
    return out
end

-- How many builds the site counted, since when, spec shares.
function TF.Meta(class, d)
    d = d or TF.Data()
    local pop = d and d.popular and d.popular[class]
    if not pop then return nil end
    return { builds = pop.builds, window = pop.window, asOf = pop.asOf, spec = pop.spec, dataBuild = d.build }
end

-- Share of the player's points that the build has too (0..1), and how many points match.
local function similarity(player, build)
    local total, matched = 0, 0
    for spellID, rank in pairs(player) do
        total = total + rank
        matched = matched + math.min(rank, build[spellID] or 0)
    end
    if total == 0 then return 0, 0 end
    return matched / total, matched
end
TF.Similarity = similarity

-- The popular build of this mode closest to the player's talents. Returns build, similarity.
function TF.Closest(class, mode, ranksBySpell, d)
    local best, bestScore
    for _, b in ipairs(TF.Builds(class, mode, d)) do
        local ranks = TF.Decode(class, b.code, d)
        if ranks then
            local score = similarity(ranksBySpell or {}, ranks)
            if not bestScore or score > bestScore then best, bestScore = b, score end
        end
    end
    return best, bestScore or 0
end

-- The player's own plan in Talents Forever (what they intend to take), as { [spellID] = rank }.
function TF.PlayerPlan(class)
    local book = _G.TalentsForeverBook
    local api = book and book.API
    if not (api and api.GetPlanCode) then return nil end
    local ok, code = pcall(api.GetPlanCode)
    if not ok or type(code) ~= "string" then return nil end
    return TF.Decode(class, code), code
end

ns.Events:On("FC_LOGIN", TF, function()
    local book = _G.TalentsForeverBook
    if book and book.API and book.API.OnChange then
        pcall(book.API.OnChange, function() ns.Events:Fire("FC_TF_PLAN_CHANGED") end)
    end
end)
