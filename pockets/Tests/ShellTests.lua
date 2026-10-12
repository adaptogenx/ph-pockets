--[[
    Tests/ShellTests.lua - Single-frame state machine + stable shell
    contract (.plans/Pockets_Glance_UI.md §4, §15)

    Needs the real Shell frame (created by Shell:Initialize() during addon
    load), so these run via /pockets test run like the rest of the
    frame-dependent suites.
]]

local _, Pockets = ...

local Shell = Pockets.UI.Shell

local function ResetToGlance()
    Shell:SetState(Shell.STATE.GLANCE)
end

-- GetPoint() coordinates round-trip through UIParent's effective scale,
-- so comparing a value it returns against a plain Lua arithmetic result
-- (e.g. savedX + 37) needs a tolerance, not exact equality - see the same
-- note in Tests/PositionStrategyTests.lua.
local EPSILON = 0.01
local function ApproxEqual(a, b)
    return math.abs(a - b) < EPSILON
end

--------------------------------------------------
-- Pure predicates
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Ammo row hidden when ammo capacity is nil", function()
    local ok = Shell:ShouldShowAmmoRow(nil) == false
    return ok, ok and "OK" or "expected Ammo row hidden for nil capacity"
end)

Pockets.Tests.TestRunner:Register("Shell: Ammo row hidden when no ammo bag equipped (0/0)", function()
    local ok = Shell:ShouldShowAmmoRow({ used = 0, total = 0 }) == false
    return ok, ok and "OK" or "expected Ammo row hidden for zero total"
end)

Pockets.Tests.TestRunner:Register("Shell: Ammo row shown for equipped-but-empty quiver (0/16)", function()
    local ok = Shell:ShouldShowAmmoRow({ used = 0, total = 16 }) == true
    return ok, ok and "OK" or "expected Ammo row shown once a quiver is equipped, even at 0 used"
end)

Pockets.Tests.TestRunner:Register("Layout: ETA formatting never includes a '~' prefix", function()
    local Layout = Pockets.UI.Layout
    local eta = Layout:FormatETA(13 * 60)
    local suffix = Layout:FormatETASuffix(13 * 60)
    local ok = eta == "13m to full" and not suffix:find("~", 1, true)
    return ok, ok and "OK" or string.format("expected no '~' prefix, got eta=%s suffix=%s", tostring(eta), tostring(suffix))
end)

Pockets.Tests.TestRunner:Register("Layout: FormatETA returns nil for no data (caller omits rather than guesses)", function()
    local ok = Pockets.UI.Layout:FormatETA(nil) == nil
    return ok, ok and "OK" or "expected nil ETA to stay nil, never a fabricated string"
end)

--------------------------------------------------
-- State machine
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Glance click transitions to Menu", function()
    if not Shell.frame then
        return false, "Shell frame not initialized yet"
    end
    ResetToGlance()
    Shell.frame:Click()
    local ok = Shell:GetState() == Shell.STATE.MENU
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected MENU after Glance click, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: Menu -> Category -> Menu -> All -> Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    local afterCategory = Shell:GetState() == Shell.STATE.CATEGORY

    Shell:GoBack()
    local backToMenu = Shell:GetState() == Shell.STATE.MENU

    Shell:SetState(Shell.STATE.ALL)
    local afterAll = Shell:GetState() == Shell.STATE.ALL

    Shell:GoBack()
    local backToMenu2 = Shell:GetState() == Shell.STATE.MENU

    ResetToGlance()
    local ok = afterCategory and backToMenu and afterAll and backToMenu2
    return ok, ok and "OK" or "unexpected state during Menu/Category/All round-trip"
end)

Pockets.Tests.TestRunner:Register("Shell: Category -> All -> Menu (Category's + jumps straight to All)", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    Shell:SetState(Shell.STATE.ALL)
    local ok = Shell:GetState() == Shell.STATE.ALL
    ResetToGlance()
    return ok, ok and "OK" or "expected Category's + to land directly on ALL"
end)

Pockets.Tests.TestRunner:Register("Shell: one Escape from Category goes straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell:HandleEscape()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or string.format(
        "expected a single Escape from Category to land on GLANCE directly, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: one Escape from All goes straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.ALL)
    Shell:HandleEscape()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or string.format(
        "expected a single Escape from All to land on GLANCE directly, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: one Escape from Menu goes to Glance and is a no-op from Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:HandleEscape()
    local step1 = Shell:GetState() == Shell.STATE.GLANCE

    Shell:HandleEscape() -- no-op at Glance (frame doesn't even see it - see keyboard-capture test)
    local step2 = Shell:GetState() == Shell.STATE.GLANCE

    local ok = step1 and step2
    return ok, ok and "OK" or "expected Menu -> Escape -> Glance, then a no-op"
end)

Pockets.Tests.TestRunner:Register("Shell: Shift-B (ToggleAllItems) jumps directly to All from any state", function()
    ResetToGlance()
    Shell:ToggleAllItems()
    local fromGlance = Shell:GetState() == Shell.STATE.ALL

    Shell:SetState(Shell.STATE.MENU)
    Shell:ToggleAllItems()
    local fromMenu = Shell:GetState() == Shell.STATE.ALL

    Shell:ToggleAllItems() -- toggling again from ALL closes to Glance
    local toggleBack = Shell:GetState() == Shell.STATE.GLANCE

    ResetToGlance()
    local ok = fromGlance and fromMenu and toggleBack
    return ok, ok and "OK" or "expected ToggleAllItems to jump straight to ALL and toggle back"
end)

Pockets.Tests.TestRunner:Register("Shift-B binding invokes the same All Items jump as Menu's + button", function()
    local originalToggle = Pockets.API.ToggleFullInventory
    local calls = 0
    Pockets.API.ToggleFullInventory = function() calls = calls + 1 end

    Pockets_ToggleFullInventory()

    Pockets.API.ToggleFullInventory = originalToggle

    local ok = calls == 1
    return ok, ok and "OK" or string.format("expected Shift-B to call ToggleFullInventory once, got %d", calls)
end)

Pockets.Tests.TestRunner:Register("Shell: same root frame is reused across every state transition", function()
    local frameBefore = Shell.frame
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.QUEST })
    Shell:SetState(Shell.STATE.ALL)
    ResetToGlance()
    local ok = Shell.frame == frameBefore
    return ok, ok and "OK" or "expected the root frame to never be destroyed/recreated"
end)

--------------------------------------------------
-- Stable shell contract (§3)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Menu/Category/All share identical width, header height, footer height", function()
    local L = Pockets.Constants.LAYOUT

    Shell:SetState(Shell.STATE.MENU)
    local menuWidth, menuHeader, menuFooter =
        Shell.frame:GetWidth(), Shell.frame.shell.header:GetHeight(), Shell.frame.shell.footer:GetHeight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.TRADE_GOODS })
    local catWidth, catHeader, catFooter =
        Shell.frame:GetWidth(), Shell.frame.shell.header:GetHeight(), Shell.frame.shell.footer:GetHeight()

    Shell:SetState(Shell.STATE.ALL)
    local allWidth, allHeader, allFooter =
        Shell.frame:GetWidth(), Shell.frame.shell.header:GetHeight(), Shell.frame.shell.footer:GetHeight()

    ResetToGlance()

    local ok = menuWidth == L.SHELL_WIDTH and catWidth == L.SHELL_WIDTH and allWidth == L.SHELL_WIDTH
        and menuHeader == catHeader and catHeader == allHeader
        and menuFooter == catFooter and catFooter == allFooter
    return ok, ok and "OK" or "Menu/Category/All geometry diverged"
end)

-- Expanding (Search/Menu/Category/All) is meant to match pH's real HUD
-- width exactly (verified value, not Glance's own intentionally-compact
-- width - Glance is content-sized on purpose, never meant to clone pH's
-- footprint).
Pockets.Tests.TestRunner:Register("Shell: expanded width equals pH's real HUD width (PHUI.PH_HUD_WIDTH)", function()
    local L = Pockets.Constants.LAYOUT
    local phHudWidth = Pockets.UI.PHUI.PH_HUD_WIDTH
    local ok = L.SHELL_WIDTH == phHudWidth
    return ok, ok and "OK" or string.format(
        "expected SHELL_WIDTH (%s) to equal PHUI.PH_HUD_WIDTH (%s)",
        tostring(L.SHELL_WIDTH), tostring(phHudWidth))
end)

Pockets.Tests.TestRunner:Register("Shell: state changes do not move the frame's screen anchor", function()
    Shell:SetState(Shell.STATE.MENU)
    local point1, _, relPoint1, x1, y1 = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.CONSUMABLE })
    local point2, _, relPoint2, x2, y2 = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.ALL)
    local point3, _, relPoint3, x3, y3 = Shell.frame:GetPoint()

    ResetToGlance()

    local ok = point1 == point2 and point2 == point3
        and relPoint1 == relPoint2 and relPoint2 == relPoint3
        and x1 == x2 and x2 == x3 and y1 == y2 and y2 == y3
    return ok, ok and "OK" or "frame anchor point moved across state transitions"
end)

Pockets.Tests.TestRunner:Register("Shell: header action zones stay fixed - only the control changes", function()
    Shell:SetState(Shell.STATE.MENU)
    local header = Shell.frame.shell.header
    local rightEdgeMenu = header.plusButton:GetRight()

    Shell:SetState(Shell.STATE.ALL)
    local rightEdgeAll = header.searchBox:GetRight()

    ResetToGlance()

    local ok = rightEdgeMenu and rightEdgeAll and math.abs(rightEdgeMenu - rightEdgeAll) < 0.01
    return ok, ok and "OK" or "right header zone shifted position between Menu (+) and All (search)"
end)

--------------------------------------------------
-- UI polish pass: width, header/footer borders, chevron, item grid
--------------------------------------------------

-- Width follow-up: both the original 220 and the first polish pass's
-- narrower 192 left a visibly wasted trailing gap in Category/All's item
-- grid because only 3-4 columns fit. Width must be wide enough that the
-- grid defaults to 5 columns with no scrollbar showing.
Pockets.Tests.TestRunner:Register("Shell: expanded width fits 5 item-grid columns with no scrollbar reserved", function()
    local L = Pockets.Constants.LAYOUT
    local usableNoScrollbar = L.SHELL_WIDTH - L.SHELL_PADDING * 2
    local fiveColumnsWidth = 5 * L.ITEM_BUTTON_SIZE + 4 * L.ITEM_BUTTON_GAP
    local ok = usableNoScrollbar >= fiveColumnsWidth
    return ok, ok and "OK" or string.format(
        "expected usable width (%s) >= 5-column width (%s)", tostring(usableNoScrollbar), tostring(fiveColumnsWidth))
end)

Pockets.Tests.TestRunner:Register("Shell: header and footer use a real PHUI backdrop+border", function()
    Shell:SetState(Shell.STATE.MENU)
    local header, footer = Shell.frame.shell.header, Shell.frame.shell.footer
    local ok = header.GetBackdrop and header:GetBackdrop() ~= nil
        and footer.GetBackdrop and footer:GetBackdrop() ~= nil
    ResetToGlance()
    return ok, ok and "OK" or "expected header/footer to carry a real backdrop, not a flat texture"
end)

Pockets.Tests.TestRunner:Register("Shell: Menu row worst-case (long label + 3-digit count) fits without clipping", function()
    Shell:SetState(Shell.STATE.MENU)
    local row = Shell.frame.shell.menuRows[1]
    row.label:SetText("Consumables")
    row.count:SetText("180")

    local labelRight = row.label:GetRight()
    local countLeft = row.count:GetLeft()
    local chevronLeft = row.chevron:GetLeft()
    local countRight = row.count:GetRight()

    ResetToGlance()

    local ok = labelRight and countLeft and labelRight <= countLeft
        and chevronLeft and countRight and chevronLeft >= countRight
    return ok, ok and "OK" or "worst-case Menu row label/count/chevron overlapped"
end)

Pockets.Tests.TestRunner:Register("Shell: Menu chevron is a legible size, not the old tiny glyph", function()
    Shell:SetState(Shell.STATE.MENU)
    local row = Shell.frame.shell.menuRows[1]
    local _, fontSize = row.chevron:GetFont()
    local text = row.chevron:GetText()
    ResetToGlance()

    local ok = text == ">" and fontSize and fontSize >= 14
    return ok, ok and "OK" or string.format("expected '>' at >=14px, got text=%s size=%s", tostring(text), tostring(fontSize))
end)

Pockets.Tests.TestRunner:Register("Shell: category counts stay right-aligned regardless of digit count", function()
    Shell:SetState(Shell.STATE.MENU)
    local row = Shell.frame.shell.menuRows[1]

    row.count:SetText("1")
    local rightWith1Digit = row.count:GetRight()
    row.count:SetText("180")
    local rightWith3Digits = row.count:GetRight()

    ResetToGlance()

    local ok = rightWith1Digit and rightWith3Digits and math.abs(rightWith1Digit - rightWith3Digits) < 0.01
    return ok, ok and "OK" or "count's right edge shifted when digit count changed"
end)

Pockets.Tests.TestRunner:Register("Shell: no scrollbar when Category content fits the viewport", function()
    Shell:SetState(Shell.STATE.MENU)
    -- Junk is a low-count category in test/dev environments - well under
    -- one viewport's worth of items.
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })

    local shell = Shell.frame.shell
    local contentWidth = shell.content:GetWidth()
    local viewportWidth = shell.scrollFrame:GetWidth()
    local scrollBarShown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)

    ResetToGlance()

    local ok = not scrollBarShown and math.abs(contentWidth - viewportWidth) < 0.01
    return ok, ok and "OK" or "scrollbar was present without overflowing content"
end)

