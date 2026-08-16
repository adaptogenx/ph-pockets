--[[
    UI/Layout.lua - Shared font/color constants for Pockets UI (TDD §13.5, UI_RULES.md)

    Fixed pixel geometry (widths/heights/columns) lives in
    Constants.LAYOUT so it has exactly one source of truth across HUD,
    CategoryFlyout, ItemFlyout, and FullInventory (UI_SPEC §4, §7, §16).
    This module holds fonts, padding, and the capacity color function.
]]

local _, Pockets = ...

Pockets.UI.Layout = Pockets.UI.Layout or {}
local Layout = Pockets.UI.Layout

Layout.PADDING = 8

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
