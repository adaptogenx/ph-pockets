--[[
    Tests/LootLogUITests.lua - UI/LootLog.lua layout/formatting and the
    Loot Log's integration with Shell (entry points, navigation, stable
    anchoring, scrollbar, empty state, Glance's ">>" button).

    PlanRows is tested with a fake `measure` so the wrapping/height
    arithmetic is verified independent of real font metrics; Shell tests
    use a throwaway log store and restore the player's real one.
]]

local _, Pockets = ...

local LootLogView = Pockets.UI.LootLog
local LootLog = Pockets.Services.LootLog
local Shell = Pockets.UI.Shell
local Constants = Pockets.Constants
local L = Constants.LAYOUT
local TestRunner = Pockets.Tests.TestRunner

local LINEN = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
local COWL = "|cff0070dd|Hitem:9999::::::::|h[Wizard's Cowl of the Eagle]|h|r"

local function WithFreshLog(fn)
    local saved = {
        store = LootLog.store, entries = LootLog.entries, revision = LootLog.revision,
        lastMoney = LootLog.lastMoney, clock = LootLog.clock,
    }
    LootLog.store = { nextId = 1, entries = {} }
    LootLog.entries = LootLog.store.entries
    LootLog.clock = function() return 1000 end
    local ok, a, b = pcall(fn)
    LootLog.store, LootLog.entries, LootLog.revision = saved.store, saved.entries, saved.revision
    LootLog.lastMoney, LootLog.clock = saved.lastMoney, saved.clock
    if not ok then
        Shell:SetState(Shell.STATE.GLANCE)
        error(a, 0)
    end
    return a, b
end

--------------------------------------------------
-- Formatting
--------------------------------------------------

TestRunner:Register("LootLog UI: quantity 1 is omitted, quantity > 1 shows x N", function()
    local ok = LootLogView:FormatQuantity(1) == "" and LootLogView:FormatQuantity(nil) == ""
        and LootLogView:FormatQuantity(2) == "\195\1512" and LootLogView:FormatQuantity(20) == "\195\15120"
    return ok, ok and "OK" or "quantity formatting wrong"
end)

TestRunner:Register("LootLog UI: timestamp is HH:MM with no seconds", function()
    local text = LootLogView:FormatTime(1700000000)
    local ok = text:match("^%d%d:%d%d$") ~= nil
    return ok, ok and "OK" or ("got " .. text)
end)

TestRunner:Register("LootLog UI: item text uses the link's quality color and bare name", function()
    local text = LootLogView:ItemText({ kind = "item", itemID = 9999, itemLink = COWL, quantity = 1 })
    local ok = text == "|cff0070ddWizard's Cowl of the Eagle|r"
    return ok, ok and "OK" or ("got " .. text)
end)

TestRunner:Register("LootLog UI: item text appends quantity only when > 1", function()
    local one = LootLogView:ItemText({ kind = "item", itemID = 2589, itemLink = LINEN, quantity = 1 })
    local two = LootLogView:ItemText({ kind = "item", itemID = 2589, itemLink = LINEN, quantity = 2 })
    local ok = one == "|cffffffffLinen Cloth|r" and two == "|cffffffffLinen Cloth|r \195\1512"
    return ok, ok and "OK" or string.format("got %q / %q", one, two)
end)

TestRunner:Register("LootLog UI: uncached item with no link falls back without erroring", function()
    local ok, text = pcall(LootLogView.ItemText, LootLogView, { kind = "item", itemID = 987654321, quantity = 1 })
    return ok and type(text) == "string" and text ~= "", ok and "OK" or tostring(text)
end)

TestRunner:Register("LootLog UI: money text is negative-aware and uses the shared formatter", function()
    local gain = LootLogView:MoneyText({ kind = "money", copper = 213 })
    local loss = LootLogView:MoneyText({ kind = "money", copper = -4500 })
    local ok = gain == "2s 13c" and loss == "-45s"
    return ok, ok and "OK" or string.format("got %q / %q", gain, loss)
end)

