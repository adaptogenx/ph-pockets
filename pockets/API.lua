--[[
    API.lua - Small public integration surface (TDD §18)

    Intentionally minimal. This is the seam future pH integration and any
    other consumer should use instead of reaching into Core/UI modules
    directly.
]]

local _, Pockets = ...

local API = Pockets.API

function API.GetBagStatus()
    return Pockets.Services.InventoryState:GetGeneralCapacity()
end

function API.GetAmmoStatus()
    return Pockets.Services.InventoryState:GetAmmoCapacity()
end

function API.GetBagETA()
    local estimator = Pockets.Services.CapacityEstimator
    return {
        state = estimator:GetState(),
        seconds = estimator:GetETA(),
        confidence = estimator:GetConfidence(),
    }
end

function API.GetRecentItems(limit)
    return Pockets.Services.RecentItems:GetRecent(limit)
end

-- Recent is a history view, not an assigned category (TDD §5.2/§10) - its
-- entries are resolved against current InventoryState here rather than in
-- UI code, so both the flyout and full inventory stay consistent
-- (UI_SPEC §9 "Recent Items", §10 "share item rendering code").
local function GetResolvedRecentItems()
    local out = {}
    for _, entry in ipairs(Pockets.Services.RecentItems:GetRecent(Pockets.Constants.RECENT_DISPLAY_LIMIT)) do
        local live = Pockets.Services.InventoryState:FindLiveRecordByItemID(entry.itemID)
        if live then
            table.insert(out, live)
        else
            local meta = Pockets.Adapters.ItemAPI:GetItemMetadata(entry.itemID, entry.itemLink)
            table.insert(out, {
                itemID = entry.itemID,
                itemLink = entry.itemLink,
                quantity = entry.quantity,
                texture = meta and meta.texture,
                quality = meta and meta.quality,
                interactive = false, -- no longer carried; never a fake action (UI_SPEC §9)
            })
        end
    end
    return out
end

-- Returns the item records to render for a category or "recent" (TDD §5.1
-- GetItemsByCategory + the Recent resolution above). Read-only lookup over
-- already-precomputed state - performs no bag scan/categorization
-- (UI_SPEC §6), safe to call on every hover.
function API.GetCategoryItems(categoryID)
    if categoryID == Pockets.Constants.CATEGORY.RECENT then
        return GetResolvedRecentItems()
    end
    return Pockets.Services.InventoryState:GetItemsByCategory(categoryID)
end

function API.GetCategorySummary()
    local summary = {}
    for _, categoryID in ipairs(Pockets.Constants.CATEGORY_ORDER) do
        local count
        if categoryID == Pockets.Constants.CATEGORY.RECENT then
            count = #Pockets.Services.RecentItems:GetRecent(Pockets.Constants.RECENT_DISPLAY_LIMIT)
        else
            count = 0
            for _, item in ipairs(Pockets.Services.InventoryState:GetItemsByCategory(categoryID)) do
                count = count + item.quantity
            end
        end
        table.insert(summary, {
            categoryID = categoryID,
            label = Pockets.Constants.CATEGORY_LABEL[categoryID],
            icon = Pockets.Constants.CATEGORY_ICON[categoryID],
            count = count,
        })
    end
    return summary
end

function API.GetCarriedQuantity(itemID)
    return Pockets.Services.InventoryState:GetCarriedQuantity(itemID)
end

function API.Open()
    Pockets.UI.FullInventory:Show()
end

function API.Close()
    Pockets.UI.FullInventory:Hide()
end

function API.Toggle()
    Pockets.UI.FullInventory:Toggle()
end

function API.ToggleFullInventory()
    Pockets.UI.FullInventory:Toggle()
end

function API.Subscribe(eventName, callback, owner)
    Pockets.Services.EventBus:Subscribe(eventName, callback, owner)
end
