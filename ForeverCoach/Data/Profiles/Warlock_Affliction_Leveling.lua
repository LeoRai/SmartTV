-- Warlock, Affliction, leveling: dots, Siphon Life and drain-tanking behind the demon.
-- Matched when Affliction holds most talent points (stage 2: exact Talents Forever builds).
local ADDON, ns = ...

ns.Data:DefineProfile("WARLOCK", function()
    return {
        id = "Warlock_Affliction_Leveling",
        build = "Affliction",
        mode = "leveling",
        version = "0.2.0", patch = "1.60.1", date = "2026-11-11",
        aoe = true, -- 3+ enemies: AoE lines at the top, "AoE" label above the block
        talents = { nightfall = 1, siphon_life = 1 }, -- key talents of the build

        main = {
            -- Health gates (gate = ...): Forever hides health from addons, the client shows these itself.
            { "drain_soul", "soul_shards < opt.shards", gate = { unit = "target", below = 20 }, why = "WHY_EXECUTE_SHARD" },
            { "shadow_bolt", "buff.shadow_trance.up", why = "WHY_PROC", glow = true },
            { "hellfire", "enemies >= 3 & player.hp_pct > 50", why = "WHY_AOE_HELLFIRE" },
            { "rain_of_fire", "enemies >= 3 & !known.hellfire", why = "WHY_AOE_RAIN" },
            { "life_tap", "player.oom & player.hp_pct > opt.hp", why = "WHY_LIFE_TAP" },
            { "siphon_life", "debuff.siphon_life.refreshable & target.ttd > 10", why = "WHY_DOT" },
            { "curse_of_agony", "debuff.curse_of_agony.refreshable & target.ttd > 10", why = "WHY_CURSE" },
            { "curse_of_weakness", "!known.curse_of_agony & debuff.curse_of_weakness.down & target.ttd > 10", why = "WHY_CURSE" },
            { "corruption", "debuff.corruption.refreshable & target.ttd > 8", why = "WHY_DOT" },
            { "immolate", "!known.siphon_life & debuff.immolate.refreshable & target.ttd > 6 & player.mana_pct > 50", why = "WHY_DOT" },
            { "drain_life", "player.hp_pct < 70", why = "WHY_DRAIN_LIFE" },
            { "shoot", "combat & (target.hp_pct < 25 | player.mana_pct < 30)", why = "WHY_WAND" },
            { "shadow_bolt", "", why = "WHY_FILLER" },
            { "shoot", "", why = "WHY_WAND_OOM" },
        },

        defense = {
            { "healthstone", "", gate = { unit = "player", below = "hp" }, why = "WHY_HEALTHSTONE" },
            { "healing_potion", "!item.healthstone.ready", gate = { unit = "player", below = "hp" }, why = "WHY_POTION" },
            { "death_coil", "", gate = { unit = "player", below = "hp" }, why = "WHY_DEATH_COIL" },
            { "sacrifice", "", gate = { unit = "pet", below = 20 }, why = "WHY_SACRIFICE" },
            { "health_funnel", "pet.exists & player.hp_pct > 50", gate = { unit = "pet", below = "pet_hp" }, why = "WHY_HEALTH_FUNNEL" },
            { "howl_of_terror", "enemies >= 3", why = "WHY_HOWL" },
            { "fear", "enemies = 2 & last.fear > 15 & !target.player", why = "WHY_FEAR_SECOND" },
        },

        cooldown = {
            { "amplify_curse", "(target.boss | target.elite | target.player) & debuff.curse_of_agony.refreshable & target.ttd > 15", why = "WHY_AMPLIFY" },
            { "curse_of_doom", "target.boss & target.ttd > 60 & debuff.curse_of_doom.down", why = "WHY_CURSE" },
        },

        prep = {
            { "!pet.exists & (known.summon_imp | known.summon_voidwalker)", text = "PREP_NO_PET" },
            { "known.create_healthstone & item.healthstone.count = 0 & soul_shards > 0", text = "PREP_NO_HEALTHSTONE" },
            { "buff.armor.down & (known.demon_skin | known.demon_armor)", text = "PREP_NO_ARMOR" },
            { "known.drain_soul & soul_shards < 1", text = "PREP_FEW_SHARDS", value = "soul_shards" },
            { "trainer > 0", text = "PREP_TRAINER", value = "trainer", place = "trainer" },
        },
    }
end)
