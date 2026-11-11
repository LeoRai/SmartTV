-- The on-screen block, as in the mockup "Блок подсказок: состояния":
--
--              [ AoE · 4 врага ]                    (3+ enemies, AoE profile)
--   [defense]  [ MAIN ] [next] [next] [next]  [cooldown]
--     31%                                       ready
--          [ + Spells waiting at the trainer · Brill ]   (out of combat only)
--
-- Main icon: real spell icon from the client, key in the corner, the global cooldown and the
-- spell's cooldown fill clockwise like on action bars (CooldownFrameTemplate), gold frame when
-- it is time to press, violet glow on an instant proc. Each next icon is paler than the last.
-- Defense (left) and cooldown (right) slots, the AoE label and the sounds appear only when needed.
-- Nothing pops up in combat by itself; the windows open on their own keys.
local ADDON, ns = ...
local L, API, W = ns.L, ns.API, ns.Widgets
local C = W.C

local HUD = { next = {} }
ns.HUD = HUD

local BASE = 56                        -- the mockup's main icon size, px
local NEXT_ALPHA = { 0.9, 0.72, 0.55 } -- each next icon paler
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local COOLDOWN_SLOT = { 0.788, 0.635, 0.243 } -- #C9A23E

local function px(v) return math.floor(v * ns.db.iconSize / BASE + 0.5) end

local textureCache = {}
local function textureFor(rec)
    local cacheKey = rec.kind .. rec.id
    local tex = textureCache[cacheKey]
    if tex == nil then
        if rec.kind == "item" then
            tex = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(rec.id))
                or (GetItemIcon and GetItemIcon(rec.id))
        else
            tex = API.SpellTexture(rec.id)
        end
        tex = API.Clean(tex) or QUESTION
        textureCache[cacheKey] = tex
    end
    return tex
end

---------------------------------------------------------------------------
-- Tooltip: why this action
---------------------------------------------------------------------------

local function onEnter(self)
    local rec = self.rec
    if not rec or not rec.id or rec.action == "" or not ns.db.tooltips then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if rec.kind == "item" then GameTooltip:SetItemByID(rec.id) else GameTooltip:SetSpellByID(rec.id) end
    local line = rec.line
    if line and line.why then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L.WHY, L[line.why]), 0.6, 0.8, 1, true)
    end
    if rec.outOfRange then GameTooltip:AddLine(L.OUT_OF_RANGE, 1, 0.35, 0.35) end
    if rec.noMana then GameTooltip:AddLine(L.NO_MANA, 0.45, 0.55, 1) end
    local bm = ns.BuildMatcher
    if bm.profile then
        GameTooltip:AddLine(string.format(L.PROFILE, bm.profile.id .. (bm.approximate and L.PROFILE_APPROX or "")), 0.5, 0.5, 0.5)
    end
    if ns.db.debug and line and line.src ~= "" then GameTooltip:AddLine(line.src, 0.5, 0.5, 0.5, true) end
    GameTooltip:Show()
end

local function onLeave() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local function createIcon(parent, withCooldown)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Box(f, C.panel, C.border)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    if withCooldown then
        f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        f.cd:SetPoint("TOPLEFT", 1, -1)
        f.cd:SetPoint("BOTTOMRIGHT", -1, 1)
        if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
        if f.cd.SetDrawBling then f.cd:SetDrawBling(false) end
        if f.cd.SetSwipeColor then f.cd:SetSwipeColor(0, 0, 0, 0.62) end
        if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    end

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 3)
    f.key = top:CreateFontString(nil, "OVERLAY")
    f.key:SetPoint("BOTTOMRIGHT", -3, 2)

    -- State frame: gold (time to press), violet (proc), red (defense), dark gold (cooldown).
    f.ring = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.ring:SetPoint("TOPLEFT", -3, 3)
    f.ring:SetPoint("BOTTOMRIGHT", 3, -3)
    f.ring:SetFrameLevel(f:GetFrameLevel() + 2)
    f.ring:Hide()
    f.glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.glow:SetTexture(GLOW)
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.glow:Hide()
    f.pulse = f.glow:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.4)
    fade:SetDuration(0.45)

    f.label = parent:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -5)

    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    f:SetScript("OnEnter", onEnter)
    f:SetScript("OnLeave", onLeave)
    f:Hide()
    return f
end

local function sizeIcon(f, size, keySize)
    f:SetSize(size, size)
    f.key:SetFont(STANDARD_TEXT_FONT, keySize, "OUTLINE")
    f.label:SetFont(STANDARD_TEXT_FONT, math.max(9, px(11)), "")
    f.glow:SetSize(size * 1.75, size * 1.75)
