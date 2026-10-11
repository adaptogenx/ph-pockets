--[[
    Core/LootLog.lua - Bounded, persisted feed of recent item and money
    changes (Loot Log). "What did I just get or spend?" - nothing more.
    Durable history/analytics stay pH's job.

    Pockets-owned and fully standalone: nothing here reads pH. The event
    shape (id, time, kind, itemID/itemLink/quantity | copper) is
    deliberately plain so pH can consume it later through an optional
    API without Pockets depending on pH.

    EVENT SOURCES AND DEDUPLICATION
    There is exactly ONE source per kind, so one player action can never
    be recorded twice:
      * items: InventoryState:Refresh()'s aggregate per-itemID POSITIVE
        delta (same acquisition-vs-movement rule RecentItems uses, TDD
        §8.2), fed in through RecordItem. This covers mob/chest loot,
        gathering, quest item rewards, vendor purchases and crafting
        results alike. CHAT_MSG_LOOT is intentionally NOT used: it would
        be a second signal for the same acquisition (and a locale-
        dependent text parse).
      * money: PLAYER_MONEY -> ObserveMoney(), a diff of successive
        GetMoney() values. CHAT_MSG_MONEY and QUEST_TURNED_IN's
        moneyReward are intentionally NOT used: both describe a change
        PLAYER_MONEY already reports. A repeated PLAYER_MONEY with an
        unchanged balance yields a zero delta and records nothing.
    No attribution (mob/NPC/quest) is recorded - WoW doesn't reliably
    say why money or an item changed.

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
LootLog.lastMoney = nil
LootLog.clock = LootLog.clock or time

local KIND_ITEM = "item"
local KIND_MONEY = "money"
LootLog.KIND = { ITEM = KIND_ITEM, MONEY = KIND_MONEY }

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

-- copper is signed: positive income, negative expense.
function LootLog:RecordMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper == 0 then
        return nil
    end
    return Push(self, { kind = KIND_MONEY, copper = copper })
end

-- Called on every PLAYER_MONEY with the current balance. The first call
-- only establishes the baseline (login must not look like income).
function LootLog:ObserveMoney(currentMoney)
    currentMoney = tonumber(currentMoney)
    if not currentMoney then
        return nil
    end
    local previous = self.lastMoney
    self.lastMoney = currentMoney
    if previous == nil then
        return nil
    end
    return self:RecordMoney(currentMoney - previous)
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
        local valid = type(e) == "table" and type(e.id) == "number" and type(e.time) == "number"
            and ((e.kind == KIND_ITEM and e.itemID and (e.quantity or 0) > 0)
                or (e.kind == KIND_MONEY and type(e.copper) == "number" and e.copper ~= 0))
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
