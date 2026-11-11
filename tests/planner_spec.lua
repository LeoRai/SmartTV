-- Planner (stage 2): trainer summary, what the rotation still needs, level preview, class quests.
local addon = require("helpers.addon")

describe("Planner", function()
    local ns, W, Planner, def
    before_each(function()
        ns, W = addon.load()
        Planner = ns.Planner
        def = ns.Data.class
    end)

    local function state()
        local _, s = addon.compute(ns, W)
        return s
    end

    it("sums up what waits at the trainer, with prices", function()
        addon.learnUpTo(ns, W, 12)
        W.level = 14 -- two levels without a visit
        addon.rescan(ns)
        local s = state()
        local sum = Planner.TrainerSummary(def, 14, s.knownRank, s.talents)
        assert.equal(s.trainer, sum.count)
        assert.is_true(sum.count > 0)
        local keys = {}
        for _, it in ipairs(sum.list) do
            keys[it.key] = true
            assert.is_true(it.level > 12 and it.level <= 14)
        end
        assert.is_true(keys.drain_life and keys.curse_of_recklessness)
        assert.equal(sum.cost > 0 or sum.unknownCost, true)
    end)

    it("writes prices in the client's coins, or in letters without it", function()
        assert.equal("1g 23s 45c", Planner.Money(12345))
        assert.equal("50s", Planner.Money(5000))
        assert.equal("0c", Planner.Money(0))
        assert.equal(ns.L.PRICE_UNKNOWN, Planner.Money(nil))
        _G.GetCoinTextureString = function(c) return "coins:" .. c end
        assert.equal("coins:12345", Planner.Money(12345))
        _G.GetCoinTextureString = nil
    end)

    it("sends the player to the trainer they visited, else the known one", function()
        local t = Planner.Trainer(def)
        assert.equal("Richard Kerwin", t.npc)
        assert.equal("Undercity", t.place)
        assert.equal(88.7, t.x)
        W.faction = "Alliance"
        assert.is_nil(Planner.Trainer(def)) -- no Alliance trainer in the data yet
        ns.Events:Fire("TRAINER_SHOW")
        t = Planner.Trainer(def)
        assert.equal("npc", t.npc) -- the test client names every unit by its token
        assert.equal("Brill", t.place)
        assert.equal(61.6, t.x)
        assert.equal(52.5, t.y)
    end)

    it("knows which class quests are done", function()
        addon.learnUpTo(ns, W, 22)
        W.known[712] = nil -- the Succubus quest is not done yet (the Voidwalker is)
        addon.rescan(ns)
        local q = Planner.Quests(def, state().known, 22)
        assert.equal(4, #q)
        assert.equal("voidwalker", q[1].key)
        assert.is_true(q[1].done)
        assert.is_false(q[2].done)
        assert.is_true(q[2].available)
        assert.is_false(q[3].available)
    end)

    it("lists what the rotation still needs, most urgent first", function()
        addon.learnUpTo(ns, W, 12)
        W.level = 14
        W.known[697] = nil -- no Voidwalker yet
        addon.rescan(ns)
        local s = state()
        local profile = ns.Data.profiles.Warlock_Affliction_Leveling
        local onBars = function(key) return key ~= "fear" end
        local next = { spellID = 18094, name = "Nightfall", rank = 1, level = 14, now = true }
        local needs = Planner.Needs(def, profile, s, 14, onBars, next, { siphon_life = true })
        local status = {}
        for _, it in ipairs(needs) do status[it.key] = it.status end
        assert.equal("trainer", status.drain_life)          -- level 14: waiting at the trainer
        assert.equal("talent", status.siphon_life)          -- a talent of the build
        assert.equal("talent", status["talent:18094"])      -- the build's next point
        assert.equal("level", status.rain_of_fire)          -- opens at 20
        assert.equal("quest", status.summon_voidwalker)     -- class quest from 10
        assert.equal("nobar", status.fear)
        assert.is_nil(status.amplify_curse)                 -- a talent the build does not take
        -- order: trainer, talent, quest for now, not on the bars, later levels, later quests
        for i = 2, #needs do
            assert.is_true(Planner.Rank(needs[i - 1]) <= Planner.Rank(needs[i]))
        end
        local voidwalker, fearAt
        for i, it in ipairs(needs) do
            if it.key == "summon_voidwalker" then voidwalker = i end
            if it.key == "fear" then fearAt = i end
        end
        assert.is_true(voidwalker < fearAt)
    end)

    it("previews the levels ahead: what is new and the rotation there", function()
        assert.same({ 12, 14, 18, 20, 24, 30 }, Planner.PreviewLevels(12))
        assert.same({ 56, 58, 60 }, Planner.PreviewLevels(56))
        local new = Planner.NewAt(def, 12, 14, {})
        local keys = {}
        for _, it in ipairs(new) do keys[it.key] = it.first end
        assert.is_true(keys.drain_life)              -- a new spell
        assert.is_true(keys.curse_of_recklessness)
        addon.learnUpTo(ns, W, 12)
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.player.combat = true
        local live = addon.mainActions(addon.compute(ns, W))
        local s = state()
        local prepared = ns.Engine.Prepare(ns.Data.profiles.Warlock_Affliction_Leveling, def)
        local rot = Planner.RotationAt(def, prepared, 20, s, 4)
        local keys2 = {}
        for i, r in ipairs(rot) do keys2[i] = r.key end
        assert.same({ "curse_of_agony", "corruption", "immolate", "shadow_bolt" }, keys2)
        -- the preview has its own engine: the live hint stays as it was
        assert.same(live, addon.mainActions(ns.Engine.result))
    end)
end)

describe("Planner: the rotation now is the live hint's", function()
    it("matches the live hint on a fresh target, with only what is learned", function()
        local ns, W = addon.load()
        addon.learnUpTo(ns, W, 12)
        W.level = 16 -- four levels without a visit to the trainer: Drain Life and new ranks not bought
        addon.rescan(ns)
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "fresh" }
        W.player.combat = true
        local r, s = addon.compute(ns, W)
        local live = addon.mainActions(r)
        local def = ns.Data.class
        local now = ns.Planner.RotationNow(def, ns.Loop.current, s, #live)
        local keys = {}
        for i, x in ipairs(now) do keys[i] = x.key end
        assert.same(live, keys)
        -- the preview at level 16 assumes the purchases: it may differ, "now" must not
        for _, x in ipairs(now) do assert.is_not_nil(s.known[x.key]) end
    end)
end)
