-- Condition language of the rotation profiles.
--
--   debuff.corruption.down & target.ttd > 8
--   player.hp_pct < 35 & item.healthstone.ready
--   talent.nightfall & buff.shadow_trance.up
--   enemies >= 3
--   player.mana_pct < player.hp_pct - 20
--   pet.hp_pct < 40
--
-- Grammar (lowest to highest precedence):
--   or   := and  { "|" and }                    also "||", "or"
--   and  := not  { "&" not }                    also "&&", "and"
--   not  := "!" not | cmp                       also "not"
--   cmp  := sum [ ("<" | "<=" | ">" | ">=" | "=" | "==" | "!=" | "~=") sum ]
--   sum  := prod { ("+" | "-") prod }
--   prod := unary { ("*" | "/") unary }
--   unary:= "-" unary | atom
--   atom := number | true | false | path | "(" or ")"
--   path := name { "." name }                   resolved through a variables table
--
-- Booleans count as 1 / 0 in arithmetic; numbers are true when not 0.
-- Strings compile once into Lua closures: no load(), no parsing while playing.
local ADDON, ns = ...

local Conditions = {}
ns.Conditions = Conditions

local function truthy(v)
    return v == true or (type(v) == "number" and v ~= 0)
end
local function num(v)
    if type(v) == "number" then return v end
    if v == true then return 1 end
    return 0
end
Conditions.truthy, Conditions.num = truthy, num

local KEYWORDS = { ["and"] = "&", ["or"] = "|", ["not"] = "!" }
local TWO = { ["<="] = true, [">="] = true, ["=="] = true, ["!="] = true, ["~="] = true, ["&&"] = "&", ["||"] = "|" }
local ONE = { ["<"] = true, [">"] = true, ["="] = true, ["!"] = true, ["&"] = true, ["|"] = true,
              ["("] = true, [")"] = true, ["+"] = true, ["-"] = true, ["*"] = true, ["/"] = true }

