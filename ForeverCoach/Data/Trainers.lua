-- Class trainers: where the planner sends the player. Map IDs and coordinates from the stage 0
-- dump (TRAINER_SHOW); names per locale, the city name comes from the client (C_Map.GetMapInfo).
-- The trainer the player visited last (remembered in game) wins over this list.
local ADDON, ns = ...

ns.Data:DefineTrainers({ version = "0.1.0", patch = "1.60.1", date = "2026-11-11" }, {
    { class = "WARLOCK", faction = "Horde", map = 1458, x = 88.7, y = 15.9,
      npc = { enUS = "Richard Kerwin", ruRU = "Ричард Кервин" } },
})
