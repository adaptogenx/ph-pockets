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

Pockets.Tests.TestRunner:Register("Shell: PositionStrategy V1 anchor is TOPLEFT", function()
    local ok = Pockets.UI.PositionStrategy:GetRootAnchor() == "TOPLEFT"
    return ok, ok and "OK" or "expected the V1 position strategy to report TOPLEFT"
end)

--------------------------------------------------
-- Height: content-driven Menu, bounded Category/All (§5, §6, §18)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Menu body height is derived from category count, not a fixed giant viewport", function()
    local L = Pockets.Constants.LAYOUT
    local expected = #Pockets.Constants.CATEGORY_ORDER * L.MENU_ROW_HEIGHT + L.SHELL_PADDING * 2
    local ok = L.MENU_BODY_HEIGHT == expected and L.MENU_BODY_HEIGHT < L.SHELL_BODY_MAX_HEIGHT
    return ok, ok and "OK" or string.format(
        "expected MENU_BODY_HEIGHT (%s) to equal rows*height+padding (%s) and be smaller than the Category/All viewport",
        tostring(L.MENU_BODY_HEIGHT), tostring(expected))
end)

Pockets.Tests.TestRunner:Register("Shell: Menu is shorter overall than Category/All (no giant empty body)", function()
    Shell:SetState(Shell.STATE.MENU)
    local menuHeight = Shell.frame:GetHeight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local categoryHeight = Shell.frame:GetHeight()

    ResetToGlance()
    local ok = menuHeight < categoryHeight
    return ok, ok and "OK" or string.format("expected Menu (%s) shorter than Category (%s)",
        tostring(menuHeight), tostring(categoryHeight))
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
