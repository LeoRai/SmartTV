-- Hint engine.
-- Walks the profile top to bottom and picks the first action that is available and whose
-- condition holds. Then "plays" that action in a virtual copy of the state (global cooldown,
-- cast time, debuff timers, cooldowns, consumed procs) and picks the next 3 the same way.
--
-- Available = known (highest rank), off cooldown (or ready by the end of the global cooldown),
-- usable according to the client (mana, requirements), a hostile target for damage spells,
-- the right demon for demon abilities, a wand for Shoot. Out of range is allowed only when
-- nothing in range fits (the icon is tinted red then).
--
-- Forecast: the main icon plus up to 3 next ones (settings: next icons 0..3).
-- Rows: every profile has main (the big icon and the next ones), defense (left slot) and
-- cooldown (right slot) lists, plus prep (the out-of-combat preparation line).
local ADDON, ns = ...
local Data, Conditions = ns.Data, ns.Conditions
local truthy = Conditions.truthy

local Engine = {}
ns.Engine = Engine

local EPS = 0.01

---------------------------------------------------------------------------
-- Variables of the condition language (docs/PROFILES.md)
---------------------------------------------------------------------------

local checkDef -- class definition used to validate keys while compiling

local function fieldCheck(fields, what)
    return function(a)
        if not fields[a] then return string.format("unknown %s field '%s'", what, tostring(a)) end
    end
end

local function keyCheck(section, what, fields)
    return function(a, b)
        if checkDef then
            local list = checkDef[section]
            if not list or not list[a] then return string.format("unknown %s '%s'", what, tostring(a)) end
            if section == "spells" and what == "debuff" and not list[a].duration then
                return string.format("'%s' leaves no debuff (no duration in the spell data)", a)
            end
        end
        if fields and not fields[b] then return string.format("unknown %s field '%s'", what, tostring(b)) end
    end
end

local function set(...)
    local t = {}
    for i = 1, select("#", ...) do t[select(i, ...)] = true end
    return t
end

local PLAYER = set("level", "hp_pct", "mana_pct", "mana", "moving", "casting", "oom", "in_combat", "dead")
local TARGET = set("exists", "enemy", "hp_pct", "ttd", "boss", "elite", "player", "in_range")
local AURA = set("up", "down", "remains", "refreshable", "stack")
local COOLDOWN = set("ready", "remains")
local ITEM = set("count", "ready")
local GCD = set("remains", "duration")
local MODES = set("leveling", "group", "pvp")
local OPTS = set("hp", "pet_hp", "shards")

local function auraRemains(ctx, overlay, base, key)
    local exp = overlay[key]
    if exp == nil then exp = base[key] end
    if not exp then return 0 end
    local rem = exp - ctx.t
    if rem < 0 then return 0 end
    return rem
end

local function debuffRemains(ctx, key) return auraRemains(ctx, ctx.debuffs, ctx.s.debuffs, key) end
local function buffRemains(ctx, key) return auraRemains(ctx, ctx.buffs, ctx.s.buffs, key) end

local function cooldownRemains(ctx, key)
    local ready = ctx.cds[key] or ctx.s.cds[key]
    if not ready then return 0 end
    local rem = ready - ctx.t
    if rem < 0 then return 0 end
    return rem
end

local function auraField(rem, f, refreshWindow)
    if f == "up" then return rem > 0 end
    if f == "down" then return rem <= 0 end
    if f == "remains" then return rem end
    if f == "refreshable" then return rem <= refreshWindow end
    if f == "stack" then return rem > 0 and 1 or 0 end
end

