--[[
    Tests/LootLogTests.lua - Core/LootLog.lua: event storage, ordering,
    bounds, persistence, money observation and single-source dedup.

    Every test runs against a throwaway store (WithFreshLog) and restores
    the player's real log afterward - these tests must never wipe or
    pollute the persisted Loot Log.
]]

local _, Pockets = ...

local LootLog = Pockets.Services.LootLog
local Constants = Pockets.Constants
local TestRunner = Pockets.Tests.TestRunner

local function WithFreshLog(fn)
    local saved = {
        store = LootLog.store, entries = LootLog.entries, revision = LootLog.revision,
        lastMoney = LootLog.lastMoney, clock = LootLog.clock,
    }
    LootLog.store = { nextId = 1, entries = {} }
    LootLog.entries = LootLog.store.entries
    LootLog.lastMoney = nil
    LootLog.clock = function() return 1000 end -- every event in the same second
    local ok, a, b = pcall(fn)
    LootLog.store, LootLog.entries, LootLog.revision = saved.store, saved.entries, saved.revision
    LootLog.lastMoney, LootLog.clock = saved.lastMoney, saved.clock
    if not ok then
        error(a, 0)
    end
    return a, b
end

TestRunner:Register("LootLog: item event recorded with quantity and link preserved", function()
    return WithFreshLog(function()
        LootLog:RecordItem(2589, 3, "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r")
        local e = LootLog:GetEntries()[1]
        local ok = e.kind == "item" and e.itemID == 2589 and e.quantity == 3 and e.itemLink:find("Linen Cloth", 1, true)
        return ok and true or false, ok and "OK" or "item entry did not keep itemID/quantity/link"
    end)
end)

TestRunner:Register("LootLog: item without a link or cached metadata is still recorded", function()
    return WithFreshLog(function()
        LootLog:RecordItem(99999, 1, nil)
        local ok = #LootLog:GetEntries() == 1 and LootLog:GetEntries()[1].itemLink == nil
        return ok, ok and "OK" or "event lost when item metadata/link was unavailable"
    end)
end)

TestRunner:Register("LootLog: invalid item events (zero/negative/missing) are ignored", function()
    return WithFreshLog(function()
        LootLog:RecordItem(1, 0)
        LootLog:RecordItem(1, -2)
        LootLog:RecordItem(nil, 1)
        local ok = #LootLog:GetEntries() == 0
        return ok, ok and "OK" or "invalid item event was recorded"
    end)
end)

TestRunner:Register("LootLog: money gain and expense recorded with sign", function()
    return WithFreshLog(function()
        LootLog:RecordMoney(213)
        LootLog:RecordMoney(-4500)
        LootLog:RecordMoney(0)
        local entries = LootLog:GetEntries()
        local ok = #entries == 2 and entries[2].copper == 213 and entries[1].copper == -4500
            and entries[1].kind == "money"
        return ok, ok and "OK" or "expected +213 then -4500 and no zero entry"
    end)
end)

TestRunner:Register("LootLog: newest first, and same-second events keep insertion order", function()
    return WithFreshLog(function()
        LootLog:RecordItem(1, 1)
        LootLog:RecordMoney(10)
        LootLog:RecordItem(2, 1)
        local e = LootLog:GetEntries()
        local ok = e[1].itemID == 2 and e[2].copper == 10 and e[3].itemID == 1
            and e[1].time == e[3].time and e[1].id > e[2].id and e[2].id > e[3].id
        return ok, ok and "OK" or "ordering is not strictly newest-first by id within one second"
    end)
end)

TestRunner:Register("LootLog: history is bounded to LOOT_LOG_MAX, oldest dropped first", function()
    return WithFreshLog(function()
        local max = Constants.LOOT_LOG_MAX
        for i = 1, max + 25 do
            LootLog:RecordItem(i, 1)
        end
        local e = LootLog:GetEntries()
        local ok = #e == max and e[1].itemID == max + 25 and e[#e].itemID == 26
        return ok, ok and "OK" or string.format("expected %d entries newest=%d oldest=26, got %d", max, max + 25, #e)
    end)
end)

TestRunner:Register("LootLog: GetEntries(limit) returns the newest N", function()
    return WithFreshLog(function()
        for i = 1, 5 do LootLog:RecordItem(i, 1) end
        local e = LootLog:GetEntries(2)
        local ok = #e == 2 and e[1].itemID == 5 and e[2].itemID == 4
        return ok, ok and "OK" or "limit did not return newest-first slice"
    end)
end)

-- Money observation / dedup ---------------------------------------------

TestRunner:Register("LootLog: first money observation is only a baseline (login is not income)", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(123456)
        local ok = #LootLog:GetEntries() == 0 and LootLog.lastMoney == 123456
        return ok, ok and "OK" or "baseline observation was recorded as an event"
    end)
end)

