-- Action bars: which key casts a spell (shown on the hint icon) and whether a learned spell is
-- on the bars at all (stage 2 planner: "learned, but not on your bars").
-- Default Blizzard bars only; bar addons with their own bindings show no key text.
local ADDON, ns = ...
local API, Data, Events = ns.API, ns.Data, ns.Events

local ActionBars = { keys = {}, onBars = {}, dirty = true }
ns.ActionBars = ActionBars

-- Action slot ranges -> binding command prefix of the default UI.
local RANGES = {
    { 1, 12, "ACTIONBUTTON" },
    { 25, 36, "MULTIACTIONBAR3BUTTON" },
    { 37, 48, "MULTIACTIONBAR4BUTTON" },
    { 49, 60, "MULTIACTIONBAR2BUTTON" },
    { 61, 72, "MULTIACTIONBAR1BUTTON" },
    { 145, 156, "MULTIACTIONBAR5BUTTON" },
    { 157, 168, "MULTIACTIONBAR6BUTTON" },
    { 169, 180, "MULTIACTIONBAR7BUTTON" },
}
local LAST_SLOT = 180

local function commandForSlot(slot)
    for _, r in ipairs(RANGES) do
        if slot >= r[1] and slot <= r[2] then return r[3] .. (slot - r[1] + 1) end
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
    self.dirty = false
    local def = Data.class
    if not def then return end
    for slot = 1, LAST_SLOT do
        local key = actionKey(def, slot)
        if key then
            self.onBars[key] = true
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

local function markDirty() ActionBars.dirty = true end
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "FC_LOGIN", "FC_SPELLS_CHANGED" }) do
    Events:On(event, ActionBars, markDirty)
end
