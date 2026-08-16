--[[
    UI/ItemFlyout.lua - Item flyout for one category (TDD §13.4, §14, PRD §3.5)

    Uses pooled item buttons; independently closable from CategoryFlyout so
    click navigation keeps working in combat (TDD §13.4).
]]

local _, Pockets = ...

Pockets.UI.ItemFlyout = Pockets.UI.ItemFlyout or {}
local ItemFlyout = Pockets.UI.ItemFlyout

local Layout = Pockets.UI.Layout

function ItemFlyout:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "PocketsItemFlyout", UIParent, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:Hide()

    self.frame = frame
    return frame
end

function ItemFlyout:Show(anchorRow, categoryID)
    local frame = self:EnsureFrame()

    frame:ClearAllPoints()
    frame:SetPoint("LEFT", anchorRow, "RIGHT", 2, 0)

    Pockets.UI.ItemButtonPool:ReleaseAll(frame)

    local items = Pockets.Services.InventoryState:GetItemsByCategory(categoryID)
    local perRow = 6
    local size = Layout.ITEM_BUTTON_SIZE
    local spacing = Layout.ITEM_BUTTON_SPACING

    for index, item in ipairs(items) do
        local button = Pockets.UI.ItemButtonPool:Acquire(frame)
        local col = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT",
            Layout.PADDING + col * (size + spacing),
            -Layout.PADDING - row * (size + spacing))

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
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        button:Show()
    end

    local rows = math.max(1, math.ceil(#items / perRow))
    frame:SetWidth(Layout.PADDING * 2 + perRow * size + (perRow - 1) * spacing)
    frame:SetHeight(Layout.PADDING * 2 + rows * size + (rows - 1) * spacing)
    frame:Show()
end

function ItemFlyout:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
