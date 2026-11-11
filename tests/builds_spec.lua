-- Builds (stage 2): the chosen Talents Forever build per spec, the lists, the comparison.
local addon = require("helpers.addon")
local tf = require("helpers.tf")

-- Talent spells of the test data.
local IC, NF, SL, DS, FD, SB = 17810, 18094, 18265, 18788, 18708, 17877

describe("Builds", function()
    local ns, W, Builds
    before_each(function()
        _G.TalentsForeverBookData = tf.data()
        ns, W = addon.load()
        Builds = ns.Builds
        addon.learnUpTo(ns, W, 12)
    end)
    after_each(function() _G.TalentsForeverBookData = nil end)

    it("keeps one chosen build per spec and follows it in the rotation", function()
        W.traits = {} -- no talent points yet: nothing tells the build apart
        addon.rescan(ns)
        addon.compute(ns, W)
        assert.equal("Warlock_Generic_Leveling", ns.BuildMatcher.profile.id)

        local fired = 0
        ns.Events:On("FC_BUILD_CHOSEN", {}, function() fired = fired + 1 end)
        local list = Builds.List("leveling", {})
        Builds.Choose(list[1])
        assert.equal(1, fired)
        assert.equal("Affliction", Builds.Chosen().lead)
        assert.equal("warlock/60/521-1--12", Builds.Chosen(1).code)
        assert.is_nil(Builds.Chosen(2))
        assert.equal("Warlock_Affliction_Leveling", ns.BuildMatcher.profile.id)
        assert.is_true(Builds.List("leveling", {})[1].chosen)

        Builds.Choose(list[2], 2) -- the second spec keeps its own
        assert.equal("Demonology", Builds.Chosen(2).lead)
        assert.equal("Affliction", Builds.Chosen().lead)

        Builds.Choose(nil) -- back to "by my talents"
        assert.is_nil(Builds.Chosen())
        assert.equal("Warlock_Generic_Leveling", ns.BuildMatcher.profile.id)
    end)

    it("lists builds per tab and marks the one closest to the player's talents", function()
        local all = Builds.List("all", { [IC] = 3 })
        assert.equal(2, #all)
        assert.equal(453, all[1].saved)
        assert.same({ 8, 2, 1 }, all[1].pts)
        assert.is_true(all[1].yours)
        assert.is_nil(all[2].yours)
        assert.equal(1, all[1].similarity)

        local group = Builds.List("group", {})
        assert.equal(1, #group)
        assert.equal("Demonology", group[1].lead)
        assert.is_nil(group[1].yours) -- no points: nothing is "yours"
        assert.same({}, Builds.List("pvp", {}))
    end)

    it("reads a pasted link or code", function()
        local b = Builds.FromLink("  https://talentsforever.com/warlock/60/521-1--12?a ")
        assert.equal("warlock/60/521-1--12", b.code)
        assert.equal("Affliction", b.lead)
        assert.same({ 8, 1, 0 }, b.pts)
        assert.equal("link", b.source)
        assert.equal(5, b.ranks[IC])
        local none, why = Builds.FromLink("hello")
        assert.is_nil(none)
        assert.equal("bad_code", why)
    end)

    it("places points like the site: lead tree first, rows open with 5 points, prerequisites full", function()
        local layout = ns.TalentsForever.Layout("WARLOCK")
        local order = Builds.GuessOrder(layout, { [IC] = 5, [NF] = 2, [SL] = 1, [DS] = 1, [FD] = 1, [SB] = 1 })
        local ids = {}
        for i, o in ipairs(order) do ids[i] = o.talent.spell end
        assert.same({ IC, IC, IC, IC, IC, NF, NF, SL, DS, FD, SB }, ids)
        -- Siphon Life before Nightfall is full cannot be placed: it waits for its prerequisite.
        order = Builds.GuessOrder(layout, { [IC] = 5, [NF] = 1, [SL] = 1 })
        assert.equal(6, #order)
    end)

    it("compares the player's talents with a build and finds the next point", function()
        local build = { [IC] = 5, [NF] = 2, [SL] = 1, [DS] = 1 }
        -- level 12 with 3 points in Improved Corruption: all of them match, the 4th point comes at 13
        local c = Builds.Compare(build, { [IC] = 3 }, 12)
        assert.equal(3, c.spent)
        assert.is_true(c.all)
        assert.equal(IC, c.next.spellID)
        assert.equal(4, c.next.rank)
        assert.equal(13, c.next.level)
        assert.is_false(c.next.now)
        -- the client says one point is free: it goes in now
        c = Builds.Compare(build, { [IC] = 3 }, 12, 1)
        assert.is_true(c.next.now)
        assert.equal(12, c.next.level)
        -- a point the build does not have
        c = Builds.Compare(build, { [IC] = 2, [SB] = 1 }, 12)
        assert.is_false(c.all)
        assert.equal(2, c.matched)
        -- everything taken
        c = Builds.Compare(build, { [IC] = 5, [NF] = 2, [SL] = 1, [DS] = 1 }, 18)
        assert.is_true(c.done)
        assert.is_nil(c.next)
    end)

    it("reads free talent points from the client", function()
        assert.is_nil((ns.API.TalentPoints(1117)))
        W.traits = {}
        W.talentPoints = { 2, 1 }
        local unspent, spent = ns.API.TalentPoints(ns.TalentsForever.TreeID("WARLOCK"))
        assert.equal(2, unspent)
        assert.equal(1, spent)
    end)

    it("shows a build's rotation at the player's level and what joins it later", function()
        -- level 18 with 9 points elsewhere: the Demonology build's points come at 19, 20, 21
        addon.learnUpTo(ns, W, 18)
        W.traits = { [IC] = 5, [NF] = 2, [SL] = 1, [SB] = 1 }
        addon.rescan(ns)
        addon.compute(ns, W)
        local def = ns.Data.class
        local build = ns.TalentsForever.Decode("WARLOCK", "warlock/60/-113--12") -- Sacrifice, Domination, Brand 3/3
        local plan = ns.Planner.TalentsAt(def, build, W.traits, 18, 60)
        assert.equal(19, plan[1].first)
        assert.equal(21, plan[3].first) -- Demonic Brand's first point
        local profile = ns.Data.profiles.Warlock_Demonology_Leveling
        local _, s = addon.compute(ns, W)
        local later = ns.Planner.Upcoming(def, profile, s, 18, build)
        local at = {}
        for _, u in ipairs(later) do at[u.key] = u end
        -- Searing Pain is known from 18, but the rotation uses it only with Demonic Brand
        assert.equal(21, at.searing_pain.level)
        assert.equal("aoe", at.hellfire.kind)
        assert.equal(30, at.hellfire.level)
        assert.is_nil(at.siphon_life) -- this build does not take it
        -- the window: Demonology's rotation now, and the line of what comes later
        ns.BuildsWindow.link = { code = "warlock/60/-113--12", lead = "Demonology", pts = { 0, 5, 0 }, ranks = build, source = "link" }
        local m = ns.BuildsWindow:Model()
        assert.equal("curse_of_agony", m.card.rotation[1].key)
        assert.matches("spell5676 from 21", m.card.later)
        assert.matches("spell1949 from 30 %(3%+ enemies%)", m.card.later)
    end)

    it("opens the second spec from level 40", function()
        assert.equal(1, Builds.ActiveSpec())
        assert.equal(40, Builds.SPEC2_LEVEL)
    end)
end)
