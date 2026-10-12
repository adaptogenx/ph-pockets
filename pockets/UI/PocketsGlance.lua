--[[
    UI/PocketsGlance.lua - Pockets' Glance content composed on the shared
    GlanceFrame chassis (Forever Glance TDD §4-§6).

    Header: pockets | main-bag ETA | Search, Log, Expand (+).
    Body:   bag capacity (click -> All Items) | money | five Recent icons.
    Tabs:   specialized bags (Ammo, Reagents, profession) docked below.

    Reads domain state only (InventoryState/CapacityEstimator/Recent); it
    never rescans bags. Layout is fixed - values update in place, nothing
    is rebuilt or resized per render.
]]

local _, Pockets = ...

Pockets.UI.PocketsGlance = Pockets.UI.PocketsGlance or {}
local PocketsGlance = Pockets.UI.PocketsGlance
local GlanceFrame = Pockets.UI.GlanceFrame
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local T = GlanceFrame.TOKENS

PocketsGlance.RECENT_SLOTS = 5
PocketsGlance.MAX_TABS = #Pockets.Adapters.BagAPI.BAG_CLASS_ORDER

--------------------------------------------------
-- Pure formatting (unit-testable)
--------------------------------------------------

-- "used / total", or "— / —" when capacity is unknown (never divides).
function PocketsGlance.FormatCapacity(used, total)
    if type(total) ~= "number" or total <= 0 then
        return "\226\128\148 / \226\128\148"
    end
    return string.format("%d / %d", used or 0, total)
end

-- Main-bag ETA header text -> value, suffix. Prefers omission to a noisy
-- number: only the FILLING state above the confidence threshold shows one.
-- `eta` is already the compact string ("18m") or nil.
function PocketsGlance.FormatEta(isFull, isFilling, confidenceOK, compactEta)
    if isFull then
        return "Full", ""
    end
    if isFilling and confidenceOK and compactEta then
        return compactEta, "to full"
    end
    return "\226\128\148", "to full"
end

-- Specialized capacities (InventoryState:GetSpecializedCapacities) -> tab
-- models, preserving the given stable order.
function PocketsGlance.BuildTabModels(specialized, colorFor)
    local models = {}
    for _, cap in ipairs(specialized or {}) do
        table.insert(models, {
            class = cap.class,
            texture = cap.texture,
            value = PocketsGlance.FormatCapacity(cap.used, cap.total),
            label = cap.label,
            fraction = cap.utilization,
            color = colorFor(cap.utilization),
        })
    end
    return models
end

--------------------------------------------------
-- Build
--------------------------------------------------

