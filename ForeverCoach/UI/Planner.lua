-- Planner window (/fc plan), as in the mockup:
--   left:  what waits at the trainer (count, price, who and where); what the build's rotation
--          still needs, with a status per line (at the trainer, talent, not on the bars,
--          opens at level N, class quest)
--   right: a preview of a level ahead (what is new, the rotation there); class quests
-- Model() gathers what the window shows; the frames only draw it (the tests check the model).
local ADDON, ns = ...
local L, API, Data, Events, W = ns.L, ns.API, ns.Data, ns.Events, ns.Widgets
local Planner = ns.Planner
local C = W.C

local PlannerWindow = { at = nil }
ns.PlannerWindow = PlannerWindow

local WIDTH, HEIGHT = 840, 660
local LEFT_X, LEFT_W = 22, 480
local RIGHT_X, RIGHT_W = 520, 298
local NEED_ROWS, NEED_H, NEED_GAP = 6, 50, 7
local TALENT_LINES, ROTATION, QUESTS, LEVELS, SITU_ROWS, SITU_ICONS = 3, 5, 4, 6, 6, 6

local STATUS_COLOR = { trainer = C.gold, talent = C.proc, nobar = C.danger, level = C.muted, quest = C.teal }

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------

local function treeName(en) return ns.Tr("TREE_" .. tostring(en), en or "?") end

local function ptsText(pts)
    local parts = {}
    for i, p in ipairs(pts or {}) do parts[i] = tostring(p) end
    return table.concat(parts, " / ")
end

local function note(key) return ns.Tr("NOTE_" .. tostring(key), nil) end

local function spellName(id, key) return API.SpellName(id) or key end

-- The build the plan is for: the chosen one, else the player's own points.
local function buildOf(def)
    local chosen = ns.Builds.Chosen()
    if chosen then return chosen.lead, chosen.pts, chosen end
    local pts = ns.State.treePoints
    local lead = ns.BuildMatcher.DominantTree(pts, def.trees)
    return lead, pts, nil
end

-- The chosen build's talent ranks, if Talents Forever can read the build.
local function chosenRanks(def, chosen)
    local TF = ns.TalentsForever
    if not (chosen and TF and TF.Available()) then return nil end
    return (TF.Decode(def.token, chosen.code))
end

-- The chosen build's next talent point.
local function nextTalent(def, ranks, level)
    if not ranks then return nil end
    local TF = ns.TalentsForever
    local unspent = API.TalentPoints(TF.TreeID(def.token))
    local c = ns.Builds.Compare(ranks, ns.State.traits or {}, level, unspent)
    if c.next then c.next.unspent = unspent end
    return c.next
end

-- Talent keys the plan takes: from the chosen build, else the key talents of the profile.
local function buildTalents(def, ranks, profile)
    local set = {}
    if ranks then
        for key, t in pairs(def.talents or {}) do
            if (ranks[t.ids[1]] or 0) > 0 then set[key] = true end
        end
    elseif profile and profile.talents then
        for key in pairs(profile.talents) do set[key] = true end
    end
    return set
end

local function needRow(item, level)
    local row = { key = item.key, status = item.status, id = item.id, texture = API.SpellTexture(item.id) }
    local name = item.name or spellName(item.id, item.key)
    if item.status == "trainer" and (item.rank or 1) > 1 then name = name .. string.format(L.P_RANK, item.rank) end
    row.name = name
    local n = note(item.key)
    if item.status == "trainer" then
        row.sub = Planner.Money(item.cost) .. (n and (" — " .. n) or "")
        row.pill = L.P_ST_trainer
    elseif item.status == "talent" then
        if item.key:find("^talent:") then
            row.sub = item.now and ns.Count(math.max(1, item.unspent or 1), L.P_SUB_TALENT_NOW)
                or string.format(L.P_SUB_TALENT_AT, item.level or level + 1)
        else
            row.sub = L.P_SUB_TALENT_SPELL
        end
        row.pill = L.P_ST_talent
    elseif item.status == "nobar" then
        row.sub = L.P_SUB_NOBAR
        row.pill = L.P_ST_nobar
    elseif item.status == "level" then
        row.sub = ns.Count(math.max(1, (item.level or level) - level), L.P_SUB_LEVEL)
        row.pill = string.format(L.P_ST_level, item.level or level)
    else -- quest
        row.sub = L.P_SUB_QUEST
        row.pill = string.format(L.P_ST_quest, item.level or level)
    end
    row.color = STATUS_COLOR[item.status] or C.muted
    return row
end

