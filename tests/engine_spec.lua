-- Engine scenarios: "level 12, Voidwalker, target at 20% -> Drain Soul" and friends.
local addon = require("helpers.addon")

-- Warlock spell IDs used below (Data/Spells/Warlock.lua).
local SHADOW_BOLT_R2, SHADOW_BOLT_R3 = 695, 705
local CORRUPTION_R1 = 172
local SHADOW_TRANCE = 17941
local NIGHTFALL_R1 = 18094
local HEALTHSTONE_MINOR = 5512
local SOUL_SHARD = 6265
local SACRIFICE_R1 = 7812

local function fight(_, W, target)
    W.target = target or { hp = 100, hpMax = 100, enemy = true }
    W.player.combat = true
end

describe("Engine", function()
    local ns, W

    before_each(function()
        ns, W = addon.load()
    end)

    it("level 12, Voidwalker, target at 20% -> Drain Soul", function()
        addon.learnUpTo(ns, W, 12)
        W.pet = { hp = 100, hpMax = 100, family = "Voidwalker" }
        ns.Timers:DetectPet()
        fight(ns, W, { hp = 20, hpMax = 100, enemy = true })
        local r = addon.compute(ns, W)
        assert.equal("drain_soul", r.main[1].action)
        assert.equal(1120, r.main[1].id)
        assert.equal("Warlock_Generic_Leveling", r.prepared.id)
    end)

    it("does not plan the same channel twice in a row", function()
        addon.learnUpTo(ns, W, 12)
        fight(ns, W, { hp = 20, hpMax = 100, enemy = true })
        local r = addon.compute(ns, W)
        assert.equal("drain_soul", r.main[1].action)
        assert.are_not.equal("drain_soul", r.main[2].action)
    end)

    it("level 1: Immolate first, then Shadow Bolt", function()
        addon.learnUpTo(ns, W, 1)
        fight(ns, W)
        ns.db.nextIcons = 1
        local r = addon.compute(ns, W)
        assert.same({ "immolate", "shadow_bolt" }, addon.mainActions(r))
    end)

    it("shows nothing without a hostile target", function()
        addon.learnUpTo(ns, W, 10)
        W.player.combat = true
        local r = addon.compute(ns, W)
        assert.equal(0, r.mainCount)
        W.target = { hp = 100, hpMax = 100, enemy = false }
        r = addon.compute(ns, W)
        assert.equal(0, r.mainCount)
    end)

    it("respects the number of next icons", function()
        addon.learnUpTo(ns, W, 20)
        fight(ns, W)
        ns.db.nextIcons = 0
        assert.equal(1, addon.compute(ns, W).mainCount)
        ns.db.nextIcons = 2
        assert.equal(3, addon.compute(ns, W).mainCount)
    end)

    it("puts dots up on a long-living target and plays them forward", function()
        addon.learnUpTo(ns, W, 14)
        fight(ns, W)
        ns.db.nextIcons = 2
        local r = addon.compute(ns, W)
        -- Curse of Agony, then Corruption, then Immolate: each one disappears from the plan once cast.
        assert.same({ "curse_of_agony", "corruption", "immolate" }, addon.mainActions(r))
    end)

    it("skips Corruption on a target that dies in less than 8 seconds", function()
        addon.learnUpTo(ns, W, 14)
        fight(ns, W)
        W.auras.target = { { spellId = 1014, expirationTime = W.time + 30 } } -- Curse of Agony up
        -- Health falls 10% per second: at 60% the target has ~6 s left.
        for hp = 100, 60, -10 do
            W.target.hp = hp
            addon.compute(ns, W)
            W.time = W.time + 1
        end
        W.time = W.time - 1
        local r, s = addon.compute(ns, W)
        assert.is_true(s.target.ttd < 8)
        assert.are_not.equal("corruption", r.main[1].action)

        -- A fresh target that does not lose health lives "long": Corruption comes back.
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "other" }
        W.auras.target = { { spellId = 1014, expirationTime = W.time + 30 } }
        r = addon.compute(ns, W)
        assert.equal("corruption", r.main[1].action)
    end)

    it("glows Shadow Bolt on a Nightfall proc", function()
        addon.learnUpTo(ns, W, 20, { NIGHTFALL_R1 })
        fight(ns, W)
        W.auras.player = { { spellId = SHADOW_TRANCE, expirationTime = W.time + 8 } }
        local r, s = addon.compute(ns, W)
        assert.equal(1, s.talents.nightfall)
        assert.equal("shadow_bolt", r.main[1].action)
        assert.is_true(r.main[1].glow)
        -- The proc is consumed in the forecast: the next icon is not another instant Shadow Bolt.
        assert.are_not.equal("shadow_bolt", r.main[2].action)
    end)

    it("switches to the new rank right after it is learned", function()
        addon.learnUpTo(ns, W, 11)
        fight(ns, W)
        W.auras.target = {
            { spellId = 707, expirationTime = W.time + 30 },
            { spellId = CORRUPTION_R1, expirationTime = W.time + 30 },
            { spellId = 980, expirationTime = W.time + 30 },
        }
        local r = addon.compute(ns, W)
        assert.equal("shadow_bolt", r.main[1].action)
        assert.equal(SHADOW_BOLT_R2, r.main[1].id)

        W.level = 12
        addon.rescan(ns)
        local _, s = addon.compute(ns, W)
        local waiting = s.trainer
        assert.is_true(waiting > 0)

        W.known[SHADOW_BOLT_R3] = true
        addon.rescan(ns)
        r, s = addon.compute(ns, W)
        assert.equal(SHADOW_BOLT_R3, r.main[1].id)
        assert.equal(waiting - 1, s.trainer)
    end)

    it("uses a Healthstone below the health threshold", function()
        addon.learnUpTo(ns, W, 20)
        fight(ns, W)
        W.items[HEALTHSTONE_MINOR] = 1
        W.player.hp = 30
        addon.rescan(ns)
        local r = addon.compute(ns, W)
        assert.is_true(r.hasDefense)
        assert.equal("healthstone", r.defense.action)
        assert.equal(HEALTHSTONE_MINOR, r.defense.id)

        W.player.hp = 90
        r = addon.compute(ns, W)
        assert.is_false(r.hasDefense)
    end)

    it("sacrifices a dying Voidwalker", function()
        addon.learnUpTo(ns, W, 20)
        W.petKnown[SACRIFICE_R1] = true
        W.pet = { hp = 15, hpMax = 100, family = "Voidwalker" }
        ns.Timers:DetectPet()
        addon.rescan(ns)
        fight(ns, W)
        local r = addon.compute(ns, W)
        assert.equal("sacrifice", r.defense.action)
    end)

    it("heals a dying Imp with Health Funnel", function()
        addon.learnUpTo(ns, W, 20)
        W.pet = { hp = 30, hpMax = 100, family = "Imp" }
        ns.Timers:DetectPet()
        fight(ns, W)
        local r = addon.compute(ns, W)
        assert.equal("health_funnel", r.defense.action)
    end)

    it("fears the second enemy", function()
        addon.learnUpTo(ns, W, 20)
        fight(ns, W)
        -- The target has no nameplate here; one more enemy has one.
        W.units.nameplate1 = { enemy = true, combat = true, threat = 0 }
        W.plates = { "nameplate1" }
        local r, s = addon.compute(ns, W)
        assert.equal(2, s.enemies)
        assert.equal("fear", r.defense.action)
    end)

    it("taps life when out of mana and falls back to the wand", function()
        addon.learnUpTo(ns, W, 20)
        fight(ns, W)
        W.auras.target = {
            { spellId = 1094, expirationTime = W.time + 30 },
            { spellId = 6222, expirationTime = W.time + 30 },
            { spellId = 1014, expirationTime = W.time + 30 },
        }
        W.player.mana = 5
        for _, id in ipairs({ 1088, 1120, 689, 5676 }) do W.usable[id] = false; W.noMana[id] = true end
        local r = addon.compute(ns, W)
        assert.equal("life_tap", r.main[1].action)

        W.player.hp = 30 -- too low to tap
        r = addon.compute(ns, W)
        assert.equal("shoot", r.main[1].action)
    end)

    it("waits for the global cooldown and for the cast in progress", function()
        addon.learnUpTo(ns, W, 14)
        fight(ns, W)
        -- Corruption is being cast: it lands in 1.5 s and leaves the plan.
        W.casting = { spellID = 6222, startMS = (W.time - 0.5) * 1000, endMS = (W.time + 1.5) * 1000 }
        local r = addon.compute(ns, W)
        assert.are_not.equal("corruption", r.main[1].action)
        assert.is_true(math.abs(r.main[1].wait - 1.5) < 0.01)

        -- An instant curse triggers the global cooldown (own timer: the client shows none here).
        W.casting = nil
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 1014)
        r = addon.compute(ns, W)
        assert.is_true(r.main[1].wait > 1.4)
    end)

    it("tints the hint when the target is out of range", function()
        addon.learnUpTo(ns, W, 4)
        fight(ns, W)
        for _, sp in pairs(ns.Data.class.spells) do
            for _, rank in ipairs(sp.ranks) do W.range[rank[1]] = false end
        end
        local r = addon.compute(ns, W)
        assert.is_true(r.main[1].outOfRange)
    end)

    it("shows one preparation item out of combat", function()
        addon.learnUpTo(ns, W, 12)
        W.items[SOUL_SHARD] = 2
        addon.rescan(ns)
        local r = addon.compute(ns, W)
        assert.equal("PREP_NO_PET", r.prep)

        W.pet = { hp = 100, hpMax = 100, family = "Voidwalker" }
        r = addon.compute(ns, W)
        assert.equal("PREP_NO_HEALTHSTONE", r.prep)

        W.items[HEALTHSTONE_MINOR] = 1
        W.auras.player = { { spellId = 696, expirationTime = 0 } } -- Demon Skin
        W.level = 14
        addon.rescan(ns)
        r = addon.compute(ns, W)
        assert.equal("PREP_TRAINER", r.prep)
        assert.is_true(r.prepValue > 0)

        W.player.combat = true
        W.target = { hp = 100, hpMax = 100, enemy = true }
        r = addon.compute(ns, W)
        assert.is_nil(r.prep)
    end)

    it("stays fast: under 1 ms per update on average", function()
        addon.learnUpTo(ns, W, 60, { NIGHTFALL_R1, 18265 })
        fight(ns, W)
        ns.db.nextIcons = 2
        local n = 2000
        local start = os.clock()
        for i = 1, n do
            W.time = W.time + 0.1
            W.target.hp = 100 - (i % 100)
            addon.compute(ns, W)
        end
        local avg = (os.clock() - start) * 1000 / n
        assert.is_true(avg < 1, string.format("average %.3f ms", avg))
    end)
