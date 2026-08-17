--[[
    Tests/ItemButtonPoolTests.lua - Count-fontstring visibility (TDD §24.1)

    Needs a real button (ItemButtonTemplate), so this runs in-client via
    /pockets test run rather than as a pure logic test.
]]

local _, Pockets = ...

local ItemButtonPool = Pockets.UI.ItemButtonPool

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure shows the Count text for quantity > 1", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, { itemID = 1, texture = 1, quantity = 63 })

    local ok = button.Count and button.Count:IsShown() and button.Count:GetText() == "63"
    ItemButtonPool:ReleaseAll(UIParent)
    return ok, ok and "OK" or "expected Count fontstring shown with text '63' for quantity 63"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure hides the Count text for quantity == 1", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, { itemID = 1, texture = 1, quantity = 1 })

    local ok = button.Count == nil or not button.Count:IsShown()
    ItemButtonPool:ReleaseAll(UIParent)
    return ok, ok and "OK" or "expected Count fontstring hidden for quantity 1"
end)
