-- Draws a ForeverCoach window outside the game as an HTML page, to compare it with the mockups.
-- Frames are recorded (size, anchors, backdrop, textures, text), anchors are resolved the way the
-- client does it, and every visible region becomes an absolutely placed <div>.
-- Spell icons are placeholders and text width is estimated, so this checks layout, not pixels.
--   lua tools/preview_ui.lua builds|planner|recap|recap-session|recap-records|settings [ruRU|enUS] > preview.html
package.path = "tests/?.lua;" .. package.path
local addon = require("helpers.addon")
local tf = require("helpers.tf")

local which, locale = arg[1] or "builds", arg[2] or "ruRU"

-- Russian names of the spells the previews show (the test client only knows IDs).
local NAMES = {
    [686] = "Стрела Тьмы", [695] = "Стрела Тьмы", [705] = "Стрела Тьмы", [1088] = "Стрела Тьмы",
    [348] = "Жертвенный огонь", [707] = "Жертвенный огонь", [1094] = "Жертвенный огонь",
    [172] = "Порча", [6222] = "Порча", [980] = "Проклятие агонии", [1014] = "Проклятие агонии",
    [702] = "Проклятие слабости", [1108] = "Проклятие слабости", [689] = "Похищение жизни",
    [18265] = "Вытягивание жизни", [5740] = "Огненный ливень", [5782] = "Страх", [1454] = "Жизнеотвод",
    [755] = "Канал здоровья", [704] = "Проклятие безрассудства", [697] = "Призыв демона Бездны",
    [712] = "Призыв суккуба", [17810] = "Улучшенная порча", [18094] = "Сумерки", [18788] = "Демоническое жертвоприношение",
    [706] = "Демонический доспех", [5697] = "Бесконечное дыхание", [6201] = "Создание камня здоровья",
}

---------------------------------------------------------------------------
-- Recording frames
---------------------------------------------------------------------------

local regions = {}
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local Region = {}
Region.__index = function(_, k)
    local v = rawget(Region, k)
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^%u") then
        if k:match("^Get") then return function() return 0 end end
        if k:match("^Create") then return function() return nil end end
        return function() end
    end
end

