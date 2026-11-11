-- Block of the mockup: sounds, AoE, forecast depth, bar highlight, settings migration.
local addon = require("helpers.addon")

local function fight(W, target)
    W.target = target or { hp = 100, hpMax = 100, enemy = true }
    W.player.combat = true
end

local function soundsOf(W, kind)
    local n = 0
    for _, path in ipairs(W.sounds) do if path:find(kind .. "_", 1, true) then n = n + 1 end end
    return n
end

describe("Sounds", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 14)
        fight(W)
    end)

    -- Instant curse: own global cooldown runs 1.5 s; tick the loop through it.
    local function castAndWait(pressAhead)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 1014)
        ns.Loop:Update()                     -- waiting for the global cooldown
        W.time = W.time + 1.0
        ns.Loop:Update()
        if pressAhead then ns.Events:Fire("UNIT_SPELLCAST_SENT", "player") end
        W.time = W.time + 0.6                -- global cooldown over
        ns.Loop:Update()
        W.time = W.time + 0.15
        ns.Loop:Update()
    end

    it("clicks once when the global cooldown ends", function()
        castAndWait(false)
        assert.equal(1, soundsOf(W, "ready"))
        W.time = W.time + 0.2
        ns.Loop:Update()
        assert.equal(1, soundsOf(W, "ready"))
    end)

    it("stays silent when the button was pressed in advance", function()
        castAndWait(true)
        assert.equal(0, soundsOf(W, "ready"))
    end)

    it("stays silent when switched off, but the preview plays", function()
        ns.db.soundReady = false
        castAndWait(false)
        assert.equal(0, soundsOf(W, "ready"))
        assert.is_true(ns.Sounds:Play("ready", true))
        assert.equal(1, soundsOf(W, "ready"))
    end)

    it("chimes on an instant proc", function()
        addon.learnUpTo(ns, W, 20, { 18094 })
        ns.Loop:Update()
        assert.equal(0, soundsOf(W, "proc"))
        W.auras.player = { { spellId = 17941, expirationTime = W.time + 8 } }
        ns.Loop:Update()
        assert.equal(1, soundsOf(W, "proc"))
        ns.Loop:Update()
        assert.equal(1, soundsOf(W, "proc"))
    end)

    it("picks the file closest to the volume", function()
        assert.matches("ready_40%.ogg$", ns.Sounds.File("ready", 35))
        assert.matches("proc_70%.ogg$", ns.Sounds.File("proc", 70))
        assert.matches("proc_10%.ogg$", ns.Sounds.File("proc", 2))
        assert.is_nil(ns.Sounds.File("proc", 0))
    end)
end)

describe("Block", function()
    local ns, W
    before_each(function() ns, W = addon.load() end)

    it("forecasts three steps after the main icon by default", function()
        addon.learnUpTo(ns, W, 20)
        fight(W)
        assert.equal(3, ns.db.nextIcons)
        assert.equal(4, addon.compute(ns, W).mainCount)
    end)

    it("switches to AoE from three enemies: Hellfire from 30, Rain of Fire before", function()
        addon.learnUpTo(ns, W, 30)
        fight(W)
        W.units.nameplate1 = { enemy = true, combat = true }
        W.units.nameplate2 = { enemy = true, combat = true }
        W.plates = { "nameplate1", "nameplate2" }
        local r, s = addon.compute(ns, W)
        assert.equal(3, s.enemies)
        assert.is_true(r.aoe)
        assert.equal("hellfire", r.main[1].action)

        ns, W = addon.load()
        addon.learnUpTo(ns, W, 24)
        fight(W)
        W.units.nameplate1 = { enemy = true, combat = true }
        W.units.nameplate2 = { enemy = true, combat = true }
        W.plates = { "nameplate1", "nameplate2" }
        r = addon.compute(ns, W)
        assert.equal("rain_of_fire", r.main[1].action)
    end)

    it("taps life when mana is lower than health by the threshold", function()
        addon.learnUpTo(ns, W, 20)
        fight(W)
        W.player.mana = 50
        assert.equal("life_tap", addon.compute(ns, W).main[1].action)
        W.player.mana = 85
        assert.are_not.equal("life_tap", addon.compute(ns, W).main[1].action)
        ns.db.lifeTapGap = 10
        W.player.mana = 85
        assert.equal("life_tap", addon.compute(ns, W).main[1].action)
    end)

    it("finds the key and the bar button of the main hint", function()
        addon.learnUpTo(ns, W, 20)
        fight(W)
        W.actions[2] = { "spell", 1088 } -- Shadow Bolt rank 4
        W.bindings.ACTIONBUTTON2 = "2"
        local button = { IsVisible = function() return true end }
        _G.ActionButton2 = button
        ns.ActionBars.dirty = true
        assert.equal("2", ns.ActionBars:KeyFor("shadow_bolt"))
        assert.equal(button, ns.ActionBars:ButtonFor("shadow_bolt"))
        assert.is_true(ns.ActionBars:IsOnBars("shadow_bolt"))
        ns.ActionBars:Highlight("shadow_bolt")
        assert.equal("shadow_bolt", ns.ActionBars.highlighted)
        _G.ActionButton2 = nil
    end)

    it("names the town of the last class trainer in the preparation line", function()
        addon.learnUpTo(ns, W, 12)
        W.pet = { hp = 100, hpMax = 100, family = "Voidwalker" }
        W.items[5512] = 1
        W.items[6265] = 2
        W.auras.player = { { spellId = 696, expirationTime = 0 } }
        W.level = 14
        addon.rescan(ns)
        ns.Events:Fire("TRAINER_SHOW")
        local r = addon.compute(ns, W)
        assert.equal("PREP_TRAINER", r.prep)
        assert.equal("trainer", r.prepPlace)
        assert.equal("Brill", ns.db.trainerPlace)
    end)

    it("moves old settings to the new layout", function()
        local db = ns.Migrate({ schema = 1, nextIcons = 1, scale = 1.2, sound = true, hideOutOfCombat = false })
        assert.equal(3, db.nextIcons)
        assert.is_true(db.hideOutOfCombat)
        assert.is_nil(db.scale)
        assert.is_nil(db.sound)
        assert.equal(2, db.schema)
    end)
end)
