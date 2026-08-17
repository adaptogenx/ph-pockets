--[[
    Tests/FlowLayoutTests.lua - Dynamic category/item packing (pure, no
    live UI needed - UI/FlowLayout.lua takes/returns plain numbers).
]]

local _, Pockets = ...

local FlowLayout = Pockets.UI.FlowLayout

-- rowWidth=200, itemSize=40, gap=4, labelHeight=16 -> 4 items fit per
-- fresh row (4*44=176<=200+4trailing, 5th would need 220).
local OPTS = { rowWidth = 200, itemSize = 40, gap = 4, labelHeight = 16 }

Pockets.Tests.TestRunner:Register("FlowLayout: empty category list produces no placements, zero height", function()
    local plan = FlowLayout:Plan({ { categoryID = "a", labelWidth = 50, itemCount = 0 } }, OPTS)
    local ok = #plan.categoryPlacements == 0 and plan.contentHeight == 0
    return ok, ok and "OK" or "expected an empty-itemCount category to reserve nothing"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: one-row category (items <= columns per row)", function()
    local plan = FlowLayout:Plan({ { categoryID = "a", labelWidth = 50, itemCount = 3 } }, OPTS)
    local cat = plan.categoryPlacements[1]
    local ok = #cat.itemPlacements == 3
        and cat.itemPlacements[1].y == cat.itemPlacements[3].y -- same row
        and plan.contentHeight == 64 -- 16(label)+4(gap)+40(item)+4(gap)
    return ok, ok and "OK" or string.format("expected one row at height 64, got contentHeight=%s", tostring(plan.contentHeight))
end)

Pockets.Tests.TestRunner:Register("FlowLayout: multi-row category wraps onto a fresh row", function()
    local plan = FlowLayout:Plan({ { categoryID = "a", labelWidth = 50, itemCount = 5 } }, OPTS)
    local cat = plan.categoryPlacements[1]
    local ok = cat.itemPlacements[5].y > cat.itemPlacements[4].y and cat.itemPlacements[5].x == 0
    return ok, ok and "OK" or "expected item 5 to wrap onto a new row starting at x=0"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: exactly one overflow item stays alone on row 2", function()
    local plan = FlowLayout:Plan({ { categoryID = "a", labelWidth = 50, itemCount = 5 } }, OPTS)
    local cat = plan.categoryPlacements[1]
    local row1Y, row2Y = cat.itemPlacements[1].y, cat.itemPlacements[5].y
    local row1Count, row2Count = 0, 0
    for _, p in ipairs(cat.itemPlacements) do
        if p.y == row1Y then row1Count = row1Count + 1
        elseif p.y == row2Y then row2Count = row2Count + 1 end
    end
    local ok = row1Count == 4 and row2Count == 1
    return ok, ok and "OK" or string.format("expected 4+1 split, got %d+%d", row1Count, row2Count)
end)