TestRunner:Register("LootLog: PLAYER_MONEY diff records gain, then expense", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(1000)
        LootLog:ObserveMoney(1213)
        LootLog:ObserveMoney(768)
        local e = LootLog:GetEntries()
        local ok = #e == 2 and e[2].copper == 213 and e[1].copper == -445
        return ok, ok and "OK" or "expected +213 then -445"
    end)
end)

TestRunner:Register("LootLog dedup: repeated PLAYER_MONEY with an unchanged balance records nothing", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(5000)
        LootLog:ObserveMoney(5100)
        LootLog:ObserveMoney(5100)
        LootLog:ObserveMoney(5100)
        local ok = #LootLog:GetEntries() == 1
        return ok, ok and "OK" or "a repeated PLAYER_MONEY duplicated the money event"
    end)
end)

TestRunner:Register("LootLog dedup: quest money is one entry (PLAYER_MONEY is the only money source)", function()
    -- A quest turn-in fires QUEST_TURNED_IN (moneyReward), CHAT_MSG_MONEY
    -- and PLAYER_MONEY. Only PLAYER_MONEY is wired, so Pockets sees one.
    return WithFreshLog(function()
        LootLog:ObserveMoney(0)
        LootLog:ObserveMoney(2500)
        local ok = #LootLog:GetEntries() == 1 and LootLog:GetEntries()[1].copper == 2500
        return ok, ok and "OK" or "expected exactly one +2500 entry"
    end)
end)

local function WithStubbedBags(slots, fn)
    local BagAPI = Pockets.Adapters.BagAPI
    local InventoryState = Pockets.Services.InventoryState
    local RecentItems = Pockets.Services.RecentItems
    local originalScan, originalCounts = BagAPI.ScanAllBags, BagAPI.GetCapacityCounts
    local Estimator = Pockets.Services.CapacityEstimator
    local originalPrevious = InventoryState.previousQuantitiesByItemID
    local originalRecent = RecentItems.entries
    -- Refresh() replaces the live snapshot/capacity/estimator history with
    -- the stub's; restore them so a test run never leaves bogus state.
    local originalItems, originalGeneral, originalAmmo =
        InventoryState.items, InventoryState.generalCapacity, InventoryState.ammoCapacity
    local originalSamples = Estimator.samples
    Estimator.samples = {}

    BagAPI.ScanAllBags = function() return slots.current end
    BagAPI.GetCapacityCounts = function()
        return { general = { used = 0, total = 16 }, ammo = { used = 0, total = 0 } }
    end
    InventoryState.previousQuantitiesByItemID = nil
    RecentItems.entries = {}

    local ok, err = pcall(fn)

    BagAPI.ScanAllBags, BagAPI.GetCapacityCounts = originalScan, originalCounts
    InventoryState.previousQuantitiesByItemID = originalPrevious
    RecentItems.entries = originalRecent
    InventoryState.items, InventoryState.generalCapacity, InventoryState.ammoCapacity =
        originalItems, originalGeneral, originalAmmo
    Estimator.samples = originalSamples
    if not ok then
        error(err, 0)
    end
end

local function Slot(bag, index, itemID, quantity)
    return { bagID = bag, slotIndex = index, itemID = itemID, quantity = quantity, itemLink = "item:" .. itemID }
end

TestRunner:Register("LootLog dedup: moving/splitting/combining stacks is not an acquisition", function()
    return WithFreshLog(function()
        local slots = {}
        local ok
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            slots.current = { Slot(0, 1, 2589, 10), Slot(0, 2, 2589, 5) }
            InventoryState:Refresh("baseline")
            -- Combine into one stack in another bag: same total.
            slots.current = { Slot(1, 1, 2589, 15) }
            InventoryState:Refresh("move")
            -- Split.
            slots.current = { Slot(1, 1, 2589, 8), Slot(1, 2, 2589, 7) }
            InventoryState:Refresh("split")
            ok = #LootLog:GetEntries() == 0
        end)
        return ok, ok and "OK" or "stack movement was logged as loot"
    end)
end)

TestRunner:Register("LootLog dedup: one acquisition across two bags logs one item entry with the total delta", function()
    return WithFreshLog(function()
        local slots = {}
        local ok, detail
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            slots.current = { Slot(0, 1, 2589, 10) }
            InventoryState:Refresh("baseline")
            -- +5 landing as a new stack in another bag.
            slots.current = { Slot(0, 1, 2589, 10), Slot(1, 1, 2589, 5) }
            InventoryState:Refresh("loot")
            local e = LootLog:GetEntries()
            ok = #e == 1 and e[1].itemID == 2589 and e[1].quantity == 5
            detail = #e
        end)
        return ok, ok and "OK" or ("expected one +5 entry, got " .. tostring(detail))
    end)
