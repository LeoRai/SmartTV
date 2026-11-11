-- Update loop and slash commands.
-- Game events mark the hint dirty; a timer recomputes it, never more than 10 times a second
-- (every 0.1 s in combat or with a target, every 0.5 s otherwise, at once after an event).
local ADDON, ns = ...
local L, Data, Events, State, Engine = ns.L, ns.Data, ns.Events, ns.State, ns.Engine

local Loop = {
    prepared = {},   -- profile id -> compiled profile
    current = nil,   -- compiled profile in use
    dirty = true,
    active = false,
    acc = 0,
    stats = { n = 0, total = 0, max = 0 },
    lastDebug = nil,
}
ns.Loop = Loop

local MIN_INTERVAL, IDLE_INTERVAL = 0.1, 0.5

function Loop:Use(profile)
    if not profile then
        self.current = nil
        return
    end
    local p = self.prepared[profile.id]
    if not p then
        p = Engine.Prepare(profile, Data.class)
        self.prepared[profile.id] = p
        if #p.errors > 0 then
            for _, e in ipairs(p.errors) do ns.Print("%s: %s", profile.id, e) end
        end
    end
    self.current = p
    self.dirty = true
end

-- Snapshot + hints, without drawing. Used by the HUD and by the tests.
function Loop:Compute(now)
    local s = State:Refresh(now)
    if not s then return nil, nil end
    local depth = 1 + math.max(0, math.min(3, ns.db.nextIcons or 3))
    return Engine:Recommend(s, self.current, depth), s
end

function Loop:Debug(r, s)
    local main = r.main[1]
    local key = main and (main.line.row .. main.action .. main.line.src) or "none"
    if key == self.lastDebug then return end
    self.lastDebug = key
    if main then
        ns.Print(Engine.Explain(main, s))
    elseif s.target.enemy then
        ns.Print(L.DEBUG_NONE, self.current and self.current.id or "no profile")
    end
end

function Loop:Update()
    local now = GetTime()
    local t0 = debugprofilestop and debugprofilestop()
    local r, s = self:Compute(now)
    if t0 then
        local ms = debugprofilestop() - t0
        local st = self.stats
        st.n, st.total = st.n + 1, st.total + ms
        if ms > st.max then st.max = ms end
    end
    self.active = s ~= nil and (s.player.in_combat or s.target.exists or s.castKey ~= nil)
    ns.HUD:Render(r, s, now)
    ns.Sounds:Update(r, s, now)
    if s and r and ns.db.debug then self:Debug(r, s) end
    ns.SafeCall("surprises", ns.Surprises.Track, ns.Surprises, r, s, now)
    Events:Fire("FC_RECOMMENDATION", r, s) -- combat recap (stage 3) listens here
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(_, elapsed)
    Loop.acc = Loop.acc + elapsed
    if Loop.acc < MIN_INTERVAL then return end
    if not Loop.dirty and not Loop.active and Loop.acc < IDLE_INTERVAL then return end
    Loop.acc, Loop.dirty = 0, false
    ns.SafeCall("update", Loop.Update, Loop)
end)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function markDirty() Loop.dirty = true end
Events:On("FC_DIRTY", Loop, markDirty)
for _, event in ipairs({
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}) do
    Events:On(event, Loop, markDirty)
end
Events:On("UNIT_AURA", Loop, markDirty, "player", "target")
Events:On("UNIT_HEALTH", Loop, markDirty, "player", "target", "pet")
Events:On("UNIT_POWER_UPDATE", Loop, markDirty, "player")

-- If the client ever blocks one of our calls, name the function so it can be fixed.
local function blocked(_, _, addon, func)
    if addon == ADDON then ns.Print(L.BLOCKED, tostring(func)) end
end
Events:On("ADDON_ACTION_FORBIDDEN", Loop, blocked)
Events:On("ADDON_ACTION_BLOCKED", Loop, blocked)

Events:On("FC_PROFILE_CHANGED", Loop, function(self, _, profile, approximate)
    self:Use(profile)
    if ns.db.debug and profile then
        ns.Print(L.PROFILE_ACTIVE, profile.id, approximate and L.PROFILE_APPROX or "")
    end
end)

Events:On("FC_SETTINGS_CHANGED", Loop, function(self)
    ns.HUD:ApplySettings()
    ns.Settings:Refresh()
    self.dirty = true
end)

Events:On("FC_LOGIN", Loop, function(self)
    if not Data.class then
        ns.Print(L.NO_CLASS_DATA)
        return
    end
    ns.HUD:Create()
    ns.MinimapButton:Create()
    State:ScanKnown()
    ns.BuildMatcher:Update()
    Data:CheckVersion(ns.db)
    driver:Show()
end)

---------------------------------------------------------------------------
-- Slash commands and key bindings
---------------------------------------------------------------------------

local Commands = {}
ns.Commands = Commands

local function setting(key, value)
    ns.db[key] = value
    Events:Fire("FC_SETTINGS_CHANGED", key)
end

