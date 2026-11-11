-- Combat recap window (/fc recap), as in the mockup:
--   tabs Recent fights / Session / Records;
--   recent fights: the last 10 fights (time, target, accuracy); the selected one: accuracy,
--   debuffs on the target, idle time, missed procs, presses over time, mistakes with the reason,
--   the session against the last one;
--   footer: "No hints" mode (the block hides, the recap keeps counting) and Training (a score
--   after every fight, the best one per build is its record; on any target, Forever has no dummies).
-- Before the first recorded fight the window shows sample data, marked as such.
-- Model() gathers what the window shows; the frames only draw it (the tests check the model).
local ADDON, ns = ...
local L, Events, W = ns.L, ns.Events, ns.Widgets
local Metrics = ns.RecapMetrics
local C = W.C

local RecapWindow = { tab = "fights", selected = 1 }
ns.RecapWindow = RecapWindow

RecapWindow.TABS = { "fights", "session", "records" }
local WIDTH, HEIGHT = 840, 620
local LIST_X, LIST_Y, ROW_W, ROW_H, ROW_STEP = 22, -108, 234, 36, 40
local DX, DW = 273, 546 -- detail column
local CARD_W, CARD_H, CARD_STEP = 130, 95, 139
local ERROR_ROWS, MAX_BLOCKS, SESSION_ROWS, RECORD_ROWS = 3, 90, 8, 6
local IDLE_COLOR = { 0.29, 0.30, 0.34 }

---------------------------------------------------------------------------
-- Sample data (before the first fight), like the mockup
---------------------------------------------------------------------------

local SAMPLE = {
    { "05:41", 24, 14, 12 }, { "05:39", 31, 22, 20 }, { "05:36", 18, 9, 7 }, { "05:34", 22, 12, 10 },
    { "05:31", 27, 13, 12 }, { "05:29", 16, 19, 14 }, { "05:26", 21, 17, 15 }, { "05:24", 19, 10, 8 },
    { "05:21", 25, 13, 11 }, { "05:19", 29, 16, 13 },
}

local function sampleFights()
    local out = {}
    for i, row in ipairs(SAMPLE) do
        local names = L.R_SAMPLE_TARGETS
        out[i] = {
            at = row[1], dur = row[2], presses = row[3], matched = row[4], target = type(names) == "table" and names[i] or "?",
            reactSum = row[3] * 0.35, reactN = row[3], idle = i == 1 and 2.1 or 0, pauses = i == 1 and 1 or 0,
            debuffUp = row[2] * 0.92, debuffTotal = row[2], procs = 0, missed = 0,
            procTalent = { key = "nightfall", id = 18094, level = 25 },
            events = i == 1 and "ooxooo-oooooxoo" or string.rep("o", row[4]) .. string.rep("x", row[3] - row[4]),
            errors = i == 1 and {
                { t = 6, kind = "miss", pressed = "shadow_bolt", pressedId = 686, hint = "corruption", hintId = 172, reason = "down" },
                { t = 13, kind = "idle", gap = 2.1, hint = "curse_of_agony", hintId = 980 },
                { t = 19, kind = "miss", pressed = "shadow_bolt", pressedId = 686, hint = "immolate", hintId = 348, reason = "low" },
            } or {},
        }
    end
    return out
end

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------

local function treeName(en) return ns.Tr("TREE_" .. tostring(en), en or "?") end

local function deltaText(d)
    if not d then return nil end
    local pts = math.floor(d * 100 + (d >= 0 and 0.5 or -0.5))
    return (pts >= 0 and "+" or "-") .. math.abs(pts) .. "%", pts >= 0 and C.good or C.aoe
end

local function procCard(f)
    if (f.procs or 0) > 0 then return tostring(f.missed or 0), ns.Count(f.procs, L.R_PROCS_SUB) end
    local t = f.procTalent
    if t then
        local name = ns.API.SpellName(t.id) or t.key
        return "—", t.level and string.format(L.R_PROCS_TALENT_AT, name, t.level) or string.format(L.R_PROCS_TALENT, name)
    end
    return "0", L.R_PROCS_NONE
end

