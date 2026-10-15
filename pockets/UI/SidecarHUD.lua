--[[
    UI/SidecarHUD.lua - Pockets' Sidecar HUD: the existing Mini with gold
    and ammo (icon + text on a soft dark pill) stacked to its right and the five newest recent items in a
    strip beneath it spanning exactly the same width (no outer frame).

    No labels. The root keeps the Mini footprint, so the Mini never moves;
    badges and strip are children of the root. Gold sits on the Mini midpoint alone,
    stacks above Ammo when present; the strip is content-sized and hidden
    when empty. Reuses RadialGlance's data model and recent strip. Nothing
    here uses items - clicks only navigate. Reads domain state only; frames
    are built once.
]]

local _, Pockets = ...

Pockets.UI.SidecarHUD = Pockets.UI.SidecarHUD or {}
local SidecarHUD = Pockets.UI.SidecarHUD
local RadialGlance = Pockets.UI.RadialGlance
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local L = Constants.LAYOUT

SidecarHUD.STRIP_SPEC = {
    icons = L.SIDECAR_STRIP_ICONS,
    icon = L.SIDECAR_STRIP_ICON,
    gap = L.SIDECAR_STRIP_GAP,
    padX = L.SIDECAR_STRIP_PAD_X,
    height = L.SIDECAR_STRIP_HEIGHT,
    backdrop = nil, -- no outer frame or background; the item borders are the frame
}

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- Gold amount (copper) and ammo model (or nil when not applicable), from the
-- same rules the Radial uses: an ammo bag, or any carried ammo.
function SidecarHUD.BuildModel(gold, specialized, ammoItems)
    local models = RadialGlance.BuildModel(gold, specialized, ammoItems)
    local ammo
    for _, model in ipairs(models) do
        if model.isAmmo or model.kind == "ammo" then
            ammo = model
        end
    end
    return { gold = gold or 0, ammo = ammo }
end

-- Gap between strip icons so five of them span exactly `width` (never less
-- than the minimum gap).
function SidecarHUD.StripGap(width)
    local spec = SidecarHUD.STRIP_SPEC
    return math.max(spec.gap, (width - spec.icons * spec.icon) / (spec.icons - 1))
end

-- Left offset of icon i (of n shown) in a strip `width` wide. Icons keep the
-- five-item slot spacing; align = "left" | "right" | "center".
function SidecarHUD.IconX(i, n, width, align)
    local spec = SidecarHUD.STRIP_SPEC
    local step = spec.icon + SidecarHUD.StripGap(width)
    local used = n * spec.icon + (n - 1) * (step - spec.icon)
    local start = 0
    if align == "right" then
        start = width - used
    elseif align == "center" then
        start = (width - used) / 2
    end
    return start + (i - 1) * step
end

-- Which side of the screen the HUD is on, by thirds of the Mini's centre.
function SidecarHUD.Align(centerX, screenW)
    if centerX < screenW / 3 then
        return "left"
    elseif centerX > screenW * 2 / 3 then
        return "right"
    end
    return "center"
end

-- Badge width: at least the spec width, grown to fit icon + text (no clipping).
function SidecarHUD.BadgeWidth(textWidth)
    local pad = 4
    return math.max(L.SIDECAR_BADGE_WIDTH, pad * 3 + L.SIDECAR_BADGE_ICON + (textWidth or 0))
end

--------------------------------------------------
-- Build / Render
--------------------------------------------------

local function CreateBadge(root, handlers)
    local badge = CreateFrame("Button", nil, root, "BackdropTemplate")
    badge:SetSize(L.SIDECAR_BADGE_WIDTH, L.SIDECAR_BADGE_HEIGHT)
    badge:RegisterForClicks("AnyUp")
    -- Soft dark rounded pill (translucent, faint bronze edge) so the value
    -- stays readable over bright scenery.
    PHUI.ApplyBackdrop(badge, {
        backdrop = PHUI.Backdrops.ROUNDED_SMALL,
        bgColor = PHUI.Colors.BADGE_BG,
        bgAlpha = 0.72,
        borderColor = PHUI.Colors.BORDER_BRONZE,
        borderAlpha = 0.55,
    })
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetSize(L.SIDECAR_BADGE_ICON, L.SIDECAR_BADGE_ICON)
    badge.icon:SetPoint("LEFT", badge, "LEFT", 4, 0)
    badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge.text = PHUI.CreateLabel(badge, "primary", nil, PHUI.Fonts.SIDECAR_VALUE)
    badge.text:SetPoint("LEFT", badge.icon, "RIGHT", 3, 0)
    badge.text:SetJustifyH("LEFT")
    badge:SetScript("OnEnter", function(self)
        if self.onEnter then self.onEnter(self) end
    end)
    badge:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.onLeave then self.onLeave(self) end
    end)
    badge:SetScript("OnClick", function(self)
        if self.handler then self.handler() end
    end)
    badge:RegisterForDrag("LeftButton")
    badge:SetScript("OnDragStart", handlers.dragStart)
    badge:SetScript("OnDragStop", handlers.dragStop)
    badge:Hide()
    return badge
end

-- Sets icon + text; returns the width this badge needs for its text.
local function SetBadge(badge, icon, text)
    badge.icon:SetTexture(icon)
    badge.text:SetText(text)
    return SidecarHUD.BadgeWidth(badge.text:GetStringWidth())
end

