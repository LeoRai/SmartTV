-- Event bus shared by all modules.
--   Game events (UPPER_CASE from the client) are registered on demand.
--   Addon events start with "FC_" and never touch the client:
--     FC_INIT, FC_LOGIN          lifecycle (Core/Init.lua)
--     FC_SPELLS_CHANGED          known spells or ranks changed (Core/State.lua)
--     FC_TALENTS_CHANGED         talents or active spec changed
--     FC_MODE_CHANGED            leveling / group / pvp switched (Core/Modes.lua)
--     FC_PROFILE_CHANGED         rotation profile switched (Core/BuildMatcher.lua)
--     FC_SETTINGS_CHANGED        a setting changed (UI/Settings.lua, slash commands)
--     FC_DIRTY                   something changed: recompute the hint soon
--     FC_RECOMMENDATION          new hint computed (payload: result, snapshot)
local ADDON, ns = ...

local Events = { handlers = {}, unavailable = {} }
ns.Events = Events

local frame = CreateFrame("Frame")
local registered = {}

local function isAddonEvent(event)
    return event:sub(1, 3) == "FC_"
end

local function dispatch(event, ...)
    local list = Events.handlers[event]
    if not list then return end
    local unit = ...
    for i = 1, #list do
        local h = list[i]
        if not h.units or h.units[unit] then
            ns.SafeCall(event, h.fn, h.owner, event, ...)
        end
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    dispatch(event, ...)
end)

-- Subscribe owner:fn(event, ...) to an event.
-- For UNIT_* events pass the units you care about: Events:On("UNIT_HEALTH", self, fn, "player", "target").
function Events:On(event, owner, fn, ...)
    if type(fn) == "string" then
        local method = fn
        fn = function(o, ...) return o[method](o, ...) end
    end
    local units
    if select("#", ...) > 0 then
        units = {}
        for i = 1, select("#", ...) do units[select(i, ...)] = true end
    end
    local list = self.handlers[event]
    if not list then
        list = {}
        self.handlers[event] = list
    end
    list[#list + 1] = { owner = owner, fn = fn, units = units }

    if not isAddonEvent(event) and not registered[event] then
        -- An event missing from this client raises an error: remember it instead of breaking the load.
        local ok = pcall(frame.RegisterEvent, frame, event)
        registered[event] = true
        if not ok then self.unavailable[event] = true end
    end
end

function Events:Off(event, owner)
    local list = self.handlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then table.remove(list, i) end
    end
end

function Events:Fire(event, ...)
    dispatch(event, ...)
end

function Events:IsAvailable(event)
    return not self.unavailable[event]
end
