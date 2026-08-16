--[[
    UI/CategoryFlyout.lua - Category summary flyout (TDD §13.3, §14, PRD §3.5)

    Shown by hovering/clicking the HUD outside combat, or clicking it during
    combat. Renders only non-empty categories, using pooled rows.
]]

local _, Pockets = ...

Pockets.UI.CategoryFlyout = Pockets.UI.CategoryFlyout or {}
local CategoryFlyout = Pockets.UI.CategoryFlyout

local Layout = Pockets.UI.Layout
local HIDE_DELAY_SECONDS = 0.25

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Layout.ROW_HEIGHT)

    row.label = row:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    row.label:SetPoint("LEFT", row, "LEFT", Layout.PADDING, 0)

    row.count = row:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    row.count:SetPoint("RIGHT", row, "RIGHT", -Layout.PADDING, 0)

    return row
end

function CategoryFlyout:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "PocketsCategoryFlyout", UIParent, "BackdropTemplate")
    frame:SetWidth(Layout.MAX_FLYOUT_WIDTH)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function() self:CancelHide() end)
    frame:SetScript("OnLeave", function() self:ScheduleHide() end)
    frame:Hide()

    self.frame = frame
    self.rows = {}
    return frame
end

function CategoryFlyout:Show(anchorFrame)
    local frame = self:EnsureFrame()
    self:CancelHide()

    frame:ClearAllPoints()
    frame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)

    local summary = Pockets.API.GetCategorySummary()

    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    local y = -Layout.PADDING
    local rowIndex = 0
    for _, entry in ipairs(summary) do
        if entry.count > 0 then
            rowIndex = rowIndex + 1
            local row = self.rows[rowIndex]
            if not row then
                row = CreateRow(frame)
                self.rows[rowIndex] = row
            end

            row.categoryID = entry.categoryID
            row.label:SetText(entry.label)
            row.count:SetText(tostring(entry.count))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
            row:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
            row:SetScript("OnEnter", function()
                self:CancelHide()
                if Pockets.Adapters.CombatAPI:CanHoverExpand() then
                    Pockets.UI.ItemFlyout:Show(row, entry.categoryID)
                end
            end)
            row:SetScript("OnClick", function()
                Pockets.UI.ItemFlyout:Show(row, entry.categoryID)
            end)
            row:Show()

            y = y - Layout.ROW_HEIGHT - Layout.ROW_SPACING
        end
    end

    frame:SetHeight(math.max(-y + Layout.PADDING, Layout.ROW_HEIGHT))
    frame:Show()
end

function CategoryFlyout:Hide()
    if self.frame then
        self.frame:Hide()
    end
    Pockets.UI.ItemFlyout:Hide()
end

function CategoryFlyout:CancelHide()
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
end

function CategoryFlyout:ScheduleHide()
    self:CancelHide()
    self.hideTimer = C_Timer.NewTimer(HIDE_DELAY_SECONDS, function()
        self:Hide()
    end)
end
