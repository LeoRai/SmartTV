-- ForeverCoach Probe: stage 0 of the plan.
-- Answers "what can an addon read in WoW Forever, in and out of combat?" before the engine
-- relies on it. Every check runs inside pcall, so the probe itself never breaks the game.
--
--   /fcprobe          status and commands
--   /fcprobe snap     record the current situation now
--   /fcprobe dump     export spellbook, talents, demon abilities (out of combat)
--   /fcprobe report   window with the full report to copy (Ctrl+A, Ctrl+C)
--   /fcprobe reset    forget everything recorded
--
-- Snapshots are also taken by themselves: at login, 1 and 4 s into each fight, every 5 s in a
-- fight, right after it. Trainer windows and turned-in quests are recorded when they happen.
-- Everything lands in WTF\Account\<account>\SavedVariables\ForeverCoach_Probe.lua.
local ADDON = ...

local VERSION = 1
local DB
local isRu = GetLocale and GetLocale() == "ruRU"

local function T(ru, en) return isRu and ru or en end

local function say(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage("|cff8f7fffFC Probe|r: " .. text)
end

---------------------------------------------------------------------------
-- Classification of one value
---------------------------------------------------------------------------

local function resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

local function short(v)
    local s = tostring(v)
    if #s > 40 then s = s:sub(1, 40) .. "..." end
    return s
end

-- Returns status, sample. status: ok | secret | nil | error | missing | skip
local function classify(fn)
    local ok, v, skip = pcall(fn)
    if not ok then return "error", short(v) end
    if skip == "skip" then return "skip" end
    if issecretvalue and issecretvalue(v) then return "secret" end
    if v == nil then return "nil" end
    if type(v) == "number" then
        -- A secret that issecretvalue does not flag would still refuse arithmetic.
        local fine = pcall(function() return v + 1 > v end)
        if not fine then return "secret" end
    end
    return "ok", short(v)
end

---------------------------------------------------------------------------
-- What to check
---------------------------------------------------------------------------

-- A basic spell every character of the class knows from level 1.
local BASIC = {
    WARLOCK = 686, MAGE = 133, PRIEST = 585, WARRIOR = 78, ROGUE = 1752, HUNTER = 2973,
    DRUID = 5176, PALADIN = 635, SHAMAN = 403,
}
local GCD_SPELL = 61304
local HEARTHSTONE = 6948
local SOUL_SHARD = 6265

local function basicSpell()
    return BASIC[select(2, UnitClass("player"))] or 6603
end

-- API presence, checked once.
local APIS = {
    "issecretvalue", "canaccessvalue", "canaccesssecrets", "C_Secrets", "C_Spell.GetSpellInfo", "C_Spell.GetSpellName",
    "C_Spell.GetSpellCooldown", "C_Spell.GetSpellCooldownDuration", "C_Spell.IsSpellUsable", "C_Spell.IsSpellInRange",
    "GetSpellInfo", "GetSpellCooldown", "IsUsableSpell", "IsSpellInRange", "IsPlayerSpell", "IsSpellKnown",
    "C_SpellBook.IsSpellKnown", "C_SpellBook.GetSpellBookItemInfo", "GetSpellBookItemInfo", "GetSpellBookItemName",
    "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetPlayerAuraBySpellID", "C_UnitAuras.GetAuraDataBySpellName",
    "UnitAura", "UnitDebuff", "AuraUtil.ForEachAura", "GetTalentInfo", "GetNumTalentTabs", "GetTalentTabInfo",
    "GetTalentLink", "C_Traits.GetConfigInfo", "C_ClassTalents.GetActiveConfigID", "GetActiveTalentGroup",
    "GetActiveSpecGroup", "GetNumTalentGroups", "C_NamePlate.GetNamePlates", "C_AssistedCombat.GetNextCastSpell",
    "C_ActionBar.FindSpellActionButtons", "GetActionInfo", "CombatLogGetCurrentEventInfo", "C_Item.GetItemCount",
    "GetItemCount", "C_Container.GetItemCooldown", "GetItemCooldown", "GetNumTrainerServices", "GetTrainerServiceInfo",
    "GetTrainerServiceCost", "GetTrainerServiceLevelReq", "C_TooltipInfo.GetTrainerService", "UnitCastingInfo",
    "UnitChannelInfo", "UnitThreatSituation", "GetPetActionInfo", "UnitCreatureFamily", "HasWandEquipped",
    "C_QuestLog.GetTitleForQuestID", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "Settings.RegisterCanvasLayoutCategory",
}

local function firstAura(unit, filter, field)
    return function()
        if not UnitExists(unit) then return nil, "skip" end
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, 1, filter)
        if aura == nil then return nil, "skip" end
        if issecretvalue and issecretvalue(aura) then return aura end
        return aura[field]
    end
