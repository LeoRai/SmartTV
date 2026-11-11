-- Stubs of the WoW client API for tests outside the game.
-- A test describes the world in W (level, known spells, health, auras, ...) and the stubs read it.
-- Values listed in W.secret come back as secret values: any arithmetic or comparison on them
-- raises an error, exactly like tainted code hitting a secret in the real client.
local M = {}

local SECRET_MT = {}
local function secretError() error("attempt to use a secret value", 2) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat", "__lt", "__le", "__eq", "__len", "__index", "__call" }) do
    SECRET_MT[op] = secretError
end
SECRET_MT.__tostring = function() return "<secret>" end
SECRET_MT.__metatable = false

local function secret()
    local s = newproxy and newproxy(true) or setmetatable({}, SECRET_MT)
    if newproxy then
        local mt = getmetatable(s)
        for k, v in pairs(SECRET_MT) do mt[k] = v end
    end
    return s
end

local function isSecret(v) return type(v) == "userdata" and tostring(v) == "<secret>" end

-- Fresh world with sane defaults.
function M.newWorld()
    return {
        time = 1000,
        class = "WARLOCK",
        locale = "enUS",
        level = 1,
        known = {},          -- spellID -> true
        petKnown = {},       -- pet spellID -> true
        castTimes = {},      -- spellID -> ms
        cooldowns = {},      -- spellID -> { start, duration }
        usable = {},         -- spellID -> false to make unusable
        noMana = {},         -- spellID -> true
        range = {},          -- spellID -> false when out of range
        player = { hp = 100, hpMax = 100, mana = 100, manaMax = 100, combat = false, speed = 0 },
        target = nil,        -- { hp, hpMax, enemy, dead, guid, class, level, player, combat }
        pet = nil,           -- { hp, hpMax, family }
        auras = { player = {}, target = {} }, -- list of { spellId, expirationTime, applications, mine }
        items = {},          -- itemID -> count
        itemCooldowns = {},  -- itemID -> { start, duration }
        casting = nil,       -- { spellID, startMS, endMS, channel }
        instance = "none",
        plates = {},         -- unit tokens with nameplates
        units = {},          -- extra units: token -> { enemy, combat, dead }
        wand = true,
        talentTabs = nil,    -- { { {name, rank, max}, ... }, ... }
        secret = {},         -- "player.hp", "target.hp", "player.mana", "auras", "cooldowns", "cast"
        build = "1.60.1",
        chat = {},
        sounds = {},         -- files passed to PlaySoundFile
        actions = {},        -- action slot -> { "spell", spellID }
        bindings = {},       -- binding command -> key
        subzone = "Brill",
        registered = {},     -- events registered on any frame
        auraError = false,   -- Forever in combat: aura reads raise "Auras cannot be accessed"
        auraCalls = 0,
        noGcdSpell = false,  -- Forever: the global cooldown spell 61304 answers nil
        traits = nil,        -- talent spellID -> rank (trait system); nil = no trait API
    }
end

