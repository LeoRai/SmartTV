-- Class quests by level. "Done" = the spell the quest gives is known.
-- Quest names come from Locales (QUEST_<key>), quest IDs are filled after the stage 0 dump.
local ADDON, ns = ...

ns.Data:DefineQuests({ version = "0.1.0", patch = "1.60.1", date = "2026-11-11" }, {
    { class = "WARLOCK", key = "voidwalker", level = 10, gives = "summon_voidwalker", start = "trainer" },
    { class = "WARLOCK", key = "succubus", level = 20, gives = "summon_succubus", start = "trainer" },
    { class = "WARLOCK", key = "felhunter", level = 30, gives = "summon_felhunter", start = "trainer" },
    { class = "WARLOCK", key = "felsteed", level = 40, gives = "summon_felsteed", start = "trainer" },
})