Pockets.Tests.TestRunner:Register("FlowLayout: final row <50% used permits inlining the next category", function()
    -- Category A: 9 items -> final row has 1 item (used width 40 of 200 = 20%, well under 50%).
    local plan = FlowLayout:Plan({
        { categoryID = "a", labelWidth = 50, itemCount = 9 },
        { categoryID = "b", labelWidth = 50, itemCount = 1 },
    }, OPTS)
    local catA, catB = plan.categoryPlacements[1], plan.categoryPlacements[2]
    local lastAItem = catA.itemPlacements[#catA.itemPlacements]
    local ok = catB.labelY == lastAItem.y and catB.labelX == lastAItem.x + OPTS.itemSize + OPTS.gap
    return ok, ok and "OK" or "expected category B's label to inline on category A's final (under-50%) row"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: final row at exactly 50% used does NOT inline", function()
    -- 1 item at itemSize=40 in a rowWidth=80 row is exactly 50% used.
    local opts = { rowWidth = 80, itemSize = 40, gap = 0, labelHeight = 16 }
    local plan = FlowLayout:Plan({
        { categoryID = "a", labelWidth = 10, itemCount = 1 },
        { categoryID = "b", labelWidth = 10, itemCount = 1 },
    }, opts)
    local catA, catB = plan.categoryPlacements[1], plan.categoryPlacements[2]
    local ok = catB.labelX == 0 and catB.labelY > catA.itemPlacements[1].y
    return ok, ok and "OK" or "expected exactly-50%-used final row to force a fresh row, not inline"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: final row >50% used does NOT inline", function()
    local opts = { rowWidth = 60, itemSize = 40, gap = 0, labelHeight = 16 }
    local plan = FlowLayout:Plan({
        { categoryID = "a", labelWidth = 10, itemCount = 1 }, -- 40/60 = 67% used
        { categoryID = "b", labelWidth = 10, itemCount = 1 },
    }, opts)
    local catA, catB = plan.categoryPlacements[1], plan.categoryPlacements[2]
    local ok = catB.labelX == 0 and catB.labelY > catA.itemPlacements[1].y
    return ok, ok and "OK" or "expected a >50%-used final row to force a fresh row, not inline"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: label fits alone but label+one item does not -> wrap", function()
    -- After category A (1 item), remaining row width is 156. A 130px
    -- label fits alone (130<=156) but label+gap+item (174) does not.
    local plan = FlowLayout:Plan({
        { categoryID = "a", labelWidth = 10, itemCount = 1 },
        { categoryID = "b", labelWidth = 130, itemCount = 1 },
    }, OPTS)
    local catA, catB = plan.categoryPlacements[1], plan.categoryPlacements[2]
    local ok = catB.labelX == 0 and catB.labelY > catA.itemPlacements[1].y
    return ok, ok and "OK" or "expected wrap when the label fits but label+item does not"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: a label never splits (label width never exceeds remaining row width)", function()
    local plan = FlowLayout:Plan({
        { categoryID = "a", labelWidth = 50, itemCount = 9 },
        { categoryID = "b", labelWidth = 50, itemCount = 6 },
        { categoryID = "c", labelWidth = 190, itemCount = 1 },
    }, OPTS)
    local ok = true
    for _, cat in ipairs(plan.categoryPlacements) do
        if cat.labelX + cat.labelWidth > OPTS.rowWidth then
            ok = false
        end
    end
    return ok, ok and "OK" or "a category label was placed wider than the available row"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: an inlined category's own items still wrap onto fresh rows", function()
    -- Category B inlines after A, but has more items than fit in the
    -- remaining space on that shared row - the rest must wrap to x=0.
    local plan = FlowLayout:Plan({
        { categoryID = "a", labelWidth = 50, itemCount = 9 }, -- leaves 1 item on final row (20% used)
        { categoryID = "b", labelWidth = 50, itemCount = 4 },
    }, OPTS)
    local catB = plan.categoryPlacements[2]
    local wrapped = false
    for _, p in ipairs(catB.itemPlacements) do
        if p.x == 0 then
            wrapped = true
        end
    end
    return wrapped, wrapped and "OK" or "expected at least one of category B's items to wrap onto a fresh row"
end)

Pockets.Tests.TestRunner:Register("FlowLayout: contentHeight matches the actual last row used", function()
    local plan = FlowLayout:Plan({ { categoryID = "a", labelWidth = 50, itemCount = 9 } }, OPTS)
    local cat = plan.categoryPlacements[1]
    local lastY = cat.itemPlacements[#cat.itemPlacements].y
    local ok = plan.contentHeight == lastY + OPTS.itemSize + OPTS.gap
    return ok, ok and "OK" or "contentHeight did not match the last placed row"
end)

Pockets.Tests.TestRunner:Register("FlowLayout.PlanFlat: wraps a flat item list with no labels", function()
    local plan = FlowLayout:PlanFlat(5, { rowWidth = 200, itemSize = 40, gap = 4 })
    local ok = #plan.itemPlacements == 5 and plan.itemPlacements[5].y > plan.itemPlacements[4].y
        and plan.itemPlacements[5].x == 0
    return ok, ok and "OK" or "expected a flat 5-item wrap with item 5 on a new row"
end)

Pockets.Tests.TestRunner:Register("FlowLayout.PlanFlat: zero items produces zero height", function()
    local plan = FlowLayout:PlanFlat(0, { rowWidth = 200, itemSize = 40, gap = 4 })
    local ok = plan.contentHeight == 0 and #plan.itemPlacements == 0
    return ok, ok and "OK" or "expected zero items to produce zero height"
end)