--------------------------------------------------
-- Pure layout (fake measure)
--------------------------------------------------

local LINE = 12
local function Measure(lines)
    return function(entry, width) return (lines[entry.id] or 1) * LINE end
end

local function Entries()
    return {
        { id = 3, kind = "item", itemID = 1, quantity = 1 },
        { id = 2, kind = "money", copper = 100 },
        { id = 1, kind = "item", itemID = 2, quantity = 1 },
    }
end

TestRunner:Register("LootLog layout: short item stays one line (height = icon/line + padding)", function()
    local rows = LootLogView:PlanRows(Entries(), 250, Measure({}))
    local expected = math.max(LINE, L.GLANCE_METRIC_ICON_SIZE) + L.LOOT_ROW_PAD_Y * 2
    local ok = rows[1].height == expected
    return ok, ok and "OK" or string.format("expected %s, got %s", expected, rows[1].height)
end)

TestRunner:Register("LootLog layout: wrapped item grows its row; variable heights accumulate exactly", function()
    local entries = Entries()
    local rows, total = LootLogView:PlanRows(entries, 250, Measure({ [3] = 1, [2] = 1, [1] = 3 }))
    local pad = L.LOOT_ROW_PAD_Y * 2
    local h1 = math.max(LINE, L.GLANCE_METRIC_ICON_SIZE) + pad
    local h3 = 3 * LINE + pad
    local ok = rows[1].y == 0 and rows[2].y == h1 and rows[3].y == h1 + rows[2].height
        and rows[3].height == h3 and total == rows[1].height + rows[2].height + h3
        and rows[3].height > rows[1].height
    return ok, ok and "OK" or "row offsets/total did not follow per-row heights"
end)

TestRunner:Register("LootLog layout: item text gets the width after timestamp + icon; money starts at the icon column", function()
    local rows = LootLogView:PlanRows(Entries(), 250, Measure({}))
    local lootLeft = L.LOOT_TIME_WIDTH + L.LOOT_COLUMN_GAP
    local itemLeft = lootLeft + L.GLANCE_METRIC_ICON_SIZE + L.LOOT_COLUMN_GAP
    local ok = rows[1].textLeft == itemLeft and rows[1].textWidth == 250 - itemLeft
        and rows[2].textLeft == lootLeft and rows[2].textWidth == 250 - lootLeft
    return ok, ok and "OK" or "column math wrong"
end)

TestRunner:Register("LootLog layout: width passed to measure is the remaining content width", function()
    local seen = {}
    LootLogView:PlanRows(Entries(), 250, function(entry, width) seen[entry.id] = width; return LINE end)
    local ok = seen[3] == seen[1] and seen[2] > seen[3]
    return ok, ok and "OK" or "item rows must be narrower than money rows by the icon column"
end)

TestRunner:Register("LootLog layout: a row is never shorter than its icon", function()
    local rows = LootLogView:PlanRows(Entries(), 250, function() return 1 end)
    local ok = rows[1].height >= L.GLANCE_METRIC_ICON_SIZE + L.LOOT_ROW_PAD_Y * 2
    return ok, ok and "OK" or "row height ignored the icon"
end)

TestRunner:Register("LootLog layout: timestamp column fits HH:MM and never wraps", function()
    local view = LootLogView:Create(CreateFrame("Frame", nil, UIParent))
    local scratch = view.parent:CreateFontString(nil, "ARTWORK", Pockets.UI.PHUI.Fonts.SMALL)
    scratch:SetText("00:00")
    local ok = scratch:GetStringWidth() <= L.LOOT_TIME_WIDTH
    return ok, ok and "OK" or string.format("'00:00' is %s wide, column is %s", scratch:GetStringWidth(), L.LOOT_TIME_WIDTH)
end)

--------------------------------------------------
-- Shell integration
--------------------------------------------------