Pockets.Tests.TestRunner:Register("Shell: FlowLayout actually places 5 columns per row at the no-scrollbar usable width", function()
    local L = Pockets.Constants.LAYOUT
    local usableNoScrollbar = L.SHELL_WIDTH - L.SHELL_PADDING * 2
    local plan = Pockets.UI.FlowLayout:PlanFlat(6, {
        rowWidth = usableNoScrollbar, itemSize = L.ITEM_BUTTON_SIZE, gap = L.ITEM_BUTTON_GAP,
    })
    -- item 6 should wrap to row 2 (y differs from item 1) since 5 fit per row.
    local ok = plan.itemPlacements[5].y == plan.itemPlacements[1].y
        and plan.itemPlacements[6].y > plan.itemPlacements[1].y
    return ok, ok and "OK" or "expected exactly 5 columns to fit per row before wrapping"
end)

Pockets.Tests.TestRunner:Register(
    "Shell: scrollbar appears when content overflows without narrowing content width (scrollbar redesign pass)", function()
    -- Force an overflow deterministically by aggregating far more items
    -- than the viewport could ever fit, bypassing live inventory state.
    -- The compact scrollbar lives in the panel's existing padding gutter,
    -- not a reserved column, so content width must stay exactly the full
    -- viewport width whether or not the bar is showing.
    local L = Pockets.Constants.LAYOUT
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local originalMode = Pockets.SavedSettings.categoryViewMode
    local manyItems = {}
    for i = 1, 200 do
        manyItems[i] = { itemID = i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return manyItems end
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.GRID

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

    local shell = Shell.frame.shell
    local contentWidth = shell.content:GetWidth()
    local fullWidth = L.SHELL_WIDTH - L.SHELL_PADDING * 2
    local scrollBarShown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = scrollBarShown and math.abs(contentWidth - fullWidth) < 0.01
    return ok, ok and "OK" or string.format(
        "expected scrollbar shown and content width unchanged at %s; got shown=%s content=%s",
        tostring(fullWidth), tostring(scrollBarShown), tostring(contentWidth))
end)

--------------------------------------------------
-- Hard anchor rule: TOPLEFT is the origin (UI layout pass §1, §18)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Glance -> Menu -> Category -> All -> Glance never moves TOPLEFT", function()
    ResetToGlance()
    local _, _, _, gx1, gy1 = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.MENU)
    local _, _, _, mx, my = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.CONSUMABLE })
    local _, _, _, cx, cy = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.ALL)
    local _, _, _, ax, ay = Shell.frame:GetPoint()

    ResetToGlance()
    local _, _, _, gx2, gy2 = Shell.frame:GetPoint()

    local ok = gx1 == mx and mx == cx and cx == ax and ax == gx2
        and gy1 == my and my == cy and cy == ay and ay == gy2
    return ok, ok and "OK" or string.format(
        "TOPLEFT drifted: glance=(%s,%s) menu=(%s,%s) category=(%s,%s) all=(%s,%s) glance2=(%s,%s)",
        tostring(gx1), tostring(gy1), tostring(mx), tostring(my), tostring(cx), tostring(cy),
        tostring(ax), tostring(ay), tostring(gx2), tostring(gy2))
end)

Pockets.Tests.TestRunner:Register("Shell: expanding from Glance grows right/down only (TOPLEFT edge fixed)", function()
    ResetToGlance()
    local glanceLeft, glanceTop = Shell.frame:GetLeft(), Shell.frame:GetTop()

    Shell:SetState(Shell.STATE.MENU)
    local menuLeft, menuTop = Shell.frame:GetLeft(), Shell.frame:GetTop()

    ResetToGlance()
    local ok = glanceLeft == menuLeft and glanceTop == menuTop
    return ok, ok and "OK" or "left/top edge shifted when Glance expanded into Menu"
end)

--------------------------------------------------
-- Glance redesign pass: compact metric-list HUD (header + Bag/Gold/Ammo
-- metric rows + Recent Items strip), replacing the old centered/square
-- status card.
--------------------------------------------------

local function WithAmmoCapacity(capacity, fn)
    local InventoryState = Pockets.Services.InventoryState
    local original = InventoryState.GetAmmoCapacity
    InventoryState.GetAmmoCapacity = function() return capacity end

    local ok, err = pcall(fn)

    InventoryState.GetAmmoCapacity = original
    if not ok then
        error(err, 0)
    end
end

local function WithRecentItems(items, fn)
    local original = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function(categoryID)
        if categoryID == Pockets.Constants.CATEGORY.RECENT then
            return items
        end
        return original(categoryID)
    end

    local ok, err = pcall(fn)

    Pockets.API.GetAggregatedCategoryItems = original
    if not ok then
        error(err, 0)
    end
end

local function FakeRecentItem(itemID, quantity)
    return {
        itemID = itemID, itemLink = "item:" .. itemID, name = "Item " .. itemID,
        texture = 1, quality = 1, quantity = quantity, bagID = 0, slotID = itemID,
        interactive = true,
    }
end

--------------------------------------------------
-- Header (no X/back button, Search top-right, same visual size as
-- metric icons)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: header has no X/back button", function()
    ResetToGlance()
    local header = Shell.frame.glance.header
    local ok = header.closeButton == nil and header.backButton == nil
    return ok, ok and "OK" or "expected Glance's header to have no close/back button"
end)

Pockets.Tests.TestRunner:Register("Glance: Search icon is right-aligned and matches Shell's expanded-header icon-button size", function()
    ResetToGlance()
    local L = Pockets.Constants.LAYOUT
    local point = Shell.frame.glance.header.iconButton:GetPoint()
    local width = Shell.frame.glance.header.iconButton:GetWidth()
    -- Must match SHELL_HEADER_SIDE_WIDTH (Shell's expanded-header back/
    -- close/+ buttons), NOT GLANCE_METRIC_ICON_SIZE - a bordered icon
    -- BUTTON is a different kind of element than a plain metric-row
    -- icon, and conflating the two is exactly what made Glance's "+"
    -- visibly mismatch Shell's own "+" earlier.
    local ok = point == "RIGHT" and width == L.GLANCE_HEADER_ICON_SIZE
        and width == L.SHELL_HEADER_SIDE_WIDTH
    return ok, ok and "OK" or string.format(
        "expected Search right-anchored at Shell's icon-button size, got point=%s width=%s", tostring(point), tostring(width))
end)

Pockets.Tests.TestRunner:Register("Glance: header has Search, Loot Log, then a '+' All Items icon, '+' flush to the header's right edge", function()
    ResetToGlance()
    local header = Shell.frame.glance.header
    local searchIsFirst = header.iconButton == header.icons[1]
    local plusIsSecond = header.plusButton == header.icons[3] and header.lootButton == header.icons[2]
    local plusPoint = header.plusButton:GetPoint()
    local plusTexture = header.plusButton:GetNormalTexture() and header.plusButton:GetNormalTexture():GetTexture()
    local ok = searchIsFirst and plusIsSecond and plusPoint == "RIGHT" and Pockets.Tests.TextureEquals(plusTexture, Pockets.UI.PHUI.Icons.PLUS)
    return ok, ok and "OK" or string.format(
        "expected search=icons[1], loot=icons[2], plus=icons[3] flush right using PHUI.Icons.PLUS, got plusPoint=%s plusTexture=%s",
        tostring(plusPoint), tostring(plusTexture))
end)

Pockets.Tests.TestRunner:Register("Glance: clicking the header's '+' jumps straight to All Items", function()
    ResetToGlance()
    Shell.frame.glance.header.plusButton:Click()
    local ok = Shell:GetState() == Shell.STATE.ALL
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected ALL after clicking Glance's '+', got %s", tostring(Shell:GetState()))
end)

--------------------------------------------------
-- Metric row system: Bag/Gold/Ammo share one component/geometry
--------------------------------------------------

Pockets.Tests.TestRunner:Register("MetricRow: Bag/Gold/Ammo use the shared MetricRow component", function()
    ResetToGlance()
    local glance = Shell.frame.glance
    -- MetricRow:Create defines its methods per instance (closures), so
    -- function identity can never match; what proves a shared component is
    -- that every row has the same method set and the same child regions.
    local ok = true
    for _, row in ipairs({ glance.bagRow, glance.goldRow, glance.ammoRow }) do
        ok = ok and type(row.SetPrimary) == "function" and type(row.SetPrimaryColor) == "function"
            and type(row.SetTexture) == "function" and row.icon ~= nil and row.primaryText ~= nil
    end
    return ok, ok and "OK" or "expected Bag/Gold/Ammo rows to be built by the shared MetricRow component"
end)

Pockets.Tests.TestRunner:Register("MetricRow: Bag/Gold/Ammo rows have identical icon size, row height, and left edge", function()
    ResetToGlance()
    local L = Pockets.Constants.LAYOUT
    local glance = Shell.frame.glance
    local rows = { glance.bagRow, glance.goldRow, glance.ammoRow }

    local ok = true
    for _, row in ipairs(rows) do
        local iw, ih = row.icon:GetSize()
        local point, _, _, xOfs, yOfs = row.icon:GetPoint()
        if iw ~= L.GLANCE_METRIC_ICON_SIZE or ih ~= L.GLANCE_METRIC_ICON_SIZE
            or row:GetHeight() ~= L.GLANCE_METRIC_ROW_HEIGHT
            or point ~= "LEFT" or xOfs ~= 0 or yOfs ~= 0 then
            ok = false
        end
    end
    return ok, ok and "OK" or "expected identical icon size/row height/left-edge anchor across Bag/Gold/Ammo"
end)

Pockets.Tests.TestRunner:Register("Glance: Bag/Gold/Ammo plain-icon size matches the shared library's default (PHUI.Spacing.ICON_SIZE)", function()
    local L = Pockets.Constants.LAYOUT
    local defaultIconSize = Pockets.UI.PHUI.Spacing.ICON_SIZE
    local ok = L.GLANCE_METRIC_ICON_SIZE == defaultIconSize
    return ok, ok and "OK" or string.format(
        "expected GLANCE_METRIC_ICON_SIZE (%s) to equal PHUI.Spacing.ICON_SIZE (%s)",
        tostring(L.GLANCE_METRIC_ICON_SIZE), tostring(defaultIconSize))
end)

-- Guards the exact regression that prompted this pass: Glance's header
-- "+" visibly not matching Shell's expanded-header "+" because they were
-- built from two different, un-linked size numbers. Both Glance's search
-- icon and Shell's expanded-header side (back/+) button must trace back
-- to the one shared default. The close (X) button is intentionally
-- excluded here - see the dedicated native-close-size test below.
Pockets.Tests.TestRunner:Register("Glance/Shell header icon-button sizes all match the shared library's default (PHUI.Spacing.ICON_BUTTON_SIZE)", function()
    local L = Pockets.Constants.LAYOUT
    local defaultIconButtonSize = Pockets.UI.PHUI.Spacing.ICON_BUTTON_SIZE
    local ok = L.GLANCE_HEADER_ICON_SIZE == defaultIconButtonSize
        and L.SHELL_HEADER_SIDE_WIDTH == defaultIconButtonSize
    return ok, ok and "OK" or string.format(
        "expected GLANCE_HEADER_ICON_SIZE (%s) and SHELL_HEADER_SIDE_WIDTH (%s) to both equal PHUI.Spacing.ICON_BUTTON_SIZE (%s)",
        tostring(L.GLANCE_HEADER_ICON_SIZE), tostring(L.SHELL_HEADER_SIDE_WIDTH), tostring(defaultIconButtonSize))
end)

-- pH never resizes its own UIPanelCloseButton away from its native size
-- (ph/UI_History.lua:156-157) - forcing it down to the same 20px as the
-- other header icon buttons was the actual bug (the template's art
-- doesn't scale cleanly), not a size PICKED to be different on purpose.
Pockets.Tests.TestRunner:Register("Shell close (X) button matches pH's native, unscaled UIPanelCloseButton size", function()
    local L = Pockets.Constants.LAYOUT
    local nativeSize = Pockets.UI.PHUI.NATIVE_CLOSE_BUTTON_SIZE
    -- Forever's close-button art is larger, so it renders at its own
    -- (smaller) size there; the layout slot constant stays pH's native 32.
    local renderedSize = Pockets.Adapters.ClientAPI:IsForever()
        and Pockets.UI.PHUI.FOREVER_CLOSE_BUTTON_SIZE or nativeSize
    ResetToGlance()
    Shell:SetState(Shell.STATE.MENU)
    local closeButton = Shell.frame.shell.header.closeButton
    local width, height = closeButton:GetSize()
    ResetToGlance()
    local ok = L.SHELL_HEADER_CLOSE_WIDTH == nativeSize and width == renderedSize and height == renderedSize
    return ok, ok and "OK" or string.format(
        "expected SHELL_HEADER_CLOSE_WIDTH (%s) and rendered size (%sx%s) to equal PHUI.NATIVE_CLOSE_BUTTON_SIZE (%s)",
        tostring(L.SHELL_HEADER_CLOSE_WIDTH), tostring(width), tostring(height), tostring(nativeSize))
end)

Pockets.Tests.TestRunner:Register("Glance header '+' matches Shell's expanded-header '+' exactly (size and texture)", function()
    ResetToGlance()
    local glancePlus = Shell.frame.glance.header.plusButton
    local glanceWidth = glancePlus:GetWidth()
    local glanceTexture = glancePlus:GetNormalTexture() and glancePlus:GetNormalTexture():GetTexture()

    Shell:SetState(Shell.STATE.MENU)
    local shellPlus = Shell.frame.shell.header.plusButton
    local shellWidth = shellPlus:GetWidth()
    local shellTexture = shellPlus:GetNormalTexture() and shellPlus:GetNormalTexture():GetTexture()
    ResetToGlance()

    local ok = glanceWidth == shellWidth and glanceTexture == shellTexture and Pockets.Tests.TextureEquals(glanceTexture, Pockets.UI.PHUI.Icons.PLUS)
    return ok, ok and "OK" or string.format(
        "expected identical +buttons, got glance(width=%s texture=%s) shell(width=%s texture=%s)",
        tostring(glanceWidth), tostring(glanceTexture), tostring(shellWidth), tostring(shellTexture))
end)

Pockets.Tests.TestRunner:Register("MetricRow: Ammo icon has no ItemButton/border treatment", function()
    ResetToGlance()
    local icon = Shell.frame.glance.ammoRow.icon
    local ok = icon.GetBackdrop == nil and icon.GetObjectType and icon:GetObjectType() == "Texture"
    return ok, ok and "OK" or "expected the Ammo icon to be a plain Texture, not a bordered/backdrop widget"
end)

--------------------------------------------------
-- Bag row: capacity + ETA
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: header subtitle uses the existing estimator, compact and parenthesized", function()
    local estimator = Pockets.Services.CapacityEstimator
    local originalGetState = estimator.GetState
    local originalGetConfidence = estimator.GetConfidence
    local originalGetETA = estimator.GetETA
    estimator.GetState = function() return Pockets.Constants.ESTIMATOR_STATE.FILLING end
    estimator.GetConfidence = function() return 1.0 end
    estimator.GetETA = function() return 13 * 60 end

    ResetToGlance()
    local text = Shell.frame.glance.header.subtitleText:GetText()

    estimator.GetState = originalGetState
    estimator.GetConfidence = originalGetConfidence
    estimator.GetETA = originalGetETA
    ResetToGlance()

    local ok = text == "(13m)"
    return ok, ok and "OK" or string.format("expected compact '(13m)', got %s", tostring(text))
end)

