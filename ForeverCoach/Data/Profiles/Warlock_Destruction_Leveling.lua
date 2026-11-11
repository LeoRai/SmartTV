-- Warlock, Destruction, leveling. Built from the Forever talent texts (Talents Forever data):
--   Conflagrate (talent, row 4) works only on a target with Immolate and burns it away, unless
--   Shadow and Flame is full; Bane, Improved Shadow Bolt and Ruin make Shadow Bolt the filler;
--   Shadowburn (talent, row 3) costs a Soul Shard, so it finishes a dying target only while
--   enough shards are kept (Drain Soul collects them otherwise).
-- Not here yet: Incinerate, Bane of Havoc (no text for them in Talents Forever).
-- Matched when Destruction holds most talent points or a Destruction build is chosen.
local ADDON, ns = ...

ns.Data:DefineProfile("WARLOCK", function()
    return {
        id = "Warlock_Destruction_Leveling",
        build = "Destruction",
        mode = "leveling",
        version = "0.1.0", patch = "1.60.1", date = "2026-11-11",
        aoe = true,
        talents = { shadowburn = 1 }, -- key talent of the build

        main = {
            { "drain_soul", "soul_shards < opt.shards", gate = { unit = "target", below = 20, warn = 15, takeover = true }, alert = "ALERT_EXECUTE", why = "WHY_EXECUTE_SHARD" },
            { "shadowburn", "soul_shards >= opt.shards", gate = { unit = "target", below = 20, warn = 15, takeover = true }, alert = "ALERT_EXECUTE", why = "WHY_SHADOWBURN" },
            { "life_tap", "player.hp_pct > opt.hp", gate = { unit = "player", power = "mana", below = 15, warn = 15 }, alert = "ALERT_LOW_MANA", why = "WHY_LIFE_TAP" },
            { "shadow_bolt", "buff.shadow_trance.up", why = "WHY_PROC", glow = true },
            { "hellfire", "enemies >= 3 & player.hp_pct > 50", why = "WHY_AOE_HELLFIRE" },
            { "rain_of_fire", "enemies >= 3 & !known.hellfire", why = "WHY_AOE_RAIN" },
            { "life_tap", "player.oom & player.hp_pct > opt.hp", why = "WHY_LIFE_TAP" },
            { "drain_life", "player.hp_pct < 40", why = "WHY_DRAIN_LIFE" },
            { "immolate", "debuff.immolate.refreshable & target.ttd > 6", why = "WHY_IMMOLATE_FIRST" },
            { "conflagrate", "debuff.immolate.up", why = "WHY_CONFLAGRATE" },
            { "curse_of_agony", "debuff.curse_of_agony.refreshable & target.ttd > 10", why = "WHY_CURSE" },
            { "curse_of_weakness", "!known.curse_of_agony & debuff.curse_of_weakness.down & target.ttd > 10", why = "WHY_CURSE" },
            { "corruption", "debuff.corruption.refreshable & target.ttd > 8", why = "WHY_DOT" },
            { "shoot", "combat & (target.hp_pct < 25 | player.mana_pct < 25)", why = "WHY_WAND" },
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
