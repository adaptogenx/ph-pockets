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
Constants.RECENT_DISPLAY_LIMIT = 20
Constants.ESTIMATOR_SAMPLE_WINDOW_MAX = 60

--[[
    Verified Blizzard icon assets (UI_SPEC §3, §16.11-12).

    Every value below was confirmed present by grepping shipped, working
    addons on this machine's live Anniversary client (Baganator/BagBrother/
    Attune/Inscription-adjacent code) for the exact fileID or texture path
    already in production use - not guessed. Numeric values are texture
    FileDataIDs (usable directly with :SetTexture(number)); string values
    are "Interface\Icons\<name>" paths.

    Provenance, for future maintainers who want to swap any of these:
      HUD/other  = 133628  (BagBrother "Normal Bags" rule icon - generic bag look)
      recent     = "Interface\Icons\INV_Scroll_02" (Inscription/Attune scroll icon, distinct from quest)
      equipment  = 133126  (BagBrother item-class icon: Armor/Weapon/Gem)
      consumable = 134756  (BagBrother item-class icon: Consumable)
      trade_goods= 132894  (BagBrother item-class icon: Tradegoods/Profession/Reagent/Recipe)
      quest      = "Interface\Icons\INV_Scroll_03" (Attune/Inscription scroll icon)
      ammo       = 133581  (BagBrother's default-ammo-icon fallback)
      junk       = 134414  (BagBrother item-class icon: Miscellaneous)
]]
Constants.HUD_ICON = 133628

Constants.CATEGORY_ICON = {
    recent = "Interface\\Icons\\INV_Scroll_02",
    equipment = 133126,
    consumable = 134756,
    trade_goods = 132894,
    quest = "Interface\\Icons\\INV_Scroll_03",
    ammo = 133581,
    junk = 134414,
    other = 133628,
}

-- Fixed UI geometry for the single-frame Glance -> Menu -> Category -> All
-- Items shell (.plans/Pockets_Glance_UI.md). Only Glance is exempt from the
-- stable width/header/footer contract shared by Menu/Category/All.
Constants.LAYOUT = {
    -- Glance: minimal always-visible HUD, exempt from the stable shell
    -- contract. Fixed size (no longer content-dependent - Ammo was
    -- dropped from Glance entirely) so it stays as compact as possible:
    -- icon + "59 / 76" on one row, compact "13m" ETA on the next.
    GLANCE_WIDTH = 128,
    GLANCE_HEIGHT = 52,
    GLANCE_ICON_SIZE = 30,
    GLANCE_PADDING = 8,
    GLANCE_TEXT_GAP_X = 6,
    GLANCE_TEXT_GAP_Y = 1,

    -- Stable shell: Menu/Category/All share this exact width, TOPLEFT,
    -- header height, footer height, and body left/right bounds (§3/§8
    -- "Stable application shell"). Total HEIGHT is intentionally NOT
    -- shared - Menu's body is content-driven (MENU_BODY_HEIGHT, derived
    -- below from the fixed category count) while Category/All get a
    -- bounded, scrollable browsing viewport (SHELL_BODY_MAX_HEIGHT). The
    -- invariant is position stability, not identical frame height.
    SHELL_WIDTH = 220,
    SHELL_PADDING = 8,
    SHELL_HEADER_HEIGHT = 26,
    SHELL_BODY_MAX_HEIGHT = 260,
    SHELL_FOOTER_HEIGHT = 22,
    -- Fixed left (back) and right (+/search) header action-zone widths -
    -- the control occupying a zone may change, the zone itself never moves.
    SHELL_HEADER_SIDE_WIDTH = 20,
    SHELL_HEADER_RIGHT_WIDTH = 60,

    MENU_ROW_HEIGHT = 24,
    MENU_ROW_ICON_SIZE = 16,
    MENU_ROW_COUNT_WIDTH = 34,

    ITEM_PANEL_COLUMNS = 4,
    ITEM_BUTTON_SIZE = 40,
    ITEM_BUTTON_GAP = 4,

    FULL_INVENTORY_LABEL_HEIGHT = 16,
    FULL_INVENTORY_LABEL_ICON_SIZE = 12,
    FULL_INVENTORY_LABEL_ICON_GAP = 4,

    -- Centralized expanded-surface opacity (UI layout pass §9) - Glance
    -- keeps the lighter, passive-HUD-like alpha; every expanded state
    -- (Menu/Category/All) uses one shared, more opaque body alpha plus a
    -- slightly-more-opaque header/footer chrome band, so nothing hardcodes
    -- its own alpha independently.
    GLANCE_ALPHA = 0.85,
    EXPANDED_BODY_ALPHA = 0.92,
    EXPANDED_CHROME_ALPHA = 0.96,
}

-- Menu's body height is derived, not hand-tuned: HEADER + one row per
-- category + FOOTER + top/bottom padding, and nothing else (§5 "no giant
-- empty body"). Computed once here (not per-render) since the category
-- count is fixed at load time.
Constants.LAYOUT.MENU_BODY_HEIGHT = #Constants.CATEGORY_ORDER * Constants.LAYOUT.MENU_ROW_HEIGHT
    + Constants.LAYOUT.SHELL_PADDING * 2

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

-- Default SavedVariables shape (TDD §19). TOPLEFT is Pockets' one V1
-- positional anchor (UI layout pass §1/§2) - Glance and every expanded
-- state share this same screen-space origin; only TOPLEFT-anchored
-- positions are ever saved/restored (see UI/PositionStrategy.lua).
Constants.DEFAULT_SETTINGS = {
    hud = {
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 100,
        y = -100,
        locked = false,
    },
}
