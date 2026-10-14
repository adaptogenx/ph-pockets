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

-- Category body presentation preference (Category List/Grid view pass).
-- Grid is the existing, preserved-exactly implementation; List is new.
-- Grid stays the default until a deliberate future product decision.
Constants.CATEGORY_VIEW_MODE = {
    GRID = "GRID",
    LIST = "LIST",
}

-- Persistent HUD presentation (Mini HUD TDD §3). Glance stays the default.
Constants.HUD_MODE = {
    GLANCE = "GLANCE",
    MINI = "MINI",
    RADIAL = "RADIAL",
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
-- Loot Log (recent activity feed, NOT a durable history - pH owns that).
-- Per-character, persisted in PocketsCharDB.lootLog; oldest entries drop
-- first once the bound is hit.
Constants.LOOT_LOG_MAX = 100
-- Seconds after the loot window closes during which new bag items still
-- count as loot (bag scans are debounced and trail the window).
Constants.LOOT_CONTEXT_GRACE_SECONDS = 5

--[[
    Verified Blizzard icon assets (UI_SPEC §3, §16.11-12).

    Every value below was confirmed present by grepping shipped, working
    addons on this machine's live Anniversary client (Baganator/BagBrother/
    Attune/Inscription-adjacent code) for the exact fileID or texture path
    already in production use - not guessed. Numeric values are texture
    FileDataIDs (usable directly with :SetTexture(number)); string values
    are "Interface\Icons\<name>" paths.

    Provenance, for future maintainers who want to swap any of these:
      HUD        = "Interface\Buttons\Button-Backpack-Up" (stock Blizzard
                   backpack-slot icon art - a clean backpack drawing on a
                   transparent background, not an item-icon square with
                   black corner padding, so it reads well at Glance's
                   small icon size with no texcoord cropping needed)
      other      = 133628  (BagBrother "Normal Bags" rule icon - generic bag look)
      recent     = "Interface\Icons\INV_Scroll_02" (Inscription/Attune scroll icon, distinct from quest)
      equipment  = 133126  (BagBrother item-class icon: Armor/Weapon/Gem)
      consumable = 134756  (BagBrother item-class icon: Consumable)
      trade_goods= 132894  (BagBrother item-class icon: Tradegoods/Profession/Reagent/Recipe)
      quest      = "Interface\Icons\INV_Scroll_03" (Attune/Inscription scroll icon)
      ammo       = 133581  (BagBrother's default-ammo-icon fallback)
      junk       = 134414  (BagBrother item-class icon: Miscellaneous)
      gold       = "Interface\MoneyFrame\UI-GoldIcon" (stock Blizzard money-
                   frame coin icon - same asset pH's own Ledger/HUD money
                   display uses, already clean/inline at small sizes)
]]
Constants.HUD_ICON = "Interface\\Buttons\\Button-Backpack-Up"
Constants.GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"

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
    -- Glance: compact metric-list HUD (Glance redesign pass), NOT a
    -- centered status card and NOT forced square - exempt from the
    -- stable shell contract. Structure: a lightweight header ("pockets" +
    -- Search), then Bag/Gold/Ammo metric rows (Ammo optional, always
    -- last), then a Recent Items icon strip. Width is fixed (chosen to
    -- comfortably fit both the worst-case metric-row text and ~5 Recent
    -- icons - see GLANCE_WIDTH below); height is pure arithmetic from
    -- these constants in Shell:RenderGlance (row count varies only with
    -- Ammo's presence), never a runtime GetHeight() query.
    GLANCE_PADDING = 8,
    -- "pockets (time till full)" + Search + All Items icons, one row.
    GLANCE_HEADER_HEIGHT = 18,
    GLANCE_HEADER_GAP = 6,
    -- Gap between "pockets" and its "(8m)"/"(Full)" subtitle, and between
    -- the two trailing icon buttons.
    GLANCE_HEADER_TITLE_GAP = 4,
    GLANCE_HEADER_ICON_GAP = 4,
    -- Must match PHUI.Spacing.ICON_BUTTON_SIZE (Shared/PHUI.lua) - these
    -- are bordered, clickable icon BUTTONS (Search, All Items), the same
    -- kind of element as Shell's expanded-header back/close/+ buttons
    -- (SHELL_HEADER_SIDE_WIDTH/SHELL_HEADER_CLOSE_WIDTH below), not a
    -- plain metric-row icon - they must match THAT convention, size-wise,
    -- not GLANCE_METRIC_ICON_SIZE below.
    GLANCE_HEADER_ICON_SIZE = 20,
    -- Must match PHUI.Spacing.ICON_SIZE (Shared/PHUI.lua) - a PLAIN icon
    -- with no button chrome (distinct from GLANCE_HEADER_ICON_SIZE
    -- above), verified against pH's own UI_HUD.lua metric-tile icon
    -- size (12px), not guessed. Shared by every metric row (Bag/Gold/
    -- Ammo) via UI/MetricRow.lua - identical icon size/row height/left
    -- edge/spacing is the whole point of the shared component (METRIC
    -- ROW SYSTEM spec), not per-row tuning.
    GLANCE_METRIC_ICON_SIZE = 12,
    -- Row height stays taller than the 12px icon alone (comfortable
    -- click/hover target, room for GameFontNormal-sized primary text) -
    -- unlike pH's TILE_HEIGHT (icon+gap+bar stacked vertically), Pockets'
    -- rows lay icon+text out horizontally, so there's no equivalent pH
    -- value this needs to match.
    GLANCE_METRIC_ROW_HEIGHT = 18,
    GLANCE_METRIC_ICON_TEXT_GAP = 6,
    -- Small, uniform gap between stacked metric rows - deliberately not a
    -- divider (spec: "Do NOT add divider lines between these rows").
    GLANCE_METRIC_ROW_GAP = 3,
    -- Recent Items strip (RECENT ITEMS spec) - "slightly larger than the
    -- 16-20px metric icons... but keep compact". Width/count below are
    -- sized together: 5 icons at this size+gap is what GLANCE_WIDTH's
    -- content width is chosen to fit (RECENT ITEMS + WIDTH spec - the
    -- strip helps set Glance's width, not the other way around).
    -- Shell/RecentItemStrip still clamp to however many ACTUALLY fit at
    -- render time rather than hard-coding a count.
    GLANCE_RECENT_GAP = 6,
    GLANCE_RECENT_ICON_SIZE = 22,
    GLANCE_RECENT_ICON_GAP = 4,
    -- Fixed content width: comfortably fits the worst-case metric-row
    -- text (icon + "199 / 200" + gap + "8m") AND 5 Recent icons
    -- (5*22 + 4*4 = 126, +6px slack = 132). Total width adds
    -- GLANCE_PADDING on both sides.
    GLANCE_WIDTH = 148,
    -- Forever Glance (UI/PocketsGlance.lua): reserved widths of the bag and
    -- money groups in the content row; Recent takes the remainder.
    GLANCE_BAG_GROUP_WIDTH = 84,
    GLANCE_MONEY_GROUP_WIDTH = 74,
    -- Glance's ">>" (more Recent) button sits in the strip's slot right
    -- after the last shown Recent icon, same size as a Recent icon, so it
    -- takes one icon slot (4 icons + ">>" at GLANCE_WIDTH) instead of
    -- widening Glance.
    GLANCE_RECENT_MORE_SIZE = 22,

    -- Loot Log rows (Loot Log feature): `timestamp | loot`, dense, no
    -- cards. Icon reuses GLANCE_METRIC_ICON_SIZE (pH-verified plain-icon
    -- size) - a Loot Log row icon is a plain icon, not a bordered button.
    -- LOOT_TIME_WIDTH fits "00:00" in GameFontNormalSmall with slack so
    -- the timestamp can never wrap or push the loot column around.
    LOOT_TIME_WIDTH = 34,
    LOOT_ROW_PAD_Y = 3,
    LOOT_COLUMN_GAP = 6,

    -- Stable shell: Menu/Category/All share this exact width, TOPLEFT,
    -- header height, footer height, and body left/right bounds (§3/§8
    -- "Stable application shell"). Total HEIGHT is intentionally NOT
    -- shared - every expanded state's body grows to fit its actual
    -- visible content between SHELL_BODY_MIN_HEIGHT and
    -- SHELL_BODY_MAX_HEIGHT (a scrollbar only appears past the max;
    -- Menu and Category List use their own shared row-count-based cap
    -- instead - see MAX_VISIBLE_LIST_ROWS), rather than always claiming
    -- the max whether or not the content needs it. The invariant is
    -- position stability, not identical frame height.
    -- Must match PHUI.PH_HUD_WIDTH_EXPANDED (Shared/PHUI.lua), the same width as Glance so every view is one consistent width. Originally PHUI.PH_HUD_WIDTH - pH's own real,
    -- verified HUD width (ph/UI_HUD.lua:2629/2834, hudFrame:SetWidth(266))
    -- - NOT GLANCE_WIDTH. Glance stays intentionally compact/content-sized
    -- (never meant to clone pH's footprint), but the expanded Shell
    -- (Search/Menu/Category/All) is meant to match pH's real width. The
    -- item grid's column count is computed dynamically from this width
    -- (FlowLayout:PlanFlat) rather than assumed fixed, so this value is
    -- free to change without breaking layout.
    SHELL_WIDTH = 340,
    -- Matches PHUI.Spacing.PANEL_PADDING (Shared/PHUI.lua) - Menu/Category/
    -- All are pH's smaller inner-sub-panel style, not the main HUD frame
    -- (that's Glance, which uses PHUI.Spacing.PADDING - see GLANCE_PADDING).
    SHELL_PADDING = 8,
    SHELL_HEADER_HEIGHT = 26,
    -- Sensible floor for Category/All's dynamic body height (dynamic
    -- height pass) - comfortably fits one Grid item row or two List rows
    -- even for a near-empty category, so the panel never collapses to
    -- something absurdly thin.
    SHELL_BODY_MIN_HEIGHT = 64,
    SHELL_BODY_MAX_HEIGHT = 260,
    SHELL_FOOTER_HEIGHT = 22,
    -- Fixed left (back), contextual-action (+/search), and close (X)
    -- header zone widths - the control occupying a zone may change, the
    -- zone itself never moves (top-bar/close pass). X is always reserved
    -- at the far right, with the contextual action immediately left of it,
    -- so the title's right edge never shifts between expanded states.
    -- Must match PHUI.Spacing.ICON_BUTTON_SIZE (Shared/PHUI.lua) - see
    -- GLANCE_HEADER_ICON_SIZE's comment above; this is the SAME
    -- established icon-button size, just this constant's own name
    -- predates that shared default existing.
    SHELL_HEADER_SIDE_WIDTH = 20,
    SHELL_HEADER_RIGHT_WIDTH = 60,
    -- Must match PHUI.NATIVE_CLOSE_BUTTON_SIZE (Shared/PHUI.lua) - the X
    -- is a real UIPanelCloseButton, and pH's own closeBtn (ph/UI_History.
    -- lua:156-157) never resizes it away from its native 32px. This is
    -- deliberately NOT ICON_BUTTON_SIZE (20) like the other header
    -- buttons - forcing the close template down to 20px visibly didn't
    -- match pH's real X (the template's border/glow art doesn't scale
    -- cleanly), so this one stays at pH's true native size and is
    -- allowed to overhang SHELL_HEADER_HEIGHT slightly, same as pH's own
    -- close button overhangs its thin corner placement.
    SHELL_HEADER_CLOSE_WIDTH = 32,
    SHELL_HEADER_ACTION_GAP = 4,

    -- Shared Pockets list-row visual geometry (row unification pass) -
    -- Category List is the visual source of truth; Menu category rows
    -- and Category item rows are the SAME row component (same height,
    -- icon size, padding, gap, count column, hover treatment), only
    -- their semantics differ. Fixed conceptual columns ICON | LABEL |
    -- FLEX | COUNT | CHEVRON - only LABEL/FLEX ever changes width, and
    -- item rows reserve the same trailing CHEVRON column (left empty)
    -- so their count lines up with category rows' count exactly.
    LIST_ROW_HEIGHT = 30,
    LIST_ICON_SIZE = 24,
    LIST_ROW_PADDING = 4,
    LIST_ROW_GAP = 4,
    LIST_ROW_COUNT_WIDTH = 26,
    LIST_ROW_CHEVRON_WIDTH = 16,

    -- Shared list-row visible-row cap (height-management pass) - both
    -- Menu and Category List grow naturally until this many complete
    -- rows are showing, then cap and scroll. Deliberately row-count-based
    -- rather than Grid/All's raw pixel budget (SHELL_BODY_MAX_HEIGHT), so
    -- the cap always lands on a whole row, never a half-visible one.
    -- Implementation constant, not a user preference yet. Lowered from
    -- an earlier 8 to 6 specifically to stop Pockets from consuming too
    -- much vertical space on smaller screens (dynamic screen-edge
    -- positioning is explicitly out of scope for this pass).
    MAX_VISIBLE_LIST_ROWS = 6,

    -- Informational only - FlowLayout derives actual column count from
    -- content width/ITEM_BUTTON_SIZE/ITEM_BUTTON_GAP dynamically, not
    -- from this constant. Documents the width-driven default (no
    -- scrollbar showing) so the two stay in sync when tuned.
    ITEM_PANEL_COLUMNS = 5,
    ITEM_BUTTON_SIZE = 40,
    ITEM_BUTTON_GAP = 4,

    -- Full-inventory category header redesign (icon-free, collapsible
    -- section headers - no pH equivalent exists for this, so this reuses
    -- Pockets' OWN already-established compact single-line row height
    -- (GLANCE_HEADER_HEIGHT/GLANCE_METRIC_ROW_HEIGHT are both 18) rather
    -- than a freshly eyeballed number.
    CATEGORY_HEADER_HEIGHT = 18,
    -- Distinct from RECENT_DISPLAY_LIMIT (20, used by Glance's strip and
    -- Quick Search) - the Full Inventory Recent SECTION is capped tighter
    -- ("what did I just pick up", not another full category).
    FULL_INVENTORY_RECENT_LIMIT = 5,

    -- Centralized expanded-surface opacity (UI layout pass §9) - Glance
    -- keeps the lighter, passive-HUD-like alpha; every expanded state
    -- (Menu/Category/All) uses one shared, more opaque body alpha plus a
    -- slightly-more-opaque header/footer chrome band, so nothing hardcodes
    -- its own alpha independently.
    GLANCE_ALPHA = 0.78,

    -- Mini HUD (Mini HUD TDD §2): round portrait + ring + count badge.
    -- Footprint is exactly portrait + badge minus their overlap.
    -- Sized 1.25x the original 52x62 / 48px TDD spec (player feedback:
    -- too small). Height = portrait - overlap + badge.
    MINI_WIDTH = 65,
    MINI_HEIGHT = 77,
    MINI_PORTRAIT_SIZE = 60,
    MINI_ICON_SIZE = 43,
    MINI_RING_THICKNESS = 5,
    MINI_BADGE_WIDTH = 62,
    MINI_BADGE_HEIGHT = 22,
    MINI_BADGE_OVERLAP = 5,

    -- Radial Glance (Outer Ring TDD §3): eight fixed semantic slots on a
    -- ring around the Mini center. Slots clockwise from the top:
    -- 1 gold, 2 ammo, 3-4 specialized bags, 5-8 recent items (newest first).
    RADIAL_SLOTS = 4, -- metric satellites: gold, ammo, up to two specialized bags
    RADIAL_ARC_STEP = 48, -- degrees between satellites: ~a quarter circle for three
    RADIAL_RADIUS = 76, -- arc radius; clears the 65x77 Mini and its hanging badge
    RADIAL_NODE_SIZE = 42,
    RADIAL_NODE_ICON = 30,
    RADIAL_BADGE_WIDTH = 42,
    RADIAL_GOLD_BADGE_WIDTH = 52,
    RADIAL_BADGE_HEIGHT = 14,
    RADIAL_BADGE_OVERLAP = 6,
    -- Recent strip right under the radial: 5 exact 24px icons, 6px apart,
    -- inside a rounded border (8px side padding, 6px top/bottom).
    RADIAL_STRIP_ICONS = 5,
    RADIAL_STRIP_ICON = 24,
    RADIAL_STRIP_GAP = 6,
    RADIAL_STRIP_PAD_X = 8,
    RADIAL_STRIP_WIDTH = 160, -- full width (5 icons); the strip shrinks to fit fewer
    RADIAL_STRIP_HEIGHT = 36,
    RADIAL_STRIP_OFFSET = 4, -- gap below the lowest visible radial element
    RADIAL_MAX_SHIFT = 24, -- most the ring may slide to stay on screen
    EXPANDED_BODY_ALPHA = 0.92,
    EXPANDED_CHROME_ALPHA = 0.96,

    -- Glance Quick Search (SEARCH state) - deliberately NOT the
    -- scrollable Menu/Category/All body: no footer, no scrollbar, capped
    -- at SEARCH_MAX_RESULT_ROWS rows, height derived purely from whatever
    -- is currently shown (input row, result rows, or feedback text).
    -- Up to SEARCH_MAX_RESULT_ROWS matches render as real rows (with an
    -- "and N more" line once totalCount exceeds that); beyond
    -- SEARCH_OVERFLOW_LIMIT matches it collapses to "keep typing" feedback
    -- instead, same as the old 3+-match behavior.
    SEARCH_INPUT_HEIGHT = 20,
    SEARCH_ICON_SIZE = 14,
    SEARCH_ROW_GAP = 4,
    SEARCH_FEEDBACK_LINE_HEIGHT = 16,
    SEARCH_FEEDBACK_LINE_GAP = 2,
    SEARCH_MAX_RESULT_ROWS = 7,
    SEARCH_OVERFLOW_LIMIT = 20,

    -- Recent Item Preview (opt-in toggle, off by default) - a large
    -- floating icon shown near top-center of the screen while hovering a
    -- Recent Items strip button, independent of Glance's own position/
    -- size so it never gets clipped by Glance's small footprint.
    RECENT_PREVIEW_ICON_SIZE = 96,
    RECENT_PREVIEW_PADDING = 8,
    RECENT_PREVIEW_TOP_OFFSET = 60,
}

-- NOTE: Menu's and Category List's max browsing height
-- (MAX_VISIBLE_LIST_ROWS * LIST_ROW_HEIGHT) is a CONTENT-height
-- threshold, computed where it's used (Shell.lua's RenderMenu/
-- RenderCategoryList) via the same ResolveDynamicHeight() every
-- dynamic-height renderer shares - not duplicated here as a separate
-- derived bodyHeight constant.

-- NOTE: Menu's body height is NOT a load-time constant - zero-count
-- categories are hidden at render time (§10 of the row-unification
-- pass), so the visible row count (and thus height) can only be known
-- when Shell:RenderMenu() actually reads live category counts. See
-- Shell.lua's RenderMenu, which computes and applies it per-render the
-- same way Category/All already do.

-- Single source of truth for Glance's total height, shared by
-- Shell:RenderGlance (which also decides includeAmmo) and tests - pure
-- arithmetic from fixed row-geometry constants, deliberately never a
-- runtime GetHeight()/GetBottom() query (a frame anchored by a single
-- point with an unresolved dimension can report nil for those - see the
-- Glance blank-render bug this pass fixed). Ammo adds exactly one metric
-- row; its absence removes exactly that row's height (AMMO ROW spec).
function Constants:GlanceContentHeight(includeAmmo)
    local L = Constants.LAYOUT
    local rowCount = includeAmmo and 3 or 2
    return L.GLANCE_PADDING * 2
        + L.GLANCE_HEADER_HEIGHT + L.GLANCE_HEADER_GAP
        + rowCount * L.GLANCE_METRIC_ROW_HEIGHT + (rowCount - 1) * L.GLANCE_METRIC_ROW_GAP
        + L.GLANCE_RECENT_GAP + L.GLANCE_RECENT_ICON_SIZE
end

-- Domain events published on Pockets' internal EventBus (TDD §5.5)
Constants.DOMAIN_EVENT = {
    INVENTORY_CHANGED = "POCKETS_INVENTORY_CHANGED",
    ITEM_ACQUIRED = "POCKETS_ITEM_ACQUIRED",
    CATEGORY_CHANGED = "POCKETS_CATEGORY_CHANGED",
    CAPACITY_CHANGED = "POCKETS_CAPACITY_CHANGED",
    ETA_CHANGED = "POCKETS_ETA_CHANGED",
    COMBAT_STATE_CHANGED = "POCKETS_COMBAT_STATE_CHANGED",
    LOOT_LOGGED = "POCKETS_LOOT_LOGGED",
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
    categoryViewMode = Constants.CATEGORY_VIEW_MODE.GRID,
    hudMode = Constants.HUD_MODE.GLANCE,
    -- Opt-in (v1 stays minimal/opinionated by default - PRD §4 non-goals
    -- warn against a large configuration surface, so new visual extras
    -- default OFF rather than always-on).
    recentItemPreviewEnabled = false,
}
