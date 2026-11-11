-- English strings. Also the fallback for every other locale:
-- a key missing in ruRU.lua is shown in English, a key missing here is shown as is.
local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ns.L = L

L.ADDON = "ForeverCoach"

-- Plural word for n: forms = { one, few, many }. English uses one / many; ruRU.lua overrides.
function ns.Plural(n, forms)
    return n == 1 and forms[1] or forms[3]
end

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
    "/fc minimap - show or hide the minimap button",
    "/fc mode auto | leveling | group | pvp - pin the mode",
    "/fc builds | plan | recap - windows (coming in later stages)",
    "/fc debug - print the reason for every hint",
    "/fc state - print the current game snapshot",
    "/fc perf - update timing",
    "/fc surprises - hints that jumped in unexpectedly (clear - forget them)",
    "/fc reset - reset position and settings",
}
L.HINTS_SHOWN = "Hints shown."
L.HINTS_HIDDEN = "Hints hidden."
L.LOCKED = "Hint block locked."
L.UNLOCKED = "Hint block unlocked: drag it, then /fc lock."
L.DEBUG_ON = "Debug on: the reason for each hint is printed to chat."
L.DEBUG_OFF = "Debug off."
L.RESET_DONE = "Settings reset."
L.MINIMAP_SHOWN = "Minimap button shown."
L.MINIMAP_HIDDEN = "Minimap button hidden: /fc minimap brings it back."
L.MODE_SET = "Mode: %s."
L.UNKNOWN_COMMAND = "Unknown command. /fc help for the list."
L.NOT_YET = "This window arrives in stage %d of the plan (see README)."
L.NO_CLASS_DATA = "No rotation data for your class yet: warlock comes first, other classes follow."
L.DATA_OUTDATED = "Rotation data was made for patch %s, the game is %s: some hints may be out of date."
L.PROFILE_ACTIVE = "Profile: %s%s"
L.PROFILE_APPROX = " (approximate)"
L.TF_CLOSEST = "Closest Talents Forever build: #%d %s %s, %d%% of your points match"
L.PERF = "Updates: %d, average %.3f ms, max %.3f ms."
L.LUA_ERROR = "Error in %s: %s"
L.BLOCKED = "The game blocked an action of the addon: %s. Please send this line to the developer."
L.DEBUG_PICK = "%s <- %s"
L.DEBUG_NONE = "no hint: %s"
L.HIDDEN_SUFFIX = " (hidden, assumed %s)"
L.SURPRISE_LINE = "%s, %.0f s into the fight: suddenly %s, the queue was %s. %s"
L.SURPRISES_NONE = "No unexpected hint changes so far."
L.SURPRISES_HEAD = "Unexpected hint changes: %d, the last %d below. They are saved in WTF\\Account\\<account>\\<realm>\\<character>\\SavedVariables\\ForeverCoach.lua: send that file to the developer."
L.SURPRISES_CLEARED = "The list of unexpected hint changes is cleared."
L.PRICE_UNKNOWN = "price unknown"
L.COIN_GOLD = "g"
L.COIN_SILVER = "s"
L.COIN_COPPER = "c"

-- Modes
L.MODE_auto = "Auto"
L.MODE_leveling = "Leveling"
L.MODE_group = "Group"
L.MODE_pvp = "PvP"

-- HUD
L.AOE = "AoE · %d %s"
L.ENEMY_FORMS = { "enemy", "enemies", "enemies" }
L.READY = "ready"
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
L.WHY_LIFE_TAP = "not enough mana for your next spell and enough health: convert health into mana"
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
L.WHY_AOE_HELLFIRE = "three or more enemies around you: Hellfire hits them all (it burns you too)"
L.WHY_PET_ATTACK = "your demon is idle"
L.WHY_PULL = "out of combat: open with a long cast"

-- Settings window (layout of the mockup: Look, Mode | Thresholds, Sound, Keys)
L.SETTINGS_TITLE = "Settings"
L.S_SECTION_LOOK = "LOOK"
L.S_ICON_SIZE = "Main icon size"
L.S_PX = "%d px"
L.S_ALPHA = "Opacity"
L.S_PERCENT = "%d%%"
L.S_NEXT = "Next icons"
L.S_HIDE_OOC = "Hide icons out of combat"
L.S_HIGHLIGHT = "Highlight the button on action bars"
L.S_SECTION_MODE = "MODE"
L.S_MODE_HELP = "Auto: battleground - PvP, dungeon or raid - group, everything else - leveling."
L.S_SECTION_THRESHOLDS = "THRESHOLDS"
L.S_HP = "Healthstone when health is below"
L.S_PET_HP = "Health Funnel when the demon is below"
L.S_SHARDS = "Soul Shards to keep"
L.S_SECTION_SOUND = "SOUND"
L.S_SOUND_READY = "\"Time to press\" - soft click"
L.S_SOUND_PROC = "Instant proc - bright chime"
L.S_VOLUME = "Volume"
L.S_SOUND_NOTE = "The click stays silent if the button was already pressed in advance."
L.S_SECTION_KEYS = "KEYS"
L.S_KEY_TOGGLE = "Show or hide hints"
L.S_KEY_WINDOWS = "Builds · Planner · Combat recap"
L.S_KEY_NONE = "not bound"
L.S_OPEN_KEYS = "Open key bindings"
L.S_FOOTER = "Builds: |cffF2C94CTalents Forever|r (baldwinbuilds), co-author · v%s"
L.S_RESET = "Reset"
L.S_DONE = "Done"

-- Minimap button
L.MINIMAP_TIP_LEFT = "Left click: settings"
L.MINIMAP_TIP_RIGHT = "Right click: show or hide hints"
L.MINIMAP_TIP_DRAG = "Drag: move the button"
