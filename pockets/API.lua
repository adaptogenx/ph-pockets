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

function API.GetCategorySummary()
    local summary = {}
    for _, categoryID in ipairs(Pockets.Constants.CATEGORY_ORDER) do
        local items = Pockets.Services.InventoryState:GetItemsByCategory(categoryID)
        local count = 0
        for _, item in ipairs(items) do
            count = count + item.quantity
        end
        table.insert(summary, {
            categoryID = categoryID,
            label = Pockets.Constants.CATEGORY_LABEL[categoryID],
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