TestRunner:Register("LootLog Shell: Glance header scroll icon opens Loot Log; Back returns to Glance", function()
    return WithFreshLog(function()
        Shell:SetState(Shell.STATE.GLANCE)
        Shell.frame.glance.header.lootButton:Click()
        local opened = Shell:GetState() == Shell.STATE.LOOT
        Shell:GoBack()
        local back = Shell:GetState() == Shell.STATE.GLANCE
        local ok = opened and back
        return ok, ok and "OK" or string.format("opened=%s back=%s", tostring(opened), tostring(back))
    end)
end)

TestRunner:Register("LootLog Shell: opened from Category, Back returns to that same Category", function()
    return WithFreshLog(function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Constants.CATEGORY.JUNK })
        Shell.frame.shell.header.lootButton:Click()
        local opened = Shell:GetState() == Shell.STATE.LOOT
        Shell:GoBack()
        local ok = opened and Shell:GetState() == Shell.STATE.CATEGORY
            and Shell.context.categoryID == Constants.CATEGORY.JUNK
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "Back did not restore the originating Category"
    end)
end)

TestRunner:Register("LootLog Shell: X and Escape dismiss straight to Glance", function()
    return WithFreshLog(function()
        Shell:OpenLootLog()
        Shell.frame.shell.header.closeButton:Click()
        local viaX = Shell:GetState() == Shell.STATE.GLANCE
        Shell:OpenLootLog()
        Shell:HandleEscape()
        local ok = viaX and Shell:GetState() == Shell.STATE.GLANCE
        return ok, ok and "OK" or "X/Escape did not return to Glance"
    end)
end)

TestRunner:Register("LootLog Shell: header shows title, hides + and scroll icons", function()
    return WithFreshLog(function()
        Shell:SetState(Shell.STATE.GLANCE)
        Shell:OpenLootLog()
        local header = Shell.frame.shell.header
        local ok = header.titleText:GetText() == "Loot Log" and not header.plusButton:IsShown()
            and not header.lootButton:IsShown() and header.closeButton:IsShown() and header.backButton:IsShown()
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "Loot Log header chrome wrong"
    end)
end)

TestRunner:Register("LootLog Shell: scroll icon matches the other expanded-header icon buttons' size", function()
    return WithFreshLog(function()
        Shell:SetState(Shell.STATE.MENU)
        local button = Shell.frame.shell.header.lootButton
        local ok = button:GetWidth() == L.SHELL_HEADER_SIDE_WIDTH and button:IsShown()
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "scroll icon size drifted from SHELL_HEADER_SIDE_WIDTH"
    end)
end)

TestRunner:Register("LootLog Shell: anchor is identical across Glance -> Loot Log -> Glance", function()
    return WithFreshLog(function()
        Shell:SetState(Shell.STATE.GLANCE)
        local p1, _, r1, x1, y1 = Shell.frame:GetPoint()
        Shell:OpenLootLog()
        local p2, _, r2, x2, y2 = Shell.frame:GetPoint()
        Shell:GoBack()
        local p3, _, r3, x3, y3 = Shell.frame:GetPoint()
        local ok = p1 == p2 and p2 == p3 and r1 == r2 and r2 == r3 and x1 == x2 and x2 == x3 and y1 == y2 and y2 == y3
        return ok, ok and "OK" or "TOPLEFT anchor moved"
    end)
end)

TestRunner:Register("LootLog Shell: width matches the other expanded views", function()
    return WithFreshLog(function()
        Shell:OpenLootLog()
        local ok = Shell.frame:GetWidth() == L.SHELL_WIDTH
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "Loot Log width differs from SHELL_WIDTH"
    end)
end)

TestRunner:Register("LootLog Shell: empty state shows 'No recent loot.' and no scrollbar", function()
    return WithFreshLog(function()
        Shell:OpenLootLog()
        local view = Shell.frame.shell.lootView
        local ok = view.emptyText:IsShown() and view.emptyText:GetText() == "No recent loot."
            and not Shell.frame.shell.scrollBar:IsShown()
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "empty state wrong"
    end)
end)

