--[[
    Tests/BagAPITests.lua - Ammo vs. general capacity split (TDD §7, §24.1)

    BagAPI:ClassifyCapacity is a pure aggregation step (bag entries in,
    {general, ammo} out) so the ammo-bag-equipped rule can be verified
    without a live bag scan: ammo capacity must come from bag family
    (isAmmo), never from what item category happens to be carried.
]]

local _, Pockets = ...

local BagAPI = Pockets.Adapters.BagAPI

--------------------------------------------------
-- IsAmmoFamily (Ammo detection debugging pass §7/§8): pure bitmask
-- check, split out of IsAmmoBag specifically so this rule is testable
-- without a live inventory API. Root cause of "Ammo capacity never
-- appears": IsAmmoBag used to read GetItemInfo()'s 9th return value
-- (itemEquipLoc, a STRING) and compare it to the number 2 - always
-- false. Family comes from GetItemFamily(), a bitmask (Quiver=2,
-- Ammo Pouch=4), not GetItemInfo().
--------------------------------------------------

Pockets.Tests.TestRunner:Register("BagAPI: IsAmmoFamily recognizes Quiver (family bit 2)", function()
    local ok = BagAPI:IsAmmoFamily(2) == true
    return ok, ok and "OK" or "expected family 2 (Quiver) to classify as ammo"
end)

Pockets.Tests.TestRunner:Register("BagAPI: IsAmmoFamily recognizes Ammo Pouch (family bit 4)", function()
    local ok = BagAPI:IsAmmoFamily(4) == true
    return ok, ok and "OK" or "expected family 4 (Ammo Pouch) to classify as ammo"
end)

Pockets.Tests.TestRunner:Register("BagAPI: IsAmmoFamily rejects a non-ammo bag family", function()
    local ok = BagAPI:IsAmmoFamily(1) == false and BagAPI:IsAmmoFamily(8) == false
    return ok, ok and "OK" or "expected non-ammo family bits to classify as not-ammo"
end)

Pockets.Tests.TestRunner:Register("BagAPI: IsAmmoFamily rejects nil (undetectable family)", function()
    local ok = BagAPI:IsAmmoFamily(nil) == false
    return ok, ok and "OK" or "expected nil family to classify conservatively as not-ammo"
end)

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

--------------------------------------------------
-- ResolveSlotCount: mail/AH can report 0 slots for bags still equipped
-- (Glance collapsed 66/76 -> 10/20). Live counts win; cache holds the
-- last known size while equipped; unequipped bags drop to 0.
--------------------------------------------------

Pockets.Tests.TestRunner:Register("BagAPI: ResolveSlotCount prefers a live slot count", function()
    local count, incomplete = BagAPI.ResolveSlotCount(16, 20, true)
    local ok = count == 16 and incomplete == false
    return ok, ok and "OK" or "expected the live API count to win over the cache"
end)

Pockets.Tests.TestRunner:Register("BagAPI: ResolveSlotCount keeps cached size when live count is 0 for an equipped bag", function()
    local count, incomplete = BagAPI.ResolveSlotCount(0, 16, true)
    local ok = count == 16 and incomplete == false
    return ok, ok and "OK" or "expected the cached size to hold while the bag is still equipped"
end)

Pockets.Tests.TestRunner:Register("BagAPI: ResolveSlotCount drops an unequipped bag even if a cache remains", function()
    local count, incomplete = BagAPI.ResolveSlotCount(0, 20, false)
    local ok = count == 0 and incomplete == false
    return ok, ok and "OK" or "expected an unequipped bag to contribute 0 slots"
end)

Pockets.Tests.TestRunner:Register("BagAPI: ResolveSlotCount marks equipped bags with no live count and no cache as incomplete", function()
    local count, incomplete = BagAPI.ResolveSlotCount(0, 0, true)
    local ok = count == 0 and incomplete == true
    return ok, ok and "OK" or "expected an equipped-but-unreadable bag to flag the scan incomplete"
end)

Pockets.Tests.TestRunner:Register("BagAPI: ClassifyCapacity of a single remaining bag matches the 10/20 Glance collapse", function()
    -- Documents the bug: if GetEquippedBags drops every bag whose live
    -- slot count is 0, capacity becomes whatever one bag still answered.
    local collapsed = BagAPI:ClassifyCapacity({
        { isAmmo = false, slotCount = 20, usedSlots = 10 },
    })
    local full = BagAPI:ClassifyCapacity({
        { isAmmo = false, slotCount = 16, usedSlots = 12 },
        { isAmmo = false, slotCount = 16, usedSlots = 16 },
        { isAmmo = false, slotCount = 16, usedSlots = 16 },
        { isAmmo = false, slotCount = 8, usedSlots = 8 },
        { isAmmo = false, slotCount = 20, usedSlots = 14 },
    })
    local ok = collapsed.general.used == 10 and collapsed.general.total == 20
        and full.general.used == 66 and full.general.total == 76
    return ok, ok and "OK" or "expected the 10/20 vs 66/76 split the Glance bug reported"
end)
