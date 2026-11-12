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
        assert.equal("Next point at level 13: spell17877", card.second.text) -- Shadowburn: changes the hints, open
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
        -- now, the levels where the hints change, 60
        assert.equal(14, m.levels[1])
        assert.equal(60, m.levels[#m.levels])
        assert.equal(20, m.at)
        assert.equal(4, #m.quests)
        assert.equal("Voidwalker", m.quests[1].name)
        assert.is_false(m.quests[1].done)
    end)

    it("previews another level and draws without errors", function()
        PW:SetLevel(30)
        local m = PW:Model()
        assert.equal(30, m.at)
        local kinds = {}
        for _, g in ipairs(m.situational) do kinds[g.kind] = g end
        assert.is_table(kinds.aoe) -- Rain of Fire from 20, Hellfire from 30
        assert.is_true(kinds.aoe.icons[1].new)
        assert.is_table(kinds.strong) -- Curse of the Elements on strong targets from 20
        assert.matches("^By level 30 the trainer adds", m.trainerAt)
        PW:SetLevel(99) -- not offered: back to the default
        assert.equal(20, PW:Model().at)
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

describe("Planner: the chosen build's plan by level", function()
    local ns, W, PW
    local NF, SL = 18094, 18265 -- Nightfall, Siphon Life (IC: Improved Corruption, above)
    before_each(function()
        _G.TalentsForeverBookData = tf.data()
        ns, W = addon.load()
        PW = ns.PlannerWindow
        addon.learnUpTo(ns, W, 12)
        W.traits = { [IC] = 3 }
        addon.rescan(ns)
        addon.compute(ns, W)
    end)
    after_each(function() _G.TalentsForeverBookData = nil end)

    it("places the build's points level by level, in the site's order", function()
        local def = ns.Data.class
        local build = { [IC] = 5, [NF] = 2, [SL] = 1 }
        local plan, points = ns.Planner.TalentsAt(def, build, { [IC] = 3 }, 12, 16)
        assert.equal(4, points) -- one point per level 13..16
        assert.equal(IC, plan[1].spellID)
        assert.equal(3, plan[1].from)
        assert.equal(5, plan[1].to)
        assert.equal(14, plan[1].level)
        assert.equal(NF, plan[2].spellID)
        assert.equal(2, plan[2].to)
        assert.equal(16, plan[2].level)
        -- a free point now moves everything a level earlier
        plan, points = ns.Planner.TalentsAt(def, build, { [IC] = 3 }, 12, 16, 1)
        assert.equal(5, points)
        assert.equal(SL, plan[3].spellID)
        -- the talents then, by our keys
        local keys = ns.Planner.TalentKeysAt(def, { nightfall = 0 }, plan)
        assert.equal(2, keys.nightfall)
        assert.equal(1, keys.siphon_life)
    end)

    it("shows the plan in the level preview and plays the rotation with those talents", function()
        assert.equal(ns.L.P_TALENTS_NO_BUILD, PW:Model().talentNote) -- no build chosen yet
        local list = ns.Builds.List("leveling", W.traits)
        ns.Builds.Choose(list[1]) -- Affliction 8 / 1 / 0: Improved Corruption, Nightfall, Siphon Life, ...
        local m = PW:Model()
        PW:SetLevel(m.levels[#m.levels]) -- 60
        m = PW:Model()
        assert.is_nil(m.talentNote)
        -- the talents that change the hints by name, from the level they start working; the rest as a number
        -- (Improved Corruption 4 and 5 at 13 and 14 fill the row for Nightfall; Demonic Sacrifice last)
        assert.same({ "spell18094 2/2, from level 15", "spell18265 1/1, from level 17", "3 more points elsewhere" }, m.talents)
        PW:SetLevel(12) -- the current level: no free point
        assert.equal(ns.L.P_TALENTS_NONE, PW:Model().talentNote)
        -- level 30: Siphon Life comes from the build's talent, the preview rotation uses it
        local def, s = ns.Data.class, ns.State.snapshot
        local plan = ns.Planner.TalentsAt(def, ns.TalentsForever.Decode("WARLOCK", list[1].code), W.traits, 12, 30)
        local rot = ns.Planner.RotationAt(def, ns.Loop.current, 30, s, 4, ns.Planner.TalentKeysAt(def, s.talents, plan))
        assert.equal("siphon_life", rot[1].key)
        local without = ns.Planner.RotationAt(def, ns.Loop.current, 30, s, 4)
        for _, r in ipairs(without) do assert.are_not.equal("siphon_life", r.key) end
        PW:Toggle()
        PW:Draw()
    end)
end)