TestRunner:Register("LootLog Shell: few rows - rows shown, no scrollbar, empty text hidden", function()
    return WithFreshLog(function()
        LootLog:RecordItem(2589, 2, LINEN)
        LootLog:RecordMoney(213)
        LootLog:RecordMoney(-4500)
        Shell:OpenLootLog()
        local view = Shell.frame.shell.lootView
        local ok = view.rows[1]:IsShown() and view.rows[3]:IsShown() and not view.rows[4]
            and not view.emptyText:IsShown() and not Shell.frame.shell.scrollBar:IsShown()
        -- Newest first: the -45s expense is on top.
        ok = ok and view.rows[1].text:GetText() == "-45s" and view.rows[3].entry.kind == "item"
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "short log rendering wrong"
    end)
end)

TestRunner:Register("LootLog Shell: many rows - scrollbar shown, opens at the newest (top)", function()
    return WithFreshLog(function()
        for i = 1, 60 do
            LootLog:RecordItem(2589, i, LINEN)
        end
        Shell:OpenLootLog()
        local ok = Shell.frame.shell.scrollBar:IsShown() and Shell.frame.shell.scrollFrame:GetVerticalScroll() == 0
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "expected a scrollbar and a top-of-list start"
    end)
end)

TestRunner:Register("LootLog Shell: reopening after scrolling starts at the top again", function()
    return WithFreshLog(function()
        for i = 1, 60 do LootLog:RecordMoney(i) end
        Shell:OpenLootLog()
        Shell.frame.shell.scrollBar.slider:SetValue(100)
        Shell:GoBack()
        Shell:OpenLootLog()
        local ok = Shell.frame.shell.scrollFrame:GetVerticalScroll() == 0
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "reopened Loot Log kept an old scroll offset"
    end)
end)

TestRunner:Register("LootLog Shell: a new event while viewing the newest keeps the newest visible", function()
    return WithFreshLog(function()
        for i = 1, 60 do LootLog:RecordMoney(i) end
        Shell:OpenLootLog()
        LootLog:RecordMoney(999)
        Shell:Render() -- RefreshLootLog's deferred render, run synchronously
        local view = Shell.frame.shell.lootView
        local ok = Shell.frame.shell.scrollFrame:GetVerticalScroll() == 0 and view.rows[1].entry.copper == 999
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "newest entry not on top at offset 0"
    end)
end)

TestRunner:Register("LootLog Shell: re-render keeps the player's scroll position", function()
    return WithFreshLog(function()
        for i = 1, 60 do LootLog:RecordMoney(i) end
        Shell:OpenLootLog()
        Shell.frame.shell.scrollBar.slider:SetValue(80)
        Shell:Render()
        local ok = math.abs(Shell.frame.shell.scrollFrame:GetVerticalScroll() - 80) < 0.5
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "scroll offset lost on re-render"
    end)
end)

TestRunner:Register("LootLog Shell: no render work while Loot Log is not the visible state", function()
    return WithFreshLog(function()
        Shell:SetState(Shell.STATE.GLANCE)
        local renders = 0
        local original = Shell.RenderLoot
        Shell.RenderLoot = function(self, ...) renders = renders + 1; return original(self, ...) end
        LootLog:RecordMoney(5)
        Shell:RefreshLootLog()
        Shell.RenderLoot = original
        local ok = renders == 0
        return ok, ok and "OK" or "Loot Log rendered while hidden"
    end)
end)

TestRunner:Register("LootLog Shell: item rows have a tooltip handler; money rows are not interactive", function()
    return WithFreshLog(function()
        LootLog:RecordItem(2589, 1, LINEN)
        LootLog:RecordMoney(10)
        Shell:OpenLootLog()
        local rows = Shell.frame.shell.lootView.rows
        local ok = rows[2].entry.kind == "item" and rows[2]:GetScript("OnEnter") ~= nil and rows[2]:IsMouseEnabled()
            and not rows[1]:IsMouseEnabled()
        Shell:SetState(Shell.STATE.GLANCE)
        return ok, ok and "OK" or "row interactivity wrong"
    end)
end)

