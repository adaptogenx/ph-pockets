--[[
    Tests/APITests.lua - Recent-item resolution and category summary counts
    (UI_SPEC §9 "Recent Items", TDD §24.1)
]]

local _, Pockets = ...

local InventoryState = Pockets.Services.InventoryState
local RecentItems = Pockets.Services.RecentItems

Pockets.Tests.TestRunner:Register("InventoryState: FindLiveRecordByItemID finds carried item", function()
    InventoryState.items = { ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 777, quantity = 3 } }
    local found = InventoryState:FindLiveRecordByItemID(777)
    local ok = found and found.bagID == 0 and found.slotID == 1
    return ok and true or false, ok and "OK" or "expected to find live record for carried itemID"
end)

Pockets.Tests.TestRunner:Register("InventoryState: FindLiveRecordByItemID returns nil when not carried", function()
    InventoryState.items = {}
    local found = InventoryState:FindLiveRecordByItemID(999)
    return found == nil, found == nil and "OK" or "expected nil for uncarried itemID"
end)

Pockets.Tests.TestRunner:Register("API: recent category count is entry count, not quantity sum", function()
    InventoryState.items = {}
    RecentItems:Clear()
    RecentItems:Record({ itemID = 1, quantity = 20, timestamp = 1 })
    RecentItems:Record({ itemID = 2, quantity = 5, timestamp = 2 })

    local summary = Pockets.API.GetCategorySummary()
    local recentEntry
    for _, entry in ipairs(summary) do
        if entry.categoryID == Pockets.Constants.CATEGORY.RECENT then
            recentEntry = entry
        end
    end

    local ok = recentEntry and recentEntry.count == 2
    return ok and true or false,
        ok and "OK" or string.format("expected recent count 2, got %s", tostring(recentEntry and recentEntry.count))
end)

Pockets.Tests.TestRunner:Register("API: GetCategoryItems(recent) marks uncarried entries non-interactive", function()
    InventoryState.items = {}
    RecentItems:Clear()
    RecentItems:Record({ itemID = 42, quantity = 1, timestamp = 1, itemLink = "item:42" })

    local items = Pockets.API.GetCategoryItems(Pockets.Constants.CATEGORY.RECENT)
    local ok = #items == 1 and items[1].interactive == false
    return ok, ok and "OK" or "expected uncarried recent entry to be interactive=false"
end)

Pockets.Tests.TestRunner:Register("API: GetCategoryItems(recent) resolves carried entries to live bag/slot", function()
    InventoryState.items = { ["0:2"] = { key = "0:2", bagID = 0, slotID = 2, itemID = 88, quantity = 4 } }
    RecentItems:Clear()
    RecentItems:Record({ itemID = 88, quantity = 4, timestamp = 1 })

    local items = Pockets.API.GetCategoryItems(Pockets.Constants.CATEGORY.RECENT)
    local ok = #items == 1 and items[1].bagID == 0 and items[1].slotID == 2 and items[1].interactive ~= false
    return ok, ok and "OK" or "expected carried recent entry resolved to live bag/slot"
end)
