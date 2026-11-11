-- Settings window (/fc), as in the mockup:
--   left:  LOOK (main icon size, opacity, next icons, hide out of combat, bar highlight), MODE
--   right: THRESHOLDS, SOUND (two signals, volume, preview), KEYS
--   footer: Talents Forever co-author credit, Reset, Done. Esc closes it.
local ADDON, ns = ...
local L, Events, W = ns.L, ns.Events, ns.Widgets
local C = W.C

-- (named SettingsWindow: "Settings" is the game's own settings API)
local SettingsWindow = {}
ns.Settings = SettingsWindow

local WIDTH, HEIGHT = 760, 700
local LEFT, RIGHT, COL = 24, 392, 344

local function changed(key)
    Events:Fire("FC_SETTINGS_CHANGED", key)
    Events:Fire("FC_DIRTY")
end

local function getter(key) return function() return ns.db[key] end end
local function setter(key) return function(v) ns.db[key] = v; changed(key) end end

local function at(widget, parent, x, y)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    return widget
end

local function bindingText(...)
    local keys = {}
    for i = 1, select("#", ...) do
        local key = GetBindingKey and GetBindingKey(select(i, ...))
        if key then keys[#keys + 1] = GetBindingText and GetBindingText(key) or key end
    end
    if #keys == 0 then return L.S_KEY_NONE end
    return table.concat(keys, ", ")
end

local function openKeyBindings()
    if InCombatLockdown and InCombatLockdown() then return end
    local api = _G.Settings
    if api and api.OpenToCategory and api.KEYBINDINGS_CATEGORY_ID then
        if pcall(api.OpenToCategory, api.KEYBINDINGS_CATEGORY_ID) then return end
    end
end

function SettingsWindow:Create()
    if self.frame then return end
    local f = W.Window("ForeverCoachSettings", L.SETTINGS_TITLE, WIDTH, HEIGHT)
    local widgets = {}
    local function add(w) widgets[#widgets + 1] = w; return w end

    -- LOOK --------------------------------------------------------------------
    at(W.Section(f, L.S_SECTION_LOOK), f, LEFT, -74)
    at(add(W.Slider(f, COL, L.S_ICON_SIZE, L.S_PX, 32, 96, 2, getter("iconSize"), setter("iconSize"))), f, LEFT, -100)
    at(add(W.Slider(f, COL, L.S_ALPHA, L.S_PERCENT, 20, 100, 5,
        function() return math.floor(ns.db.alpha * 100 + 0.5) end,
        function(v) ns.db.alpha = v / 100; changed("alpha") end)), f, LEFT, -152)
    at(W.Font(f, 13, C.text), f, LEFT, -216):SetText(L.S_NEXT)
    local next = add(W.Segmented(f, 156, { { 0, "0" }, { 1, "1" }, { 2, "2" }, { 3, "3" } },
        getter("nextIcons"), setter("nextIcons")))
    at(next, f, LEFT + COL - 156, -206)
    at(add(W.Check(f, L.S_HIDE_OOC, getter("hideOutOfCombat"), setter("hideOutOfCombat"))), f, LEFT, -256)
    at(add(W.Check(f, L.S_HIGHLIGHT, getter("highlightBar"), setter("highlightBar"))), f, LEFT, -286)

    -- MODE --------------------------------------------------------------------
    at(W.Section(f, L.S_SECTION_MODE), f, LEFT, -330)
    local modes = {}
    for _, m in ipairs(ns.Modes.list) do modes[#modes + 1] = { m, L["MODE_" .. m] } end
    at(add(W.Segmented(f, COL, modes, getter("mode"), setter("mode"))), f, LEFT, -354)
    local help = at(W.Font(f, 12, C.muted), f, LEFT, -400)
    help:SetWidth(COL)
    help:SetText(L.S_MODE_HELP)

    -- COMBAT RECAP ----------------------------------------------------------------
    at(W.Section(f, L.S_SECTION_RECAP), f, LEFT, -452)
    local minLabel = at(W.Font(f, 13, C.text), f, LEFT, -482)
    minLabel:SetWidth(COL - 80)
    minLabel:SetText(L.S_MIN_FIGHT)
    at(add(W.NumberBox(f, 3, 120, getter("recapMinFight"), setter("recapMinFight"))), f, LEFT + COL - 48, -478)

    -- THRESHOLDS ----------------------------------------------------------------
    at(W.Section(f, L.S_SECTION_THRESHOLDS), f, RIGHT, -74)
    local rows = {
        { L.S_HP, "hpThreshold", 5, 90, true },
        { L.S_PET_HP, "petHpThreshold", 5, 90, true },
        { L.S_SHARDS, "shards", 0, 30, false },
    }
    for i, row in ipairs(rows) do
        local y = -100 - (i - 1) * 40
        local label = at(W.Font(f, 13, C.text), f, RIGHT, y - 4)
        label:SetWidth(COL - 80)
        label:SetText(row[1])
        local box = add(W.NumberBox(f, row[3], row[4], getter(row[2]), setter(row[2])))
        at(box, f, RIGHT + COL - 70, y)
        if row[5] then at(W.Font(f, 13, C.muted), f, RIGHT + COL - 14, y - 6):SetText("%") end
    end

    -- SOUND ---------------------------------------------------------------------
    at(W.Section(f, L.S_SECTION_SOUND), f, RIGHT, -228)
    local sounds = {
        { L.S_SOUND_READY, "soundReady", "soundReadyVolume", "ready" },
        { L.S_SOUND_PROC, "soundProc", "soundProcVolume", "proc" },
    }
    for i, snd in ipairs(sounds) do
        local y = -254 - (i - 1) * 66
        at(add(W.Check(f, snd[1], getter(snd[2]), setter(snd[2]))), f, RIGHT, y)
        at(W.PlayButton(f, function() ns.Sounds:Play(snd[4], true) end), f, RIGHT + COL - 28, y + 5)
        at(add(W.Slider(f, COL - 26, L.S_VOLUME, L.S_PERCENT, 0, 100, 5, getter(snd[3]), setter(snd[3]), true)),
            f, RIGHT + 26, y - 30)
    end
    local note = at(W.Font(f, 12, C.muted), f, RIGHT, -390)
    note:SetWidth(COL)
    note:SetText(L.S_SOUND_NOTE)

    -- KEYS ----------------------------------------------------------------------
    at(W.Section(f, L.S_SECTION_KEYS), f, RIGHT, -428)
    local keyRows = {
        { L.S_KEY_TOGGLE, { "FOREVERCOACH_TOGGLE" } },
        { L.S_KEY_WINDOWS, { "FOREVERCOACH_BUILDS", "FOREVERCOACH_PLAN", "FOREVERCOACH_RECAP" } },
    }
    for i, row in ipairs(keyRows) do
        local y = -454 - (i - 1) * 26
        at(W.Font(f, 13, C.text), f, RIGHT, y):SetText(row[1])
        local value = W.Font(f, 13, C.muted)
        value:SetPoint("TOPRIGHT", f, "TOPLEFT", RIGHT + COL, y)
        value:SetJustifyH("RIGHT")
        add({ refresh = function() value:SetText(bindingText(unpack(row[2]))) end })
    end
    at(W.Button(f, L.S_OPEN_KEYS, 208, false, openKeyBindings), f, RIGHT, -508)

    -- Footer --------------------------------------------------------------------
    local footer = W.Font(f, 12, C.muted)
    footer:SetPoint("BOTTOMLEFT", 24, 23)
    footer:SetText(string.format(L.S_FOOTER, ns.VERSION))
    local done = W.Button(f, L.S_DONE, 76, true, function() f:Hide() end)
    done:SetPoint("BOTTOMRIGHT", -24, 13)
    local reset = W.Button(f, L.S_RESET, 100, false, function()
        ns:ResetSettings()
        changed("reset")
        SettingsWindow:Refresh()
    end)
    reset:SetPoint("RIGHT", done, "LEFT", -10, 0)

    f:SetScript("OnShow", function()
        for _, w in ipairs(widgets) do w.refresh() end
    end)
    self.frame = f
end

function SettingsWindow:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function SettingsWindow:Refresh()
    if self.frame and self.frame:IsShown() then self.frame:GetScript("OnShow")(self.frame) end
end

Events:On("UPDATE_BINDINGS", SettingsWindow, function(self) self:Refresh() end)
