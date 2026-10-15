--[[
    Shared/CircularMetricNode.lua - Small circular satellite (Outer Ring
    TDD §4, §6): CircularPortrait + optional thin capacity arc + optional
    bottom badge, lower-right stack count, and click callback.

    Generic: no Pockets strings or inventory APIs. A node never performs
    item actions - it is a plain Button that only calls the given handler.
    Created once; Set* update in place.
]]

local _, Pockets = ...

Pockets.UI.CircularMetricNode = Pockets.UI.CircularMetricNode or {}
local CircularMetricNode = Pockets.UI.CircularMetricNode
local PHUI = Pockets.UI.PHUI

-- opts: size, iconSize, badgeWidth, badgeHeight, badgeOverlap, onDragStart,
-- onDragStop (forwarded so dragging a satellite moves the HUD).
function CircularMetricNode:Create(parent, opts)
    local node = CreateFrame("Button", nil, parent)
    node:RegisterForClicks("AnyUp")
    node.size = opts.size
    node.badgeHeight = opts.badgeHeight
    node.badgeOverlap = opts.badgeOverlap

    local portrait = Pockets.UI.CircularPortrait:Create(node, {
        size = opts.size,
        iconSize = opts.iconSize,
        rimColor = PHUI.Colors.BORDER_BRONZE,
        rimThickness = 1.5,
        badge = {
            width = opts.badgeWidth,
            height = opts.badgeHeight,
            overlap = opts.badgeOverlap,
            font = PHUI.Fonts.NODE_COUNT,
            backdrop = PHUI.Backdrops.BADGE,
            bgColor = PHUI.Colors.BADGE_BG,
            borderColor = PHUI.Colors.BORDER_BRONZE,
            textColor = PHUI.Colors.TEXT_PRIMARY,
        },
    })
    portrait:SetPoint("TOP", node, "TOP", 0, 0)
    node.portrait = portrait

    -- Thin capacity arc just inside the rim (only for true used/total).
    local arc = Pockets.UI.CapacityRing:Create(portrait.portrait, {
        diameter = opts.size - 4,
        thickness = 2,
        segments = 28,
    })
    arc:SetPoint("CENTER", portrait.portrait, "CENTER", 0, 0)
    arc:SetFrameLevel(portrait.portrait:GetFrameLevel() + 10)
    arc:Hide()
    node.arc = arc

    -- Stack count, lower-right of the icon (WoW convention).
    local countHost = CreateFrame("Frame", nil, node)
    countHost:SetAllPoints(portrait.portrait)
    countHost:SetFrameLevel(portrait.portrait:GetFrameLevel() + 20)
    countHost:EnableMouse(false)
    node.count = PHUI.CreateLabel(countHost, "primary", nil, PHUI.Fonts.NODE_STACK)
    node.count:SetPoint("BOTTOMRIGHT", countHost, "BOTTOMRIGHT", -1, 3)
    node.count:SetJustifyH("RIGHT")

    function node:SetIcon(tex) portrait:SetIcon(tex) end
    function node:SetBadgeText(text) portrait:SetBadgeText(text) end
    function node:SetBadgeWidth(w) portrait:SetBadgeWidth(w) end
    function node:SetRimColor(r, g, b) portrait.rim:SetColor(r, g, b) end
    function node:SetCount(text) self.count:SetText(text or "") end
    -- Shows/hides the badge and resizes the hit rect to the visible art.
    function node:ShowBadge(shown)
        portrait.badge:SetShown(shown)
        local h = self.size
        if shown then
            h = self.size - self.badgeOverlap + self.badgeHeight
        end
        self:SetSize(math.max(self.size, shown and portrait.badge:GetWidth() or 0), h)
    end
    -- fraction nil -> no arc.
    function node:SetFraction(fraction, r, g, b)
        if fraction == nil then
            self.arc:Hide()
            return
        end
        self.arc:Show()
        self.arc:SetColor(r, g, b)
        self.arc:SetFraction(fraction)
    end
    function node:SetHandler(fn)
        self.handler = fn
    end
    -- Plain text tooltip (or clears hover handling when text is nil).
    function node:SetTooltipText(text)
        if not text then
            self.onEnter, self.onLeave = nil, nil
            return
        end
        self.onEnter = function(n)
            if GameTooltip then
                GameTooltip:SetOwner(n, "ANCHOR_RIGHT")
                GameTooltip:SetText(text)
                GameTooltip:Show()
            end
        end
        self.onLeave = nil
    end
    -- Custom hover handlers: enter(node) / leave(node).
    function node:SetHover(enter, leave)
        self.onEnter, self.onLeave = enter, leave
    end

    node:SetScript("OnClick", function(self)
        if self.handler then
            self.handler()
        end
    end)
    node:SetScript("OnEnter", function(self)
        if self.onEnter then
            self.onEnter(self)
        end
    end)
    node:SetScript("OnLeave", function(self)
        if GameTooltip then
            GameTooltip:Hide()
        end
        if self.onLeave then
            self.onLeave(self)
        end
    end)
    if opts.onDragStart then
        node:RegisterForDrag("LeftButton")
        node:SetScript("OnDragStart", opts.onDragStart)
        node:SetScript("OnDragStop", opts.onDragStop)
    end

    node:ShowBadge(true)
    node:SetSize(node:GetWidth(), node:GetHeight())
    return node
end