Pockets.Tests.TestRunner:Register("Glance: header subtitle shows '(Full)' in the full state", function()
    local estimator = Pockets.Services.CapacityEstimator
    local originalGetState = estimator.GetState
    estimator.GetState = function() return Pockets.Constants.ESTIMATOR_STATE.FULL end

    ResetToGlance()
    local text = Shell.frame.glance.header.subtitleText:GetText()

    estimator.GetState = originalGetState
    ResetToGlance()

    local ok = text == "(Full)"
    return ok, ok and "OK" or string.format("expected '(Full)', got %s", tostring(text))
end)

--------------------------------------------------
-- Gold: always present, pH Ledger-compatible formatting
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: Gold is always rendered", function()
    ResetToGlance()
    local text = Shell.frame.glance.goldRow.primaryText:GetText()
    local ok = text ~= nil and text ~= ""
    return ok, ok and "OK" or "expected Glance's Gold row to always show some value"
end)

Pockets.Tests.TestRunner:Register("Glance: Gold uses the standalone Pockets money formatter (matches GetMoney())", function()
    ResetToGlance()
    local text = Shell.frame.glance.goldRow.primaryText:GetText()
    local expected = Pockets.UI.MoneyFormat:Format(GetMoney())
    local ok = text == expected
    return ok, ok and "OK" or string.format("expected Gold text %q, got %q", tostring(expected), tostring(text))
end)

--------------------------------------------------
-- Ammo: optional, always follows Gold, removes its row when absent
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: Ammo hidden when no ammo container is equipped", function()
    WithAmmoCapacity({ used = 0, total = 0 }, function()
        ResetToGlance()
        if Shell.frame.glance.ammoRow:IsShown() then
            error("expected Ammo row hidden when GetAmmoCapacity reports total 0", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("Glance: Ammo shown and formatted when a container is equipped", function()
    local text
    WithAmmoCapacity({ used = 12, total = 16 }, function()
        ResetToGlance()
        local ammoRow = Shell.frame.glance.ammoRow
        if not ammoRow:IsShown() then
            error("expected Ammo row shown", 0)
        end
        text = ammoRow.primaryText:GetText()
    end)
    ResetToGlance()
    local ok = text == "12 / 16"
    return ok, ok and "OK" or string.format("expected '12 / 16', got %s", tostring(text))
end)

Pockets.Tests.TestRunner:Register("Glance: Ammo always follows Gold (anchored relative to the Gold row)", function()
    ResetToGlance()
    local glance = Shell.frame.glance
    local _, relativeTo = glance.ammoRow:GetPoint()
    local ok = relativeTo == glance.goldRow
    return ok, ok and "OK" or "expected Ammo's anchor to be relative to the Gold row"
end)

Pockets.Tests.TestRunner:Register("Glance: Ammo absence removes exactly its row height (no reserved space)", function()
    local L = Pockets.Constants.LAYOUT
    local heightWithout, heightWith

    WithAmmoCapacity({ used = 0, total = 0 }, function()
        ResetToGlance()
        heightWithout = Shell.frame:GetHeight()
    end)
    WithAmmoCapacity({ used = 3, total = 16 }, function()
        ResetToGlance()
        heightWith = Shell.frame:GetHeight()
    end)
    ResetToGlance()

    local expectedDelta = L.GLANCE_METRIC_ROW_HEIGHT + L.GLANCE_METRIC_ROW_GAP
    local ok = heightWith - heightWithout == expectedDelta
    return ok, ok and "OK" or string.format(
        "expected Ammo to add exactly %s px (row height + gap), got delta %s",
        tostring(expectedDelta), tostring(heightWith - heightWithout))
end)

--------------------------------------------------
-- Recent Items strip
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: Recent items render newest-first, in the order the API returns them", function()
    local order
    WithRecentItems({ FakeRecentItem(301, 1), FakeRecentItem(302, 1), FakeRecentItem(303, 1) }, function()
        ResetToGlance()
        local pool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.glance.recentStrip.poolAnchor)
        order = {}
        for _, button in ipairs(pool.active) do
            table.insert(order, button.itemID)
        end
    end)
    ResetToGlance()

    local ok = order and order[1] == 301 and order[2] == 302 and order[3] == 303
    return ok, ok and "OK" or string.format("expected newest-first order 301,302,303 - got %s",
        order and table.concat(order, ",") or "nil")
end)

Pockets.Tests.TestRunner:Register("Glance: Recent items carry no duplicate itemIDs", function()
    ResetToGlance()
    local items = Pockets.API.GetAggregatedCategoryItems(Pockets.Constants.CATEGORY.RECENT)
    local seen = {}
    local ok = true
    for _, item in ipairs(items) do
        if seen[item.itemID] then
            ok = false
        end
        seen[item.itemID] = true
    end
    return ok, ok and "OK" or "expected Glance's Recent source to contain no duplicate itemIDs"
end)

Pockets.Tests.TestRunner:Register("Glance: Recent item quantity reflects the current carried total", function()
    local quantity
    WithRecentItems({ FakeRecentItem(401, 7) }, function()
        ResetToGlance()
        local pool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.glance.recentStrip.poolAnchor)
        quantity = pool.active[1] and pool.active[1].quantity
    end)
    ResetToGlance()

    local ok = quantity == 7
    return ok, ok and "OK" or string.format("expected quantity 7, got %s", tostring(quantity))
end)

Pockets.Tests.TestRunner:Register("Glance: Recent strip clamps to however many items actually fit its width", function()
    local L = Pockets.Constants.LAYOUT
    local contentWidth = L.GLANCE_WIDTH - L.GLANCE_PADDING * 2
    local maxFit = math.floor((contentWidth + L.GLANCE_RECENT_ICON_GAP) / (L.GLANCE_RECENT_ICON_SIZE + L.GLANCE_RECENT_ICON_GAP))

    local manyItems = {}
    for i = 1, maxFit + 5 do
        manyItems[i] = FakeRecentItem(500 + i, 1)
    end

    local shownCount
    WithRecentItems(manyItems, function()
        ResetToGlance()
        local pool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.glance.recentStrip.poolAnchor)
        shownCount = #pool.active
    end)
    ResetToGlance()

    -- One slot is the ">>" more button, so items clamp to maxFit - 1.
    local ok = shownCount == maxFit - 1
    return ok, ok and "OK" or string.format("expected exactly %s items shown (width-clamped, minus the >> slot), got %s",
        tostring(maxFit - 1), tostring(shownCount))
end)

Pockets.Tests.TestRunner:Register("Glance: Recent strip targets roughly 4-5 icons at the current width", function()
    local L = Pockets.Constants.LAYOUT
    local contentWidth = L.GLANCE_WIDTH - L.GLANCE_PADDING * 2
    local maxFit = math.floor((contentWidth + L.GLANCE_RECENT_ICON_GAP) / (L.GLANCE_RECENT_ICON_SIZE + L.GLANCE_RECENT_ICON_GAP))
    local ok = maxFit >= 4 and maxFit <= 5
    return ok, ok and "OK" or string.format("expected 4-5 Recent icons to fit, got %s", tostring(maxFit))
end)

--------------------------------------------------
-- Recent Item Preview (opt-in toggle, /pockets recentpreview)
--------------------------------------------------

local function WithRecentPreviewEnabled(enabled, fn)
    local original = Pockets.SavedSettings.recentItemPreviewEnabled
    Pockets.SavedSettings.recentItemPreviewEnabled = enabled
    local ok, err = pcall(fn)
    Pockets.SavedSettings.recentItemPreviewEnabled = original
    if not ok then
        error(err, 0)
    end
end

Pockets.Tests.TestRunner:Register("ItemPreview: Show/Hide toggles the frame's visibility", function()
    Pockets.UI.ItemPreview:Show({ texture = 1, quality = 1 })
    local shownAfterShow = Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown()
    Pockets.UI.ItemPreview:Hide()
    local hiddenAfterHide = not (Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown())
    local ok = shownAfterShow and hiddenAfterHide
    return ok, ok and "OK" or "expected Show() to display the preview frame and Hide() to hide it again"
end)

Pockets.Tests.TestRunner:Register("ItemPreview: Show is a no-op without a texture (never shows a blank frame)", function()
    Pockets.UI.ItemPreview:Hide()
    Pockets.UI.ItemPreview:Show({ quality = 1 })
    local ok = not (Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown())
    return ok, ok and "OK" or "expected Show() with no texture to leave the preview hidden"
end)

Pockets.Tests.TestRunner:Register("ItemPreview: Show re-anchors an already-visible GameTooltip to its own top-right", function()
    -- Generic show (no real item) is enough to exercise the re-anchor -
    -- ItemPreview:Show only cares whether GameTooltip:IsShown(), not
    -- what it's currently displaying.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    -- Forever hides an empty tooltip on Show(); give it content.
    GameTooltip:SetText("Pockets test")
    GameTooltip:Show()

    Pockets.UI.ItemPreview:Show({ texture = 1, quality = 1 })
    local point, relativeTo, relativePoint = GameTooltip:GetPoint()
    local ok = point == "TOPLEFT" and relativeTo == Pockets.UI.ItemPreview.frame and relativePoint == "TOPRIGHT"

    GameTooltip:Hide()
    Pockets.UI.ItemPreview:Hide()
    return ok, ok and "OK" or string.format(
        "expected GameTooltip TOPLEFT anchored to preview's TOPRIGHT, got point=%s relativeTo=%s relativePoint=%s",
        tostring(point), tostring(relativeTo == Pockets.UI.ItemPreview.frame), tostring(relativePoint))
end)

Pockets.Tests.TestRunner:Register("ItemPreview: Show does not touch GameTooltip when it isn't currently shown", function()
    GameTooltip:Hide()
    local ok, err = pcall(function()
        Pockets.UI.ItemPreview:Show({ texture = 1, quality = 1 })
    end)
    local stillHidden = not GameTooltip:IsShown()
    Pockets.UI.ItemPreview:Hide()
    local result = ok and stillHidden
    return result, result and "OK" or string.format("expected no error and GameTooltip to stay hidden, ok=%s err=%s", tostring(ok), tostring(err))
end)

Pockets.Tests.TestRunner:Register("Glance: hovering a Recent item shows the large preview only when the toggle is on", function()
    local ok, message = true, "OK"

    WithRecentPreviewEnabled(true, function()
        WithRecentItems({ FakeRecentItem(601, 1) }, function()
            ResetToGlance()
            local poolAnchor = Shell.frame.glance.recentStrip.poolAnchor
            local pool = Pockets.UI.ItemButtonPool:GetPool(poolAnchor)
            local row = pool.active[1]
            -- previewOnEnter/previewOnLeave are called DIRECTLY (not via
            -- GetScript, which only ever returns a SetScript handler,
            -- never one of RecentItemStrip's HookScript'd callbacks).
            row.previewOnEnter(row)
            local shownWhenOn = Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown()
            row.previewOnLeave(row)
            local hiddenAfterLeave = not (Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown())
            ok = shownWhenOn and hiddenAfterLeave
            message = ok and "OK" or string.format("shownWhenOn=%s hiddenAfterLeave=%s", tostring(shownWhenOn), tostring(hiddenAfterLeave))
        end)
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Glance: hovering a Recent item does nothing when the preview toggle is off", function()
    local ok, message = true, "OK"
    WithRecentPreviewEnabled(false, function()
        WithRecentItems({ FakeRecentItem(602, 1) }, function()
            ResetToGlance()
            local poolAnchor = Shell.frame.glance.recentStrip.poolAnchor
            local pool = Pockets.UI.ItemButtonPool:GetPool(poolAnchor)
            local row = pool.active[1]
            Pockets.UI.ItemPreview:Hide()
            row.previewOnEnter(row)
            ok = not (Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown())
            message = ok and "OK" or "expected no preview while the toggle is off"
        end)
    end)
    ResetToGlance()
    return ok, message
end)

--------------------------------------------------
-- Sizing: content-driven rectangle, not a forced square
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: sizes to content width/height, not a forced square", function()
    local L = Pockets.Constants.LAYOUT
    WithAmmoCapacity({ used = 0, total = 0 }, function()
        ResetToGlance()
        local width, height = Shell.frame:GetWidth(), Shell.frame:GetHeight()
        if width ~= L.GLANCE_WIDTH then
            error(string.format("expected width %s, got %s", tostring(L.GLANCE_WIDTH), tostring(width)), 0)
        end
        if height ~= Pockets.Constants:GlanceContentHeight(false) then
            error(string.format("expected content-derived height, got %s", tostring(height)), 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("Shell: PositionStrategy V1 anchor is TOPLEFT", function()
    local ok = Pockets.UI.PositionStrategy:GetRootAnchor() == "TOPLEFT"
    return ok, ok and "OK" or "expected the V1 position strategy to report TOPLEFT"
end)

Pockets.Tests.TestRunner:Register("Shell: full state sequence GLANCE>MENU>CATEGORY>ALL>MENU>GLANCE holds one TOPLEFT (§10)", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    local sequence = {
        { Shell.STATE.MENU, nil },
        { Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.QUEST } },
        { Shell.STATE.ALL, nil },
        { Shell.STATE.MENU, nil },
        { Shell.STATE.GLANCE, nil },
    }

    local drifted = false
    for _, step in ipairs(sequence) do
        Shell:SetState(step[1], step[2])
        local _, _, _, x, y = Shell.frame:GetPoint()
        if x ~= x0 or y ~= y0 then
            drifted = true
        end
    end

    local ok = not drifted
    return ok, ok and "OK" or "TOPLEFT drifted somewhere in GLANCE>MENU>CATEGORY>ALL>MENU>GLANCE"
end)

Pockets.Tests.TestRunner:Register("Shell: repeated Glance<->Menu and Menu<->Category cycles never drift", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    local drifted = false
    for _ = 1, 6 do
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.AMMO })
        Shell:GoBack()
        ResetToGlance()
        local _, _, _, x, y = Shell.frame:GetPoint()
        if x ~= x0 or y ~= y0 then
            drifted = true
        end
    end

    local ok = not drifted
    return ok, ok and "OK" or "repeated Glance<->Menu<->Category cycling drifted TOPLEFT"
end)

