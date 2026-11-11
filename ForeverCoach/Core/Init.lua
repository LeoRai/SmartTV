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
    schema = 1,
    shown = true,          -- the "show or hide hints" key
    hideOutOfCombat = false,
    locked = true,
    tooltips = true,
    sound = false,         -- sound on proc, off by default
    debug = false,
    nextIcons = 1,         -- 0..2 icons after the main one
    scale = 1.0,
    alpha = 1.0,
    pos = { point = "CENTER", x = 0, y = -170 },
    mode = "auto",         -- auto | leveling | group | pvp
    hpThreshold = 35,      -- defense slot: player health, %
    petHpThreshold = 40,   -- defense slot: demon health, %
    shards = 3,            -- Soul Shards to keep
    minimap = { hide = false, angle = 215 },
    warnedData = {},       -- data versions already reported as outdated
}

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

function ns:ResetSettings()
    ns.wipe(ns.db)
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
        ForeverCoachCharDB = copyDefaults(ForeverCoachCharDB or {}, ns.Defaults)
        ns.db = ForeverCoachCharDB
        ns.Events:Fire("FC_INIT")
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        ns.Events:Fire("FC_LOGIN")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
