--[[
    UI/Layout.lua - Shared spacing/font/color constants for Pockets UI (TDD §13.5, UI_RULES.md)

    No UI module should hard-code its own spacing or font values; pull them
    from here so category/item presentation stays visually consistent.
]]

local _, Pockets = ...

Pockets.UI.Layout = Pockets.UI.Layout or {}
local Layout = Pockets.UI.Layout

Layout.PADDING = 8
Layout.ROW_HEIGHT = 18
Layout.ROW_SPACING = 2
Layout.ITEM_BUTTON_SIZE = 28
Layout.ITEM_BUTTON_SPACING = 4
Layout.MAX_FLYOUT_WIDTH = 220
Layout.MAX_FULL_INVENTORY_WIDTH = 340
Layout.MAX_FULL_INVENTORY_HEIGHT = 480

Layout.FONT = "GameFontNormal"
Layout.FONT_SMALL = "GameFontNormalSmall"

function Layout:GetCapacityColor(utilization)
    local thresholds = Pockets.Constants.CAPACITY_COLOR_THRESHOLDS
    local colors = Pockets.Constants.CAPACITY_COLOR

    if utilization >= thresholds.RED_AT then
        return colors.RED
    elseif utilization >= thresholds.YELLOW_AT then
        return colors.YELLOW
    end
    return colors.GREEN
end
