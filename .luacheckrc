-- luacheck config: WoW client globals the addon reads, globals it defines, busted in tests.
std = "lua51"
max_line_length = false
codes = true
ignore = {
    "211/ADDON",  -- every file unpacks (ADDON, ns) from the addon vararg
    "212/self",   -- method signatures kept uniform
    "212/_.*",
    "212/event",
}

globals = {
    -- defined by ForeverCoach
    "ForeverCoachCharDB", "ForeverCoach_Binding", "ForeverCoach_OnAddonCompartmentClick",
    "BINDING_HEADER_FOREVERCOACH", "BINDING_NAME_FOREVERCOACH_TOGGLE", "BINDING_NAME_FOREVERCOACH_BUILDS",
    "BINDING_NAME_FOREVERCOACH_PLAN", "BINDING_NAME_FOREVERCOACH_RECAP", "BINDING_NAME_FOREVERCOACH_SETTINGS",
    "SLASH_FOREVERCOACH1", "SLASH_FOREVERCOACH2", "SlashCmdList", "UISpecialFrames",
    -- defined by ForeverCoach_Probe
    "ForeverCoachProbeDB", "SLASH_FCPROBE1",
}

read_globals = {
    -- client API used by the addons
    "C_AddOns", "GetAddOnMetadata", "DEFAULT_CHAT_FRAME", "CreateFrame", "UIParent", "Minimap", "GameTooltip",
    "GetTime", "debugprofilestop", "GetLocale", "GetBuildInfo", "issecretvalue", "canaccessvalue", "C_Secrets",
    "C_Spell", "GetSpellInfo", "GetSpellTexture", "IsPlayerSpell", "IsSpellKnown", "C_SpellBook", "Enum",
    "GetSpellCooldown", "IsUsableSpell", "IsSpellInRange", "UnitHealth", "UnitHealthMax", "UnitPower",
    "UnitPowerMax", "UnitExists", "UnitCanAttack", "UnitIsDeadOrGhost", "UnitAffectingCombat", "UnitGUID",
    "UnitClassification", "UnitLevel", "UnitIsPlayer", "UnitIsUnit", "UnitClass", "UnitCreatureFamily",
    "GetUnitSpeed", "UnitCastingInfo", "UnitChannelInfo", "C_UnitAuras", "UnitAura", "C_Item", "GetItemCount",
    "C_Container", "GetItemCooldown", "GetItemIcon", "HasWandEquipped", "GetNumTalentTabs", "GetNumTalents",
    "GetTalentInfo", "GetTalentLink", "GetTalentTabInfo", "GetActiveTalentGroup", "GetActiveSpecGroup",
    "GetNumTalentGroups", "C_Traits", "C_ClassTalents", "IsInInstance", "C_NamePlate", "InCombatLockdown",
    "GetActionInfo", "GetMacroSpell", "GetBindingKey", "C_ActionBar", "PlaySound", "SOUNDKIT",
    "GetCursorPosition", "C_AssistedCombat", "CombatLogGetCurrentEventInfo", "GetNumTrainerServices",
    "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceLevelReq", "C_TooltipInfo",
    "GetSpellBookItemInfo", "GetSpellBookItemName", "GetNumSpellTabs", "GetSpellTabInfo", "GetPetActionInfo",
    "UnitThreatSituation", "IsInGroup", "IsInRaid", "C_PvP", "C_Timer", "wipe", "WOW_PROJECT_ID",
    "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC", "newproxy", "GetQuestsCompleted", "C_QuestLog",
    "UnitName", "GetRealZoneText", "C_Map", "date", "Settings", "AuraUtil", "canaccesssecrets",
    "GetBindingText", "KeyBindingFrame_LoadUI", "KeyBindingFrame", "ShowUIPanel", "PlaySoundFile",
    "STANDARD_TEXT_FONT", "IsTradeskillTrainer", "GetSubZoneText",
}

files["tests/"] = { std = "+busted" }
files["tools/"] = { std = "+lua51" }