end

-- color = nil hides the frame; glowAlpha > 0 adds a soft glow; pulse animates it.
local function setRing(f, color, glowAlpha, pulse)
    if not color then
        f.ring:Hide()
        if f.glow:IsShown() then f.pulse:Stop(); f.glow:Hide() end
        f.ringColor = nil
        return
    end
    if f.ringColor ~= color then
        W.Box(f.ring, { 0, 0, 0 }, color, 2, 0)
        f.glow:SetVertexColor(color[1], color[2], color[3])
        f.ringColor = color
    end
    f.ring:Show()
    if glowAlpha and glowAlpha > 0 then
        f.glow:SetAlpha(glowAlpha)
        if not f.glow:IsShown() then f.glow:Show() end
        if pulse and not f.pulse:IsPlaying() then f.pulse:Play() end
        if not pulse and f.pulse:IsPlaying() then f.pulse:Stop() end
    elseif f.glow:IsShown() then
        f.pulse:Stop(); f.glow:Hide()
    end
end

local function setIcon(f, rec)
    f.rec = rec
    if not rec or not rec.id then
        f.icon:SetTexture(nil)
        f.key:SetText("")
        return
    end
    f.icon:SetTexture(textureFor(rec))
    if rec.outOfRange then
        f.icon:SetVertexColor(1, 0.35, 0.35)
    elseif rec.noMana then
        f.icon:SetVertexColor(0.45, 0.55, 1)
    else
        f.icon:SetVertexColor(1, 1, 1)
    end
    f.key:SetText(ns.ActionBars:KeyFor(rec.action) or "")
end

-- The main icon's swirl: the client's own cooldown of that spell (global cooldown included),
-- exactly as its action button shows it; our own global cooldown timer when the client won't say.
local function showCooldown(f, rec, s, now)
    if not rec or not rec.id then
        f.cd:Clear()
        return
    end
    if rec.kind == "spell" and API.ShowSpellCooldown(f.cd, rec.id) then return end
    if rec.kind == "item" then
        local start, duration = API.ItemCooldown(rec.id)
        if start and duration and duration > 0 then f.cd:SetCooldown(start, duration) return end
    end
    if s.gcdEnd > now then f.cd:SetCooldown(s.gcdEnd - s.gcd, s.gcd) else f.cd:Clear() end
end

---------------------------------------------------------------------------
-- Pills: AoE label above, preparation line below
---------------------------------------------------------------------------

local function createPill(parent)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p.text = W.Font(p, 12, C.text)
    p:Hide()
    return p
end

local function fitPill(p, padX, height)
    local w = p.text:GetStringWidth() + padX * 2 + (p.extraWidth or 0)
    p:SetSize(w, height)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

function HUD:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "ForeverCoachHUD", UIParent, "BackdropTemplate")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) if not ns.db.locked then f:StartMoving() end end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        ns.db.pos.point, ns.db.pos.x, ns.db.pos.y = point, x, y
    end)
    self.frame = frame

    self.main = createIcon(frame, true)
    for i = 1, 3 do self.next[i] = createIcon(frame, false) end
    self.defense = createIcon(frame, false)
    self.cooldown = createIcon(frame, false)

    -- Health-gated hints laid over their slots: the client shows them only below the threshold.
    -- Not hoverable (an invisible icon must not catch the mouse).
    self.mainGates = {}
    for i = 1, 2 do
        local g = createIcon(frame, false)
        g:SetAllPoints(self.main)
        g:SetFrameLevel(self.main:GetFrameLevel() + 12 - i * 3) -- the first one on top
        self.mainGates[i] = g
    end
    self.defenseGates = {}
    for i = 1, 3 do
        local g = createIcon(frame, false)
        g:SetAllPoints(self.defense)
        g:SetFrameLevel(self.defense:GetFrameLevel() + 12 - i * 3) -- the first (most important) on top
        self.defenseGates[i] = g
    end
    for _, g in ipairs(self.mainGates) do g:EnableMouse(false) end
    for _, g in ipairs(self.defenseGates) do g:EnableMouse(false) end

    -- Lines under the block for the main hints the client shows by hidden mana or health
    -- ("Low mana: Life Tap"): they fade in and leave the main icon in sight.
    self.alerts, self.alertList, self.takeoverList = {}, {}, {}
    for i = 1, 2 do
        local a = createPill(frame)
        W.Box(a, { 0.055, 0.059, 0.075 }, C.line, 1, 0.9)
        a.icon = a:CreateTexture(nil, "ARTWORK")
        a.icon:SetPoint("LEFT", 6, 0)
        a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        a.text:SetPoint("LEFT", a.icon, "RIGHT", 7, 0)
        a:EnableMouse(false)
        self.alerts[i] = a
    end

    self.aoe = createPill(frame)
    W.Box(self.aoe, C.window, C.aoe, 1, 0)
    self.aoe.text:SetTextColor(C.aoeText[1], C.aoeText[2], C.aoeText[3], 1)
    self.aoe.text:SetPoint("CENTER")

    self.prep = createPill(frame)
    W.Box(self.prep, { 0.055, 0.059, 0.075 }, C.line, 1, 0.88)
    self.prep.mark = W.Font(self.prep, 14, C.gold)
    self.prep.mark:SetPoint("LEFT", 10, 0)
    self.prep.mark:SetText("+")
    self.prep.text:SetPoint("LEFT", self.prep.mark, "RIGHT", 8, 0)
    self.prep.place = W.Font(self.prep, 12, C.muted)
    self.prep.place:SetPoint("LEFT", self.prep.text, "RIGHT", 4, 0)
    -- "Spells wait at the trainer": a click opens the planner (the line shows out of combat only).
    self.prep:SetScript("OnMouseUp", function(p) if p.trainer then ns.PlannerWindow:Toggle() end end)

    self.label = W.Font(frame, 12, C.gold)
    self.label:SetPoint("BOTTOM", frame, "TOP", 0, 30)
    self.label:SetJustifyH("CENTER")
    self.label:SetText(L.UNLOCKED_LABEL)

    self:ApplySettings()
