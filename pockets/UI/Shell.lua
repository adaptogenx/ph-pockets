--[[
    UI/Shell.lua - Single-frame Glance -> Menu -> Category -> All Items
    navigation shell (.plans/Pockets_Glance_UI.md)

    ONE OBJECT. ONE ROOT FRAME. CONTENT CHANGES IN PLACE.

    Replaces the previous HUD -> hover flyout -> item flyout -> separate
    full-inventory-window model. There is exactly one root frame
    (PocketsShellFrame); navigation moves it between four explicit states
    (Shell.STATE) rather than opening/closing adjacent windows. Only
    GLANCE is allowed unique geometry - MENU/CATEGORY/ALL share identical
    width, header height, body-viewport height, footer height, and screen
    position (§3 "Stable application shell"). Click is the only navigation
    mechanism; hover is reserved for ordinary WoW tooltips/button feedback.

    State transitions never rescan bags or recreate the root frame - every
    Render* function reads already-computed InventoryState/CapacityEstimator
    data (§14 Performance).
]]

local _, Pockets = ...

Pockets.UI.Shell = Pockets.UI.Shell or {}
local Shell = Pockets.UI.Shell

local Layout = Pockets.UI.Layout
local Constants = Pockets.Constants
local L = Constants.LAYOUT
local FlowLayout = Pockets.UI.FlowLayout

Shell.STATE = {
    GLANCE = "GLANCE",
    MENU = "MENU",
    CATEGORY = "CATEGORY",
    ALL = "ALL",
}

-- Escape hierarchy (§4): CATEGORY/ALL -> MENU -> GLANCE -> no-op.
local ESCAPE_PARENT = {
    [Shell.STATE.CATEGORY] = Shell.STATE.MENU,
    [Shell.STATE.ALL] = Shell.STATE.MENU,
    [Shell.STATE.MENU] = Shell.STATE.GLANCE,
}

local SHELL_TOTAL_HEIGHT = L.SHELL_HEADER_HEIGHT + L.SHELL_PADDING
    + L.SHELL_BODY_HEIGHT + L.SHELL_PADDING
    + L.SHELL_FOOTER_HEIGHT + L.SHELL_PADDING

--------------------------------------------------
-- Pure predicates (unit-testable without a live frame)
--------------------------------------------------

-- An Ammo row/stat is shown only when an ammo-specialized bag is actually
-- equipped (ammo.total > 0), never merely because ammo items are being
-- carried in normal bags (TDD §7).
function Shell:ShouldShowAmmoRow(ammoCapacity)
    return (ammoCapacity and ammoCapacity.total or 0) > 0
end

function Shell:GetParentState(state)
    return ESCAPE_PARENT[state]
end

--------------------------------------------------
-- Menu row widget (click-only category navigation - no hover-flyout)
--------------------------------------------------

local function CreateMenuRow(parent, rowWidth)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(L.MENU_ROW_HEIGHT)
    row:SetWidth(rowWidth)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(L.MENU_ROW_ICON_SIZE, L.MENU_ROW_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.label = PHUI.CreateLabel(row, "primary", nil, PHUI.Fonts.SMALL)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -(L.MENU_ROW_COUNT_WIDTH + 14), 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.count = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.SMALL)
    row.count:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    row.count:SetWidth(L.MENU_ROW_COUNT_WIDTH)
    row.count:SetJustifyH("RIGHT")

    row.chevron = PHUI.CreateLabel(row, "muted", "\226\128\186", PHUI.Fonts.SMALL) -- ">"
    row.chevron:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    local hoverColor = PHUI.Colors.HOVER
    row.highlight:SetColorTexture(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 1)
    row.highlight:Hide()
    row:HookScript("OnEnter", function(self) self.highlight:Show() end)
    row:HookScript("OnLeave", function(self) self.highlight:Hide() end)

    return row
end

--------------------------------------------------
-- Frame construction
--------------------------------------------------

