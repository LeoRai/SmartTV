-- Warlock: spells, ranks, buffs, talents, items.
-- IDs only: names and icons come from the client, so the Russian client shows Russian names.
--
-- STATUS: checked against the stage 0 dump (Forever 1.60.1 build 70888, level 12, Undercity
-- trainer): every trainer rank from level 14 to 60 has the ID, level and price below.
-- Forever changes found there: Conflagrate is a trainer spell from 32 (new rank 1), Incinerate
-- is new at 50, Curse of the Elements has new IDs, Dark Pact is gone. Ranks below level 12
-- were already learned and match the spellbook. Demon abilities other than the Voidwalker's
-- are still unverified.
local ADDON, ns = ...

ns.Data:DefineClass("WARLOCK", function()
    return {
        name = "Warlock",
        version = "0.1.0",
        patch = "1.60.1",
        date = "2026-11-11",
        verified = true, -- checked against the stage 0 dump, see STATUS above
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
            conflagrate = { -- Forever: rank 1 from the talent (Destruction row 4: level 25 at the earliest),
                -- the trainer sells the next ranks to those who have it (stage 0 dump). Burns Immolate
                -- away, unless Shadow and Flame is full (Talents Forever text of that talent).
                role = "filler", source = "trainer", talent = "conflagrate", cooldown = 10, requires = "immolate",
                consumesDebuff = "immolate", keepsDebuff = { talent = "shadow_and_flame", rank = 5 },
                ranks = { {1293817, 25, "talent"}, {1293818, 32}, {17962, 40}, {18930, 48}, {18931, 54}, {18932, 60} },
            },
            incinerate = { -- new in Forever: the last talent of Destruction (row 7: level 40 at the earliest),
                -- the trainer sells ranks 2 and 3. Not in any rotation yet: Talents Forever has no text for it.
                role = "filler", source = "trainer", talent = "incinerate", cast = 2.5,
                ranks = { {412758, 40, "talent"}, {1293812, 50}, {1293813, 60} },
            },
            rain_of_fire = {
                role = "aoe", source = "trainer", channel = true, cast = 8,
                ranks = { {5740, 20}, {6219, 34}, {11677, 46}, {11678, 58} },
            },
            hellfire = {
                role = "aoe", source = "trainer", channel = true, cast = 15,
                ranks = { {1949, 30}, {11683, 42}, {11684, 54} },
            },
            shoot = { -- auto-repeat: every shot reports success, none of them restarts the global cooldown
                role = "wand", source = "class", wand = true, cast = 1.5, gcd = false,
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
                role = "utility", source = "trainer", restoresMana = true,
                ranks = { {1454, 6}, {1455, 16}, {1456, 26}, {11687, 36}, {11688, 46}, {11689, 56} },
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

            -- Not in the rotation, but sold by the trainer: needed for an exact trainer summary.
            curse_of_recklessness = {
                role = "curse", source = "trainer", duration = 120,
                ranks = { {704, 14}, {7658, 28}, {7659, 42}, {11717, 56} },
            },
            curse_of_elements = { -- Forever IDs
                role = "curse", source = "trainer", duration = 300,
                ranks = { {440892, 20}, {1311676, 30}, {1311677, 40}, {1311680, 50} },
            },
            curse_of_tongues = { role = "curse", source = "trainer", duration = 30, ranks = { {1714, 26}, {11719, 50} } },
            drain_mana = { role = "utility", source = "trainer", harmful = true, channel = true, cast = 5,
                           ranks = { {5138, 24}, {6226, 34}, {11703, 44}, {11704, 54} } },
            banish = { role = "cc", harmful = false, source = "trainer", cast = 1.5, ranks = { {710, 28}, {18647, 48} } },
            enslave_demon = { role = "utility", source = "trainer", cast = 3, ranks = { {1098, 30}, {11725, 44}, {11726, 58} } },
            shadow_ward = { role = "defense", source = "trainer", cooldown = 30, ranks = { {6229, 32}, {11739, 42}, {11740, 52} } },
            unending_breath = { role = "utility", source = "trainer", ranks = { {5697, 16} } },
            ritual_of_summoning = { role = "utility", source = "trainer", ranks = { {698, 20} } },
            eye_of_kilrogg = { role = "utility", source = "trainer", ranks = { {126, 22} } },
            sense_demons = { role = "utility", source = "trainer", ranks = { {5500, 24} } },
            detect_invisibility = { role = "utility", source = "trainer", ranks = { {132, 26}, {2970, 38}, {11743, 50} } },
            create_soulstone = { role = "utility", source = "trainer", cast = 3,
                                 ranks = { {693, 18}, {20752, 30}, {20755, 40}, {20756, 50}, {20757, 60} } },
            create_firestone = { role = "utility", source = "trainer", cast = 3,
                                 ranks = { {6366, 28}, {17951, 36}, {17952, 46}, {17953, 56} } },
            create_spellstone = { role = "utility", source = "trainer", cast = 5, ranks = { {2362, 36}, {17727, 48}, {17728, 60} } },
        },

        -- Trainer prices in copper, from the stage 0 dump (ranks from level 14 up).
        costs = {
            [6222] = 1000, [689] = 1000, [704] = 1000, [1455] = 1600, [5697] = 1600, [1014] = 1700,
            [5676] = 1700, [693] = 1700, [706] = 2500, [1094] = 2500, [3698] = 2500, [5740] = 2500,
            [440892] = 2500, [698] = 2500, [1088] = 2500, [126] = 3800, [699] = 3800, [6205] = 3800,
            [6202] = 3800, [18867] = 4800, [6223] = 4800, [8288] = 4800, [5138] = 4800, [5500] = 4800,
            [17919] = 5000, [1456] = 5000, [132] = 5000, [1714] = 5000, [6217] = 6000, [710] = 6000,
            [3699] = 6000, [7658] = 6000, [6366] = 6000, [1106] = 6000, [1949] = 7000, [1086] = 7000,
            [2941] = 7000, [1098] = 7000, [709] = 7000, [1311676] = 7000, [20752] = 7000, [6229] = 8000,
            [18868] = 8000, [1293818] = 8000, [7646] = 8000, [6213] = 8000, [17920] = 9000, [6219] = 9000,
            [7648] = 9000, [6226] = 9000, [5699] = 9000, [11687] = 10000, [3700] = 10000, [17951] = 10000,
            [2362] = 10000, [7641] = 10000, [11711] = 11000, [18879] = 11000, [2970] = 11000, [8289] = 11000,
            [7651] = 11000, [5484] = 14000, [11733] = 14000, [11665] = 14000, [18869] = 14000, [17962] = 14000,
            [1311677] = 14000, [20755] = 14000, [11683] = 15000, [17921] = 15000, [11739] = 15000, [6789] = 15000,
            [7659] = 15000, [11707] = 15000, [11693] = 16000, [11725] = 16000, [11671] = 16000, [11703] = 16000,
            [11659] = 16000, [11688] = 20000, [11677] = 20000, [11699] = 20000, [11729] = 20000, [17952] = 20000,
            [11712] = 21000, [18880] = 21000, [18647] = 21000, [6353] = 21000, [18870] = 21000, [18930] = 21000,
            [17727] = 21000, [11734] = 22000, [17922] = 22000, [11667] = 22000, [1293812] = 22000, [17925] = 22000,
            [11743] = 22000, [11719] = 22000, [1311680] = 22000, [20756] = 22000, [11740] = 23000, [11694] = 23000,
            [11675] = 23000, [11708] = 23000, [11660] = 23000, [11684] = 24000, [17928] = 24000, [18931] = 24000,
            [11672] = 24000, [11700] = 24000, [11704] = 24000, [11689] = 25000, [17924] = 25000, [18871] = 25000,
            [11717] = 25000, [17953] = 25000, [6215] = 25000, [11713] = 26000, [18881] = 26000, [17923] = 26000,
            [17926] = 26000, [11678] = 26000, [11726] = 26000, [11730] = 26000, [603] = 27000, [11735] = 27000,
            [11668] = 27000, [1293813] = 27000, [11695] = 27000, [18932] = 27000, [20757] = 27000, [17728] = 27000,
            [11661] = 27000,
        },

        -- Buffs on the player. glow: the client highlights this spell while the buff is up
        -- (fallback when auras are hidden in combat).
        buffs = {
            shadow_trance = { ids = { 17941 }, glow = "shadow_bolt", duration = 10, talent = "nightfall" },
            armor = { ids = {}, duration = 1800 }, -- Demon Skin / Demon Armor add their IDs
        },

        -- Talents: rank = highest known ID (IsPlayerSpell), else matched by name in the talent frame.
        talents = {
            nightfall = { ids = { 18094, 18095 }, tree = 1 },
            siphon_life = { ids = { 18265 }, tree = 1 },
            amplify_curse = { ids = { 18288 }, tree = 1 },
            fel_domination = { ids = { 18708 }, tree = 2 },
            demonic_sacrifice = { ids = { 18788 }, tree = 2 },
            soul_link = { ids = { 19028 }, tree = 2 },
            shadowburn = { ids = { 17877 }, tree = 3 },
            conflagrate = { ids = { 1293817 }, tree = 3 },
            shadow_and_flame = { ids = { 426316 }, tree = 3 },
            incinerate = { ids = { 412758 }, tree = 3 },
            demonic_brand = { ids = { 1293695 }, tree = 2 },
            decimation = { ids = { 440870 }, tree = 2 },
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