end

function HUD:ApplySettings()
    local frame, db = self.frame, ns.db
    if not frame then return end
    frame:SetScale(1)
    frame:SetAlpha(db.alpha)
    frame:ClearAllPoints()
    frame:SetPoint(db.pos.point or "CENTER", UIParent, db.pos.point or "CENTER", db.pos.x or 0, db.pos.y or 0)

    local main, small, side = db.iconSize, px(36), px(40)
    frame:SetSize(main + 8, main + 8)
    sizeIcon(self.main, main, math.max(10, px(13)))
    for i = 1, 2 do sizeIcon(self.mainGates[i], main, math.max(10, px(13))) end
    for i = 1, 3 do sizeIcon(self.defenseGates[i], side, math.max(9, px(11))) end
    for i = 1, 3 do sizeIcon(self.next[i], small, math.max(9, px(11))) end
    sizeIcon(self.defense, side, math.max(9, px(11)))
    sizeIcon(self.cooldown, side, math.max(9, px(11)))

    self.main:ClearAllPoints()
    self.main:SetPoint("CENTER")
    local gap = px(8)
    self.next[1]:ClearAllPoints()
    self.next[1]:SetPoint("BOTTOMLEFT", self.main, "BOTTOMRIGHT", gap, 0)
    for i = 2, 3 do
        self.next[i]:ClearAllPoints()
        self.next[i]:SetPoint("BOTTOMLEFT", self.next[i - 1], "BOTTOMRIGHT", gap, 0)
    end
    self.defense:ClearAllPoints()
    self.defense:SetPoint("BOTTOMRIGHT", self.main, "BOTTOMLEFT", -px(12), 0)
    for i, a in ipairs(self.alerts) do
        a.icon:SetSize(px(18), px(18))
        a.text:SetFont(STANDARD_TEXT_FONT, math.max(10, px(12)), "")
        a.extraWidth = px(18) + 7
        a:ClearAllPoints()
        if i == 1 then a:SetPoint("TOP", self.main, "BOTTOM", 0, -px(14)) else a:SetPoint("TOP", self.alerts[i - 1], "BOTTOM", 0, -px(6)) end
    end
    self.shownNext = nil -- re-anchor the cooldown slot and the AoE label on the next render

    local unlocked = not db.locked
    frame:EnableMouse(unlocked)
    if unlocked then
        W.Box(frame, C.window, C.gold, 1, 0.6)
        self.label:Show()
    else
        frame:SetBackdrop(nil)
        self.label:Hide()
    end
end

