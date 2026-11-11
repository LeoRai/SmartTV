-- Look of the mockups (dark panels, gold accent) built from flat textures:
-- windows, section headers, sliders, checkboxes, segmented controls, number boxes, buttons.
-- One place for colors and fonts, so every window looks the same.
local ADDON, ns = ...

local W = {}
ns.Widgets = W

local FLAT = "Interface\\Buttons\\WHITE8X8"
W.FLAT = FLAT

local function hex(h)
    return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 }
end

-- Palette of the mockups.
W.C = {
    window = hex("#16171C"),
    panel = hex("#1B1D22"),
    field = hex("#121318"),
    line = hex("#2E3139"),
    border = hex("#3A3D46"),
    track = hex("#3A3D46"),
    text = hex("#ECEDEF"),
    muted = hex("#A3A7B0"),
    dim = hex("#8A8F99"),
    gold = hex("#F2C94C"),
    goldDark = hex("#1A1408"),
    danger = hex("#E06A6E"),
    dangerText = hex("#FF9A9C"),
    proc = hex("#8788EE"),
    aoe = hex("#E8A24A"),
    aoeText = hex("#F5C27F"),
    teal = hex("#4FB3A9"),
    good = hex("#6FCF97"),
    mana = hex("#6EA8FE"),
}
-- Talent tree colors on bars and legends, in tree order (Affliction, Demonology, Destruction ...).
W.TREE_COLORS = { W.C.proc, W.C.teal, W.C.aoe }
local C = W.C

function W.Font(parent, size, color, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- Flat background with a 1 px border (or `edge` px).
function W.Box(frame, bg, border, edge, alpha)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = edge or 1 })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
    if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    else frame:SetBackdropBorderColor(0, 0, 0, 0) end
end

function W.Line(parent, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(FLAT)
    local c = color or C.line
    t:SetVertexColor(c[1], c[2], c[3], 1)
    t:SetHeight(1)
    return t
end

-- Gold diamond: the ForeverCoach mark.
function W.Logo(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(FLAT)
    t:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    t:SetSize(size, size)
    t:SetRotation(math.rad(45))
    return t
end

-- Window: "◆ ForeverCoach / <title>", close cross, Esc closes it.
function W.Window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Box(f, C.window, C.border, 1, 0.98)
    f:Hide()
    table.insert(UISpecialFrames, name)

    local logo = W.Logo(f, 9)
    logo:SetPoint("TOPLEFT", 24, -22)
    local brand = W.Font(f, 13, C.muted)
    brand:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    brand:SetText("ForeverCoach")
    local slash = W.Font(f, 15, C.dim)
    slash:SetPoint("LEFT", brand, "RIGHT", 8, 0)
    slash:SetText("/")
    f.title = W.Font(f, 15, C.gold)
    f.title:SetPoint("LEFT", slash, "RIGHT", 8, 0)
    f.title:SetText(title)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -16, -16)
    for _, angle in ipairs({ 45, -45 }) do
        local bar = close:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(FLAT)
        bar:SetSize(14, 1.5)
        bar:SetPoint("CENTER")
        bar:SetRotation(math.rad(angle))
        bar:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 1)
    end
    close:SetScript("OnClick", function() f:Hide() end)

    local top = W.Line(f)
    top:SetPoint("TOPLEFT", 1, -50)
    top:SetPoint("TOPRIGHT", -1, -50)
    f.footerLine = W.Line(f)
    f.footerLine:SetPoint("BOTTOMLEFT", 1, 58)
    f.footerLine:SetPoint("BOTTOMRIGHT", -1, 58)
    return f
end

function W.Section(parent, text)
    local fs = W.Font(parent, 12, C.gold, "")
    fs:SetText(text)
    return fs
end

-- Button: primary = gold, otherwise outlined.
function W.Button(parent, text, width, primary, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 32)
    W.Box(b, primary and C.gold or C.window, primary and C.gold or C.border)
    b.label = W.Font(b, 13, primary and C.goldDark or C.text)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self:SetAlpha(0.85) end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(1) end)
    return b