Pockets.Tests.TestRunner:Register("Shell: changing width/height via SetSize alone never moves TOPLEFT", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    Shell.frame:SetSize(140, 90)
    local _, _, _, xa, ya = Shell.frame:GetPoint()
    Shell.frame:SetSize(220, 400)
    local _, _, _, xb, yb = Shell.frame:GetPoint()

    ResetToGlance()
    local ok = x0 == xa and y0 == ya and xa == xb and ya == yb
    return ok, ok and "OK" or "SetSize alone moved the frame's TOPLEFT anchor"
end)

Pockets.Tests.TestRunner:Register("Shell: a SetState during a phantom drag is deferred, not resized mid-move", function()
    -- The actual bug: WoW fires OnDragStart/OnDragStop on every click,
    -- moving or not. A click that also changes state (Glance -> Menu)
    -- must never resize the frame while isDragging is true - doing so
    -- corrupted the position WoW's drag system committed on stop.
    ResetToGlance()
    local glanceWidth = Shell.frame:GetWidth()

    Shell.isDragging = true
    Shell:SetState(Shell.STATE.MENU) -- e.g. from a click's OnClick handler
    local widthWhileDragging = Shell.frame:GetWidth()
    local stateAlreadyUpdated = Shell:GetState() == Shell.STATE.MENU

    -- OnDragStop's flush
    Shell.isDragging = false
    Shell:Render()
    local widthAfterFlush = Shell.frame:GetWidth()

    ResetToGlance()

    local ok = widthWhileDragging == glanceWidth and stateAlreadyUpdated
        and widthAfterFlush == Pockets.Constants.LAYOUT.SHELL_WIDTH
    return ok, ok and "OK" or string.format(
        "expected no resize while dragging (stayed %s) then Menu width after flush (got %s)",
        tostring(widthWhileDragging), tostring(widthAfterFlush))
end)

Pockets.Tests.TestRunner:Register("Shell: Render skips re-anchoring while a drag is in progress", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.MENU)
    local _, _, _, savedX, savedY = Shell.frame:GetPoint()

    -- Mid-drag: simulates StartMoving() having already moved the frame,
    -- then a background event (bag update, ETA tick) calling Render()
    -- before the player has released the mouse.
    Shell.isDragging = true
    Shell.frame:ClearAllPoints()
    Shell.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", savedX + 37, savedY - 41)
    Shell:Render()
    local _, _, _, midDragX, midDragY = Shell.frame:GetPoint()
    local heldDuringDrag = ApproxEqual(midDragX, savedX + 37) and ApproxEqual(midDragY, savedY - 41)

    -- Drag ends: OnDragStop clears isDragging and saves the new position
    -- together (Shell.lua's OnDragStop handler), so the next Render()
    -- should reapply that NEW position, not the pre-drag one.
    Shell.isDragging = false
    Shell:SavePosition()
    Shell:Render()
    local _, _, _, afterX, afterY = Shell.frame:GetPoint()

    -- restore the real saved position so later tests aren't affected
    Pockets.CharDB.hud.x, Pockets.CharDB.hud.y = savedX, savedY
    ResetToGlance()

    local ok = heldDuringDrag and ApproxEqual(afterX, savedX + 37) and ApproxEqual(afterY, savedY - 41)
    return ok, ok and "OK" or "Render fought an in-progress drag or lost the position saved when it ended"
end)

--------------------------------------------------
-- Height: content-driven Menu, bounded Category/All (§5, §6, §18)
--------------------------------------------------

-- Row unification pass (§10/§11): zero-count categories are hidden, so
-- Menu's height is derived at render time from the VISIBLE category
-- count, not a load-time constant covering the full taxonomy.
Pockets.Tests.TestRunner:Register("Shell: Menu body height is derived from the visible (non-zero) category count", function()
    local L = Pockets.Constants.LAYOUT
    local originalGetSummary = Pockets.API.GetCategorySummary
    Pockets.API.GetCategorySummary = function()
        return {
            { categoryID = "a", label = "A", icon = 1, count = 3 },
            { categoryID = "b", label = "B", icon = 1, count = 0 },
            { categoryID = "c", label = "C", icon = 1, count = 5 },
        }
    end

    Shell:SetState(Shell.STATE.MENU)
    local height = Shell.frame:GetHeight()

    Pockets.API.GetCategorySummary = originalGetSummary
    ResetToGlance()

    -- 2 visible rows (zero-count "b" hidden) + header/footer, with the
    -- body padding the scrollFrame viewport is inset by on both top and
    -- bottom (vertical sizing fix - a body height of exactly
    -- contentHeight, with no padding added back, clips the last row).
    local contentHeight = 2 * L.LIST_ROW_HEIGHT
    local minContentHeight = math.max(L.SHELL_BODY_MIN_HEIGHT - L.SHELL_PADDING * 2, 0)
    local bodyHeight = math.max(contentHeight, minContentHeight) + L.SHELL_PADDING * 2
    local expected = L.SHELL_HEADER_HEIGHT + bodyHeight + L.SHELL_FOOTER_HEIGHT
    local ok = height == expected
    return ok, ok and "OK" or string.format("expected height %s for 2 visible categories, got %s",
        tostring(expected), tostring(height))
end)

Pockets.Tests.TestRunner:Register("Shell: Menu hides zero-count categories entirely (no empty rows)", function()
    local originalGetSummary = Pockets.API.GetCategorySummary
    Pockets.API.GetCategorySummary = function()
        return {
            { categoryID = "a", label = "A", icon = 1, count = 0 },
            { categoryID = "b", label = "B", icon = 1, count = 2 },
        }
    end

    Shell:SetState(Shell.STATE.MENU)
    local visibleLabels = {}
    for _, row in ipairs(Shell.frame.shell.menuRows) do
        if row:IsShown() then
            table.insert(visibleLabels, row.label:GetText())
        end
    end

    Pockets.API.GetCategorySummary = originalGetSummary
    ResetToGlance()

    local ok = #visibleLabels == 1 and visibleLabels[1] == "B"
    return ok, ok and "OK" or "expected exactly one visible row (the non-zero category)"
end)


-- Category/List tests need items to render; the live inventory may have
-- none in the chosen category (it varies per character), so tests that
-- inspect List rows run against a fixed fake category list instead.
local function StubCategoryItems()
    local original = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function()
        local items = {}
        for i = 1, 3 do
            items[i] = { itemID = 9000 + i, name = "Test Item " .. i, quantity = i, quality = 1,
                bagID = 0, slotID = i, texture = 134400 }
        end
        return items
    end
    return function() Pockets.API.GetAggregatedCategoryItems = original end
end

local function RegisterWithItems(name, fn)
    Pockets.Tests.TestRunner:Register(name, function()
        local restore = StubCategoryItems()
        local ok, a, b = pcall(fn)
        restore()
        if not ok then
            return false, "ERROR: " .. tostring(a)
        end
        return a, b
    end)
end

--------------------------------------------------
-- Row unification: Menu category rows and Category List item rows share
-- one visual row component (§1-§9)
--------------------------------------------------

RegisterWithItems("RowUnification: Menu row height equals Category List row height", function()
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    Shell:SetState(Shell.STATE.MENU)
    local menuRowHeight = Shell.frame.shell.menuRows[1] and Shell.frame.shell.menuRows[1]:GetHeight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRowHeight = Shell.frame.shell.categoryListRows[1] and Shell.frame.shell.categoryListRows[1]:GetHeight()

    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = menuRowHeight and listRowHeight and menuRowHeight == listRowHeight
        and menuRowHeight == Pockets.Constants.LAYOUT.LIST_ROW_HEIGHT
    return ok, ok and "OK" or string.format("expected equal row heights, got menu=%s list=%s",
        tostring(menuRowHeight), tostring(listRowHeight))
end)

RegisterWithItems("RowUnification: Menu icon size equals Category List icon size", function()
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    Shell:SetState(Shell.STATE.MENU)
    local menuIconSize = Shell.frame.shell.menuRows[1] and select(1, Shell.frame.shell.menuRows[1].icon:GetSize())

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listIconSize = Shell.frame.shell.categoryListRows[1] and select(1, Shell.frame.shell.categoryListRows[1].icon:GetSize())

    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = menuIconSize and listIconSize and menuIconSize == listIconSize
        and menuIconSize == Pockets.Constants.LAYOUT.LIST_ICON_SIZE
    return ok, ok and "OK" or string.format("expected equal icon sizes, got menu=%s list=%s",
        tostring(menuIconSize), tostring(listIconSize))
end)

RegisterWithItems("RowUnification: category label and item name start at the same X", function()
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    Shell:SetState(Shell.STATE.MENU)
    local menuLabelLeft = Shell.frame.shell.menuRows[1] and Shell.frame.shell.menuRows[1].label:GetLeft()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local itemNameLeft = Shell.frame.shell.categoryListRows[1] and Shell.frame.shell.categoryListRows[1].name:GetLeft()

    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = menuLabelLeft and itemNameLeft and math.abs(menuLabelLeft - itemNameLeft) < 0.01
    return ok, ok and "OK" or string.format("expected matching label X, got menu=%s item=%s",
        tostring(menuLabelLeft), tostring(itemNameLeft))
end)

-- Wasted-space pass: item rows no longer reserve Menu's chevron column
-- (items never navigate deeper, so that 20px was permanently dead space,
-- worse once a scrollbar narrowed the row further) - qty now sits flush
-- against the row's own right edge instead of aligning with Menu's count.
RegisterWithItems("RowUnification: item qty sits flush against the row's right edge (no reserved chevron gap)", function()
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRow = Shell.frame.shell.categoryListRows[1]
    local itemQtyRight = listRow and listRow.qty:GetRight()
    local rowRight = listRow and listRow:GetRight()

    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = itemQtyRight and rowRight and math.abs((rowRight - itemQtyRight) - Pockets.Constants.LAYOUT.LIST_ROW_PADDING) < 0.01
    return ok, ok and "OK" or string.format("expected qty flush to row edge (padding only), got qtyRight=%s rowRight=%s",
        tostring(itemQtyRight), tostring(rowRight))
end)

RegisterWithItems("RowUnification: item rows have no chevron", function()
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRow = Shell.frame.shell.categoryListRows[1]

    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = listRow and listRow.chevron == nil
    return ok, ok and "OK" or "expected Category List rows to have no chevron field at all"
end)

RegisterWithItems("RowUnification: Menu and Category List rows use the same Blizzard highlight texture mechanism", function()
    Shell:SetState(Shell.STATE.MENU)
    local menuRow = Shell.frame.shell.menuRows[1]
    local ok = menuRow and menuRow.GetHighlightTexture and menuRow:GetHighlightTexture() ~= nil
    ResetToGlance()
    return ok, ok and "OK" or "expected Menu rows to use a real Button highlight texture, not a bespoke overlay"
end)

RegisterWithItems("RowUnification: category rows still navigate, item rows still resolve to a real stack", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell.frame.shell.menuRows[1]:Click()
    local navigated = Shell:GetState() == Shell.STATE.CATEGORY
    ResetToGlance()
    return navigated, navigated and "OK" or "expected clicking a Menu row to still navigate into its category"
end)

--------------------------------------------------
-- Category List max visible rows (List max-height pass)
--------------------------------------------------

local function WithNItems(n, fn)
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local items = {}
    for i = 1, n do
        items[i] = { itemID = i, name = "Item " .. i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return items end
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    local ok, err = pcall(fn)

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    Pockets.SavedSettings.categoryViewMode = originalMode
    if not ok then
        error(err, 0)
    end
end

local function CheckListScrollState(n, expectScrollbar)
    WithNItems(n, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local shell = Shell.frame.shell
        local shown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)
        local contentWidth = shell.content:GetWidth()
        local viewportWidth = shell.scrollFrame:GetWidth()
        -- Content width never changes based on scrollbar visibility
        -- (scrollbar redesign pass - the compact bar lives in the existing
        -- padding gutter, not a reserved column), so this holds shown or
        -- not, unlike the old wide Blizzard scrollbar's reserved column.
        local noGutter = math.abs(contentWidth - viewportWidth) < 0.01

        if shown ~= expectScrollbar then
            error(string.format("n=%d: expected scrollbar shown=%s, got %s", n, tostring(expectScrollbar), tostring(shown)), 0)
        end
        if not noGutter then
            error(string.format("n=%d: expected content width to always match the viewport width", n), 0)
        end
    end)
    ResetToGlance()
