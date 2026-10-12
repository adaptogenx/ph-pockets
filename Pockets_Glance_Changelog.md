# Forever Glance - changelog

Implements `Pockets_Forever_Glance_TDD.md`. Pockets only; pH untouched.

## What changed
- Glance is a fixed 340 x 64 horizontal HUD (pH's real expanded HUD width) built on a reusable chassis
  (`Shared/GlanceFrame.lua`) composed in `UI/PocketsGlance.lua`.
- Header: `pockets` | main-bag ETA (`18m` / `to full`, `—` when unknown) |
  Search, Log (scroll), Expand (+).
- Body: bag icon + `used / total` + `>` arrow + fill bar (one click target,
  opens All Items) | money | five Recent icons (20px, no label, no `>>`).
- Specialized-bag tabs dock 4px under the HUD (left edge + 12): Ammo (only
  with an ammo bag equipped), Reagents, and profession bags. Main capacity,
  fill bar and ETA now exclude all specialized bags.
- `Shared/PHUI.lua` palette and font tokens updated to the TDD values; the
  expanded header title uses the same `PHUI.Fonts.TITLE` token.
- In-combat: bag group, tabs, `+` use secure overlays like the existing
  combat-safe toggle.

## Bag APIs actually used (feature-detected, not hardcoded)
- Reagent slot: `Enum.BagIndex.ReagentBag` (nil on clients without it).
  **Not verified against the installed Forever client** - Blizzard UI
  source is not on disk here. Run `/pockets debug bags` on Forever and
  record `reagentBagID`, `scannedBagIDs`, and each bag's `itemClass`.
- Bag type: bag item `classID/subClassID` via `C_Item.GetItemInfoInstant`
  (11 = quiver/ammo; 1 + subclass = soul/herbs/enchanting/engineering/gems/
  mining/skinning(leatherworking)/inscription/fishing/cooking). Falls back
  to the existing family-mask ammo check. Unknown bags stay "general".
- Dedicated reagent slot is always labelled `Reagents`.

## Deviations / notes
- The TDD's 560px/17px-font numbers did not match pH's real HUD
  (`ph/UI_HUD.lua`: 266 collapsed / 340 expanded, 20px buttons). Spacing
  follows the approved mockup (12px/4px padding, 20px icons) at 340px, the
  narrowest pH width that fits five Recent icons with that padding. Width
  and button size are read from PHUI. Section gap is 8px (mockup: 12) to fit.
- The `›` chevron is a Blizzard arrow texture (title font glyph coverage is
  unreliable on this client).
- Recent icons fill left to right inside a right-anchored 176px strip.
- Specialized tab icon is the equipped bag item's own icon.
- Old Glance geometry tests (tall layout, Ammo row, `>>`) were removed;
  new coverage is in `Tests/PocketsGlanceTests.lua`.

## Not yet verified in game
Everything: layout at several UI scales, combat open of tabs, reagent-bag
detection on Forever, mixed profession bags.