Engine.vars = {
    player = { arity = 1, check = fieldCheck(PLAYER, "player"), get = function(ctx, f) return ctx.s.player[f] end },
    target = {
        arity = 1, check = fieldCheck(TARGET, "target"),
        get = function(ctx, f)
            local t = ctx.s.target
            if f == "ttd" then
                local v = t.ttd - (ctx.t - ctx.s.now)
                return v > 0 and v or 0
            end
            return t[f]
        end,
    },
    pet = {
        arity = 1,
        check = function(a)
            if a == "exists" or a == "hp_pct" then return nil end
            if checkDef and not (checkDef.pets and checkDef.pets[a]) then
                return string.format("unknown pet field '%s' (exists, hp_pct or a demon name)", tostring(a))
            end
        end,
        get = function(ctx, f)
            local pet = ctx.s.pet
            if f == "exists" then return pet.exists end
            if f == "hp_pct" then return pet.hp_pct end
            return pet.exists and pet.family == f
        end,
    },
    debuff = {
        arity = 2, check = keyCheck("spells", "debuff", AURA),
        get = function(ctx, key, f)
            return auraField(debuffRemains(ctx, key), f, (ctx.s.castTime[key] or 0) + 0.5)
        end,
    },
    buff = {
        arity = 2, check = keyCheck("buffs", "buff", AURA),
        get = function(ctx, key, f) return auraField(buffRemains(ctx, key), f, 0.5) end,
    },
    cooldown = {
        arity = 2, check = keyCheck("spells", "spell", COOLDOWN),
        get = function(ctx, key, f)
            local rem = cooldownRemains(ctx, key)
            if f == "ready" then return rem <= 0 end
            return rem
        end,
    },
    known = { arity = 1, check = keyCheck("spells", "spell"), get = function(ctx, key) return ctx.s.known[key] ~= nil end },
    talent = { arity = 1, check = keyCheck("talents", "talent"), get = function(ctx, key) return ctx.s.talents[key] or 0 end },
    item = {
        arity = 2, check = keyCheck("items", "item", ITEM),
        get = function(ctx, key, f)
            local it = ctx.s.items[key]
            if f == "count" then return it and it.count or 0 end
            return it ~= nil and it.count > 0 and it.readyAt <= ctx.t + EPS
        end,
    },
    last = {
        arity = 1, check = keyCheck("spells", "spell"),
        get = function(ctx, key)
            local at = ctx.last[key] or ctx.s.last[key]
            return at and (ctx.t - at) or 999
        end,
    },
    gcd = {
        arity = 1, check = fieldCheck(GCD, "gcd"),
        get = function(ctx, f)
            if f == "duration" then return ctx.s.gcd end
            local rem = ctx.s.gcdEnd - ctx.t
            return rem > 0 and rem or 0
        end,
    },
    mode = { arity = 1, check = fieldCheck(MODES, "mode"), get = function(ctx, m) return ctx.s.mode == m end },
    opt = { arity = 1, check = fieldCheck(OPTS, "opt"), get = function(ctx, k) return ctx.s.opt[k] or 0 end },
    combat = { arity = 0, get = function(ctx) return ctx.s.player.in_combat end },
    enemies = { arity = 0, get = function(ctx) return ctx.s.enemies end },
    soul_shards = { arity = 0, get = function(ctx) return ctx.s.shards end },
    trainer = { arity = 0, get = function(ctx) return ctx.s.trainer end },
}

---------------------------------------------------------------------------
-- Profile preparation (compile once per profile)
---------------------------------------------------------------------------

local ROWS = { "main", "defense", "cooldown" }

