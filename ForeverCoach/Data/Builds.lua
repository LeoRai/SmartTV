-- Builds from Talents Forever (author: baldwinbuilds) — the only source of builds.
-- Data license: CC BY 4.0, attribution required (confirm with the author at stage 0).
-- Filled at stage 2 by tools/build_data.py (or read live from the Talents Forever addon).
--
-- Entry:
--   {
--     class = "WARLOCK", mode = "leveling" | "group" | "pvp",
--     name = "Affliction leveling", tree = 1,
--     talents = "<Talents Forever build string>",
--     order = { "<talent key per level>", ... },  -- point order from level 10
--     popularity = 0.42, date = "2026-11-10",
--     profile = "Warlock_Affliction_Leveling",
--     url = "https://talentsforever.com/...",
--   }
local ADDON, ns = ...

ns.Data:DefineBuilds({
    source = "Talents Forever",
    author = "baldwinbuilds",
    license = "CC BY 4.0",
    url = "https://talentsforever.com/popular",
    version = "0.0.0",
    date = "2026-11-11",
}, {
    -- empty until stage 2
})