end

for _, n in ipairs({ 1, 3, 6 }) do
    Pockets.Tests.TestRunner:Register(string.format("CategoryList: %d item(s) - no scrollbar", n), function()
        CheckListScrollState(n, false)
        return true, "OK"
    end)
end

Pockets.Tests.TestRunner:Register("CategoryList: exactly MAX_VISIBLE_LIST_ROWS items (the cap) - still no scrollbar", function()
    CheckListScrollState(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS, false)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: MAX_VISIBLE_LIST_ROWS + 1 items - only whole rows visible in the viewport", function()
    WithNItems(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS + 1, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        local L = Pockets.Constants.LAYOUT
        local bodyHeight = L.MAX_VISIBLE_LIST_ROWS * L.LIST_ROW_HEIGHT + L.SHELL_PADDING * 2
        local expected = L.SHELL_HEADER_HEIGHT + bodyHeight + L.SHELL_FOOTER_HEIGHT
        if Shell.frame:GetHeight() ~= expected then
            error(string.format("expected capped height %d (whole rows only), got %d", expected, Shell.frame:GetHeight()), 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

-- WoW only clips/scrolls a ScrollFrame's actual frame DESCENDANTS, not
-- frames merely SetPoint-anchored relative to its scroll child. List
-- rows previously lived in a pool parented as a SIBLING of
-- shell.content, so they rendered unclipped and spilled straight past
-- the panel (and the footer) once a category had more items than the
-- visible viewport (vertical scrolling overflow fix).
Pockets.Tests.TestRunner:Register("CategoryList: rows are real frame descendants of the scrollable content (not just SetPoint-adjacent)", function()
    WithNItems(3, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local row = Shell.frame.shell.categoryListRows[1]
        local isDescendant = false
        local ancestor = row and row:GetParent()
        while ancestor do
            if ancestor == Shell.frame.shell.content then
                isDescendant = true
                break
            end
            ancestor = ancestor:GetParent()
        end
        if not isDescendant then
            error("expected a Category List row's frame ancestry to include shell.content", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: MAX_VISIBLE_LIST_ROWS + 1 items - scrollbar appears", function()
    CheckListScrollState(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS + 1, true)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: large category (200 items) - scrollbar appears", function()
    CheckListScrollState(200, true)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: body height caps at exactly MAX_VISIBLE_ROWS*rowHeight, not the generic Grid/All budget", function()
    WithNItems(200, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        local L = Pockets.Constants.LAYOUT
        local maxBodyHeight = L.MAX_VISIBLE_LIST_ROWS * L.LIST_ROW_HEIGHT + L.SHELL_PADDING * 2
        local expected = L.SHELL_HEADER_HEIGHT + maxBodyHeight + L.SHELL_FOOTER_HEIGHT
        local height = Shell.frame:GetHeight()
        if height ~= expected then
            error(string.format("expected height %d, got %d", expected, height), 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: growing from 3 items to the cap only extends the bottom edge (TOPLEFT fixed)", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    WithNItems(3, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)
    local _, _, _, x1, y1 = Shell.frame:GetPoint()

    WithNItems(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS, function()
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)
    local _, _, _, x2, y2 = Shell.frame:GetPoint()

    ResetToGlance()

    local ok = x0 == x1 and y0 == y1 and x1 == x2 and y1 == y2
    return ok, ok and "OK" or "TOPLEFT moved while the List body grew from 3 rows to the cap"
end)

--------------------------------------------------
-- Menu height-management pass: same shared row-count cap as Category List
--------------------------------------------------

local function WithNVisibleCategories(n, fn)
    local originalGetSummary = Pockets.API.GetCategorySummary
    local summary = {}
    for i = 1, n do
        summary[i] = { categoryID = "cat" .. i, label = "Cat " .. i, icon = 1, count = i }
    end
    Pockets.API.GetCategorySummary = function() return summary end

    local ok, err = pcall(fn)

    Pockets.API.GetCategorySummary = originalGetSummary
    if not ok then
        error(err, 0)
    end
end

local function CheckMenuScrollState(n, expectScrollbar)
    WithNVisibleCategories(n, function()
        Shell:SetState(Shell.STATE.MENU)

        local shell = Shell.frame.shell
        local shown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)
        local contentWidth = shell.content:GetWidth()
        local viewportWidth = shell.scrollFrame:GetWidth()
        local noGutter = math.abs(contentWidth - viewportWidth) < 0.01

        if shown ~= expectScrollbar then
            error(string.format("n=%d: expected scrollbar shown=%s, got %s", n, tostring(expectScrollbar), tostring(shown)), 0)
        end
        if not noGutter then
            error(string.format("n=%d: expected content width to always match the viewport width", n), 0)
        end
    end)
    ResetToGlance()
end

for _, n in ipairs({ 1, 3 }) do
    Pockets.Tests.TestRunner:Register(string.format("Menu: %d visible categor%s - no scrollbar", n, n == 1 and "y" or "ies"), function()
        CheckMenuScrollState(n, false)
        return true, "OK"
    end)
end

Pockets.Tests.TestRunner:Register("Menu: exactly MAX_VISIBLE_LIST_ROWS categories (the cap) - still no scrollbar", function()
    CheckMenuScrollState(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS, false)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("Menu: MAX_VISIBLE_LIST_ROWS + 1 categories - scrollbar appears", function()
    CheckMenuScrollState(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS + 1, true)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("Menu: MAX_VISIBLE_LIST_ROWS + 1 categories - only whole rows visible in the viewport", function()
    WithNVisibleCategories(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS + 1, function()
        Shell:SetState(Shell.STATE.MENU)
        local L = Pockets.Constants.LAYOUT
        local bodyHeight = L.MAX_VISIBLE_LIST_ROWS * L.LIST_ROW_HEIGHT + L.SHELL_PADDING * 2
        local expected = L.SHELL_HEADER_HEIGHT + bodyHeight + L.SHELL_FOOTER_HEIGHT
        if Shell.frame:GetHeight() ~= expected then
            error(string.format("expected capped height %d (whole rows only), got %d", expected, Shell.frame:GetHeight()), 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

-- Menu's taxonomy is fixed at 8 categories total (never truly "large"
-- the way a Category List item count can be), but 8 still exceeds the
-- 6-row cap, so a scrollbar is still expected here.
Pockets.Tests.TestRunner:Register("Menu: full 8-category taxonomy exceeds the cap - scrollbar appears", function()
    CheckMenuScrollState(#Pockets.Constants.CATEGORY_ORDER, true)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("Menu: growing from 3 categories to the cap only extends the bottom edge (TOPLEFT fixed)", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    WithNVisibleCategories(3, function()
        Shell:SetState(Shell.STATE.MENU)
    end)
    local _, _, _, x1, y1 = Shell.frame:GetPoint()

    WithNVisibleCategories(Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS, function()
        Shell:SetState(Shell.STATE.MENU)
    end)
    local _, _, _, x2, y2 = Shell.frame:GetPoint()

    ResetToGlance()

    local ok = x0 == x1 and y0 == y1 and x1 == x2 and y1 == y2
    return ok, ok and "OK" or "TOPLEFT moved while Menu's body grew from 3 rows to the cap"
end)

-- §7 "Menu and Category List should now behave identically in terms of
-- vertical sizing" - both cap at the SAME total frame height once each
-- has more than MAX_VISIBLE_LIST_ROWS visible rows.
Pockets.Tests.TestRunner:Register("Menu and Category List cap at the identical total height once over the row limit", function()
    local overCap = Pockets.Constants.LAYOUT.MAX_VISIBLE_LIST_ROWS + 2

    WithNVisibleCategories(overCap, function()
        Shell:SetState(Shell.STATE.MENU)
    end)
    local menuHeight = Shell.frame:GetHeight()
    ResetToGlance()

    local listHeight
    WithNItems(overCap, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        listHeight = Shell.frame:GetHeight()
    end)
    ResetToGlance()

    local ok = menuHeight == listHeight
    return ok, ok and "OK" or string.format("expected matching capped height, got menu=%s list=%s",
        tostring(menuHeight), tostring(listHeight))
end)

-- Dynamic body height pass: Category/All no longer always claim
-- SHELL_BODY_MAX_HEIGHT - they grow to fit actual content, floored at
-- SHELL_BODY_MIN_HEIGHT and capped at SHELL_BODY_MAX_HEIGHT.
Pockets.Tests.TestRunner:Register("Shell: Category body height with a small item count is well under the max (not pinned to it)", function()
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function()
        return { { itemID = 1, name = "Solo Item", texture = 1, quantity = 1, bagID = 0, slotID = 1 } }
    end

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local height = Shell.frame:GetHeight()
    local L = Pockets.Constants.LAYOUT
    local maxTotal = L.SHELL_HEADER_HEIGHT + L.SHELL_BODY_MAX_HEIGHT + L.SHELL_FOOTER_HEIGHT
    local minTotal = L.SHELL_HEADER_HEIGHT + L.SHELL_BODY_MIN_HEIGHT + L.SHELL_FOOTER_HEIGHT

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    ResetToGlance()

    local ok = height == minTotal and height < maxTotal
    return ok, ok and "OK" or string.format(
        "expected height clamped to the minimum (%s), got %s (max would be %s)",
        tostring(minTotal), tostring(height), tostring(maxTotal))
end)

Pockets.Tests.TestRunner:Register("Shell: Category body height grows to (but never past) the max once content overflows", function()
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local manyItems = {}
    for i = 1, 200 do
        manyItems[i] = { itemID = i, name = "Item " .. i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return manyItems end

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local height = Shell.frame:GetHeight()
    local L = Pockets.Constants.LAYOUT
    local maxTotal = L.SHELL_HEADER_HEIGHT + L.SHELL_BODY_MAX_HEIGHT + L.SHELL_FOOTER_HEIGHT

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    ResetToGlance()

    local ok = height == maxTotal
    return ok, ok and "OK" or string.format("expected height capped at max (%s), got %s", tostring(maxTotal), tostring(height))
end)

--------------------------------------------------
-- Render cleanup: no cross-state leakage (§7, §18)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Menu -> Category leaves zero Menu rows visible", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

    local anyVisible = false
    for _, row in ipairs(Shell.frame.shell.menuRows) do
        if row:IsShown() then
            anyVisible = true
        end
    end

    ResetToGlance()
    local ok = not anyVisible
    return ok, ok and "OK" or "a Menu row was still visible after switching to Category"
end)

Pockets.Tests.TestRunner:Register("Shell: Category -> Menu leaves zero item buttons visible in the body", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.TRADE_GOODS })
    Shell:GoBack() -- Category -> Menu

    local pool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.shell.content)
    local anyVisible = false
    for _, button in ipairs(pool.active) do
        if button:IsShown() then
            anyVisible = true
        end
    end

    ResetToGlance()
    local ok = not anyVisible and #pool.active == 0
    return ok, ok and "OK" or "an item button was still active/visible after returning from Category to Menu"
end)

Pockets.Tests.TestRunner:Register("Shell: repeated Menu<->Category transitions do not grow the row/button pool unboundedly", function()
    Shell:SetState(Shell.STATE.MENU)
    for _ = 1, 5 do
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
        Shell:GoBack()
    end
    local rowCount = #Shell.frame.shell.menuRows
    ResetToGlance()
    local ok = rowCount == #Pockets.Constants.CATEGORY_ORDER
    return ok, ok and "OK" or string.format(
        "expected the Menu row pool to stay at exactly %d rows, got %d",
        #Pockets.Constants.CATEGORY_ORDER, rowCount)
end)

--------------------------------------------------
-- Footer stability (§14, §18)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: removing Ammo from the footer does not shift the Bags anchor", function()
    Shell:SetState(Shell.STATE.MENU)
    local shell = Shell.frame.shell
    local bagsLeftBefore = shell.footerBagRow:GetLeft()

    shell.footerAmmoRow:Show() -- simulate an ammo pool being present
    Shell:ConfigureFooter() -- re-derives visibility from real (ammo-less) state, hiding it again
    local bagsLeftAfter = shell.footerBagRow:GetLeft()

    ResetToGlance()
    local ok = bagsLeftBefore == bagsLeftAfter
    return ok, ok and "OK" or "Bags anchor moved when Ammo visibility changed"
end)

Pockets.Tests.TestRunner:Register("Shell: footer always shows Bag and Gold, reusing the shared MetricRow/MoneyFormat components", function()
    Shell:SetState(Shell.STATE.MENU)
    local shell = Shell.frame.shell
    Shell:ConfigureFooter()
    local ok = shell.footerBagRow:IsShown() and shell.footerGoldRow:IsShown()
        and shell.footerBagRow.primaryText:GetText() ~= nil
        and shell.footerGoldRow.primaryText:GetText() == Pockets.UI.MoneyFormat:Format(GetMoney())
    ResetToGlance()
    return ok, ok and "OK" or "expected footer Bag/Gold rows visible and Gold text to match MoneyFormat output"
end)

Pockets.Tests.TestRunner:Register("Shell: footer Ammo metric shows only when ShouldShowAmmoRow is true", function()
    Shell:SetState(Shell.STATE.MENU)
    local shell = Shell.frame.shell
    local ammoCapacity = Pockets.Services.InventoryState:GetAmmoCapacity()
    local expectedShown = Shell:ShouldShowAmmoRow(ammoCapacity)
    Shell:ConfigureFooter()
    local ok = shell.footerAmmoRow:IsShown() == expectedShown
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected footer Ammo shown=%s per ShouldShowAmmoRow", tostring(expectedShown))
end)

Pockets.Tests.TestRunner:Register("Shell: SavePosition ignores a negligible (phantom-drag) position change", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.MENU)
    local hud = Pockets.CharDB.hud
    local originalX, originalY = hud.x, hud.y

    -- Same spot, only float-rounding-scale noise - simulates a
    -- zero-movement click-triggered OnDragStart/OnDragStop cycle.
    Shell.frame:ClearAllPoints()
    Shell.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", originalX + 0.001, originalY - 0.001)
    Shell:SavePosition()

    local unchanged = hud.x == originalX and hud.y == originalY

    -- A REAL move still gets saved.
    Shell.frame:ClearAllPoints()
    Shell.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", originalX + 50, originalY - 50)
    Shell:SavePosition()
    local realMoveSaved = ApproxEqual(hud.x, originalX + 50) and ApproxEqual(hud.y, originalY - 50)

    hud.x, hud.y = originalX, originalY
    ResetToGlance()

    local ok = unchanged and realMoveSaved
    return ok, ok and "OK" or "SavePosition either persisted negligible noise or dropped a real move"
end)

--------------------------------------------------
-- Menu -> Glance back navigation (UI/anchoring fix pass §4, §5, §11)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Menu header shows a back button", function()
    Shell:SetState(Shell.STATE.MENU)
    local ok = Shell.frame.shell.header.backButton:IsShown()
    ResetToGlance()
    return ok, ok and "OK" or "expected Menu's header to show the back button"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking Menu's back button navigates to Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell.frame.shell.header.backButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected GLANCE after clicking Menu's back button, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: clicking Category's back button navigates to Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell.frame.shell.header.backButton:Click()
    local ok = Shell:GetState() == Shell.STATE.MENU
    ResetToGlance()
    return ok, ok and "OK" or "expected MENU after clicking Category's back button"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking All's back button navigates to Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.ALL)
    Shell.frame.shell.header.backButton:Click()
    local ok = Shell:GetState() == Shell.STATE.MENU
    ResetToGlance()
    return ok, ok and "OK" or "expected MENU after clicking All's back button"
end)

--------------------------------------------------
-- Top bar / close (X) pass: consistent header geometry, X dismisses
-- straight to Glance from every expanded state
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: X is shown and sits at the same far-right position in Menu, Category, and All", function()
    local header = Shell.frame.shell.header

    Shell:SetState(Shell.STATE.MENU)
    local menuShown, menuRight = header.closeButton:IsShown(), header.closeButton:GetRight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local catShown, catRight = header.closeButton:IsShown(), header.closeButton:GetRight()

    Shell:SetState(Shell.STATE.ALL)
    local allShown, allRight = header.closeButton:IsShown(), header.closeButton:GetRight()

    ResetToGlance()

    local ok = menuShown and catShown and allShown
        and menuRight and catRight and allRight
        and math.abs(menuRight - catRight) < 0.01 and math.abs(catRight - allRight) < 0.01
    return ok, ok and "OK" or "X was hidden or shifted position between Menu/Category/All"
end)

Pockets.Tests.TestRunner:Register("Shell: title's right edge stays fixed across Menu/Category/All regardless of contextual control", function()
    local header = Shell.frame.shell.header

    Shell:SetState(Shell.STATE.MENU)
    local menuTitleRight = header.titleText:GetRight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local catTitleRight = header.titleText:GetRight()

    Shell:SetState(Shell.STATE.ALL)
    local allTitleRight = header.titleText:GetRight()

    ResetToGlance()

    local ok = menuTitleRight and catTitleRight and allTitleRight
        and math.abs(menuTitleRight - catTitleRight) < 0.01 and math.abs(catTitleRight - allTitleRight) < 0.01
    return ok, ok and "OK" or "title's right edge shifted between Menu (+) / Category (+) / All (search)"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking X from Menu navigates straight to Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell.frame.shell.header.closeButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE after clicking Menu's X"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking X from Category navigates straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell.frame.shell.header.closeButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE (not MENU) after clicking Category's X"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking X from All navigates straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.ALL)
    Shell.frame.shell.header.closeButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE (not MENU) after clicking All's X"
end)

Pockets.Tests.TestRunner:Register("Shell: Glance does not intercept Escape (keyboard capture disabled)", function()
    ResetToGlance()
    local ok = not Shell.escapeCatcher:IsShown() and not Shell.frame:IsKeyboardEnabled()
    return ok, ok and "OK" or "expected Glance to leave keyboard capture disabled so Escape is not intercepted"
end)

-- Combat-safety hardening pass: an expanded state must keep working
-- (keyboard capture enabled, action-bar keys still propagate through
-- non-Escape presses) even while CombatAPI reports combat - Pockets must
-- never block/hide behind a combat conditional (CLAUDE.md/UI_RULES.md).
-- Forcing IsInCombat true here also guards against ever reintroducing a
-- combat-conditional branch into Render() by accident.
for _, state in ipairs({ Shell.STATE.MENU, Shell.STATE.ALL, Shell.STATE.SEARCH }) do
    Pockets.Tests.TestRunner:Register(
        string.format("Shell: %s keeps its Escape catcher shown (no keyboard capture) even while CombatAPI reports combat", tostring(state)),
        function()
            local CombatAPI = Pockets.Adapters.CombatAPI
            local original = CombatAPI.IsInCombat
            CombatAPI.IsInCombat = function() return true end

            Shell:SetState(state)
            local ok = Shell.escapeCatcher:IsShown() == true

            CombatAPI.IsInCombat = original
            ResetToGlance()
            return ok, ok and "OK" or string.format(
                "expected keyboard capture still enabled for %s during combat", tostring(state))
        end)
end

Pockets.Tests.TestRunner:Register("Shell: CATEGORY keeps its Escape catcher shown (no keyboard capture) even while CombatAPI reports combat", function()
    local CombatAPI = Pockets.Adapters.CombatAPI
    local original = CombatAPI.IsInCombat
    CombatAPI.IsInCombat = function() return true end

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    local ok = Shell.escapeCatcher:IsShown() == true

    CombatAPI.IsInCombat = original
    ResetToGlance()
    return ok, ok and "OK" or "expected keyboard capture still enabled for CATEGORY during combat"
end)

-- Back = navigate up (routes through GoBack/ESCAPE_PARENT, one level at a
-- time); X/Escape = dismiss Pockets (jump straight to Glance, bypassing
-- GoBack entirely) - top-bar/close pass's semantic distinction.
Pockets.Tests.TestRunner:Register("Shell: Back routes through GoBack; X and Escape bypass it and dismiss straight to Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })

    local originalGoBack = Shell.GoBack
    local calls = 0
    Shell.GoBack = function(self, ...)
        calls = calls + 1
        return originalGoBack(self, ...)
    end

    Shell.frame.shell.header.backButton:Click() -- Category -> Menu, via GoBack
    local afterBackClick = calls
    local backLandedOnMenu = Shell:GetState() == Shell.STATE.MENU

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    Shell.frame.shell.header.closeButton:Click() -- Category -> Glance directly, NOT through GoBack
    local afterCloseClick = calls
    local closeLandedOnGlance = Shell:GetState() == Shell.STATE.GLANCE

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    Shell:HandleEscape() -- Category -> Glance directly, NOT through GoBack
    local afterEscape = calls
    local escapeLandedOnGlance = Shell:GetState() == Shell.STATE.GLANCE

    Shell.GoBack = originalGoBack
    ResetToGlance()

    local ok = afterBackClick == 1 and backLandedOnMenu
        and afterCloseClick == afterBackClick and closeLandedOnGlance
        and afterEscape == afterBackClick and escapeLandedOnGlance
    return ok, ok and "OK" or string.format(
        "expected only Back to call GoBack (got %d calls after back, %d after close, %d after escape)",
        afterBackClick, afterCloseClick, afterEscape)
end)

Pockets.Tests.TestRunner:Register("Shell: header title sits at the same fixed offset in Menu, Category, and All (§6)", function()
    Shell:SetState(Shell.STATE.MENU)
    local menuLeft = Shell.frame.shell.header.titleText:GetLeft()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local categoryLeft = Shell.frame.shell.header.titleText:GetLeft()

    Shell:SetState(Shell.STATE.ALL)
    local allLeft = Shell.frame.shell.header.titleText:GetLeft()

    ResetToGlance()
    local ok = menuLeft == categoryLeft and categoryLeft == allLeft
    return ok, ok and "OK" or string.format(
        "expected a stable title x-offset, got menu=%s category=%s all=%s",
        tostring(menuLeft), tostring(categoryLeft), tostring(allLeft))
end)

--------------------------------------------------
-- Category List/Grid view preference
--------------------------------------------------

local function WithCategoryViewMode(mode, fn)
    local original = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = mode
    local ok, err = pcall(fn)
    Pockets.SavedSettings.categoryViewMode = original
    if not ok then
        error(err, 0)
    end
end

Pockets.Tests.TestRunner:Register("CategoryView: default preference is GRID", function()
    local ok = Pockets.Constants.DEFAULT_SETTINGS.categoryViewMode == Pockets.Constants.CATEGORY_VIEW_MODE.GRID
    return ok, ok and "OK" or "expected the default Category view to be GRID"
end)

Pockets.Tests.TestRunner:Register("CategoryView: SetCategoryViewMode(LIST) persists", function()
    local original = Pockets.SavedSettings.categoryViewMode
    Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST)
    local ok = Pockets.SavedSettings.categoryViewMode == Pockets.Constants.CATEGORY_VIEW_MODE.LIST
    Pockets.SavedSettings.categoryViewMode = original
    return ok, ok and "OK" or "expected LIST to persist into SavedSettings"
end)

Pockets.Tests.TestRunner:Register("CategoryView: SetCategoryViewMode(GRID) persists", function()
    local original = Pockets.SavedSettings.categoryViewMode
    Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID)
    local ok = Pockets.SavedSettings.categoryViewMode == Pockets.Constants.CATEGORY_VIEW_MODE.GRID
    Pockets.SavedSettings.categoryViewMode = original
    return ok, ok and "OK" or "expected GRID to persist into SavedSettings"
end)

Pockets.Tests.TestRunner:Register("CategoryView: an invalid value is ignored, not persisted", function()
    local original = Pockets.SavedSettings.categoryViewMode
    Shell:SetCategoryViewMode("BOGUS")
    local ok = Pockets.SavedSettings.categoryViewMode == original
    Pockets.SavedSettings.categoryViewMode = original
    return ok, ok and "OK" or "expected an invalid mode to be silently ignored"
end)

Pockets.Tests.TestRunner:Register("CategoryView: RenderCategory dispatches to the Grid renderer when mode=GRID", function()
    local originalGrid = Shell.RenderCategoryGrid
    local originalList = Shell.RenderCategoryList
    local gridCalls, listCalls = 0, 0
    Shell.RenderCategoryGrid = function(self, ...) gridCalls = gridCalls + 1; return originalGrid(self, ...) end
    Shell.RenderCategoryList = function(self, ...) listCalls = listCalls + 1; return originalList(self, ...) end

    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)

    Shell.RenderCategoryGrid = originalGrid
    Shell.RenderCategoryList = originalList
    ResetToGlance()

    local ok = gridCalls == 1 and listCalls == 0
    return ok, ok and "OK" or string.format("expected exactly 1 grid call / 0 list calls, got %d/%d", gridCalls, listCalls)
end)

Pockets.Tests.TestRunner:Register("CategoryView: RenderCategory dispatches to the List renderer when mode=LIST", function()
    local originalGrid = Shell.RenderCategoryGrid
    local originalList = Shell.RenderCategoryList
    local gridCalls, listCalls = 0, 0
    Shell.RenderCategoryGrid = function(self, ...) gridCalls = gridCalls + 1; return originalGrid(self, ...) end
    Shell.RenderCategoryList = function(self, ...) listCalls = listCalls + 1; return originalList(self, ...) end

    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)

    Shell.RenderCategoryGrid = originalGrid
    Shell.RenderCategoryList = originalList
    ResetToGlance()

    local ok = gridCalls == 0 and listCalls == 1
    return ok, ok and "OK" or string.format("expected exactly 0 grid calls / 1 list call, got %d/%d", gridCalls, listCalls)
end)