end

local function cooldownField(spell, field)
    return function()
        local id = type(spell) == "function" and spell() or spell
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(id)
            if info == nil then return nil end
            if issecretvalue and issecretvalue(info) then return info end
            return info[field]
        end
        local start, duration = GetSpellCooldown(id)
        return field == "startTime" and start or duration
    end
end

local function needTarget(fn)
    return function()
        if not UnitExists("target") then return nil, "skip" end
        return fn()
    end
end

local function firstPlate()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then return unit end
    end
end

local function needPlate(fn)
    return function()
        local unit = firstPlate()
        if not unit then return nil, "skip" end
        return fn(unit)
    end
end

-- Value checks, run in every snapshot. Order = order in the report.
local CHECKS = {
    { "player.health", function() return UnitHealth("player") end },
    { "player.healthMax", function() return UnitHealthMax("player") end },
    { "player.mana", function() return UnitPower("player", 0) end },
    { "player.inCombat", function() return UnitAffectingCombat("player") end },
    { "player.speed", function() return GetUnitSpeed("player") end },
    { "player.cast.spellID", function()
        local name, _, _, _, _, _, _, _, id = UnitCastingInfo("player")
        if name == nil then return nil, "skip" end
        return id
    end },
    { "player.channel.spellID", function()
        local name, _, _, _, _, _, _, id = UnitChannelInfo("player")
        if name == nil then return nil, "skip" end
        return id
    end },
    { "target.guid", needTarget(function() return UnitGUID("target") end) },
    { "target.health", needTarget(function() return UnitHealth("target") end) },
    { "target.healthMax", needTarget(function() return UnitHealthMax("target") end) },
    { "target.level", needTarget(function() return UnitLevel("target") end) },
    { "target.classification", needTarget(function() return UnitClassification("target") end) },
    { "target.canAttack", needTarget(function() return UnitCanAttack("player", "target") end) },
    { "target.inCombat", needTarget(function() return UnitAffectingCombat("target") end) },
    { "target.threat", needTarget(function() return UnitThreatSituation("player", "target") end) },
    { "pet.health", function() if not UnitExists("pet") then return nil, "skip" end return UnitHealth("pet") end },
    { "pet.family", function() if not UnitExists("pet") then return nil, "skip" end return UnitCreatureFamily("pet") end },
    { "spell.known", function() return IsPlayerSpell(basicSpell()) end },
    { "spell.castTime", function()
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(basicSpell())
            if issecretvalue and issecretvalue(info) then return info end
            return info and info.castTime
        end
        return (select(4, GetSpellInfo(basicSpell())))
    end },
    { "spell.cooldown.start", cooldownField(basicSpell, "startTime") },
    { "gcd.cooldown.start", cooldownField(GCD_SPELL, "startTime") },
    { "gcd.cooldown.duration", cooldownField(GCD_SPELL, "duration") },
    { "spell.usable", function()
        if C_Spell and C_Spell.IsSpellUsable then return (C_Spell.IsSpellUsable(basicSpell())) end
        return (IsUsableSpell(basicSpell()))
    end },
    { "spell.noMana", function()
        if C_Spell and C_Spell.IsSpellUsable then return (select(2, C_Spell.IsSpellUsable(basicSpell()))) end
        return (select(2, IsUsableSpell(basicSpell())))
    end },
    { "spell.inRange", needTarget(function()
        if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(basicSpell(), "target") end
        return IsSpellInRange(GetSpellInfo(basicSpell()), "target")
    end) },
    { "aura.player.spellId", firstAura("player", "HELPFUL", "spellId") },
    { "aura.player.expirationTime", firstAura("player", "HELPFUL", "expirationTime") },
    { "aura.target.mine.spellId", firstAura("target", "HARMFUL|PLAYER", "spellId") },
    { "aura.target.mine.expirationTime", firstAura("target", "HARMFUL|PLAYER", "expirationTime") },
    { "aura.target.any.spellId", firstAura("target", "HARMFUL", "spellId") },
    { "nameplates.count", function()
        if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
        return #(C_NamePlate.GetNamePlates() or {})
    end },
    { "nameplate.canAttack", needPlate(function(unit) return UnitCanAttack("player", unit) end) },
    { "nameplate.inCombat", needPlate(function(unit) return UnitAffectingCombat(unit) end) },
    { "nameplate.health", needPlate(function(unit) return UnitHealth(unit) end) },
    { "nameplate.inRange", needPlate(function(unit)
        if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(basicSpell(), unit) end
        return IsSpellInRange(GetSpellInfo(basicSpell()), unit)
    end) },
    { "item.count", function()
        if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(SOUL_SHARD) end
        return GetItemCount(SOUL_SHARD)
    end },
    { "item.cooldown.start", function()
        if C_Container and C_Container.GetItemCooldown then return (C_Container.GetItemCooldown(HEARTHSTONE)) end
        return (GetItemCooldown(HEARTHSTONE))
    end },
    { "talent.rank", function()
        if not GetTalentInfo then return nil end
        return (select(5, GetTalentInfo(1, 1)))
    end },
    { "actionbar.slot1", function() return (GetActionInfo(1)) end },
    { "wand.equipped", function() return HasWandEquipped() end },
}

