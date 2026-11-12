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
        -- Improved Corruption fills the row for Nightfall (Shadowburn changes no Affliction hint)
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

    it("shows the trainer, the needs, the rotation by level and the quests", function()
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
        -- the rotation by level: now (what is learned), after the trainer, then where the hints change
        assert.equal(ns.L.P_EVO_NO_BUILD, m.note) -- no build chosen: the current talents only
        assert.is_true(m.steps[1].now)
        assert.equal("Now", m.steps[1].label)
        assert.equal("curse_of_agony", m.steps[1].icons[1].key)
        assert.matches("^For a situation: spell1120 %(finisher%)", m.steps[1].text)
        assert.equal("Trainer", m.steps[2].label)
        assert.equal("+ spell689 (low health)", m.steps[2].text) -- Drain Life waits at the trainer
        assert.equal("level 20", m.steps[3].label)
        assert.matches("%+ spell5740 %(3%+ enemies%)", m.steps[3].text) -- Rain of Fire
        assert.equal("level 60", m.steps[#m.steps].label)
        for _, st in ipairs(m.steps) do
            for _, ic in ipairs(st.icons) do assert.are_not.equal("siphon_life", ic.key) end -- no talent of a build
        end
        assert.equal(4, #m.quests)
        assert.equal("Voidwalker", m.quests[1].name)
        assert.is_false(m.quests[1].done)
    end)

    it("draws the steps without errors", function()
        PW:Toggle()
        PW:Draw()
        ns.Commands:Run("plan")
    end)

    it("folds the steps that do not fit into the last row", function()
        local Planner = ns.Planner
        local real = Planner.Evolution
        Planner.Evolution = function()
            local steps = { { level = 14, now = true, rotation = {}, situations = {} } }
            for l = 16, 60, 4 do -- 12 more
                steps[#steps + 1] = { level = l, rotation = { { key = "x" .. l, id = 686, new = true } }, talents = {},
                                      replaced = {}, added = { { key = "x" .. l, id = 686 } }, removed = {}, situations = {} }
            end
            return steps
        end
        local ok, m = pcall(PW.Model, PW)
        Planner.Evolution = real
        assert.is_true(ok, m)
        assert.equal(10, #m.steps)
        assert.equal("levels 48-60", m.steps[10].label)
        assert.matches("^%+ spell686; level 52: %+ spell686; level 56: %+ spell686; level 60: %+ spell686$", m.steps[10].text)
        assert.equal("x60", m.steps[10].icons[1].key) -- the rotation at the end
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

    it("shows how the chosen build's rotation develops, with the talents it takes", function()
        local list = ns.Builds.List("leveling", W.traits)
        ns.Builds.Choose(list[1]) -- Affliction 8 / 1 / 0: Improved Corruption, Nightfall, Siphon Life, ...
        W.level = 14
        addon.rescan(ns)
        local m = PW:Model()
        assert.equal(ns.L.P_EVO_NOTE, m.note)
        local byLabel = {}
        for _, st in ipairs(m.steps) do byLabel[st.label] = st end
        -- two free points at 14 fill Improved Corruption; Nightfall from 15, Siphon Life from 17
        local nf = byLabel["level 15"]
        assert.equal("talents: spell18094; + spell705 on proc", nf.text) -- Shadow Bolt, the rank known
        assert.is_true(nf.icons[#nf.icons].proc)
        assert.is_true(nf.icons[#nf.icons].new)
        -- the talent's own spell says it: no "talents" part
        assert.equal("spell18265 instead of spell707", byLabel["level 17"].text)
        assert.is_true(byLabel["level 17"].icons[1].new)
        assert.equal("siphon_life", byLabel["level 17"].icons[1].key)
        -- the proc stays in the row when the rotation changes
        local last = byLabel["level 17"].icons[#byLabel["level 17"].icons]
        assert.is_true(last.proc)
        assert.is_falsy(last.new)
        -- level 30: the preview rotation uses Siphon Life from the build's talent
        local def, s = ns.Data.class, ns.State.snapshot
        local plan = ns.Planner.TalentsAt(def, ns.TalentsForever.Decode("WARLOCK", list[1].code), W.traits, 14, 30)
        local rot = ns.Planner.RotationAt(def, ns.Loop.current, 30, s, 4, ns.Planner.TalentKeysAt(def, s.talents, plan))
        assert.equal("siphon_life", rot[1].key)
        local without = ns.Planner.RotationAt(def, ns.Loop.current, 30, s, 4)
        for _, r in ipairs(without) do assert.are_not.equal("siphon_life", r.key) end
        PW:Toggle()
        PW:Draw()
    end)

    it("names what a talent changes when the rotation does not show it, from the rank it needs", function()
        local d = tf.data()
        table.insert(d.classes.WARLOCK.trees[3].talents, { name = "Shadow and Flame", max = 5, spell = 426316, row = 1, col = 1 })
        _G.TalentsForeverBookData = d
        ns, W = addon.load()
        PW = ns.PlannerWindow
        addon.learnUpTo(ns, W, 12)
        W.level = 14
        W.traits = { [IC] = 3 }
        addon.rescan(ns)
        addon.compute(ns, W)
        ns.Builds.Choose(ns.Builds.FromLink("warlock/60/--15-12")) -- Shadowburn, Shadow and Flame 5/5
        assert.equal("Warlock_Destruction_Leveling", ns.BuildMatcher.profile.id)
        local m = PW:Model()
        local byLabel = {}
        for _, st in ipairs(m.steps) do byLabel[st.label] = st end
        -- Shadowburn now (a free point): its finisher line joins at the trainer step
        assert.matches("%+ spell17877 %(finisher%)", byLabel["Trainer"].text)
        -- Shadow and Flame's first point at 14 changes nothing; at 5/5 (level 18) it keeps Immolate
        assert.is_nil(byLabel["Trainer"].text:find("spell426316", 1, true))
        assert.equal("talents: spell426316 5/5 — " .. ns.L.P_EVO_EFFECT_shadow_and_flame, byLabel["level 18"].text)
    end)

    it("names a talent the hints do not follow from the level its spell comes", function()
        local d = tf.data()
        table.insert(d.classes.WARLOCK.trees[2].talents, { name = "Decimation", max = 2, spell = 440870, row = 1, col = 1 })
        _G.TalentsForeverBookData = d
        ns, W = addon.load()
        PW = ns.PlannerWindow
        addon.learnUpTo(ns, W, 12)
        W.level = 14
        W.traits = { [IC] = 3 }
        addon.rescan(ns)
        addon.compute(ns, W)
        ns.Builds.Choose(ns.Builds.FromLink("warlock/60/-1132--12")) -- Demonic Brand 3/3, Decimation 2/2
        local m = PW:Model()
        local byLabel = {}
        for _, st in ipairs(m.steps) do byLabel[st.label] = st end
        -- Decimation is taken early, Soul Fire comes at 48: named there, as not followed by the hints
        assert.equal("talents: spell440870 — " .. ns.L.P_EVO_EFFECT_decimation, byLabel["level 48"].text)
        for _, st in ipairs(m.steps) do
            for _, ic in ipairs(st.icons) do assert.are_not.equal("soul_fire", ic.key) end
        end
    end)
end)
