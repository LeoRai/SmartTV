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

    it("hands Life Tap to the display by hidden mana", function()
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

    it("binds the gated hints to the client's health and mana curves", function()
        local r, s = addon.compute(ns, W)
        ns.HUD:Render(r, s, W.time)
        -- Three lines under the block (Life Tap, Drain Life, then Drain Soul), Drain Soul over the
        -- main icon, three over the defense slot.
        assert.equal(7, W.gateBinds)
        assert.equal("life_tap", ns.HUD.alerts[1].action)
        assert.equal("drain_life", ns.HUD.alerts[2].action)
        assert.equal("drain_soul", ns.HUD.alerts[3].action)
        assert.equal("drain_soul", ns.HUD.mainGates[1].rec.action)
    end)

    local function curveAt(world, threshold, third)
        for _, points in ipairs(world.curves) do
            if #points == 4 and points[2][1] == threshold and math.abs(points[3][1] - third) < 1e-9 then return points end
        end
    end

    it("announces Drain Soul under the block from 35% and takes the main icon over at 20%", function()
        local r, s = addon.compute(ns, W)
        assert.equal(15, r.gatedMain.gate.warn)
        ns.HUD:Render(r, s, W.time)
        -- the line fades in evenly from 35% to 20%
        local ramp = curveAt(W, 0.2, 0.35)
        assert.is_table(ramp)
        assert.same({ 0, 1 }, ramp[1])
        assert.equal(0, ramp[3][2])
        -- the main icon is covered only from 20%: no faint stage over it
        local step = curveAt(W, 0.2, 0.201)
        assert.is_table(step)
        assert.equal(0, step[3][2])
    end)

    it("shows low mana as a line under the block and leaves the main icon in sight", function()
        local r, s = addon.compute(ns, W)
        ns.HUD:Render(r, s, W.time)
        local ramp = curveAt(W, 0.15, 0.30)
        assert.is_table(ramp) -- fades in from 30% mana, full at 15%
        for _, g in ipairs(ns.HUD.mainGates) do
            assert.are_not.equal("life_tap", g.rec and g.rec.action) -- never over the main icon
        end
        -- out of combat no line
        W.player.combat = false
        r, s = addon.compute(ns, W)
        ns.HUD:Render(r, s, W.time)
        assert.is_nil(ns.HUD.alerts[1].action)
    end)
end)

describe("A cast that just finished", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 12)
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.player.combat = true
        W.auraError = true
        W.castTimes[707] = 2000
        W.auras.target = { { spellId = 980, expirationTime = W.time + 30 }, { spellId = 172, expirationTime = W.time + 30 } }
        ns.Timers:OnTargetChanged("guid-target", W.time)
        -- Curse of Agony and Corruption are already up (own timers).
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "a", 980)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b", 172)
        W.time = W.time + 2
        -- Immolate rank 2: a 2 s cast.
        W.casting = { spellID = 707, startMS = W.time * 1000, endMS = (W.time + 2) * 1000 }
        ns.Events:Fire("UNIT_SPELLCAST_START", "player", "c", 707)
    end)

    local function mainAction()
        return addon.compute(ns, W).main[1].action
    end

    it("does not come back while the game's confirmation is on its way", function()
        assert.are_not.equal("immolate", mainAction())
        -- The cast bar is gone, the confirmation is not here yet.
        W.time = W.time + 2.05
        W.casting = nil
        assert.are_not.equal("immolate", mainAction())
        -- The game reports the end of the cast bar first, then the success.
        ns.Events:Fire("UNIT_SPELLCAST_STOP", "player", "c", 707)
        W.time = W.time + 0.2
        assert.are_not.equal("immolate", mainAction())
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 707)
        local r = addon.compute(ns, W)
        assert.are_not.equal("immolate", r.main[1].action)
        assert.equal(0, r.main[1].wait) -- the confirmation did not start another global cooldown
    end)

    it("comes back when the cast was interrupted", function()
        W.time = W.time + 1
        W.casting = nil
        ns.Events:Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "c", 707)
        assert.equal("immolate", mainAction())
    end)

    it("comes back if the game never confirms it", function()
        W.time = W.time + 2.05
        W.casting = nil
        ns.Events:Fire("UNIT_SPELLCAST_STOP", "player", "c", 707)
        W.time = W.time + 1
        assert.equal("immolate", mainAction())
    end)
end)

describe("Fixes from the full review", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 12)
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "mob-1" }
        W.player.combat = true
        W.auraError = true
    end)

    it("keeps own debuffs for a target kept through /reload", function()
        -- No PLAYER_TARGET_CHANGED since login: the target was already selected.
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "a", 980)
        local _, s = addon.compute(ns, W)
        assert.is_truthy(s.debuffs.curse_of_agony)
    end)

    it("does not count the target twice when its nameplate is shown", function()
        W.units.nameplate1 = { enemy = true, combat = true, guid = "mob-1" }
        W.plates = { "nameplate1" }
        _G.UnitIsUnit = function() return ns.API.IsSecret and require("helpers.wow").secret() end
        local _, s = addon.compute(ns, W)
        assert.equal(1, s.enemies)
    end)

    it("wand shots do not restart the global cooldown", function()
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "w1", 5019)
        local r = addon.compute(ns, W)
        assert.equal(0, r.main[1].wait)
    end)

    it("a refused press of another spell leaves the cast alone", function()
        W.castTimes[705] = 2800
        ns.Events:Fire("UNIT_SPELLCAST_START", "player", "c", 705)
        ns.Events:Fire("UNIT_SPELLCAST_FAILED", "player", "x", 172)
        assert.is_table(ns.Timers.cast)
        ns.Events:Fire("UNIT_SPELLCAST_FAILED", "player", "c", 705)
        assert.is_nil(ns.Timers.cast)
    end)