-- Events whose arguments we look at: does it fire, are its values readable?
local EVENTS = {
    UNIT_SPELLCAST_START = function(unit, _, spellID) return unit == "player", spellID end,
    UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID) return unit == "player", spellID end,
    UNIT_SPELLCAST_CHANNEL_START = function(unit, _, spellID) return unit == "player", spellID end,
    UNIT_HEALTH = function(unit) return unit == "target", unit end,
    UNIT_AURA = function(unit, info)
        if unit ~= "target" and unit ~= "player" then return false end
        local added = type(info) == "table" and not (issecretvalue and issecretvalue(info)) and info.addedAuras
        if added and added[1] then return true, added[1].spellId end
        return true, unit
    end,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = function(spellID) return true, spellID end,
    PLAYER_TARGET_CHANGED = function() return true, "target" end,
    NAME_PLATE_UNIT_ADDED = function(unit) return true, unit end,
    -- No COMBAT_LOG_EVENT_UNFILTERED: subscribing to the combat log is a Blizzard-only action in
    -- Forever, and the client blocks the addon with a popup even inside pcall. Its absence is
    -- already known; the API list still records whether CombatLogGetCurrentEventInfo exists.
}

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local INSTANCE_NAMES = { none = "world", party = "dungeon", raid = "raid", pvp = "battleground", arena = "arena", scenario = "scenario" }

local function contextName()
    local inside, kind = IsInInstance()
    local place = inside and (INSTANCE_NAMES[kind] or tostring(kind)) or "world"
    local fight = InCombatLockdown() and "combat" or "idle"
    return place .. "/" .. fight
end

local function contextTable(ctx)
    DB.contexts[ctx] = DB.contexts[ctx] or { snaps = 0, checks = {}, events = {} }
    return DB.contexts[ctx]
end

local function snapshot(manual)
    local ctx = contextName()
    local isNew = DB.contexts[ctx] == nil
    local c = contextTable(ctx)
    c.snaps = c.snaps + 1
    for _, check in ipairs(CHECKS) do
        local name, fn = check[1], check[2]
        local status, sample = classify(fn)
        if status ~= "skip" then
            local rec = c.checks[name] or {}
            c.checks[name] = rec
            rec[status] = (rec[status] or 0) + 1
            if status == "ok" and sample then rec.sample = sample end
            if status == "error" then rec.err = sample end
        end
    end
    if isNew or manual then say(T("снимок записан: %s", "snapshot saved: %s"), ctx) end
end

