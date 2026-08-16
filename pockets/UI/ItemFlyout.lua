--[[
    UI/ItemFlyout.lua - Item panel for one category (TDD §13.4, §14, PRD §3.5;
    UI_SPEC §7, §8, §13)

    Fixed 4-column/40px/4px-gap grid (UI_SPEC §7) - panel width derives from
    that geometry, never from item names/count. Buttons are real,
    interactive item buttons bound to a live bag+slot via
    ItemButtonPool:Configure (UI_SPEC §8). Independently closable from
    CategoryFlyout so click navigation keeps working in combat (TDD §13.4).
]]

local _, Pockets = ...

Pockets.UI.ItemFlyout = Pockets.UI.ItemFlyout or {}
local ItemFlyout = Pockets.UI.ItemFlyout

local L = Pockets.Constants.LAYOUT

local function PanelWidth()
    return L.ITEM_PANEL_PADDING * 2 + L.ITEM_PANEL_COLUMNS * L.ITEM_BUTTON_SIZE
        + (L.ITEM_PANEL_COLUMNS - 1) * L.ITEM_BUTTON_GAP
end

function ItemFlyout:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "PocketsItemFlyout", UIParent, "BackdropTemplate")
    frame:SetWidth(PanelWidth()) -- fixed; grid geometry never changes
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    frame:SetBackdropBorderColor(0.35, 0.30, 0.20, 1)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function() Pockets.UI.HoverGroup:Enter() end)
    frame:SetScript("OnLeave", function()
        Pockets.UI.HoverGroup:Leave(function() ItemFlyout:Hide() end)
    end)
    frame:Hide()

    self.frame = frame

    -- Stale-location safety (UI_SPEC §8): if inventory changes while a
    -- panel is open, re-render so buttons never act on an old bag/slot.
    Pockets.Services.EventBus:Subscribe(Pockets.Constants.DOMAIN_EVENT.INVENTORY_CHANGED, function()
        if self.frame:IsShown() and self.currentCategoryID then
            self:Render(self.currentCategoryID)
        end
    end, self)

    return frame
end

function ItemFlyout:Render(categoryID)
    local frame = self.frame
    self.currentCategoryID = categoryID

    Pockets.UI.ItemButtonPool:ReleaseAll(frame)

    local items = Pockets.API.GetCategoryItems(categoryID)
    local columns = L.ITEM_PANEL_COLUMNS
    local size = L.ITEM_BUTTON_SIZE
    local gap = L.ITEM_BUTTON_GAP
    local pad = L.ITEM_PANEL_PADDING
    local maxVisibleRows = L.ITEM_PANEL_MAX_ROWS

    local visibleCount = math.min(#items, columns * maxVisibleRows)
    for index = 1, visibleCount do
        local item = items[index]
        local button = Pockets.UI.ItemButtonPool:Acquire(frame)
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT",
            pad + col * (size + gap),
            -pad - row * (size + gap))

        Pockets.UI.ItemButtonPool:Configure(button, item)
        button:Show()
    end

    local rows = math.max(1, math.ceil(visibleCount / columns))
    frame:SetHeight(pad * 2 + rows * size + (rows - 1) * gap)
end

function ItemFlyout:Show(anchorRow, categoryID)
    local frame = self:EnsureFrame()
    Pockets.UI.HoverGroup:Enter()

    self:Render(categoryID)

    frame:ClearAllPoints()
    local width = frame:GetWidth()
    local rightEdgeX = (anchorRow:GetRight() or 0) + width
    if rightEdgeX > UIParent:GetWidth() then
        -- Not enough room to the right; flip left (UI_SPEC §7, §13).
        frame:SetPoint("TOPRIGHT", anchorRow, "TOPLEFT", -2, 0)
    else
        frame:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 2, 0)
    end

    frame:Show()
end

function ItemFlyout:Hide()
    if self.frame then
        self.frame:Hide()
    end
    self.currentCategoryID = nil
end