local function newRegion(kind, parent, layer)
    local r = setmetatable({ kind = kind, parent = parent, points = {}, shown = true, layer = LAYER[layer or "ARTWORK"] or 3,
                             scripts = {}, children = {}, order = #regions + 1, depth = parent and parent.depth + 1 or 0 }, Region)
    regions[#regions + 1] = r
    if parent then parent.children[#parent.children + 1] = r end
    return r
end

function Region:SetSize(w, h) self.w, self.h = w, h end
function Region:SetWidth(w) self.w = w end
function Region:SetHeight(h) self.h = h end
function Region:GetWidth() return self.w or 0 end
function Region:GetHeight() return self.h or 0 end
function Region:ClearAllPoints() self.points = {} end
function Region:SetPoint(point, a, b, c, d)
    local rel, relPoint, x, y
    if type(a) == "number" or a == nil then
        rel, relPoint, x, y = nil, point, a or 0, b or 0
    elseif type(a) == "string" then
        rel, relPoint, x, y = nil, a, b or 0, c or 0
    else
        rel = a
        if type(b) == "string" then relPoint, x, y = b, c or 0, d or 0 else relPoint, x, y = point, b or 0, c or 0 end
    end
    for i, p in ipairs(self.points) do
        if p.point == point then table.remove(self.points, i) break end
    end
    self.points[#self.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function Region:SetAllPoints(rel)
    self.points = {}
    self:SetPoint("TOPLEFT", rel or self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", rel or self.parent, "BOTTOMRIGHT", 0, 0)
end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:SetShown(v) self.shown = v and true or false end
function Region:IsShown() return self.shown end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript() end
function Region:SetBackdrop(b) self.backdrop = b end
function Region:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a or 1 } end
function Region:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a or 1 } end
function Region:SetAlpha(a) self.alpha = a end
function Region:CreateTexture(_, layer) return newRegion("texture", self, layer) end
function Region:CreateFontString(_, layer) return newRegion("text", self, layer) end
function Region:SetTexture(t) self.texture = t end
function Region:SetColorTexture(r, g, b, a) self.texture = "flat"; self.color = { r, g, b, a or 1 } end
function Region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
function Region:SetRotation(rad) self.rotation = rad end
function Region:SetFont(_, size) self.size = size end
function Region:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a or 1 } end
function Region:SetJustifyH(j) self.justify = j end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetWordWrap(v) self.noWrap = not v end
function Region:GetStringWidth()
    local longest = 0
    for line in tostring(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gmatch("[^\n]+") do
        local n = select(2, line:gsub("[^\128-\191]", ""))
        if n > longest then longest = n end
    end
    return longest * (self.size or 12) * 0.56
end
function Region:SetThumbTexture(t) self.thumb = t end
function Region:SetValue(v) self.value = v end

local root = newRegion("frame", nil)
root.w, root.h = 1600, 1000

local function install()
    _G.CreateFrame = function(kind, _, parent)
        local f = newRegion(kind == "EditBox" and "edit" or "frame", parent or root)
        return f
    end
    _G.UIParent = root
    _G.UISpecialFrames = {}
    _G.C_Spell.GetSpellName = function(id) return NAMES[id] or ("spell" .. id) end
    _G.C_Spell.GetSpellInfo = function(id)
        return { name = NAMES[id] or ("spell" .. id), spellID = id, castTime = 0, iconID = id }
    end
end

---------------------------------------------------------------------------
-- The scene: a level 14 warlock with three talent points and Talents Forever installed
---------------------------------------------------------------------------

_G.TalentsForeverBookData = tf.data()
local ns, W = addon.load({ world = { locale = locale } })
addon.learnUpTo(ns, W, 12)
W.level = 14
W.known[697] = nil
W.traits = { [17810] = 3 }
addon.rescan(ns)
addon.compute(ns, W)
install()

local window
if which == "builds" then
    ns.BuildsWindow:Toggle()
    window = ns.BuildsWindow.frame
elseif which == "planner" then
    ns.Builds.Choose(ns.Builds.List("leveling", W.traits)[1])
    ns.PlannerWindow.at = 18
    ns.PlannerWindow:Toggle()
    window = ns.PlannerWindow.frame
elseif which == "recap" or which == "recap-session" or which == "recap-records" then
    ns.RecapWindow.tab = which == "recap" and "fights" or which:match("%-(%a+)$")
    ns.RecapWindow:Toggle()
    window = ns.RecapWindow.frame
else
    ns.Settings:Toggle()
    ns.Settings.frame:GetScript("OnShow")(ns.Settings.frame)
    window = ns.Settings.frame
end

---------------------------------------------------------------------------
-- Layout: anchors -> rectangles (x right, y down from the window's top-left corner)
---------------------------------------------------------------------------

local rects = {}
local function anchorOf(rect, point)
    local x = point:find("LEFT") and rect.l or point:find("RIGHT") and rect.r or (rect.l + rect.r) / 2
    local y = point:find("TOP") and rect.t or point:find("BOTTOM") and rect.b or (rect.t + rect.b) / 2
    return x, y
end

local resolve
resolve = function(r)
    if rects[r] then return rects[r] end
    if r == window then
        rects[r] = { l = 0, t = 0, r = r.w, b = r.h }
        return rects[r]
    end
    if r == root or not r.parent then
        rects[r] = { l = 0, t = 0, r = root.w, b = root.h }
        return rects[r]
    end
    local w, h = r.w, r.h
    if r.kind == "text" then
        w = w or r:GetStringWidth()
        local lines = select(2, tostring(r.text or ""):gsub("\n", "")) + 1
        if r.w and not r.noWrap then lines = math.max(lines, math.ceil(r:GetStringWidth() / r.w)) end
        h = h or (r.size or 12) * 1.25 * lines
    end
    local L, T, R, B, CX, CY
    for _, p in ipairs(r.points) do
        local rel = resolve(p.rel or r.parent)
        local ax, ay = anchorOf(rel, p.relPoint)
        ax, ay = ax + p.x, ay - p.y
        if p.point:find("LEFT") then L = ax elseif p.point:find("RIGHT") then R = ax else CX = ax end
        if p.point:find("TOP") then T = ay elseif p.point:find("BOTTOM") then B = ay else CY = ay end
    end
    w, h = w or 0, h or 0
    if not (L and R) then -- two edges anchored: the size follows them
        if L then R = L + w elseif R then L = R - w elseif CX then L, R = CX - w / 2, CX + w / 2 else L, R = 0, w end
    end
    if not (T and B) then
        if T then B = T + h elseif B then T = B - h elseif CY then T, B = CY - h / 2, CY + h / 2 else T, B = 0, h end
    end
    rects[r] = { l = L, t = T, r = R, b = B }
    return rects[r]
end

local function visible(r)
    while r do
        if not r.shown then return false end
        if r == window then return true end
        r = r.parent
    end
    return false
end

local function within(r)
    while r do
        if r == window then return true end
        r = r.parent
    end
    return false
end

---------------------------------------------------------------------------
-- HTML
---------------------------------------------------------------------------

local function css(c, alpha)
    if not c then return "transparent" end
    return string.format("rgba(%d,%d,%d,%.2f)", c[1] * 255, c[2] * 255, c[3] * 255, (c[4] or 1) * (alpha or 1))
end

local function esc(s)
    s = tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    s = s:gsub("|c%x%x(%x%x%x%x%x%x)(.-)|r", '<span style="color:#%1">%2</span>')
    return (s:gsub("\n", "<br>"))
end

local out = {}
local function emit(s) out[#out + 1] = s end
emit('<!doctype html><meta charset="utf-8"><title>ForeverCoach ' .. which .. '</title>')
emit('<style>body{margin:0;background:#0c0d10;font-family:Inter,Segoe UI,Arial,sans-serif}'
    .. '#w{position:relative;margin:0}div{position:absolute;box-sizing:border-box;white-space:nowrap}'
    .. '.t{white-space:normal;line-height:1.25}</style>')
emit(string.format('<div id="w" style="width:%dpx;height:%dpx">', window.w, window.h))
for _, r in ipairs(regions) do
    if within(r) and visible(r) then
        local rc = resolve(r)
        local z = r.depth * 10 + r.layer + (r.kind == "text" and 5 or 0)
        local box = string.format("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;z-index:%d;",
            rc.l, rc.t, math.max(0, rc.r - rc.l), math.max(0, rc.b - rc.t), z)
        if r.alpha then box = box .. string.format("opacity:%.2f;", r.alpha) end
        if r.kind == "frame" or r.kind == "edit" then
            if r.backdrop then
                local edge = r.backdrop.edgeSize or 1
                emit(string.format('<div style="%sbackground:%s;border:%dpx solid %s"></div>', box, css(r.bg),
                    edge, css(r.border)))
            end
            if r.kind == "edit" and r.text then
                emit(string.format('<div style="%scolor:#888;font-size:13px;padding:7px 10px">%s</div>', box, esc(r.text)))
            end
        elseif r.kind == "texture" and r.texture then
            local tex = tostring(r.texture)
            local style
            local glyph = (tex:find("ReadyCheck%-Ready") and '<b style="color:#6FCF97">&#10003;</b>')
                or (tex:find("Indicator%-Gray") and '<b style="color:#8A8F99">&#9675;</b>')
                or (tex:find("ChatFrameExpandArrow") and '<b style="color:#8A8F99">&#8250;</b>') or nil
            if glyph then
                style = "font-size:" .. math.floor(math.max(10, (r.h or 12))) .. "px;line-height:1;text-align:center"
                emit(string.format('<div style="%s%s">%s</div>', box, style, glyph))
                style = nil
            elseif tex:find("WHITE8X8") or tex == "flat" then
                style = "background:" .. css(r.color or { 1, 1, 1, 1 })
            elseif tex:find("Icons") or tonumber(tex) then
                style = "background:linear-gradient(135deg,#5b4a8a,#2a2440);"
            else
                style = "background:" .. css(r.color or { 0.6, 0.6, 0.6, 0.6 })
            end
            if style then
                if r.rotation then style = style .. string.format(";transform:rotate(%.0fdeg)", math.deg(r.rotation)) end
                emit(string.format('<div style="%s%s"></div>', box, style))
            end
        elseif r.kind == "text" and r.text and r.text ~= "" then
            local c = r.textColor or { 1, 1, 1, 1 }
            local align = (r.justify or "LEFT"):lower()
            local wrap = (r.w and not r.noWrap) and ' class="t"' or ""
            emit(string.format('<div%s style="%scolor:%s;font-size:%dpx;text-align:%s;overflow:visible">%s</div>',
                wrap, box, css(c), r.size or 12, align, esc(r.text)))
        end
    end
end
emit("</div>")
io.write(table.concat(out, "\n"))
