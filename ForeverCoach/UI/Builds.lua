-- Builds window (/fc builds), as in the mockup:
--   tabs All / Leveling / PvE / PvP and "Paste a link"; the top builds of the tab with the
--   player's own marked; the card of the selected build: its trees, how many players saved it,
--   the rotation it leads to, how the player's talents compare and where the next point goes;
--   Spec 1 / Spec 2 (from level 40) and "Choose build".
-- Builds come from Talents Forever (baldwinbuilds, co-author), read from its addon in game.
-- Model() gathers what the window shows; the frames only draw it (the tests check the model).
local ADDON, ns = ...
local L, API, Data, Events, W = ns.L, ns.API, ns.Data, ns.Events, ns.Widgets
local C = W.C

local BuildsWindow = { tab = "all", selected = 1, spec = nil, link = nil, message = nil }
ns.BuildsWindow = BuildsWindow

local WIDTH, HEIGHT = 840, 660
local ROWS, ROTATION = 5, 5
local LIST_X, LIST_Y, ROW_H, ROW_GAP = 22, -133, 56, 7
local CARD_X, CARD_W, CARD_H = 338, 480, 470

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------

local function treeName(en) return ns.Tr("TREE_" .. tostring(en), en or "?") end

local function ptsText(pts)
    local parts = {}
    for i, p in ipairs(pts or {}) do parts[i] = tostring(p) end
    return table.concat(parts, " / ")
end

local function playerLevel() return API.UnitLevel("player") or 1 end

-- The player's talent ranks by talent spell (from the client's traits).
local function playerRanks() return ns.State.traits or {} end

-- Spell ID to show for a data key: the known rank, else the first one.
local function spellIdOf(key)
    local def = Data.class
    local sp = def and def.spells[key]
    if not sp then return nil end
    return ns.State.known[key] or sp.ranks[1][1]
end

local function icon(key, id, proc)
    id = id or spellIdOf(key)
    local name = API.SpellName(id) or key
    return { key = key, id = id, texture = API.SpellTexture(id), proc = proc,
             label = proc and string.format(L.B_ON_PROC, name) or name, name = name }
end

