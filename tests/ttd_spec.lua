-- Time to die.
local addon = require("helpers.addon")

describe("TTD", function()
    local TTD
    before_each(function()
        local ns = addon.load({ login = false })
        TTD = ns.TTD
        TTD:Reset(nil)
    end)

    it("needs a few samples over more than 1.5 s", function()
        TTD:Add("a", 0, 100)
        TTD:Add("a", 0.5, 95)
        assert.is_nil(TTD:Get(0.5))
        TTD:Add("a", 1.0, 90)
        assert.is_nil(TTD:Get(1.0)) -- 3 samples, but only 1 s of history
        TTD:Add("a", 2.0, 80)
        assert.is_number(TTD:Get(2.0))
    end)

    it("extrapolates a linear drop", function()
        for i = 0, 5 do TTD:Add("a", i, 100 - 10 * i) end -- 10% per second, at 50% now
        assert.is_true(math.abs(TTD:Get(5) - 5) < 0.01)
        assert.is_true(math.abs(TTD:Get(6) - 4) < 0.01) -- a second later, a second less
    end)

    it("returns nil when health does not fall", function()
        for i = 0, 5 do TTD:Add("a", i, 70) end
        assert.is_nil(TTD:Get(5))
    end)

    it("starts over on another target or after a heal", function()
        for i = 0, 5 do TTD:Add("a", i, 100 - 10 * i) end
        TTD:Add("b", 6, 100)
        assert.equal(1, TTD.size)
        for i = 0, 5 do TTD:Add("b", 10 + i, 80 - 5 * i) end
        TTD:Add("b", 16, 90) -- healed
        assert.equal(1, TTD.size)
    end)

    it("forgets samples older than the window", function()
        for i = 0, 30 do TTD:Add("a", i, 100 - i) end
        assert.is_true(TTD.size <= TTD.window + 1)
    end)
end)
