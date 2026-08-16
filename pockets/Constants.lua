--[[
    Constants.lua - Shared constants for Pockets

    Centralizes capacity classes, category IDs, colors, and other values
    that must not be duplicated across modules (TDD §7, §10, §13.2).
]]

local _, Pockets = ...

Pockets.Constants = Pockets.Constants or {}
local Constants = Pockets.Constants

-- Capacity classes (TDD §7)
Constants.CAPACITY_CLASS = {
    GENERAL = "GENERAL",
    AMMO = "AMMO",
}

-- Stable category IDs (TDD §5.2)
Constants.CATEGORY = {
    RECENT = "recent",
    EQUIPMENT = "equipment",
    CONSUMABLE = "consumable",
    TRADE_GOODS = "trade_goods",
    QUEST = "quest",
    AMMO = "ammo",
    JUNK = "junk",
    OTHER = "other",
}

-- Display order for category flyout / full inventory (PRD §3.4)
Constants.CATEGORY_ORDER = {
    Constants.CATEGORY.RECENT,
    Constants.CATEGORY.EQUIPMENT,
    Constants.CATEGORY.CONSUMABLE,
    Constants.CATEGORY.TRADE_GOODS,
    Constants.CATEGORY.QUEST,
    Constants.CATEGORY.AMMO,
    Constants.CATEGORY.JUNK,
    Constants.CATEGORY.OTHER,
}

Constants.CATEGORY_LABEL = {
    [Constants.CATEGORY.RECENT] = "Recent",
    [Constants.CATEGORY.EQUIPMENT] = "Equipment",
    [Constants.CATEGORY.CONSUMABLE] = "Consumables",
    [Constants.CATEGORY.TRADE_GOODS] = "Trade Goods",
    [Constants.CATEGORY.QUEST] = "Quest",
    [Constants.CATEGORY.AMMO] = "Ammo",
    [Constants.CATEGORY.JUNK] = "Junk",
    [Constants.CATEGORY.OTHER] = "Other",
}

-- Capacity color thresholds (TDD §13.2). Implementation defaults, not user-tunable in v1.
Constants.CAPACITY_COLOR_THRESHOLDS = {
    YELLOW_AT = 0.70,
    RED_AT = 0.90,
}

Constants.CAPACITY_COLOR = {
    GREEN = { r = 0.20, g = 0.80, b = 0.30 },
    YELLOW = { r = 0.95, g = 0.85, b = 0.20 },
    RED = { r = 0.90, g = 0.25, b = 0.20 },
}

-- Estimator states (TDD §5.4, §11.4)
Constants.ESTIMATOR_STATE = {
    WARMING_UP = "warming_up",
    FILLING = "filling",
    STABLE = "stable",
    FREEING = "freeing",
    FULL = "full",
}

-- Bounded history/window sizes (TDD §21 performance requirements)
Constants.RECENT_ITEMS_MAX = 50
Constants.ESTIMATOR_SAMPLE_WINDOW_MAX = 60

-- Domain events published on Pockets' internal EventBus (TDD §5.5)
Constants.DOMAIN_EVENT = {
    INVENTORY_CHANGED = "POCKETS_INVENTORY_CHANGED",
    ITEM_ACQUIRED = "POCKETS_ITEM_ACQUIRED",
    CATEGORY_CHANGED = "POCKETS_CATEGORY_CHANGED",
    CAPACITY_CHANGED = "POCKETS_CAPACITY_CHANGED",
    ETA_CHANGED = "POCKETS_ETA_CHANGED",
    COMBAT_STATE_CHANGED = "POCKETS_COMBAT_STATE_CHANGED",
    READY = "POCKETS_READY",
}

-- Default SavedVariables shape (TDD §19)
Constants.DEFAULT_SETTINGS = {
    hud = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        locked = false,
    },
}