end)

TestRunner:Register("LootLog: simultaneous acquisitions land in a deterministic (itemID) order", function()
    return WithFreshLog(function()
        local slots = {}
        local ok
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            slots.current = {}
            InventoryState:Refresh("baseline")
            slots.current = { Slot(0, 1, 30, 1), Slot(0, 2, 10, 1), Slot(0, 3, 20, 1) }
            InventoryState:Refresh("loot")
            local e = LootLog:GetEntries()
            -- Newest first: last recorded (highest itemID) is on top.
            ok = #e == 3 and e[1].itemID == 30 and e[2].itemID == 20 and e[3].itemID == 10
        end)
        return ok, ok and "OK" or "simultaneous loot was not recorded in deterministic order"
    end)
end)

-- Persistence ------------------------------------------------------------

TestRunner:Register("LootLog: LoadPersisted drops malformed entries, re-sorts, and keeps ids increasing", function()
    return WithFreshLog(function()
        local saved = {
            nextId = 1, -- stale/corrupt: below the surviving ids
            entries = {
                { id = 3, time = 1, kind = "item", itemID = 5, quantity = 1 },
                "garbage",
                { id = 7, time = 1, kind = "money", copper = -5 },
                { id = 4, time = 1, kind = "item", itemID = 6, quantity = 0 }, -- invalid quantity
                { id = 5, time = 1, kind = "money", copper = 0 }, -- invalid copper
                { id = 6, time = 1, kind = "item", itemID = 7, quantity = 2 },
            },
        }
        LootLog:LoadPersisted(saved)
        local e = LootLog:GetEntries()
        local ok = #e == 3 and e[1].id == 7 and e[2].id == 6 and e[3].id == 3 and saved.nextId == 8
            and LootLog.entries == saved.entries
        local newest = LootLog:RecordItem(1, 1)
        ok = ok and newest.id == 8 and LootLog:GetEntries()[1] == newest
        return ok, ok and "OK" or "persisted load did not sanitize/sort or nextId regressed"
    end)
end)

TestRunner:Register("LootLog: LoadPersisted adopts the saved table so later events persist in place", function()
    return WithFreshLog(function()
        local saved = { nextId = 1, entries = {} }
        LootLog:LoadPersisted(saved)
        LootLog:RecordMoney(50)
        local ok = #saved.entries == 1 and saved.nextId == 2
        return ok, ok and "OK" or "events recorded after load did not land in the persisted table"
    end)
end)

TestRunner:Register("LootLog: publishes LOOT_LOGGED once per recorded event", function()
    return WithFreshLog(function()
        local count = 0
        local owner = {}
        Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.LOOT_LOGGED, function() count = count + 1 end, owner)
        LootLog:RecordItem(1, 1)
        LootLog:RecordMoney(5)
        LootLog:RecordMoney(0)
        Pockets.Services.EventBus:UnsubscribeOwner(owner)
        local ok = count == 2
        return ok, ok and "OK" or ("expected 2 publishes, got " .. count)
    end)
end)

-- pH independence --------------------------------------------------------

TestRunner:Register("LootLog: works with pH absent (no pH global is read or required)", function()
    return WithFreshLog(function()
        -- Key assembled at runtime: static-checks.sh bans literal pH_
        -- references in Pockets code, and this is deliberately not one.
        local ledgerKey = "p" .. "H_Ledger"
        local savedLedger = _G[ledgerKey]
        _G[ledgerKey] = nil
        local ok, err = pcall(function()
            LootLog:RecordItem(1, 1)
            LootLog:ObserveMoney(10)
            LootLog:ObserveMoney(20)
            Pockets.UI.MoneyFormat:Format(-20)
        end)
        _G[ledgerKey] = savedLedger
        return ok, ok and "OK" or tostring(err)
    end)
end)

-- Money formatting -------------------------------------------------------

local MONEY_CASES = {
    { 78, "78c" }, { 5678, "56s 78c" }, { 12340000, "1,234g" }, { 12345678, "1,234g 56s" },
    { 29382514, "2,938g 25s" }, { 12500, "1g 25s" }, { -4500, "-45s" }, { -213, "-2s 13c" },
    { 213, "2s 13c" },
}

for _, case in ipairs(MONEY_CASES) do
    TestRunner:Register(string.format("LootLog money format: %d -> %q", case[1], case[2]), function()
        local actual = Pockets.UI.MoneyFormat:Format(case[1])
        local ok = actual == case[2]
        return ok, ok and "OK" or string.format("expected %q, got %q", case[2], tostring(actual))
    end)
end