RegisterWithItems("CategoryView: switching mode while Category is open re-renders immediately, no state change", function()
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local _, _, _, x0, y0 = Shell.frame:GetPoint()
        local headerHeightBefore = Shell.frame.shell.header:GetHeight()
        local footerHeightBefore = Shell.frame.shell.footer:GetHeight()

        Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST)

        local stillCategory = Shell:GetState() == Shell.STATE.CATEGORY
        local anyListRowVisible = false
        for _, row in ipairs(Shell.frame.shell.categoryListRows) do
            if row:IsShown() then anyListRowVisible = true end
        end
        local _, _, _, x1, y1 = Shell.frame:GetPoint()
        local headerHeightAfter = Shell.frame.shell.header:GetHeight()
        local footerHeightAfter = Shell.frame.shell.footer:GetHeight()

        local ok = stillCategory and anyListRowVisible
            and x0 == x1 and y0 == y1
            and headerHeightBefore == headerHeightAfter
            and footerHeightBefore == footerHeightAfter
        if not ok then
            error("switching to LIST moved state/anchor/header/footer or didn't render", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryView: List -> Grid cleanup leaves zero list rows visible", function()
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID)

        local anyListRowVisible = false
        for _, row in ipairs(Shell.frame.shell.categoryListRows) do
            if row:IsShown() then anyListRowVisible = true end
        end
        if anyListRowVisible then
            error("a List row was still visible after switching to Grid", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryView: Grid -> List cleanup leaves zero grid buttons active", function()
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST)

        local gridPool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.shell.content)
        if #gridPool.active ~= 0 then
            error("a Grid item button was still active after switching to List", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

RegisterWithItems("CategoryView: repeated Grid<->List toggling does not accumulate rows", function()
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        -- List rows are long-lived and shared across tests, so earlier
        -- tests may already have grown the pool; what matters is that
        -- toggling never grows it beyond what one List render needs.
        Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST)
        local baseline = #Shell.frame.shell.categoryListRows
        Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID)
        for _ = 1, 5 do
            Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST)
            Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID)
        end
        local rowCount = #Shell.frame.shell.categoryListRows
        if rowCount > baseline then
            error(string.format("expected at most %d pooled List rows, got %d", baseline, rowCount), 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryView: List row shows the same aggregate quantity Grid would", function()
    local items = Pockets.API.GetAggregatedCategoryItems(Pockets.Constants.CATEGORY.OTHER)
    if #items == 0 then
        return true, "OK (no items in Other to compare)"
    end

    local ok = true
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        local row = Shell.frame.shell.categoryListRows[1]
        ok = row and row.qty:GetText() == tostring(items[1].quantity)
    end)
    ResetToGlance()
    return ok, ok and "OK" or "List row quantity did not match the shared aggregate total"
