-- Mode: battleground or arena -> pvp, dungeon or raid -> group, otherwise leveling.
-- /fc mode <name> or the settings window pins it.
local ADDON, ns = ...
local API, Events = ns.API, ns.Events

local Modes = {
    current = "leveling",
    list = { "auto", "leveling", "group", "pvp" },
    -- Profile file suffix for each mode: Data/Profiles/<Class>_<Build>_<Suffix>.lua
    suffix = { leveling = "Leveling", group = "Group", pvp = "PvP" },
}
ns.Modes = Modes

function Modes.FromInstance(kind)
    if kind == "pvp" or kind == "arena" then return "pvp" end
    if kind == "party" or kind == "raid" or kind == "scenario" then return "group" end
    return "leveling"
end

function Modes:Detect()
    local pinned = ns.db and ns.db.mode
    if pinned and pinned ~= "auto" and self.suffix[pinned] then return pinned end
    return Modes.FromInstance(API.InstanceType())
end

function Modes:Update()
    local mode = self:Detect()
    if mode ~= self.current then
        self.current = mode
        Events:Fire("FC_MODE_CHANGED", mode)
    end
end

local function update() Modes:Update() end
Events:On("FC_LOGIN", Modes, update)
Events:On("PLAYER_ENTERING_WORLD", Modes, update)
Events:On("ZONE_CHANGED_NEW_AREA", Modes, update)
Events:On("FC_SETTINGS_CHANGED", Modes, function(_, _, key)
    if key == "mode" then update() end
end)