local function dumpState()
    local r, s = Loop:Compute(GetTime())
    if not s then ns.Print(L.NO_CLASS_DATA) return end
    local p, t, pet = s.player, s.target, s.pet
    ns.Print("level %d, hp %.0f%%, mana %.0f%%, combat %s, mode %s", p.level, p.hp_pct, p.mana_pct, tostring(p.in_combat), s.mode)
    ns.Print("target %s, enemy %s, hp %.0f%%, ttd %.0f, boss %s, elite %s, enemies %d",
        tostring(t.exists), tostring(t.enemy), t.hp_pct or 0, t.ttd or 0, tostring(t.boss), tostring(t.elite), s.enemies)
    ns.Print("pet %s (%s), hp %.0f%%; shards %d; trainer %d", tostring(pet.exists), tostring(pet.family), pet.hp_pct or 0, s.shards, s.trainer)
    local known, debuffs, hidden = 0, {}, {}
    for _ in pairs(s.known) do known = known + 1 end
    for key, exp in pairs(s.debuffs) do debuffs[#debuffs + 1] = string.format("%s %.0fs", key, exp - s.now) end
    for key in pairs(s.hidden) do hidden[#hidden + 1] = key end
    ns.Print("known spells %d; debuffs: %s", known, table.concat(debuffs, ", "))
    ns.Print("hidden by the client: %s", #hidden > 0 and table.concat(hidden, ", ") or "-")
    local bm = ns.BuildMatcher
    ns.Print(L.PROFILE_ACTIVE, bm.profile and bm.profile.id or "-", bm.approximate and L.PROFILE_APPROX or "")
    local tree = ns.State.treePoints
    if tree then ns.Print("talent points: %s", table.concat(tree, "/")) end
    if bm.popular then
        ns.Print(L.TF_CLOSEST, bm.popular.rank or 0, table.concat(bm.popular.pts or {}, "/"), tostring(bm.popular.lead),
            math.floor(bm.similarity * 100 + 0.5))
    end
    if r and r.main[1] then ns.Print(Engine.Explain(r.main[1], s)) end
    local unavailable = {}
    for event in pairs(Events.unavailable) do unavailable[#unavailable + 1] = event end
    if #unavailable > 0 then ns.Print("events missing in this client: %s", table.concat(unavailable, ", ")) end
end

function Commands:Run(cmd, arg)
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "settings" or cmd == "config" then
        ns.Settings:Toggle()
    elseif cmd == "toggle" then
        setting("shown", not ns.db.shown)
        ns.Print(ns.db.shown and L.HINTS_SHOWN or L.HINTS_HIDDEN)
    elseif cmd == "lock" then
        setting("locked", true)
        ns.Print(L.LOCKED)
    elseif cmd == "unlock" then
        setting("locked", false)
        ns.Print(L.UNLOCKED)
    elseif cmd == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        Events:Fire("FC_SETTINGS_CHANGED", "minimap")
        ns.Print(ns.db.minimap.hide and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
    elseif cmd == "builds" or cmd == "plan" then
        ns.Print(L.NOT_YET, 2)
    elseif cmd == "recap" then
        ns.Print(L.NOT_YET, 3)
    elseif cmd == "mode" then
        arg = (arg or ""):lower()
        if arg == "auto" or ns.Modes.suffix[arg] then
            setting("mode", arg)
            ns.Print(L.MODE_SET, L["MODE_" .. arg])
        else
            ns.Print(L.UNKNOWN_COMMAND)
        end
    elseif cmd == "debug" then
        setting("debug", not ns.db.debug)
        Loop.lastDebug = nil
        ns.Print(ns.db.debug and L.DEBUG_ON or L.DEBUG_OFF)
    elseif cmd == "state" then
        dumpState()
    elseif cmd == "surprises" then
        local Surprises = ns.Surprises
        if (arg or ""):lower() == "clear" then
            Surprises.Clear()
            ns.Print(L.SURPRISES_CLEARED)
            return
        end
        local list = Surprises.List()
        if #list == 0 then
            ns.Print(L.SURPRISES_NONE)
            return
        end
        ns.Print(L.SURPRISES_HEAD, #list, math.min(#list, Surprises.SHOW))
        for i = math.max(1, #list - Surprises.SHOW + 1), #list do ns.Print(Surprises.Format(list[i])) end
    elseif cmd == "perf" then
        local st = Loop.stats
        ns.Print(L.PERF, st.n, st.n > 0 and st.total / st.n or 0, st.max)
    elseif cmd == "reset" then
        ns:ResetSettings()
        Events:Fire("FC_SETTINGS_CHANGED", "reset")
        ns.Print(L.RESET_DONE)
    elseif cmd == "help" then
        for _, line in ipairs(L.HELP) do ns.Print(line) end
    else
        ns.Print(L.UNKNOWN_COMMAND)
    end
end

SLASH_FOREVERCOACH1 = "/fc"
SLASH_FOREVERCOACH2 = "/forevercoach"
SlashCmdList = SlashCmdList or {}
SlashCmdList.FOREVERCOACH = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    Commands:Run(cmd, arg)
end
