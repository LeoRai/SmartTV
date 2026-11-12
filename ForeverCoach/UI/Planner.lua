-- Planner window (/fc plan):
--   left:  what waits at the trainer (count, price, who and where); what the build's rotation
--          still needs, with a status per line (at the trainer, talent, not on the bars,
--          opens at level N, class quest); class quests
--   right: how the chosen build's rotation develops: now, after the trainer, then every level
--          where a spell or a talent changes the hints (Planner.Evolution)
-- Model() gathers what the window shows; the frames only draw it (the tests check the model).
local ADDON, ns = ...
local L, API, Data, Events, W = ns.L, ns.API, ns.Data, ns.Events, ns.Widgets
local Planner = ns.Planner
local C = W.C

local PlannerWindow = {}
ns.PlannerWindow = PlannerWindow

local WIDTH, HEIGHT = 900, 660
local LEFT_X, LEFT_W = 22, 440
local RIGHT_X, RIGHT_W = 480, 398
local NEED_ROWS, NEED_H, NEED_GAP = 6, 50, 7
-- steps: the first one (now) has three lines of text, the others two
local QUESTS, STEPS, STEP_ICONS, STEP_H, FIRST_H = 4, 10, 6, 51, 62

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

local function actionName(r)
    local name = spellName(r.id, r.key)
    return r.proc and string.format(L.B_PROC_NAME, name) or name
end

local function names(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = actionName(r) end
    return table.concat(out, ", ")
end

-- A talent that starts changing the hints: its name, the rank it needs when more than one, and
-- what it changes when that is not seen in the rotation (P_EVO_EFFECT_<talent>).
local function talentText(t)
    local name = t.name
    if (t.rank or 1) > 1 then name = string.format("%s %d/%d", name, t.rank, t.max or t.rank) end
    local effect = t.talent and ns.Tr("P_EVO_EFFECT_" .. t.talent, nil)
    return effect and (name .. " — " .. effect) or name
end

-- What changes at a step, in words: the talents that start working, what replaces what, what joins
-- the rotation or leaves it, what comes for a situation. The first step names the situations now.
local function evolutionText(st)
    if st.now then
        local sit = {}
        for _, g in ipairs(st.situations or {}) do
            sit[#sit + 1] = names(g.spells) .. " (" .. L["B_KIND_" .. g.kind] .. ")"
        end
        return #sit > 0 and string.format(L.P_EVO_SITUATIONS, table.concat(sit, ", ")) or ""
    end
    local parts = {}
    local talents = {}
    for _, t in ipairs(st.talents or {}) do
        if not t.shown then talents[#talents + 1] = talentText(t) end -- else its spell says it below
    end
    if #talents > 0 then parts[#parts + 1] = string.format(L.P_EVO_TALENTS, table.concat(talents, ", ")) end
    for _, r in ipairs(st.replaced or {}) do
        parts[#parts + 1] = string.format(L.P_EVO_REPLACED, actionName(r.new), actionName(r.old))
    end
    if st.added and #st.added > 0 then parts[#parts + 1] = string.format(L.P_EVO_ADDED, names(st.added)) end
    if st.removed and #st.removed > 0 then parts[#parts + 1] = string.format(L.P_EVO_REMOVED, names(st.removed)) end
    for _, g in ipairs(st.situations or {}) do
        parts[#parts + 1] = string.format(L.P_EVO_ADDED, names(g.spells)) .. " (" .. L["B_KIND_" .. g.kind] .. ")"
    end
    return table.concat(parts, "; ")
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

-- Everything the window shows.
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

    -- How the rotation develops for this build, step by step. More steps than rows: the last row
    -- takes the rest ("52-60"), its icons the rotation at the end.
    m.steps = {}
    m.note = ranks and L.P_EVO_NOTE or L.P_EVO_NO_BUILD
    local steps = Planner.Evolution(def, profile, ns.Loop.current, s, level, ranks)
    for i, st in ipairs(steps) do
        local row = { level = st.level, now = st.now, icons = {}, text = evolutionText(st) }
        row.label = st.now and L.P_EVO_NOW or (st.trainer and L.P_EVO_TRAINER or string.format(L.P_EVO_LEVEL, st.level))
        local last = st
        if i == STEPS and #steps > STEPS then
            last = steps[#steps]
            local texts = { row.text }
            for j = STEPS + 1, #steps do texts[#texts + 1] = string.format(L.P_EVO_AT, steps[j].level, evolutionText(steps[j])) end
            row.text = table.concat(texts, "; ")
            row.label = string.format(L.P_EVO_LEVELS, st.level, last.level)
        end
        for j, r in ipairs(last.rotation) do
            if j <= STEP_ICONS then
                row.icons[j] = { key = r.key, texture = API.SpellTexture(r.id), new = r.new, proc = r.proc }
            end
        end
        m.steps[i] = row
        if i == STEPS then break end
    end

    -- Class quests
    m.quests = {}
    for i, q in ipairs(Planner.Quests(def, s.known, level)) do
        m.quests[i] = { level = q.level, name = ns.Tr("QUEST_" .. q.key, q.key), done = q.done }
    end
    return m
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

    -- How the rotation develops: one row per step, the level on the left
    local pv = W.Panel(f, RIGHT_W, 584)
    pv:SetPoint("TOPLEFT", RIGHT_X, -66)
    local pvTitle = W.Section(pv, L.P_EVOLUTION)
    pvTitle:SetPoint("TOPLEFT", 18, -16)
    local hint = W.Font(pv, 11, C.dim)
    hint:SetPoint("TOPLEFT", 18, -34)
    hint:SetWidth(RIGHT_W - 36)
    pv.hint = hint
    pv.steps = {}
    local y = -56
    for i = 1, STEPS do
        local row = { icons = {} }
        row.label = W.Font(pv, 12, C.text)
        row.label:SetPoint("TOPLEFT", 18, y - 3)
        row.label:SetWidth(54)
        row.label:SetWordWrap(true)
        for j = 1, STEP_ICONS do
            local ic = W.Icon(pv, 20)
            ic:SetPoint("TOPLEFT", 76 + (j - 1) * 24, y)
            row.icons[j] = ic
        end
        row.text = W.Font(pv, 11, C.muted)
        row.text:SetPoint("TOPLEFT", 76, y - 22)
        row.text:SetWidth(RIGHT_W - 90)
        if row.text.SetMaxLines then row.text:SetMaxLines(i == 1 and 3 or 2) end
        pv.steps[i] = row
        y = y - (i == 1 and FIRST_H or STEP_H)
    end
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
    pv.hint:SetText(m.note)
    for i, row in ipairs(pv.steps) do
        local st = m.steps[i]
        row.label:SetShown(st ~= nil)
        row.text:SetShown(st ~= nil)
        if st then
            row.label:SetText(st.label)
            setColor(row.label, st.now and C.gold or C.text)
            row.text:SetText(st.text)
        end
        for j, ic in ipairs(row.icons) do
            local x = st and st.icons[j]
            ic:SetShown(x ~= nil)
            if x then ic.set(x.texture, (not st.now and x.new) and C.gold or (x.proc and C.proc or nil)) end
        end
    end

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
