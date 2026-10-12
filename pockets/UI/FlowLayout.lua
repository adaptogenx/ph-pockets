--[[
    UI/FlowLayout.lua - Pure item-grid wrap-flow geometry (no frame/widget
    creation - inputs are plain numbers, outputs are plain pixel
    placements, fully unit-testable without a live UI).

    Full Inventory's multi-category "<50% width used -> inline next
    category" packing heuristic (formerly FlowLayout:Plan) was removed
    (Full Inventory redesign - every category now always starts a fresh
    row; Shell:RenderAll stacks CategoryHeader/ItemGrid sections directly,
    it no longer needs a shared multi-category planner).
]]

local _, Pockets = ...

Pockets.UI.FlowLayout = Pockets.UI.FlowLayout or {}
local FlowLayout = Pockets.UI.FlowLayout

-- Simple no-label wrap grid (used for flattened search results - "may
-- temporarily flatten categories into dense matching aggregated items").
-- opts: { rowWidth, itemSize, gap }
-- Returns: { contentHeight, itemPlacements = { { index, x, y }, ... } }
function FlowLayout:PlanFlat(itemCount, opts)
    local rowWidth = opts.rowWidth
    local itemSize = opts.itemSize
    local gap = opts.gap

    local x, y = 0, 0
    local itemPlacements = {}
    for i = 1, itemCount do
        if x > 0 and (x + itemSize) > rowWidth then
            x = 0
            y = y + itemSize + gap
        end
        table.insert(itemPlacements, { index = i, x = x, y = y })
        x = x + itemSize + gap
    end

    local contentHeight = itemCount > 0 and (y + itemSize + gap) or 0
    return { contentHeight = contentHeight, itemPlacements = itemPlacements }
end