function Shell:BuildGlance()
    local frame = self.frame
    local glance = CreateFrame("Frame", nil, frame)
    glance:SetAllPoints(frame)
    frame.glance = glance

    glance.icon = glance:CreateTexture(nil, "ARTWORK")
    glance.icon:SetSize(L.GLANCE_ICON_SIZE, L.GLANCE_ICON_SIZE)
    glance.icon:SetPoint("TOP", glance, "TOP", 0, -L.GLANCE_PADDING)
    glance.icon:SetTexture(Constants.HUD_ICON)
    glance.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    glance.capacityText = PHUI.CreateLabel(glance, "primary", nil, PHUI.Fonts.LARGE)
    glance.capacityText:SetPoint("TOP", glance.icon, "BOTTOM", 0, -L.GLANCE_ROW_GAP)

    glance.etaText = PHUI.CreateLabel(glance, "muted", nil, PHUI.Fonts.SMALL)
    glance.etaText:SetPoint("TOP", glance.capacityText, "BOTTOM", 0, -2)

    glance.ammoText = PHUI.CreateLabel(glance, "primary", nil, PHUI.Fonts.SMALL)
    glance.ammoText:SetPoint("TOP", glance.etaText, "BOTTOM", 0, -L.GLANCE_ROW_GAP)
    glance.ammoText:Hide()
end

function Shell:BuildShell()
    local frame = self.frame
    local shell = CreateFrame("Frame", nil, frame)
    shell:SetAllPoints(frame)
    frame.shell = shell
    shell.menuRows = {}
    shell.categoryLabels = {}

    -- Header: fixed [back][title][right] zones (§3 header contracts) -
    -- the control occupying a zone changes, the zone itself never moves.
    local header = CreateFrame("Frame", nil, shell)
    header:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", shell, "TOPRIGHT", 0, 0)
    header:SetHeight(L.SHELL_HEADER_HEIGHT)
    shell.header = header

    header.backButton = PHUI.CreateIconButton(header, L.SHELL_HEADER_SIDE_WIDTH, nil, {
        tooltipText = "Back",
        onClick = function() Shell:GoBack() end,
    })
    header.backButton:SetPoint("LEFT", header, "LEFT", L.SHELL_PADDING, 0)
    header.backButton.glyph = PHUI.CreateLabel(header.backButton, "primary", "\226\128\185", PHUI.Fonts.SMALL) -- "<"
    header.backButton.glyph:SetPoint("CENTER", 0, 0)

    header.titleText = PHUI.CreateLabel(header, "primary", "Pockets", PHUI.Fonts.NORMAL)
    header.titleText:SetJustifyH("LEFT")
    header.titleText:SetWordWrap(false)

    header.plusButton = PHUI.CreateIconButton(header, 20, nil, {
        tooltipText = "All Items",
        onClick = function() Shell:SetState(Shell.STATE.ALL) end,
    })
    header.plusButton:SetPoint("RIGHT", header, "RIGHT", -L.SHELL_PADDING, 0)
    header.plusButton.glyph = PHUI.CreateLabel(header.plusButton, "primary", "+", PHUI.Fonts.SMALL)
    header.plusButton.glyph:SetPoint("CENTER", 0, 0)

    header.searchBox = CreateFrame("EditBox", nil, header, "InputBoxTemplate")
    header.searchBox:SetHeight(18)
    header.searchBox:SetWidth(L.SHELL_HEADER_RIGHT_WIDTH - 6)
    header.searchBox:SetPoint("RIGHT", header, "RIGHT", -L.SHELL_PADDING, 0)
    header.searchBox:SetAutoFocus(false)
    header.searchBox:SetScript("OnTextChanged", function(box)
        Shell:RenderAll(box:GetText())
    end)
    header.searchBox:Hide()

    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.divider:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header.divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    header.divider:SetHeight(1)
    local dividerColor = PHUI.Colors.DIVIDER
    header.divider:SetColorTexture(dividerColor[1], dividerColor[2], dividerColor[3], dividerColor[4] or 1)

    -- Body: one scrolling viewport reused by Menu/Category/All (§3
    -- "consistent body viewport").
    shell.scrollFrame = CreateFrame("ScrollFrame", nil, shell, "UIPanelScrollFrameTemplate")
    shell.scrollFrame:SetPoint("TOPLEFT", shell, "TOPLEFT", L.SHELL_PADDING, -(L.SHELL_HEADER_HEIGHT + L.SHELL_PADDING))
    shell.scrollFrame:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT",
        -(L.SHELL_PADDING + 20), L.SHELL_FOOTER_HEIGHT + L.SHELL_PADDING)

    shell.content = CreateFrame("Frame", nil, shell.scrollFrame)
    shell.content:SetWidth(L.SHELL_WIDTH - L.SHELL_PADDING * 2 - 20)
    shell.content:SetHeight(1)
    shell.scrollFrame:SetScrollChild(shell.content)

    -- Footer: same Bags/ETA/Ammo semantics as before, one compact row.
    shell.footer = CreateFrame("Frame", nil, shell)
    shell.footer:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", L.SHELL_PADDING, L.SHELL_PADDING)
    shell.footer:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -L.SHELL_PADDING, L.SHELL_PADDING)
    shell.footer:SetHeight(L.SHELL_FOOTER_HEIGHT)

    shell.footerBagsText = PHUI.CreateLabel(shell.footer, "primary", nil, PHUI.Fonts.SMALL)
    shell.footerBagsText:SetPoint("LEFT", shell.footer, "LEFT", 0, 0)

    shell.footerEtaText = PHUI.CreateLabel(shell.footer, "muted", nil, PHUI.Fonts.SMALL)
    shell.footerEtaText:SetPoint("LEFT", shell.footerBagsText, "RIGHT", 4, 0)

    shell.footerAmmoText = PHUI.CreateLabel(shell.footer, "primary", nil, PHUI.Fonts.SMALL)
    shell.footerAmmoText:SetPoint("RIGHT", shell.footer, "RIGHT", 0, 0)
    shell.footerAmmoText:Hide()
