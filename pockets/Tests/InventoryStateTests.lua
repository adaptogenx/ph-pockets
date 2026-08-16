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
