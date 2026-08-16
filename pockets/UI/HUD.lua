--[[
    UI/HUD.lua - Compact bag HUD (TDD §13.1, PRD §3.1; UI_SPEC §2)

    Fixed-size frame: square bag icon (left) + capacity/ETA text region
    (right). Width/height never change with content - digit count or ETA
    appearing/disappearing must not resize the frame (UI_SPEC §16.2).
]]

local _, Pockets = ...

Pockets.UI.HUD = Pockets.UI.HUD or {}
local HUD = Pockets.UI.HUD

local Layout = Pockets.UI.Layout
local Constants = Pockets.Constants
local L = Constants.LAYOUT

function HUD:Initialize()
    if self.frame then
        return
    end

    local frame = CreateFrame("Button", "PocketsHUDFrame", UIParent, "BackdropTemplate")
    frame:SetSize(L.HUD_WIDTH, L.HUD_HEIGHT)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
    frame:SetBackdropBorderColor(0.35, 0.30, 0.20, 1)

    -- Square bag icon (UI_SPEC §2, §3): a verified built-in Blizzard
    -- texture, never custom artwork. See Constants.HUD_ICON provenance note.
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(L.HUD_ICON_SIZE, L.HUD_ICON_SIZE)
    frame.icon:SetPoint("LEFT", frame, "LEFT", 2, 0)
    frame.icon:SetTexture(Constants.HUD_ICON)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim default icon border padding

    frame.iconBorder = frame:CreateTexture(nil, "OVERLAY")
    frame.iconBorder:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -2, 2)
    frame.iconBorder:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 2, -2)
    frame.iconBorder:SetColorTexture(0.35, 0.30, 0.20, 1)
    frame.iconBorder:SetDrawLayer("ARTWORK", -1)

    -- Fixed-width text region: reserving this space (rather than sizing
    -- fontstrings to their text) is what keeps the frame width constant.
    frame.capacityText = frame:CreateFontString(nil, "OVERLAY", Layout.FONT)
    frame.capacityText:SetPoint("LEFT", frame.icon, "RIGHT", 8, 6)
    frame.capacityText:SetJustifyH("LEFT")

    frame.etaText = frame:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    frame.etaText:SetPoint("LEFT", frame.icon, "RIGHT", 8, -10)
    frame.etaText:SetJustifyH("LEFT")
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
        Pockets.UI.HoverGroup:Enter()
        if Pockets.Adapters.CombatAPI:CanHoverExpand() then
            Pockets.UI.CategoryFlyout:Show(frame)
        end
    end)
    frame:SetScript("OnLeave", function()
        Pockets.UI.HoverGroup:Leave(function()
            Pockets.UI.CategoryFlyout:Hide()
        end)
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
-- idempotent; safe to call from any domain-event handler. Never resizes
-- the frame - text just occupies (or leaves blank) its fixed region.
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
    elseif state == Constants.ESTIMATOR_STATE.FILLING and confidenceOK then
        self.frame.etaText:SetText(FormatETA(estimator:GetETA()) or "")
    else
        -- warming_up / stable / freeing / low confidence: prefer omission
        -- over noise (TDD §11.4). Text just goes blank; frame size is
        -- untouched either way.
        self.frame.etaText:SetText("")
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