-- Everything the window shows for the level preview `at` (default: the second level offered).
function PlannerWindow:Model()
    local def = Data.class
    local m = { available = def ~= nil }
    if not def then return m end
    local s = ns.State:Refresh(GetTime())
    local level = s.player.level
    m.level = level

    local lead, pts, chosen = buildOf(def)
    m.subtitle = "— " .. string.format(L.P_LEVEL, level)
    if lead then m.subtitle = m.subtitle .. ", " .. treeName(lead) .. " " .. ptsText(pts) end

    -- Trainer
    local sum = Planner.TrainerSummary(def, level, s.knownRank, s.talents)
    local trainer = Planner.Trainer(def)
    local t = { count = sum.count }
    if sum.count > 0 then
        t.title = ns.Count(sum.count, L.P_TRAINER_WAITS)
        t.price = Planner.Money(sum.cost) .. (sum.unknownCost and " +" or "")
    else
        t.title = L.P_TRAINER_NONE
        local nextAt = Planner.NextTrainerLevel(def, level, s.knownRank, s.talents)
        t.price = nextAt and string.format(L.P_TRAINER_NEXT, nextAt) or nil
    end
    if trainer then
        local where = trainer.npc or ""
        if trainer.place and trainer.place ~= "" then where = where .. ", " .. trainer.place end
        if trainer.x and trainer.y then where = where .. string.format(" (%.1f, %.1f)", trainer.x, trainer.y) end
        t.where = where
    else
        t.where = L.P_TRAINER_UNKNOWN
    end
    t.sub = t.price and (t.price .. " — " .. t.where) or t.where
    m.trainer = t

    -- What the rotation needs
    local profile = ns.BuildMatcher.profile
    local onBars = function(key) return ns.ActionBars:IsOnBars(key) end
    local ranks = chosenRanks(def, chosen)
    local talentItem = nextTalent(def, ranks, level)
    local needs = Planner.Needs(def, profile, s, level, onBars, talentItem, buildTalents(def, ranks, profile))
    m.needs = {}
    for i, item in ipairs(needs) do
        if item.key:find("^talent:") and talentItem then item.unspent = talentItem.unspent end
        m.needs[i] = needRow(item, level)
    end

    -- Level preview: now, the levels where this build's hints change, and 60.
    m.levels = Planner.Milestones(def, profile, s, level, ranks, LEVELS)
    local at = self.at
    local offered = false
    for _, l in ipairs(m.levels) do if l == at then offered = true end end
    if not offered then at = m.levels[2] or m.levels[1] end
    m.at = at
    local fromTrainer = #Planner.NewAt(def, level, at, s.talents)
    m.trainerAt = fromTrainer > 0 and (string.format(L.P_TRAINER_AT, at) .. ns.Count(fromTrainer, L.P_NEW_SPELLS)) or nil

    -- The chosen build's talents up to that level: those that change the hints by name, the rest
    -- as a number of points.
    local planned
    if ranks then
        local TF = ns.TalentsForever
        local unspent = API.TalentPoints(TF.TreeID(def.token))
        local points
        planned, points = Planner.TalentsAt(def, ranks, ns.State.traits or {}, level, at, unspent)
        m.talents = {}
        local other = 0
        for _, e in ipairs(planned) do
            if e.key then
                m.talents[#m.talents + 1] = e.now and string.format(L.P_TALENT_NOW, e.name, e.to, e.max)
                    or string.format(L.P_TALENT_AT, e.name, e.to, e.max, e.first)
            else
                other = other + (e.to - e.from)
            end
        end
        if other > 0 then m.talents[#m.talents + 1] = ns.Count(other, L.P_TALENTS_OTHER) end
        m.talentPoints = points
        if points == 0 then m.talentNote = L.P_TALENTS_NONE end
    else
        m.talentNote = L.P_TALENTS_NO_BUILD
    end

    -- The rotation on one target now and at that level (distinct actions in priority order; the
    -- proc once the talent that gives it is there). New ones at that level are marked.
    local function rotation(atLevel, talents, actual)
        local out = {}
        for _, r in ipairs(Planner.Distinct(Planner.RotationAt(def, ns.Loop.current, atLevel, s, 8, talents, actual))) do
            if #out < ROTATION then out[#out + 1] = { key = r.key, id = r.id, texture = API.SpellTexture(r.id) } end
        end
        for _, b in pairs(def.buffs or {}) do
            local sp = b.glow and def.spells[b.glow]
            if sp and b.talent and ((talents or s.talents)[b.talent] or 0) > 0 and #out < ROTATION then
                out[#out + 1] = { key = "proc:" .. b.glow, id = sp.ranks[1][1], proc = true,
                                  texture = API.SpellTexture(s.known[b.glow] or sp.ranks[1][1]) }
            end
        end
        return out
    end
    m.rotationNow = rotation(level, nil, true) -- what the live hint uses: learned spells, taken talents
    m.rotation = rotation(at, planned and Planner.TalentKeysAt(def, s.talents, planned) or nil)
    local before = {}
    for _, r in ipairs(m.rotationNow) do before[r.key] = true end
    for _, r in ipairs(m.rotation) do r.new = not before[r.key] end

    -- What the build uses only in a situation at that level (finisher, low health, 3+ enemies...).
    local usable = {}
    for _, g in ipairs(Planner.Situational(def, profile, s, level, level, ranks)) do
        for _, sp in ipairs(g.spells) do usable[g.kind .. sp.key] = true end
    end
    m.situational = {}
    for _, g in ipairs(Planner.Situational(def, profile, s, level, at, ranks)) do
        local row = { kind = g.kind, label = L["P_KIND_" .. g.kind], icons = {} }
        for _, sp in ipairs(g.spells) do
            row.icons[#row.icons + 1] = { key = sp.key, id = sp.id, texture = API.SpellTexture(sp.id),
                                          new = not usable[g.kind .. sp.key] }
        end
        for _, x in ipairs(row.icons) do row.new = row.new or x.new end
        m.situational[#m.situational + 1] = row
    end
    -- what is new at that level first (the kinds' own order inside)
    for i, row in ipairs(m.situational) do row.order = i end
    table.sort(m.situational, function(a, b)
        if (a.new or false) ~= (b.new or false) then return a.new == true end
        return a.order < b.order
    end)

    -- Class quests
    m.quests = {}
    for i, q in ipairs(Planner.Quests(def, s.known, level)) do
        m.quests[i] = { level = q.level, name = ns.Tr("QUEST_" .. q.key, q.key), done = q.done }
    end
    return m
end

function PlannerWindow:SetLevel(at)
    self.at = at
    self:Refresh()
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], 1) end

function PlannerWindow:Create()
    if self.frame then return end
    local f = W.Window("ForeverCoachPlanner", L.PLANNER_TITLE, WIDTH, HEIGHT)
    f.subtitle = W.Font(f, 13, C.muted)
    f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.footerLine:Hide()

    -- Trainer card
    local tr = CreateFrame("Frame", nil, f, "BackdropTemplate")
    tr:SetSize(LEFT_W, 62)
    tr:SetPoint("TOPLEFT", LEFT_X, -66)
    W.Box(tr, C.goldDark, C.gold, 1, 0.9)
    tr.icon = W.Icon(tr, 34)
    tr.icon:SetPoint("LEFT", 14, 0)
    tr.icon.set("Interface\\Icons\\INV_Misc_Coin_02", C.gold)
    tr.title = W.Font(tr, 15, C.text)
    tr.title:SetPoint("TOPLEFT", 62, -12)
    tr.sub = W.Font(tr, 12, C.muted)
    tr.sub:SetPoint("TOPLEFT", 62, -34)
    tr.sub:SetWidth(LEFT_W - 76)
    f.trainer = tr

    local needsTitle = W.Section(f, L.P_NEEDS)
    needsTitle:SetPoint("TOPLEFT", LEFT_X, -148)
    f.needs = {}
    for i = 1, NEED_ROWS do
        local row = W.Panel(f, LEFT_W, NEED_H)
        row:SetPoint("TOPLEFT", LEFT_X, -170 - (i - 1) * (NEED_H + NEED_GAP))
        row.icon = W.Icon(row, 32)
        row.icon:SetPoint("LEFT", 10, 0)
        row.name = W.Font(row, 14, C.text)
        row.name:SetPoint("TOPLEFT", 54, -9)
        row.sub = W.Font(row, 12, C.muted)
        row.sub:SetPoint("TOPLEFT", 54, -28)
        row.sub:SetWidth(LEFT_W - 190)
        row.pill = W.Pill(row, C.gold)
        row.pill:SetPoint("RIGHT", -12, 0)
        row.more = W.Font(row, 13, C.muted)
        row.more:SetPoint("LEFT", 16, 0)
        f.needs[i] = row
    end
    f.needsNone = W.Font(f, 13, C.muted)
    f.needsNone:SetPoint("TOPLEFT", LEFT_X, -176)

    -- Class quests: one compact block under the list
    local qsTitle = W.Section(f, L.P_QUESTS)
    qsTitle:SetPoint("TOPLEFT", LEFT_X, -528)
    f.quests = {}
    for i = 1, QUESTS do
        local x, y = LEFT_X + ((i - 1) % 2) * 240, -552 - math.floor((i - 1) / 2) * 26
        local r = {}
        r.mark = W.Mark(f, 13)
        r.mark:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        r.level = W.Font(f, 13, C.muted)
        r.level:SetPoint("TOPLEFT", f, "TOPLEFT", x + 22, y)
        r.name = W.Font(f, 13, C.text)
        r.name:SetPoint("TOPLEFT", f, "TOPLEFT", x + 52, y)
        f.quests[i] = r
    end

    -- Level preview
    local pv = W.Panel(f, RIGHT_W, 560)
    pv:SetPoint("TOPLEFT", RIGHT_X, -66)
    local pvTitle = W.Section(pv, L.P_PREVIEW)
    pvTitle:SetPoint("TOPLEFT", 18, -18)
    pv.levels = {}
    for i = 1, LEVELS do
        local b = CreateFrame("Button", nil, pv, "BackdropTemplate")
        b:SetSize(40, 32)
        b:SetPoint("TOPLEFT", 18 + (i - 1) * 44, -42)
        b.label = W.Font(b, 13, C.text)
        b.label:SetPoint("CENTER")
        b.label:SetJustifyH("CENTER")
        b:SetScript("OnClick", function() if b.level then self:SetLevel(b.level) end end)
        pv.levels[i] = b
    end
    -- The chosen build's talents up to that level
    pv.talTitle = W.Font(pv, 12, C.muted)
    pv.talTitle:SetPoint("TOPLEFT", 18, -92)
    pv.talents = {}
    for i = 1, TALENT_LINES do
        local mark = W.Font(pv, 13, C.proc)
        mark:SetPoint("TOPLEFT", 18, -112 - (i - 1) * 22)
        mark:SetText("+")
        local text = W.Font(pv, 13, C.text)
        text:SetPoint("TOPLEFT", 34, -112 - (i - 1) * 22)
        text:SetWidth(RIGHT_W - 52)
        text:SetWordWrap(false)
        pv.talents[i] = { mark = mark, text = text }
    end
    pv.talNote = W.Font(pv, 12, C.muted)
    pv.talNote:SetPoint("TOPLEFT", 18, -112)
    pv.talNote:SetWidth(RIGHT_W - 36)
    -- Two rows: the rotation on one target now and at that level, new actions in a gold frame.
    local function iconRow(y)
        local row = { icons = {}, arrows = {} }
        row.title = W.Font(pv, 12, C.muted)
        row.title:SetPoint("TOPLEFT", 18, y)
        for i = 1, ROTATION do
            local ic = W.Icon(pv, 30)
            ic:SetPoint("TOPLEFT", 18 + (i - 1) * 48, y - 20)
            row.icons[i] = ic
            if i > 1 then
                local arrow = W.Arrow(pv)
                arrow:SetPoint("CENTER", pv, "TOPLEFT", 18 + (i - 1) * 48 - 9, y - 35)
                row.arrows[i] = arrow
            end
        end
        return row
    end
    pv.rotNow = iconRow(-188)
    pv.rotAt = iconRow(-252)
    -- What comes into play in a situation at that level
    pv.situTitle = W.Font(pv, 12, C.muted)
    pv.situTitle:SetPoint("TOPLEFT", 18, -318)
    pv.situ = {}
    for i = 1, SITU_ROWS do
        local y = -340 - (i - 1) * 32
        local row = { icons = {} }
        row.label = W.Font(pv, 12, C.text)
        row.label:SetPoint("TOPLEFT", 18, y - 6)
        row.label:SetWidth(100)
        row.label:SetWordWrap(false)
        for j = 1, SITU_ICONS do
            local ic = W.Icon(pv, 24)
            ic:SetPoint("TOPLEFT", 122 + (j - 1) * 28, y)
            row.icons[j] = ic
        end
        pv.situ[i] = row
    end
    pv.situNone = W.Font(pv, 12, C.muted)
    pv.situNone:SetPoint("TOPLEFT", 18, -340)
    pv.trainerAt = W.Font(pv, 12, C.muted)
    pv.trainerAt:SetPoint("TOPLEFT", 18, -536)
    pv.trainerAt:SetWidth(RIGHT_W - 36)
    pv.help = W.Font(pv, 11, C.dim)
    pv.help:SetPoint("BOTTOMLEFT", 18, 16)
    pv.help:SetWidth(RIGHT_W - 36)
    pv.help:SetText(L.P_ORDER_HELP)
    f.preview = pv

    f:SetScript("OnShow", function() self:Draw() end)
    self.frame = f
end

function PlannerWindow:Draw()
    local f = self.frame
    if not f then return end
    local m = self:Model()
    if not m.available then return end
    f.subtitle:SetText(m.subtitle)

    local tr = f.trainer
    tr.title:SetText(m.trainer.title)
    tr.sub:SetText(m.trainer.sub)

    local needs = m.needs
    local shown = #needs > NEED_ROWS and NEED_ROWS - 1 or #needs
    for i, row in ipairs(f.needs) do
        local it = needs[i]
        local isMore = #needs > NEED_ROWS and i == NEED_ROWS
        row:SetShown(it ~= nil and (i <= shown or isMore))
        row.more:SetShown(isMore)
        row.icon:SetShown(not isMore)
        row.name:SetShown(not isMore)
        row.sub:SetShown(not isMore)
        row.pill:SetShown(not isMore)
        if isMore then
            row.more:SetText(string.format(L.P_MORE, #needs - shown))
        elseif it then
            row.icon.set(it.texture, it.color)
            row.name:SetText(it.name)
            row.sub:SetText(it.sub)
            row.pill.set(it.pill, it.color)
        end
    end
    f.needsNone:SetShown(#needs == 0)
    f.needsNone:SetText(L.P_NEEDS_NONE)

    local pv = f.preview
    for i, b in ipairs(pv.levels) do
        local l = m.levels[i]
        b:SetShown(l ~= nil)
        b.level = l
        if l then
            b.label:SetText(tostring(l))
            local on = l == m.at
            W.Box(b, on and C.gold or C.window, on and C.gold or C.border)
            setColor(b.label, on and C.goldDark or C.text)
        end
    end
    pv.talTitle:SetText(string.format(L.P_TALENTS_AT, m.at))
    local tal = m.talents or {}
    for i, line in ipairs(pv.talents) do
        local text = tal[i]
        if i == TALENT_LINES and #tal > TALENT_LINES then text = string.format(L.P_MORE, #tal - TALENT_LINES + 1) end
        line.mark:SetShown(text ~= nil and not m.talentNote)
        line.text:SetShown(text ~= nil and not m.talentNote)
        line.text:SetText(text or "")
    end
    pv.talNote:SetShown(m.talentNote ~= nil)
    pv.talNote:SetText(m.talentNote or "")
    local function drawRow(row, title, list)
        row.title:SetText(title)
        for i, ic in ipairs(row.icons) do
            local r = list[i]
            ic:SetShown(r ~= nil)
            if r then ic.set(r.texture, r.new and C.gold or (r.proc and C.proc or nil)) end
            if row.arrows[i] then row.arrows[i]:SetShown(r ~= nil) end
        end
    end
    drawRow(pv.rotNow, string.format(L.P_ROTATION_NOW, m.level), m.rotationNow)
    drawRow(pv.rotAt, string.format(L.P_ROTATION_AT, m.at), m.rotation)

    pv.situTitle:SetText(string.format(L.P_SITUATIONAL_AT, m.at))
    for i, row in ipairs(pv.situ) do
        local g = m.situational[i]
        row.label:SetShown(g ~= nil)
        row.label:SetText(g and g.label or "")
        for j, ic in ipairs(row.icons) do
            local x = g and g.icons[j]
            ic:SetShown(x ~= nil)
            if x then ic.set(x.texture, x.new and C.gold or nil) end
        end
    end
    pv.situNone:SetShown(#m.situational == 0)
    pv.situNone:SetText(L.P_SITUATIONAL_NONE)
    pv.trainerAt:SetText(m.trainerAt or "")

    for i, r in ipairs(f.quests) do
        local q = m.quests[i]
        r.mark:SetShown(q ~= nil)
        r.level:SetShown(q ~= nil)
        r.name:SetShown(q ~= nil)
        if q then
            r.mark:Set(q.done and "check" or "dot")
            r.level:SetText(tostring(q.level))
            r.name:SetText(q.name)
            setColor(r.name, q.done and C.muted or C.text)
        end
    end
end

function PlannerWindow:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self:Draw() end
end

function PlannerWindow:Refresh()
    if self.frame and self.frame:IsShown() then self:Draw() end
end

local function refresh() PlannerWindow:Refresh() end
for _, event in ipairs({ "FC_SPELLS_CHANGED", "FC_TALENTS_CHANGED", "FC_BUILD_CHOSEN", "FC_PROFILE_CHANGED",
                         "PLAYER_LEVEL_UP", "TRAINER_CLOSED", "ACTIONBAR_SLOT_CHANGED" }) do
    Events:On(event, PlannerWindow, refresh)
end