end

-- Small square button with an arrow: plays a sound preview.
function W.PlayButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(28, 26)
    W.Box(b, C.window, C.border)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(12, 12)
    arrow:SetPoint("CENTER", 1, 0)
    b:SetScript("OnClick", onClick)
    return b
end

-- Checkbox: gold square with a check mark, label to the right.
function W.Check(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(16, 16)
    local mark = b:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetPoint("CENTER")
    mark:SetSize(18, 18)
    mark:SetVertexColor(C.goldDark[1], C.goldDark[2], C.goldDark[3], 1)
    b.text = W.Font(parent, 13, C.text)
    b.text:SetPoint("LEFT", b, "RIGHT", 10, 0)
    b.text:SetText(label)
    function b.refresh()
        local on = get()
        if on then W.Box(b, C.gold, C.gold) else W.Box(b, C.field, C.border) end
        mark:SetShown(on and true or false)
    end
    b:SetScript("OnClick", function() set(not get()); b.refresh() end)
    return b
end

-- Slider with a gold fill and a round thumb.
-- Stacked (default): label and value above the track. Inline: label | track | value in one row.
function W.Slider(parent, width, label, format, min, max, step, get, set, inline)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, inline and 20 or 40)
    local name = W.Font(holder, 13, inline and C.muted or C.text)
    local value = W.Font(holder, 13, C.muted)
    value:SetJustifyH("RIGHT")
    local s = CreateFrame("Slider", nil, holder)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    if inline then
        name:SetPoint("LEFT")
        value:SetPoint("RIGHT")
        value:SetWidth(44)
        s:SetPoint("LEFT", 100, 0)
        s:SetPoint("RIGHT", -54, 0)
    else
        name:SetPoint("TOPLEFT")
        value:SetPoint("TOPRIGHT")
        s:SetPoint("TOPLEFT", 0, -20)
        s:SetPoint("TOPRIGHT", 0, -20)
    end
    name:SetText(label)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(FLAT)
    track:SetVertexColor(C.track[1], C.track[2], C.track[3], 1)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(FLAT)
    fill:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    fill:SetHeight(4)
    fill:SetPoint("LEFT")
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    thumb:SetSize(16, 16)
    s:SetThumbTexture(thumb)

    local function show(v)
        value:SetText(string.format(format, v))
        local w = s:GetWidth()
        if w and w > 0 and max > min then fill:SetWidth(math.max(1, (v - min) / (max - min) * w)) end
    end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if get() ~= v then set(v) end
    end)
    function holder.refresh()
        s:SetValue(get())
        show(get())
    end
    holder.slider = s
    return holder
end

-- Segmented control: items = { { value, label }, ... }.
function W.Segmented(parent, width, items, get, set)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width, 34)
    W.Box(holder, C.field, C.border)
    local seg = (width - 8) / #items
    local buttons = {}
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, holder, "BackdropTemplate")
        b:SetSize(seg, 26)
        b:SetPoint("LEFT", 4 + (i - 1) * seg, 0)
        b.label = W.Font(b, 13, C.muted)
        b.label:SetPoint("CENTER")
        b.label:SetText(item[2])
        b:SetScript("OnClick", function() set(item[1]); holder.refresh() end)
        buttons[i] = b
    end
    function holder.refresh()
        local current = get()
        for i, item in ipairs(items) do
            local b, on = buttons[i], item[1] == current
            if on then W.Box(b, C.border, nil) else b:SetBackdrop(nil) end
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3], 1)
        end
    end
    return holder
end

-- Panel: a slightly lighter block with a border (cards, side panels, list rows).
function W.Panel(parent, width, height, border)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetSize(width, height)
    W.Box(p, C.panel, border or C.line)
    return p
end