local function detailOf(f)
    local d = { title = f.target or L.R_NO_TARGET }
    d.meta = string.format(L.R_FIGHT_META, Metrics.Clock(f.dur), f.at or "?") .. (f.blind and L.R_BLIND or "")
    local acc, up = Metrics.Accuracy(f), Metrics.Uptime(f)
    local procValue, procSub = procCard(f)
    d.cards = {
        { label = L.R_ACCURACY, value = Metrics.Percent(acc), sub = string.format(L.R_ACCURACY_SUB, f.matched, f.presses),
          color = Metrics.AccuracyColor(acc, C) },
        { label = L.R_UPTIME, value = up and Metrics.Percent(up) or "—", sub = up and L.R_UPTIME_SUB or L.R_UPTIME_NONE },
        { label = L.R_IDLE, value = string.format(L.R_IDLE_VALUE, Metrics.Seconds(f.idle)), sub = ns.Count(f.pauses or 0, L.R_PAUSES) },
        { label = L.R_PROCS, value = procValue, sub = procSub },
    }
    d.events = f.events or ""
    d.axis = { Metrics.Clock(0), Metrics.Clock((f.dur or 0) / 2), Metrics.Clock(f.dur) }
    d.errors = {}
    for i, e in ipairs(f.errors or {}) do
        local text, reason = Metrics.ErrorText(e)
        d.errors[i] = { time = Metrics.Clock(e.t), text = text, reason = reason, idle = e.kind == "idle" }
    end
    return d
end

local function sessionLine(sum)
    if sum.fights == 0 then return L.R_SESSION_NONE end
    local parts = { ns.Count(sum.fights, L.R_FIGHTS), string.format(L.R_SESSION_AVG, Metrics.Percent(sum.accuracy)) }
    parts[3] = sum.previous and string.format(L.R_SESSION_PREV, Metrics.Percent(sum.previous)) or L.R_SESSION_NO_PREV
    return table.concat(parts, ", ")
end