end

function Shell:Initialize()
    if self.frame then
        return
    end

    local frame = CreateFrame("Button", "PocketsShellFrame", UIParent, "BackdropTemplate")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    PHUI.ApplyBackdrop(frame)

    frame:SetScript("OnDragStart", function(self)
        if not Pockets.SavedSettings.hud.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Shell:SavePosition()
    end)

    -- Click is the only navigation mechanism (§1). Clicking Glance opens
    -- Menu; clicks inside Menu/Category/All are handled by their own
    -- child buttons/rows and never reach this handler.
    frame:SetScript("OnClick", function()
        if Shell.state == Shell.STATE.GLANCE then
            Shell:SetState(Shell.STATE.MENU)
        end
    end)

    -- Escape hierarchy (§4). Keyboard capture is only enabled outside
    -- GLANCE (see SetState) so Escape never fights other UI while
    -- collapsed, and any other key just propagates through untouched.
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            Shell:HandleEscape()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    self.frame = frame
    self:BuildGlance()
    self:BuildShell()
    self:RestorePosition()

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.ETA_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.INVENTORY_CHANGED, function() self:OnDataChanged() end, self)

    self.state = self.STATE.GLANCE
    self.context = {}
    self:Render()
end

function Shell:RestorePosition()
    local hud = Pockets.SavedSettings.hud
    self.frame:ClearAllPoints()
    self.frame:SetPoint(hud.point, UIParent, hud.relativePoint, hud.x, hud.y)
end

function Shell:SavePosition()
    local hud = Pockets.SavedSettings.hud
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    hud.point = point
    hud.relativePoint = relativePoint
    hud.x = x
    hud.y = y
end

--------------------------------------------------
-- State machine (§4)
--------------------------------------------------

function Shell:GetState()
    return self.state
end

-- Cheap: never rescans bags, never recreates the root frame - every
-- Render* function below only reads already-computed domain state (§14).
function Shell:SetState(state, context)
    self.state = state
    self.context = context or {}
    self:Render()
end

function Shell:GoBack()
    local parent = self:GetParentState(self.state)
    if parent then
        self:SetState(parent)
    end
end

function Shell:HandleEscape()
    self:GoBack()
end

function Shell:OnDataChanged()
    if self.frame then
        self:Render()
    end
end

