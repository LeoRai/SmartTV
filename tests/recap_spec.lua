-- Combat recap (stage 3): the recorder on simulated fights, the metrics, the window.
local addon = require("helpers.addon")

-- Spells of a level 20 warlock.
local AGONY, CORRUPTION, IMMOLATE, BOLT, SHOOT = 1014, 6222, 1094, 1088, 5019
local TRANCE = 17941

local function setup(level)
    local ns, W = addon.load()
    addon.learnUpTo(ns, W, level or 20)
    return ns, W
end

local guidN = 0
-- An instant spell: the press reports SENT, then SUCCEEDED (with a cast GUID unless guid = false).
local function press(ns, id, guid)
    guidN = guidN + 1
    local g = guid ~= false and ("Cast-" .. guidN) or nil
    ns.Events:Fire("UNIT_SPELLCAST_SENT", "player", "target", g, id)
    ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", g, id)
end

local function fight(ns, W)
    W.player.combat = true
    W.target = W.target or { hp = 100, hpMax = 100, enemy = true, guid = "mob-1" }
    ns.Events:Fire("PLAYER_REGEN_DISABLED")
end

-- The loop runs 10 times a second.
local function wait(ns, W, seconds)
    for _ = 1, math.floor(seconds * 10 + 0.5) do
        W.time = W.time + 0.1
        ns.Loop:Update()
    end
end

local function finish(ns, W)
    W.player.combat = false
    ns.Events:Fire("PLAYER_REGEN_ENABLED")
    return ns.Recorder.Store().fights[1]
end

local function dotsUp(W, except)
    W.auras.target = {}
    for _, id in ipairs({ AGONY, CORRUPTION, IMMOLATE }) do
        if id ~= except then table.insert(W.auras.target, { spellId = id, expirationTime = W.time + 60 }) end
    end
end

