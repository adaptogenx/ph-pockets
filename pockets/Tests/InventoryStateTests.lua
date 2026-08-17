--[[
    Tests/InventoryStateTests.lua - Aggregate capacity math (TDD §24.1)

    Full bag-scan/diff behavior requires live container APIs and is covered
    by the manual acceptance matrix (TESTING_GUIDE.md) and future in-game
    tests. These tests exercise the pure aggregate helpers that don't
    require a real bag scan.
]]

local _, Pockets = ...

local InventoryState = Pockets.Services.InventoryState

Pockets.Tests.TestRunner:Register("InventoryState: capacity result shape", function()
    local result = InventoryState:BuildCapacityResult({ used = 55, total = 70 })
    local ok = result.used == 55 and result.total == 70 and result.free == 15
        and math.abs(result.utilization - (55 / 70)) < 0.0001
    return ok, ok and "OK" or "capacity result fields did not match expected shape"
end)

Pockets.Tests.TestRunner:Register("InventoryState: zero-total capacity does not divide by zero", function()
    local result = InventoryState:BuildCapacityResult({ used = 0, total = 0 })
    local ok = result.utilization == 0
    return ok, ok and "OK" or string.format("expected utilization 0, got %s", tostring(result.utilization))
end)

Pockets.Tests.TestRunner:Register("InventoryState: general vs ammo are independent pools", function()
    InventoryState.generalCapacity = InventoryState:BuildCapacityResult({ used = 68, total = 68 })
    InventoryState.ammoCapacity = InventoryState:BuildCapacityResult({ used = 4, total = 16 })

    local general = InventoryState:GetGeneralCapacity()
    local ammo = InventoryState:GetAmmoCapacity()
    local ok = general.free == 0 and ammo.free == 12
    return ok, ok and "OK" or "general-full-while-ammo-has-space scenario failed"
end)

Pockets.Tests.TestRunner:Register("InventoryState: carried quantity defaults to zero for unseen item", function()
    local qty = InventoryState:GetCarriedQuantity(-1)
    return qty == 0, qty == 0 and "OK" or string.format("expected 0, got %s", tostring(qty))
end)

Pockets.Tests.TestRunner:Register("InventoryState: bag-full ETA sampling uses GENERAL capacity only, never ammo", function()
    local BagAPI = Pockets.Adapters.BagAPI
    local CapacityEstimator = Pockets.Services.CapacityEstimator
    local originalScan = BagAPI.ScanAllBags
    local originalCounts = BagAPI.GetCapacityCounts

    -- Stub the adapter boundary (no live bag scan needed): empty bags so
    -- BuildRecord never runs, and a GENERAL/AMMO split that would be
    -- wrong if ETA sampling ever blended the two pools.
    BagAPI.ScanAllBags = function() return {} end
    BagAPI.GetCapacityCounts = function()
        return { general = { used = 10, total = 20 }, ammo = { used = 5, total = 16 } }
    end

    CapacityEstimator:Reset("test")
    InventoryState:Refresh("test")

    BagAPI.ScanAllBags = originalScan
    BagAPI.GetCapacityCounts = originalCounts

    local last = CapacityEstimator.samples[#CapacityEstimator.samples]
    local ok = last and last.usedSlots == 10 and last.totalSlots == 20
    return ok, ok and "OK" or "estimator sample did not match GENERAL capacity (ammo may have leaked in)"
end)

Pockets.Tests.TestRunner:Register("InventoryState: AggregateRecords collapses split stacks into one itemID entry", function()
    local records = {
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 20, bagID = 0, slotID = 1 },
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 20, bagID = 0, slotID = 2 },
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 20, bagID = 0, slotID = 3 },
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 3, bagID = 0, slotID = 4 },
    }
    local aggregates = InventoryState:AggregateRecords(records)
    local ok = #aggregates == 1 and aggregates[1].totalQuantity == 63 and #aggregates[1].stacks == 4
    return ok, ok and "OK" or string.format(
        "expected 1 aggregate at 63 total across 4 stacks, got %d aggregates, total=%s",
        #aggregates, ok and "" or tostring(aggregates[1] and aggregates[1].totalQuantity))
end)

-- Physical stack resolver (.plans/Pockets_Glance_UI.md §7) picks the
-- SMALLEST unlocked stack, not just any/the first unlocked one - less
-- disruptive to manipulate. slotID 1 (qty 20) is locked and skipped;
-- between the two unlocked stacks (40, 3), the smaller (slotID 3) wins.
Pockets.Tests.TestRunner:Register("ItemButtonPool.ToButtonRecord: sums totalQuantity into quantity, prefers the smallest unlocked stack", function()
    local agg = {
        itemID = 100, itemLink = "item:100", texture = 1, quality = 1, totalQuantity = 63,
        stacks = {
            { bagID = 0, slotID = 1, quantity = 20, isLocked = true },
            { bagID = 0, slotID = 2, quantity = 40, isLocked = false },
            { bagID = 0, slotID = 3, quantity = 3, isLocked = false },
        },
    }
    local record = Pockets.UI.ItemButtonPool.ToButtonRecord(agg)
    local ok = record.quantity == 63 and record.bagID == 0 and record.slotID == 3 and record.interactive == true
    return ok, ok and "OK" or string.format(
        "expected quantity=63 slotID=3(smallest unlocked), got quantity=%s slotID=%s",
        tostring(record.quantity), tostring(record.slotID))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool.ToButtonRecord: no stacks means non-interactive", function()
    local agg = { itemID = 1, texture = 1, totalQuantity = 0, stacks = {} }
    local record = Pockets.UI.ItemButtonPool.ToButtonRecord(agg)
    local ok = record.interactive == false and record.bagID == nil
    return ok, ok and "OK" or "expected a stack-less aggregate to be non-interactive"
end)

Pockets.Tests.TestRunner:Register("InventoryState: AggregateRecords keeps distinct itemIDs separate, in first-seen order", function()
    local records = {
        { itemID = 200, name = "Linen Cloth", quantity = 10, bagID = 0, slotID = 1 },
        { itemID = 300, name = "Wool Cloth", quantity = 5, bagID = 0, slotID = 2 },
        { itemID = 200, name = "Linen Cloth", quantity = 8, bagID = 0, slotID = 3 },
    }
    local aggregates = InventoryState:AggregateRecords(records)
    local ok = #aggregates == 2 and aggregates[1].itemID == 200 and aggregates[1].totalQuantity == 18
        and aggregates[2].itemID == 300 and aggregates[2].totalQuantity == 5
    return ok, ok and "OK" or "expected two distinct aggregates in first-seen order"
end)
