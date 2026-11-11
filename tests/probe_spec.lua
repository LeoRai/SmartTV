-- Stage 0 probe: runs, classifies secrets and builds its report without errors.
local wow = require("helpers.wow")

local function fire(W, event, ...)
    for _, f in ipairs(W.frames) do
        local handler = f:GetScript("OnEvent")
        if handler then handler(f, event, ...) end
    end
end

describe("Probe", function()
    local W

    before_each(function()
        W = wow.newWorld()
        wow.install(W)
        ForeverCoachProbeDB = nil
        assert(loadfile("ForeverCoach_Probe/Probe.lua"))("ForeverCoach_Probe")
        fire(W, "ADDON_LOADED", "ForeverCoach_Probe")
        fire(W, "PLAYER_LOGIN")
    end)

    it("records readable values out of combat", function()
        W.target = { hp = 50, hpMax = 100, enemy = true }
        SlashCmdList.FCPROBE("snap")
        local checks = ForeverCoachProbeDB.contexts["world/idle"].checks
        assert.is_truthy(checks["target.health"].ok)
        assert.is_truthy(checks["player.mana"].ok)
        assert.equal("present", ForeverCoachProbeDB.api["C_Spell.GetSpellCooldown"])
        assert.equal("missing", ForeverCoachProbeDB.api["GetSpellInfo"])
    end)

    it("records secrets in combat, per situation", function()
        W.player.combat = true
        W.instance = "party"
        W.target = { hp = 50, hpMax = 100, enemy = true }
        W.auras.target = { { spellId = 172, expirationTime = W.time + 10 } }
        W.secret = { ["target.hp"] = true, auras = true }
        SlashCmdList.FCPROBE("snap")
        local checks = ForeverCoachProbeDB.contexts["dungeon/combat"].checks
        assert.is_truthy(checks["target.health"].secret)
        assert.is_truthy(checks["aura.target.mine.spellId"].secret)
        assert.is_truthy(checks["player.health"].ok)
    end)

    it("records event payloads and builds the report", function()
        fire(W, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 686)
        fire(W, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast", wow.secret())
        local e = ForeverCoachProbeDB.contexts["world/idle"].events.UNIT_SPELLCAST_SUCCEEDED
        assert.equal(2, e.fired)
        assert.equal(1, e.secret)
        SlashCmdList.FCPROBE("dump")
        SlashCmdList.FCPROBE("report")
        SlashCmdList.FCPROBE("")
        SlashCmdList.FCPROBE("reset")
        assert.same({}, ForeverCoachProbeDB.contexts)
    end)
end)