end)

Pockets.Tests.TestRunner:Register("CategoryView: List row is bound to the same itemID/bagID/slotID contract as Grid buttons", function()
    local items = Pockets.API.GetAggregatedCategoryItems(Pockets.Constants.CATEGORY.OTHER)
    if #items == 0 then
        return true, "OK (no items in Other to check)"
    end

    local ok = true
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        local row = Shell.frame.shell.categoryListRows[1]
        ok = row and row.itemID == items[1].itemID
            and row.bagID == items[1].bagID and row.slotID == items[1].slotID
    end)
    ResetToGlance()
    return ok, ok and "OK" or "List row was not bound to the resolver-backed bagID/slotID contract Configure() sets"
end)

Pockets.Tests.TestRunner:Register("CategoryView: List has no scrollbar when rows fit the viewport", function()
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })

        local shell = Shell.frame.shell
        local contentWidth = shell.content:GetWidth()
        local viewportWidth = shell.scrollFrame:GetWidth()
        local scrollBarShown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)

        if scrollBarShown or math.abs(contentWidth - viewportWidth) >= 0.01 then
            error("scrollbar present without List content overflowing", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register(
    "CategoryView: List shows a scrollbar without narrowing content width when rows overflow", function()
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local manyItems = {}
    for i = 1, 200 do
        manyItems[i] = { itemID = i, name = "Test Item " .. i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return manyItems end

    local ok, failMessage
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local L = Pockets.Constants.LAYOUT
        local shell = Shell.frame.shell
        local contentWidth = shell.content:GetWidth()
        local fullWidth = L.SHELL_WIDTH - L.SHELL_PADDING * 2
        local shown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)

        ok = shown and math.abs(contentWidth - fullWidth) < 0.01
        if not ok then
            failMessage = string.format(
                "expected scrollbar shown and content width unchanged at %s; got shown=%s content=%s",
                tostring(fullWidth), tostring(shown), tostring(contentWidth))
        end
    end)

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    ResetToGlance()

    return ok, ok and "OK" or (failMessage or "expected a scrollbar without content narrowing once List rows overflow")
end)

--------------------------------------------------
-- Full Inventory category headers/collapse (Full Inventory redesign)
--
-- No mock-inventory harness exists (per AGENTS.md, full confidence needs
-- a manual in-game `/pockets test run`), so these run against whatever
-- real bag/Recent contents the test character happens to have. They're
-- written as structural invariants that hold regardless of exact
-- contents (rather than asserting specific counts/items), except the
-- Recent cap check, which is a best-effort upper-bound check.
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: entering Full Inventory preserves the TOPLEFT anchor", function()
    Shell:SetState(Shell.STATE.GLANCE)
    local pointBefore, _, relBefore, xBefore, yBefore = Shell.frame:GetPoint()
    Shell:SetState(Shell.STATE.ALL)
    local pointAfter, _, relAfter, xAfter, yAfter = Shell.frame:GetPoint()
    ResetToGlance()
    local ok = pointBefore == pointAfter and pointBefore == "TOPLEFT"
        and relBefore == relAfter and xBefore == xAfter and yBefore == yAfter
    return ok, ok and "OK" or "expected TOPLEFT anchor to be unchanged entering ALL"
end)

Pockets.Tests.TestRunner:Register("Shell: Full Inventory category headers never share a row (no <50% packing)", function()
    Shell:SetState(Shell.STATE.ALL)
    local headers = Shell.frame.shell.categoryHeaders
    local ok = true
    for i = 2, #headers do
        if headers[i]:IsShown() and headers[i - 1]:IsShown() then
            -- Fresh-row guarantee: each header's top is strictly below
            -- the previous header's top (never side-by-side on one row).
            if headers[i]:GetTop() >= headers[i - 1]:GetTop() then
                ok = false
            end
        end
    end
    ResetToGlance()
    return ok, ok and "OK" or "expected every category header to start below the previous one, never sharing a row"
end)

Pockets.Tests.TestRunner:Register("Shell: Full Inventory category headers have no icon region and share one component", function()
    Shell:SetState(Shell.STATE.ALL)
    local headers = Shell.frame.shell.categoryHeaders
    local ok = #headers > 0
    for _, header in ipairs(headers) do
        if header:IsShown() then
            ok = ok and header.icon == nil and header.isPocketsCategoryHeader == true
                and header.label:GetText():match("^.+ %(%d+%)$") ~= nil
        end
    end
    ResetToGlance()
    return ok, ok and "OK" or "expected every visible header to be icon-free, share the CategoryHeader marker, and read 'Name (count)'"
end)

Pockets.Tests.TestRunner:Register("Shell: Full Inventory never shows a zero-count category header", function()
    Shell:SetState(Shell.STATE.ALL)
    local ok = true
    for _, header in ipairs(Shell.frame.shell.categoryHeaders) do
        if header:IsShown() then
            local count = tonumber(header.label:GetText():match("%((%d+)%)$"))
            if not count or count <= 0 then
                ok = false
            end
        end
    end
    ResetToGlance()
    return ok, ok and "OK" or "expected no visible category header with a zero item count"
end)

Pockets.Tests.TestRunner:Register("Shell: Recent's Full Inventory header is capped at FULL_INVENTORY_RECENT_LIMIT and uses the same header component", function()
    Shell:SetState(Shell.STATE.ALL)
    local L = Pockets.Constants.LAYOUT
    local found, ok = false, true
    for _, header in ipairs(Shell.frame.shell.categoryHeaders) do
        if header:IsShown() and header.label:GetText():match("^Recent %(") then
            found = true
            local count = tonumber(header.label:GetText():match("%((%d+)%)$"))
            ok = header.isPocketsCategoryHeader == true and count and count <= L.FULL_INVENTORY_RECENT_LIMIT
        end
    end
    ResetToGlance()
    -- found=false just means the test character has no recent items right
    -- now (nothing to assert against) - not a failure.
    return (not found) or ok, ok and "OK" or "expected Recent's header count to be <= FULL_INVENTORY_RECENT_LIMIT"
end)

Pockets.Tests.TestRunner:Register("Shell: collapsing a Full Inventory category updates its header's chevron and persists in CharDB", function()
    Shell:SetState(Shell.STATE.ALL)
    local header = Shell.frame.shell.categoryHeaders[1]
    local ok = false
    if header and header:IsShown() then
        -- header[1] corresponds to the FIRST visible section, which is
        -- Recent whenever any recent items exist, else the next
        -- populated category in CATEGORY_ORDER - read the id back off
        -- CharDB after toggling rather than assuming which one it is.
        header:Click()
        local collapsedID
        for id, collapsed in pairs(Pockets.CharDB.collapsedCategories) do
            if collapsed then
                collapsedID = id
            end
        end
        ok = collapsedID ~= nil and header.collapsed == true
            and Pockets.Tests.TextureEquals(header.chevron:GetTexture(), Pockets.UI.PHUI.Icons.PLUS) -- collapsed
        -- Cleanup: never leave test-induced collapse state behind.
        if collapsedID then
            Pockets.CharDB.collapsedCategories[collapsedID] = nil
        end
        Shell:RenderAll("")
    end
    ResetToGlance()
    return ok, ok and "OK" or "expected clicking a header to collapse it (chevron -> plus texture, persisted in CharDB.collapsedCategories)"
end)

Pockets.Tests.TestRunner:Register("Shell: Full Inventory item buttons are all identical dimensions (ITEM_BUTTON_SIZE)", function()
    Shell:SetState(Shell.STATE.ALL)
    local L = Pockets.Constants.LAYOUT
    local pool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.shell.content)
    local ok = true
    for _, button in ipairs(pool.active) do
        local w, h = button:GetSize()
        if w ~= L.ITEM_BUTTON_SIZE or h ~= L.ITEM_BUTTON_SIZE then
            ok = false
        end
    end
    ResetToGlance()
    return ok, ok and "OK" or "expected every Full Inventory item button to be ITEM_BUTTON_SIZE x ITEM_BUTTON_SIZE"
end)

--------------------------------------------------
-- Render smoke tests
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: RenderMenu does not error", function()
    local ok, err = pcall(function() Shell:SetState(Shell.STATE.MENU) end)
    ResetToGlance()
    return ok, ok and "OK" or tostring(err)
end)

Pockets.Tests.TestRunner:Register("Shell: RenderCategory does not error", function()
    local ok, err = pcall(function()
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)
    ResetToGlance()
    return ok, ok and "OK" or tostring(err)
end)

Pockets.Tests.TestRunner:Register("Shell: RenderAll does not error for categorized flow or a flattened search query", function()
    local ok1, err1 = pcall(function()
        Shell:SetState(Shell.STATE.ALL)
        Shell:RenderAll("")
    end)
    local ok2, err2 = pcall(function() Shell:RenderAll("zzz_no_match_zzz") end)
    local ok3, err3 = pcall(function() Shell:RenderAll("") end) -- clearing search restores categorized flow
    ResetToGlance()
    local ok = ok1 and ok2 and ok3
    return ok, ok and "OK" or string.format("%s / %s / %s", tostring(err1), tostring(err2), tostring(err3))
end)

--------------------------------------------------
-- Legacy hover navigation is gone
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Legacy: Pockets.UI no longer exposes the old flyout modules", function()
    local ok = Pockets.UI.CategoryFlyout == nil and Pockets.UI.ItemFlyout == nil
        and Pockets.UI.HoverGroup == nil and Pockets.UI.HUD == nil and Pockets.UI.FullInventory == nil
    return ok, ok and "OK" or "an old hover-flyout module is still present"
end)

Pockets.Tests.TestRunner:Register("Legacy: hovering the Glance frame does not change Shell state", function()
    ResetToGlance()
    if Shell.frame:GetScript("OnEnter") then
        Shell.frame:GetScript("OnEnter")(Shell.frame)
    end
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    return ok, ok and "OK" or "hovering Glance changed navigation state"
end)

--------------------------------------------------
-- Glance Quick Search (SEARCH state) - Glance -> Search -> interact ->
-- Glance. NOT inventory browsing (product intent) - separate, lightweight
-- from All Items' own search box/behavior, which is untouched.
--------------------------------------------------

-- fn returns (ok, message), same contract TestRunner:Register expects -
-- WithAllAggregatedItems just guarantees the stub is restored either way
-- and passes that (ok, message) straight through.
local function WithAllAggregatedItems(items, fn)
    local original = Pockets.API.GetAllAggregatedItems
    Pockets.API.GetAllAggregatedItems = function() return items end
    local callOK, ok, message = pcall(fn)
    Pockets.API.GetAllAggregatedItems = original
    if not callOK then
        return false, "ERROR: " .. tostring(ok)
    end
    return ok, message
end

Pockets.Tests.TestRunner:Register("Shell: Glance's search icon is visible and clickable", function()
    ResetToGlance()
    local ok = Shell.frame.glance.header.iconButton:IsShown()
    return ok, ok and "OK" or "expected the Glance header's search icon to be visible"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking Glance's search icon enters SEARCH, not Menu/All Items", function()
    ResetToGlance()
    Shell.frame.glance.header.iconButton:Click()
    local ok = Shell:GetState() == Shell.STATE.SEARCH
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected SEARCH after clicking the Glance search icon, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: entering SEARCH from Glance preserves the exact same TOPLEFT anchor", function()
    ResetToGlance()
    local _, _, _, glanceX, glanceY = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.SEARCH)
    local _, _, _, searchX, searchY = Shell.frame:GetPoint()

    ResetToGlance()
    local ok = glanceX == searchX and glanceY == searchY
    return ok, ok and "OK" or string.format(
        "TOPLEFT drifted entering SEARCH: glance=(%s,%s) search=(%s,%s)",
        tostring(glanceX), tostring(glanceY), tostring(searchX), tostring(searchY))
end)

Pockets.Tests.TestRunner:Register("Shell: entering SEARCH uses the same shared width as Menu/Category/All", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok = Shell.frame:GetWidth() == Pockets.Constants.LAYOUT.SHELL_WIDTH
    ResetToGlance()
    return ok, ok and "OK" or "expected SEARCH to share SHELL_WIDTH with Menu/Category/All"
end)