-- Cooldown slot and AoE label depend on how many next icons are shown.
function HUD:Anchor(shownNext)
    if shownNext == self.shownNext then return end
    self.shownNext = shownNext
    local last = shownNext > 0 and self.next[shownNext] or self.main
    self.cooldown:ClearAllPoints()
    self.cooldown:SetPoint("BOTTOMLEFT", last, "BOTTOMRIGHT", px(12), 0)
    local rowWidth = ns.db.iconSize + shownNext * (px(36) + px(8))
    self.aoe:ClearAllPoints()
    self.aoe:SetPoint("BOTTOM", self.main, "TOP", (rowWidth - ns.db.iconSize) / 2, px(8))
end

local function healthLabel(line, s)
    for _, path in ipairs(line.paths or {}) do
        if path == "pet.hp_pct" and not s.hidden["pet.hp_pct"] then
            return string.format("%d%%", math.floor(s.pet.hp_pct + 0.5))
        end
        if path == "player.hp_pct" and not s.hidden["player.hp_pct"] then
            return string.format("%d%%", math.floor(s.player.hp_pct + 0.5))
        end
    end
    return ""
end

function HUD:ShowPrep(r, centered)
    local p = self.prep
    if not r.prep then p:Hide() return end
    local text = L[r.prep]
    if r.prepValue ~= nil then text = string.format(text, r.prepValue) end
    p.text:SetText(text)
    local place = r.prepPlace == "trainer" and ns.db.trainerPlace or nil
    p.trainer = r.prepPlace == "trainer"
    p:EnableMouse(p.trainer)
    p.place:SetText(place and ("— " .. place) or "")
    p.extraWidth = 18 + (place and (p.place:GetStringWidth() + 4) or 0)
    fitPill(p, 12, 30)
    p:ClearAllPoints()
    if centered then p:SetPoint("CENTER", self.main, "CENTER") else p:SetPoint("TOP", self.main, "BOTTOM", 0, -px(14)) end
    p:Show()
end

-- Show a health-gated hint over its slot; the client decides the visibility from hidden health.
-- With a warning band (gate.warn) the icon fades in faintly before the threshold and gets its frame
-- only at the threshold, so the switch never comes out of nowhere.
local function showGate(f, rec, color)
    if not rec then
        f:Hide()
        return
    end
    setIcon(f, rec)
    local warn = rec.gate.warn and rec.gate.warn / 100 or nil
    setRing(f, color, warn and 0 or 0.5, not warn)
    f:Show()
    if not API.BindGate(f, rec.gate, rec.threshold, warn) then
        f:SetAlpha(0)
    elseif warn then
        f.ring:SetAlpha(0)
        API.BindGate(f.ring, rec.gate, rec.threshold)
    else
        f.ring:SetAlpha(1) -- the frame may come from a warning gate before
    end
end

-- A gate that takes the main icon over past its threshold (Drain Soul on a dying target). No
-- faint stage over the main icon: the line under the block has announced it already.
local function showTakeover(f, rec)
    if not rec then
        f:Hide()
        return
    end
    setIcon(f, rec)
    setRing(f, C.gold, 0.5, true)
    f:Show()
    f.ring:SetAlpha(1)
    if not API.BindGate(f, rec.gate, rec.threshold, nil, "step") then f:SetAlpha(0) end
end

-- The line under the block: icon, "Low mana: Life Tap", fading in over the warning band.
local function showAlert(a, rec)
    if not rec then
        a.action = nil
        a:Hide()
        return
    end
    a.action = rec.action
    a.icon:SetTexture(rec.id and textureFor(rec) or QUESTION)
    local name = rec.kind == "spell" and API.SpellName(rec.id) or rec.action
    local label = rec.line.alert and L[rec.line.alert]
    a.text:SetText(label and (label .. " — " .. tostring(name)) or tostring(name))
    local c = rec.gate.power == "mana" and C.mana or C.gold
    a.text:SetTextColor(c[1], c[2], c[3], 1)
    a:SetBackdropBorderColor(c[1], c[2], c[3], 0.7)
    fitPill(a, 6, px(26))
    a:Show()
    local warn = rec.gate.warn and rec.gate.warn / 100 or nil
    if not API.BindGate(a, rec.gate, rec.threshold, warn, "ramp") then a:SetAlpha(0) end
end

local function hideGates(self)
    for i = 1, 2 do self.mainGates[i]:Hide() end
    for i = 1, 3 do self.defenseGates[i]:Hide() end
    for i = 1, 2 do showAlert(self.alerts[i], nil) end
end

local function hideAll(self)
    hideGates(self)
    self.main.rec = nil
    self.main:Hide()
    for i = 1, 3 do self.next[i].rec = nil; self.next[i]:Hide() end
    self.defense:Hide(); self.defense.label:SetText("")
    self.cooldown:Hide(); self.cooldown.label:SetText("")
    self.aoe:Hide()