function Shell:Render()
    local frame = self.frame
    local state = self.state

    if state == self.STATE.GLANCE then
        frame.shell:Hide()
        frame.glance:Show()
        frame:EnableKeyboard(false)
        self:RenderGlance()
        return
    end

    frame.glance:Hide()
    frame.shell:Show()
    frame:EnableKeyboard(true)
    frame:SetSize(L.SHELL_WIDTH, SHELL_TOTAL_HEIGHT)

    self:RenderHeader()
    self:RenderFooter()

    if state == self.STATE.MENU then
        self:RenderMenu()
    elseif state == self.STATE.CATEGORY then
        self:RenderCategory(self.context.categoryID)
    elseif state == self.STATE.ALL then
        self:RenderAll(frame.shell.header.searchBox:GetText())
    end
end

--------------------------------------------------
-- GLANCE
--------------------------------------------------

function Shell:RenderGlance()
    local glance = self.frame.glance

    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)
    glance.capacityText:SetText(string.format("%d / %d", capacity.used, capacity.total))
    glance.capacityText:SetTextColor(color.r, color.g, color.b)

    local estimator = Pockets.Services.CapacityEstimator
    local estimatorState = estimator:GetState()
    local confidenceOK = estimator:GetConfidence() >= 0.5
    if estimatorState == Constants.ESTIMATOR_STATE.FULL then
        glance.etaText:SetText("Full")
    elseif estimatorState == Constants.ESTIMATOR_STATE.FILLING and confidenceOK then
        -- Prefer omission to a noisy/fabricated number (§2, §9).
        glance.etaText:SetText(Layout:FormatETA(estimator:GetETA()) or "")
    else
        glance.etaText:SetText("")
    end

    local ammoCapacity = Pockets.Services.InventoryState:GetAmmoCapacity()
    local showAmmo = self:ShouldShowAmmoRow(ammoCapacity)
    if showAmmo then
        glance.ammoText:SetText(string.format("%d / %d", ammoCapacity.used, ammoCapacity.total))
        glance.ammoText:Show()
    else
        glance.ammoText:Hide()
    end

    local height = L.GLANCE_PADDING * 2
        + L.GLANCE_ICON_SIZE + L.GLANCE_ROW_GAP
        + L.GLANCE_CAPACITY_ROW_HEIGHT
        + L.GLANCE_ETA_ROW_HEIGHT
        + (showAmmo and (L.GLANCE_ROW_GAP + L.GLANCE_AMMO_ROW_HEIGHT) or 0)
    self.frame:SetSize(L.GLANCE_WIDTH, height)
end

--------------------------------------------------
-- Header (§3 header contracts)
--------------------------------------------------

function Shell:RenderHeader()
    local header = self.frame.shell.header
    local state = self.state

    header.titleText:ClearAllPoints()
    header.titleText:SetPoint("RIGHT", header, "RIGHT", -(L.SHELL_HEADER_RIGHT_WIDTH + L.SHELL_PADDING), 0)

    if state == self.STATE.MENU then
        header.backButton:Hide()
        header.titleText:SetPoint("LEFT", header, "LEFT", L.SHELL_PADDING, 0)
        header.titleText:SetText("Pockets")
        header.plusButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.CATEGORY then
        header.backButton:Show()
        header.titleText:SetPoint("LEFT", header.backButton, "RIGHT", 4, 0)
        header.titleText:SetText(Constants.CATEGORY_LABEL[self.context.categoryID] or "")
        header.plusButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.ALL then
        header.backButton:Show()
        header.titleText:SetPoint("LEFT", header.backButton, "RIGHT", 4, 0)
        header.titleText:SetText("All")
        header.plusButton:Hide() -- already in All Items - its slot becomes Search (§3)
        header.searchBox:Show()
    end
end

--------------------------------------------------
-- MENU (§3 STATE 2)
--------------------------------------------------

function Shell:RenderMenu()
    local shell = self.frame.shell
    local content = shell.content
    for _, row in ipairs(shell.menuRows) do
        row:Hide()
    end

    local rowWidth = content:GetWidth()
    local summary = Pockets.API.GetCategorySummary()
    local y = 0
    for index, entry in ipairs(summary) do
        local row = shell.menuRows[index]
        if not row then
            row = CreateMenuRow(content, rowWidth)
            shell.menuRows[index] = row
        end

        row.categoryID = entry.categoryID
        row.icon:SetTexture(entry.icon)
        row.label:SetText(entry.label)
        row.count:SetText(tostring(entry.count))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetScript("OnClick", function()
            Shell:SetState(Shell.STATE.CATEGORY, { categoryID = entry.categoryID })
        end)
        row:Show()

        y = y + L.MENU_ROW_HEIGHT
    end

    content:SetHeight(math.max(y, 1))
