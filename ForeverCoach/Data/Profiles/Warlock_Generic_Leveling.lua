-- Warlock, any talents, leveling. The fallback when no build-specific profile fits:
-- shown as "approximate" in /fc debug and in the Builds window.
--
-- Each line: { "action", "condition", why = "locale key", glow = true }
-- Lines are checked top to bottom; the first available action whose condition holds wins.
-- Language reference: docs/PROFILES.md
local ADDON, ns = ...

ns.Data:DefineProfile("WARLOCK", function()
    return {
        id = "Warlock_Generic_Leveling",
        build = "Generic",
        mode = "leveling",
        approximate = true,
        version = "0.2.0", patch = "1.60.1", date = "2026-11-11",
        aoe = true, -- 3+ enemies: AoE lines at the top, "AoE" label above the block

        main = {
            { "drain_soul", "target.hp_pct <= 20 & soul_shards < opt.shards", why = "WHY_EXECUTE_SHARD" },
            { "shadow_bolt", "buff.shadow_trance.up", why = "WHY_PROC", glow = true },
            { "hellfire", "enemies >= 3 & player.hp_pct > 50", why = "WHY_AOE_HELLFIRE" },
            { "rain_of_fire", "enemies >= 3 & !known.hellfire", why = "WHY_AOE_RAIN" },
            { "life_tap", "(player.mana_pct < player.hp_pct - opt.tap | player.oom) & player.hp_pct > opt.hp", why = "WHY_LIFE_TAP" },
            { "drain_life", "player.hp_pct < 40", why = "WHY_DRAIN_LIFE" },
            { "curse_of_agony", "debuff.curse_of_agony.refreshable & target.ttd > 10", why = "WHY_CURSE" },
            { "curse_of_weakness", "!known.curse_of_agony & debuff.curse_of_weakness.down & target.ttd > 10", why = "WHY_CURSE" },
            { "corruption", "debuff.corruption.refreshable & target.ttd > 8", why = "WHY_DOT" },
            { "siphon_life", "debuff.siphon_life.refreshable & target.ttd > 10", why = "WHY_DOT" },
            { "immolate", "debuff.immolate.refreshable & target.ttd > 6 & (player.mana_pct > 40 | !combat)", why = "WHY_DOT" },
            { "shoot", "combat & (target.hp_pct < 25 | player.mana_pct < 25)", why = "WHY_WAND" },
            { "shadow_bolt", "", why = "WHY_FILLER" },
            { "shoot", "", why = "WHY_WAND_OOM" },
        },

        -- Left slot: only when health is low, the demon is dying or a second enemy shows up.
        defense = {
            { "healthstone", "player.hp_pct < opt.hp", why = "WHY_HEALTHSTONE" },
            { "healing_potion", "player.hp_pct < opt.hp & !item.healthstone.ready", why = "WHY_POTION" },
            { "death_coil", "player.hp_pct < opt.hp", why = "WHY_DEATH_COIL" },
            { "sacrifice", "pet.hp_pct < opt.pet_hp / 2", why = "WHY_SACRIFICE" },
            { "health_funnel", "pet.exists & pet.hp_pct < opt.pet_hp & player.hp_pct > 50", why = "WHY_HEALTH_FUNNEL" },
            { "howl_of_terror", "enemies >= 3", why = "WHY_HOWL" },
            { "fear", "enemies = 2 & last.fear > 15 & !target.player", why = "WHY_FEAR_SECOND" },
        },

        -- Right slot: only on bosses, elites and players. Leveling keeps big cooldowns for them.
        cooldown = {
            { "amplify_curse", "(target.boss | target.elite | target.player) & debuff.curse_of_agony.refreshable & target.ttd > 15", why = "WHY_AMPLIFY" },
            { "curse_of_doom", "target.boss & target.ttd > 60 & debuff.curse_of_doom.down", why = "WHY_CURSE" },
        },

        -- Preparation line: out of combat, the first failing check is shown.
        prep = {
            { "!pet.exists & (known.summon_imp | known.summon_voidwalker)", text = "PREP_NO_PET" },
            { "known.create_healthstone & item.healthstone.count = 0 & soul_shards > 0", text = "PREP_NO_HEALTHSTONE" },
            { "buff.armor.down & (known.demon_skin | known.demon_armor)", text = "PREP_NO_ARMOR" },
            { "known.drain_soul & soul_shards < 1", text = "PREP_FEW_SHARDS", value = "soul_shards" },
            { "trainer > 0", text = "PREP_TRAINER", value = "trainer", place = "trainer" },
        },
    }
end)
