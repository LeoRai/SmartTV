-- The on-screen block: about four icons wide, dark and minimal.
--   [defense] [ MAIN ] [next] [next] [cooldown]
--               AoE (above main, 3+ enemies when the profile switches to AoE)
--          preparation line (below, out of combat only)
-- In combat only the main icon is always there; everything else shows up only when needed.
-- Nothing ever pops up by itself in combat: windows open on their own keys.
local ADDON, ns = ...
local L, API = ns.L, ns.API

local HUD = { icons = {} }
ns.HUD = HUD

local MAIN, SMALL, GAP = 48, 32, 4
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

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
-- Icons
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

local function createIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.85)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    f.key = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    f.key:SetPoint("TOPRIGHT", -2, -2)
    f.timer = top:CreateFontString(nil, "OVERLAY", size >= MAIN and "GameFontHighlightLarge" or "GameFontHighlight")
    f.timer:SetPoint("CENTER")

    f.glow = top:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.glow:SetSize(size * 1.8, size * 1.8)
    f.glow:SetVertexColor(1, 0.8, 0.3)
    f.glow:Hide()
    f.pulse = f.glow:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.45)

    -- Hover explains the hint; clicks go through to the world where the client allows it.
    f:EnableMouse(true)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    f:SetScript("OnEnter", onEnter)
    f:SetScript("OnLeave", onLeave)
    f:Hide()
    return f
end

local function setGlow(f, on)
    if on then
        if not f.glow:IsShown() then f.glow:Show(); f.pulse:Play() end
    elseif f.glow:IsShown() then
        f.pulse:Stop(); f.glow:Hide()
    end
end

-- Show a recommendation on an icon. rec may be nil (empty slot).
local function setIcon(f, rec, now, withTimer)
    f.rec = rec
    if not rec or not rec.id then
        f.icon:SetTexture(nil)
        f.key:SetText("")
        f.timer:SetText("")
        setGlow(f, false)
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
    setGlow(f, rec.glow)
    if withTimer then
        local wait = rec.wait or 0
        f.timer:SetText(wait >= 0.3 and string.format("%.1f", wait) or "")
        -- Swirl until the action is available (global cooldown, cast in progress).
        if wait > 0.05 then
            if not f.cdEnd or math.abs(f.cdEnd - rec.at) > 0.05 then
                f.cdEnd = rec.at
                f.cd:SetCooldown(now, wait)
            end
        elseif f.cdEnd then
            f.cdEnd = nil
            f.cd:Clear()
        end
    end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

function HUD:Create()
    if self.frame then return end
    local frame = CreateFrame("Frame", "ForeverCoachHUD", UIParent, "BackdropTemplate")
    frame:SetSize(MAIN + 8, MAIN + 8)
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

    self.main = createIcon(frame, MAIN)
    self.main:SetPoint("CENTER")
    self.next = { createIcon(frame, SMALL), createIcon(frame, SMALL) }
    self.next[1]:SetPoint("LEFT", self.main, "RIGHT", GAP, 0)
    self.next[2]:SetPoint("LEFT", self.next[1], "RIGHT", GAP, 0)
    self.defense = createIcon(frame, SMALL)
    self.defense:SetPoint("RIGHT", self.main, "LEFT", -GAP, 0)
    self.cooldown = createIcon(frame, SMALL)

    self.aoe = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.aoe:SetPoint("BOTTOM", self.main, "TOP", 0, 3)
    self.aoe:SetText(L.AOE)
    self.aoe:SetTextColor(1, 0.55, 0.2)
    self.aoe:Hide()

    self.prep = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.prep:SetPoint("TOP", self.main, "BOTTOM", 0, -6)
    self.prep:SetTextColor(0.85, 0.85, 0.85)
    self.prep:Hide()

    self.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.label:SetPoint("BOTTOM", frame, "TOP", 0, 14)
    self.label:SetText(L.UNLOCKED_LABEL)

    self:ApplySettings()
end

function HUD:ApplySettings()
    local frame, db = self.frame, ns.db
    if not frame then return end
    frame:SetScale(db.scale)
    frame:SetAlpha(db.alpha)
    frame:ClearAllPoints()
    frame:SetPoint(db.pos.point or "CENTER", UIParent, db.pos.point or "CENTER", db.pos.x or 0, db.pos.y or 0)

    local unlocked = not db.locked
    frame:EnableMouse(unlocked)
    if unlocked then
        frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        frame:SetBackdropColor(0.1, 0.1, 0.2, 0.7)
        self.label:Show()
    else
        frame:SetBackdrop(nil)
        self.label:Hide()
    end

    -- The cooldown slot sits right after the last "next" icon.
    local anchor = self.main
    for i = 1, math.min(db.nextIcons, 2) do anchor = self.next[i] end
    self.cooldown:ClearAllPoints()
    self.cooldown:SetPoint("LEFT", anchor, "RIGHT", GAP, 0)
end

-- Draw the hints. r = Engine result, s = snapshot (nil when there is no class data).
function HUD:Render(r, s, now)
    local frame, db = self.frame, ns.db
    if not frame then return end
    local unlocked = not db.locked
    if (not db.shown and not unlocked) or not s then
        frame:Hide()
        return
    end
    frame:Show()

    if unlocked then
        -- Placeholders so the whole block can be placed.
        local fake = { id = 1, kind = "spell", action = "", wait = 0, at = now }
        textureCache["spell1"] = QUESTION
        for _, f in ipairs({ self.main, self.defense, self.cooldown }) do setIcon(f, fake, now); f:Show() end
        for i = 1, 2 do
            if i <= db.nextIcons then setIcon(self.next[i], fake, now); self.next[i]:Show() else self.next[i]:Hide() end
        end
        self.aoe:Show()
        self.prep:SetText(L.PREP_NO_PET)
        self.prep:Show()
        return
    end

    local inCombat = s.player.in_combat
    local showBlock = not s.player.dead and (inCombat or (not db.hideOutOfCombat and s.target.enemy))

    if showBlock then
        setIcon(self.main, r.main[1], now, true)
        self.main:Show()
        for i = 1, 2 do
            local rec = i <= db.nextIcons and r.main[i + 1] or nil
            if rec then setIcon(self.next[i], rec, now); self.next[i]:Show() else self.next[i].rec = nil; self.next[i]:Hide() end
        end
        if r.hasDefense then setIcon(self.defense, r.defense, now); self.defense:Show() else self.defense.rec = nil; self.defense:Hide() end
        if r.hasCooldown then setIcon(self.cooldown, r.cooldown, now); self.cooldown:Show() else self.cooldown.rec = nil; self.cooldown:Hide() end
        self.aoe:SetShown(r.aoe)
    else
        self.main.rec = nil
        self.main:Hide()
        self.next[1]:Hide(); self.next[2]:Hide()
        self.defense:Hide(); self.cooldown:Hide()
        self.aoe:Hide()
    end

    if not inCombat and r.prep then
        local text = L[r.prep]
        if r.prepValue ~= nil then text = string.format(text, r.prepValue) end
        self.prep:SetText(text)
        self.prep:Show()
    else
        self.prep:Hide()
    end

    -- Optional sound when a proc becomes the main hint.
    local main = showBlock and r.main[1]
    local glowing = main and main.glow or false
    if glowing and not self.lastGlow and db.sound and PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    self.lastGlow = glowing
end
