-- Build recognition: talents -> rotation profile.
-- Stage 1: the tree with most points picks the build (Affliction / Demonology / Destruction),
-- key talents confirm it. Stage 2 adds exact matching against Talents Forever builds
-- (Data/Builds.lua, Integrations/TalentsForever.lua) and a manual choice per spec.
-- Fallback chain: <Class>_<Build>_<Mode> -> <Class>_Generic_<Mode> -> <Class>_<Build>_Leveling
--                 -> <Class>_Generic_Leveling. Anything but the first is "approximate".
local ADDON, ns = ...
local Data, Events, Modes = ns.Data, ns.Events, ns.Modes

local BuildMatcher = { profile = nil, approximate = true, build = "Generic" }
ns.BuildMatcher = BuildMatcher

local MIN_POINTS = 5 -- fewer talent points than this is not a build yet

function BuildMatcher.DominantTree(points, trees)
    if not points or not trees then return nil end
    local best, bestPoints, total = nil, 0, 0
    for i, pts in ipairs(points) do
        total = total + pts
        if pts > bestPoints then best, bestPoints = i, pts end
    end
    if total < MIN_POINTS or not best then return nil end
    return trees[best]
end

local function talentsMatch(profile, talents)
    if not profile.talents then return true, 0 end
    local matched, all = 0, true
    for key, rank in pairs(profile.talents) do
        if (talents[key] or 0) >= rank then matched = matched + 1 else all = false end
    end
    return all, matched
end

-- Pure selection, used by the addon and by the tests.
-- Returns profile, approximate, build name.
function BuildMatcher.Select(def, profilesById, points, talents, mode)
    local className = def.name
    local suffix = Modes.suffix[mode] or "Leveling"
    local build = BuildMatcher.DominantTree(points, def.trees)

    -- No tree points from the client: guess the build by key talents of the profiles.
    if not build then
        local bestMatched = 0
        for _, p in pairs(profilesById) do
            if p.class == def.token and p.build ~= "Generic" and p.talents then
                local all, matched = talentsMatch(p, talents)
                if all and matched > bestMatched then build, bestMatched = p.build, matched end
            end
        end
    end
    build = build or "Generic"

    local chain = {
        className .. "_" .. build .. "_" .. suffix,
        className .. "_Generic_" .. suffix,
        className .. "_" .. build .. "_Leveling",
        className .. "_Generic_Leveling",
    }
    for i, id in ipairs(chain) do
        local p = profilesById[id]
        if p then
            local all = talentsMatch(p, talents)
            local approximate = i > 1 or p.approximate or not all
            return p, approximate and true or false, build
        end
    end
    -- Last resort: any profile of the class.
    for _, p in pairs(profilesById) do
        if p.class == def.token then return p, true, build end
    end
    return nil, true, build
end

function BuildMatcher:Update()
    local def = Data.class
    if not def then return end
    local State = ns.State
    local profile, approximate, build = BuildMatcher.Select(def, Data.profiles, State.treePoints, State.talents, Modes.current)
    if profile ~= self.profile or approximate ~= self.approximate then
        self.profile, self.approximate, self.build = profile, approximate, build
        Events:Fire("FC_PROFILE_CHANGED", profile, approximate)
    end
end

local function update() BuildMatcher:Update() end
Events:On("FC_TALENTS_CHANGED", BuildMatcher, update)
Events:On("FC_SPELLS_CHANGED", BuildMatcher, update)
Events:On("FC_MODE_CHANGED", BuildMatcher, update)
