--[[
    Core/InventoryState.lua - Authoritative normalized inventory (TDD §5.1, §6, §8)

    Owns the current snapshot of carried items plus capacity aggregates.
    UI modules read from here; they must never rescan bags themselves
    (TDD §3.1). Refresh() is the single entry point that turns a raw
    BagAPI scan into normalized records, diffs it against the previous
    snapshot to find true acquisitions (TDD §8.2), updates the capacity
    estimator, and publishes domain events.
]]

local _, Pockets = ...

Pockets.Services.InventoryState = Pockets.Services.InventoryState or {}
local InventoryState = Pockets.Services.InventoryState

local Constants = Pockets.Constants
local EventBus = Pockets.Services.EventBus

InventoryState.items = InventoryState.items or {} -- key "bag:slot" -> normalized item record
InventoryState.previousQuantitiesByItemID = InventoryState.previousQuantitiesByItemID or nil
InventoryState.revision = InventoryState.revision or 0

-- Builds a normalized item record (TDD §6) from a raw BagAPI slot + cached metadata.
local function BuildRecord(slot)
    local meta = Pockets.Adapters.ItemAPI:GetItemMetadata(slot.itemID, slot.itemLink)
    local isQuestItem = meta and meta.status == "ready" and meta.classID == 12 or false

    local record = {
        key = slot.bagID .. ":" .. slot.slotIndex,
        bagID = slot.bagID,
        slotID = slot.slotIndex,
        itemID = slot.itemID,
        itemLink = slot.itemLink,
        quantity = slot.quantity,
        quality = slot.quality,
        isLocked = slot.isLocked,
        capacityClass = slot.capacityClass,
        texture = slot.texture,
        isQuestItem = isQuestItem,
    }

    if meta and meta.status == "ready" then
        record.name = meta.name
        record.texture = record.texture or meta.texture
        record.maxStack = meta.maxStack
        record.classID = meta.classID
        record.subclassID = meta.subclassID
        record.quality = record.quality or meta.quality
    end

    record.categoryID = Pockets.Services.ItemCategorizer:GetDisplayCategory(record)
    return record
end

-- Aggregates a list of normalized records into { [itemID] = totalQuantity }.
local function AggregateByItemID(records)
    local totals = {}
    for _, record in pairs(records) do
        if record.itemID then
            totals[record.itemID] = (totals[record.itemID] or 0) + record.quantity
        end
    end
    return totals
end

-- Diffs old vs. new aggregate totals and records positive deltas as
-- acquisitions in RecentItems (TDD §8.2). Negative deltas are ignored here;
-- they only matter for capacity/ETA which Refresh() handles separately.
local function RecordAcquisitions(oldTotals, newTotals, itemsByID)
    for itemID, newTotal in pairs(newTotals) do
        local oldTotal = oldTotals and oldTotals[itemID] or 0
        local delta = newTotal - oldTotal
        if delta > 0 then
            local sample = itemsByID[itemID]
            Pockets.Services.RecentItems:Record({
                itemID = itemID,
                quantity = delta,
                timestamp = GetTime(),
                itemLink = sample and sample.itemLink,
            })
        end
    end
end

-- Re-scans bags, normalizes, diffs against the previous snapshot, updates
-- capacity/estimator state, and publishes domain events. `reason` is a
-- free-form string used for debug logging only.
function InventoryState:Refresh(reason)
    local rawSlots = Pockets.Adapters.BagAPI:ScanAllBags()

    local newItems = {}
    local itemsByID = {}
    for _, slot in ipairs(rawSlots) do
        local record = BuildRecord(slot)
        newItems[record.key] = record
        itemsByID[record.itemID] = record
    end

    local oldTotals = self.previousQuantitiesByItemID
    local newTotals = AggregateByItemID(newItems)

    if oldTotals then
        RecordAcquisitions(oldTotals, newTotals, itemsByID)
    end

    self.items = newItems
    self.previousQuantitiesByItemID = newTotals
    self.revision = self.revision + 1

    local capacity = Pockets.Adapters.BagAPI:GetCapacityCounts()
    self.generalCapacity = self:BuildCapacityResult(capacity.general)
    self.ammoCapacity = self:BuildCapacityResult(capacity.ammo)

    Pockets.Services.CapacityEstimator:AddSample(GetTime(), capacity.general.used, capacity.general.total)

    EventBus:Publish(Constants.DOMAIN_EVENT.INVENTORY_CHANGED, { reason = reason })
    EventBus:Publish(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, self.generalCapacity)
end

function InventoryState:BuildCapacityResult(counts)
    local used, total = counts.used or 0, counts.total or 0
    return {
        used = used,
        total = total,
        free = total - used,
        utilization = total > 0 and (used / total) or 0,
    }
end

function InventoryState:GetGeneralCapacity()
    return self.generalCapacity or self:BuildCapacityResult({ used = 0, total = 0 })
end

function InventoryState:GetAmmoCapacity()
    return self.ammoCapacity or self:BuildCapacityResult({ used = 0, total = 0 })
end

function InventoryState:GetUtilization()
    return self:GetGeneralCapacity().utilization
end

function InventoryState:GetItems()
    return self.items
end

function InventoryState:GetItem(itemKey)
    return self.items[itemKey]
end

function InventoryState:GetItemsByCategory(categoryID)
    local out = {}
    for _, record in pairs(self.items) do
        if record.categoryID == categoryID then
            table.insert(out, record)
        end
    end
    return out
end

function InventoryState:GetCarriedQuantity(itemID)
    local totals = self.previousQuantitiesByItemID
    return (totals and totals[itemID]) or 0
end

function InventoryState:GetRevision()
    return self.revision
end