end

--------------------------------------------------
-- CATEGORY (§3 STATE 3) - straightforward responsive item grid, same
-- pooled real item-button component as All Items.
--------------------------------------------------

function Shell:RenderCategory(categoryID)
    local shell = self.frame.shell
    local content = shell.content
    local pool = Pockets.UI.ItemButtonPool
    pool:ReleaseAll(content)
    for _, widget in ipairs(shell.categoryLabels) do
        widget:Hide()
    end

    local items = Pockets.API.GetAggregatedCategoryItems(categoryID)
    local rowWidth = content:GetWidth()
    local plan = FlowLayout:PlanFlat(#items, {
        rowWidth = rowWidth,
        itemSize = L.ITEM_BUTTON_SIZE,
        gap = L.ITEM_BUTTON_GAP,
    })

    for _, placement in ipairs(plan.itemPlacements) do
        local button = pool:Acquire(content)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", content, "TOPLEFT", placement.x, -placement.y)
        pool:Configure(button, items[placement.index])
        button:Show()
    end

    content:SetHeight(math.max(plan.contentHeight, 1))
end

--------------------------------------------------
-- ALL ITEMS (§3 STATE 4) - categorized dynamic flow + search, ported
-- from the previous FullInventory window onto Shell's shared body.
--------------------------------------------------

local function EnsureCategoryLabel(content, labels, index)
    local widget = labels[index]
    if widget then
        return widget
    end

    widget = CreateFrame("Frame", nil, content)
    widget:SetHeight(L.FULL_INVENTORY_LABEL_HEIGHT)

    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetSize(L.FULL_INVENTORY_LABEL_ICON_SIZE, L.FULL_INVENTORY_LABEL_ICON_SIZE)
    widget.icon:SetPoint("LEFT", widget, "LEFT", 0, 0)

    widget.text = PHUI.CreateLabel(widget, "muted", nil, PHUI.Fonts.SMALL)
    widget.text:SetPoint("LEFT", widget.icon, "RIGHT", L.FULL_INVENTORY_LABEL_ICON_GAP, 0)

    function widget:Measure()
        return L.FULL_INVENTORY_LABEL_ICON_SIZE + L.FULL_INVENTORY_LABEL_ICON_GAP + (self.text:GetStringWidth() or 0)
    end

    labels[index] = widget
    return widget
end

local function BuildCategorySections()
    local sections = {}
    for _, categoryID in ipairs(Constants.CATEGORY_ORDER) do
        local items = Pockets.API.GetAggregatedCategoryItems(categoryID)
        if #items > 0 then
            table.insert(sections, {
                categoryID = categoryID,
                label = Constants.CATEGORY_LABEL[categoryID],
                icon = Constants.CATEGORY_ICON[categoryID],
                buttonRecords = items,
            })
        end
    end
    return sections
end

-- Flat, name-matching aggregate list across every category (no
-- per-category grouping) - the "temporarily flatten" search mode (§11).
local function BuildFlatSearchResults(query)
    local Search = Pockets.UI.Search
    local out = {}
    local seen = {}
    for _, categoryID in ipairs(Constants.CATEGORY_ORDER) do
        for _, item in ipairs(Pockets.API.GetAggregatedCategoryItems(categoryID)) do
            if Search:Matches(item, query) and not seen[item.itemID] then
                seen[item.itemID] = true
                table.insert(out, item)
            end
        end
    end
    return out
end

