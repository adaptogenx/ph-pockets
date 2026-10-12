--[[
    Tests/FlowLayoutTests.lua - Pure item-grid wrap-flow geometry (no live
    UI needed - UI/FlowLayout.lua takes/returns plain numbers).

    The old multi-category "<50% -> inline next category" packing
    heuristic (FlowLayout:Plan) was removed in the Full Inventory redesign
    - every category now always starts a fresh row. This file only covers
    the remaining PlanFlat (flat wrap-grid) geometry.
]]

local _, Pockets = ...

local FlowLayout = Pockets.UI.FlowLayout

Pockets.Tests.TestRunner:Register("FlowLayout: Plan (the old <50% packing heuristic) is gone", function()
    local ok = FlowLayout.Plan == nil
    return ok, ok and "OK" or "expected FlowLayout:Plan to have been removed (Full Inventory redesign)"
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

Pockets.Tests.TestRunner:Register("FlowLayout.PlanFlat: exactly one overflow item stays alone on row 2", function()
    local plan = FlowLayout:PlanFlat(5, { rowWidth = 200, itemSize = 40, gap = 4 })
    local row1Y, row2Y = plan.itemPlacements[1].y, plan.itemPlacements[5].y
    local row1Count, row2Count = 0, 0
    for _, p in ipairs(plan.itemPlacements) do
        if p.y == row1Y then row1Count = row1Count + 1
        elseif p.y == row2Y then row2Count = row2Count + 1 end
    end
    local ok = row1Count == 4 and row2Count == 1
    return ok, ok and "OK" or string.format("expected 4+1 split, got %d+%d", row1Count, row2Count)
end)

Pockets.Tests.TestRunner:Register("FlowLayout.PlanFlat: contentHeight matches the actual last row used", function()
    local plan = FlowLayout:PlanFlat(9, { rowWidth = 200, itemSize = 40, gap = 4 })
    local lastY = plan.itemPlacements[#plan.itemPlacements].y
    local ok = plan.contentHeight == lastY + 40 + 4
    return ok, ok and "OK" or "contentHeight did not match the last placed row"
end)