-- root: the HUD root (TOPLEFT = Mini's top-left). handlers as RadialGlance's.
function SidecarHUD:Build(root, handlers)
    local sidecar = { root = root, handlers = handlers }
    sidecar.gold = CreateBadge(root, handlers)
    sidecar.ammo = CreateBadge(root, handlers)
    sidecar.strip = RadialGlance.CreateStrip(root, handlers, SidecarHUD.STRIP_SPEC)
    return sidecar
end

-- The Mini plus the gold/ammo column form one container; the recent strip
-- spans exactly that width (shared left and right boundaries). Gold/ammo sit
-- 4px right of the Mini (left of it when the HUD is on the right of the
-- screen, mirroring the whole container); the strip is 4px beneath the Mini.
-- Icons are left-aligned on the left of the screen, right-aligned on the
-- right, centred otherwise. Near the bottom edge the strip moves above the
-- Mini. The Mini never moves.
function SidecarHUD:Layout(sidecar)
    local root = sidecar.root
    local left, top = root:GetLeft(), root:GetTop()
    local screenW = UIParent:GetWidth()
    local sideW = sidecar.sideW or L.SIDECAR_BADGE_WIDTH
    local containerW = L.MINI_WIDTH + L.SIDECAR_MINI_GAP + sideW
    local align, flip, stripAbove = "left", false, false
    if left and top then
        align = SidecarHUD.Align(left + L.MINI_WIDTH / 2, screenW)
        flip = align == "right" or left + containerW > screenW
        if flip and left + L.MINI_WIDTH - containerW < 0 then
            flip = false -- no room on the left either
        end
        stripAbove = top - L.MINI_HEIGHT - L.SIDECAR_STRIP_BELOW - L.SIDECAR_STRIP_HEIGHT < 0
    end

    -- Badge column, vertically centred on the Mini portrait: gold + ammo as
    -- a pair, or gold alone on the portrait's midpoint.
    local column = 2 * L.SIDECAR_BADGE_HEIGHT + L.SIDECAR_BADGE_GAP
    local columnTop = -(L.MINI_PORTRAIT_SIZE - column) / 2
    local function place(badge, y)
        badge:SetWidth(sideW)
        badge:ClearAllPoints()
        if flip then
            badge:SetPoint("TOPRIGHT", root, "TOPLEFT", -L.SIDECAR_MINI_GAP, y)
        else
            badge:SetPoint("TOPLEFT", root, "TOPLEFT", L.MINI_WIDTH + L.SIDECAR_MINI_GAP, y)
        end
    end
    if sidecar.ammo:IsShown() then
        place(sidecar.gold, columnTop)
        place(sidecar.ammo, columnTop - L.SIDECAR_BADGE_HEIGHT - L.SIDECAR_BADGE_GAP)
    else
        place(sidecar.gold, -(L.MINI_PORTRAIT_SIZE - L.SIDECAR_BADGE_HEIGHT) / 2)
        place(sidecar.ammo, columnTop - L.SIDECAR_BADGE_HEIGHT - L.SIDECAR_BADGE_GAP)
    end

    local strip = sidecar.strip
    strip:SetWidth(containerW)
    strip:ClearAllPoints()
    local side = flip and "RIGHT" or "LEFT"
    if stripAbove then
        strip:SetPoint("BOTTOM" .. side, root, "TOP" .. side, 0, L.SIDECAR_STRIP_BELOW)
    else
        strip:SetPoint("TOP" .. side, root, "BOTTOM" .. side, 0, -L.SIDECAR_STRIP_BELOW)
    end
    local shown = 0
    for _, btn in ipairs(strip.icons) do
        if btn:IsShown() then
            shown = shown + 1
        end
    end
    local n = 0
    for _, btn in ipairs(strip.icons) do
        if btn:IsShown() then
            n = n + 1
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", strip, "LEFT", SidecarHUD.IconX(n, shown, containerW, align), 0)
        end
    end
end

-- layout: pass false in combat (anchors are left untouched).
function SidecarHUD:Render(sidecar, layout)
    local InventoryState = Pockets.Services.InventoryState
    local model = SidecarHUD.BuildModel(
        Pockets.Adapters.MoneyAPI:GetMoney(),
        InventoryState:GetSpecializedCapacities(),
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.AMMO))
    local recent = RadialGlance.BuildRecent(
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.RECENT), SidecarHUD.STRIP_SPEC)
    Pockets.UI.ItemPreview:Hide()
    sidecar.model = model

    local gold = sidecar.gold
    local sideW = SetBadge(gold, Constants.GOLD_ICON, RadialGlance.FormatGold(model.gold))
    local money = Pockets.UI.MoneyFormat:Format(model.gold)
    gold.onEnter = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(money)
        GameTooltip:Show()
    end
    gold:Show()

    local ammo = sidecar.ammo
    if model.ammo then
        local m = model.ammo
        local icon = m.kind == "ammo" and m.item.texture or m.cap.texture
        sideW = math.max(sideW, SetBadge(ammo, icon, RadialGlance.FormatCount(m.ammoCount or 0)))
        ammo.onEnter = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Ammo: " .. (m.ammoCount or 0))
            GameTooltip:Show()
        end
        ammo.handler = sidecar.handlers.openAmmo
        ammo:Show()
    else
        ammo:Hide()
    end

    for i, btn in ipairs(sidecar.strip.icons) do
        RadialGlance.ConfigureStripIcon(btn, recent[i])
    end
    sidecar.sideW = sideW
    sidecar.strip:SetShown(#recent > 0)

    if layout ~= false then
        self:Layout(sidecar)
    end
end

function SidecarHUD:SetShown(sidecar, shown)
    if not shown then
        sidecar.gold:Hide()
        sidecar.ammo:Hide()
        sidecar.strip:Hide()
    end
end
