-- A small copy of the Talents Forever data layout (TalentsForeverBook/Data.lua): three tiny trees,
-- popular builds for the lists. Rows open with 5 points per row above; req is the index of the
-- talent in the same tree that must be full first.
local M = {}

function M.data()
    return {
        build = "1.60.1.70755", codeVersion = "12",
        classes = {
            WARLOCK = {
                name = "Warlock", tree = 1117,
                trees = {
                    { name = "Affliction", talents = {
                        { name = "Improved Corruption", max = 5, spell = 17810, node = 105924, row = 1, col = 3 },
                        { name = "Nightfall", max = 2, spell = 18094, node = 105914, row = 2, col = 2 },
                        { name = "Siphon Life", max = 1, spell = 18265, node = 105912, row = 2, col = 3, req = 2 },
                    } },
                    { name = "Demonology", talents = {
                        { name = "Demonic Sacrifice", max = 1, spell = 18788, node = 105900, row = 1, col = 2 },
                        { name = "Fel Domination", max = 1, spell = 18708, node = 105895, row = 1, col = 3 },
                        { name = "Demonic Brand", max = 3, spell = 1293695, node = 105896, row = 1, col = 4 },
                    } },
                    { name = "Destruction", talents = {
                        { name = "Shadowburn", max = 1, spell = 17877, node = 105884, row = 1, col = 3 },
                    } },
                },
            },
        },
        popular = {
            WARLOCK = {
                builds = 127534, window = "since the Oct 15 patch", asOf = "2026-11-05",
                spec = { { "Affliction", 40 }, { "Demonology", 38 }, { "Destruction", 22 } },
                top = {
                    { code = "warlock/60/521-11-1-12", lead = "Affliction", pts = { 8, 2, 1 }, rank = 1, saved = 453, opened = 4884, variants = 138 },
                    { code = "warlock/60/-11-1-12", lead = "Demonology", pts = { 0, 2, 1 }, rank = 2, saved = 120, opened = 900, variants = 12 },
                },
                fors = {
                    leveling = {
                        { code = "warlock/60/521-1--12", lead = { "Affliction" }, pts = { 8, 1, 0 } },
                        { code = "warlock/60/-11-1-12", lead = { "Demonology" }, pts = { 0, 2, 1 } },
                    },
                    pve = { { code = "warlock/60/5-11-1-12", lead = { "Demonology" }, pts = { 5, 2, 1 } } },
                },
            },
        },
    }
end

return M
