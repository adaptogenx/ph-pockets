--[[
    UI/FullInventory.lua - Compact full-inventory escape hatch (TDD §13.5,
    PRD §3.6; UI_SPEC §10)

    Grouped by Pockets categories, not physical bag layout. Fixed/bounded
    width; internal scrolling instead of growing off-screen. Uses the same
    real item-button component (ItemButtonPool:Configure) as the item
    flyout - UI_SPEC §10 "share item rendering/pooling code". Bound to
    Shift-B by default via Adapters/BindingsAPI + Bindings.xml.
]]

local _, Pockets = ...

Pockets.UI.FullInventory = Pockets.UI.FullInventory or {}
local FullInventory = Pockets.UI.FullInventory

local Layout = Pockets.UI.Layout
local L = Pockets.Constants.LAYOUT

local WIDTH = L.FULL_INVENTORY_WIDTH
local HEIGHT = L.FULL_INVENTORY_HEIGHT

function FullInventory:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "PocketsFullInventoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, HEIGHT) -- fixed/bounded (UI_SPEC §10)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.35, 0.30, 0.20, 1)
    frame:Hide()
    table.insert(UISpecialFrames, "PocketsFullInventoryFrame")

    frame.searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.searchBox:SetSize(WIDTH - 40, 20)
    frame.searchBox:SetPoint("TOP", frame, "TOP", 0, -Layout.PADDING)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetScript("OnTextChanged", function(box)
        self:Render(box:GetText())
    end)

    -- Internal scrolling (UI_SPEC §10) rather than growing off-screen.
    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scrollFrame:SetPoint("TOPLEFT", frame.searchBox, "BOTTOMLEFT", -4, -8)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, Layout.PADDING)

    frame.content = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.content:SetWidth(WIDTH - 40)
    frame.content:SetHeight(1)
    frame.scrollFrame:SetScrollChild(frame.content)

    frame.sectionLabels = {}
    self.frame = frame

    Pockets.Services.EventBus:Subscribe(Pockets.Constants.DOMAIN_EVENT.INVENTORY_CHANGED, function()
        if self.frame:IsShown() then
            self:Render(self.frame.searchBox:GetText())
        end
    end, self)

    return frame
end

local function RenderCategorySection(content, pool, sectionLabels, sectionIndex, categoryID, items, y)
    local label = sectionLabels[sectionIndex]
    if not label then
        label = content:CreateFontString(nil, "OVERLAY", Layout.FONT)
        sectionLabels[sectionIndex] = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", content, "TOPLEFT", Layout.PADDING, y)
    label:SetText(string.format("%s (%d)", Pockets.Constants.CATEGORY_LABEL[categoryID], #items))
    label:Show()
    y = y - L.FLYOUT_ROW_HEIGHT

    local columns = L.ITEM_PANEL_COLUMNS
    local size = L.ITEM_BUTTON_SIZE
    local gap = L.ITEM_BUTTON_GAP

    for index, item in ipairs(items) do
        local button = pool:Acquire(content)
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", content, "TOPLEFT",
            Layout.PADDING + col * (size + gap),
            y - row * (size + gap))

        pool:Configure(button, item)
        button:Show()
    end

    local rows = math.ceil(#items / columns)
    return y - rows * (size + gap) - Layout.PADDING
end

function FullInventory:Render(query)
    local frame = self:EnsureFrame()
    local pool = Pockets.UI.ItemButtonPool
    pool:ReleaseAll(frame.content)

    for _, label in ipairs(frame.sectionLabels) do
        label:Hide()
    end

    local y = -4
    local sectionIndex = 0

    -- Recent first (PRD §3.6), unaffected by search.
    local recentItems = Pockets.API.GetCategoryItems(Pockets.Constants.CATEGORY.RECENT)
    if #recentItems > 0 then
        sectionIndex = sectionIndex + 1
        y = RenderCategorySection(frame.content, pool, frame.sectionLabels, sectionIndex,
            Pockets.Constants.CATEGORY.RECENT, recentItems, y)
    end

    local filtered = Pockets.UI.Search:Filter(query)
    local byCategory = {}
    for _, item in pairs(filtered) do
        byCategory[item.categoryID] = byCategory[item.categoryID] or {}
        table.insert(byCategory[item.categoryID], item)
    end

    for _, categoryID in ipairs(Pockets.Constants.CATEGORY_ORDER) do
        if categoryID ~= Pockets.Constants.CATEGORY.RECENT then
            local items = byCategory[categoryID]
            if items and #items > 0 then
                sectionIndex = sectionIndex + 1
                y = RenderCategorySection(frame.content, pool, frame.sectionLabels, sectionIndex,
                    categoryID, items, y)
            end
        end
    end

    frame.content:SetHeight(math.max(-y, 1))
end

function FullInventory:Show()
    local frame = self:EnsureFrame()
    self:Render(frame.searchBox:GetText())
    frame:Show()
end

function FullInventory:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function FullInventory:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
