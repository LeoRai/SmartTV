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
    "/fc builds - builds window (Talents Forever)",
    "/fc plan - planner: trainer, talents, level preview",
    "/fc recap - combat recap: the last 10 fights and the session",
    "/fc nohints - no-hints mode: the block hides, the recap keeps counting",
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
L.AOE = "AoE: %d %s"
L.ENEMY_FORMS = { "enemy", "enemies", "enemies" }
L.READY = "ready"
L.WHY = "Why: %s"
L.PROFILE = "Profile: %s"
L.OUT_OF_RANGE = "Out of range"
-- A line under the block for a hint the client shows by hidden health or mana (gate alert)
L.ALERT_LOW_MANA = "Low mana"
L.ALERT_EXECUTE = "Target almost dead"
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
L.S_KEY_WINDOWS = "Builds, planner, combat recap"
L.S_KEY_NONE = "not bound"
L.S_OPEN_KEYS = "Open key bindings"
L.S_FOOTER = "Builds: |cffF2C94CTalents Forever|r (baldwinbuilds), co-author, v%s"
L.S_RESET = "Reset"
L.S_DONE = "Done"

-- Minimap button
L.MINIMAP_TIP_LEFT = "Left click: settings"
L.MINIMAP_TIP_RIGHT = "Right click: show or hide hints"
L.MINIMAP_TIP_DRAG = "Drag: move the button"

-- Numbers: 4,884
L.THOUSANDS = ","

-- Talent trees (Talents Forever names them in English)
L.TREE_Affliction = "Affliction"
L.TREE_Demonology = "Demonology"
L.TREE_Destruction = "Destruction"

-- Class quests
L.QUEST_voidwalker = "Voidwalker"
L.QUEST_succubus = "Succubus"
L.QUEST_felhunter = "Felhunter"
L.QUEST_felsteed = "Felsteed"

-- What a spell is for, in the planner (optional: a spell without a note shows its name only)
L.NOTE_drain_life = "heals you at the enemy's cost"
L.NOTE_health_funnel = "heals the demon"
L.NOTE_life_tap = "health into mana"
L.NOTE_fear = "takes an enemy out for a while"
L.NOTE_drain_soul = "a Soul Shard from a dying enemy"
L.NOTE_corruption = "damage over time, instant"
L.NOTE_curse_of_agony = "curse: damage over time"
L.NOTE_curse_of_weakness = "curse: the enemy hits softer"
L.NOTE_immolate = "fire damage and burning"
L.NOTE_siphon_life = "damage over time that heals you"
L.NOTE_rain_of_fire = "damage in an area"
L.NOTE_hellfire = "damage around you, hurts you too"
L.NOTE_death_coil = "heals you and frightens the enemy"
L.NOTE_howl_of_terror = "frightens the enemies around you"
L.NOTE_shadowburn = "instant finisher"
L.NOTE_conflagrate = "burns Immolate away for a burst"
L.NOTE_incinerate = "fire nuke, stronger on a burning target"
L.NOTE_searing_pain = "fast fire nuke"
L.NOTE_soul_fire = "big fire nuke for a Soul Shard"
L.NOTE_create_healthstone = "a stone that heals"
L.NOTE_demon_armor = "armor and health regeneration"
L.NOTE_amplify_curse = "a stronger next curse"
L.NOTE_curse_of_doom = "a huge hit after a minute"

