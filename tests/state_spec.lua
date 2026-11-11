-- Modes, build recognition, profile switching, slash commands.
local addon = require("helpers.addon")

local function talentTabs(a, b, c)
    -- One talent per tree carrying all the points: enough for tree totals.
    return { { { "A", a, 31 } }, { { "B", b, 31 } }, { { "C", c, 31 } } }
end

describe("Modes", function()
    local ns, W
    before_each(function() ns, W = addon.load() end)

    it("detects the mode from the instance type", function()
        assert.equal("pvp", ns.Modes.FromInstance("pvp"))
        assert.equal("pvp", ns.Modes.FromInstance("arena"))
        assert.equal("group", ns.Modes.FromInstance("party"))
        assert.equal("group", ns.Modes.FromInstance("raid"))
        assert.equal("leveling", ns.Modes.FromInstance("none"))
    end)

    it("switches by itself on entering a dungeon and can be pinned", function()
        W.instance = "party"
        ns.Events:Fire("PLAYER_ENTERING_WORLD")
        assert.equal("group", ns.Modes.current)
        ns.db.mode = "pvp"
        ns.Events:Fire("FC_SETTINGS_CHANGED", "mode")
        assert.equal("pvp", ns.Modes.current)
        ns.db.mode = "auto"
        ns.Events:Fire("FC_SETTINGS_CHANGED", "mode")
        assert.equal("group", ns.Modes.current)
    end)
end)

describe("BuildMatcher", function()
    local ns
    before_each(function() ns = addon.load() end)

    local function select(points, talents, mode)
        return ns.BuildMatcher.Select(ns.Data.class, ns.Data.profiles, points, talents or {}, mode or "leveling")
    end

    it("picks the profile of the tree with most points", function()
        local p, approximate, build = select({ 31, 0, 20 }, { nightfall = 2, siphon_life = 1 })
        assert.equal("Warlock_Affliction_Leveling", p.id)
        assert.is_false(approximate)
        assert.equal("Affliction", build)
    end)

    it("marks the profile approximate when key talents are missing", function()
        local p, approximate = select({ 31, 0, 20 }, {})
        assert.equal("Warlock_Affliction_Leveling", p.id)
        assert.is_true(approximate)
    end)

    it("falls back to the generic profile", function()
        local p, approximate, build = select({ 0, 31, 20 })
        assert.equal("Warlock_Generic_Leveling", p.id)
        assert.is_true(approximate)
        assert.equal("Demonology", build)
        p = select({ 0, 0, 3 })
        assert.equal("Warlock_Generic_Leveling", p.id)
    end)

    it("guesses the build by key talents when tree points are unknown", function()
        local p = select(nil, { nightfall = 1, siphon_life = 1 })
        assert.equal("Warlock_Affliction_Leveling", p.id)
    end)

    it("uses the leveling profile, marked approximate, where the mode has none yet", function()
        local p, approximate = select({ 31, 0, 20 }, { nightfall = 2, siphon_life = 1 }, "group")
        assert.equal("Warlock_Affliction_Leveling", p.id)
        assert.is_true(approximate)
    end)
end)

describe("Profile switching", function()
    it("follows a talent change on the very next update", function()
        local ns, W = addon.load()
        addon.learnUpTo(ns, W, 40)
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.player.combat = true
        W.talentTabs = talentTabs(0, 0, 0)
        addon.rescan(ns)
        local r = addon.compute(ns, W)
        assert.equal("Warlock_Generic_Leveling", r.prepared.id)

        W.talentTabs = talentTabs(30, 0, 0)
        W.known[18094] = true -- Nightfall
        W.known[18095] = true
        W.known[18265] = true -- Siphon Life
        ns.Events:Fire("PLAYER_TALENT_UPDATE")
        r = addon.compute(ns, W)
        assert.equal("Warlock_Affliction_Leveling", r.prepared.id)
        assert.equal(2, ns.State.talents.nightfall)
        assert.equal("siphon_life", r.main[1].action)
    end)
end)

describe("Slash commands", function()
    it("toggle hints, lock, mode and debug", function()
        local ns, W = addon.load()
        SlashCmdList.FOREVERCOACH("toggle")
        assert.is_false(ns.db.shown)
        SlashCmdList.FOREVERCOACH("toggle")
        assert.is_true(ns.db.shown)
        SlashCmdList.FOREVERCOACH("unlock")
        assert.is_false(ns.db.locked)
        SlashCmdList.FOREVERCOACH("mode PvP")
        assert.equal("pvp", ns.db.mode)
        SlashCmdList.FOREVERCOACH("debug")
        assert.is_true(ns.db.debug)
        SlashCmdList.FOREVERCOACH("state")
        SlashCmdList.FOREVERCOACH("perf")
        SlashCmdList.FOREVERCOACH("help")
        SlashCmdList.FOREVERCOACH("reset")
        assert.is_true(ns.db.locked)
        assert.equal("auto", ns.db.mode)
        assert.is_true(#W.chat > 5)
    end)

    it("warns once when the client is newer than the data", function()
        local ns, W = addon.load({ world = { build = "1.61.0" } })
        local warnings = 0
        for _, line in ipairs(W.chat) do if line:find("1.60.1", 1, true) then warnings = warnings + 1 end end
        assert.equal(1, warnings)
        ns.Data:CheckVersion(ns.db)
        local again = 0
        for _, line in ipairs(W.chat) do if line:find("1.60.1", 1, true) then again = again + 1 end end
        assert.equal(1, again)
    end)
end)