function RecapWindow:Model()
    local store = ns.Recorder.Store()
    local m = { tab = self.tab, noHints = ns.db.noHints and true or false, training = ns.db.training and true or false }
    local fights = store.fights
    m.sample = #fights == 0
    if m.sample then fights = sampleFights() end

    m.list = {}
    for i, f in ipairs(fights) do
        local acc = Metrics.Accuracy(f)
        m.list[i] = { at = f.at or "", target = f.target or L.R_NO_TARGET, accuracy = Metrics.Percent(acc),
                      color = Metrics.AccuracyColor(acc, C), blind = f.blind }
    end
    m.selected = math.max(1, math.min(self.selected, #fights))
    m.detail = fights[m.selected] and detailOf(fights[m.selected]) or nil

    -- Session: the sample shows the mockup's numbers.
    local sum
    if m.sample then
        sum = { fights = 23, accuracy = 0.84, previous = 0.78, delta = 0.06 }
    else
        sum = Metrics.Session(ns.Recorder.session, store.sessions)
    end
    m.session = { line = sessionLine(sum) }
    m.session.delta, m.session.deltaColor = deltaText(sum.delta)

    if self.tab == "session" then
        local cur = ns.Recorder.session
        m.current = { line = sessionLine(sum) }
        if cur and cur.blind and cur.blind > 0 then
            m.current.blind = string.format(L.R_SESSION_BLIND, ns.Count(cur.blind, L.R_FIGHTS),
                Metrics.Percent(cur.blindAccSum / cur.blind))
        else
            m.current.blind = L.R_SESSION_BLIND_NONE
        end
        m.past = {}
        for i = #store.sessions, 1, -1 do
            local s = store.sessions[i]
            if s ~= cur and s.fights > 0 and #m.past < SESSION_ROWS then
                m.past[#m.past + 1] = { at = s.at or "?", fights = ns.Count(s.fights, L.R_FIGHTS), accuracy = s.accSum / s.fights }
            end
        end
    elseif self.tab == "records" then
        m.records = {}
        for _, rec in pairs(store.records) do
            m.records[#m.records + 1] = {
                name = treeName(rec.build) .. ", " .. ns.Tr("MODE_" .. tostring(rec.mode), rec.mode or ""),
                score = rec.score, sub = string.format(L.R_RECORD_SUB, rec.accuracy or 0, rec.speed or 0, rec.at or "?"),
            }
        end
        table.sort(m.records, function(a, b) return a.score > b.score end)
    end
    return m
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function RecapWindow:SetTab(tab)
    self.tab = tab
    self:Refresh()
end

function RecapWindow:Select(i)
    self.selected = i
    self:Refresh()
end

function RecapWindow.SetNoHints(on)
    ns.db.noHints = on and true or false
    ns.Print(on and L.R_NOHINTS_ON or L.R_NOHINTS_OFF)
    Events:Fire("FC_SETTINGS_CHANGED", "noHints")
    Events:Fire("FC_DIRTY")
end

function RecapWindow.SetTraining(on)
    ns.db.training = on and true or false
    ns.Print(on and L.R_TRAINING_STARTED or L.R_TRAINING_STOPPED)
    RecapWindow:Refresh()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end

local function flat(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(W.FLAT)
    return t
end

function RecapWindow:Create()
    if self.frame then return end
    local f = W.Window("ForeverCoachRecap", L.RECAP_TITLE, WIDTH, HEIGHT)
    f.badge = W.Pill(f, C.muted)
    f.badge:SetPoint("TOPRIGHT", -50, -15)

    -- Tabs: text with a gold underline under the open one.
    f.tabs = {}
    local x = 22
    for i, tab in ipairs(RecapWindow.TABS) do
        local b = CreateFrame("Button", nil, f)
        b.label = W.Font(b, 14, C.muted)
        b.label:SetPoint("LEFT", 10, 0)
        b.label:SetText(L["R_TAB_" .. tab])
        local w = math.max(60, (b.label:GetStringWidth() or 0) + 20)
        b:SetSize(w, 30)
        b:SetPoint("TOPLEFT", x, -60)
        b.line = flat(b, "OVERLAY")
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 0, -6)
        b.line:SetPoint("BOTTOMRIGHT", 0, -6)
        b.line:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
        b:SetScript("OnClick", function() self:SetTab(tab) end)
        b.tab = tab
        f.tabs[i] = b
        x = x + w + 6
    end
    local sep = W.Line(f)
    sep:SetPoint("TOPLEFT", 1, -96)
    sep:SetPoint("TOPRIGHT", -1, -96)

    -- Recent fights: list ---------------------------------------------------------
    local fightsView = CreateFrame("Frame", nil, f)
    fightsView:SetAllPoints()
    f.fights = fightsView
    fightsView.rows = {}
    for i = 1, ns.RecapMetrics.FIGHTS_KEPT do
        local row = W.Row(fightsView, ROW_W, ROW_H, function() self:Select(i) end)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_X, LIST_Y - (i - 1) * ROW_STEP)
        row.at = W.Font(row, 12, C.dim)
        row.at:SetPoint("LEFT", 10, 0)
        row.target = W.Font(row, 13, C.text)
        row.target:SetPoint("LEFT", 58, 0)
        row.target:SetWidth(ROW_W - 120)
        row.target:SetWordWrap(false)
        row.acc = W.Font(row, 13, C.text)
        row.acc:SetPoint("RIGHT", -12, 0)
        row.acc:SetJustifyH("RIGHT")
        fightsView.rows[i] = row
    end

    -- Recent fights: the selected fight ---------------------------------------------
    local title = W.Font(fightsView, 17, C.text)
    title:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -112)
    local meta = W.Font(fightsView, 13, C.muted)
    meta:SetPoint("LEFT", title, "RIGHT", 10, 0)
    fightsView.title, fightsView.meta = title, meta

    fightsView.cards = {}
    for i = 1, 4 do
        local card = W.Panel(fightsView, CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", f, "TOPLEFT", DX + (i - 1) * CARD_STEP, -143)
        card.label = W.Font(card, 12, C.muted)
        card.label:SetPoint("TOPLEFT", 14, -14)
        card.label:SetWidth(CARD_W - 24)
        card.value = W.Font(card, 21, C.text)
        card.value:SetPoint("TOPLEFT", 14, -40)
        card.sub = W.Font(card, 11, C.muted)
        card.sub:SetPoint("TOPLEFT", 14, -68)
        card.sub:SetWidth(CARD_W - 24)
        fightsView.cards[i] = card
    end

    local tl = W.Section(fightsView, L.R_TIMELINE)
    tl:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -254)
    local bar = CreateFrame("Frame", nil, fightsView)
    bar:SetSize(DW, 27)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -273)
    fightsView.bar, fightsView.blocks = bar, {}
    fightsView.axis = {}
    for i, point in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
        local fs = W.Font(fightsView, 11, C.dim)
        fs:SetPoint("TOP" .. (point == "CENTER" and "" or point), bar, "BOTTOM" .. (point == "CENTER" and "" or point), 0, -6)
        fs:SetJustifyH(point)
        fightsView.axis[i] = fs
    end
    local legend = { { C.proc, L.R_LEGEND_OK }, { C.aoe, L.R_LEGEND_OTHER }, { IDLE_COLOR, L.R_LEGEND_IDLE } }
    local prev
    for _, item in ipairs(legend) do
        local sq = flat(fightsView)
        sq:SetSize(9, 9)
        sq:SetVertexColor(item[1][1], item[1][2], item[1][3], 1)
        if prev then sq:SetPoint("LEFT", prev, "RIGHT", 16, 0) else sq:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -330) end
        local fs = W.Font(fightsView, 12, C.muted)
        fs:SetPoint("LEFT", sq, "RIGHT", 6, 0)
        fs:SetText(item[2])
        prev = fs
    end

    local errTitle = W.Section(fightsView, L.R_ERRORS)
    errTitle:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -356)
    fightsView.errors = {}
    for i = 1, ERROR_ROWS do
        local row = W.Panel(fightsView, DW, 32)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -375 - (i - 1) * 38)
        row.time = W.Font(row, 12, C.aoe)
        row.time:SetPoint("LEFT", 12, 0)
        row.text = W.Font(row, 13, C.text)
        row.text:SetPoint("LEFT", 54, 0)
        row.reason = W.Font(row, 13, C.muted)
        row.reason:SetPoint("LEFT", row.text, "RIGHT", 0, 0)
        row.reason:SetPoint("RIGHT", -10, 0)
        row.reason:SetWordWrap(false)
        fightsView.errors[i] = row
    end
    fightsView.noErrors = W.Font(fightsView, 13, C.muted)
    fightsView.noErrors:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -382)
    fightsView.moreErrors = W.Font(fightsView, 12, C.muted)
    fightsView.moreErrors:SetPoint("TOPRIGHT", f, "TOPLEFT", DX + DW, -357)
    fightsView.moreErrors:SetJustifyH("RIGHT")

    local sess = CreateFrame("Frame", nil, fightsView, "BackdropTemplate")
    sess:SetSize(DW, 37)
    sess:SetPoint("TOPLEFT", f, "TOPLEFT", DX, -490)
    W.Box(sess, C.proc, C.proc, 1, 0.08)
    sess:SetBackdropBorderColor(C.proc[1], C.proc[2], C.proc[3], 0.6)
    sess.label = W.Font(sess, 13, C.text)
    sess.label:SetPoint("LEFT", 14, 0)
    sess.label:SetText(L.R_SESSION)
    sess.text = W.Font(sess, 13, C.muted)
    sess.text:SetPoint("LEFT", sess.label, "RIGHT", 8, 0)
    sess.delta = W.Font(sess, 13, C.good)
    sess.delta:SetPoint("RIGHT", -14, 0)
    sess.delta:SetJustifyH("RIGHT")
    fightsView.session = sess

    -- Session tab -----------------------------------------------------------------
    local sessionView = CreateFrame("Frame", nil, f)
    sessionView:SetAllPoints()
    f.sessionView = sessionView
    local curTitle = W.Section(sessionView, L.R_SESSION_TITLE)
    curTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -118)
    sessionView.line = W.Font(sessionView, 15, C.text)
    sessionView.line:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -142)
    sessionView.line:SetWidth(WIDTH - 44)
    sessionView.delta = W.Font(sessionView, 15, C.good)
    sessionView.delta:SetPoint("TOPRIGHT", f, "TOPLEFT", WIDTH - 22, -142)
    sessionView.delta:SetJustifyH("RIGHT")
    sessionView.blind = W.Font(sessionView, 13, C.muted)
    sessionView.blind:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -170)
    sessionView.blind:SetWidth(WIDTH - 44)
    local pastTitle = W.Section(sessionView, L.R_SESSIONS_PAST)
    pastTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -214)
    sessionView.none = W.Font(sessionView, 13, C.muted)
    sessionView.none:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -240)
    sessionView.rows = {}
    for i = 1, SESSION_ROWS do
        local y = -238 - (i - 1) * 34
        local row = {}
        row.at = W.Font(sessionView, 13, C.muted)
        row.at:SetPoint("TOPLEFT", f, "TOPLEFT", 22, y)
        row.fights = W.Font(sessionView, 13, C.text)
        row.fights:SetPoint("TOPLEFT", f, "TOPLEFT", 150, y)
        row.track = flat(sessionView, "BACKGROUND")
        row.track:SetSize(420, 8)
        row.track:SetPoint("TOPLEFT", f, "TOPLEFT", 270, y - 4)
        row.track:SetVertexColor(C.track[1], C.track[2], C.track[3], 1)
        row.fill = flat(sessionView)
        row.fill:SetHeight(8)
        row.fill:SetPoint("LEFT", row.track, "LEFT", 0, 0)
        row.acc = W.Font(sessionView, 13, C.text)
        row.acc:SetPoint("TOPRIGHT", f, "TOPLEFT", WIDTH - 22, y)
        row.acc:SetJustifyH("RIGHT")
        sessionView.rows[i] = row
    end

    -- Records tab -----------------------------------------------------------------
    local recordsView = CreateFrame("Frame", nil, f)
    recordsView:SetAllPoints()
    f.recordsView = recordsView
    local recTitle = W.Section(recordsView, L.R_RECORDS_TITLE)
    recTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -118)
    recordsView.none = W.Font(recordsView, 13, C.muted)
    recordsView.none:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -144)
    recordsView.none:SetWidth(WIDTH - 44)
    recordsView.rows = {}
    for i = 1, RECORD_ROWS do
        local row = W.Panel(recordsView, WIDTH - 44, 50)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -140 - (i - 1) * 57)
        row.name = W.Font(row, 14, C.text)
        row.name:SetPoint("TOPLEFT", 16, -9)
        row.sub = W.Font(row, 12, C.muted)
        row.sub:SetPoint("TOPLEFT", 16, -28)
        row.score = W.Font(row, 20, C.gold)
        row.score:SetPoint("RIGHT", -16, 0)
        row.score:SetJustifyH("RIGHT")
        recordsView.rows[i] = row
    end
    recordsView.help = W.Font(recordsView, 12, C.muted)
    recordsView.help:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 76)
    recordsView.help:SetWidth(WIDTH - 44)
    recordsView.help:SetText(L.R_SCORE_HELP)

    -- Footer ----------------------------------------------------------------------
    f.noHints = W.Check(f, L.R_NOHINTS, function() return ns.db.noHints end, function(v) RecapWindow.SetNoHints(v) end)
    f.noHints:SetPoint("BOTTOMLEFT", 24, 22)
    local note = W.Font(f, 12, C.muted)
    note:SetPoint("LEFT", f.noHints.text, "RIGHT", 12, 0)
    note:SetText(L.R_NOHINTS_NOTE)
    f.training = W.Button(f, L.R_TRAINING, 178, false, function() RecapWindow.SetTraining(not ns.db.training) end)
    f.training:SetPoint("BOTTOMRIGHT", -22, 13)

    f:SetScript("OnShow", function() self:Draw() end)
    self.frame = f
