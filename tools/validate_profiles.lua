-- Checks the data files outside the game: every profile compiles, every action and key exists,
-- spell ranks are consistent, every text key is translated.
--
--   lua5.1 tools/validate_profiles.lua        (from the repository root; exit code 1 on problems)
--
-- Uses the addon's own condition compiler (Core/Conditions.lua) through the test loader,
-- so the validator and the game can never disagree about the language.
package.path = "tests/?.lua;" .. package.path
local addon = require("helpers.addon")

local M = {}

local MODE_SUFFIX = { leveling = "Leveling", group = "Group", pvp = "PvP" }

local function check(problems, ok, fmt, ...)
    if not ok then problems[#problems + 1] = string.format(fmt, ...) end
end

local function validateClass(problems, token, def)
    local where = "Spells/" .. token
    for _, field in ipairs({ "name", "version", "patch", "date", "trees", "spells" }) do
        check(problems, def[field] ~= nil, "%s: missing field '%s'", where, field)
    end
    local seen = {}
    for key, sp in pairs(def.spells) do
        local w = where .. "." .. key
        check(problems, type(sp.ranks) == "table" and #sp.ranks > 0, "%s: no ranks", w)
        local prev = 0
        for i, r in ipairs(sp.ranks or {}) do
            local id, level = r[1], r[2]
            check(problems, type(id) == "number", "%s: rank %d has no spell ID", w, i)
            check(problems, type(level) == "number" and level >= 1 and level <= 60, "%s: rank %d bad level", w, i)
            check(problems, (level or 0) >= prev, "%s: rank %d level goes down", w, i)
            prev = level or prev
            if id then
                check(problems, not seen[id], "%s: spell ID %d also used by %s", w, id, tostring(seen[id]))
                seen[id] = key
            end
        end
        if sp.talent then check(problems, def.talents and def.talents[sp.talent], "%s: unknown talent '%s'", w, sp.talent) end
        for _, field in ipairs({ "buff", "consumes" }) do
            if sp[field] then check(problems, def.buffs and def.buffs[sp[field]], "%s: unknown buff '%s'", w, sp[field]) end
        end
        if sp.requires then
            local req = def.spells[sp.requires]
            check(problems, req and req.duration, "%s: requires '%s' which leaves no debuff", w, sp.requires)
        end
        if sp.petFamily then check(problems, def.pets and def.pets[sp.petFamily], "%s: unknown demon '%s'", w, sp.petFamily) end
    end
    for key, p in pairs(def.pets or {}) do
        check(problems, def.spells[p.summon], "%s.pets.%s: unknown summon '%s'", where, key, tostring(p.summon))
    end
    if def.filler then check(problems, def.spells[def.filler], "%s: unknown filler '%s'", where, def.filler) end
end

local function validateProfile(problems, ns, p, L)
    local where = "Profiles/" .. tostring(p.id)
    local def = ns.Data.classes[p.class]
    if not def then
        problems[#problems + 1] = where .. ": no spell data for class " .. tostring(p.class)
        return
    end
    for _, field in ipairs({ "id", "build", "mode", "version", "patch", "date", "main" }) do
        check(problems, p[field] ~= nil, "%s: missing field '%s'", where, field)
    end
    local expected = def.name .. "_" .. tostring(p.build) .. "_" .. tostring(MODE_SUFFIX[p.mode])
    check(problems, p.id == expected, "%s: id should be '%s' (class_build_mode)", where, expected)
    for key in pairs(p.talents or {}) do
        check(problems, def.talents and def.talents[key], "%s: unknown key talent '%s'", where, key)
    end
    local prepared = ns.Engine.Prepare(p, def)
    for _, e in ipairs(prepared.errors) do problems[#problems + 1] = where .. ": " .. e end
    for _, row in ipairs({ "main", "defense", "cooldown" }) do
        for i, entry in ipairs(p[row] or {}) do
            if entry.why then check(problems, rawget(L, entry.why), "%s: %s #%d: no text for '%s'", where, row, i, entry.why) end
        end
    end
    for i, entry in ipairs(p.prep or {}) do
        check(problems, entry.text and rawget(L, entry.text), "%s: prep #%d: no text for '%s'", where, i, tostring(entry.text))
    end
end

function M.run()
    local problems = {}
    local ns = addon.load({ loadAll = true, login = false })
    for token, def in pairs(ns.Data.classes) do validateClass(problems, token, def) end
    local count = 0
    for _, p in pairs(ns.Data.profiles) do
        count = count + 1
        validateProfile(problems, ns, p, ns.L)
    end
    for i, q in ipairs(ns.Data.quests) do
        local def = ns.Data.classes[q.class]
        check(problems, def and def.spells[q.gives], "Quests #%d: unknown spell '%s'", i, tostring(q.gives))
    end
    table.sort(problems)
    return problems, count
end

function M.main()
    local problems, count = M.run()
    for _, p in ipairs(problems) do print(p) end
    print(string.format("%d profile(s) checked, %d problem(s).", count, #problems))
    return #problems == 0 and 0 or 1
end

-- Tests load this file with the argument "--library" and call M.run() themselves.
if (...) ~= "--library" then os.exit(M.main()) end
return M