-- Builds window
L.BUILDS_TITLE = "Builds"
L.B_TAB_all = "All"
L.B_TAB_leveling = "Leveling"
L.B_TAB_group = "PvE"
L.B_TAB_pvp = "PvP"
L.B_PASTE = "Paste a link"
L.B_SUBTITLE = "Popular builds from Talents Forever, updated daily"
L.B_SUBTITLE_ASOF = "Popular builds from Talents Forever, updated daily (data of %s)"
L.B_YOURS = "Yours"
L.B_CHOSEN = "Chosen"
L.B_LINK = "link"
L.B_STATS = "Saved %s, opened %s, %s similar builds"
L.B_STATS_LINK = "Build from a link"
L.B_ROTATION = "ROTATION FOR THIS BUILD"
L.B_ON_PROC = "%s\non proc"
L.B_COMPARE = "COMPARED WITH YOUR TALENTS"
L.B_ALL_MATCH = { "Your %d point matches the build", "All %d points match the build", "All %d points match the build" }
L.B_NO_POINTS = "No talent points invested yet"
L.B_SOME_MATCH = "%d of %d points match the build"
L.B_NEXT_AT = "Next point at level %d: %s"
L.B_NEXT_NOW = "Free point now: %s"
L.B_DONE = "The build is complete"
L.B_SPEC = "Spec %d"
L.B_SPEC2_LOCKED = "Spec 2 (from %d)"
L.B_CHOOSE = "Choose build"
L.B_UNCHOOSE = "Cancel choice"
L.B_FOOTER = "Builds: |cffF2C94CTalents Forever|r (baldwinbuilds), co-author, CC BY 4.0"
L.B_NO_TF = "Builds come from the Talents Forever addon (TalentsForeverBook). Install it and the popular builds appear here."
L.B_EMPTY_TAB = "No builds in this list yet."
L.B_PASTE_HINT = "Paste a Talents Forever link or code, then press Enter"
L.B_BAD_LINK = "That does not look like a Talents Forever link or code."
L.B_AUTO = "No build chosen: the rotation follows your talents."
L.B_CHOSEN_MSG = "Spec %d: build %s %s chosen."
L.B_UNCHOSEN_MSG = "Spec %d: no build chosen, the rotation follows your talents."

-- Planner window
L.PLANNER_TITLE = "Planner"
L.P_LEVEL = "level %d"
L.P_TRAINER_WAITS = { "%d spell waits at the trainer", "%d spells wait at the trainer", "%d spells wait at the trainer" }
L.P_TRAINER_NONE = "Nothing new at the trainer"
L.P_TRAINER_NEXT = "next at level %d"
L.P_TRAINER_UNKNOWN = "visit your class trainer once and the addon remembers where"
L.P_NEEDS = "WHAT THE BUILD'S ROTATION NEEDS"
L.P_NEEDS_NONE = "Everything is learned and on the bars."
L.P_MORE = "and %d more"
L.P_RANK = ", rank %d"
L.P_ST_trainer = "At trainer"
L.P_ST_talent = "Talent"
L.P_ST_nobar = "Not on bars"
L.P_ST_level = "Lvl %d"
L.P_ST_quest = "Quest, %d"
L.P_SUB_TALENT_NOW = { "%d free talent point", "%d free talent points", "%d free talent points" }
L.P_SUB_TALENT_AT = "Talent point at level %d"
L.P_SUB_TALENT_SPELL = "Comes from a talent of the build"
L.P_SUB_NOBAR = "Learned, but not on the action bars"
L.P_SUB_LEVEL = { "Opens in %d level", "Opens in %d levels", "Opens in %d levels" }
L.P_SUB_QUEST = "Class quest, starts at the trainer"
L.P_PREVIEW = "LEVEL PREVIEW"
L.P_NEW_AT = "New at level %d"
L.P_NOTHING_NEW = "Nothing new at this level"
L.P_RANKS_MORE = { "%d new rank", "%d new ranks", "%d new ranks" }
L.P_ROTATION_AT = "Rotation at level %d"
L.P_QUESTS = "CLASS QUESTS"
L.P_QUEST_DONE = "done"

L.MINIMAP_TIP_SHIFT = "Shift+click: builds"
L.MINIMAP_TIP_CTRL = "Ctrl+click: planner"
L.MINIMAP_TIP_ALT = "Alt+click: combat recap"

