-- Namespace, saved settings and module lifecycle.
-- Modules never call each other's internals for game events: they talk through ns.Events (Core/Events.lua).
local ADDON, ns = ...
local L = ns.L

ns.ADDON = ADDON

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMeta and getMeta(ADDON, "Version")) or "dev"

-- Lua helpers that exist in the game but not in plain Lua (tests run outside the game).
ns.wipe = wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage("|cff8f7fffForeverCoach|r: " .. text)
    else
        print("ForeverCoach: " .. text)
    end
end

-- Settings kept per character (SavedVariablesPerCharacter: ForeverCoachCharDB).
ns.Defaults = {
    schema = 3,
    shown = true,            -- the "show or hide hints" key
    hideOutOfCombat = true,  -- out of combat only the preparation line stays
    highlightBar = true,     -- gold frame on the action bar button of the main hint
    locked = true,
    tooltips = true,
    debug = false,
    nextIcons = 3,           -- 0..3 icons after the main one
    iconSize = 56,           -- main icon, px; the others scale with it
    alpha = 1.0,
    pos = { point = "CENTER", x = 0, y = -170 },
    mode = "auto",           -- auto | leveling | group | pvp
    hpThreshold = 35,        -- defense slot: player health, %
    petHpThreshold = 40,     -- defense slot: demon health, %
    shards = 3,              -- Soul Shards to keep
    soundReady = true,       -- "time to press": soft click
    soundReadyVolume = 35,
    soundProc = true,        -- instant proc: bright chime
    soundProcVolume = 70,
    minimap = { hide = false, angle = 215 },
    warnedData = {},         -- data versions already reported as outdated
}

-- Settings saved by an older version: move to the current layout.
local function migrate(db)
    if (db.schema or 1) < 2 then
        db.nextIcons, db.hideOutOfCombat = 3, true -- the block now shows the rotation ahead
        db.scale, db.sound = nil, nil              -- replaced by iconSize and two sound settings
    end
    if (db.schema or 1) < 3 then
        db.lifeTapGap = nil -- Forever hides mana and health: Life Tap goes by "out of mana" only
    end
    db.schema = ns.Defaults.schema
    return db
end
ns.Migrate = migrate

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
ns.CopyDefaults = copyDefaults

-- Data that is not a setting survives /fc reset.
ns.KeepOnReset = { builds = true, trainerVisit = true, trainerPlace = true, surprises = true, warnedData = true }

function ns:ResetSettings()
    local kept = {}
    for key in pairs(ns.KeepOnReset) do kept[key] = ns.db[key] end
    ns.wipe(ns.db)
    for key, value in pairs(kept) do ns.db[key] = value end
    copyDefaults(ns.db, ns.Defaults)
end

-- Error reporting: never let one bad tick spam error popups, but never hide errors either.
local reported = {}
function ns.SafeCall(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[where] then
        reported[where] = true
        ns.Print(L.LUA_ERROR, where, tostring(err))
    end
    return ok, err
end

-- Key bindings: the names are globals the game reads from Bindings.xml.
BINDING_HEADER_FOREVERCOACH = L.BINDING_HEADER
BINDING_NAME_FOREVERCOACH_TOGGLE = L.BINDING_TOGGLE
BINDING_NAME_FOREVERCOACH_BUILDS = L.BINDING_BUILDS
BINDING_NAME_FOREVERCOACH_PLAN = L.BINDING_PLAN
BINDING_NAME_FOREVERCOACH_RECAP = L.BINDING_RECAP
BINDING_NAME_FOREVERCOACH_SETTINGS = L.BINDING_SETTINGS

function ForeverCoach_Binding(command)
    if ns.Commands then ns.Commands:Run(command) end
end

function ForeverCoach_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        ForeverCoach_Binding("toggle")
    else
        ForeverCoach_Binding("settings")
    end
end

-- Lifecycle: ADDON_LOADED -> settings ready (FC_INIT); PLAYER_LOGIN -> game data ready (FC_LOGIN).
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        ForeverCoachCharDB = copyDefaults(migrate(ForeverCoachCharDB or {}), ns.Defaults)
        ns.db = ForeverCoachCharDB
        ns.Events:Fire("FC_INIT")
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.Events:Fire("FC_LOGIN")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