describe("Combat recap: recorder", function()
    local ns, W
    before_each(function()
        ns, W = setup(20)
        ns.db.recapMinFight = 3
    end)

    it("counts presses as hinted and otherwise, with the reason", function()
        fight(ns, W)
        wait(ns, W, 0.2)
        assert.equal("curse_of_agony", ns.Recorder.hint.action)
        press(ns, AGONY)                      -- as hinted
        wait(ns, W, 1.6)                      -- the global cooldown ends, the hint moves on
        assert.equal("corruption", ns.Recorder.hint.action)
        press(ns, BOLT)                       -- otherwise: Corruption was not on the target
        wait(ns, W, 1.5)
        local rec = finish(ns, W)
        assert.equal(2, rec.presses)
        assert.equal(1, rec.matched)
        assert.equal("ox", rec.events)
        local e = rec.errors[1]
        assert.equal("miss", e.kind)
        assert.equal("shadow_bolt", e.pressed)
        assert.equal("corruption", e.hint)
        assert.equal("down", e.reason)
        assert.equal(0.5, ns.RecapMetrics.Accuracy(rec))
        assert.equal("target", rec.target) -- the test client names units by their token
        assert.equal(20, rec.level)
    end)

    it("counts pauses longer than 1.5 s while a hint was ready", function()
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 3.6)                      -- 1.5 s of global cooldown, then about 2 s doing nothing
        press(ns, CORRUPTION)
        wait(ns, W, 1.4)
        local rec = finish(ns, W)
        assert.equal(1, rec.pauses)
        assert.is_true(math.abs(rec.idle - 2.1) < 0.15)
        assert.equal("o-o", rec.events)
        local e = rec.errors[1]
        assert.equal("idle", e.kind)
        assert.equal("corruption", e.hint)
        -- a short wait is no pause
        ns.Recorder:StartFight(W.time)
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 2.6)                      -- 1 s after the global cooldown
        press(ns, CORRUPTION)
        wait(ns, W, 1.4)
        assert.equal(0, finish(ns, W).pauses)
    end)

    it("measures how long the profile's debuffs stayed on the target", function()
        fight(ns, W)
        dotsUp(W)
        wait(ns, W, 0.1)
        press(ns, BOLT)
        wait(ns, W, 3.9)                      -- all three up: 4 s
        dotsUp(W, CORRUPTION)                 -- Corruption falls off and is asked for: 2 s down
        wait(ns, W, 2)
        local rec = finish(ns, W)
        local up = ns.RecapMetrics.Uptime(rec)
        assert.is_true(math.abs(up - 16 / 18) < 0.03, tostring(up))
    end)

    it("counts procs and the ones that ran out unused", function()
        fight(ns, W)
        dotsUp(W)
        wait(ns, W, 0.1)
        press(ns, BOLT)
        W.auras.player = { { spellId = TRANCE, expirationTime = W.time + 10 } }
        wait(ns, W, 1)
        W.auras.player = {}                   -- ran out, no Shadow Bolt
        wait(ns, W, 1)
        W.auras.player = { { spellId = TRANCE, expirationTime = W.time + 10 } }
        wait(ns, W, 0.5)
        press(ns, BOLT)                       -- used
        W.auras.player = {}
        wait(ns, W, 1)
        local rec = finish(ns, W)
        assert.equal(2, rec.procs)
        assert.equal(1, rec.missed)
    end)

    it("names the talent that gives procs when the player does not have it", function()
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 3)
        local rec = finish(ns, W)
        assert.equal(0, rec.procs)
        assert.equal("nightfall", rec.procTalent.key)
        assert.equal(18094, rec.procTalent.id)
    end)

    it("takes a wand's auto-repeat for one press, and a cast for one press", function()
        fight(ns, W)
        wait(ns, W, 0.2)
        for _ = 1, 3 do
            ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Shot-" .. W.time, SHOOT)
            wait(ns, W, 1.5)
        end
        wait(ns, W, 3.5)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Shot-late", SHOOT) -- shooting again: a new press
        -- a cast with a GUID: START, then SUCCEEDED of the same cast
        ns.Events:Fire("UNIT_SPELLCAST_START", "player", "Cast-A", BOLT)
        wait(ns, W, 0.3)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-A", BOLT)
        -- without GUIDs: the success of the spell whose cast started is the same press
        ns.Events:Fire("UNIT_SPELLCAST_START", "player", nil, IMMOLATE)
        wait(ns, W, 0.3)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, IMMOLATE)
        -- an interrupted cast stays a press; the next instant success is a new one
        ns.Events:Fire("UNIT_SPELLCAST_START", "player", nil, IMMOLATE)
        ns.Events:Fire("UNIT_SPELLCAST_INTERRUPTED", "player", nil, IMMOLATE)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, IMMOLATE)
        wait(ns, W, 0.5)
        local rec = finish(ns, W)
        assert.equal(6, rec.presses) -- wand, wand again, bolt, immolate, interrupted immolate, immolate
    end)

    it("does not count a cast begun before combat (the pull) twice", function()
        ns.Events:Fire("UNIT_SPELLCAST_START", "player", "Cast-pull", BOLT)
        fight(ns, W)
        ns.Events:Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-pull", BOLT)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 3)
        assert.equal(1, finish(ns, W).presses)
    end)

    it("drops short fights and fights without presses, keeps the last 10", function()
        ns.db.recapMinFight = 10
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 5)
        assert.is_nil(finish(ns, W))
        fight(ns, W)
        wait(ns, W, 12)
        assert.is_nil(finish(ns, W)) -- no press at all
        ns.db.recapMinFight = 3
        for _ = 1, 12 do
            fight(ns, W)
            wait(ns, W, 0.2)
            press(ns, AGONY)
            wait(ns, W, 3)
            finish(ns, W)
        end
        assert.equal(10, #ns.Recorder.Store().fights)
        assert.equal(12, ns.Recorder.session.fights)
    end)

    it("sums up the session against the last one", function()
        local Metrics = ns.RecapMetrics
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 3)
        finish(ns, W)
        local first = ns.Recorder.session
        assert.equal(1, first.fights)
        ns.Recorder:StartSession() -- next login
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, BOLT) -- otherwise
        wait(ns, W, 1.6)
        press(ns, CORRUPTION)
        wait(ns, W, 3)
        finish(ns, W)
        local sum = Metrics.Session(ns.Recorder.session, ns.Recorder.Store().sessions)
        assert.equal(1, sum.fights)
        assert.equal(1, sum.previous)
        assert.is_true(sum.delta < 0)
    end)

    it("scores training fights and keeps the best one per build", function()
        ns.db.training = true
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 3)
        local rec = finish(ns, W)
        local records = ns.Recorder.Store().records
        local best = records["Generic:leveling"]
        assert.equal(rec.score, best.score)
        assert.is_true(rec.score > 0)
        assert.matches("record", W.chat[#W.chat])
    end)

    it("keeps counting in no-hints mode while the block, sounds and bar highlight stay off", function()
        ns.RecapWindow.SetNoHints(true)
        assert.is_true(ns.db.noHints)
        W.actions[2] = { "spell", AGONY }
        ns.ActionBars.dirty = true
        fight(ns, W)
        wait(ns, W, 0.2)
        assert.is_nil(ns.ActionBars.highlighted)
        press(ns, AGONY)
        wait(ns, W, 3)
        local rec = finish(ns, W)
        assert.equal(0, #W.sounds)
        assert.is_true(rec.blind)
        assert.equal(1, rec.matched) -- judged against the hidden hint
        ns.Commands:Run("nohints")
        assert.is_false(ns.db.noHints)
    end)
end)

describe("Combat recap: metrics", function()
    it("turns reaction into speed and a score", function()
        local _ = setup(20)
        local M = _.RecapMetrics
        assert.equal(1, M.Speed(0.2))
        assert.equal(0.75, M.Speed(0.9))
        assert.equal(0.5, M.Speed(2))
        assert.equal(1, M.Speed(nil))
        assert.equal(860, M.Score({ presses = 50, matched = 43, reactSum = 5, reactN = 50 }))
        assert.equal(0, M.Score({ presses = 0, matched = 0 }))
        assert.equal("1:15", M.Clock(75))
        assert.equal("0:00", M.Clock(nil))
        assert.equal("86%", M.Percent(0.857))
        assert.equal("—", M.Percent(nil))
    end)

    it("writes numbers and mistakes in the player's language", function()
        local ns = addon.load({ world = { locale = "ruRU" } })
        local M = ns.RecapMetrics
        assert.equal("2,1", M.Seconds(2.1))
        local text, reason = M.ErrorText({ kind = "miss", pressed = "shadow_bolt", pressedId = 686, hint = "corruption",
                                           hintId = 172, reason = "down" })
        assert.equal("spell686 вместо подсказки «spell172»", text)
        assert.equal("дебаффа не было на цели", reason)
        text, reason = M.ErrorText({ kind = "idle", gap = 2.1, hint = "curse_of_agony", hintId = 980 })
        assert.equal("Простой 2,1 с", text)
        assert.equal("можно было нажать «spell980»", reason)
        assert.equal("рядом 3 врага", select(2, M.ErrorText({ kind = "miss", pressed = "shadow_bolt", hint = "hellfire",
                                                               reason = "aoe", arg = 3 })))
    end)
end)

describe("Combat recap: window", function()
    local ns, W, RW
    before_each(function()
        ns, W = setup(20)
        ns.db.recapMinFight = 3
        RW = ns.RecapWindow
    end)

    it("shows sample data, marked, before the first fight", function()
        local m = RW:Model()
        assert.is_true(m.sample)
        assert.equal(10, #m.list)
        assert.equal("05:41", m.list[1].at)
        assert.equal("86%", m.list[1].accuracy)
        assert.equal("86%", m.detail.cards[1].value)
        assert.equal("12 of 14 presses", m.detail.cards[1].sub)
        assert.equal("92%", m.detail.cards[2].value)
        assert.equal("2.1 s", m.detail.cards[3].value)
        assert.equal("1 pause", m.detail.cards[3].sub)
        assert.equal("—", m.detail.cards[4].value)
        assert.equal(3, #m.detail.errors)
        assert.equal("0:06", m.detail.errors[1].time)
        assert.equal("23 fights, average accuracy 84%, last session 78%", m.session.line)
        assert.equal("+6%", m.session.delta)
    end)

    it("shows recorded fights, the session and records, and draws every tab", function()
        ns.db.training = true
        fight(ns, W)
        wait(ns, W, 0.2)
        press(ns, AGONY)
        wait(ns, W, 1.6)
        press(ns, BOLT)
        wait(ns, W, 3)
        finish(ns, W)
        local m = RW:Model()
        assert.is_false(m.sample)
        assert.equal(1, #m.list)
        assert.equal("50%", m.list[1].accuracy)
        assert.equal("1 of 2 presses", m.detail.cards[1].sub)
        assert.equal("spell1088 instead of the hinted spell6222", m.detail.errors[1].text)
        assert.equal("it was not on the target", m.detail.errors[1].reason)
        assert.equal("1 fight, average accuracy 50%, no earlier session", m.session.line)

        RW:Toggle()
        RW:Draw()
        RW:SetTab("session")
        m = RW:Model()
        assert.equal("1 fight, average accuracy 50%, no earlier session", m.current.line)
        assert.equal(0, #m.past)
        RW:Draw()
        RW:SetTab("records")
        m = RW:Model()
        assert.equal(1, #m.records)
        assert.equal("Generic, Leveling", m.records[1].name)
        RW:Draw()
        RW:SetTab("fights")
        RW.SetTraining(false)
        assert.is_false(ns.db.training)
        ns.Commands:Run("recap")
    end)
end)
