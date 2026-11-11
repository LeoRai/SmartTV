-- Talents Forever integration on a small copy of its data layout.
local addon = require("helpers.addon")

-- Same shape as TalentsForeverBookData (TalentsForeverBook/Data.lua), three tiny trees.
local function fakeData()
    return {
        build = "1.60.1.70755", codeVersion = "12",
        classes = {
            WARLOCK = {
                name = "Warlock",
                trees = {
                    { name = "Affliction", talents = {
                        { name = "Improved Corruption", max = 5, spell = 17810, node = 105924 },
                        { name = "Nightfall", max = 2, spell = 18094, node = 105914 },
                        { name = "Siphon Life", max = 1, spell = 18265, node = 105912 },
                    } },
                    { name = "Demonology", talents = {
                        { name = "Demonic Sacrifice", max = 1, spell = 18788, node = 105900 },
                        { name = "Fel Domination", max = 1, spell = 18708, node = 105895 },
                    } },
                    { name = "Destruction", talents = {
                        { name = "Shadowburn", max = 1, spell = 17877, node = 105884 },
                    } },
                },
            },
        },
        popular = {
            WARLOCK = {
                builds = 127534, window = "since the Oct 15 patch", asOf = "2026-11-05",
                spec = { { "Affliction", 40 }, { "Demonology", 38 }, { "Destruction", 22 } },
                top = {
                    { code = "warlock/60/521-11-1-12", lead = "Affliction", pts = { 8, 2, 1 }, rank = 1, saved = 453, opened = 4884, variants = 138 },
                },
                fors = {
                    leveling = {
                        { code = "warlock/60/521-1--12", lead = { "Affliction" }, pts = { 8, 1, 0 } },
                        { code = "warlock/60/-11-1-12", lead = { "Demonology" }, pts = { 0, 2, 1 } },
                    },
                    pve = { { code = "warlock/60/5-11-1-12", lead = { "Demonology" }, pts = { 5, 2, 1 } } },
                },
            },
        },
    }
end

describe("Talents Forever", function()
    local ns, W, TF
    before_each(function()
        _G.TalentsForeverBookData = fakeData()
        ns, W = addon.load()
        TF = ns.TalentsForever
    end)
    after_each(function() _G.TalentsForeverBookData = nil end)

    it("decodes a build code into talent ranks and tree points", function()
        local ranks, points, level = TF.Decode("WARLOCK", "warlock/60/521-1--12")
        assert.same({ [17810] = 5, [18094] = 2, [18265] = 1, [18788] = 1 }, ranks)
        assert.same({ 8, 1, 0 }, points)
        assert.equal(60, level)
        assert.is_nil((TF.Decode("WARLOCK", "not a code")))
        assert.is_nil((TF.Decode("WARLOCK", "warlock/60/521--1-3"))) -- older generation, no addon to carry it over
    end)

    it("lists popular builds per mode, best first", function()
        local leveling = TF.Builds("WARLOCK", "leveling")
        assert.equal(2, #leveling)
        assert.equal("Affliction", leveling[1].lead)
        assert.equal("Demonology", TF.Builds("WARLOCK", "group")[1].lead)
        assert.equal(453, TF.Builds("WARLOCK", nil)[1].saved)
        assert.equal(127534, TF.Meta("WARLOCK").builds)
    end)

    it("finds the closest build to the player's talents", function()
        local build, score = TF.Closest("WARLOCK", "leveling", { [18788] = 1, [18708] = 1 })
        assert.equal("Demonology", build.lead)
        assert.equal(1, score)
    end)

    it("splits Forever's trait ranks into trees and picks the profile", function()
        addon.learnUpTo(ns, W, 40, { 18094, 18265 })
        W.traits = { [17810] = 5, [18094] = 2, [18265] = 1, [18788] = 1 }
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.player.combat = true
        addon.rescan(ns)
        local r, s = addon.compute(ns, W)
        assert.same({ 8, 1, 0 }, ns.State.treePoints)
        assert.equal("Warlock_Affliction_Leveling", r.prepared.id)
        assert.equal(2, s.talents.nightfall)
        assert.equal("Affliction", ns.BuildMatcher.popular.lead)
        assert.equal(1, ns.BuildMatcher.similarity)
    end)

    it("does nothing without Talents Forever", function()
        _G.TalentsForeverBookData = nil
        assert.is_false(TF.Available())
        assert.same({}, TF.Builds("WARLOCK", "leveling"))
        addon.learnUpTo(ns, W, 20)
        W.traits = { [18094] = 1 }
        addon.rescan(ns)
        addon.compute(ns, W)
        assert.is_nil(ns.State.treePoints)
        assert.is_nil(ns.BuildMatcher.popular)
    end)
end)
