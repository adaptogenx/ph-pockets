--[[
    UI/FullInventory.lua - Compact full-inventory escape hatch (TDD §13.5, PRD §3.6)

    Grouped by Pockets categories, not physical bag layout. One frame with
    category sections and pooled item buttons - never one panel per bag.
    Bound to Shift-B by default via Adapters/BindingsAPI + Bindings.xml.
]]

local _, Pockets = ...

Pockets.UI.FullInventory = Pockets.UI.FullInventory or {}
local FullInventory = Pockets.UI.FullInventory

local Layout = Pockets.UI.Layout

function FullInventory:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "PocketsFullInventoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(Layout.MAX_FULL_INVENTORY_WIDTH, Layout.MAX_FULL_INVENTORY_HEIGHT)
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
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()
    table.insert(UISpecialFrames, "PocketsFullInventoryFrame")

    frame.searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.searchBox:SetSize(Layout.MAX_FULL_INVENTORY_WIDTH - 40, 20)
    frame.searchBox:SetPoint("TOP", frame, "TOP", 0, -Layout.PADDING)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetScript("OnTextChanged", function(box)
        self:Render(box:GetText())
    end)

    frame.sectionLabels = {}
    self.frame = frame
    return frame
end

function FullInventory:Render(query)
    local frame = self:EnsureFrame()
    Pockets.UI.ItemButtonPool:ReleaseAll(frame)

    for _, label in ipairs(frame.sectionLabels) do
        label:Hide()
    end

    local filtered = Pockets.UI.Search:Filter(query)
    local byCategory = {}
    for _, item in pairs(filtered) do
        byCategory[item.categoryID] = byCategory[item.categoryID] or {}
        table.insert(byCategory[item.categoryID], item)
    end

    local y = -40
    local size = Layout.ITEM_BUTTON_SIZE
    local spacing = Layout.ITEM_BUTTON_SPACING
    local perRow = 8
    local sectionIndex = 0

    for _, categoryID in ipairs(Pockets.Constants.CATEGORY_ORDER) do
        local items = byCategory[categoryID]
        if items and #items > 0 then
            sectionIndex = sectionIndex + 1
            local label = frame.sectionLabels[sectionIndex]
            if not label then
                label = frame:CreateFontString(nil, "OVERLAY", Layout.FONT)
                frame.sectionLabels[sectionIndex] = label
            end
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", frame, "TOPLEFT", Layout.PADDING, y)
            label:SetText(string.format("%s (%d)", Pockets.Constants.CATEGORY_LABEL[categoryID], #items))
            label:Show()
            y = y - Layout.ROW_HEIGHT

            for index, item in ipairs(items) do
                local button = Pockets.UI.ItemButtonPool:Acquire(frame)
                local col = (index - 1) % perRow
                local row = math.floor((index - 1) / perRow)

                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", frame, "TOPLEFT",
                    Layout.PADDING + col * (size + spacing),
                    y - row * (size + spacing))

                if button.icon then
                    button.icon:SetTexture(item.texture)
                end
                if button.Count then
                    button.Count:SetText(item.quantity > 1 and tostring(item.quantity) or "")
                end
                button.itemLink = item.itemLink
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if self.itemLink then
                        GameTooltip:SetHyperlink(self.itemLink)
                    end
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
                button:Show()
            end

            local rows = math.ceil(#items / perRow)
            y = y - rows * (size + spacing) - Layout.PADDING
        end
    end
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
