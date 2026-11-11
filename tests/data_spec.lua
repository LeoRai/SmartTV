-- Data files: profiles compile, keys exist, texts are translated.
local validator = assert(loadfile("tools/validate_profiles.lua"))("--library")

local function assignedKeys(path)
    local keys = {}
    for line in io.lines(path) do
        local key = line:match("^L%.([%w_]+)%s*=")
        if key then keys[key] = true end
    end
    return keys
end

describe("Data", function()
    it("passes the profile validator", function()
        local problems, count = validator.run()
        assert.is_true(count >= 2)
        assert.same({}, problems)
    end)

    it("has a Russian text for every English one", function()
        local en = assignedKeys("ForeverCoach/Locales/enUS.lua")
        local ru = assignedKeys("ForeverCoach/Locales/ruRU.lua")
        -- Deliberately the same in both languages.
        local same = { ADDON = true, BINDING_HEADER = true, AOE = true, DEBUG_PICK = true }
        local missing = {}
        for key in pairs(en) do
            if not ru[key] and not same[key] then missing[#missing + 1] = key end
        end
        for key in pairs(ru) do
            assert.is_true(en[key] ~= nil, "ruRU has an extra key " .. key)
        end
        table.sort(missing)
        assert.same({}, missing)
    end)

    it("loads only the player's class", function()
        local addon = require("helpers.addon")
        local ns = addon.load({ world = { class = "MAGE" } })
        assert.is_nil(ns.Data.class)
        assert.is_nil(next(ns.Data.profiles))
        assert.is_nil(next(ns.Data.classes))
    end)

    it("loads Russian strings in the Russian client", function()
        local addon = require("helpers.addon")
        local ns = addon.load({ world = { locale = "ruRU" }, login = false })
        assert.equal("Демон не призван", ns.L.PREP_NO_PET)
        assert.equal("ForeverCoach", ns.L.ADDON)
    end)
end)