-- Combat recap window (stage 3)
L.DECIMAL = "."
L.RECAP_TITLE = "Combat recap"
L.R_SAMPLE = "Sample data"
L.R_TAB_fights = "Recent fights"
L.R_TAB_session = "Session"
L.R_TAB_records = "Records"
L.R_NO_TARGET = "No target"
L.R_FIGHT_META = "fight %s, %s"
L.R_BLIND = ", without hints"
L.R_ACCURACY = "Accuracy"
L.R_ACCURACY_SUB = "%d of %d presses"
L.R_UPTIME = "Debuffs on target"
L.R_UPTIME_SUB = "of the fight"
L.R_UPTIME_NONE = "none asked for"
L.R_IDLE = "Idle"
L.R_IDLE_VALUE = "%s s"
L.R_PAUSES = { "%d pause", "%d pauses", "%d pauses" }
L.R_PROCS = "Missed procs"
L.R_PROCS_SUB = { "of %d proc", "of %d procs", "of %d procs" }
L.R_PROCS_NONE = "no procs this fight"
L.R_PROCS_TALENT_AT = "%s from level %d"
L.R_PROCS_TALENT = "needs the talent %s"
L.R_TIMELINE = "PRESSES OVER TIME"
L.R_LEGEND_OK = "as hinted"
L.R_LEGEND_OTHER = "otherwise"
L.R_LEGEND_IDLE = "idle"
L.R_ERRORS = "MISTAKES"
L.R_NO_ERRORS = "No mistakes in this fight."
L.R_MORE_ERRORS = "and %d more"
L.R_ERR_MISS = "%s instead of the hinted %s"
L.R_ERR_IDLE = "Idle %s s"
L.R_IDLE_HINT = "%s was ready"
L.R_WHY_DOWN = "it was not on the target"
L.R_WHY_LOW = "it was about to run out"
L.R_WHY_PROC = "a proc made it instant"
L.R_WHY_MANA = "out of mana"
L.R_WHY_AOE = { "%d enemy around", "%d enemies around", "%d enemies around" }
L.R_SESSION = "Session:"
L.R_FIGHTS = { "%d fight", "%d fights", "%d fights" }
L.R_SESSION_AVG = "average accuracy %s"
L.R_SESSION_PREV = "last session %s"
L.R_SESSION_NO_PREV = "no earlier session"
L.R_SESSION_NONE = "no fights recorded yet this session"
L.R_SESSION_TITLE = "THIS SESSION"
L.R_SESSION_BLIND = "Without hints: %s, accuracy %s"
L.R_SESSION_BLIND_NONE = "Without hints: no fights yet. Try the mode below to check what you remember."
L.R_SESSIONS_PAST = "EARLIER SESSIONS"
L.R_SESSIONS_NONE = "No earlier sessions yet."
L.R_RECORDS_TITLE = "RECORDS BY BUILD"
L.R_RECORD_SUB = "accuracy %d%%, speed %d%%, %s"
L.R_RECORDS_NONE = "No records yet: turn on Training, and after every fight you get a score; the best one per build is kept."
L.R_SCORE_HELP = "Score: accuracy times speed, up to 1000. Speed is 100% when you press within 0.3 s of the moment you could, and falls to 50% at 1.5 s."
L.R_EMPTY = "No fights yet: fight longer than %d s and the recap appears here."
L.R_NOHINTS = "No-hints mode"
L.R_NOHINTS_NOTE = "icons hidden, the recap keeps counting"
L.R_TRAINING = "Training"
L.R_TRAINING_ON = "Training: on"
L.R_TRAINING_STARTED = "Training on: after every fight you get a score for accuracy and speed, the best one is the build's record."
L.R_TRAINING_STOPPED = "Training off."
L.R_TRAINING_RESULT = "Training: %d (accuracy %d%%, speed %d%%). Build record: %d."
L.R_TRAINING_RECORD = "Training: %d (accuracy %d%%, speed %d%%), a new build record!"
L.R_NOHINTS_ON = "No-hints mode: the hint block is hidden, the combat recap keeps counting. /fc nohints turns it off."
L.R_NOHINTS_OFF = "Hints are shown again."
L.R_SAMPLE_TARGETS = { "Scarlet Warrior", "Scarlet Warrior", "Rotting Dead", "Rotting Dead", "Vampire Bat",
                       "Scarlet Recruit", "Scarlet Recruit", "Spider", "Spider", "Scarlet Warrior" }
L.S_SECTION_RECAP = "COMBAT RECAP"
L.S_MIN_FIGHT = "Skip fights shorter than, s"
