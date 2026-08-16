--[[
    UI/CategoryFlyout.lua - Category summary flyout (TDD §13.3, §14, PRD §3.5;
    UI_SPEC §4, §5, §13)

    Fixed 220px width (UI_SPEC §4) - only height varies with visible
    category count. Rows read precomputed InventoryState/RecentItems data
    only; no bag scan or categorization happens on hover (UI_SPEC §6).
    Open is immediate; close goes through the shared HoverGroup grace timer
    (UI_SPEC §5) so crossing into the item panel doesn't flicker-close.
]]

local _, Pockets = ...

Pockets.UI.CategoryFlyout = Pockets.UI.CategoryFlyout or {}
local CategoryFlyout = Pockets.UI.CategoryFlyout

local Layout = Pockets.UI.Layout
local L = Pockets.Constants.LAYOUT

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(L.FLYOUT_ROW_HEIGHT)
    row:SetWidth(L.FLYOUT_WIDTH)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(L.FLYOUT_ICON_SIZE, L.FLYOUT_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", L.FLYOUT_PADDING, 0)

    row.label = row:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    -- Fixed-width label region ending before the count column - labels
    -- truncate instead of pushing the count out of alignment (UI_SPEC §4).
    row.label:SetPoint("RIGHT", row, "RIGHT", -(L.FLYOUT_COUNT_WIDTH + 16), 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    row.count = row:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    row.count:SetPoint("RIGHT", row, "RIGHT", -(L.FLYOUT_PADDING + 12), 0)
    row.count:SetWidth(L.FLYOUT_COUNT_WIDTH)
    row.count:SetJustifyH("RIGHT")

    row.chevron = row:CreateFontString(nil, "OVERLAY", Layout.FONT_SMALL)
    row.chevron:SetPoint("RIGHT", row, "RIGHT", -L.FLYOUT_PADDING, 0)
    row.chevron:SetText(">")

    return row
end

function CategoryFlyout:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "PocketsCategoryFlyout", UIParent, "BackdropTemplate")
    frame:SetWidth(L.FLYOUT_WIDTH) -- fixed; never SetWidth again after this
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
        Pockets.UI.HoverGroup:Leave(function() CategoryFlyout:Hide() end)
    end)
    frame:Hide()

    self.frame = frame
    self.rows = {}
    return frame
end

function CategoryFlyout:Show(anchorFrame)
    local frame = self:EnsureFrame()
    Pockets.UI.HoverGroup:Enter()

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)

    -- Reads precomputed category/recent summaries only - no bag scan or
    -- categorization runs here (UI_SPEC §6).
    local summary = Pockets.API.GetCategorySummary()

    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    local y = -L.FLYOUT_PADDING
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
            row.icon:SetTexture(entry.icon)
            row.label:SetText(entry.label)
            row.count:SetText(entry.count >= 1000
                and (tostring(entry.count):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
                or tostring(entry.count))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
            row:SetScript("OnEnter", function()
                Pockets.UI.HoverGroup:Enter()
                if Pockets.Adapters.CombatAPI:CanHoverExpand() then
                    Pockets.UI.ItemFlyout:Show(row, entry.categoryID)
                end
            end)
            row:SetScript("OnClick", function()
                Pockets.UI.ItemFlyout:Show(row, entry.categoryID)
            end)
            row:Show()

            y = y - L.FLYOUT_ROW_HEIGHT
        end
    end

    frame:SetHeight(math.max(-y + L.FLYOUT_PADDING, L.FLYOUT_ROW_HEIGHT))
    frame:Show()
end

function CategoryFlyout:Hide()
    if self.frame then
        self.frame:Hide()
    end
    Pockets.UI.ItemFlyout:Hide()
end
