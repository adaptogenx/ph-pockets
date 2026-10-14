--[[
    UI/RadialGlance.lua - Pockets' Radial Glance: the existing Mini centre
    with a semicircle of metric satellites (gold, ammo, specialized bags)
    that fans away from the nearest screen edge, plus a compact strip of the
    five newest recent items beneath it.

    Only available metrics get a satellite; they are spread evenly across the
    arc. The root keeps the Mini footprint, so the Mini never moves.
    Satellites and strip fade to a low idle alpha and brighten while the HUD
    is hovered (no layout change). Nothing here uses items - clicks only
    navigate. Reads domain state only; nodes/strip icons are built once.
]]

-- luacheck: globals MouseIsOver

local _, Pockets = ...

Pockets.UI.RadialGlance = Pockets.UI.RadialGlance or {}
local RadialGlance = Pockets.UI.RadialGlance
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local RadialLayout = Pockets.UI.RadialLayout
local L = Constants.LAYOUT

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- Compact carried money that keeps its denomination: "45c", "12s",
-- "152g", "12.4kg", "1.2mg".
function RadialGlance.FormatGold(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then
        copper = 0
    end
    local gold = math.floor(copper / 10000)
    if gold >= 1000000 then
        return string.format("%.1fmg", gold / 1000000)
    elseif gold >= 10000 then
        return string.format("%.1fkg", gold / 1000)
    elseif gold > 0 then
        return string.format("%dg", gold)
    end
    local silver = math.floor(copper / 100)
    if silver > 0 then
        return string.format("%ds", silver)
    end
    return string.format("%dc", copper)
end

-- Stack-style count: "100", "9999", "12k".
function RadialGlance.FormatCount(n)
    n = math.floor(tonumber(n) or 0)
    if n >= 10000 then
        return string.format("%dk", math.floor(n / 1000))
    end
    return tostring(n)
end

-- "used/total" for a bag-occupancy node.
function RadialGlance.FormatBag(used, total)
    return Pockets.UI.MiniHUD.FormatCount(used, total)
end

-- Visible metric satellites, in fixed order: gold, ammo, then up to two
-- specialized bags. Unavailable metrics are simply absent (no placeholders).
--   gold: copper; specialized: InventoryState:GetSpecializedCapacities();
--   ammoItems: carried ammo records (any character can carry ammo, not just
--   ones with a quiver).
function RadialGlance.BuildModel(gold, specialized, ammoItems)
    local ammoCount = 0
    for _, item in ipairs(ammoItems or {}) do
        ammoCount = ammoCount + (item.quantity or 0)
    end
    local ammo
    local others = {}
    for _, cap in ipairs(specialized or {}) do
        if (cap.total or 0) > 0 then
            if cap.class == "ammo" then
                ammo = { kind = "bag", cap = cap, isAmmo = true, ammoCount = ammoCount }
            else
                table.insert(others, cap)
            end
        end
    end
    -- Loose ammo with no quiver: icon + arrow count, no capacity badge/arc.
    if not ammo and ammoCount > 0 then
        ammo = { kind = "ammo", item = ammoItems[1], ammoCount = ammoCount }
    end

    local nodes = { { kind = "gold", copper = gold or 0 } }
    if ammo then
        table.insert(nodes, ammo)
    end
    for i = 1, 2 do
        if others[i] then
            table.insert(nodes, { kind = "bag", cap = others[i] })
        end
    end
    return nodes
end

-- The newest recent items for the strip (newest first, max 5).
function RadialGlance.BuildRecent(recent)
    local out = {}
    for i = 1, math.min(#(recent or {}), L.RADIAL_STRIP_ICONS) do
        out[i] = recent[i]
    end
    return out
end

--------------------------------------------------
-- Build / Render
--------------------------------------------------

-- root: the HUD root (TOPLEFT = Mini's top-left). handlers: { openRecent,
-- openAmmo, openList, dragStart, dragStop }.
function RadialGlance:Build(root, handlers)
    local radial = { root = root, handlers = handlers, nodes = {} }
    for slot = 1, L.RADIAL_SLOTS do
        local node = Pockets.UI.CircularMetricNode:Create(root, {
            size = L.RADIAL_NODE_SIZE,
            iconSize = L.RADIAL_NODE_ICON,
            badgeWidth = L.RADIAL_BADGE_WIDTH,
            badgeHeight = L.RADIAL_BADGE_HEIGHT,
            badgeOverlap = L.RADIAL_BADGE_OVERLAP,
            onDragStart = handlers.dragStart,
            onDragStop = handlers.dragStop,
            onHover = function(_, entered)
                RadialGlance:OnHover(radial, entered)
            end,
        })
        node.slot = slot
        node:Hide()
        radial.nodes[slot] = node
    end
    radial.strip = RadialGlance:CreateStrip(root, radial, handlers)
    root:HookScript("OnEnter", function() RadialGlance:OnHover(radial, true) end)
    root:HookScript("OnLeave", function() RadialGlance:OnHover(radial, false) end)
    return radial
end

-- Recent strip: fixed-size frame (never resizes with content), five plain
-- 24px icon buttons. Hover = item tooltip (+ big preview when enabled);
-- click = open Recent. Never uses the item.
function RadialGlance:CreateStrip(root, radial, handlers)
    local strip = CreateFrame("Frame", nil, root, "BackdropTemplate")
    strip:SetSize(L.RADIAL_STRIP_WIDTH, L.RADIAL_STRIP_HEIGHT)
    PHUI.ApplyBackdrop(strip, {
        backdrop = PHUI.Backdrops.BADGE,
        bgColor = PHUI.Colors.BG_DARK,
        bgAlpha = L.GLANCE_ALPHA,
        borderColor = PHUI.Colors.BORDER_BRONZE,
    })
    strip:Hide()
    strip.icons = {}
    local bronze = PHUI.Colors.BORDER_BRONZE
    for i = 1, L.RADIAL_STRIP_ICONS do
        local btn = CreateFrame("Button", nil, strip, "BackdropTemplate")
        btn:SetSize(L.RADIAL_STRIP_ICON, L.RADIAL_STRIP_ICON)
        btn:SetPoint("LEFT", strip, "LEFT",
            L.RADIAL_STRIP_PAD_X + (i - 1) * (L.RADIAL_STRIP_ICON + L.RADIAL_STRIP_GAP), 0)
        btn:RegisterForClicks("AnyUp")
        btn:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.count = PHUI.CreateLabel(btn, "primary", nil, PHUI.Fonts.NODE_STACK)
        btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.count:SetJustifyH("RIGHT")
        btn:SetScript("OnClick", function() handlers.openRecent() end)
        btn:SetScript("OnEnter", function(self)
            RadialGlance:OnHover(radial, true)
            if self.onEnter then self.onEnter(self) end
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            if self.onLeave then self.onLeave(self) end
            RadialGlance:OnHover(radial, false)
        end)
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnDragStart", handlers.dragStart)
        btn:SetScript("OnDragStop", handlers.dragStop)
        btn.defaultBorder = bronze
        btn:Hide()
        strip.icons[i] = btn
    end
    return strip
end

-- Ring centre relative to the root's TOPLEFT: the middle of the whole Mini
-- footprint (portrait + hanging count badge).
local CENTER_X = L.MINI_WIDTH / 2
local CENTER_Y = -L.MINI_HEIGHT / 2

-- Anchors the visible satellites on a semicircle facing away from the
-- nearest screen edge (sliding the fan, never the Mini, just enough to stay
-- on screen), then the strip beneath the lowest visible element. Plain
-- frames only; safe to call whenever. Visible nodes only - hidden ones are
-- not positioned.
function RadialGlance:Layout(radial)
    local visible = {}
    for _, node in ipairs(radial.nodes) do
        if node:IsShown() then
            table.insert(visible, node)
        end
    end
    local half = L.RADIAL_NODE_SIZE / 2
    local miniHalfW, miniHalfH = L.MINI_WIDTH / 2, L.MINI_HEIGHT / 2

    local root = radial.root
    local left, top = root:GetLeft(), root:GetTop()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local ringX, ringY
    if left and top then
        ringX, ringY = left + CENTER_X, top + CENTER_Y
    end
    local center = ringX and RadialLayout.EdgeAngle(ringX, ringY, screenW, screenH) or 0
    radial.facing = center

    -- Positions relative to the ring centre (y up) and the fan's bounding box.
    local angles = RadialLayout.ArcAngles(#visible, center, L.RADIAL_ARC_SPAN)
    local pts = {}
    local minX, maxX, minY, maxY = -miniHalfW, miniHalfW, -miniHalfH, miniHalfH
    for i, node in ipairs(visible) do
        local x, y = RadialLayout.PositionAt(angles[i], L.RADIAL_RADIUS)
        pts[i] = { x = x, y = y }
        minX = math.min(minX, x - node:GetWidth() / 2)
        maxX = math.max(maxX, x + node:GetWidth() / 2)
        maxY = math.max(maxY, y + half)
        minY = math.min(minY, y + half - node:GetHeight())
    end
    local dx, dy = 0, 0
    if ringX then
        dx, dy = RadialLayout.ClampOffset(ringX, ringY,
            { left = -minX, right = maxX, top = maxY, bottom = -minY },
            screenW, screenH, L.RADIAL_MAX_SHIFT)
    end
    radial.offsetX, radial.offsetY = dx, dy
    -- The shift only applies to satellites; the Mini rect stays put.
    local lowest, highest = -miniHalfH, miniHalfH
    for i, node in ipairs(visible) do
        node:ClearAllPoints()
        node:SetPoint("TOP", root, "TOPLEFT", CENTER_X + pts[i].x + dx, CENTER_Y + pts[i].y + dy + half)
        lowest = math.min(lowest, pts[i].y + dy + half - node:GetHeight())
        highest = math.max(highest, pts[i].y + dy + half)
    end

    -- Strip: centred under the Mini, 6px below the lowest visible element;
    -- if that would fall off the bottom of the screen, above the highest.
    local strip = radial.strip
    if strip:IsShown() then
        local stripTop = lowest - L.RADIAL_STRIP_OFFSET
        if ringY and ringY + stripTop - L.RADIAL_STRIP_HEIGHT < 0 then
            stripTop = highest + L.RADIAL_STRIP_OFFSET + L.RADIAL_STRIP_HEIGHT
        end
        local sdx = 0
        if ringX then
            local halfStrip = L.RADIAL_STRIP_WIDTH / 2
            if ringX - halfStrip < 0 then
                sdx = halfStrip - ringX
            elseif ringX + halfStrip > screenW then
                sdx = screenW - halfStrip - ringX
            end
        end
        strip:ClearAllPoints()
        strip:SetPoint("TOP", root, "TOPLEFT", CENTER_X + sdx, CENTER_Y + stripTop)
    end
end

-- Real item tooltip on hover (bag slot when known, else the link/id), plus
-- the big floating preview when the player enabled it. Display only.
function RadialGlance.ItemHover(item)
    local function enter(node)
        GameTooltip:SetOwner(node, "ANCHOR_RIGHT")
        local BagAPI = Pockets.Adapters.BagAPI
        local ok = false
        if item.bagID and item.slotID then
            ok = pcall(BagAPI.SetTooltipToBagItem, BagAPI, GameTooltip, item.bagID, item.slotID)
        end
        if not ok then
            local link = item.itemLink or (item.itemID and ("item:" .. item.itemID))
            ok = link ~= nil and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        end
        if ok then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
        if Pockets.SavedSettings.recentItemPreviewEnabled then
            Pockets.UI.ItemPreview:Show(item)
        end
    end
    local function leave()
        Pockets.UI.ItemPreview:Hide()
    end
    return enter, leave
end

local function Configure(node, model, handlers)
    local Layout = Pockets.UI.Layout
    local bronze = PHUI.Colors.BORDER_BRONZE
    node:SetRimColor(bronze[1], bronze[2], bronze[3])
    node:SetCount(nil)
    node:SetFraction(nil)
    node:SetTooltipText(nil)
    node:SetHandler(nil)

    if model.kind == "gold" then
        node:SetBadgeWidth(L.RADIAL_GOLD_BADGE_WIDTH)
        node:ShowBadge(true)
        node:SetIcon(Constants.GOLD_ICON)
        node:SetBadgeText(RadialGlance.FormatGold(model.copper))
        node:SetTooltipText(Pockets.UI.MoneyFormat:Format(model.copper))
    elseif model.kind == "bag" then
        local cap = model.cap
        node:SetBadgeWidth(L.RADIAL_BADGE_WIDTH)
        node:ShowBadge(true)
        node:SetIcon(cap.texture)
        node:SetBadgeText(RadialGlance.FormatBag(cap.used, cap.total))
        local c = Layout:GetCapacityColor(cap.utilization or 0)
        node:SetFraction(cap.utilization or 0, c.r, c.g, c.b)
        if model.ammoCount and model.ammoCount > 0 then
            node:SetCount(RadialGlance.FormatCount(model.ammoCount))
        end
        node:SetTooltipText(model.ammoCount and (cap.label .. ": " .. model.ammoCount) or cap.label)
        node:SetHandler(model.isAmmo and handlers.openAmmo or handlers.openList)
    elseif model.kind == "ammo" then
        node:ShowBadge(false)
        node:SetIcon(model.item.texture)
        node:SetCount(RadialGlance.FormatCount(model.ammoCount))
        node:SetHover(RadialGlance.ItemHover(model.item))
        node:SetHandler(handlers.openAmmo)
    end
end

-- Configures one strip icon (or hides it) for a recent-item record.
local function ConfigureStripIcon(btn, item)
    if not item then
        btn:Hide()
        return
    end
    btn.icon:SetTexture(item.texture)
    btn.count:SetText((item.quantity or 0) > 1 and tostring(item.quantity) or "")
    local color = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
    local c = btn.defaultBorder
    if color and item.quality > 1 then
        btn:SetBackdropBorderColor(color.r, color.g, color.b, 1)
    else
        btn:SetBackdropBorderColor(c[1], c[2], c[3], 0.6)
    end
    btn.onEnter, btn.onLeave = RadialGlance.ItemHover(item)
    btn:Show()
end

-- layout: pass false in combat (anchors are left untouched).
function RadialGlance:Render(radial, layout)
    local InventoryState = Pockets.Services.InventoryState
    local models = RadialGlance.BuildModel(
        Pockets.Adapters.MoneyAPI:GetMoney(),
        InventoryState:GetSpecializedCapacities(),
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.AMMO))
    local recent = RadialGlance.BuildRecent(
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.RECENT))
    Pockets.UI.ItemPreview:Hide() -- a node may have been reconfigured under the cursor
    radial.model = models
    radial.recentModel = recent
    for i, node in ipairs(radial.nodes) do
        local model = models[i]
        if model then
            Configure(node, model, radial.handlers)
            node:Show()
        else
            node:Hide()
        end
    end
    for i, btn in ipairs(radial.strip.icons) do
        ConfigureStripIcon(btn, recent[i])
    end
    radial.strip:SetShown(#recent > 0)
    self:ApplyAlpha(radial)
    if layout ~= false then
        self:Layout(radial)
    end
end

-- Fade only: brightens while the mouse is over the centre or any satellite.
function RadialGlance:ApplyAlpha(radial)
    local hovered = radial.hovered
    local alpha = hovered and 1 or L.RADIAL_IDLE_ALPHA
    for _, node in ipairs(radial.nodes) do
        node:SetAlpha(alpha)
    end
    radial.strip:SetAlpha(alpha)
end

-- Frame:IsMouseOver on current clients; the old global where it still exists.
local function Over(frame)
    if frame.IsMouseOver then
        return frame:IsMouseOver()
    end
    return MouseIsOver and MouseIsOver(frame) or false
end

local function IsMouseOverHud(radial)
    if Over(radial.root) then
        return true
    end
    for _, node in ipairs(radial.nodes) do
        if node:IsShown() and Over(node) then
            return true
        end
    end
    return radial.strip:IsShown() and Over(radial.strip)
end

function RadialGlance:OnHover(radial, entered)
    if entered then
        radial.hovered = true
        self:ApplyAlpha(radial)
        return
    end
    -- Leaving one piece may mean entering a neighbour: re-check shortly.
    local function settle()
        radial.hovered = IsMouseOverHud(radial)
        RadialGlance:ApplyAlpha(radial)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.1, settle)
    else
        settle()
    end
end

function RadialGlance:SetShown(radial, shown)
    if not shown then
        for _, node in ipairs(radial.nodes) do
            node:Hide()
        end
        radial.strip:Hide()
    end
end
