-- Settings window (/fc). Closes with Esc. Built from plain widgets, no deprecated templates.
local ADDON, ns = ...
local L, Events = ns.L, ns.Events

local Settings = {}
ns.Settings = Settings

local WIDTH, HEIGHT = 380, 560
local DARK = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
               edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } }

local function changed(key)
    Events:Fire("FC_SETTINGS_CHANGED", key)
    Events:Fire("FC_DIRTY")
end

local function header(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    return fs
end

local function checkbox(parent, y, label, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 14, y)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetWidth(WIDTH - 70)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    cb:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        changed(key)
    end)
    cb.refresh = function() cb:SetChecked(ns.db[key]) end
    return cb
end

local function slider(parent, y, fmt, key, min, max, step, percent)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 18, y)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(WIDTH - 60, 16)
    s:SetPoint("TOPLEFT", 20, y - 16)
    s:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
                    tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local function show(v) label:SetText(string.format(fmt, percent and math.floor(v * 100 + 0.5) or v)) end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if ns.db[key] ~= v then
            ns.db[key] = v
            changed(key)
        end
    end)
    s.refresh = function() s:SetValue(ns.db[key]); show(ns.db[key]) end
    return s
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

function Settings:Create()
    if self.frame then return end
    local f = CreateFrame("Frame", "ForeverCoachSettings", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(DARK)
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    table.insert(UISpecialFrames, "ForeverCoachSettings") -- Esc closes it

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(L.SETTINGS_TITLE)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local widgets = {}
    local y = -40
    header(f, L.S_SECTION_LOOK, y); y = y - 20
    widgets[#widgets + 1] = checkbox(f, y, L.S_SHOW, "shown"); y = y - 24
    widgets[#widgets + 1] = checkbox(f, y, L.S_HIDE_OOC, "hideOutOfCombat"); y = y - 24
    widgets[#widgets + 1] = checkbox(f, y, L.S_LOCKED, "locked"); y = y - 24
    widgets[#widgets + 1] = checkbox(f, y, L.S_TOOLTIPS, "tooltips"); y = y - 24
    widgets[#widgets + 1] = checkbox(f, y, L.S_SOUND, "sound"); y = y - 24
    -- The minimap setting lives in db.minimap.hide (inverted).
    local mm = checkbox(f, y, L.S_MINIMAP, "_minimap"); y = y - 24
    mm:SetScript("OnClick", function(cb)
        ns.db.minimap.hide = not cb:GetChecked()
        changed("minimap")
    end)
    mm.refresh = function() mm:SetChecked(not ns.db.minimap.hide) end
    widgets[#widgets + 1] = mm
    widgets[#widgets + 1] = checkbox(f, y, L.S_DEBUG, "debug"); y = y - 30
    widgets[#widgets + 1] = slider(f, y, L.S_NEXT, "nextIcons", 0, 2, 1); y = y - 40
    widgets[#widgets + 1] = slider(f, y, L.S_SCALE, "scale", 0.5, 2, 0.05, true); y = y - 40
    widgets[#widgets + 1] = slider(f, y, L.S_ALPHA, "alpha", 0.2, 1, 0.05, true); y = y - 44

    header(f, L.S_SECTION_THRESHOLDS, y); y = y - 20
    widgets[#widgets + 1] = slider(f, y, L.S_HP, "hpThreshold", 10, 80, 5); y = y - 40
    widgets[#widgets + 1] = slider(f, y, L.S_PET_HP, "petHpThreshold", 10, 80, 5); y = y - 40
    widgets[#widgets + 1] = slider(f, y, L.S_SHARDS, "shards", 0, 10, 1)

    local mode = button(f, "", 200)
    mode:SetPoint("BOTTOMLEFT", 16, 16)
    local function showMode() mode:SetText(string.format(L.S_MODE, L["MODE_" .. ns.db.mode])) end
    mode:SetScript("OnClick", function()
        local list, idx = ns.Modes.list, 1
        for i, m in ipairs(list) do if m == ns.db.mode then idx = i end end
        ns.db.mode = list[idx % #list + 1]
        showMode()
        changed("mode")
    end)

    local reset = button(f, L.S_RESET_POS, 130)
    reset:SetPoint("BOTTOMRIGHT", -16, 16)
    reset:SetScript("OnClick", function()
        ns.db.pos = { point = "CENTER", x = 0, y = -170 }
        changed("pos")
    end)

    f:SetScript("OnShow", function()
        for _, w in ipairs(widgets) do w.refresh() end
        showMode()
    end)
    self.frame = f
end

function Settings:Toggle()
    self:Create()
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function Settings:Refresh()
    if self.frame and self.frame:IsShown() then self.frame:GetScript("OnShow")(self.frame) end
end
