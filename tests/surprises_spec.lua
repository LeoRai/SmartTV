-- Surprise journal: a main hint the queue did not show in time is noted with its reason.
local addon = require("helpers.addon")

-- Immolate, Corruption and Curse of Agony of a level 20 warlock.
local IMMOLATE, CORRUPTION, AGONY = 1094, 6222, 1014

local function dots(W, immolateLeft)
    W.auras.target = {
        { spellId = CORRUPTION, expirationTime = W.time + 30 },
        { spellId = AGONY, expirationTime = W.time + 30 },
    }
    if immolateLeft then
        table.insert(W.auras.target, { spellId = IMMOLATE, expirationTime = W.time + immolateLeft })
    end
end

describe("Surprise journal", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 20)
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "mob-1" }
        W.player.combat = true
    end)

    local function tick(dt)
        W.time = W.time + (dt or 0.1)
        ns.Loop:Update()
    end

    it("notes a main hint that was not in the queue", function()
        dots(W, 30)
        tick()
        assert.same({ "shadow_bolt", "shadow_bolt", "shadow_bolt", "shadow_bolt" }, addon.mainActions(addon.compute(ns, W)))
        dots(W, nil) -- Immolate is gone early (dispelled)
        tick()
        local list = ns.Surprises.List()
        assert.equal(1, #list)
        local n = list[1]
        assert.equal("immolate", n.to)
        assert.equal("shadow_bolt>shadow_bolt>shadow_bolt>shadow_bolt", n.from)
        assert.equal(0, n.age)
        assert.matches("immolate", n.why)
        assert.equal(1, n.enemies)
        assert.equal(20, n.level)
        assert.equal("Warlock_Generic_Leveling", n.profile)
    end)

    it("stays quiet when the queue showed the action first", function()
        dots(W, 4) -- the test client casts instantly: one step is the global cooldown
        tick()
        tick()
        assert.same({ "shadow_bolt", "shadow_bolt", "shadow_bolt", "immolate" }, addon.mainActions(addon.compute(ns, W)))
        -- Immolate runs low and becomes the main hint: it was on screen for a while.
        for _ = 1, 40 do
            tick()
            if addon.compute(ns, W).main[1].action == "immolate" then break end
        end
        assert.equal("immolate", addon.compute(ns, W).main[1].action)
        assert.equal(0, #ns.Surprises.List())
    end)

    it("does not count a new target or the start of a fight", function()
        tick() -- the block has just appeared: its queue is the starting point
        dots(W, 30)
        W.auras.target[3] = { spellId = IMMOLATE, expirationTime = W.time + 30 } -- Agony and Corruption were in it
        tick()
        W.target = { hp = 100, hpMax = 100, enemy = true, guid = "mob-2" }
        W.auras.target = {}
        tick()
        assert.equal(0, #ns.Surprises.List())
    end)

    it("forgets the queue out of combat and keeps the last 30 notes", function()
        for _ = 1, 35 do
            dots(W, 30)
            tick()
            dots(W, nil)
            tick()
        end
        assert.equal(ns.Surprises.KEEP, #ns.Surprises.List())
        W.player.combat = false
        tick()
        assert.is_nil(ns.Surprises.fightStart)
        assert.equal(0, ns.Surprises.queueN)
    end)

    it("prints the notes, clears them and keeps them through /fc reset", function()
        dots(W, 30)
        tick()
        dots(W, nil)
        tick()
        ns.db.builds = { { code = "x" } }
        ns.Commands:Run("reset")
        assert.equal(1, #ns.Surprises.List())
        assert.equal("x", ns.db.builds[1].code)
        assert.equal(3, ns.db.nextIcons)
        local before = #W.chat
        ns.Commands:Run("surprises")
        assert.equal(before + 2, #W.chat)
        assert.matches("immolate", W.chat[#W.chat])
        ns.Commands:Run("surprises", "clear")
        assert.equal(0, #ns.Surprises.List())
    end)

    it("prints each surprise at once in debug mode", function()
        ns.db.debug = true
        dots(W, 30)
        tick()
        local before = #W.chat
        dots(W, nil)
        tick()
        local found = false
        for i = before + 1, #W.chat do
            if W.chat[i]:find("suddenly", 1, true) then found = true end
        end
        assert.is_true(found)
    end)
end)