end

local function drawBlocks(view, events)
    local n = math.min(#events, MAX_BLOCKS)
    local gap = n <= 30 and 4 or (n <= 60 and 2 or 1)
    local w = n > 0 and (DW - (n - 1) * gap) / n or 0
    for i = 1, math.max(n, #view.blocks) do
        local b = view.blocks[i]
        if i <= n then
            if not b then
                b = flat(view.bar)
                b:SetHeight(27)
                view.blocks[i] = b
            end
            local kind = events:sub(#events - n + i, #events - n + i) -- the last blocks of a very long fight
            local c = kind == "o" and C.proc or (kind == "x" and C.aoe or IDLE_COLOR)
            b:SetVertexColor(c[1], c[2], c[3], 1)
            b:ClearAllPoints()
            b:SetPoint("LEFT", view.bar, "LEFT", (i - 1) * (w + gap), 0)
            b:SetWidth(math.max(1, w))
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

function RecapWindow:Draw()
    local f = self.frame
    if not f then return end
    local m = self:Model()
    f.badge.set(L.R_SAMPLE, C.muted)
    f.badge:SetShown(m.sample and m.tab == "fights")
    for _, b in ipairs(f.tabs) do
        local on = b.tab == m.tab
        setColor(b.label, on and C.text or C.muted)
        b.line:SetShown(on)
    end
    f.fights:SetShown(m.tab == "fights")
    f.sessionView:SetShown(m.tab == "session")
    f.recordsView:SetShown(m.tab == "records")
    f.noHints.refresh()
    f.training.label:SetText(m.training and L.R_TRAINING_ON or L.R_TRAINING)
    W.Box(f.training, m.training and C.gold or C.window, m.training and C.gold or C.border)
    setColor(f.training.label, m.training and C.goldDark or C.text)

    if m.tab == "fights" then
        local v = f.fights
        for i, row in ipairs(v.rows) do
            local it = m.list[i]
            row:SetShown(it ~= nil)
            if it then
                row.at:SetText(it.at)
                row.target:SetText(it.target)
                row.acc:SetText(it.accuracy)
                setColor(row.acc, it.color)
                row.select(i == m.selected)
            end
        end
        local d = m.detail
        if d then
            v.title:SetText(d.title)
            v.meta:SetText(d.meta)
            for i, card in ipairs(v.cards) do
                local c = d.cards[i]
                card.label:SetText(c.label)
                card.value:SetText(c.value)
                setColor(card.value, c.color or C.text)
                card.sub:SetText(c.sub)
            end
            drawBlocks(v, d.events)
            for i, fs in ipairs(v.axis) do fs:SetText(d.axis[i]) end
            for i, row in ipairs(v.errors) do
                local e = d.errors[i]
                row:SetShown(e ~= nil)
                if e then
                    row.time:SetText(e.time)
                    row.text:SetText(e.text)
                    row.reason:SetText(e.reason and (" — " .. e.reason) or "")
                end
            end
            v.noErrors:SetShown(#d.errors == 0)
            v.noErrors:SetText(L.R_NO_ERRORS)
            v.moreErrors:SetShown(#d.errors > ERROR_ROWS)
            v.moreErrors:SetText(string.format(L.R_MORE_ERRORS, #d.errors - ERROR_ROWS))
        end
        v.session.text:SetText(m.session.line)
        v.session.delta:SetText(m.session.delta or "")
        if m.session.deltaColor then setColor(v.session.delta, m.session.deltaColor) end
    elseif m.tab == "session" then
        local v = f.sessionView
        v.line:SetText(m.current.line)
        v.delta:SetText(m.session.delta or "")
        if m.session.deltaColor then setColor(v.delta, m.session.deltaColor) end
        v.blind:SetText(m.current.blind)
        v.none:SetShown(#m.past == 0)
        v.none:SetText(L.R_SESSIONS_NONE)
        for i, row in ipairs(v.rows) do
            local p = m.past[i]
            for _, part in ipairs({ row.at, row.fights, row.track, row.fill, row.acc }) do part:SetShown(p ~= nil) end
            if p then
                row.at:SetText(p.at)
                row.fights:SetText(p.fights)
                row.fill:SetWidth(math.max(1, 420 * p.accuracy))
                local c = Metrics.AccuracyColor(p.accuracy, C)
                row.fill:SetVertexColor(c[1], c[2], c[3], 1)
                row.acc:SetText(Metrics.Percent(p.accuracy))
            end
        end
    else
        local v = f.recordsView
        v.none:SetShown(#m.records == 0)
        v.none:SetText(L.R_RECORDS_NONE)
        for i, row in ipairs(v.rows) do
            local r = m.records[i]
            row:SetShown(r ~= nil)
            if r then
                row.name:SetText(r.name)
                row.sub:SetText(r.sub)
                row.score:SetText(tostring(r.score))
            end
        end
    end
end

function RecapWindow:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self:Draw() end
end

function RecapWindow:Refresh()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

Events:On("FC_FIGHT_RECORDED", RecapWindow, function(self)
    self.selected = 1
    self:Refresh()
end)
Events:On("FC_SETTINGS_CHANGED", RecapWindow, function(self) self:Refresh() end)
