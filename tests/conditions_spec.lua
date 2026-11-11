-- Condition language: parsing, precedence, errors.
local addon = require("helpers.addon")

describe("Conditions", function()
    local ns, C
    setup(function()
        ns = addon.load({ login = false })
        C = ns.Conditions
    end)

    -- A tiny variables table: a.b paths read from ctx.
    local vars = {
        x = { arity = 0, get = function(ctx) return ctx.x end },
        flag = { arity = 0, get = function(ctx) return ctx.flag end },
        unit = {
            arity = 1,
            check = function(f) if f ~= "hp" and f ~= "dead" then return "bad field " .. f end end,
            get = function(ctx, f) return ctx.unit[f] end,
        },
        aura = { arity = 2, get = function(ctx, k, f) return ctx.auras[k] and ctx.auras[k][f] end },
    }
    local ctx = { x = 5, flag = true, unit = { hp = 30, dead = false }, auras = { dot = { up = true, remains = 4 } } }

    local function eval(src)
        local fn, err = C.Compile(src, vars)
        assert.is_nil(err)
        return fn(ctx)
    end

    it("follows arithmetic precedence", function()
        assert.equal(7, eval("1 + 2 * 3"))
        assert.equal(9, eval("(1 + 2) * 3"))
        assert.equal(-3, eval("-x + 2"))
        assert.equal(2.5, eval("x / 2"))
        assert.equal(0, eval("x / 0"))
    end)

    it("compares and combines", function()
        assert.is_true(eval("x > 3 & x < 10"))
        assert.is_false(eval("x > 3 & x > 10"))
        assert.is_true(eval("x > 10 | flag"))
        assert.is_true(eval("!unit.dead & unit.hp < 35"))
        assert.is_true(eval("unit.hp = 30"))
        assert.is_true(eval("unit.hp == 30 and not unit.dead"))
        assert.is_true(eval("x != 4"))
        assert.is_true(eval("x ~= 4 && x >= 5 || false"))
    end)

    it("binds & tighter than |", function()
        assert.is_true(eval("true | false & false"))
        assert.is_false(eval("(true | false) & false"))
    end)

    it("applies ! to the comparison that follows", function()
        assert.is_true(eval("!x > 10"))
        assert.is_false(eval("!flag"))
    end)

    it("treats booleans as 1/0 and numbers as truthy", function()
        assert.equal(2, eval("flag + flag"))
        assert.is_true(eval("x & flag"))
        assert.is_false(eval("0 | false"))
    end)

    it("reads two-level paths", function()
        assert.is_true(eval("aura.dot.up & aura.dot.remains > 3"))
        assert.is_falsy(eval("aura.missing.up"))
    end)

    it("compiles an empty condition to true", function()
        assert.is_true(eval(""))
        assert.is_true(eval("   "))
    end)

    it("returns the paths it uses", function()
        local _, _, paths = C.Compile("unit.hp < 35 & x > 1", vars)
        assert.same({ "unit.hp", "x" }, paths)
    end)

    it("reports errors with a position", function()
        local function errorOf(src)
            local fn, err = C.Compile(src, vars)
            assert.is_nil(fn, src)
            return err
        end
        assert.matches("pos 5", errorOf("x > "))
        assert.matches("unknown variable 'nope'", errorOf("nope > 1"))
        assert.matches("needs 1 part", errorOf("unit > 1"))
        assert.matches("bad field mana", errorOf("unit.mana > 1"))
        assert.matches("missing '%)'", errorOf("(x > 1"))
        assert.matches("unexpected '#'", errorOf("x # 1"))
        assert.matches("unexpected '1'", errorOf("x > 1 1"))
        assert.matches("bad name", errorOf("unit..hp"))
    end)

    it("compiles every example of the spec against the real variables", function()
        local examples = {
            "debuff.corruption.down & target.ttd > 8",
            "player.hp_pct < 35 & item.healthstone.ready",
            "talent.nightfall & buff.shadow_trance.up",
            "enemies >= 3",
            "player.mana_pct < player.hp_pct - 20",
            "pet.hp_pct < 40",
        }
        for _, src in ipairs(examples) do
            local fn, err = C.Compile(src, ns.Engine.vars)
            assert.is_nil(err, src)
            assert.is_function(fn)
        end
    end)
end)
