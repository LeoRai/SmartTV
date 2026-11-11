-- What stage 0 found in WoW Forever 1.60.1 (build 70888), replayed against the engine:
--   always hidden: player health and mana, demon health, nameplate health
--   hidden in combat: target health, spell cooldowns, speed; aura reads raise an error
--   readable: casts and their events, usable / no mana, range, nameplates, items, pet family
--   the global cooldown spell 61304 answers nil; talents only through the trait system.
local addon = require("helpers.addon")

local function forever(W, inCombat)
    W.secret = { ["player.hp"] = true, ["player.mana"] = true, ["pet.hp"] = true }
    W.noGcdSpell = true
    W.auraError = inCombat
    if inCombat then
        W.secret["target.hp"] = true
        W.secret.cooldowns = true
    end
end

describe("Forever as found at stage 0", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 12)
        W.pet = { hp = 100, hpMax = 100, family = "Демон Бездны" }
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.player.combat = true
        forever(W, true)
        ns.Timers:DetectPet()
    end)

    it("keeps working when aura reads fail in combat", function()
        local r, s = addon.compute(ns, W)
        assert.equal("curse_of_agony", r.main[1].action)
        assert.is_true(s.hidden.debuffs)
        assert.is_true(s.hidden["player.hp_pct"])
        assert.is_true(s.hidden["target.ttd"])
        assert.equal("voidwalker", s.pet.family)
    end)

    it("stops asking for auras for the rest of the fight", function()
        addon.compute(ns, W)
        local calls = W.auraCalls
        addon.compute(ns, W)
        addon.compute(ns, W)
        assert.equal(calls, W.auraCalls)
        assert.is_true(ns.State.aurasBlocked)
        ns.Events:Fire("PLAYER_REGEN_ENABLED")
        assert.is_false(ns.State.aurasBlocked)
    end)

    it("runs the rotation on its own timers", function()
        ns.Timers:OnTargetChanged("guid-target", W.time)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 980) -- Curse of Agony
        local r = addon.compute(ns, W)
        assert.is_true(r.main[1].wait > 1.4)          -- own global cooldown, the client gives none
        W.time = W.time + 1.6
        r = addon.compute(ns, W)
        assert.equal("corruption", r.main[1].action)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 172) -- Corruption
        W.time = W.time + 1.6
        r = addon.compute(ns, W)
        assert.equal("immolate", r.main[1].action)
    end)

    it("taps life when the filler is out of mana", function()
        for _, id in ipairs({ 705, 707, 172, 980, 1120 }) do W.usable[id] = false; W.noMana[id] = true end
        local r = addon.compute(ns, W)
        assert.equal("life_tap", r.main[1].action)
    end)

    it("reads talents from the trait system", function()
        W.traits = { [18094] = 2, [17810] = 1, [18265] = 0 }
        addon.rescan(ns)
        local _, s = addon.compute(ns, W)
        assert.equal(2, s.talents.nightfall)
        assert.equal(0, s.talents.siphon_life)
    end)

    it("counts the ranks waiting at the trainer like the game does", function()
        W.level = 14
        addon.rescan(ns)
        local _, s = addon.compute(ns, W)
        -- Level 14 at the Undercity trainer: Corruption 2, Drain Life 1, Curse of Recklessness 1.
        assert.equal(3, s.trainer)
    end)
end)

describe("Health gates in Forever", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 20)
        W.pet = { hp = 100, hpMax = 100, family = "Демон Бездны" }
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.items[5512] = 1 -- Minor Healthstone
        W.player.combat = true
        W.secret = { ["player.hp"] = true, ["target.hp"] = true, ["pet.hp"] = true, ["player.mana"] = true }
        W.auraError = true
        W.petKnown[7812] = true -- Sacrifice
        ns.Timers:DetectPet()
        addon.rescan(ns)
    end)

    it("hands the hidden-health hints to the display instead of guessing", function()
        local r = addon.compute(ns, W)
        assert.are_not.equal("drain_soul", r.main[1].action)
        assert.equal("drain_soul", r.gatedMain.action)
        assert.equal("target", r.gatedMain.gate.unit)
        assert.equal(0.2, r.gatedMain.threshold)
        local actions = {}
        for i, g in ipairs(r.gatedDefense) do actions[i] = g.action end
        assert.same({ "healthstone", "sacrifice", "health_funnel" }, actions)
        assert.equal(0.35, r.gatedDefense[1].threshold)
        assert.is_false(r.hasDefense)
    end)

    it("lays Life Tap over the main icon by hidden mana", function()
        local r = addon.compute(ns, W)
        assert.equal("life_tap", r.gatedMains[2].action)
        assert.equal("mana", r.gatedMains[2].gate.power)
        assert.equal(0.15, r.gatedMains[2].threshold)
    end)

    it("keeps Drain Soul out once enough shards are kept", function()
        W.items[6265] = 5
        addon.rescan(ns)
        local r = addon.compute(ns, W)
        for _, g in ipairs(r.gatedMains) do assert.are_not.equal("drain_soul", g.action) end
    end)

    it("binds the gated icons to the client's health curve", function()
        local r, s = addon.compute(ns, W)
        ns.HUD:Render(r, s, W.time)
        -- Drain Soul and Life Tap over the main icon (icon + its frame each), three over the defense slot.
        assert.equal(7, W.gateBinds)
    end)

    it("fades Drain Soul in from 35% and shows it fully at 20%", function()
        local r, s = addon.compute(ns, W)
        assert.equal(15, r.gatedMain.gate.warn)
        ns.HUD:Render(r, s, W.time)
        local fade
        for _, points in ipairs(W.curves) do
            if #points == 5 and points[2][1] == 0.2 then fade = points end
        end
        assert.is_table(fade)
        assert.same({ 0, 1 }, fade[1])
        assert.same({ 0.2, 1 }, fade[2])
        assert.equal(ns.API.WARN_ALPHA, fade[3][2])
        assert.is_true(math.abs(fade[4][1] - 0.35) < 1e-9)
        assert.equal(0, fade[4][2])
    end)
end)
