-- Builds and Planner windows: what they show (the models), and drawing every state on frame stubs.
local addon = require("helpers.addon")
local tf = require("helpers.tf")

local IC = 17810

describe("Builds window", function()
    local ns, W, BW
    before_each(function()
        _G.TalentsForeverBookData = tf.data()
        ns, W = addon.load()
        BW = ns.BuildsWindow
        addon.learnUpTo(ns, W, 12)
        W.traits = { [IC] = 3 }
        addon.rescan(ns)
        addon.compute(ns, W)
    end)
    after_each(function() _G.TalentsForeverBookData = nil end)

    it("shows the tab's builds and the card of the selected one", function()
        local m = BW:Model()
        assert.is_true(m.available)
        assert.equal("Warlock", m.className)
        assert.equal(2, #m.list)
        assert.equal("8 / 2 / 1", m.list[1].ptsText)
        assert.equal("Affliction", m.list[1].leadName)
        assert.is_true(m.list[1].yours)
        assert.equal(1, m.selectedIndex)
        local card = m.card
        assert.equal("Affliction", card.title)
        assert.equal(3, #card.trees)
        assert.equal(8, card.trees[1].pts)
        assert.equal("Saved 453, opened 4,884, 138 similar builds", card.stats)
        assert.equal("All 3 points match the build", card.first.text)
        assert.equal("Next point at level 13: spell17810", card.second.text)
        assert.is_true(#card.rotation >= 3)
        assert.is_false(card.isChosen)
    end)

    it("switches tabs, selects, chooses and cancels per spec", function()
        BW:SetTab("leveling")
        BW:Select(2)
        local m = BW:Model()
        assert.equal("Demonology", m.selected.lead)
        BW:ChooseSelected()
        assert.equal("Demonology", ns.Builds.Chosen(1).lead)
        m = BW:Model()
        assert.is_true(m.card.isChosen)
        assert.is_true(m.list[2].chosen)
        BW:ChooseSelected() -- the chosen one: cancels
        assert.is_nil(ns.Builds.Chosen(1))
        -- spec 2 is closed before level 40
        BW:SetSpec(2)
        assert.equal(1, BW:Model().spec)
        W.level = 40
        assert.equal(2, BW:Model().spec)
    end)

    it("shows a pasted link in the card and says when a paste is not a code", function()
        assert.is_nil(BW:Paste("not a link"))
        assert.equal(ns.L.B_BAD_LINK, BW.message)
        local b = BW:Paste("warlock/60/5-11-1-12")
        assert.equal("Affliction", b.lead) -- 5 / 2 / 1: the tree with most points leads
        local m = BW:Model()
        assert.is_nil(m.selectedIndex)
        assert.equal(ns.L.B_STATS_LINK, m.card.stats)
        BW:ChooseSelected()
        assert.equal("warlock/60/5-11-1-12", ns.Builds.Chosen().code)
    end)

    it("draws every state without errors", function()
        BW:Toggle()
        BW:Draw()
        BW:SetTab("group")
        BW:SetTab("pvp") -- an empty list
        BW:Draw()
        BW.pasting = true
        BW:Draw()
        _G.TalentsForeverBookData = nil -- Talents Forever not installed
        assert.is_false(BW:Model().available)
        BW:Draw()
        ns.Commands:Run("builds")
    end)
end)

describe("Planner window", function()
    local ns, W, PW
    before_each(function()
        ns, W = addon.load()
        PW = ns.PlannerWindow
        addon.learnUpTo(ns, W, 12)
        W.level = 14
        W.known[697] = nil
        addon.rescan(ns)
        addon.compute(ns, W)
    end)

    it("shows the trainer, the needs, the preview and the quests", function()
        local m = PW:Model()
        assert.equal(14, m.level)
        assert.matches("^— level 14", m.subtitle)
        assert.matches("spells wait at the trainer", m.trainer.title)
        assert.matches("Richard Kerwin, Undercity %(88.7, 15.9%)", m.trainer.sub)
        local statuses = {}
        for _, row in ipairs(m.needs) do statuses[row.key] = row end
        assert.equal("At trainer", statuses.drain_life.pill)
        assert.matches("heals you at the enemy's cost", statuses.drain_life.sub)
        assert.equal("Quest, 10", statuses.summon_voidwalker.pill)
        assert.same({ 14, 16, 20, 22, 26, 32 }, m.levels)
        assert.equal(16, m.at)
        assert.equal(4, #m.quests)
        assert.equal("Voidwalker", m.quests[1].name)
        assert.is_false(m.quests[1].done)
    end)

    it("previews another level and draws without errors", function()
        PW:SetLevel(20)
        local m = PW:Model()
        assert.equal(20, m.at)
        local found = false
        for _, line in ipairs(m.newSpells) do if line:find("spell5740", 1, true) then found = true end end
        assert.is_true(found) -- Rain of Fire at 20
        assert.is_true(m.newRanks > 0)
        PW:SetLevel(99) -- not offered: back to the default
        assert.equal(16, PW:Model().at)
        PW:Toggle()
        PW:Draw()
        ns.Commands:Run("plan")
    end)

    it("opens from the trainer line under the hint block", function()
        W.pet = { hp = 100, hpMax = 100, family = "Imp" }
        ns.Timers:DetectPet()
        W.auras.player = { { spellId = 687, expirationTime = W.time + 1800 } } -- Demon Skin
        W.items[6265] = 3 -- Soul Shards
        W.items[5512] = 1 -- a Healthstone in the bags
        addon.rescan(ns)
        local r, s = addon.compute(ns, W)
        assert.equal("PREP_TRAINER", r.prep)
        ns.HUD:Render(r, s, W.time)
        assert.is_true(ns.HUD.prep.trainer)
        assert.is_nil(ns.PlannerWindow.frame)
        ns.HUD.prep:GetScript("OnMouseUp")(ns.HUD.prep)
        assert.is_not_nil(ns.PlannerWindow.frame)
    end)

    it("says when nothing waits at the trainer and when the next point is a talent", function()
        addon.learnUpTo(ns, W, 14)
        addon.rescan(ns)
        local m = PW:Model()
        assert.equal("Nothing new at the trainer", m.trainer.title)
        assert.matches("next at level 16", m.trainer.sub)
    end)
end)