-- Tokens: { kind = "num" | "path" | "bool" | "op", value, pos }
local function tokenize(src)
    local tokens, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
            local text = src:match("^%d*%.?%d+", i)
            tokens[#tokens + 1] = { kind = "num", value = tonumber(text), pos = i }
            i = i + #text
        elseif c:match("[%a_]") then
            local text = src:match("^[%a_][%w_%.]*", i)
            if text:sub(-1) == "." or text:find("%.%.") or text:find("%.%d") then
                return nil, string.format("pos %d: bad name '%s'", i, text)
            end
            local lower = text:lower()
            if KEYWORDS[lower] then
                tokens[#tokens + 1] = { kind = "op", value = KEYWORDS[lower], pos = i }
            elseif lower == "true" or lower == "false" then
                tokens[#tokens + 1] = { kind = "bool", value = lower == "true", pos = i }
            else
                tokens[#tokens + 1] = { kind = "path", value = text, pos = i }
            end
            i = i + #text
        else
            local two = src:sub(i, i + 1)
            if TWO[two] then
                tokens[#tokens + 1] = { kind = "op", value = TWO[two] == true and two or TWO[two], pos = i }
                i = i + 2
            elseif ONE[c] then
                tokens[#tokens + 1] = { kind = "op", value = c, pos = i }
                i = i + 1
            else
                return nil, string.format("pos %d: unexpected '%s'", i, c)
            end
        end
    end
    return tokens
end
Conditions.Tokenize = tokenize

-- Parser state is local to one Compile call.
local function compile(src, vars)
    local tokens, err = tokenize(src)
    if not tokens then return nil, err end
    local pos = 1
    local paths = {}

    local function peek() return tokens[pos] end
    local function isOp(value)
        local t = tokens[pos]
        return t and t.kind == "op" and t.value == value
    end
    local function fail(msg, t)
        t = t or tokens[pos]
        error({ msg = string.format("pos %d: %s", t and t.pos or #src + 1, msg) }, 0)
    end

    local parseOr

    local function parsePath(t)
        local parts = {}
        for part in t.value:gmatch("[^%.]+") do parts[#parts + 1] = part end
        local head = parts[1]
        local var = vars[head]
        if not var then fail("unknown variable '" .. head .. "'", t) end
        local arity = var.arity or 0
        if #parts - 1 ~= arity then
            fail(string.format("'%s' needs %d part(s) after '%s'", t.value, arity, head), t)
        end
        local a, b = parts[2], parts[3]
        if var.check then
            local problem = var.check(a, b)
            if problem then fail(problem, t) end
        end
        paths[#paths + 1] = t.value
        local get = var.get
        if arity == 0 then return function(ctx) return get(ctx) end end
        if arity == 1 then return function(ctx) return get(ctx, a) end end
        return function(ctx) return get(ctx, a, b) end
    end

    local function parseAtom()
        local t = peek()
        if not t then fail("unexpected end") end
        pos = pos + 1
        if t.kind == "num" or t.kind == "bool" then
            local v = t.value
            return function() return v end
        elseif t.kind == "path" then
            return parsePath(t)
        elseif t.value == "(" then
            local inner = parseOr()
            if not isOp(")") then fail("missing ')'") end
            pos = pos + 1
            return inner
        end
        fail("unexpected '" .. tostring(t.value) .. "'", t)
    end

    local function parseUnary()
        if isOp("-") then
            pos = pos + 1
            local f = parseUnary()
            return function(ctx) return -num(f(ctx)) end
        end
        return parseAtom()
    end

    local function parseProd()
        local left = parseUnary()
        while isOp("*") or isOp("/") do
            local op = peek().value
            pos = pos + 1
            local l, r = left, parseUnary()
            if op == "*" then
                left = function(ctx) return num(l(ctx)) * num(r(ctx)) end
            else
                left = function(ctx)
                    local d = num(r(ctx))
                    if d == 0 then return 0 end
                    return num(l(ctx)) / d
                end
            end
        end
        return left
    end

    local function parseSum()
        local left = parseProd()
        while isOp("+") or isOp("-") do
            local op = peek().value
            pos = pos + 1
            local l, r = left, parseProd()
            if op == "+" then
                left = function(ctx) return num(l(ctx)) + num(r(ctx)) end
            else
                left = function(ctx) return num(l(ctx)) - num(r(ctx)) end
            end
        end
        return left
    end

    local CMP = {
        ["<"] = function(a, b) return a < b end,
        ["<="] = function(a, b) return a <= b end,
        [">"] = function(a, b) return a > b end,
        [">="] = function(a, b) return a >= b end,
        ["="] = function(a, b) return a == b end,
        ["=="] = function(a, b) return a == b end,
        ["!="] = function(a, b) return a ~= b end,
        ["~="] = function(a, b) return a ~= b end,
    }

    local function parseCmp()
        local left = parseSum()
        local t = peek()
        if t and t.kind == "op" and CMP[t.value] then
            pos = pos + 1
            local cmp, l, r = CMP[t.value], left, parseSum()
            return function(ctx) return cmp(num(l(ctx)), num(r(ctx))) end
        end
        return left
    end

    local function parseNot()
        if isOp("!") then
            pos = pos + 1
            local f = parseNot()
            return function(ctx) return not truthy(f(ctx)) end
        end
        return parseCmp()
    end

    local function parseAnd()
        local left = parseNot()
        while isOp("&") do
            pos = pos + 1
            local l, r = left, parseNot()
            left = function(ctx) return truthy(l(ctx)) and truthy(r(ctx)) end
        end
        return left
    end

    parseOr = function()
        local left = parseAnd()
        while isOp("|") do
            pos = pos + 1
            local l, r = left, parseAnd()
            left = function(ctx) return truthy(l(ctx)) or truthy(r(ctx)) end
        end
        return left
    end

    local ok, result = pcall(function()
        if #tokens == 0 then return function() return true end end
        local fn = parseOr()
        if pos <= #tokens then fail("unexpected '" .. tostring(tokens[pos].value) .. "'") end
        return fn
    end)
    if not ok then
        if type(result) == "table" then return nil, result.msg end
        return nil, tostring(result)
    end
    return result, nil, paths
end

-- Compile a condition string with a variables table:
--   vars[name] = { arity = 0|1|2, get = function(ctx, a, b) ... end, check = function(a, b) -> error|nil }
-- Returns fn(ctx) -> value, or nil + error message. Third value: the list of paths used.
-- An empty string compiles to "always true".
function Conditions.Compile(src, vars)
    return compile(src or "", vars)
end

-- Evaluate a compiled condition to a boolean.
function Conditions.Test(fn, ctx)
    return truthy(fn(ctx))
end