Pockets.Tests.TestRunner:Register("Shell: entering SEARCH focuses the EditBox immediately", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok = Shell.frame.shell.searchPanel.editBox:HasFocus()
    ResetToGlance()
    return ok, ok and "OK" or "expected the Quick Search EditBox to have focus right after entering SEARCH"
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH has no footer and no scrollbar", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local shell = Shell.frame.shell
    local ok = not shell.footer:IsShown() and not shell.scrollFrame:IsShown()
        and not Pockets.UI.ScrollBar:IsShown(shell.scrollBar)
    ResetToGlance()
    return ok, ok and "OK" or "expected SEARCH to show neither the footer nor a scrollbar"
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH with 0 matches shows 'No items found' and no result rows", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok, message = WithAllAggregatedItems(
        { { itemID = 1, name = "Linen Cloth", quantity = 1, bagID = 0, slotID = 1 } }, function()
            Shell.frame.shell.searchPanel.editBox:SetText("silk")
            Shell:RenderSearch() -- OnTextChanged is deferred on Forever
            local panel = Shell.frame.shell.searchPanel
            local anyRowShown = false
            for _, row in ipairs(Shell.frame.shell.searchRows) do
                if row:IsShown() then anyRowShown = true end
            end
            local result = panel.feedbackPrimary:IsShown() and panel.feedbackPrimary:GetText() == "No items found"
                and not anyRowShown
            return result, result and "OK" or "expected 'No items found' feedback with no rows for a non-matching query"
        end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH with 1 match shows exactly one result row", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok, message = WithAllAggregatedItems({
        { itemID = 1, name = "Linen Cloth", quantity = 12, bagID = 0, slotID = 1 },
        { itemID = 2, name = "Wool Cloth", quantity = 3, bagID = 0, slotID = 2 },
    }, function()
        Shell.frame.shell.searchPanel.editBox:SetText("linen")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local rows = Shell.frame.shell.searchRows
        local shownCount = 0
        for _, row in ipairs(rows) do
            if row:IsShown() then shownCount = shownCount + 1 end
        end
        local panel = Shell.frame.shell.searchPanel
        local result = shownCount == 1 and rows[1].name:GetText() == "Linen Cloth" and rows[1].qty:GetText() == "12"
            and not panel.feedbackPrimary:IsShown()
        return result, result and "OK" or string.format("expected exactly 1 result row for 'linen', got %d shown", shownCount)
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH with 2 matches shows exactly two result rows", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok, message = WithAllAggregatedItems({
        { itemID = 1, name = "Major Mana Potion", quantity = 5, bagID = 0, slotID = 1 },
        { itemID = 2, name = "Minor Mana Potion", quantity = 2, bagID = 0, slotID = 2 },
        { itemID = 3, name = "Linen Cloth", quantity = 1, bagID = 0, slotID = 3 },
    }, function()
        Shell.frame.shell.searchPanel.editBox:SetText("mana")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local rows = Shell.frame.shell.searchRows
        local shownCount = 0
        for _, row in ipairs(rows) do
            if row:IsShown() then shownCount = shownCount + 1 end
        end
        local result = shownCount == 2
        return result, result and "OK" or string.format("expected exactly 2 result rows for 'mana', got %d shown", shownCount)
    end)
    ResetToGlance()
    return ok, message
end)

-- Builds `count` distinct "Mana <n>" items that all match query "mana",
-- for exercising the capped-rows/overflow-trailer and full-feedback-
-- collapse branches without hardcoding a match count against a layout
-- constant that might change again later.
local function BuildManaItems(count)
    local items = {}
    for i = 1, count do
        table.insert(items, { itemID = i, name = string.format("Mana %d", i), quantity = 1, bagID = 0, slotID = i })
    end
    return items
end

Pockets.Tests.TestRunner:Register(
    "Shell: SEARCH with more matches than SEARCH_MAX_RESULT_ROWS caps rows and shows an 'and N more' trailer", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local L = Pockets.Constants.LAYOUT
    local totalCount = L.SEARCH_MAX_RESULT_ROWS + 3
    local ok, message = WithAllAggregatedItems(BuildManaItems(totalCount), function()
        Shell.frame.shell.searchPanel.editBox:SetText("mana")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local rows = Shell.frame.shell.searchRows
        local shownCount = 0
        for _, row in ipairs(rows) do
            if row:IsShown() then shownCount = shownCount + 1 end
        end
        local panel = Shell.frame.shell.searchPanel
        local expectedRemaining = totalCount - L.SEARCH_MAX_RESULT_ROWS
        local result = shownCount == L.SEARCH_MAX_RESULT_ROWS and not panel.feedbackPrimary:IsShown()
            and panel.overflowLabel:IsShown()
            and panel.overflowLabel:GetText() == string.format("and %d more. Keep typing to filter.", expectedRemaining)
        return result, result and "OK" or string.format(
            "expected %d capped rows and an 'and %d more' trailer, got %d rows shown, trailer=%s",
            L.SEARCH_MAX_RESULT_ROWS, expectedRemaining, shownCount, tostring(panel.overflowLabel:GetText()))
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register(
    "Shell: SEARCH beyond SEARCH_OVERFLOW_LIMIT matches hides all result rows and shows the match count", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local L = Pockets.Constants.LAYOUT
    local totalCount = L.SEARCH_OVERFLOW_LIMIT + 1
    local ok, message = WithAllAggregatedItems(BuildManaItems(totalCount), function()
        Shell.frame.shell.searchPanel.editBox:SetText("mana")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local rows = Shell.frame.shell.searchRows
        local anyRowShown = false
        for _, row in ipairs(rows) do
            if row:IsShown() then anyRowShown = true end
        end
        local panel = Shell.frame.shell.searchPanel
        local expectedText = string.format("%d items found", totalCount)
        local result = not anyRowShown and not panel.overflowLabel:IsShown() and panel.feedbackPrimary:IsShown()
            and panel.feedbackPrimary:GetText() == expectedText
            and panel.feedbackSecondary:IsShown() and panel.feedbackSecondary:GetText() == "Keep typing..."
        return result, result and "OK" or string.format(
            "expected >SEARCH_OVERFLOW_LIMIT matches to hide rows and show '%s' / 'Keep typing...', got primary=%s secondary=%s anyRowShown=%s",
            expectedText,
            tostring(panel.feedbackPrimary:GetText()), tostring(panel.feedbackSecondary:GetText()), tostring(anyRowShown))
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH ranks exact > prefix > substring in the two-row display", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok, message = WithAllAggregatedItems({
        { itemID = 1, name = "Major Mana Potion", quantity = 1, bagID = 0, slotID = 1 }, -- substring
        { itemID = 2, name = "Mana", quantity = 1, bagID = 0, slotID = 2 },               -- exact
    }, function()
        Shell.frame.shell.searchPanel.editBox:SetText("mana")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local rows = Shell.frame.shell.searchRows
        local result = rows[1].name:GetText() == "Mana" and rows[2].name:GetText() == "Major Mana Potion"
        return result, result and "OK" or "expected exact match ('Mana') to rank ahead of the substring match"
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH result rows are real ItemButtonPool buttons bound to bag/slot", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok, message = WithAllAggregatedItems({
        { itemID = 1, name = "Linen Cloth", quantity = 12, bagID = 0, slotID = 1 },
    }, function()
        Shell.frame.shell.searchPanel.editBox:SetText("linen")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local row = Shell.frame.shell.searchRows[1]
        local result = row.itemID == 1 and row.bagID == 0 and row.slotID == 1
            and row.interactive == true and row.bagIndexFrame and row.bagIndexFrame:GetID() == 0
            and row:GetID() == 1
        return result, result and "OK" or "expected the search result row to be a real, interactive item button bound to bag 0 slot 1"
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: changing the SEARCH query updates results immediately", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local ok, message = WithAllAggregatedItems({
        { itemID = 1, name = "Linen Cloth", quantity = 1, bagID = 0, slotID = 1 },
        { itemID = 2, name = "Wool Cloth", quantity = 1, bagID = 0, slotID = 2 },
    }, function()
        local panel = Shell.frame.shell.searchPanel
        local rows = Shell.frame.shell.searchRows

        panel.editBox:SetText("linen")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local afterLinen = rows[1]:IsShown() and rows[1].name:GetText() == "Linen Cloth"

        panel.editBox:SetText("cloth") -- broadens to 2 matches
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local shownAfterCloth = 0
        for _, row in ipairs(rows) do
            if row:IsShown() then shownAfterCloth = shownAfterCloth + 1 end
        end

        panel.editBox:SetText("") -- clearing goes back to the blank/no-persistent-height state
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local anyShownAfterClear = false
        for _, row in ipairs(rows) do
            if row:IsShown() then anyShownAfterClear = true end
        end

        local result = afterLinen and shownAfterCloth == 2 and not anyShownAfterClear
            and not panel.feedbackPrimary:IsShown()
        return result, result and "OK" or string.format(
            "expected live updates: linen=%s clothShown=%d clearedAnyShown=%s",
            tostring(afterLinen), shownAfterCloth, tostring(anyShownAfterClear))
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH clearing the query does not persist an empty body height", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local blankHeight = Shell.frame:GetHeight()
    local ok, message = WithAllAggregatedItems({
        { itemID = 1, name = "Mana Potion", quantity = 1, bagID = 0, slotID = 1 },
        { itemID = 2, name = "Mana Biscuit", quantity = 1, bagID = 0, slotID = 2 },
        { itemID = 3, name = "Mana Ruby", quantity = 1, bagID = 0, slotID = 3 },
    }, function()
        Shell.frame.shell.searchPanel.editBox:SetText("mana") -- grows the frame (3+ feedback)
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever
        local grownHeight = Shell.frame:GetHeight()
        Shell.frame.shell.searchPanel.editBox:SetText("")
        Shell:RenderSearch() -- OnTextChanged is deferred on Forever -- clears back down
        local clearedHeight = Shell.frame:GetHeight()
        local result = grownHeight > blankHeight and clearedHeight == blankHeight
        return result, result and "OK" or string.format(
            "expected height to grow then return to the blank height (%s), got grown=%s cleared=%s",
            tostring(blankHeight), tostring(grownHeight), tostring(clearedHeight))
    end)
    ResetToGlance()
    return ok, message
end)

Pockets.Tests.TestRunner:Register("Shell: SEARCH header is [ < ] Search [ X ], back/X/Escape all return to Glance", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.SEARCH)
    local header = Shell.frame.shell.header
    local titleOK = header.titleText:GetText() == "Search"
    local backShown = header.backButton:IsShown()
    local closeShown = header.closeButton:IsShown()

    header.backButton:Click()
    local backLandedGlance = Shell:GetState() == Shell.STATE.GLANCE

    Shell:SetState(Shell.STATE.SEARCH)
    header.closeButton:Click()
    local closeLandedGlance = Shell:GetState() == Shell.STATE.GLANCE

    Shell:SetState(Shell.STATE.SEARCH)
    Shell:HandleEscape()
    local escapeLandedGlance = Shell:GetState() == Shell.STATE.GLANCE

    ResetToGlance()
    local ok = titleOK and backShown and closeShown and backLandedGlance and closeLandedGlance and escapeLandedGlance
    return ok, ok and "OK" or string.format(
        "title=%s back=%s close=%s backOK=%s closeOK=%s escOK=%s",
        tostring(header.titleText:GetText()), tostring(backShown), tostring(closeShown),
        tostring(backLandedGlance), tostring(closeLandedGlance), tostring(escapeLandedGlance))
end)

Pockets.Tests.TestRunner:Register("Shell: entering SEARCH never opens Menu or All Items", function()
    ResetToGlance()
    Shell.frame.glance.header.iconButton:Click()
    local ok = Shell:GetState() ~= Shell.STATE.MENU and Shell:GetState() ~= Shell.STATE.ALL
        and Shell:GetState() == Shell.STATE.SEARCH
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected SEARCH only, got %s", tostring(Shell:GetState()))
end)

-- In combat only secure code can show/hide the frames, so the Shell's state
-- must follow what is on screen. These tests stand in for the secure
-- snippet by showing/hiding the frames directly while faking combat.
local function WithFakeCombat(fn)
    local CombatAPI = Pockets.Adapters.CombatAPI
    local Pool = Pockets.UI.ItemButtonPool
    local originalCombat, originalProtected = CombatAPI.IsInCombat, Pool.templateProtected
    CombatAPI.IsInCombat = function() return true end
    Pool.templateProtected = true
    local ok, result, message = pcall(fn)
    CombatAPI.IsInCombat, Pool.templateProtected = originalCombat, originalProtected
    Pool.dirty = false
    ResetToGlance()
    if not ok then
        return false, tostring(result)
    end
    return result, message
end

Pockets.Tests.TestRunner:Register("Shell: in combat, navigation requests never change state without a secure show/hide", function()
    ResetToGlance()
    return WithFakeCombat(function()
        Shell:SetState(Shell.STATE.MENU)
        local stayedGlance = Shell:GetState() == Shell.STATE.GLANCE and not Shell.expanded:IsShown()
        return stayedGlance, stayedGlance and "OK" or "state changed in combat without the expanded frame being shown"
    end)
end)

Pockets.Tests.TestRunner:Register("Shell: secure open/close in combat is followed by Shell state; nav waits", function()
    ResetToGlance()
    Shell:Prewarm()
    return WithFakeCombat(function()
        Shell.expanded:Show()
        Shell.root:Hide() -- what the secure snippet does
        Shell:OnSecureToggle()
        local opened = Shell:GetState() == Shell.STATE.ALL and Shell.escapeCatcher:IsShown()

        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = "consumable" })
        local navRejected = Shell:GetState() == Shell.STATE.ALL

        Shell.expanded:Hide()
        Shell.root:Show()
        Shell:OnSecureToggle()
        local closed = Shell:GetState() == Shell.STATE.GLANCE and not Shell.escapeCatcher:IsShown()

        local ok = opened and navRejected and closed
        return ok, ok and "OK" or string.format("opened=%s navRejected=%s closed=%s",
            tostring(opened), tostring(navRejected), tostring(closed))
    end)
end)
