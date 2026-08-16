--[[
    Adapters/BagAPI.lua - Isolates direct bag/container API access (TDD §3.1, §8, §25.4)

    Rule: every other module must go through this adapter instead of calling
    Blizzard container APIs directly. This keeps client-version compatibility
    logic (Classic container API vs C_Container) in one place and lets
    the domain layer work against normalized Pockets-owned tables.
]]

local _, Pockets = ...

Pockets.Adapters.BagAPI = Pockets.Adapters.BagAPI or {}
local BagAPI = Pockets.Adapters.BagAPI

-- Backpack (0) + normal equipped bags (1-4) are general-purpose in WoW Classic.
-- Ammo/soul/quiver bags are detected by bag family and reported separately.
BagAPI.GENERAL_BAG_IDS = { 0, 1, 2, 3, 4 }

local CONTAINER_ITEM_FAMILY_AMMO = 2 -- BAG_FILTER_ASSIGNED family bit used by quivers/ammo pouches

-- Returns the number of slots for a given bag ID, or 0 if the bag doesn't exist.
function BagAPI:GetBagSlotCount(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bagID) or 0
    end
    return GetContainerNumSlots(bagID) or 0
end

-- Returns a normalized slot info table, or nil if the slot is empty.
-- Shape: { itemID, itemLink, quantity, quality, locked, texture }
function BagAPI:GetSlotInfo(bagID, slotIndex)
    local itemID, itemLink, quantity, quality, locked, texture

    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotIndex)
        if not info then
            return nil
        end
        itemID = info.itemID
        itemLink = info.hyperlink
        quantity = info.stackCount
        quality = info.quality
        locked = info.isLocked
        texture = info.iconFileID
    else
        local icon, count, isLocked, itemQuality
        icon, count, isLocked, itemQuality = GetContainerItemInfo(bagID, slotIndex)
        if not icon then
            return nil
        end
        itemLink = GetContainerItemLink and GetContainerItemLink(bagID, slotIndex)
        quantity = count
        quality = itemQuality
        locked = isLocked
        texture = icon
        itemID = GetContainerItemID and GetContainerItemID(bagID, slotIndex)
    end

    if not itemID then
        return nil
    end

    return {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity or 1,
        quality = quality,
        isLocked = locked and true or false,
        texture = texture,
    }
end

-- Returns whether the given bagID is a general-purpose (Bags) container.
function BagAPI:IsGeneralBag(bagID)
    for _, generalID in ipairs(self.GENERAL_BAG_IDS) do
        if generalID == bagID then
            return true
        end
    end
    return false
end

-- Returns whether the given bagID is an ammo pouch/quiver, using the bag's
-- item family. Treats unknown/undetectable bag families conservatively as
-- non-general rather than ammo (TDD §22 Error Handling).
function BagAPI:IsAmmoBag(bagID)
    if bagID == 0 then
        return false -- backpack is never a specialized bag
    end

    local invSlot = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
    if not invSlot then
        return false
    end

    local bagLink = GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
    if not bagLink then
        return false
    end

    local _, _, _, _, _, _, _, _, bagFamily = GetItemInfo(bagLink)
    if not bagFamily then
        return false
    end

    -- Bit 1 (value 2) is the ammo/quiver bag family in WoW Classic's item family bitmask.
    return bagFamily == CONTAINER_ITEM_FAMILY_AMMO
end

-- Enumerates every bag currently equipped (backpack + all four bag slots),
-- returning { bagID = ..., slotCount = ... } for non-empty bags.
function BagAPI:GetEquippedBags()
    local bags = {}
    for bagID = 0, 4 do
        local slotCount = self:GetBagSlotCount(bagID)
        if slotCount and slotCount > 0 then
            table.insert(bags, { bagID = bagID, slotCount = slotCount })
        end
    end
    return bags
end

-- Takes a full scan snapshot of all equipped bags.
-- Returns an array of { bagID, slotIndex, itemID, itemLink, quantity, quality, isLocked, texture, capacityClass }.
function BagAPI:ScanAllBags()
    local snapshot = {}
    for _, bag in ipairs(self:GetEquippedBags()) do
        local capacityClass = self:IsAmmoBag(bag.bagID)
            and Pockets.Constants.CAPACITY_CLASS.AMMO
            or Pockets.Constants.CAPACITY_CLASS.GENERAL

        for slotIndex = 1, bag.slotCount do
            local slot = self:GetSlotInfo(bag.bagID, slotIndex)
            if slot then
                slot.bagID = bag.bagID
                slot.slotIndex = slotIndex
                slot.capacityClass = capacityClass
                table.insert(snapshot, slot)
            end
        end
    end
    return snapshot
end

-- Returns { used, total } general-purpose slot counts from a snapshot's bag list.
function BagAPI:GetCapacityCounts()
    local generalUsed, generalTotal = 0, 0
    local ammoUsed, ammoTotal = 0, 0

    for _, bag in ipairs(self:GetEquippedBags()) do
        local isAmmo = self:IsAmmoBag(bag.bagID)
        local freeSlots = self:GetBagSlotCount(bag.bagID) - self:CountUsedSlots(bag.bagID, bag.slotCount)

        if isAmmo then
            ammoTotal = ammoTotal + bag.slotCount
            ammoUsed = ammoUsed + (bag.slotCount - freeSlots)
        else
            generalTotal = generalTotal + bag.slotCount
            generalUsed = generalUsed + (bag.slotCount - freeSlots)
        end
    end

    return {
        general = { used = generalUsed, total = generalTotal },
        ammo = { used = ammoUsed, total = ammoTotal },
    }
end

function BagAPI:CountUsedSlots(bagID, slotCount)
    local used = 0
    for slotIndex = 1, slotCount do
        if self:GetSlotInfo(bagID, slotIndex) then
            used = used + 1
        end
    end
    return used
end