local function recordEvent(event, ...)
    local relevant, value = EVENTS[event](...)
    if not relevant then return end
    local c = contextTable(contextName())
    local rec = c.events[event] or { fired = 0 }
    c.events[event] = rec
    rec.fired = rec.fired + 1
    if issecretvalue and issecretvalue(value) then
        rec.secret = (rec.secret or 0) + 1
    elseif value ~= nil then
        rec.readable = (rec.readable or 0) + 1
        rec.sample = short(value)
    end
end

---------------------------------------------------------------------------
-- Dumps: spellbook, talents, demon abilities, trainer, quests
---------------------------------------------------------------------------

local function dumpSpellbook()
    local out = {}
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if item and item.spellID then
                    out[#out + 1] = { id = item.spellID, name = item.name, rank = item.subName, tab = info.name }
                end
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local tabName, _, offset, count = GetSpellTabInfo(tab)
            for i = offset + 1, offset + count do
                local kind, id = GetSpellBookItemInfo(i, "spell")
                local name, rank = GetSpellBookItemName(i, "spell")
                out[#out + 1] = { id = id, kind = kind, name = name, rank = rank, tab = tabName }
            end
        end
    end
    return out
end

local function dumpTalents()
    local out = { legacy = {}, traits = {} }
    if GetNumTalentTabs then
        for tab = 1, GetNumTalentTabs() do
            local tabInfo = { GetTalentTabInfo(tab) }
            local entry = { info = {}, talents = {} }
            for i, v in ipairs(tabInfo) do entry.info[i] = short(v) end
            for i = 1, GetNumTalents(tab) do
                local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, i)
                local link = GetTalentLink and GetTalentLink(tab, i)
                entry.talents[i] = { name = name, icon = icon, tier = tier, column = column, rank = rank, max = maxRank,
                                     link = link and link:gsub("|", "||") }
            end
            out.legacy[tab] = entry
        end
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits then
        local configID = C_ClassTalents.GetActiveConfigID()
        local config = configID and C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(config and config.treeIDs or {}) do
            for n, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                if n > 400 then break end
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                for _, entryID in ipairs(node and node.entryIDs or {}) do
                    local e = C_Traits.GetEntryInfo(configID, entryID)
                    local d = e and e.definitionID and C_Traits.GetDefinitionInfo(e.definitionID)
                    out.traits[#out.traits + 1] = { node = nodeID, entry = entryID, spellID = d and d.spellID,
                                                    rank = node.currentRank, max = node.maxRanks }
                end
            end
        end
    end
    return out
end

local function dumpPet()
    local out = { family = UnitExists("pet") and UnitCreatureFamily("pet") or nil, actions = {} }
    if GetPetActionInfo then
        for i = 1, 10 do
            local name, texture, isToken, _, _, _, spellID = GetPetActionInfo(i)
            if name then out.actions[i] = { name = name, texture = texture, token = isToken, spellID = spellID } end
        end
    end
    return out
end

local function playerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return { map = map } end
    local x, y = pos:GetXY()
    return { map = map, x = math.floor(x * 1000) / 10, y = math.floor(y * 1000) / 10 }
end

local function dumpTrainer()
    if not GetNumTrainerServices then return end
    local out = { npc = UnitName("npc"), zone = GetRealZoneText and GetRealZoneText(), pos = playerPosition(),
                  level = UnitLevel("player"), services = {} }
    for i = 1, GetNumTrainerServices() do
        local ok, name, rank, category = pcall(GetTrainerServiceInfo, i)
        if ok and name then
            local svc = { name = name, rank = rank, category = category }
            pcall(function() svc.cost = GetTrainerServiceCost(i) end)
            pcall(function() svc.level = GetTrainerServiceLevelReq(i) end)
            pcall(function()
                local data = C_TooltipInfo and C_TooltipInfo.GetTrainerService and C_TooltipInfo.GetTrainerService(i)
                svc.spellID = data and data.id
            end)
            out.services[#out.services + 1] = svc
        end
    end
    DB.trainers[#DB.trainers + 1] = out
    say(T("учитель записан: %d услуг", "trainer saved: %d services"), #out.services)
end

local function dump()
    if InCombatLockdown() then
        say(T("выгрузка только вне боя", "dump works out of combat only"))
        return
    end
    local level = UnitLevel("player")
    local results = {}
    for name, fn in pairs({ spellbook = dumpSpellbook, talents = dumpTalents, pet = dumpPet }) do
        local ok, value = pcall(fn)
        DB.dumps[name] = ok and value or { error = tostring(value) }
        results[#results + 1] = name .. (ok and "" or " (error)")
    end
    DB.dumps.level, DB.dumps.at = level, date and date("%Y-%m-%d %H:%M") or nil
    say(T("выгружено: %s", "dumped: %s"), table.concat(results, ", "))
end

---------------------------------------------------------------------------
-- Report window
---------------------------------------------------------------------------

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function summarize(rec)
    if not rec then return "-" end
    local parts = {}
    for _, status in ipairs({ "ok", "secret", "nil", "error" }) do
        if rec[status] then parts[#parts + 1] = status .. ":" .. rec[status] end
    end
    local text = table.concat(parts, " ")
    if rec.sample then text = text .. " (" .. rec.sample .. ")" end
    if rec.err then text = text .. " [" .. rec.err .. "]" end
    return text
end

local function buildReport()
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
    local c = DB.client
    add("ForeverCoach Probe report v%d", VERSION)
    add("client %s build %s (%s) toc %s project %s locale %s", tostring(c.version), tostring(c.build), tostring(c.date),
        tostring(c.toc), tostring(c.project), tostring(c.locale))
    add("character: %s level %s", tostring(c.class), tostring(UnitLevel("player")))
    add("")
    local missing = {}
    for _, name in ipairs(APIS) do if DB.api[name] == "missing" then missing[#missing + 1] = name end end
    add("API missing (%d): %s", #missing, table.concat(missing, ", "))
    add("")
    local contexts = sortedKeys(DB.contexts)
    for _, ctx in ipairs(contexts) do
        local cx = DB.contexts[ctx]
        add("== %s (%d snapshots)", ctx, cx.snaps)
        for _, check in ipairs(CHECKS) do
            if cx.checks[check[1]] then add("  %-32s %s", check[1], summarize(cx.checks[check[1]])) end
        end
        for _, event in ipairs(sortedKeys(cx.events)) do
            local e = cx.events[event]
            add("  event %-26s fired:%d readable:%d secret:%d%s", event, e.fired, e.readable or 0, e.secret or 0,
                e.sample and (" (" .. e.sample .. ")") or "")
        end
    end
    add("")
    local regs = {}
    for _, event in ipairs(sortedKeys(DB.registration)) do regs[#regs + 1] = event .. "=" .. DB.registration[event] end
    add("event registration: %s", table.concat(regs, ", "))
    local blocked = {}
    for _, b in ipairs(DB.blocked or {}) do blocked[#blocked + 1] = b.func .. " (" .. b.where .. ")" end
    add("blocked by the client: %s", #blocked > 0 and table.concat(blocked, ", ") or "-")
    local book = DB.dumps.spellbook
    add("dump: spellbook %s, talents %s, pet %s, trainers %d, quests %d",
        book and (#book .. " spells") or "-", DB.dumps.talents and "yes" or "-", DB.dumps.pet and "yes" or "-",
        #DB.trainers, #DB.quests)
    add("")
    add(T("Полные выгрузки: WTF\\Account\\<аккаунт>\\SavedVariables\\ForeverCoach_Probe.lua",
          "Full dumps: WTF\\Account\\<account>\\SavedVariables\\ForeverCoach_Probe.lua"))
    return table.concat(lines, "\n")
end

local reportFrame
local function showReport()
    if not reportFrame then
        local f = CreateFrame("Frame", "ForeverCoachProbeReport", UIParent, "BackdropTemplate")
        f:SetSize(640, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        table.insert(UISpecialFrames, "ForeverCoachProbeReport")
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -10)
        title:SetText(T("Отчёт разведки: Ctrl+A, Ctrl+C и отправь разработчику",
                        "Probe report: Ctrl+A, Ctrl+C and send it to the developer"))
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("GameFontHighlightSmall")
        edit:SetSize(590, 420)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        reportFrame = f
    end
    reportFrame.edit:SetText(buildReport())
    reportFrame.edit:HighlightText()
    reportFrame:Show()
    reportFrame.edit:SetFocus()
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function newDB()
    return { version = VERSION, client = {}, api = {}, registration = {}, contexts = {}, dumps = {},
             trainers = {}, quests = {}, blocked = {} }
end

local function recordClient()
    local version, build, date_, toc = GetBuildInfo()
    DB.client = {
        version = version, build = build, date = date_, toc = toc, project = WOW_PROJECT_ID,
        locale = GetLocale(), class = select(2, UnitClass("player")),
    }
    for _, name in ipairs(APIS) do DB.api[name] = resolve(name) ~= nil and "present" or "missing" end
end

local frame = CreateFrame("Frame")
local combatTicker, combatSnaps = nil, 0

local function onCombatStart()
    combatSnaps = 0
    C_Timer.After(1, function() snapshot(false) end)
    C_Timer.After(4, function() snapshot(false) end)
    if C_Timer.NewTicker then
        combatTicker = C_Timer.NewTicker(5, function()
            combatSnaps = combatSnaps + 1
            if combatSnaps <= 12 and InCombatLockdown() then snapshot(false) end
        end)
    end
end

local function onCombatEnd()
    if combatTicker then combatTicker:Cancel(); combatTicker = nil end
    C_Timer.After(0.5, function() snapshot(false) end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        ForeverCoachProbeDB = ForeverCoachProbeDB or newDB()
        DB = ForeverCoachProbeDB
        if DB.version ~= VERSION then ForeverCoachProbeDB = newDB(); DB = ForeverCoachProbeDB end
        DB.blocked = DB.blocked or {}
    elseif event == "PLAYER_LOGIN" then
        recordClient()
        C_Timer.After(3, function() snapshot(false); pcall(dump) end)
        say(T("работает. Подерись в мире, в подземелье и на поле боя, открой учителя, затем /fcprobe report",
              "running. Fight in the world, a dungeon and a battleground, visit your trainer, then /fcprobe report"))
    elseif event == "PLAYER_REGEN_DISABLED" then
        onCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        onCombatEnd()
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(2, function() pcall(dump) end)
    elseif event == "TRAINER_SHOW" then
        C_Timer.After(0.5, function() pcall(dumpTrainer) end)
    elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        -- The client stopped an action of this addon: keep the function name for the report.
        local addon, func = ...
        if addon == ADDON and DB then
            DB.blocked[#DB.blocked + 1] = { event = event, func = tostring(func), where = contextName() }
            say(T("игра заблокировала действие: %s", "the game blocked an action: %s"), tostring(func))
        end
    elseif event == "QUEST_TURNED_IN" then
        local questID = ...
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
        DB.quests[#DB.quests + 1] = { id = questID, title = title, level = UnitLevel("player") }
    elseif EVENTS[event] and DB then
        pcall(recordEvent, event, ...)
    end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                         "PLAYER_LEVEL_UP", "TRAINER_SHOW", "QUEST_TURNED_IN",
                         "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
    pcall(frame.RegisterEvent, frame, event)
end
-- Registration itself is part of the answer (the combat log may be closed to addons).
C_Timer.After(0, function()
    for event in pairs(EVENTS) do
        local ok, err = pcall(frame.RegisterEvent, frame, event)
        if DB then DB.registration[event] = ok and "ok" or ("error: " .. short(err)) end
    end
end)

SLASH_FCPROBE1 = "/fcprobe"
SlashCmdList.FCPROBE = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    if cmd == "snap" then
        snapshot(true)
    elseif cmd == "dump" then
        dump()
    elseif cmd == "report" then
        showReport()
    elseif cmd == "reset" then
        ForeverCoachProbeDB = newDB()
        DB = ForeverCoachProbeDB
        recordClient()
        say(T("всё стёрто", "everything cleared"))
    else
        local n = 0
        for _ in pairs(DB.contexts) do n = n + 1 end
        say(T("ситуаций записано: %d. Команды: snap, dump, report, reset", "situations recorded: %d. Commands: snap, dump, report, reset"), n)
    end
end
