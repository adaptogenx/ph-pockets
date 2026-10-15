--[[
    UI/SidecarHUD.lua - Pockets' Sidecar HUD: the existing Mini with gold
    and ammo badges stacked to its right and a compact strip of the five
    newest recent items 3px beneath it.

    No labels. The root keeps the Mini footprint, so the Mini never moves;
    badges and strip are children of the root. Gold has a fixed place (it
    never shifts when Ammo hides); the strip is content-sized and hidden
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
    backdrop = PHUI.Backdrops.BADGE, -- flat 1px bronze edge, no ornament
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

-- Badge width: at least the spec width, grown to fit icon + text (no clipping).
function SidecarHUD.BadgeWidth(textWidth)
    local pad = 3
    return math.max(L.SIDECAR_BADGE_WIDTH, pad * 3 + L.SIDECAR_BADGE_ICON + (textWidth or 0))
end

--------------------------------------------------
-- Build / Render
--------------------------------------------------

local function CreateBadge(root, handlers)
    local badge = CreateFrame("Button", nil, root, "BackdropTemplate")
    badge:SetSize(L.SIDECAR_BADGE_WIDTH, L.SIDECAR_BADGE_HEIGHT)
    badge:RegisterForClicks("AnyUp")
    PHUI.ApplyBackdrop(badge, {
        backdrop = PHUI.Backdrops.BADGE,
        bgColor = PHUI.Colors.BADGE_BG,
        borderColor = PHUI.Colors.BORDER_BRONZE,
    })
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetSize(L.SIDECAR_BADGE_ICON, L.SIDECAR_BADGE_ICON)
    badge.icon:SetPoint("LEFT", badge, "LEFT", 3, 0)
    badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge.text = PHUI.CreateLabel(badge, "primary", nil, PHUI.Fonts.NODE_COUNT)
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

-- Sets icon + text and grows the badge to fit its text.
local function SetBadge(badge, icon, text)
    badge.icon:SetTexture(icon)
    badge.text:SetText(text)
    badge:SetWidth(SidecarHUD.BadgeWidth(badge.text:GetStringWidth()))
end

-- root: the HUD root (TOPLEFT = Mini's top-left). handlers as RadialGlance's.
function SidecarHUD:Build(root, handlers)
    local sidecar = { root = root, handlers = handlers }
    sidecar.gold = CreateBadge(root, handlers)
    sidecar.ammo = CreateBadge(root, handlers)
    sidecar.strip = RadialGlance.CreateStrip(root, handlers, SidecarHUD.STRIP_SPEC)
    return sidecar
end

-- Column of badges right of the Mini, vertically centred on its portrait
-- (a fixed spot, so Gold never moves when Ammo hides); strip 3px under the
-- Mini, left-aligned with it. Near the right/bottom screen edge the badges
-- flip to the Mini's left / the strip moves above it. The Mini never moves.
function SidecarHUD:Layout(sidecar)
    local root = sidecar.root
    local left, top = root:GetLeft(), root:GetTop()
    local screenW = UIParent:GetWidth()
    local flip, stripAbove = false, false

    local column = 2 * L.SIDECAR_BADGE_HEIGHT + L.SIDECAR_BADGE_GAP
    local columnTop = -(L.MINI_PORTRAIT_SIZE - column) / 2
    local wide = math.max(sidecar.gold:GetWidth(), sidecar.ammo:IsShown() and sidecar.ammo:GetWidth() or 0)
    if left and top then
        flip = left + L.MINI_WIDTH + L.SIDECAR_MINI_GAP + wide > screenW
        stripAbove = top - L.MINI_HEIGHT - L.SIDECAR_STRIP_BELOW - L.SIDECAR_STRIP_HEIGHT < 0
    end

    local function place(badge, y)
        badge:ClearAllPoints()
        if flip then
            badge:SetPoint("TOPRIGHT", root, "TOPLEFT", -L.SIDECAR_MINI_GAP, y)
        else
            badge:SetPoint("TOPLEFT", root, "TOPLEFT", L.MINI_WIDTH + L.SIDECAR_MINI_GAP, y)
        end
    end
    place(sidecar.gold, columnTop)
    place(sidecar.ammo, columnTop - L.SIDECAR_BADGE_HEIGHT - L.SIDECAR_BADGE_GAP)

    -- Left-aligned with the Mini (right-aligned when flipped).
    local strip = sidecar.strip
    strip:ClearAllPoints()
    local side = flip and "RIGHT" or "LEFT"
    if stripAbove then
        strip:SetPoint("BOTTOM" .. side, root, "TOP" .. side, 0, L.SIDECAR_STRIP_BELOW)
    else
        strip:SetPoint("TOP" .. side, root, "BOTTOM" .. side, 0, -L.SIDECAR_STRIP_BELOW)
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
    SetBadge(gold, Constants.GOLD_ICON, RadialGlance.FormatGold(model.gold))
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
        SetBadge(ammo, icon, RadialGlance.FormatCount(m.ammoCount or 0))
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
    if #recent > 0 then
        sidecar.strip:SetWidth(RadialGlance.StripWidth(#recent, SidecarHUD.STRIP_SPEC))
    end
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