--------------------------------------------------
-- Glance: third icon + ">>"
--------------------------------------------------

TestRunner:Register("Glance: adding Loot Log icon and >> does not change Glance's size", function()
    Shell:SetState(Shell.STATE.GLANCE)
    local ok = Shell.frame:GetWidth() == L.GLANCE_WIDTH
        and Shell.frame:GetHeight() == Constants:GlanceContentHeight(Shell:ShouldShowAmmoRow(
            Pockets.Services.InventoryState:GetAmmoCapacity()))
    return ok, ok and "OK" or "Glance size changed"
end)

TestRunner:Register("Glance: Loot Log icon is the same size as Search and '+'", function()
    Shell:SetState(Shell.STATE.GLANCE)
    local header = Shell.frame.glance.header
    local ok = header.lootButton:GetWidth() == header.iconButton:GetWidth()
        and header.lootButton:GetWidth() == header.plusButton:GetWidth()
    return ok, ok and "OK" or "icon sizes differ"
end)

TestRunner:Register("Glance: header icons stay inside the header's width", function()
    Shell:SetState(Shell.STATE.GLANCE)
    local header = Shell.frame.glance.header
    local ok = header.icons[1]:GetLeft() >= header:GetLeft() - 0.01
    return ok, ok and "OK" or "icons overflow the header's left edge"
end)

TestRunner:Register("Glance: '>>' follows the last Recent icon, stays inside the strip, and opens Loot Log", function()
    local strip
    local ok, detail
    local function Item(i) return { itemID = 700 + i, quantity = 1, name = "T" .. i, bagID = 0, slotID = i } end
    local original = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function() return { Item(1), Item(2) } end
    Shell:SetState(Shell.STATE.GLANCE)
    Shell:Render()
    strip = Shell.frame.glance.recentStrip
    local expectedLeft = 2 * (L.GLANCE_RECENT_ICON_SIZE + L.GLANCE_RECENT_ICON_GAP)
    local point, _, _, x = strip.moreButton:GetPoint()
    ok = strip.moreButton:IsShown() and point == "LEFT" and x == expectedLeft
        and x + strip.moreButton:GetWidth() <= strip:GetWidth()
    detail = string.format("shown=%s x=%s expected=%s", tostring(strip.moreButton:IsShown()), tostring(x), expectedLeft)
    strip.moreButton:Click()
    ok = ok and Shell:GetState() == Shell.STATE.LOOT and Shell.context.returnState == Shell.STATE.GLANCE
    Pockets.API.GetAggregatedCategoryItems = original
    Shell:SetState(Shell.STATE.GLANCE)
    return ok, ok and "OK" or detail
end)

TestRunner:Register("Glance: '>>' is hidden when there are no Recent icons, and fits even with a full strip", function()
    local original = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function() return {} end
    Shell:SetState(Shell.STATE.GLANCE)
    Shell:Render()
    local strip = Shell.frame.glance.recentStrip
    local hiddenWhenEmpty = not strip.moreButton:IsShown()

    local many = {}
    for i = 1, 12 do many[i] = { itemID = 800 + i, quantity = 1, name = "T" .. i, bagID = 0, slotID = i } end
    Pockets.API.GetAggregatedCategoryItems = function() return many end
    Shell:Render()
    local point, _, _, x = strip.moreButton:GetPoint()
    local fits = strip.moreButton:IsShown() and x + strip.moreButton:GetWidth() <= strip:GetWidth()
    Pockets.API.GetAggregatedCategoryItems = original
    Shell:SetState(Shell.STATE.GLANCE)
    local ok = hiddenWhenEmpty and fits
    return ok, ok and "OK" or string.format("hiddenWhenEmpty=%s fits=%s", tostring(hiddenWhenEmpty), tostring(fits))
end)
