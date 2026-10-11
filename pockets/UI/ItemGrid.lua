--[[
    UI/ItemGrid.lua - Pure widget-placement helper: acquire/configure/place
    a flat list of item-button records into a content frame using
    FlowLayout:PlanFlat (Full Inventory redesign).

    Extracted from the logic duplicated across RenderCategoryGrid and
    RenderAll's search/per-category branches - no new interaction
    behavior, ItemButtonPool:Acquire/Configure unchanged.
]]

local _, Pockets = ...

Pockets.UI.ItemGrid = Pockets.UI.ItemGrid or {}
local ItemGrid = Pockets.UI.ItemGrid
local FlowLayout = Pockets.UI.FlowLayout

-- opts: x, y (top-left placement origin within `parent`), width (row
-- width to wrap within), itemSize, gap (both required, same values
-- FlowLayout:PlanFlat expects).
-- Returns: { height } - this grid's own content height only, never
-- including a header - callers own header height/section spacing.
function ItemGrid:Render(pool, parent, items, opts)
    local plan = FlowLayout:PlanFlat(#items, {
        rowWidth = opts.width,
        itemSize = opts.itemSize,
        gap = opts.gap,
    })

    for _, placement in ipairs(plan.itemPlacements) do
        local button = pool:Acquire(parent)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x + placement.x, -(opts.y + placement.y))
        pool:Configure(button, items[placement.index])
        button:Show()
    end

    return { height = plan.contentHeight }
end
