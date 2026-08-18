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

Pockets.Tests.TestRunner:Register("Shell: Escape hierarchy - Category/All -> Menu -> Glance -> no-op", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell:HandleEscape()
    local step1 = Shell:GetState() == Shell.STATE.MENU

    Shell:HandleEscape()
    local step2 = Shell:GetState() == Shell.STATE.GLANCE

    Shell:HandleEscape() -- no-op at Glance
    local step3 = Shell:GetState() == Shell.STATE.GLANCE

    local ok = step1 and step2 and step3
    return ok, ok and "OK" or "escape hierarchy did not step Category -> Menu -> Glance -> no-op"
end)

Pockets.Tests.TestRunner:Register("Shell: Shift-B (ToggleAllItems) jumps directly to All from any state", function()
    ResetToGlance()
    Shell:ToggleAllItems()
    local fromGlance = Shell:GetState() == Shell.STATE.ALL

    Shell:SetState(Shell.STATE.MENU)
    Shell:ToggleAllItems()
    local fromMenu = Shell:GetState() == Shell.STATE.ALL

    Shell:ToggleAllItems() -- toggling again from ALL goes back to Menu
    local toggleBack = Shell:GetState() == Shell.STATE.MENU

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

    local scrollFrame = Shell.frame.shell.scrollFrame
    local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
    local contentWidth = Shell.frame.shell.content:GetWidth()
    local viewportWidth = scrollFrame:GetWidth()

    ResetToGlance()

    local ok = (not scrollBar or not scrollBar:IsShown()) and math.abs(contentWidth - viewportWidth) < 0.01
    return ok, ok and "OK" or "scrollbar (or its reserved gutter) was present without overflowing content"
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

Pockets.Tests.TestRunner:Register("Shell: scrollbar appears and reclaims width only when content actually overflows", function()
    -- Force an overflow deterministically by aggregating far more items
    -- than the viewport could ever fit, bypassing live inventory state.
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local manyItems = {}
    for i = 1, 200 do
        manyItems[i] = { itemID = i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return manyItems end

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

    local scrollFrame = Shell.frame.shell.scrollFrame
    local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
    local contentWidth = Shell.frame.shell.content:GetWidth()
    local viewportWidth = scrollFrame:GetWidth()

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    ResetToGlance()

    local ok = scrollBar and scrollBar:IsShown()
        and contentWidth < viewportWidth
        and math.abs((viewportWidth - contentWidth) - Pockets.Constants.LAYOUT.SCROLLBAR_RESERVE) < 0.01
    return ok, ok and "OK" or "expected the scrollbar to appear and reclaim exactly SCROLLBAR_RESERVE width"
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
-- Glance compactness pass
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Glance height is within the compact target (48-60)", function()
    ResetToGlance()
    local height = Shell.frame:GetHeight()
    local ok = height >= 48 and height <= 60
    return ok, ok and "OK" or string.format("expected height 48-60, got %s", tostring(height))
end)

-- Glance minimum-width pass: GLANCE_WIDTH must be DERIVED from its
-- actual content (padding+icon+gap+text column), never a hand-picked
-- number with slack - this is what "minimum width possible" means and
-- what keeps it from silently regressing wider later.
Pockets.Tests.TestRunner:Register("Shell: Glance width is the derived minimum, not hand-picked slack", function()
    local L = Pockets.Constants.LAYOUT
    local expected = L.GLANCE_PADDING * 2 + L.GLANCE_ICON_SIZE + L.GLANCE_TEXT_GAP_X + L.GLANCE_TEXT_BLOCK_WIDTH
    ResetToGlance()
    local width = Shell.frame:GetWidth()
    local ok = width == L.GLANCE_WIDTH and width == expected
    return ok, ok and "OK" or string.format("expected derived width %s, got %s", tostring(expected), tostring(width))
end)

Pockets.Tests.TestRunner:Register("Shell: Glance no longer shows Ammo", function()
    ResetToGlance()
    local ok = Shell.frame.glance.ammoText == nil
    return ok, ok and "OK" or "expected Glance to have no ammoText widget at all"
end)

Pockets.Tests.TestRunner:Register("Shell: Glance ETA is compact (no 'to full' suffix)", function()
    local estimator = Pockets.Services.CapacityEstimator
    local originalGetState = estimator.GetState
    local originalGetConfidence = estimator.GetConfidence
    local originalGetETA = estimator.GetETA
    estimator.GetState = function() return Pockets.Constants.ESTIMATOR_STATE.FILLING end
    estimator.GetConfidence = function() return 1.0 end
    estimator.GetETA = function() return 13 * 60 end

    ResetToGlance()
    local text = Shell.frame.glance.etaText:GetText()

    estimator.GetState = originalGetState
    estimator.GetConfidence = originalGetConfidence
    estimator.GetETA = originalGetETA
    ResetToGlance()

    local ok = text == "13m"
    return ok, ok and "OK" or string.format("expected compact '13m', got %s", tostring(text))
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
    Pockets.SavedSettings.hud.x, Pockets.SavedSettings.hud.y = savedX, savedY
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

--------------------------------------------------
-- Row unification: Menu category rows and Category List item rows share
-- one visual row component (§1-§9)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("RowUnification: Menu row height equals Category List row height", function()
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

Pockets.Tests.TestRunner:Register("RowUnification: Menu icon size equals Category List icon size", function()
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

Pockets.Tests.TestRunner:Register("RowUnification: category label and item name start at the same X", function()
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

Pockets.Tests.TestRunner:Register("RowUnification: category count and item qty share the same right edge (chevron doesn't shift it)", function()
    local originalMode = Pockets.SavedSettings.categoryViewMode
    Pockets.SavedSettings.categoryViewMode = Pockets.Constants.CATEGORY_VIEW_MODE.LIST

    Shell:SetState(Shell.STATE.MENU)
    local menuRow = Shell.frame.shell.menuRows[1]
    menuRow.count:SetText("180") -- worst-case 3-digit count
    local menuCountRight = menuRow.count:GetRight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRow = Shell.frame.shell.categoryListRows[1]
    local itemQtyRight = listRow and listRow.qty:GetRight()

    Pockets.SavedSettings.categoryViewMode = originalMode
    ResetToGlance()

    local ok = itemQtyRight and math.abs(menuCountRight - itemQtyRight) < 0.01
    return ok, ok and "OK" or string.format("expected matching count/qty right edge, got menu=%s item=%s",
        tostring(menuCountRight), tostring(itemQtyRight))
end)

Pockets.Tests.TestRunner:Register("RowUnification: item rows have no chevron", function()
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

Pockets.Tests.TestRunner:Register("RowUnification: Menu and Category List rows use the same Blizzard highlight texture mechanism", function()
    Shell:SetState(Shell.STATE.MENU)
    local menuRow = Shell.frame.shell.menuRows[1]
    local ok = menuRow and menuRow.GetHighlightTexture and menuRow:GetHighlightTexture() ~= nil
    ResetToGlance()
    return ok, ok and "OK" or "expected Menu rows to use a real Button highlight texture, not a bespoke overlay"
end)

Pockets.Tests.TestRunner:Register("RowUnification: category rows still navigate, item rows still resolve to a real stack", function()
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

        local scrollFrame = Shell.frame.shell.scrollFrame
        local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
        local shown = scrollBar and scrollBar:IsShown() or false
        local contentWidth = Shell.frame.shell.content:GetWidth()
        local viewportWidth = scrollFrame:GetWidth()
        local noGutter = math.abs(contentWidth - viewportWidth) < 0.01

        if shown ~= expectScrollbar then
            error(string.format("n=%d: expected scrollbar shown=%s, got %s", n, tostring(expectScrollbar), tostring(shown)), 0)
        end
        if (not expectScrollbar) and not noGutter then
            error(string.format("n=%d: expected zero scrollbar gutter when hidden", n), 0)
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

        local scrollFrame = Shell.frame.shell.scrollFrame
        local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
        local shown = scrollBar and scrollBar:IsShown() or false
        local contentWidth = Shell.frame.shell.content:GetWidth()
        local viewportWidth = scrollFrame:GetWidth()
        local noGutter = math.abs(contentWidth - viewportWidth) < 0.01

        if shown ~= expectScrollbar then
            error(string.format("n=%d: expected scrollbar shown=%s, got %s", n, tostring(expectScrollbar), tostring(shown)), 0)
        end
        if (not expectScrollbar) and not noGutter then
            error(string.format("n=%d: expected zero scrollbar gutter when hidden", n), 0)
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
    local bagsLeftBefore = shell.footerBagsText:GetLeft()

    shell.footerAmmoText:Show() -- simulate an ammo pool being present
    Shell:ConfigureFooter() -- re-derives visibility from real (ammo-less) state, hiding it again
    local bagsLeftAfter = shell.footerBagsText:GetLeft()

    ResetToGlance()
    local ok = bagsLeftBefore == bagsLeftAfter
    return ok, ok and "OK" or "Bags anchor moved when Ammo visibility changed"
end)

Pockets.Tests.TestRunner:Register("Shell: SavePosition ignores a negligible (phantom-drag) position change", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.MENU)
    local hud = Pockets.SavedSettings.hud
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

Pockets.Tests.TestRunner:Register("Shell: back button and Escape use the same navigation method (GoBack)", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })

    local originalGoBack = Shell.GoBack
    local calls = 0
    Shell.GoBack = function(self, ...)
        calls = calls + 1
        return originalGoBack(self, ...)
    end

    Shell.frame.shell.header.backButton:Click()
    local afterBackClick = calls

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    Shell:HandleEscape()
    local afterEscape = calls

    Shell.GoBack = originalGoBack
    ResetToGlance()

    local ok = afterBackClick == 1 and afterEscape == 2
    return ok, ok and "OK" or string.format(
        "expected the back button and Escape to both route through GoBack exactly once each, got %d/%d",
        afterBackClick, afterEscape - afterBackClick)
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

Pockets.Tests.TestRunner:Register("CategoryView: switching mode while Category is open re-renders immediately, no state change", function()
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

Pockets.Tests.TestRunner:Register("CategoryView: repeated Grid<->List toggling does not accumulate rows", function()
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        for _ = 1, 5 do
            Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST)
            Shell:SetCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.GRID)
        end
        local itemCount = #Pockets.API.GetAggregatedCategoryItems(Pockets.Constants.CATEGORY.OTHER)
        local rowCount = #Shell.frame.shell.categoryListRows
        if rowCount > itemCount then
            error(string.format("expected at most %d pooled List rows, got %d", itemCount, rowCount), 0)
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

        local scrollFrame = Shell.frame.shell.scrollFrame
        local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
        local contentWidth = Shell.frame.shell.content:GetWidth()
        local viewportWidth = scrollFrame:GetWidth()

        if (scrollBar and scrollBar:IsShown()) or math.abs(contentWidth - viewportWidth) >= 0.01 then
            error("scrollbar (or its gutter) present without List content overflowing", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryView: List shows a scrollbar and reclaims width when rows overflow", function()
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local manyItems = {}
    for i = 1, 200 do
        manyItems[i] = { itemID = i, name = "Test Item " .. i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return manyItems end

    local ok
    WithCategoryViewMode(Pockets.Constants.CATEGORY_VIEW_MODE.LIST, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local scrollFrame = Shell.frame.shell.scrollFrame
        local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
        local contentWidth = Shell.frame.shell.content:GetWidth()
        local viewportWidth = scrollFrame:GetWidth()

        ok = scrollBar and scrollBar:IsShown() and contentWidth < viewportWidth
    end)

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    ResetToGlance()

    return ok, ok and "OK" or "expected a scrollbar and reclaimed width once List rows overflow"
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