-- The build's rotation at the player's level (its own profile, the talents its plan has by now,
-- the spells known) and what joins it later, with levels.
local function rotationOf(build, tab)
    local def, Planner, TF = Data.class, ns.Planner, ns.TalentsForever
    local s = ns.State:Refresh(GetTime())
    local level = s.player.level
    local mode = tab ~= "all" and tab or ns.Modes.current
    local profile = ns.BuildMatcher.Select(def, Data.profiles, nil, {}, mode, build.lead)
    local ranks = build.ranks or TF.Decode(def.token, build.code)
    -- now: the spells learned and the talents taken, as the live hint has them
    local now = {}
    for _, r in ipairs(Planner.Distinct(Planner.RotationNow(def, Planner.Prepared(profile, def), s, 8))) do
        if #now < ROTATION then now[#now + 1] = icon(r.key, r.id) end
    end
    -- the proc, once the talent that gives it is taken
    for _, b in pairs(def.buffs or {}) do
        if b.glow and b.talent and (s.talents[b.talent] or 0) > 0 and #now < ROTATION then
            now[#now + 1] = icon(b.glow, nil, true)
        end
    end
    local later = {}
    for _, u in ipairs(Planner.Upcoming(def, profile, s, level, ranks)) do
        local name = API.SpellName(u.id) or u.key
        if u.proc then name = string.format(L.B_PROC_NAME, name) end
        local item = string.format(L.B_UPCOMING_ITEM, name, u.level)
        if u.kind and not u.proc then item = item .. string.format(" (%s)", L["B_KIND_" .. u.kind]) end
        later[#later + 1] = item
    end
    return now, later, profile
end

local function compareLines(build)
    local TF = ns.TalentsForever
    local unspent = API.TalentPoints(TF.TreeID(Data.class.token))
    local c = ns.Builds.Compare(build.ranks or {}, playerRanks(), playerLevel(), unspent)
    local first
    if c.spent == 0 then
        first = { mark = "dot", color = C.muted, text = L.B_NO_POINTS }
    elseif c.all then
        first = { mark = "check", color = C.good, text = ns.Count(c.spent, L.B_ALL_MATCH) }
    else
        first = { mark = "!", color = C.aoe, text = string.format(L.B_SOME_MATCH, c.matched, c.spent) }
    end
    local second
    if c.done or not c.next then
        second = { mark = "check", color = C.good, text = L.B_DONE }
    elseif c.next.now then
        second = { mark = "+", color = C.gold, text = string.format(L.B_NEXT_NOW, c.next.name), name = c.next.name }
    else
        second = { mark = "+", color = C.gold, text = string.format(L.B_NEXT_AT, c.next.level, c.next.name), name = c.next.name }
    end
    return first, second, c
end

-- Everything the window shows, from the current tab, selection and spec.
function BuildsWindow:Model()
    local TF, Builds = ns.TalentsForever, ns.Builds
    local def = Data.class
    local m = { tab = self.tab, available = (TF and TF.Available() and def) and true or false }
    m.className = API.Clean(UnitClass and UnitClass("player")) or (def and def.name) or ""
    local level = playerLevel()
    m.level = level
    m.spec = self.spec or Builds.ActiveSpec()
    m.spec2Open = level >= Builds.SPEC2_LEVEL
    if not m.spec2Open and m.spec == 2 then m.spec = 1 end
    m.chosen = Builds.Chosen(m.spec)
    if not m.available then return m end

    local meta = TF.Meta(def.token)
    m.subtitle = meta and meta.asOf and string.format(L.B_SUBTITLE_ASOF, meta.asOf) or L.B_SUBTITLE
    m.list = {}
    for i, b in ipairs(Builds.List(self.tab, playerRanks())) do
        if i > ROWS then break end
        b.chosen = m.chosen ~= nil and m.chosen.code == b.code
        b.ptsText = ptsText(b.pts)
        b.leadName = treeName(b.lead)
        m.list[i] = b
    end

    local sel = self.link or m.list[math.min(self.selected, #m.list)]
    m.selectedIndex = not self.link and sel and math.min(self.selected, #m.list) or nil
    if not sel then return m end
    m.selected = sel
    local layout = TF.Layout(def.token)
    local card = { title = treeName(sel.lead), pts = ptsText(sel.pts), trees = {} }
    for i, name in ipairs(layout and layout.names or {}) do
        card.trees[i] = { name = treeName(name), pts = sel.pts and sel.pts[i] or 0, color = W.TREE_COLORS[i] or C.muted }
    end
    if sel.source == "link" then
        card.stats = L.B_STATS_LINK
    elseif sel.saved then
        card.stats = string.format(L.B_STATS, ns.Number(sel.saved), ns.Number(sel.opened or 0), ns.Number(sel.variants or 0))
    end
    local later, profile
    card.rotation, later, profile = rotationOf(sel, self.tab)
    -- the first ones that join (two lines of the card at most)
    local shown, more = {}, math.max(0, #later - 5)
    for i = 1, math.min(5, #later) do shown[i] = later[i] end
    card.later = #later > 0 and (string.format(L.B_UPCOMING, table.concat(shown, ", ")) ..
        (more > 0 and string.format(L.B_UPCOMING_MORE, more) or "")) or L.B_UPCOMING_NONE
    card.approximate = profile and profile.approximate or nil
    card.first, card.second, card.compare = compareLines(sel)
    card.isChosen = m.chosen ~= nil and m.chosen.code == sel.code
    m.card = card
    return m
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function BuildsWindow:SetTab(tab)
    self.tab, self.selected, self.link, self.message = tab, 1, nil, nil
    self:Refresh()
end

function BuildsWindow:Select(i)
    self.selected, self.link, self.message = i, nil, nil
    self:Refresh()
end

function BuildsWindow:SetSpec(spec)
    self.spec = spec
    self:Refresh()
end

-- A pasted link or code: shown in the card if it reads, else a message.
function BuildsWindow:Paste(text)
    local build, why = ns.Builds.FromLink(text)
    if build then
        self.link, self.message = build, nil
    else
        self.message = why == "bad_code" and L.B_BAD_LINK or L.B_NO_TF
    end
    self.pasting = false
    self:Refresh()
    return build
end

-- "Choose build" for the spec shown, or cancel the choice when it is the chosen one.
function BuildsWindow:ChooseSelected()
    local m = self:Model()
    if not m.selected then return end
    if m.card and m.card.isChosen then
        ns.Builds.Choose(nil, m.spec)
        ns.Print(L.B_UNCHOSEN_MSG, m.spec)
    else
        ns.Builds.Choose(m.selected, m.spec)
        ns.Print(L.B_CHOSEN_MSG, m.spec, m.card.title, m.card.pts)
    end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function specButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(80, 30)
    b.label = W.Font(b, 12, C.muted)
    b.label:SetPoint("CENTER")
    b:SetScript("OnClick", onClick)
    function b.show(text, on, enabled)
        b.label:SetText(text)
        b:SetWidth(math.max(70, (b.label:GetStringWidth() or 0) + 24))
        if on then W.Box(b, C.proc, C.proc, 1, 0.18) else W.Box(b, C.window, C.border) end
        b:SetBackdropBorderColor((on and C.proc or C.border)[1], (on and C.proc or C.border)[2], (on and C.proc or C.border)[3], 1)
        local c = on and C.text or (enabled and C.muted or C.dim)
        b.label:SetTextColor(c[1], c[2], c[3], 1)
        b:EnableMouse(enabled and true or false)
    end
    return b
end

function BuildsWindow:Create()
    if self.frame then return end
    local f = W.Window("ForeverCoachBuilds", L.BUILDS_TITLE, WIDTH, HEIGHT)
    f.subtitle = W.Font(f, 13, C.muted)
    f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.footerLine:ClearAllPoints()
    f.footerLine:SetPoint("BOTTOMLEFT", 1, 40)
    f.footerLine:SetPoint("BOTTOMRIGHT", -1, 40)

    local items = {}
    for i, tab in ipairs(ns.Builds.TABS) do items[i] = { tab, L["B_TAB_" .. tab] } end
    f.tabs = W.Segmented(f, 254, items, function() return self.tab end, function(v) self:SetTab(v) end)
    f.tabs:SetPoint("TOPLEFT", 22, -64)
    f.paste = W.Button(f, L.B_PASTE, 150, false, function()
        self.pasting = not self.pasting
        self:Refresh()
        if self.pasting then f.input:SetFocus() end
    end)
    f.paste:SetPoint("TOPRIGHT", -22, -65)
    f.note = W.Font(f, 12, C.muted)
    f.note:SetPoint("TOPLEFT", 22, -108)
    f.input = W.EditLine(f, WIDTH - 44, function(text) self:Paste(text) end)
    f.input:SetPoint("TOPLEFT", 22, -100)
    f.input:SetScript("OnEscapePressed", function(e)
        e:SetText("")
        e:ClearFocus()
        self.pasting = false
        self:Refresh()
    end)
    f.input:Hide()

    f.rows = {}
    for i = 1, ROWS do
        local row = W.Row(f, 300, ROW_H, function() self:Select(i) end)
        row:SetPoint("TOPLEFT", LIST_X, LIST_Y - (i - 1) * (ROW_H + ROW_GAP))
        row.num = W.Font(row, 13, C.dim)
        row.num:SetPoint("LEFT", 16, 0)
        row.pts = W.Font(row, 15, C.text)
        row.pts:SetPoint("TOPLEFT", 48, -11)
        row.lead = W.Font(row, 13, C.muted)
        row.lead:SetPoint("TOPLEFT", 48, -31)
        row.pill = W.Pill(row, C.good)
        row.pill:SetPoint("RIGHT", -12, 0)
        f.rows[i] = row
    end
    f.empty = W.Font(f, 13, C.muted)
    f.empty:SetPoint("TOPLEFT", LIST_X, LIST_Y - 8)
    f.empty:SetWidth(WIDTH - 44)

    local card = W.Panel(f, CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", CARD_X, LIST_Y)
    card.title = W.Font(card, 18, C.text)
    card.title:SetPoint("TOPLEFT", 18, -18)
    card.pts = W.Font(card, 18, C.muted)
    card.pts:SetPoint("LEFT", card.title, "RIGHT", 10, 0)
    local bar = CreateFrame("Frame", nil, card)
    bar:SetSize(CARD_W - 36, 8)
    bar:SetPoint("TOPLEFT", 18, -54)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(W.FLAT)
    track:SetAllPoints()
    track:SetVertexColor(C.track[1], C.track[2], C.track[3], 1)
    card.bar, card.segments, card.legend = bar, {}, {}
    for i = 1, 3 do
        local seg = bar:CreateTexture(nil, "ARTWORK")
        seg:SetTexture(W.FLAT)
        seg:SetHeight(8)
        card.segments[i] = seg
        local num = W.Font(card, 13, W.TREE_COLORS[i] or C.muted)
        local name = W.Font(card, 13, C.muted)
        if i == 1 then num:SetPoint("TOPLEFT", 18, -72) else num:SetPoint("LEFT", card.legend[i - 1].name, "RIGHT", 18, 0) end
        name:SetPoint("LEFT", num, "RIGHT", 5, 0)
        card.legend[i] = { num = num, name = name }
    end
    card.stats = W.Font(card, 12, C.muted)
    card.stats:SetPoint("TOPLEFT", 18, -98)

    card.rotTitle = W.Section(card, L.B_ROTATION)
    card.rotTitle:SetPoint("TOPLEFT", 18, -132)
    card.rotation, card.arrows = {}, {}
    local colW = (CARD_W - 36) / ROTATION
    for i = 1, ROTATION do
        local slot = W.Icon(card, 36)
        slot:SetPoint("TOPLEFT", 18 + (i - 1) * colW + (colW - 36) / 2, -156)
        slot.label = W.Font(card, 11, C.muted)
        slot.label:SetJustifyH("CENTER")
        slot.label:SetWidth(colW - 4)
        slot.label:SetPoint("TOP", slot, "BOTTOM", 0, -6)
        card.rotation[i] = slot
        if i > 1 then
            local arrow = W.Arrow(card)
            arrow:SetPoint("CENTER", card, "TOPLEFT", 18 + (i - 1) * colW, -174)
            card.arrows[i] = arrow
        end
    end

    -- What joins the rotation later, with levels
    card.later = W.Font(card, 12, C.muted)
    card.later:SetPoint("TOPLEFT", 18, -236)
    card.later:SetWidth(CARD_W - 36)

    local cmpTitle = W.Section(card, L.B_COMPARE)
    cmpTitle:SetPoint("TOPLEFT", 18, -294)
    card.lines = {}
    for i = 1, 2 do
        local mark = W.Mark(card, 14)
        mark:SetPoint("TOPLEFT", 18, -296 - i * 24)
        local text = W.Font(card, 13, C.text)
        text:SetPoint("TOPLEFT", 40, -296 - i * 24)
        text:SetWidth(CARD_W - 60)
        card.lines[i] = { mark = mark, text = text }
    end
    card.auto = W.Font(card, 12, C.muted)
    card.auto:SetPoint("TOPLEFT", 18, -378)
    card.auto:SetWidth(CARD_W - 36)

    card.spec1 = specButton(card, function() self:SetSpec(1) end)
    card.spec1:SetPoint("BOTTOMLEFT", 18, 18)
    card.spec2 = specButton(card, function() self:SetSpec(2) end)
    card.spec2:SetPoint("LEFT", card.spec1, "RIGHT", 8, 0)
    card.choose = W.Button(card, L.B_CHOOSE, 140, true, function() self:ChooseSelected() end)
    card.choose:SetPoint("BOTTOMRIGHT", -18, 14)
    f.card = card

    local footer = W.Font(f, 12, C.muted)
    footer:SetPoint("BOTTOMLEFT", 24, 14)
    footer:SetText(L.B_FOOTER)

    f:SetScript("OnShow", function() self:Draw() end)
    self.frame = f
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end

function BuildsWindow:Draw()
    local f = self.frame
    if not f then return end
    local m = self:Model()
    f.subtitle:SetText("— " .. m.className)
    f.tabs.refresh()
    f.input:SetShown(self.pasting and true or false)
    f.note:SetShown(not self.pasting)
    if self.message then
        f.note:SetText(self.message)
        setColor(f.note, C.dangerText)
    else
        f.note:SetText(m.subtitle or "")
        setColor(f.note, C.muted)
    end

    local list = m.list or {}
    for i, row in ipairs(f.rows) do
        local b = list[i]
        row:SetShown(b ~= nil)
        if b then
            row.num:SetText("#" .. (b.rank or i))
            row.pts:SetText(b.ptsText)
            row.lead:SetText(b.leadName)
            row.select(m.selectedIndex == i)
            if b.chosen then row.pill.set(L.B_CHOSEN, C.gold) elseif b.yours then row.pill.set(L.B_YOURS, C.good) end
            row.pill:SetShown(b.chosen or b.yours or false)
        end
    end
    f.empty:SetShown(not m.available or #list == 0)
    f.empty:SetText(not m.available and L.B_NO_TF or L.B_EMPTY_TAB)

    local card, cm = f.card, m.card
    card:SetShown(cm ~= nil)
    if not cm then return end
    card.title:SetText(cm.title)
    card.pts:SetText(cm.pts)
    local total = 0
    for _, t in ipairs(cm.trees) do total = total + t.pts end
    local x, width = 0, CARD_W - 36
    for i, seg in ipairs(card.segments) do
        local t = cm.trees[i]
        local w = (t and total > 0) and t.pts / total * width or 0
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", card.bar, "LEFT", x, 0)
        seg:SetWidth(math.max(0.01, w))
        if t then seg:SetVertexColor(t.color[1], t.color[2], t.color[3], 1) end
        seg:SetShown(w > 0)
        x = x + w
        local lg = card.legend[i]
        lg.num:SetText(t and tostring(t.pts) or "")
        lg.name:SetText(t and t.name or "")
    end
    card.stats:SetText(cm.stats or "")

    card.rotTitle:SetText(string.format(L.B_ROTATION_AT, m.level))
    for i, ic in ipairs(card.rotation) do
        local r = cm.rotation[i]
        ic:SetShown(r ~= nil)
        ic.label:SetShown(r ~= nil)
        if r then
            ic.set(r.texture, r.proc and C.proc or C.border)
            ic.label:SetText(r.label)
        end
        if card.arrows[i] then card.arrows[i]:SetShown(r ~= nil) end
    end
    card.later:SetText(cm.later or "")

    for i, line in ipairs(card.lines) do
        local l = i == 1 and cm.first or cm.second
        line.mark:Set(l.mark, l.color)
        line.text:SetText(l.text)
    end
    card.auto:SetText(m.chosen and "" or L.B_AUTO)

    card.spec1.show(string.format(L.B_SPEC, 1), m.spec == 1, true)
    card.spec2.show(m.spec2Open and string.format(L.B_SPEC, 2) or string.format(L.B_SPEC2_LOCKED, ns.Builds.SPEC2_LEVEL),
        m.spec == 2, m.spec2Open)
    card.choose.label:SetText(cm.isChosen and L.B_UNCHOOSE or L.B_CHOOSE)
    W.Box(card.choose, cm.isChosen and C.window or C.gold, cm.isChosen and C.border or C.gold)
    setColor(card.choose.label, cm.isChosen and C.text or C.goldDark)
end

function BuildsWindow:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self:Draw() end
end

function BuildsWindow:Refresh()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

local function refresh() BuildsWindow:Refresh() end
Events:On("FC_BUILD_CHOSEN", BuildsWindow, refresh)
Events:On("FC_TALENTS_CHANGED", BuildsWindow, refresh)
Events:On("FC_MODE_CHANGED", BuildsWindow, refresh)
Events:On("PLAYER_LEVEL_UP", BuildsWindow, refresh)
