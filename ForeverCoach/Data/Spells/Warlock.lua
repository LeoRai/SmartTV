-- Warlock: spells, ranks, buffs, talents, items.
-- IDs only: names and icons come from the client, so the Russian client shows Russian names.
--
-- STATUS: IDs and levels are the Classic Era values (Warcraft Tavern, Classic database).
-- Forever reworked many talents and may have moved some ranks: the stage 0 probe
-- (ForeverCoach_Probe, /fcprobe dump) exports the real spellbook, talents and trainer
-- prices, and this file gets corrected from that dump. Prices are filled the same way.
local ADDON, ns = ...

ns.Data:DefineClass("WARLOCK", function()
    return {
        name = "Warlock",
        version = "0.1.0",
        patch = "1.60.1",
        date = "2026-11-11",
        verified = false, -- true once checked against the stage 0 dump
        trees = { "Affliction", "Demonology", "Destruction" },
        filler = "shadow_bolt", -- used for range and "out of mana" checks
        gcd = 1.5,

        spells = {
            -- Damage -------------------------------------------------------
            shadow_bolt = {
                role = "filler", source = "trainer", consumes = "shadow_trance",
                cast = { 1.7, 2.2, 2.8, 3.0 },
                ranks = { {686, 1}, {695, 6}, {705, 12}, {1088, 20}, {1106, 28}, {7641, 36},
                          {11659, 44}, {11660, 52}, {11661, 60}, {25307, 60, "book"} },
            },
            immolate = {
                role = "dot", source = "trainer", cast = 2.0, duration = 15,
                ranks = { {348, 1}, {707, 10}, {1094, 20}, {2941, 30}, {11665, 40}, {11667, 50},
                          {11668, 60}, {25309, 60, "book"} },
            },
            corruption = {
                role = "dot", source = "trainer", cast = 2.0, duration = { 12, 15, 18 },
                ranks = { {172, 4}, {6222, 14}, {6223, 24}, {7648, 34}, {11671, 44}, {11672, 54},
                          {25311, 60, "book"} },
            },
            curse_of_agony = {
                role = "curse", source = "trainer", duration = 24,
                ranks = { {980, 8}, {1014, 18}, {6217, 28}, {11711, 38}, {11712, 48}, {11713, 58} },
            },
            curse_of_weakness = {
                role = "curse", source = "trainer", duration = 120,
                ranks = { {702, 4}, {1108, 12}, {6205, 22}, {7646, 32}, {11707, 42}, {11708, 52} },
            },
            curse_of_doom = {
                role = "cooldown", harmful = true, source = "trainer", duration = 60, cooldown = 60,
                ranks = { {603, 60} },
            },
            siphon_life = {
                role = "dot", source = "trainer", talent = "siphon_life", duration = 30,
                ranks = { {18265, 30, "talent"}, {18879, 38}, {18880, 48}, {18881, 58} },
            },
            drain_soul = {
                role = "execute", source = "trainer", channel = true, cast = 15,
                ranks = { {1120, 10}, {8288, 24}, {8289, 38}, {11675, 52} },
            },
            drain_life = {
                role = "drain", source = "trainer", channel = true, cast = 5,
                ranks = { {689, 14}, {699, 22}, {709, 30}, {7651, 38}, {11699, 46}, {11700, 54} },
            },
            searing_pain = {
                role = "filler", source = "trainer", cast = 1.5,
                ranks = { {5676, 18}, {17919, 26}, {17920, 34}, {17921, 42}, {17922, 50}, {17923, 58} },
            },
            soul_fire = {
                role = "cooldown", harmful = true, source = "trainer", cast = 6.0, cooldown = 60,
                ranks = { {6353, 48}, {17924, 56} },
            },
            shadowburn = {
                role = "execute", source = "trainer", talent = "shadowburn", cooldown = 15,
                ranks = { {17877, 20, "talent"}, {18867, 24}, {18868, 32}, {18869, 40}, {18870, 48}, {18871, 56} },
            },
            conflagrate = {
                role = "filler", source = "trainer", talent = "conflagrate", cooldown = 10, requires = "immolate",
                ranks = { {17962, 40, "talent"}, {18930, 48}, {18931, 54}, {18932, 60} },
            },
            rain_of_fire = {
                role = "aoe", source = "trainer", channel = true, cast = 8,
                ranks = { {5740, 20}, {6219, 34}, {11677, 46}, {11678, 58} },
            },
            hellfire = {
                role = "aoe", source = "trainer", channel = true, cast = 15,
                ranks = { {1949, 30}, {11683, 42}, {11684, 54} },
            },
            shoot = {
                role = "wand", source = "class", wand = true, cast = 1.5,
                ranks = { {5019, 1} },
            },

            -- Control and defense ----------------------------------------------
            fear = {
                role = "cc", source = "trainer", cast = 1.5, duration = { 10, 15, 20 },
                ranks = { {5782, 8}, {6213, 32}, {6215, 56} },
            },
            howl_of_terror = {
                role = "defense", harmful = false, source = "trainer", cast = 2.0, cooldown = 40,
                ranks = { {5484, 40}, {17928, 54} },
            },
            death_coil = {
                role = "defense", harmful = true, source = "trainer", cooldown = 120,
                ranks = { {6789, 42}, {17925, 50}, {17926, 58} },
            },
            sacrifice = { -- Voidwalker ability, learned from grimoires
                role = "defense", source = "book", pet = true, petFamily = "voidwalker", gcd = false,
                ranks = { {7812, 16}, {19438, 24}, {19440, 32}, {19441, 40}, {19442, 48}, {19443, 56} },
            },

            -- Resources ---------------------------------------------------------
            life_tap = {
                role = "utility", source = "trainer",
                ranks = { {1454, 6}, {1455, 16}, {1456, 26}, {11687, 36}, {11688, 46}, {11689, 56} },
            },
            dark_pact = {
                role = "utility", source = "trainer", talent = "dark_pact",
                ranks = { {18220, 40, "talent"}, {18937, 50}, {18938, 60} },
            },
            amplify_curse = {
                role = "cooldown", source = "talent", talent = "amplify_curse", cooldown = 180, gcd = false,
                ranks = { {18288, 20} },
            },

            -- Demons ------------------------------------------------------------
            health_funnel = {
                role = "pet", source = "trainer", channel = true, cast = 10,
                ranks = { {755, 12}, {3698, 20}, {3699, 28}, {3700, 36}, {11693, 44}, {11694, 52}, {11695, 60} },
            },
            summon_imp = { role = "summon", source = "class", cast = 10, ranks = { {688, 1} } },
            summon_voidwalker = { role = "summon", source = "quest", cast = 10, ranks = { {697, 10} } },
            summon_succubus = { role = "summon", source = "quest", cast = 10, ranks = { {712, 20} } },
            summon_felhunter = { role = "summon", source = "quest", cast = 10, ranks = { {691, 30} } },
            summon_felsteed = { role = "utility", source = "quest", cast = 3, ranks = { {5784, 40} } },

            -- Self buffs and stones ----------------------------------------------
            demon_skin = { role = "buff", source = "class", buff = "armor", ranks = { {687, 1}, {696, 10} } },
            demon_armor = {
                role = "buff", source = "trainer", buff = "armor",
                ranks = { {706, 20}, {1086, 30}, {11733, 40}, {11734, 50}, {11735, 60} },
            },
            create_healthstone = { -- Minor, Lesser, normal, Greater, Major
                role = "utility", source = "trainer", cast = 3,
                ranks = { {6201, 10}, {6202, 22}, {5699, 34}, {11729, 46}, {11730, 58} },
            },
        },

        -- Buffs on the player. glow: the client highlights this spell while the buff is up
        -- (fallback when auras are hidden in combat).
        buffs = {
            shadow_trance = { ids = { 17941 }, glow = "shadow_bolt", duration = 10 },
            armor = { ids = {}, duration = 1800 }, -- Demon Skin / Demon Armor add their IDs
        },

        -- Talents: rank = highest known ID (IsPlayerSpell), else matched by name in the talent frame.
        talents = {
            nightfall = { ids = { 18094, 18095 }, tree = 1 },
            siphon_life = { ids = { 18265 }, tree = 1 },
            amplify_curse = { ids = { 18288 }, tree = 1 },
            dark_pact = { ids = { 18220 }, tree = 1 },
            fel_domination = { ids = { 18708 }, tree = 2 },
            demonic_sacrifice = { ids = { 18788 }, tree = 2 },
            soul_link = { ids = { 19028 }, tree = 2 },
            shadowburn = { ids = { 17877 }, tree = 3 },
            conflagrate = { ids = { 17962 }, tree = 3 },
        },

        -- Items: ids from best to worst; the best one in the bags is used.
        items = {
            healthstone = {
                role = "defense",
                ids = { 9421, 19013, 19012, 5510, 19011, 19010, 5509, 19009, 19008,
                        5511, 19007, 19006, 5512, 19005, 19004 },
            },
            healing_potion = { role = "defense", ids = { 13446, 3928, 1710, 929, 4596, 858, 118 } },
            soul_shard = { role = "reagent", ids = { 6265 } },
        },

        -- Demons: summon spell and creature family names (UnitCreatureFamily, enUS and ruRU).
        pets = {
            imp = { summon = "summon_imp", names = { "Imp", "Бес" } },
            voidwalker = { summon = "summon_voidwalker", names = { "Voidwalker", "Демон Бездны", "Демон бездны" } },
            succubus = { summon = "summon_succubus", names = { "Succubus", "Суккуб" } },
            felhunter = { summon = "summon_felhunter", names = { "Felhunter", "Охотник Скверны", "Охотник скверны" } },
        },
    }
end)
