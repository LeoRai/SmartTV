-- Builds from Talents Forever (author: baldwinbuilds, co-author of ForeverCoach) — the only source of builds.
-- With the author's permission builds are read directly from the Talents Forever addon in game
-- (stage 2, Integrations/TalentsForever.lua). This table holds the same entries in ForeverCoach's
-- format: what the integration produces, and the fallback for builds pasted as links.
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
