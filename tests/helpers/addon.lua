-- Loads ForeverCoach outside the game, in TOC order, on top of the client stubs.
--   local ns, W = addon.load({ world = { level = 12 } })
-- W is the stub world; change it, then call addon.compute(ns, W) for a fresh hint.
local wow = require("helpers.wow")

local M = {}

local ROOT = "ForeverCoach/"

function M.tocFiles(root)
    root = root or ROOT
    local files = {}
    for line in io.lines(root .. "ForeverCoach.toc") do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and line:match("%.lua$") then
            files[#files + 1] = root .. line:gsub("\\", "/")
        end
    end
    return files
end

-- opts.world: fields merged into the stub world; opts.loadAll: keep every class (validation);
-- opts.login = false: stop before PLAYER_LOGIN.
function M.load(opts)
    opts = opts or {}
    local W = wow.newWorld()
    for k, v in pairs(opts.world or {}) do W[k] = v end
    wow.install(W)

    local ns = {}
    local files = M.tocFiles()
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        chunk("ForeverCoach", ns)
        -- Data.loadAll must be set before the data files run.
        if opts.loadAll and ns.Data and not ns.Data.loadAll then ns.Data.loadAll = true end
    end

    ns.db = ns.CopyDefaults({}, ns.Defaults)
    ForeverCoachCharDB = ns.db
    ns.Events:Fire("FC_INIT")
    if opts.login ~= false then ns.Events:Fire("FC_LOGIN") end
    return ns, W
end

-- Mark spells as known: every rank available at the world's level from trainer/class/quest
-- sources (as if everything was bought), plus the given extra spell IDs.
function M.learnUpTo(ns, W, level, extra)
    W.level = level
    for _, sp in pairs(ns.Data.class.spells) do
        if not sp.talent and not sp.pet then
            for _, r in ipairs(sp.ranks) do
                local src = r[3] or sp.source
                if r[2] <= level and src ~= "book" and src ~= "talent" then W.known[r[1]] = true end
            end
        end
    end
    for _, id in ipairs(extra or {}) do W.known[id] = true end
    M.rescan(ns)
end

function M.rescan(ns)
    ns.State.knownDirty = true
    ns.State.itemsDirty = true
end

function M.compute(ns, W)
    return ns.Loop:Compute(W.time)
end

-- Main action keys of the last computation, e.g. { "corruption", "shadow_bolt" }.
function M.mainActions(r)
    local out = {}
    for i = 1, r.mainCount do out[i] = r.main[i].action end
    return out
end

M.wow = wow
return M
