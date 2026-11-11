-- Every text the addon shows must be drawable by the game fonts. The ruRU font has no middle
-- dot (seen in game: "·" drew as a box), arrows or check marks: those are textures instead.
-- Allowed: printable ASCII, Cyrillic, and the few signs seen drawn in game.
local addon = require("helpers.addon")

local EXTRA = { [0x00AB] = true, [0x00BB] = true, [0x2014] = true } -- « » —

-- Code points of s that the game fonts cannot draw (Lua 5.1 has no utf8 library: decoded by hand).
local function badChars(s)
    local bad = {}
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        local cp, len
        if b < 0x80 then cp, len = b, 1
        elseif b >= 0xF0 then cp, len = (b % 0x08) * 0x40000 + (s:byte(i + 1) % 0x40) * 0x1000 + (s:byte(i + 2) % 0x40) * 0x40 + (s:byte(i + 3) % 0x40), 4
        elseif b >= 0xE0 then cp, len = (b % 0x10) * 0x1000 + (s:byte(i + 1) % 0x40) * 0x40 + (s:byte(i + 2) % 0x40), 3
        else cp, len = (b % 0x20) * 0x40 + (s:byte(i + 1) % 0x40), 2 end
        local ok = (cp >= 0x20 and cp <= 0x7E) or cp == 0x0A or cp == 0x09 or (cp >= 0x0400 and cp <= 0x04FF) or EXTRA[cp]
        if not ok then bad[#bad + 1] = string.format("U+%04X", cp) end
        i = i + len
    end
    return bad
end

local function walk(t, path, out)
    for k, v in pairs(t) do
        local p = path .. "." .. tostring(k)
        if type(v) == "string" then
            local bad = badChars(v)
            if #bad > 0 then out[#out + 1] = p .. ": " .. table.concat(bad, " ") end
        elseif type(v) == "table" then
            walk(v, p, out)
        end
    end
end

describe("Glyphs", function()
    it("finds the signs the game fonts lack", function()
        assert.same({ "U+00B7", "U+2192", "U+2713" }, badChars("a · b → c ✓"))
        assert.same({}, badChars("Билды — «Чернокнижник», ёж"))
    end)

    it("every locale string can be drawn by the game fonts", function()
        for _, locale in ipairs({ "enUS", "ruRU" }) do
            local ns = addon.load({ world = { locale = locale } })
            local out = {}
            walk(ns.L, "L", out)
            assert.same({}, out)
        end
    end)

    it("strings written in the code can too", function()
        local out = {}
        for _, path in ipairs(addon.tocFiles()) do
            local n = 0
            for line in io.lines(path) do
                n = n + 1
                if not line:match("^%s*%-%-") then
                    for str in line:gmatch('"(.-)"') do
                        local bad = badChars(str)
                        if #bad > 0 then out[#out + 1] = path .. ":" .. n .. ": " .. table.concat(bad, " ") end
                    end
                end
            end
        end
        assert.same({}, out)
    end)
end)
