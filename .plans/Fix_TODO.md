Fix list for the current Glance/Menu/Category/All shell.

Do not mix Adaptive Screen Sizing into this pass (see `.plans/Adaptive_Screen_sizing.md`).

==================================================
1. Alphabetical ordering of items
==================================================

Status: broken. Category/All item lists iterate `pairs()` / first-seen bag order, so names jump around.

Fix:
- Sort aggregated items A–Z by item name (case-insensitive) in Category List, Category Grid, and All Items grouped sections.
- Keep Menu category order as `CATEGORY_ORDER` (taxonomy, not alpha).
- Keep Recent newest-first. Recency is the point of that view.
- Missing names sort last (`item:<id>` fallback), not as empty strings.

Touch:
- `pockets/Core/InventoryState.lua` (`GetItemsByCategory` / `AggregateRecords`) or a single sort at `API.GetAggregatedCategoryItems`
- Tests for A–Z order and Recent remaining unsorted by name

==================================================
2. Unique recent items
==================================================

Status: broken. Display already dedupes by `itemID` (`API.GetResolvedRecentItems`), but `RecentItems:Record` still prepends a new history row per acquisition.

Effect: fishing 20 of the same fish fills `RECENT_ITEMS_MAX` with that one id, then the other unique recents fall off the queue. After display-time dedupe the Recent category is just that fish.

Fix:
- Treat Recent as unique-by-itemID, not a raw event log.
- Re-acquiring an already-recent item: bump it to newest, do not add a second row, do not evict other unique items.
- Bound unique itemIDs (`RECENT_ITEMS_MAX` / `RECENT_DISPLAY_LIMIT`), not duplicate pickup events.
- Displayed quantity stays current carried total (existing resolver behavior).

Touch:
- `pockets/Core/RecentItems.lua`
- `pockets/Tests/RecentItemsTests.lua`
- `pockets/Tests/APITests.lua` (dedupe-at-source, not only at resolve)

==================================================
3. Glance is not a square
==================================================

Status: broken. Glance is a wide rectangle.

Current derived size:

    GLANCE_WIDTH  = 6+30+4+62+6 = 108
    GLANCE_HEIGHT = 52

The compactness pass optimized for a horizontal `[icon][capacity/ETA]` row. The Glance plan asked for a small square surface.

Fix:
- Glance frame width == height (true square, not “square-ish”).
- Bag icon stays the dominant visual.
- Capacity (`57 / 84`) and compact ETA still readable inside the square.
- Adding the search control (#4) must not stretch Glance back into a rectangle.
- Existing tests that lock the derived 108-wide layout need to change with the geometry.

Touch:
- `pockets/Constants.lua` (`LAYOUT.GLANCE_*`)
- `pockets/UI/Shell.lua` (`BuildGlance` / `RenderGlance`)
- `pockets/Tests/ShellTests.lua` (Glance size tests)

==================================================
4. Search icon / easy search on Glance
==================================================

Status: missing. Search exists only in All Items header (`header.searchBox`). PRD §3.7 forbids a persistent search *box* on the compact HUD, not a click-to-search affordance.

Fix:
- Put a small search icon on Glance (not a persistent EditBox on the HUD).
- Clicking it goes All Items and focuses the existing search field.
- Main Glance click (icon / capacity) still opens Menu.
- Click, not hover, so combat does not block it.
- Keep Glance square (#3). Do not grow a search field onto the HUD.

Spec:
- Update `Pockets_PRD.md` §3.7 and `UI_RULES.md` so Glance may expose a search *icon* that jumps to All Items search. Still no persistent HUD search box.

Touch:
- `pockets/UI/Shell.lua`
- `pockets/Tests/ShellTests.lua`
- `Pockets_PRD.md`, `UI_RULES.md`

==================================================
5. Close (X) on list views → Glance
==================================================

Status: missing. Expanded states only have hierarchical Back (`<`) and Escape:

    Category / All → Menu → Glance

There is no one-click collapse to Glance. `PHUI.CreateCloseButton` already exists and is unused by Shell.

Fix:
- Show an X/close control on Menu, Category, and All Items (every expanded list view).
- Clicking it always returns to Glance, skipping Menu when the current state is Category or All.
- Leave `<` and Escape as one-level Back. X is “dismiss Pockets,” Back is “up one level.”
- Keep X on Glance hidden; Glance is already the collapsed HUD.
- Do not steal All Items’ search slot. Park X on the far right; `+` / search sit just left of it.
- Use the existing PHUI close-button treatment rather than a one-off glyph.

Touch:
- `pockets/UI/Shell.lua` (`BuildShell`, `ConfigureHeader`, new `CloseToGlance` or `SetState(GLANCE)`)
- `pockets/Constants.lua` if the header right zone needs room for close + plus/search
- `pockets/Tests/ShellTests.lua` (X on every expanded state; Category/All X lands on Glance, not Menu)

==================================================
6. Suggested implementation order
==================================================

1. Unique recents (core, no layout risk)
2. Alphabetical item order (core/API, tests)
3. Square Glance (layout + tests)
4. Glance search icon (depends on square Glance so the control fits)
5. Close X on list views (header chrome; independent of Glance square except shared header-zone math)

==================================================
7. Out of scope
==================================================

- Adaptive viewport / growth direction
- User-facing sort UI or configurable sort order
- Persistent search box on Glance or Menu
- Changing category taxonomy order