end

-- Draw the hints. r = Engine result, s = snapshot (nil when there is no class data).
function HUD:Render(r, s, now)
    local frame, db = self.frame, ns.db
    if not frame then return end
    local unlocked = not db.locked
    if (not db.shown and not unlocked) or not s then
        frame:Hide()
        ns.ActionBars:Highlight(nil)
        return
    end
    frame:Show()

    if unlocked then
        local fake = { id = 1, kind = "spell", action = "", wait = 0, at = now }
        textureCache["spell1"] = QUESTION
        hideGates(self)
        for _, f in ipairs({ self.main, self.defense, self.cooldown }) do setIcon(f, fake); f:Show() end
        for i = 1, 3 do
            local f = self.next[i]
            if i <= db.nextIcons then setIcon(f, fake); f:SetAlpha(NEXT_ALPHA[i]); f:Show() else f:Hide() end
        end
        self:Anchor(db.nextIcons)
        self.aoe.text:SetText(string.format(L.AOE, 3, ns.Plural(3, L.ENEMY_FORMS)))
        fitPill(self.aoe, 8, 18)
        self.aoe:Show()
        self:ShowPrep({ prep = "PREP_NO_PET" }, false)
        ns.ActionBars:Highlight(nil)
        return
    end

    local inCombat = s.player.in_combat
    local showBlock = not s.player.dead and (inCombat or (not db.hideOutOfCombat and s.target.enemy))
    local main = r.main[1]

    if showBlock then
        setIcon(self.main, main)
        showCooldown(self.main, main, s, now)
        self.main:Show()
        if main and main.glow then
            setRing(self.main, C.proc, 0.7, true)
        elseif main and inCombat and main.wait <= 0.05 then
            setRing(self.main, C.gold, 0.4, false)
        else
            setRing(self.main, nil)
        end

        local shown = 0
        for i = 1, 3 do
            local f, rec = self.next[i], i <= db.nextIcons and r.main[i + 1] or nil
            if rec then
                setIcon(f, rec)
                f:SetAlpha(NEXT_ALPHA[i])
                f:Show()
                shown = i
            else
                f.rec = nil
                f:Hide()
            end
        end
        self:Anchor(shown)

        if r.hasDefense then
            setIcon(self.defense, r.defense)
            setRing(self.defense, C.danger, 0, false)
            self.defense.label:SetTextColor(C.dangerText[1], C.dangerText[2], C.dangerText[3], 1)
            self.defense.label:SetText(healthLabel(r.defense.line, s))
            self.defense:Show()
        else
            self.defense.rec = nil
            self.defense:Hide()
            self.defense.label:SetText("")
        end

        if r.hasCooldown then
            setIcon(self.cooldown, r.cooldown)
            setRing(self.cooldown, COOLDOWN_SLOT, 0.3, false)
            self.cooldown.label:SetTextColor(C.gold[1], C.gold[2], C.gold[3], 1)
            self.cooldown.label:SetText(L.READY)
            self.cooldown:Show()
        else
            self.cooldown.rec = nil
            self.cooldown:Hide()
            self.cooldown.label:SetText("")
        end

        -- Gated main hints: a line under the block each (those that only advise first, so Life Tap
        -- keeps the top line); a takeover gate also covers the main icon past its threshold.
        local alerts, takeovers = ns.wipe(self.alertList), ns.wipe(self.takeoverList)
        if inCombat then
            for _, g in ipairs(r.gatedMains) do if not g.gate.takeover then alerts[#alerts + 1] = g end end
            for _, g in ipairs(r.gatedMains) do
                if g.gate.takeover then
                    alerts[#alerts + 1] = g
                    takeovers[#takeovers + 1] = g
                end
            end
        end
        for i = 1, 2 do showAlert(self.alerts[i], alerts[i]) end
        for i = 1, 2 do showTakeover(self.mainGates[i], takeovers[i]) end
        for i = 1, 3 do showGate(self.defenseGates[i], r.gatedDefense[i], C.danger) end

        if r.aoe then
            self.aoe.text:SetText(string.format(L.AOE, s.enemies, ns.Plural(s.enemies, L.ENEMY_FORMS)))
            fitPill(self.aoe, 8, 18)
            self.aoe:Show()
        else
            self.aoe:Hide()
        end
    else
        hideAll(self)
    end

    if not inCombat then self:ShowPrep(r, not showBlock) else self.prep:Hide() end

    ns.ActionBars:Highlight(db.highlightBar and showBlock and main and main.action or nil)
end
