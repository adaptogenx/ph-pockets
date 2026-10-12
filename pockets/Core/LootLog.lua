--[[
    Core/LootLog.lua - Bounded, persisted feed of items the player LOOTED
    (Loot Log). Not a ledger: no sales, purchases, gold, mail, crafting or
    other bag changes - only items that arrived while looting.

    Pockets-owned and fully standalone: nothing here reads pH. The entry
    shape (id, time, kind, itemID/itemLink/quantity) is deliberately plain
    so pH can consume it later through an optional API without Pockets
    depending on pH.

    WHAT COUNTS AS LOOT, AND DEDUPLICATION
    One source, so one acquisition can never be recorded twice: the
    aggregate per-itemID POSITIVE delta from InventoryState:Refresh() (the
    same acquisition-vs-movement rule RecentItems uses, TDD §8.2), fed in
    through ObserveAcquisition. That delta alone cannot tell loot from a
    vendor purchase, mail, quest reward or crafting result, so it is only
    accepted while a LOOT CONTEXT is active: the loot window is open, or
    closed within LOOT_CONTEXT_GRACE_SECONDS (bag updates arrive shortly
    after the window closes, especially with auto-loot). Sales and
    purchases happen with a merchant window and never a loot window, so
    they are never logged. CHAT_MSG_LOOT is intentionally NOT used (locale-
    dependent text parse and a second signal for the same acquisition).
    Known gap: items awarded by a group-loot roll after the window closed
    arrive outside a loot context and are not logged.
    No attribution (mob/NPC) is recorded.

    Order: entries are newest-first by a monotonically increasing `id`
    that is persisted, so simultaneous events keep their insertion order
    across /reload. `time` is wall-clock (time()) for display; `id` is
    the ordering key.
]]

local _, Pockets = ...

Pockets.Services.LootLog = Pockets.Services.LootLog or {}
local LootLog = Pockets.Services.LootLog

local Constants = Pockets.Constants

LootLog.store = LootLog.store or { nextId = 1, entries = {} }
LootLog.entries = LootLog.store.entries -- same table as store.entries
LootLog.revision = LootLog.revision or 0
LootLog.lootWindowOpen = false
LootLog.lootClosedAt = nil
LootLog.clock = LootLog.clock or time

local KIND_ITEM = "item"
LootLog.KIND = { ITEM = KIND_ITEM }

local function Push(self, entry)
    entry.id = self.store.nextId
    self.store.nextId = entry.id + 1
    entry.time = self.clock()

    table.insert(self.entries, 1, entry)
    while #self.entries > Constants.LOOT_LOG_MAX do
        table.remove(self.entries)
    end

    self.revision = self.revision + 1
    Pockets.Services.EventBus:Publish(Constants.DOMAIN_EVENT.LOOT_LOGGED, entry)
    return entry
end

-- itemLink may be nil (kept as-is; the UI falls back to ItemAPI). Never
-- dropped for missing metadata - rendering resolves it later.
function LootLog:RecordItem(itemID, quantity, itemLink)
    if not itemID or not quantity or quantity <= 0 then
        return nil
    end
    return Push(self, { kind = KIND_ITEM, itemID = itemID, quantity = quantity, itemLink = itemLink })
end

-- Loot window tracking (LOOT_OPENED / LOOT_CLOSED).
function LootLog:SetLootWindowOpen(isOpen)
    self.lootWindowOpen = isOpen and true or false
    if not isOpen then
        self.lootClosedAt = self.clock()
    end
end

function LootLog:IsLootContextActive()
    if self.lootWindowOpen then
        return true
    end
    return self.lootClosedAt ~= nil
        and (self.clock() - self.lootClosedAt) <= Constants.LOOT_CONTEXT_GRACE_SECONDS
end

-- The single entry point for bag-derived acquisitions: records only while
-- a loot context is active (see header). Returns the entry or nil.
function LootLog:ObserveAcquisition(itemID, quantity, itemLink)
    if not self:IsLootContextActive() then
        return nil
    end
    return self:RecordItem(itemID, quantity, itemLink)
end

-- Newest first. Returns the live table when no limit is given.
function LootLog:GetEntries(limit)
    if not limit or limit >= #self.entries then
        return self.entries
    end
    local out = {}
    for i = 1, limit do
        out[i] = self.entries[i]
    end
    return out
end

function LootLog:GetRevision()
    return self.revision
end

-- Mutates in place so persistence (store.entries) is never orphaned.
function LootLog:Clear()
    for i = #self.entries, 1, -1 do
        table.remove(self.entries, i)
    end
    self.revision = self.revision + 1
end

-- Adopts the table WoW persists (PocketsCharDB.lootLog) as the live
-- store - same in-place-mutation reliance RecentItems:LoadPersisted
-- documents. Drops malformed entries instead of trusting a corrupted or
-- hand-edited save, re-sorts newest-first by id, trims to the bound, and
-- makes sure nextId stays above every surviving id so ordering never
-- regresses after a reload.
function LootLog:LoadPersisted(saved)
    if type(saved) ~= "table" then
        return
    end
    if type(saved.entries) ~= "table" then
        saved.entries = {}
    end
    local entries = saved.entries
    local maxId = 0
    for i = #entries, 1, -1 do
        local e = entries[i]
        -- Money/other legacy kinds from earlier versions are dropped.
        local valid = type(e) == "table" and type(e.id) == "number" and type(e.time) == "number"
            and e.kind == KIND_ITEM and e.itemID and (e.quantity or 0) > 0
        if valid then
            maxId = math.max(maxId, e.id)
        else
            table.remove(entries, i)
        end
    end
    table.sort(entries, function(a, b) return a.id > b.id end)
    while #entries > Constants.LOOT_LOG_MAX do
        table.remove(entries)
    end
    if type(saved.nextId) ~= "number" or saved.nextId <= maxId then
        saved.nextId = maxId + 1
    end
    self.store = saved
    self.entries = entries
    self.revision = self.revision + 1
end
