--[[
    UI/FlowLayout.lua - Pure dynamic item-flow packing for the full
    inventory window (PRD/UI_SPEC full-inventory dynamic layout).

    Categories flow left-to-right, top-to-bottom like wrapped text, not
    fixed-height sections. A category normally starts on a fresh row; it
    may instead continue ("inline") on the tail of the previous
    category's last row when that row is under 50% used AND the whole
    next label plus at least one item still fits there. No frame/widget
    creation happens here - inputs are plain numbers, outputs are plain
    pixel placements, so this is fully unit-testable without a live UI
    and swappable for a smarter layout later.
]]

local _, Pockets = ...

Pockets.UI.FlowLayout = Pockets.UI.FlowLayout or {}
local FlowLayout = Pockets.UI.FlowLayout

-- categories: array of { categoryID, labelWidth, itemCount }, in display
--   order. Categories with itemCount <= 0 are skipped entirely (never
--   reserve a row for an empty category).
-- opts: { rowWidth, itemSize, gap, labelHeight }
-- Returns: {
--   contentHeight = number,
--   categoryPlacements = {
--     { categoryID, labelX, labelY, labelWidth, labelHeight,
--       itemPlacements = { { index, x, y }, ... } },
--     ...
--   },
-- }
function FlowLayout:Plan(categories, opts)
    local rowWidth = opts.rowWidth
    local itemSize = opts.itemSize
    local gap = opts.gap
    local labelHeight = opts.labelHeight

    local cursorX, cursorY = 0, 0
    local categoryPlacements = {}

    for _, category in ipairs(categories) do
        local itemCount = category.itemCount or 0
        if itemCount > 0 then
            local isFirstPlaced = #categoryPlacements == 0
            local canInline = false
            if not isFirstPlaced then
                -- usedWidth/remainingWidth per the packing heuristic: the
                -- previous category's final row must be under 50% used,
                -- and this category's whole label plus at least one item
                -- must still fit in what's left of that row.
                local usedWidth = cursorX > 0 and (cursorX - gap) or 0
                local remainingWidth = rowWidth - cursorX
                canInline = usedWidth < (rowWidth * 0.5)
                    and remainingWidth >= (category.labelWidth + gap + itemSize)
            end

            local labelX, labelY, labelH
            if canInline then
                labelX, labelY, labelH = cursorX, cursorY, labelHeight
                cursorX = cursorX + category.labelWidth + gap
            else
                if cursorX > 0 then
                    -- Move past the previous category's last item row.
                    cursorY = cursorY + itemSize + gap
                end
                labelX, labelY, labelH = 0, cursorY, labelHeight
                cursorY = cursorY + labelHeight + gap
                cursorX = 0
            end

            local itemPlacements = {}
            for i = 1, itemCount do
                if cursorX > 0 and (cursorX + itemSize) > rowWidth then
                    cursorX = 0
                    cursorY = cursorY + itemSize + gap
                end
                table.insert(itemPlacements, { index = i, x = cursorX, y = cursorY })
                cursorX = cursorX + itemSize + gap
            end

            table.insert(categoryPlacements, {
                categoryID = category.categoryID,
                labelX = labelX,
                labelY = labelY,
                labelWidth = category.labelWidth,
                labelHeight = labelH,
                itemPlacements = itemPlacements,
            })
        end
    end

    local contentHeight = 0
    if #categoryPlacements > 0 then
        contentHeight = cursorY + itemSize + gap
    end

    return { contentHeight = contentHeight, categoryPlacements = categoryPlacements }
end

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
