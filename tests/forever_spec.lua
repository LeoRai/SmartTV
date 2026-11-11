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