function Shell:RenderAll(query)
    local shell = self.frame.shell
    local content = shell.content
    local pool = Pockets.UI.ItemButtonPool
    pool:ReleaseAll(content)
    for _, widget in ipairs(shell.categoryLabels) do
        widget:Hide()
    end

    local rowWidth = content:GetWidth()
    local itemSize = L.ITEM_BUTTON_SIZE
    local gap = L.ITEM_BUTTON_GAP
    local hasQuery = query ~= nil and query ~= ""

    if hasQuery then
        local items = BuildFlatSearchResults(query)
        local plan = FlowLayout:PlanFlat(#items, { rowWidth = rowWidth, itemSize = itemSize, gap = gap })
        for _, placement in ipairs(plan.itemPlacements) do
            local button = pool:Acquire(content)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", content, "TOPLEFT", placement.x, -placement.y)
            pool:Configure(button, items[placement.index])
            button:Show()
        end
        content:SetHeight(math.max(plan.contentHeight, 1))
        return
    end

    local sections = BuildCategorySections()

    local labelIndex = 0
    local planCategories = {}
    local labelWidgetByCategoryID = {}
    for _, section in ipairs(sections) do
        labelIndex = labelIndex + 1
        local widget = EnsureCategoryLabel(content, shell.categoryLabels, labelIndex)
        widget.icon:SetTexture(section.icon)
        widget.text:SetText(string.format("%s (%d)", section.label, #section.buttonRecords))
        labelWidgetByCategoryID[section.categoryID] = widget

        table.insert(planCategories, {
            categoryID = section.categoryID,
            labelWidth = widget:Measure(),
            itemCount = #section.buttonRecords,
        })
    end

    local plan = FlowLayout:Plan(planCategories, {
        rowWidth = rowWidth,
        itemSize = itemSize,
        gap = gap,
        labelHeight = L.FULL_INVENTORY_LABEL_HEIGHT,
    })

    local buttonRecordsByCategoryID = {}
    for _, section in ipairs(sections) do
        buttonRecordsByCategoryID[section.categoryID] = section.buttonRecords
    end

    for _, categoryPlacement in ipairs(plan.categoryPlacements) do
        local widget = labelWidgetByCategoryID[categoryPlacement.categoryID]
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", content, "TOPLEFT", categoryPlacement.labelX, -categoryPlacement.labelY)
        widget:SetWidth(categoryPlacement.labelWidth)
        widget:Show()

        local buttonRecords = buttonRecordsByCategoryID[categoryPlacement.categoryID]
        for _, itemPlacement in ipairs(categoryPlacement.itemPlacements) do
            local button = pool:Acquire(content)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", content, "TOPLEFT", itemPlacement.x, -itemPlacement.y)
            pool:Configure(button, buttonRecords[itemPlacement.index])
            button:Show()
        end
    end

    content:SetHeight(math.max(plan.contentHeight, 1))
end

--------------------------------------------------
-- Footer (shared by MENU/CATEGORY/ALL)
--------------------------------------------------

function Shell:RenderFooter()
    local shell = self.frame.shell
    local InventoryState = Pockets.Services.InventoryState

    local capacity = InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)
    shell.footerBagsText:SetText(string.format("%d/%d", capacity.used, capacity.total))
    shell.footerBagsText:SetTextColor(color.r, color.g, color.b)

    local estimator = Pockets.Services.CapacityEstimator
    local estimatorState = estimator:GetState()
    local confidenceOK = estimator:GetConfidence() >= 0.5
    if estimatorState == Constants.ESTIMATOR_STATE.FULL then
        shell.footerEtaText:SetText(" \194\183 Full")
    elseif estimatorState == Constants.ESTIMATOR_STATE.FILLING and confidenceOK then
        shell.footerEtaText:SetText(Layout:FormatETASuffix(estimator:GetETA()))
    else
        shell.footerEtaText:SetText("")
    end

    local ammoCapacity = InventoryState:GetAmmoCapacity()
    if self:ShouldShowAmmoRow(ammoCapacity) then
        shell.footerAmmoText:SetText(string.format("%d/%d", ammoCapacity.used, ammoCapacity.total))
        shell.footerAmmoText:Show()
    else
        shell.footerAmmoText:Hide()
    end
end

--------------------------------------------------
-- Visibility (independent of state - /pockets show)
--------------------------------------------------

function Shell:Show()
    if self.frame then
        self.frame:Show()
    end
end

function Shell:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function Shell:Toggle()
    if not self.frame then
        return
    end
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Shift-B / the old "expand" action jump directly to All Items (§4),
-- toggling back to Menu if All Items is already open.
function Shell:ToggleAllItems()
    if self.state == self.STATE.ALL then
        self:SetState(self.STATE.MENU)
    else
        self:SetState(self.STATE.ALL)
    end
end