local function compileLine(def, row, i, entry, errors)
    local action, src = entry[1], entry[2] or ""
    local line = { action = action, src = src, why = entry.why, glow = entry.glow, row = row }
    if def.spells[action] then
        line.kind, line.spell = "spell", def.spells[action]
    elseif def.items and def.items[action] then
        line.kind, line.item = "item", def.items[action]
    else
        errors[#errors + 1] = string.format("%s #%d: unknown action '%s'", row, i, tostring(action))
        return nil
    end
    local fn, err, paths = Conditions.Compile(src, Engine.vars)
    if not fn then
        errors[#errors + 1] = string.format("%s #%d (%s): %s", row, i, action, err)
        return nil
    end
    line.fn, line.paths = fn, paths
    line.pathFns = {}
    for _, path in ipairs(paths or {}) do
        line.pathFns[path] = Conditions.Compile(path, Engine.vars)
    end
    return line
end

-- Returns a prepared profile: { profile, main = {...}, defense = {...}, cooldown = {...},
-- prep = {...}, errors = { "..." } }. Lines with errors are left out (and listed in errors).
function Engine.Prepare(profile, def)
    checkDef = def
    local prepared = { profile = profile, id = profile.id, errors = {} }
    for _, row in ipairs(ROWS) do
        local lines = {}
        for i, entry in ipairs(profile[row] or {}) do
            local line = compileLine(def, row, i, entry, prepared.errors)
            if line then lines[#lines + 1] = line end
        end
        prepared[row] = lines
    end
    prepared.prep = {}
    for i, entry in ipairs(profile.prep or {}) do
        local fn, err = Conditions.Compile(entry[1], Engine.vars)
        local valueFn, verr
        if entry.value then valueFn, verr = Conditions.Compile(entry.value, Engine.vars) end
        if fn and (valueFn or not entry.value) then
            prepared.prep[#prepared.prep + 1] = { fn = fn, text = entry.text, value = valueFn, src = entry[1], place = entry.place }
        else
            prepared.errors[#prepared.errors + 1] = string.format("prep #%d: %s", i, err or verr)
        end
    end
    checkDef = nil
    return prepared
end

---------------------------------------------------------------------------
-- Virtual state
---------------------------------------------------------------------------

local function newContext()
    return { s = nil, t = 0, debuffs = {}, buffs = {}, cds = {}, last = {} }
end

local function resetContext(ctx, s)
    ctx.s, ctx.t = s, s.now
    ns.wipe(ctx.debuffs); ns.wipe(ctx.buffs); ns.wipe(ctx.cds); ns.wipe(ctx.last)
    return ctx
end

local function castTimeAt(ctx, key, sp)
    if sp.consumes and buffRemains(ctx, sp.consumes) > 0 then return 0 end
    return ctx.s.castTime[key] or Data.Cast(sp, ctx.s.knownRank[key])
end

-- Effects of casting key that started at ctx.t and lands at `landing`.
local function applyEffects(ctx, key, sp, landing)
    local s = ctx.s
    if sp.consumes and buffRemains(ctx, sp.consumes) > 0 then ctx.buffs[sp.consumes] = false end
    ctx.last[key] = ctx.t
    if sp.duration and sp.harmful then
        ctx.debuffs[key] = landing + (Data.Duration(sp, s.knownRank[key]) or 0)
    end
    if sp.cooldown then ctx.cds[key] = landing + sp.cooldown end
    if sp.buff and s.def.buffs and s.def.buffs[sp.buff] then
        ctx.buffs[sp.buff] = landing + (s.def.buffs[sp.buff].duration or 0)
    end
end

-- Play one action: effects, then advance virtual time by the cast or the global cooldown.
local function simulate(ctx, line)
    if line.kind ~= "spell" then return end
    local sp = line.spell
    local cast = castTimeAt(ctx, line.action, sp)
    applyEffects(ctx, line.action, sp, ctx.t + cast)
    local busy = cast
    if sp.gcd ~= false and busy < ctx.s.gcd then busy = ctx.s.gcd end
    ctx.t = ctx.t + busy
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

-- Returns available, outOfRange.
local function available(ctx, line, realTime)
    local s = ctx.s
    if line.kind == "item" then
        local it = s.items[line.action]
        return it ~= nil and it.count > 0 and it.readyAt <= ctx.t + EPS, false
    end
    local key, sp = line.action, line.spell
    if not s.known[key] then return false end
    if sp.harmful and not (s.target.exists and s.target.enemy) then return false end
    if sp.pet then
        if not s.pet.exists then return false end
        if sp.petFamily and s.pet.family ~= sp.petFamily then return false end
    end
    if sp.wand and not s.hasWand then return false end
    if sp.requires and debuffRemains(ctx, sp.requires) <= 0 then return false end
    if cooldownRemains(ctx, key) > EPS then return false end
    -- A channel already planned in this forecast is not planned twice in a row.
    if not realTime and sp.channel and ctx.last[key] then return false end
    if realTime then
        if s.usable[key] == false then return false end
        if sp.harmful and s.inRange and s.inRange[key] == false then return true, true end
    end
    return true, false
end

local function pick(ctx, lines, realTime, allowOutOfRange)
    for i = 1, #lines do
        local line = lines[i]
        local ok, outOfRange = available(ctx, line, realTime)
        if ok and (allowOutOfRange or not outOfRange) and truthy(line.fn(ctx)) then
            return line, outOfRange
        end
    end
    return nil
end

local function fill(rec, ctx, line, outOfRange)
    local s = ctx.s
    rec.line, rec.action, rec.kind = line, line.action, line.kind
    if line.kind == "item" then
        rec.id = s.items[line.action] and s.items[line.action].id
    else
        rec.id = s.known[line.action]
    end
    rec.wait = ctx.t - s.now
    if rec.wait < 0 then rec.wait = 0 end
    rec.at = ctx.t
    rec.outOfRange = outOfRange or false
    rec.noMana = line.kind == "spell" and s.noMana[line.action] == true or false
    rec.glow = line.glow or false
    return rec
end

local function pickRow(ctx, lines)
    local line, outOfRange = pick(ctx, lines, true, false)
    if not line then line, outOfRange = pick(ctx, lines, true, true) end
    return line, outOfRange
end

-- Compute the hints for snapshot s with a prepared profile.
-- depth: how many main icons (1 + next icons). The result table is reused between calls.
function Engine:Recommend(s, prepared, depth)
    self.ctx = self.ctx or newContext()
    self.result = self.result or { main = {}, recs = {}, defense = {}, cooldown = {} }
    local ctx, r = resetContext(self.ctx, s), self.result
    r.mainCount, r.hasDefense, r.hasCooldown, r.prep, r.prepValue, r.prepPlace, r.aoe = 0, false, false, nil, nil, nil, false
    ns.wipe(r.main)
    r.prepared = prepared
    if not prepared then return r end

    -- The cast in progress lands first; nothing else can start before the global cooldown ends.
    if s.castKey then
        local sp = s.def.spells[s.castKey]
        applyEffects(ctx, s.castKey, sp, s.castEnd)
        if s.castEnd > ctx.t then ctx.t = s.castEnd end
    end
    if s.gcdEnd > ctx.t then ctx.t = s.gcdEnd end

    -- Side slots are judged on the real state, before any simulated step.
    local line, oor = pickRow(ctx, prepared.defense)
    if line then r.hasDefense = true; fill(r.defense, ctx, line, oor) end
    line, oor = pickRow(ctx, prepared.cooldown)
    if line then r.hasCooldown = true; fill(r.cooldown, ctx, line, oor) end

    depth = depth or 2
    for i = 1, depth do
        if i == 1 then
            line, oor = pickRow(ctx, prepared.main)
        else
            line, oor = pick(ctx, prepared.main, false, true)
        end
        if not line then break end
        r.recs[i] = r.recs[i] or {}
        r.main[i] = fill(r.recs[i], ctx, line, oor)
        r.mainCount = i
        if i < depth then simulate(ctx, line) end
    end

    r.aoe = prepared.profile.aoe and s.enemies >= 3 or false

    if not s.player.in_combat then
        resetContext(ctx, s)
        for _, p in ipairs(prepared.prep) do
            if truthy(p.fn(ctx)) then
                r.prep = p.text
                r.prepValue = p.value and p.value(ctx) or nil
                r.prepPlace = p.place
                break
            end
        end
    end
    return r
end

-- Text for /fc debug: the chosen action and the values its condition saw.
function Engine.Explain(rec, s)
    local line = rec.line
    local ctx = resetContext(newContext(), s)
    ctx.t = rec.at or s.now
    local parts = {}
    for _, path in ipairs(line.paths or {}) do
        local fn = line.pathFns[path]
        local v = fn and fn(ctx)
        if type(v) == "number" then v = string.format("%.1f", v) end
        local text = path .. "=" .. tostring(v)
        local head = path:match("^[^%.]+")
        if s.hidden[path] or (head == "debuff" and s.hidden.debuffs) or (head == "buff" and s.hidden.buffs)
            or (head == "cooldown" and s.hidden.cooldowns) then
            text = text .. "*"
        end
        parts[#parts + 1] = text
    end
    return line.row .. ": " .. line.action .. (line.src ~= "" and (" [" .. line.src .. "] " .. table.concat(parts, ", ")) or "")
end
