-- Minimap button: left click settings, right click show/hide hints, drag to move around the map.
-- The same actions are in the AddOns compartment of the client (ForeverCoach_OnAddonCompartmentClick).
local ADDON, ns = ...
local L, Events = ns.L, ns.Events

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local RADIUS = 80

local function place(button, angle)
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

function MinimapButton:Create()
    if self.button or not Minimap then return end
    local b = CreateFrame("Button", "ForeverCoachMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowBolt")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, mouse)
        ForeverCoach_Binding(mouse == "RightButton" and "toggle" or "settings")
    end)
    b:SetScript("OnDragStart", function(btn)
        btn:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            ns.db.minimap.angle = angle
            place(btn, angle)
        end)
    end)
    b:SetScript("OnDragStop", function(btn) btn:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:AddLine("ForeverCoach")
        GameTooltip:AddLine(L.MINIMAP_TIP_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_RIGHT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = b
    self:Apply()
end

function MinimapButton:Apply()
    local b = self.button
    if not b then return end
    place(b, ns.db.minimap.angle or 215)
    b:SetShown(not ns.db.minimap.hide)
end

Events:On("FC_SETTINGS_CHANGED", MinimapButton, function(self, _, key)
    if key == "minimap" or key == "reset" then self:Apply() end
end)