-- Status pill: colored text in a thin frame of the same color; width follows the text.
function W.Pill(parent, color)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetHeight(22)
    p.text = W.Font(p, 12, color)
    p.text:SetPoint("CENTER")
    function p.set(text, c)
        c = c or color
        p.text:SetText(text)
        p.text:SetTextColor(c[1], c[2], c[3], 1)
        p:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        p:SetBackdropColor(c[1], c[2], c[3], 0.12)
        p:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
        p:SetWidth(math.max(40, (p.text:GetStringWidth() or 0) + 18))
    end
    return p
end

-- Spell icon in a thin frame; icon.set(spellID or texture, border color).
function W.Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    W.Box(f, C.field, C.border)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", 1, -1)
    f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    function f.set(texture, border)
        f.tex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local b = border or C.border
        f:SetBackdropBorderColor(b[1], b[2], b[3], 1)
    end
    return f
end

-- Small arrow between rotation icons (a texture: the game fonts have no arrow glyph).
function W.Arrow(parent, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    t:SetSize(10, 10)
    local c = color or C.dim
    t:SetVertexColor(c[1], c[2], c[3], 1)
    return t
end

-- A mark before a line of text. "check" and "dot" are client textures (the game fonts have no
-- check or circle glyph); anything else is drawn as text ("+", "!").
W.MARK_TEXTURES = { check = "Interface\\RaidFrame\\ReadyCheck-Ready", dot = "Interface\\COMMON\\Indicator-Gray" }
function W.Mark(parent, size)
    size = size or 14
    local m = { tex = parent:CreateTexture(nil, "OVERLAY"), text = W.Font(parent, size, C.good) }
    m.tex:SetSize(size, size)
    function m:SetPoint(...)
        self.tex:SetPoint(...)
        self.text:SetPoint(...)
    end
    function m:SetShown(on)
        self.shown = on and true or false
        self.tex:SetShown(self.shown and self.isTexture)
        self.text:SetShown(self.shown and not self.isTexture)
    end
    function m:Set(kind, color)
        local path = W.MARK_TEXTURES[kind]
        self.isTexture = path ~= nil
        if path then
            self.tex:SetTexture(path)
        else
            self.text:SetText(kind)
            local c = color or C.text
            self.text:SetTextColor(c[1], c[2], c[3], 1)
        end
        self:SetShown(self.shown ~= false)
    end
    return m
end

-- One-line text field (a pasted link): Enter calls onEnter(text), Esc clears and hides focus.
function W.EditLine(parent, width, onEnter)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(width, 30)
    e:SetAutoFocus(false)
    e:SetMaxLetters(300)
    e:SetFont(STANDARD_TEXT_FONT, 13, "")
    e:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    e:SetTextInsets(10, 10, 0, 0)
    W.Box(e, C.field, C.border)
    e:SetScript("OnEnterPressed", function(self) onEnter(self:GetText() or "") end)
    e:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    return e
end

-- Clickable row (list items): a panel that highlights on hover and when selected.
function W.Row(parent, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    function b.select(on)
        if on then W.Box(b, C.border, C.proc, 1, 0.35) else W.Box(b, C.panel, C.line) end
        b.selected = on
    end
    b.select(false)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) if not self.selected then self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1) end end)
    return b
end

-- Number box for thresholds: digits only, clamped, saved on Enter or focus loss.
function W.NumberBox(parent, min, max, get, set)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(48, 28)
    e:SetAutoFocus(false)
    e:SetNumeric(true)
    e:SetMaxLetters(3)
    e:SetFont(STANDARD_TEXT_FONT, 14, "")
    e:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    e:SetTextInsets(8, 6, 0, 0)
    W.Box(e, C.field, C.border)
    local function commit()
        local v = tonumber(e:GetText())
        if v then
            v = math.max(min, math.min(max, v))
            if v ~= get() then set(v) end
        end
        e:SetText(tostring(get()))
        e:ClearFocus()
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEscapePressed", function() e:SetText(tostring(get())); e:ClearFocus() end)
    function e.refresh() e:SetText(tostring(get())) end
    return e
end