-- Install the stubs into _G for world W.
function M.install(W)
    local G = _G
    local function S(key, value)
        if W.secret[key] then return secret() end
        return value
    end
    local function unitData(unit)
        if unit == "player" then return W.player end
        if unit == "target" then return W.target end
        if unit == "pet" then return W.pet end
        return W.units[unit]
    end

    G.issecretvalue = isSecret
    G.GetTime = function() return W.time end
    G.debugprofilestop = function() return os.clock() * 1000 end
    G.GetLocale = function() return W.locale end
    G.GetBuildInfo = function() return W.build, "1", "Nov 2026", 16001 end
    G.UnitClass = function() return "Warlock", W.class end
    G.UnitLevel = function(unit)
        if unit == "player" then return W.level end
        local d = unitData(unit)
        return d and (d.level or W.level) or 0
    end
    G.UnitExists = function(unit) return unitData(unit) ~= nil end
    G.UnitIsDeadOrGhost = function(unit) local d = unitData(unit); return d and d.dead or false end
    G.UnitCanAttack = function(_, unit) local d = unitData(unit); return d and d.enemy or false end
    G.UnitAffectingCombat = function(unit)
        local d = unitData(unit)
        if not d then return false end
        if unit == "target" and d.combat == nil then return W.player.combat end
        return d.combat or false
    end
    G.InCombatLockdown = function() return W.player.combat end
    G.UnitGUID = function(unit) local d = unitData(unit); return d and (d.guid or ("guid-" .. unit)) end
    G.UnitClassification = function(unit) local d = unitData(unit); return d and d.class or "normal" end
    G.UnitIsPlayer = function(unit) local d = unitData(unit); return d and d.player or false end
    G.UnitIsUnit = function(a, b) return a == b end
    G.UnitHealth = function(unit)
        local d = unitData(unit)
        if not d then return 0 end
        return S(unit .. ".hp", d.hp)
    end
    G.UnitHealthMax = function(unit)
        local d = unitData(unit)
        if not d then return 0 end
        return S(unit .. ".hp", d.hpMax or 100)
    end
    G.UnitPower = function(unit) local d = unitData(unit); return S(unit .. ".mana", d and d.mana or 0) end
    G.UnitPowerMax = function(unit) local d = unitData(unit); return S(unit .. ".mana", d and d.manaMax or 0) end
    G.GetUnitSpeed = function() return W.player.speed end
    G.UnitCreatureFamily = function(unit) local d = unitData(unit); return d and d.family end
    G.UnitCastingInfo = function()
        local c = W.casting
        if not c or c.channel then return nil end
        if W.secret.cast then return secret(), nil, nil, secret(), secret(), nil, nil, nil, secret() end
        return "cast", "", 0, c.startMS, c.endMS, false, "guid", false, c.spellID
    end
    G.UnitChannelInfo = function()
        local c = W.casting
        if not c or not c.channel then return nil end
        return "channel", "", 0, c.startMS, c.endMS, false, false, c.spellID
    end
    G.IsInInstance = function() return W.instance ~= "none", W.instance end
    G.HasWandEquipped = function() return W.wand end

    G.IsPlayerSpell = function(id) return W.known[id] == true end
    G.IsSpellKnown = function(id, pet)
        if pet then return W.petKnown[id] == true end
        return W.known[id] == true
    end
    G.C_Spell = {
        GetSpellName = function(id) return "spell" .. id end,
        GetSpellTexture = function(id) return id end,
        GetSpellInfo = function(id)
            return { name = "spell" .. id, spellID = id, castTime = W.castTimes[id] or 0 }
        end,
        GetSpellCooldown = function(id)
            if W.noGcdSpell and id == 61304 then return nil end
            if W.secret.cooldowns then return { startTime = secret(), duration = secret(), isEnabled = true } end
            local cd = W.cooldowns[id]
            return { startTime = cd and cd[1] or 0, duration = cd and cd[2] or 0, isEnabled = true }
        end,
        IsSpellUsable = function(id)
            if W.usable[id] == false then return false, W.noMana[id] or false end
            return true, false
        end,
        IsSpellInRange = function(id) if W.range[id] == false then return false end return true end,
    }
    G.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            W.auraCalls = W.auraCalls + 1
            if W.auraError then error("GetAuraDataByIndex(): Auras cannot be accessed while in combat") end
            local list = W.auras[unit]
            if not list then return nil end
            local mineOnly = filter and filter:find("PLAYER")
            local n = 0
            for _, a in ipairs(list) do
                if not mineOnly or a.mine ~= false then
                    n = n + 1
                    if n == i then
                        if W.secret.auras then return { spellId = secret(), expirationTime = secret(), applications = 0 } end
                        return { spellId = a.spellId, expirationTime = a.expirationTime or 0, applications = a.applications or 0 }
                    end
                end
            end
            return nil
        end,
    }
    G.C_Item = { GetItemCount = function(id) return W.items[id] or 0 end, GetItemIconByID = function(id) return id end }
    G.C_Container = {
        GetItemCooldown = function(id)
            local cd = W.itemCooldowns[id]
            if cd then return cd[1], cd[2], 1 end
            return 0, 0, 1
        end,
    }
    G.C_NamePlate = {
        GetNamePlates = function()
            local out = {}
            for _, unit in ipairs(W.plates) do out[#out + 1] = { namePlateUnitToken = unit } end
            return out
        end,
    }
    -- Trait system: one tree, one node per talent spell.
    G.C_ClassTalents = { GetActiveConfigID = function() return W.traits and 1 or nil end }
    G.C_Traits = {
        GetConfigInfo = function() return { treeIDs = { 1 } } end,
        GetTreeNodes = function()
            local nodes = {}
            for spellID in pairs(W.traits or {}) do nodes[#nodes + 1] = spellID end
            return nodes
        end,
        GetNodeInfo = function(_, nodeID) return { currentRank = W.traits[nodeID], entryIDs = { nodeID } } end,
        GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
        GetDefinitionInfo = function(definitionID) return { spellID = definitionID } end,
    }
    G.GetNumTalentTabs = function() return W.talentTabs and #W.talentTabs or 0 end
    G.GetNumTalents = function(tab) return W.talentTabs and #W.talentTabs[tab] or 0 end
    G.GetTalentInfo = function(tab, i)
        local t = W.talentTabs[tab][i]
        return t[1], 0, 1, 1, t[2], t[3]
    end
    G.GetActiveTalentGroup = function() return 1 end
    G.GetActionInfo = function(slot)
        local a = W.actions[slot]
        if a then return a[1], a[2], a[3] end
        return nil
    end
    G.GetBindingKey = function(command) return W.bindings[command] end
    G.GetBindingText = function(key) return key end
    G.PlaySoundFile = function(path) W.sounds[#W.sounds + 1] = path end
    G.GetSubZoneText = function() return W.subzone end
    G.IsTradeskillTrainer = function() return false end
    G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

    -- Frames: Create* methods return another stub, Get* return 0, everything else nil.
    -- Enough for the UI files to load and build their frames.
    local stub
    local function method(k)
        if not k:match("^%u") then return nil end -- fields, unlike methods, start lowercase
        if k:match("^Create") then return function() return stub() end end
        if k:match("^Get") then return function() return 0 end end
        return function() return nil end
    end
    stub = function()
        local scripts = {}
        local obj = {
            SetScript = function(_, name, fn) scripts[name] = fn end,
            GetScript = function(_, name) return scripts[name] end,
            RegisterEvent = function(_, event) W.registered[event] = true end,
        }
        return setmetatable(obj, { __index = function(_, k) return method(k) end })
    end
    W.frames = {}
    G.CreateFrame = function()
        local f = stub()
        W.frames[#W.frames + 1] = f
        return f
    end
    G.C_Timer = {
        After = function(_, fn) fn() end,
        NewTicker = function() return { Cancel = function() end } end,
    }
    G.UnitName = function(unit) return unit end
    G.GetRealZoneText = function() return "Zone" end
    G.UIParent = stub()
    G.Minimap = stub()
    G.GameTooltip = stub()
    G.UISpecialFrames = {}
    G.SlashCmdList = {}
    G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) W.chat[#W.chat + 1] = text end }
    G.PlaySound = function() end
    G.wipe = nil -- the addon must not depend on it outside the game
end

M.secret, M.isSecret = secret, isSecret
return M
