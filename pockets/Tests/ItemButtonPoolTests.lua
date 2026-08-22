--[[
    Tests/ItemButtonPoolTests.lua - Count-fontstring visibility (TDD §24.1)
    and secure right-click binding.

    Count/template tests need a real button (ItemButtonTemplate), so those
    run in-client via /pockets test run. Secure-binding helpers are pure
    enough to exercise with a mock button (no live bag scan).
]]

local _, Pockets = ...

local ItemButtonPool = Pockets.UI.ItemButtonPool
local BagAPI = Pockets.Adapters.BagAPI
local InventoryState = Pockets.Services.InventoryState

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

Pockets.Tests.TestRunner:Register("ItemButtonPool: pooled buttons are protected SecureActionButtons", function()
    local button = ItemButtonPool:Acquire(UIParent)
    local ok = button.IsProtected and button:IsProtected() == true
    ItemButtonPool:ReleaseAll(UIParent)
    return ok, ok and "OK" or "expected pooled item buttons to be protected (SecureActionButtonTemplate)"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure binds right-click use to the physical bag slot", function()
    if Pockets.Adapters.CombatAPI:IsInCombat() then
        return true, "SKIP: secure attributes cannot be written during combat"
    end
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, bagID = 0, slotID = 5,
    })
    local type2 = button.GetAttribute and button:GetAttribute("type2")
    local item2 = button.GetAttribute and button:GetAttribute("item2")
    ItemButtonPool:ReleaseAll(UIParent)
    local ok = type2 == "item" and item2 == "0 5"
    return ok, ok and "OK" or string.format(
        "expected type2=item item2='0 5', got type2=%s item2=%s",
        tostring(type2), tostring(item2))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure clears secure use on a non-interactive record", function()
    if Pockets.Adapters.CombatAPI:IsInCombat() then
        return true, "SKIP: secure attributes cannot be written during combat"
    end
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, bagID = 0, slotID = 5,
    })
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, interactive = false,
    })
    local type2 = button.GetAttribute and button:GetAttribute("type2")
    local item2 = button.GetAttribute and button:GetAttribute("item2")
    ItemButtonPool:ReleaseAll(UIParent)
    local ok = type2 == nil and item2 == nil
    return ok, ok and "OK" or string.format(
        "expected cleared type2/item2, got type2=%s item2=%s",
        tostring(type2), tostring(item2))
end)

local function MockSecureButton()
    local attrs = {}
    return {
        attrs = attrs,
        SetAttribute = function(self, key, value)
            self.attrs[key] = value
        end,
        GetAttribute = function(self, key)
            return self.attrs[key]
        end,
    }
end

Pockets.Tests.TestRunner:Register("ItemButtonPool: ApplySecureUseBinding writes type2/item2 out of combat", function()
    local button = MockSecureButton()
    ItemButtonPool.ApplySecureUseBinding(button, 1, 12, false)
    local ok = button.attrs.type2 == "item" and button.attrs.item2 == "1 12"
    return ok, ok and "OK" or string.format(
        "expected type2=item item2='1 12', got type2=%s item2=%s",
        tostring(button.attrs.type2), tostring(button.attrs.item2))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: ApplySecureUseBinding defers SetAttribute during combat", function()
    local button = MockSecureButton()
    ItemButtonPool.ApplySecureUseBinding(button, 0, 3, false)
    ItemButtonPool.ApplySecureUseBinding(button, 2, 8, true)
    local unchanged = button.attrs.type2 == "item" and button.attrs.item2 == "0 3"
    local pending = button.pendingSecureBagID == 2 and button.pendingSecureSlotID == 8
    ItemButtonPool.ApplySecureUseBinding(button, nil, nil, false)
    local ok = unchanged and pending
    return ok, ok and "OK" or "expected combat rebinding to leave live attributes unchanged and record a pending slot"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: FlushPendingSecureBindings applies deferred combat rebinding", function()
    local button = MockSecureButton()
    ItemButtonPool.ApplySecureUseBinding(button, 4, 1, true)
    ItemButtonPool:FlushPendingSecureBindings(false)
    local ok = button.attrs.type2 == "item" and button.attrs.item2 == "4 1"
        and button.pendingSecureBagID == nil
    return ok, ok and "OK" or string.format(
        "expected flushed item2='4 1', got type2=%s item2=%s",
        tostring(button.attrs.type2), tostring(button.attrs.item2))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: HandleInsecureClick pickups on left-click and does not UseItem on right-click", function()
    local previousItems = InventoryState.items
    InventoryState.items = {
        ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 4242, quantity = 5 },
    }

    local used, pickedBag, pickedSlot = false, nil, nil
    local origUse, origPickup = BagAPI.UseItem, BagAPI.PickupItem
    BagAPI.UseItem = function()
        used = true
    end
    BagAPI.PickupItem = function(_, bagID, slotID)
        pickedBag, pickedSlot = bagID, slotID
    end

    local origModified = IsModifiedClick
    IsModifiedClick = function()
        return false
    end

    local button = {
        interactive = true,
        bagID = 0,
        slotID = 1,
        itemID = 4242,
        itemLink = "item:4242",
    }

    ItemButtonPool.HandleInsecureClick(button, "RightButton")
    local rightUsed, rightPicked = used, pickedBag
    local rightOk = rightUsed == false and rightPicked == nil

    ItemButtonPool.HandleInsecureClick(button, "LeftButton")
    local leftOk = pickedBag == 0 and pickedSlot == 1 and used == false

    BagAPI.UseItem = origUse
    BagAPI.PickupItem = origPickup
    IsModifiedClick = origModified
    InventoryState.items = previousItems

    local ok = rightOk and leftOk
    return ok, ok and "OK" or string.format(
        "right-click used=%s picked=%s; left-click bag=%s slot=%s used=%s",
        tostring(rightUsed), tostring(rightPicked), tostring(pickedBag), tostring(pickedSlot), tostring(used))
end)