end)

describe("Fewer surprises in the queue", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 20)
        W.pet = { hp = 100, hpMax = 100, family = "Демон Бездны" }
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "mob-1" }
        W.player.combat = true
        ns.Timers:DetectPet()
    end)

    it("does not count mobs fighting someone else", function()
        W.units.nameplate1 = { enemy = true, combat = true, guid = "other-mob" } -- busy with another player
        W.units.nameplate2 = { enemy = true, combat = true, guid = "mob-2", petThreat = 3 } -- on our demon
        W.plates = { "nameplate1", "nameplate2" }
        local _, s = addon.compute(ns, W)
        assert.equal(2, s.enemies) -- the target and the mob on the demon
    end)

    it("uses a new enemy count only after it holds for a moment", function()
        local _, s = addon.compute(ns, W)
        assert.equal(1, s.enemies)
        W.units.nameplate1 = { enemy = true, combat = true, guid = "mob-2", threat = 1 }
        W.plates = { "nameplate1" }
        _, s = addon.compute(ns, W)
        assert.equal(1, s.enemies) -- the add just appeared
        W.time = W.time + 0.2
        _, s = addon.compute(ns, W)
        assert.equal(1, s.enemies)
        W.time = W.time + 0.3
        _, s = addon.compute(ns, W)
        assert.equal(2, s.enemies)
        -- it stepped out of range for a blink: the count stays
        W.plates = {}
        W.time = W.time + 0.1
        _, s = addon.compute(ns, W)
        assert.equal(2, s.enemies)
    end)

    it("keeps unaffordable spells out of the forecast until Life Tap", function()
        W.auras.target = { { spellId = 1094, expirationTime = W.time + 30 }, { spellId = 6222, expirationTime = W.time + 30 },
                           { spellId = 1014, expirationTime = W.time + 30 } }
        for _, id in ipairs({ 1088, 1094, 6222, 1014, 1120, 689, 5676 }) do W.usable[id] = false; W.noMana[id] = true end
        local r = addon.compute(ns, W)
        assert.same({ "life_tap", "shadow_bolt", "shadow_bolt", "shadow_bolt" }, addon.mainActions(r))
        -- too little health to tap: the wand, all the way
        W.player.hp = 30
        r = addon.compute(ns, W)
        assert.same({ "shoot", "shoot", "shoot", "shoot" }, addon.mainActions(r))
    end)
end)

describe("Profiles from Forever's own data", function()
    local ns, W
    local function fightAt(level, extra, profileId, talents)
        ns, W = addon.load()
        addon.learnUpTo(ns, W, level, extra)
        W.traits = talents or {}
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "mob" }
        W.player.combat = true
        addon.rescan(ns)
        addon.compute(ns, W)
        ns.Loop:Use(ns.Data.profiles[profileId])
    end
    local function dots(ids)
        W.auras.target = {}
        for _, id in ipairs(ids) do table.insert(W.auras.target, { spellId = id, expirationTime = W.time + 60 }) end
    end

    it("Destruction: Immolate first, Incinerate as the filler on a burning target", function()
        fightAt(50, { 412758 }, "Warlock_Destruction_Leveling", { [412758] = 1 })
        dots({ 11667, 11713, 11671 }) -- Immolate, Bane of Agony, Corruption of level 50
        local r = addon.compute(ns, W)
        assert.equal("incinerate", r.main[1].action)
        dots({ 11713, 11671 })
        assert.equal("immolate", addon.compute(ns, W).main[1].action)
    end)

    it("Affliction: Wrack once the dots are up, Shadow Bolt without it", function()
        fightAt(45, { 18265, 1316697 }, "Warlock_Affliction_Leveling", { [18265] = 1, [1316697] = 1 })
        dots({ 11712, 11671, 18879 }) -- Bane of Agony, Corruption, Siphon Life
        assert.equal("wrack", addon.compute(ns, W).main[1].action)
        fightAt(45, { 18265 }, "Warlock_Affliction_Leveling", { [18265] = 1 })
        dots({ 11712, 11671, 18879 })
        assert.equal("shadow_bolt", addon.compute(ns, W).main[1].action)
    end)

    it("puts Curse of the Elements next to Bane of Agony on a strong target only", function()
        fightAt(30, nil, "Warlock_Generic_Leveling")
        local function hasElements()
            for _, a in ipairs(addon.mainActions(addon.compute(ns, W))) do
                if a == "curse_of_elements" then return true end
            end
            return false
        end
        assert.is_false(hasElements())
        W.target.class = "elite"
        assert.is_true(hasElements())
    end)

    it("hands Drain Life to the display by hidden health, as a line under the block", function()
        fightAt(20, nil, "Warlock_Generic_Leveling")
        W.secret = { ["player.hp"] = true }
        local r = addon.compute(ns, W)
        local found
        for _, g in ipairs(r.gatedMains) do if g.action == "drain_life" then found = g end end
        assert.is_table(found)
        assert.equal(0.4, found.threshold)
        assert.equal("ALERT_LOW_HEALTH", found.line.alert)
        for _, a in ipairs(addon.mainActions(r)) do assert.are_not.equal("drain_life", a) end
    end)
end)
