--[[
    UI/RadialGlance.lua - Pockets' Radial Glance (Outer Ring TDD): the
    existing Mini centre surrounded by up to eight circular satellites.

    Slots are fixed and semantic (never reshuffled by data):
        1 gold | 2 ammo | 3-4 specialized bags | 5-8 recent items
    Recents also fill any unused ammo/bag slot. Satellites fade to a low
    idle alpha and brighten while the HUD is hovered (no layout change).
    Satellites are children
    of the HUD root but the root keeps the Mini footprint, so the centre's
    screen position never moves; satellites only inform/navigate and never
    use items. Reads domain state only; nodes are built once.
]]

-- luacheck: globals MouseIsOver

local _, Pockets = ...

Pockets.UI.RadialGlance = Pockets.UI.RadialGlance or {}
local RadialGlance = Pockets.UI.RadialGlance
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local RadialLayout = Pockets.UI.RadialLayout
local L = Constants.LAYOUT

RadialGlance.SLOT = { GOLD = 1, AMMO = 2, SPEC_1 = 3, SPEC_2 = 4, RECENT_FIRST = 5 }

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

-- Slot assignment. Returns { [1..8] = node model | nil }.
--   gold: copper; specialized: InventoryState:GetSpecializedCapacities();
--   recent: newest-first item records; ammoItems: carried ammo records
--   (any character can carry ammo, not just ones with a quiver).
function RadialGlance.BuildModel(gold, specialized, recent, ammoItems)
    local S = RadialGlance.SLOT
    local slots = {}
    slots[S.GOLD] = { kind = "gold", copper = gold or 0 }

    local ammoCount = 0
    for _, item in ipairs(ammoItems or {}) do
        ammoCount = ammoCount + (item.quantity or 0)
    end
    local others = {}
    for _, cap in ipairs(specialized or {}) do
        if (cap.total or 0) > 0 then
            if cap.class == "ammo" then
                slots[S.AMMO] = { kind = "bag", cap = cap, isAmmo = true, ammoCount = ammoCount }
            else
                table.insert(others, cap)
            end
        end
    end
    -- Loose ammo with no quiver: icon + arrow count, no capacity badge/arc.
    if not slots[S.AMMO] and ammoCount > 0 then
        slots[S.AMMO] = { kind = "ammo", item = ammoItems[1], ammoCount = ammoCount }
    end
    for i = 1, 2 do
        if others[i] then
            slots[S.SPEC_1 + i - 1] = { kind = "bag", cap = others[i] }
        end
    end

    -- Recents take their own slots first (5-8, newest first), then any
    -- unused ammo/bag slots (2, 3, 4) so no slot is left empty while recent
    -- items are waiting.
    local order = {}
    for slot = S.RECENT_FIRST, L.RADIAL_SLOTS do
        table.insert(order, slot)
    end
    for slot = S.AMMO, S.SPEC_2 do
        if not slots[slot] then
            table.insert(order, slot)
        end
    end
    for i, slot in ipairs(order) do
        local item = recent and recent[i]
        if not item then
            break
        end
        slots[slot] = { kind = "item", item = item }
    end
    return slots
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
    radial.offsetX, radial.offsetY = 0, 0
    root:HookScript("OnEnter", function() RadialGlance:OnHover(radial, true) end)
    root:HookScript("OnLeave", function() RadialGlance:OnHover(radial, false) end)
    return radial
end

-- Ring centre relative to the root's TOPLEFT: the middle of the whole Mini
-- footprint (portrait + hanging count badge), so the orbit looks balanced
-- rather than bottom-heavy around the portrait alone.
local CENTER_X = L.MINI_WIDTH / 2
local CENTER_Y = -L.MINI_HEIGHT / 2

-- Bounding reach of the ring from its centre (satellite radius + badge).
local function Extent()
    local half = L.RADIAL_NODE_SIZE / 2
    local reach = L.RADIAL_RADIUS + half
    return {
        left = reach,
        right = reach,
        top = reach,
        bottom = reach + L.RADIAL_BADGE_HEIGHT - L.RADIAL_BADGE_OVERLAP,
    }
end

-- Anchors every node, sliding the whole ring (never the centre) just enough
-- to stay on screen. Plain frames only; safe to call whenever.
function RadialGlance:Layout(radial)
    local dx, dy = 0, 0
    local cx, cy = radial.root:GetCenter()
    local left, top = radial.root:GetLeft(), radial.root:GetTop()
    if cx and top and left and UIParent then
        local ringX = left + CENTER_X
        local ringY = top + CENTER_Y
        dx, dy = RadialLayout.ClampOffset(ringX, ringY, Extent(), UIParent:GetWidth(), UIParent:GetHeight(), L.RADIAL_MAX_SHIFT)
    end
    radial.offsetX, radial.offsetY = dx, dy
    local half = L.RADIAL_NODE_SIZE / 2
    for slot, node in ipairs(radial.nodes) do
        -- Portrait centres sit on one true circle; the node's top edge is
        -- anchored (a badge, when present, hangs below the portrait).
        local x, y = RadialLayout.Position(slot, L.RADIAL_SLOTS, L.RADIAL_RADIUS)
        node:ClearAllPoints()
        node:SetPoint("TOP", radial.root, "TOPLEFT", CENTER_X + x + dx, CENTER_Y + y + dy + half)
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
    elseif model.kind == "item" then
        local item = model.item
        node:ShowBadge(false)
        node:SetIcon(item.texture)
        if (item.quantity or 0) > 1 then
            node:SetCount(tostring(item.quantity))
        end
        local color = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if color and item.quality > 1 then
            node:SetRimColor(color.r, color.g, color.b)
        end
        node:SetHover(RadialGlance.ItemHover(item))
        node:SetHandler(handlers.openRecent)
    end
end

-- layout: pass false in combat (anchors are left untouched).
function RadialGlance:Render(radial, layout)
    local InventoryState = Pockets.Services.InventoryState
    local slots = RadialGlance.BuildModel(
        Pockets.Adapters.MoneyAPI:GetMoney(),
        InventoryState:GetSpecializedCapacities(),
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.RECENT),
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.AMMO))
    Pockets.UI.ItemPreview:Hide() -- a node may have been reconfigured under the cursor
    radial.model = slots
    for slot, node in ipairs(radial.nodes) do
        local model = slots[slot]
        if model then
            Configure(node, model, radial.handlers)
            node:Show()
        else
            node:Hide()
        end
    end
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
    return false
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
    end
end
