# Pockets UI Rules

Modeled after pH's UI discipline, adapted for Pockets' progressive-
disclosure bag HUD (`Pockets_PRD.md` §2, `Pockets_TDD.md` §13, §26).

## Core Rules

1. **Compact HUD first.** The default, always-visible state is one small
   frame (`UI/HUD.lua`): bag icon/background, capacity text, and a
   conditionally-shown ETA text. No feature may require permanent extra
   screen space without explicit product approval.
2. **Progressive disclosure only.** HUD → category flyout → item flyout →
   full inventory. Don't skip a level, and don't add a persistent
   always-visible layer beyond the HUD itself.
3. **Frames stay on-screen.** After dragging or scaling, a frame must
   remain fully within the screen bounds.
4. **Shared constants, not duplicated values.** Spacing, fonts, and colors
   come from `UI/Layout.lua` (`Layout.PADDING`, `Layout.ROW_HEIGHT`,
   `Layout:GetCapacityColor()`, etc.). No UI module hard-codes its own
   pixel offsets or capacity-color thresholds.
5. **No UI module owns authoritative inventory state.** Every UI module
   reads from `Core/InventoryState.lua` (via `Pockets.API` or the service
   directly) and never rescans bags itself.
6. **Never block the full Pockets UI in combat.** Only hover-triggered
   expansion is suppressed in combat (`Pockets_TDD.md` §14). Clicking the
   HUD, clicking a category, and Shift-B must keep working. Individual
   protected/restricted actions degrade independently rather than hiding
   the whole addon.
7. **Hover is convenience; click is the reliable path.** Every hover-driven
   reveal (category flyout, item flyout) must have an equivalent click
   path that also works in combat.
8. **Pool, don't recreate.** Repeated rows/buttons (category rows, item
   buttons) come from `UI/ItemButtonPool.lua` or an equivalent per-frame
   pool. Flyouts and the full inventory view must not create new frames on
   every open.
9. **Render only non-empty categories.** Empty categories are hidden in
   both the category flyout and the full inventory view.
10. **Tooltip content stays terse.** `UI/TooltipCounts.lua` adds exactly
    one line (`Pockets: <count>`) and never duplicates it on tooltip
    refresh.
11. **Flyouts stay independently closable.** `CategoryFlyout` and
    `ItemFlyout` each manage their own show/hide so click navigation keeps
    working even if a parent flyout later closes.

## Capacity Colors

Use `Layout:GetCapacityColor(utilization)` - never re-implement the
green/yellow/red thresholds in a UI module. Current implementation
defaults (`Constants.CAPACITY_COLOR_THRESHOLDS`), not a user-facing tuning
system in v1:

```
Green  < 70% used
Yellow 70-89% used
Red    >= 90% used
```

## Full Inventory Layout

- Fixed maximum width/height (`Layout.MAX_FULL_INVENTORY_WIDTH/HEIGHT`)
  appropriate for small screens.
- Category sections stack vertically; no persistent sidebars.
- Search row only exists while the full view is open (`PRD §3.7`) - never
  a persistent search box in the HUD or category flyout.
- Recent items are prominently available, not buried.
- One frame with pooled item buttons - never one panel per physical bag.

## When Adding a New UI Module

1. Read state through `Pockets.Services.*` or `Pockets.API.*` - don't
   introduce a second source of truth.
2. Subscribe to `Core/EventBus.lua` domain events rather than polling.
3. Pull spacing/font/color from `UI/Layout.lua`.
4. Confirm the combat behavior matches `Pockets_TDD.md` §14's hover/click
   state machine before shipping.
5. Add the corresponding manual acceptance case to
   [TESTING_GUIDE.md](TESTING_GUIDE.md).
