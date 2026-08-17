--[[
    Tests/BagAPITests.lua - Ammo vs. general capacity split (TDD §7, §24.1)

    BagAPI:ClassifyCapacity is a pure aggregation step (bag entries in,
    {general, ammo} out) so the ammo-bag-equipped rule can be verified
    without a live bag scan: ammo capacity must come from bag family
    (isAmmo), never from what item category happens to be carried.
]]

local _, Pockets = ...

local BagAPI = Pockets.Adapters.BagAPI

Pockets.Tests.TestRunner:Register("BagAPI: no quiver equipped - no ammo pool", function()
    local result = BagAPI:ClassifyCapacity({
        { isAmmo = false, slotCount = 16, usedSlots = 5 },
        { isAmmo = false, slotCount = 20, usedSlots = 10 },
    })
    local ok = result.ammo.total == 0 and result.ammo.used == 0
        and result.general.total == 36 and result.general.used == 15
    return ok, ok and "OK" or "expected zero ammo pool with only general bags equipped"
end)

Pockets.Tests.TestRunner:Register("BagAPI: ammo items carried in normal bags do not create an ammo pool", function()
    -- Item CONTENT is irrelevant to ClassifyCapacity - it only ever sees
    -- bag-level isAmmo/slotCount/usedSlots, never item categories. This
    -- documents that carrying arrows in a normal bag slot still counts
    -- those slots as GENERAL, never AMMO.
    local result = BagAPI:ClassifyCapacity({
        { isAmmo = false, slotCount = 16, usedSlots = 12 }, -- e.g. holds a stack of arrows
    })
    local ok = result.ammo.total == 0 and result.general.total == 16 and result.general.used == 12
    return ok, ok and "OK" or "carried ammo items must not create an ammo capacity pool"
end)

Pockets.Tests.TestRunner:Register("BagAPI: empty quiver equipped - ammo pool exists at 0 used", function()
    local result = BagAPI:ClassifyCapacity({
        { isAmmo = false, slotCount = 16, usedSlots = 5 },
        { isAmmo = true, slotCount = 16, usedSlots = 0 },
    })
    local ok = result.ammo.total == 16 and result.ammo.used == 0
        and result.general.total == 16 and result.general.used == 5
    return ok, ok and "OK" or "expected a 0/16 ammo pool for an equipped-but-empty quiver"
end)

Pockets.Tests.TestRunner:Register("BagAPI: partially filled quiver", function()
    local result = BagAPI:ClassifyCapacity({
        { isAmmo = true, slotCount = 16, usedSlots = 8 },
    })
    local ok = result.ammo.total == 16 and result.ammo.used == 8
    return ok, ok and "OK" or string.format("expected 8/16, got %d/%d", result.ammo.used, result.ammo.total)
end)

Pockets.Tests.TestRunner:Register("BagAPI: full quiver", function()
    local result = BagAPI:ClassifyCapacity({
        { isAmmo = true, slotCount = 16, usedSlots = 16 },
    })
    local ok = result.ammo.total == 16 and result.ammo.used == 16
    return ok, ok and "OK" or string.format("expected 16/16, got %d/%d", result.ammo.used, result.ammo.total)
end)

Pockets.Tests.TestRunner:Register("BagAPI: quiver slots are excluded from GENERAL capacity", function()
    local result = BagAPI:ClassifyCapacity({
        { isAmmo = false, slotCount = 20, usedSlots = 10 },
        { isAmmo = true, slotCount = 16, usedSlots = 12 },
    })
    local ok = result.general.total == 20 and result.general.used == 10
    return ok, ok and "OK" or "quiver slots leaked into GENERAL capacity"
end)