-- glance: the Frame filling the HUD root. handlers: { openSearch,
-- openLog, openAll }. Returns the glance table's widgets.
function PocketsGlance:Build(glance, handlers)
    local L = Constants.LAYOUT

    local chassis = GlanceFrame:Build(glance, {
        title = "pockets",
        buttons = {
            {
                texture = "Interface\\Common\\UI-Searchbox-Icon",
                tooltipText = "Quick Search",
                onClick = handlers.openSearch,
            },
            {
                texture = PHUI.Icons.SCROLL,
                tooltipText = "Loot Log",
                onClick = handlers.openLog,
            },
            {
                texture = PHUI.Icons.PLUS,
                native = true,
                tooltipText = "All Items",
                onClick = handlers.openAll,
            },
        },
    })
    glance.chassis = chassis
    glance.header = chassis.header
    local header = chassis.header
    header.iconButton = header.icons[1]
    header.lootButton = header.icons[2]
    header.plusButton = header.icons[3]
    -- Back-compat: the ETA value is what used to be the "(8m)" subtitle.
    header.subtitleText = header.etaValue
    function header:SetSubtitle(text)
        self.etaValue:SetText(text or "")
    end

    -- Bag group: icon + count + chevron + fill bar, ONE click target that
    -- opens All Items directly.
    local bagSection = chassis:AddSection(L.GLANCE_BAG_GROUP_WIDTH)
    local bag = CreateFrame("Button", nil, bagSection)
    bag:SetAllPoints(bagSection)
    bag:RegisterForClicks("AnyUp")
    bag:SetScript("OnClick", function() handlers.openAll() end)
    bag.icon = PHUI.CreateNativeIcon(bag, T.ICON_MAIN, Constants.HUD_ICON, { insetTexCoord = false })
    bag.icon:SetPoint("LEFT", bag, "LEFT", 0, 0)
    bag.primaryText = PHUI.CreateLabel(bag, "primary", nil, PHUI.Fonts.CAPACITY)
    bag.primaryText:SetPoint("TOPLEFT", bag, "TOPLEFT", T.ICON_MAIN + 8, -7)
    bag.primaryText:SetJustifyH("LEFT")
    -- Navigation cue (a real Blizzard arrow texture - the title font has
    -- no reliable "›" glyph).
    bag.chevron = PHUI.CreateNativeIcon(bag, 14, PHUI.Icons.NEXT, { insetTexCoord = false })
    bag.chevron:SetPoint("LEFT", bag.primaryText, "RIGHT", 2, 0)
    bag.bar = GlanceFrame:CreateBar(bag, 90, 4)
    bag.bar:SetPoint("BOTTOMLEFT", bag, "BOTTOMLEFT", T.ICON_MAIN + 8, 8)
    function bag:SetPrimary(text) self.primaryText:SetText(text) end
    function bag:SetPrimaryColor(r, g, b)
        self.primaryText:SetTextColor(r, g, b)
        self.bar:SetColor(r, g, b)
    end
    function bag:SetFill(fraction) self.bar:SetFraction(fraction) end
    glance.bagRow = bag

    -- Money: coin + amount, no bar.
    local moneySection = chassis:AddSection(L.GLANCE_MONEY_GROUP_WIDTH)
    local gold = CreateFrame("Frame", nil, moneySection)
    gold:SetAllPoints(moneySection)
    gold.icon = PHUI.CreateNativeIcon(gold, 20, Constants.GOLD_ICON, { insetTexCoord = false })
    gold.icon:SetPoint("LEFT", gold, "LEFT", 0, 0)
    gold.primaryText = PHUI.CreateLabel(gold, "primary", nil, PHUI.Fonts.MONEY)
    gold.primaryText:SetPoint("LEFT", gold.icon, "RIGHT", 6, 0)
    gold.primaryText:SetJustifyH("LEFT")
    function gold:SetPrimary(text) self.primaryText:SetText(text) end
    glance.goldRow = gold

    -- Five Recent slots, newest first. No label, no ">>" button (the Log
    -- is in the header).
    local recentSection = chassis:AddSection(nil)
    local stripWidth = PocketsGlance.RECENT_SLOTS * T.ICON_RECENT + (PocketsGlance.RECENT_SLOTS - 1) * T.ICON_GAP
    glance.recentStrip = Pockets.UI.RecentItemStrip:Create(recentSection, {
        width = stripWidth,
        iconSize = T.ICON_RECENT,
        gap = T.ICON_GAP,
    })
    glance.recentStrip:SetPoint("RIGHT", recentSection, "RIGHT", 0, 0)

    -- Tabs: a fixed pool (created once; overlays/anchors never churn).
    glance.tabs = {}
    for i = 1, PocketsGlance.MAX_TABS do
        local tab = GlanceFrame:CreateTab(glance)
        tab:RegisterForClicks("AnyUp")
        tab:SetScript("OnClick", function() handlers.openAll() end)
        glance.tabs[i] = tab
    end

    return glance
end

--------------------------------------------------
-- Render (values only; never resizes or re-anchors the HUD)
--------------------------------------------------

function PocketsGlance:Render(glance)
    local InventoryState = Pockets.Services.InventoryState
    local Layout = Pockets.UI.Layout

    -- Main bags only (reagent/specialized bags are excluded upstream).
    local capacity = InventoryState:GetGeneralCapacity()
    glance.bagRow:SetPrimary(PocketsGlance.FormatCapacity(capacity.used, capacity.total))
    if capacity.total > 0 then
        local color = Layout:GetCapacityColor(capacity.utilization)
        glance.bagRow:SetPrimaryColor(color.r, color.g, color.b)
        glance.bagRow:SetFill(capacity.utilization)
    else
        local m = PHUI.Colors.TEXT_MUTED
        glance.bagRow:SetPrimaryColor(m[1], m[2], m[3])
        glance.bagRow:SetFill(0)
    end

    local estimator = Pockets.Services.CapacityEstimator
    local state = estimator:GetState()
    local value, suffix = PocketsGlance.FormatEta(
        state == Constants.ESTIMATOR_STATE.FULL,
        state == Constants.ESTIMATOR_STATE.FILLING,
        estimator:GetConfidence() >= 0.5,
        Layout:FormatCompactETA(estimator:GetETA()))
    glance.header:SetEta(value, suffix)

    glance.goldRow:SetPrimary(Pockets.UI.MoneyFormat:Format(Pockets.Adapters.MoneyAPI:GetMoney()))

    glance.recentStrip:SetItems(Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.RECENT))

    local models = PocketsGlance.BuildTabModels(InventoryState:GetSpecializedCapacities(), function(u)
        return Layout:GetCapacityColor(u)
    end)
    for i, tab in ipairs(glance.tabs) do
        if models[i] then
            tab:SetData(models[i])
        end
    end
    GlanceFrame:LayoutTabs(glance, glance.tabs, #models)
    glance.tabCount = #models
end