end)

describe("Engine with values hidden by the client", function()
    local ns, W

    before_each(function()
        ns, W = addon.load()
        W.secret = {
            ["player.hp"] = true, ["target.hp"] = true, ["pet.hp"] = true, ["player.mana"] = true,
            auras = true, cooldowns = true, cast = true,
        }
    end)

    it("never fails and falls back to safe assumptions", function()
        addon.learnUpTo(ns, W, 20)
        W.items[HEALTHSTONE_MINOR] = 1
        addon.rescan(ns)
        fight(ns, W)
        W.player.hp = 10 -- hidden: the engine can't know it
        local r, s = addon.compute(ns, W)
        assert.is_true(s.hidden["player.hp_pct"])
        assert.is_true(s.hidden["target.ttd"])
        assert.equal(100, s.player.hp_pct)
        assert.equal(999, s.target.ttd)
        assert.is_false(r.hasDefense)
        assert.equal("curse_of_agony", r.main[1].action)
    end)

    it("tracks its own debuffs from casts", function()
        addon.learnUpTo(ns, W, 14)
        fight(ns, W)
        ns.Timers:OnTargetChanged("guid-target", W.time)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1014) -- Curse of Agony
        W.time = W.time + 2
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 6222) -- Corruption
        W.time = W.time + 2
        -- The auras are on the target, but the client only shows secrets.
        W.auras.target = { { spellId = 1014, expirationTime = W.time + 20 }, { spellId = 6222, expirationTime = W.time + 13 } }
        local r, s = addon.compute(ns, W)
        assert.is_true(s.hidden.debuffs)
        assert.is_true(s.debuffs.curse_of_agony > W.time)
        assert.is_true(s.debuffs.corruption > W.time)
        assert.equal("immolate", r.main[1].action)

        -- 25 s later Curse of Agony (24 s) has run out, Corruption (15 s) too.
        W.time = W.time + 25
        r = addon.compute(ns, W)
        assert.equal("curse_of_agony", r.main[1].action)
    end)

    it("trusts own timers while the client shows none of our debuffs", function()
        W.secret = {}
        addon.learnUpTo(ns, W, 14)
        fight(ns, W)
        ns.Timers:OnTargetChanged("guid-target", W.time)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1014) -- Curse of Agony
        W.time = W.time + 4
        -- The client withholds the aura list entirely: no confirmation yet, own timer wins.
        local r = addon.compute(ns, W)
        assert.are_not.equal("curse_of_agony", r.main[1].action)

        -- The client shows our curse: from now on its list is the truth.
        W.auras.target = { { spellId = 1014, expirationTime = W.time + 20 } }
        addon.compute(ns, W)
        assert.is_true(ns.State.auraConfirmed)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 6222) -- Corruption, resisted
        W.time = W.time + 3
        r = addon.compute(ns, W)
        assert.equal("corruption", r.main[1].action)
    end)

    it("falls back to the client's proc highlight for Shadow Trance", function()
        addon.learnUpTo(ns, W, 20, { NIGHTFALL_R1 })
        fight(ns, W)
        ns.Events:Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1088)
        local r = addon.compute(ns, W)
        assert.equal("shadow_bolt", r.main[1].action)
        assert.is_true(r.main[1].glow)
    end)
end)
