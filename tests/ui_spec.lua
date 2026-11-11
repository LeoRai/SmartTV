-- The interface code runs on frame stubs: no Lua errors in any display state.
local addon = require("helpers.addon")

describe("UI", function()
    local ns, W
    before_each(function()
        ns, W = addon.load()
        addon.learnUpTo(ns, W, 20)
    end)

    local function render()
        local r, s = addon.compute(ns, W)
        ns.HUD:Render(r, s, W.time)
        return r, s
    end

    it("draws the hint block in combat, out of combat and unlocked", function()
        W.player.combat = true
        W.target = { hp = 100, hpMax = 100, enemy = true }
        W.player.hp = 20
        W.items[5512] = 1
        addon.rescan(ns)
        ns.db.nextIcons = 2
        local r = render()
        assert.is_true(r.hasDefense)

        W.player.combat = false
        W.target = nil
        render()

        ns.db.locked = false
        ns.HUD:ApplySettings()
        render()

        ns.db.shown = false
        ns.db.locked = true
        render()
    end)

    it("opens the settings window and the minimap button", function()
        ns.Settings:Toggle()
        ns.Settings.frame:GetScript("OnShow")(ns.Settings.frame)
        ns.MinimapButton:Apply()
        ForeverCoach_OnAddonCompartmentClick("ForeverCoach", "RightButton")
        assert.is_false(ns.db.shown)
        ForeverCoach_Binding("builds")
        ForeverCoach_Binding("recap")
    end)
end)
