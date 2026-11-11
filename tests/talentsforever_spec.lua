-- Talents Forever integration on a small copy of its data layout.
local addon = require("helpers.addon")

local fakeData = require("helpers.tf").data

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
