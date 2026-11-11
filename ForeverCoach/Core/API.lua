-- Client API layer.
-- WoW Forever runs on the modern client with Midnight's addon restrictions: some values come back
-- as "secret" in combat (visible on widgets, but Lua can't compare or count with them).
-- Every getter here returns a plain Lua value or nil. nil means "unknown or hidden"; the caller
-- picks a fallback (Core/State.lua) and the reason shows up in /fc debug.
-- Modern C_* functions are tried first, legacy globals second, so the addon survives either way.
local ADDON, ns = ...

local API = {}
ns.API = API

---------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------

-- True if v is a secret value (Midnight API). Always false on clients without secrets.
function API.IsSecret(v)
    local check = issecretvalue
    return check ~= nil and check(v) == true
end

-- v if it can be used in Lua arithmetic and comparisons, nil otherwise.
local function clean(v)
    local check = issecretvalue
    if check and check(v) then return nil end
    return v
end
API.Clean = clean

-- Read t[key] where t itself may be a secret table: returns nil instead of raising.
local function field(t, key)
    if t == nil then return nil end
    local check = issecretvalue
    if check and check(t) then return nil end
    local ok, v = pcall(function() return t[key] end)
    if not ok then return nil end
    return clean(v)
end
API.Field = field

local function numberOrNil(v)
    v = clean(v)
    if type(v) == "number" then return v end
    return nil
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------

function API.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return clean(C_Spell.GetSpellName(id)) end
    if GetSpellInfo then return clean((GetSpellInfo(id))) end
    return nil
end

function API.SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then return clean(C_Spell.GetSpellTexture(id)) end
    if GetSpellTexture then return clean(GetSpellTexture(id)) end
    if GetSpellInfo then return clean((select(3, GetSpellInfo(id)))) end
    return nil
end

-- Cast time in seconds from the client (already includes talents), nil if unknown.
function API.CastTime(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        local ms = numberOrNil(field(info, "castTime"))
        return ms and ms / 1000 or nil
    end
    if GetSpellInfo then
        local ms = numberOrNil((select(4, GetSpellInfo(id))))
        return ms and ms / 1000 or nil
    end
    return nil
end

-- Is this exact spell (rank) known? pet = true for demon abilities.
function API.IsKnown(id, pet)
    if pet then
        if IsSpellKnown then return clean(IsSpellKnown(id, true)) == true end
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            return clean(C_SpellBook.IsSpellKnown(id, Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet)) == true
        end
        return false
    end
    if IsPlayerSpell and clean(IsPlayerSpell(id)) == true then return true end
    if IsSpellKnown and clean(IsSpellKnown(id)) == true then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and clean(C_SpellBook.IsSpellKnown(id)) == true then return true end
    return false
end

-- Cooldown of a spell: start, duration (seconds). nil, nil when hidden or unavailable.
function API.SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if info == nil then return nil, nil end
        return numberOrNil(field(info, "startTime")), numberOrNil(field(info, "duration"))
    end
    if GetSpellCooldown then
        local start, duration = GetSpellCooldown(id)
        return numberOrNil(start), numberOrNil(duration)
    end
    return nil, nil
end

-- Draw a spell's cooldown (global cooldown included) on a Cooldown widget, like an action button.
-- Widgets accept values Lua may not read: secret values are passed through untouched.
-- Returns false when the client gives nothing to draw; the caller then uses its own timers.
function API.ShowSpellCooldown(cooldown, id)
    if C_Spell and C_Spell.GetSpellCooldownDuration and cooldown.SetCooldownFromDurationObject then
        local ok = pcall(function()
            cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(id))
        end)
        if ok then return true end
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok = pcall(function()
            local info = C_Spell.GetSpellCooldown(id)
            cooldown:SetCooldown(info.startTime, info.duration)
        end)
        return ok
    end
    if GetSpellCooldown then
        return (pcall(function() cooldown:SetCooldown(GetSpellCooldown(id)) end))
    end
    return false
end

-- Health gates: the client shows a widget only while a unit's health is at or below a threshold,
-- without the addon ever reading the health (stage 0.2: UnitHealthPercent with a curve gives a
-- secret value that SetAlpha accepts, in combat too). threshold and warn are 0..1.
-- warn > 0 adds a warning band above the threshold: the widget fades in from 0 at threshold+warn
-- to WARN_ALPHA just above the threshold, then is fully shown at the threshold.
local WARN_ALPHA = 0.4
API.WARN_ALPHA = WARN_ALPHA
local curves = {}
local function gateCurve(threshold, warn)
    warn = warn or 0
    local key = threshold .. ":" .. warn
    local curve = curves[key]
    if curve == nil then
        curve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local ok, made = pcall(function()
                local c = C_CurveUtil.CreateCurve()
                local edge = math.min(1, threshold + 0.001)
                c:AddPoint(0, 1)
                c:AddPoint(threshold, 1)
                if warn > 0 and threshold + warn < 1 then
                    c:AddPoint(edge, WARN_ALPHA)
                    c:AddPoint(threshold + warn, 0)
                else
                    c:AddPoint(edge, 0)
                end
                c:AddPoint(1, 0)
                return c
            end)
            if ok then curve = made end
        end
        curves[key] = curve
    end
    return curve or nil
end

-- Returns false when the client can't do it; the caller then keeps the widget hidden.
function API.BindHealthGate(frame, unit, threshold, warn)
    local curve = gateCurve(threshold, warn)
    if not curve or not UnitHealthPercent then return false end
    return (pcall(function() frame:SetAlpha(UnitHealthPercent(unit, true, curve)) end))
end

-- Same by the player's mana (power type 0): UnitPowerPercent(unit, powerType, usePredicted, curve).
function API.BindManaGate(frame, unit, threshold, warn)
    local curve = gateCurve(threshold, warn)
    if not curve or not UnitPowerPercent then return false end
    return (pcall(function() frame:SetAlpha(UnitPowerPercent(unit, 0, true, curve)) end))
end

-- Health or mana, as the gate says.
function API.BindGate(frame, gate, threshold, warn)
    if gate.power == "mana" then return API.BindManaGate(frame, gate.unit, threshold, warn) end
    return API.BindHealthGate(frame, gate.unit, threshold, warn)
end

-- usable, noMana. Either may be nil when hidden.
function API.SpellUsable(id)
    local usable, noMana
    if C_Spell and C_Spell.IsSpellUsable then
        usable, noMana = C_Spell.IsSpellUsable(id)
    elseif IsUsableSpell then
        usable, noMana = IsUsableSpell(id)
    else
        return nil, nil
    end
    usable, noMana = clean(usable), clean(noMana)
    if usable ~= nil then usable = usable and true or false end
    if noMana ~= nil then noMana = noMana and true or false end
    return usable, noMana
end

-- true / false, or nil when the spell has no range or the answer is hidden.
function API.SpellInRange(id, unit)
    local r
    if C_Spell and C_Spell.IsSpellInRange then
        r = clean(C_Spell.IsSpellInRange(id, unit))
    elseif IsSpellInRange then
        local name = API.SpellName(id)
        r = name and clean(IsSpellInRange(name, unit))
        if r == 1 then r = true elseif r == 0 then r = false end
    end
    if r == nil then return nil end
    return r and true or false
end

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------

-- Health in percent, nil when hidden.
function API.HealthPct(unit)
    if not UnitHealth then return nil end
    local hp, max = numberOrNil(UnitHealth(unit)), numberOrNil(UnitHealthMax(unit))
    if not hp or not max or max <= 0 then return nil end
    return hp * 100 / max
end

-- Mana (power type 0): current, max; nil when hidden.
function API.Mana(unit)
    if not UnitPower then return nil, nil end
    local cur, max = numberOrNil(UnitPower(unit, 0)), numberOrNil(UnitPowerMax(unit, 0))
    return cur, max
end

function API.UnitExists(unit) return clean(UnitExists(unit)) and true or false end
function API.CanAttack(unit) return clean(UnitCanAttack("player", unit)) and true or false end
function API.IsDead(unit) return clean(UnitIsDeadOrGhost(unit)) and true or false end
function API.InCombat(unit)
    local v = clean(UnitAffectingCombat(unit))
    if v == nil then return nil end
    return v and true or false
end
function API.GUID(unit) return clean(UnitGUID(unit)) end
function API.Classification(unit) return clean(UnitClassification(unit)) end
function API.UnitLevel(unit) return numberOrNil(UnitLevel(unit)) end
function API.IsPlayer(unit) return clean(UnitIsPlayer(unit)) and true or false end

function API.IsMoving()
    if not GetUnitSpeed then return nil end
    local speed = numberOrNil(GetUnitSpeed("player"))
    if speed == nil then return nil end
    return speed > 0
end

-- Current cast or channel of the player: spellID, endTime, isChannel, startTime (seconds).
-- nil when idle or hidden.
function API.PlayerCast()
    if UnitCastingInfo then
        local name, _, _, startMS, endMS, _, _, _, spellID = UnitCastingInfo("player")
        if clean(name) then
            local id, s, e = numberOrNil(spellID), numberOrNil(startMS), numberOrNil(endMS)
            if id and e then return id, e / 1000, false, s and s / 1000 or nil end
        end
    end
    if UnitChannelInfo then
        local name, _, _, startMS, endMS, _, _, spellID = UnitChannelInfo("player")
        if clean(name) then
            local id, s, e = numberOrNil(spellID), numberOrNil(startMS), numberOrNil(endMS)
            if id and e then return id, e / 1000, true, s and s / 1000 or nil end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------

-- Calls fn(spellId, expirationTime, applications) for each aura of unit matching filter.
-- Returns false when the aura list is hidden and the caller must use its own timers:
-- secret fields, or (stage 0 finding in Forever) an error "Auras cannot be accessed" in combat.
-- The second value is "blocked" in that last case.
local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
function API.ForEachAura(unit, filter, fn)
    if getAura then
        for i = 1, 40 do
            local ok, aura = pcall(getAura, unit, i, filter)
            if not ok then return false, "blocked" end
            if aura == nil then break end
            local id = numberOrNil(field(aura, "spellId"))
            if id == nil then return false end
            fn(id, numberOrNil(field(aura, "expirationTime")) or 0, numberOrNil(field(aura, "applications")) or 0)
        end
        return true
    end
    if UnitAura then
        for i = 1, 40 do
            local name, _, count, _, _, expires, _, _, _, spellId = UnitAura(unit, i, filter)
            if API.IsSecret(name) then return false end
            if name == nil then break end
            local id = numberOrNil(spellId)
            if id == nil then return false end
            fn(id, numberOrNil(expires) or 0, numberOrNil(count) or 0)
        end
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

function API.ItemCount(id)
    if C_Item and C_Item.GetItemCount then return numberOrNil(C_Item.GetItemCount(id)) or 0 end
    if GetItemCount then return numberOrNil(GetItemCount(id)) or 0 end
    return 0
end

function API.ItemCooldown(id)
    local start, duration
    if C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(id)
    elseif GetItemCooldown then
        start, duration = GetItemCooldown(id)
    end
    return numberOrNil(start), numberOrNil(duration)
end

function API.HasWand()
    if HasWandEquipped then
        local v = clean(HasWandEquipped())
        if v ~= nil then return v and true or false end
    end
    return nil
end

---------------------------------------------------------------------------
-- Talents
---------------------------------------------------------------------------

-- Points per talent tree {a, b, c}, or nil when the client has no classic talent API.
function API.TreePoints()
    if not GetNumTalentTabs or not GetTalentInfo or not GetNumTalents then return nil end
    local tabs = clean(GetNumTalentTabs())
    if not tabs or tabs == 0 then return nil end
    local points = {}
    for tab = 1, tabs do
        local sum = 0
        for i = 1, (clean(GetNumTalents(tab)) or 0) do
            local rank = numberOrNil((select(5, GetTalentInfo(tab, i))))
            sum = sum + (rank or 0)
        end
        points[tab] = sum
    end
    return points
end

-- Forever keeps the classic talent trees in the trait system (stage 0 finding: the classic
-- talent API is gone). Fills out[spellID of the talent] = purchased rank; nil when unavailable.
function API.TraitRanks(out)
    ns.wipe(out)
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then
        return nil
    end
    local ok = pcall(function()
        local configID = C_ClassTalents.GetActiveConfigID()
        local config = configID and C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(config and config.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local rank = node and numberOrNil(node.currentRank or node.ranksPurchased) or 0
                for _, entryID in ipairs(node and node.entryIDs or {}) do
                    local entry = C_Traits.GetEntryInfo(configID, entryID)
                    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    local spellID = def and numberOrNil(def.spellID)
                    if spellID then out[spellID] = rank end
                end
            end
        end
    end)
    if not ok or next(out) == nil then return nil end
    return out
end

-- name -> rank for all talents (localized names, matched against client spell names).
function API.TalentRanksByName()
    local out = {}
    if not GetNumTalentTabs or not GetTalentInfo or not GetNumTalents then return out end
    for tab = 1, (clean(GetNumTalentTabs()) or 0) do
        for i = 1, (clean(GetNumTalents(tab)) or 0) do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            name, rank = clean(name), numberOrNil(rank)
            if name then out[name] = rank or 0 end
        end
    end
    return out
end

function API.ActiveSpecGroup()
    if GetActiveTalentGroup then return clean(GetActiveTalentGroup()) or 1 end
    if GetActiveSpecGroup then return clean(GetActiveSpecGroup()) or 1 end
    return 1
end

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------

-- "none" | "party" | "raid" | "pvp" | "arena" | "scenario"
function API.InstanceType()
    if not IsInInstance then return "none" end
    local inside, kind = IsInInstance()
    if not clean(inside) then return "none" end
    return clean(kind) or "none"
end

function API.ClientVersion()
    if not GetBuildInfo then return nil end
    return (GetBuildInfo())
end

-- Nameplate unit tokens currently shown.
function API.NamePlateUnits(out)
    ns.wipe(out)
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return out end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then out[#out + 1] = unit end
    end
    return out
end
