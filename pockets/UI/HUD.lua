--[[
    UI/HUD.lua - Compact bag HUD (TDD §13.1, PRD §3.1)

    A single small frame with minimal child objects: bag status background,
    capacity text, and a conditionally-shown ETA text. Updates only on
    capacity/ETA/position changes - never per frame (TDD §21).
]]

local _, Pockets = ...

Pockets.UI.HUD = Pockets.UI.HUD or {}
local HUD = Pockets.UI.HUD

local Layout = Pockets.UI.Layout
local Constants = Pockets.Constants

function HUD:Initialize()
    if self.frame then
        return
    end

    local frame = CreateFrame("Button", "PocketsHUDFrame", UIParent, "BackdropTemplate")
    frame:SetSize(140, 28)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    frame.capacityText = frame:CreateFontString(nil, "OVERLAY", Layout.FONT)
    frame.capacityText:SetPoint("LEFT", frame, "LEFT", Layout.PADDING, 4)

    frame.etaText = frame:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    frame.etaText:SetPoint("LEFT", frame, "LEFT", Layout.PADDING, -8)
    frame.etaText:SetTextColor(0.7, 0.7, 0.7)

    frame:SetScript("OnDragStart", function(self)
        if not Pockets.SavedSettings.hud.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        HUD:SavePosition()
    end)

    frame:SetScript("OnClick", function()
        -- Click always reveals the category flyout, in and out of combat (TDD §14).
        Pockets.UI.CategoryFlyout:Show(frame)
    end)

    frame:SetScript("OnEnter", function()
        if Pockets.Adapters.CombatAPI:CanHoverExpand() then
            Pockets.UI.CategoryFlyout:Show(frame)
        end
    end)
    frame:SetScript("OnLeave", function()
        Pockets.UI.CategoryFlyout:ScheduleHide()
    end)

    self.frame = frame
    self:RestorePosition()

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, function()
        self:Update()
    end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.ETA_CHANGED, function()
        self:Update()
    end, self)

    self:Update()
end

function HUD:RestorePosition()
    local hud = Pockets.SavedSettings.hud
    self.frame:ClearAllPoints()
    self.frame:SetPoint(hud.point, UIParent, hud.relativePoint, hud.x, hud.y)
end

function HUD:SavePosition()
    local hud = Pockets.SavedSettings.hud
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    hud.point = point
    hud.relativePoint = relativePoint
    hud.x = x
    hud.y = y
end

local function FormatETA(seconds)
    if not seconds then
        return nil
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then
        return "<1m"
    end
    return string.format("~%dm", minutes)
end

-- Refreshes HUD text from InventoryState/CapacityEstimator. Cheap and
-- idempotent; safe to call from any domain-event handler.
function HUD:Update()
    if not self.frame then
        return
    end

    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)

    self.frame.capacityText:SetText(string.format("%d / %d", capacity.used, capacity.total))
    self.frame.capacityText:SetTextColor(color.r, color.g, color.b)

    local estimator = Pockets.Services.CapacityEstimator
    local state = estimator:GetState()
    local confidenceOK = estimator:GetConfidence() >= 0.5

    if state == Constants.ESTIMATOR_STATE.FULL then
        self.frame.etaText:SetText("Full")
        self.frame.etaText:Show()
    elseif state == Constants.ESTIMATOR_STATE.FILLING and confidenceOK then
        local etaText = FormatETA(estimator:GetETA())
        if etaText then
            self.frame.etaText:SetText(etaText)
            self.frame.etaText:Show()
        else
            self.frame.etaText:Hide()
        end
    else
        -- warming_up / stable / freeing / low confidence: prefer omission over noise (TDD §11.4)
        self.frame.etaText:Hide()
    end
end

function HUD:Show()
    if self.frame then
        self.frame:Show()
    end
end

function HUD:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function HUD:Toggle()
    if not self.frame then
        return
    end
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
