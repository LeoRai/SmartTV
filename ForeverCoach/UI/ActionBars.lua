-- Action bars: which key casts a spell (shown on the hint icon), whether a learned spell is on
-- the bars at all (stage 2 planner: "learned, but not on your bars"), and the gold frame on the
-- bar button of the main hint ("highlight the button on action bars" setting).
-- Default Blizzard bars only; bar addons with their own buttons get no key text and no frame.
local ADDON, ns = ...
local API, Data, Events = ns.API, ns.Data, ns.Events

local ActionBars = { keys = {}, onBars = {}, slots = {}, dirty = true }
ns.ActionBars = ActionBars

-- Action slot ranges -> binding command prefix and button name of the default UI.
local RANGES = {
    { 1, 12, "ACTIONBUTTON", "ActionButton" },
    { 25, 36, "MULTIACTIONBAR3BUTTON", "MultiBarRightButton" },
    { 37, 48, "MULTIACTIONBAR4BUTTON", "MultiBarLeftButton" },
    { 49, 60, "MULTIACTIONBAR2BUTTON", "MultiBarBottomRightButton" },
    { 61, 72, "MULTIACTIONBAR1BUTTON", "MultiBarBottomLeftButton" },
    { 145, 156, "MULTIACTIONBAR5BUTTON", "MultiBar5Button" },
    { 157, 168, "MULTIACTIONBAR6BUTTON", "MultiBar6Button" },
    { 169, 180, "MULTIACTIONBAR7BUTTON", "MultiBar7Button" },
}
local LAST_SLOT = 180

local function commandForSlot(slot)
    for _, r in ipairs(RANGES) do
        if slot >= r[1] and slot <= r[2] then return r[3] .. (slot - r[1] + 1) end
    end
end

local function buttonForSlot(slot)
    for _, r in ipairs(RANGES) do
        if slot >= r[1] and slot <= r[2] then return _G[r[4] .. (slot - r[1] + 1)] end
    end
end

-- "SHIFT-NUMPAD1" -> "SN1": short enough for a corner of an icon.
function ActionBars.ShortKey(key)
    key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("META%-", "M")
    key = key:gsub("NUMPAD", "N"):gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD")
    key = key:gsub("BUTTON", "M"):gsub("SPACE", "Sp")
    return key
end

local function actionKey(def, slot)
    if not GetActionInfo then return nil end
    local kind, id, subType = GetActionInfo(slot)
    kind, id = API.Clean(kind), API.Clean(id)
    if not kind or not id then return nil end
    local spellID
    if kind == "spell" then
        spellID = id
    elseif kind == "macro" then
        spellID = (API.Clean(subType) == "spell") and id or (GetMacroSpell and API.Clean(GetMacroSpell(id)))
    elseif kind == "item" then
        return def.itemById[id]
    end
    local info = spellID and def.byId[spellID]
    return info and info.key
end

function ActionBars:Scan()
    ns.wipe(self.keys)
    ns.wipe(self.onBars)
    ns.wipe(self.slots)
    self.dirty = false
    local def = Data.class
    if not def then return end
    for slot = 1, LAST_SLOT do
        local key = actionKey(def, slot)
        if key then
            self.onBars[key] = true
            self.slots[key] = self.slots[key] or {}
            table.insert(self.slots[key], slot)
            if not self.keys[key] then
                local command = commandForSlot(slot)
                local bind = command and GetBindingKey and API.Clean(GetBindingKey(command))
                if bind then self.keys[key] = ActionBars.ShortKey(bind) end
            end
        end
    end
end

function ActionBars:KeyFor(key)
    if self.dirty then self:Scan() end
    return self.keys[key]
end

function ActionBars:IsOnBars(key)
    if self.dirty then self:Scan() end
    return self.onBars[key] == true
end

-- The visible default-UI button that holds this spell, if any.
function ActionBars:ButtonFor(key)
    if self.dirty then self:Scan() end
    for _, slot in ipairs(self.slots[key] or {}) do
        local button = buttonForSlot(slot)
        if button and button.IsVisible and button:IsVisible() then return button end
    end
end

-- Gold frame around the bar button of `key` (nil hides it). Our own frame, only anchored to
-- the button: the button itself is never touched, so nothing gets tainted.
function ActionBars:Highlight(key)
    if key == self.highlighted then return end
    self.highlighted = key
    local button = key and self:ButtonFor(key)
    local frame = self.frame
    if not button then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        frame:SetFrameStrata("HIGH")
        ns.Widgets.Box(frame, { 0, 0, 0 }, ns.Widgets.C.gold, 2, 0)
        self.frame = frame
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    frame:Show()
end

local function markDirty()
    ActionBars.dirty = true
    ActionBars.highlighted = nil -- re-anchor after the bars changed
end
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "FC_LOGIN", "FC_SPELLS_CHANGED" }) do
    Events:On(event, ActionBars, markDirty)
end
