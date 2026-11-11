-- English strings. Also the fallback for every other locale:
-- a key missing in ruRU.lua is shown in English, a key missing here is shown as is.
local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.L = L

L.ADDON = "ForeverCoach"

-- Key bindings (Game Menu > Key Bindings > AddOns > ForeverCoach)
L.BINDING_HEADER = "ForeverCoach"
L.BINDING_TOGGLE = "Show or hide hints"
L.BINDING_BUILDS = "Builds window"
L.BINDING_PLAN = "Planner window"
L.BINDING_RECAP = "Combat recap window"
L.BINDING_SETTINGS = "Settings"

-- Chat
L.LOADED = "ForeverCoach %s loaded. /fc for settings, /fc help for commands."
L.HELP = {
    "/fc - settings",
    "/fc toggle - show or hide hints",
    "/fc lock | unlock - lock or move the hint block",
    "/fc mode auto | leveling | group | pvp - pin the mode",
    "/fc builds | plan | recap - windows (coming in later stages)",
    "/fc debug - print the reason for every hint",
    "/fc state - print the current game snapshot",
    "/fc perf - update timing",
    "/fc reset - reset position and settings",
}
L.HINTS_SHOWN = "Hints shown."
L.HINTS_HIDDEN = "Hints hidden."
L.LOCKED = "Hint block locked."
L.UNLOCKED = "Hint block unlocked: drag it, then /fc lock."
L.DEBUG_ON = "Debug on: the reason for each hint is printed to chat."
L.DEBUG_OFF = "Debug off."
L.RESET_DONE = "Settings reset."
L.MODE_SET = "Mode: %s."
L.UNKNOWN_COMMAND = "Unknown command. /fc help for the list."
L.NOT_YET = "This window arrives in stage %d of the plan (see README)."
L.NO_CLASS_DATA = "No rotation data for your class yet: warlock comes first, other classes follow."
L.DATA_OUTDATED = "Rotation data was made for patch %s, the game is %s: some hints may be out of date."
L.PROFILE_ACTIVE = "Profile: %s%s"
L.PROFILE_APPROX = " (approximate)"
L.PERF = "Updates: %d, average %.3f ms, max %.3f ms."
L.LUA_ERROR = "Error in %s: %s"
L.DEBUG_PICK = "%s <- %s"
L.DEBUG_NONE = "no hint: %s"
L.HIDDEN_SUFFIX = " (hidden, assumed %s)"

-- Modes
L.MODE_auto = "Auto"
L.MODE_leveling = "Leveling"
L.MODE_group = "Dungeons and raids"
L.MODE_pvp = "PvP"

-- HUD
L.AOE = "AoE"
L.WHY = "Why: %s"
L.PROFILE = "Profile: %s"
L.OUT_OF_RANGE = "Out of range"
L.NO_MANA = "Not enough mana"
L.UNLOCKED_LABEL = "ForeverCoach\ndrag me"

-- Preparation line (out of combat, one item at a time)
L.PREP_NO_PET = "Demon not summoned"
L.PREP_NO_HEALTHSTONE = "No Healthstone"
L.PREP_NO_ARMOR = "No demon armor"
L.PREP_FEW_SHARDS = "Few Soul Shards: %d"
L.PREP_TRAINER = "Spells waiting at the trainer: %d"

-- Why this action (tooltips on the hint icons)
L.WHY_FILLER = "filler: nothing more important right now"
L.WHY_DOT = "your damage-over-time effect is missing or about to expire, and the target will live long enough"
L.WHY_CURSE = "your curse is missing on the target"
L.WHY_PROC = "proc: the next cast is instant"
L.WHY_EXECUTE_SHARD = "the target is almost dead: channel Drain Soul to get a Soul Shard"
L.WHY_LIFE_TAP = "low mana and enough health: convert health into mana"
L.WHY_DRAIN_LIFE = "your health is low: heal through damage"
L.WHY_WAND = "save mana: finish the target with your wand"
L.WHY_WAND_OOM = "out of mana: use your wand"
L.WHY_HEALTHSTONE = "health below the threshold: use a Healthstone"
L.WHY_POTION = "health below the threshold and no Healthstone: drink a potion"
L.WHY_DEATH_COIL = "health below the threshold: Death Coil heals and stops the enemy"
L.WHY_SACRIFICE = "the Voidwalker is dying: sacrifice it for a shield"
L.WHY_HEALTH_FUNNEL = "your demon is dying: heal it"
L.WHY_FEAR_SECOND = "a second enemy is on you: target it and Fear it"
L.WHY_HOWL = "three or more enemies close by: fear them all"
L.WHY_AMPLIFY = "strong enemy: amplify your curse before casting it"
L.WHY_AOE_RAIN = "three or more enemies: area damage"
L.WHY_PET_ATTACK = "your demon is idle"
L.WHY_DARK_PACT = "low mana: take it from your demon instead of your health"
L.WHY_PULL = "out of combat: open with a long cast"

-- Settings window
L.SETTINGS_TITLE = "ForeverCoach settings"
L.S_SHOW = "Show hints"
L.S_HIDE_OOC = "Hide the hint block out of combat (keep the preparation line)"
L.S_LOCKED = "Lock position"
L.S_TOOLTIPS = "Explain hints on mouseover"
L.S_SOUND = "Sound on proc"
L.S_MINIMAP = "Minimap button"
L.S_DEBUG = "Debug: print the reason for each hint"
L.S_NEXT = "Next icons: %d"
L.S_SCALE = "Size: %d%%"
L.S_ALPHA = "Opacity: %d%%"
L.S_HP = "Defense when health below: %d%%"
L.S_PET_HP = "Help the demon when its health below: %d%%"
L.S_SHARDS = "Keep Soul Shards: %d"
L.S_MODE = "Mode: %s"
L.S_RESET_POS = "Reset position"
L.S_SECTION_LOOK = "Look"
L.S_SECTION_THRESHOLDS = "Thresholds"
L.S_SECTION_MODE = "Mode"

-- Minimap button
L.MINIMAP_TIP_LEFT = "Left click: settings"
L.MINIMAP_TIP_RIGHT = "Right click: show or hide hints"
L.MINIMAP_TIP_DRAG = "Drag: move the button"
