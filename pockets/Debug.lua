--[[
    Debug.lua - Debug and diagnostic infrastructure for Pockets (TDD §23)

    Provides /pockets debug ... inspection commands and /pockets test ...
    injection commands so domain logic can be exercised without performing
    every game action manually.
]]

-- luacheck: globals PocketsCharDB

local _, Pockets = ...

Pockets.Debug = Pockets.Debug or {}
local Debug = Pockets.Debug

local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff0000"
local COLOR_YELLOW = "|cffffff00"
local COLOR_RESET = "|r"

function Debug:IsVerbose()
    return Pockets.CharDB and Pockets.CharDB.debug and Pockets.CharDB.debug.verbose
end

function Debug:Log(message)
    if self:IsVerbose() then
        print(COLOR_YELLOW .. "[Pockets Debug] " .. COLOR_RESET .. message)
    end
end

function Debug:LogError(message)
    print(COLOR_RED .. "[Pockets Error] " .. COLOR_RESET .. message)
end

--------------------------------------------------
-- Inspection commands
--------------------------------------------------

function Debug:DumpInventory()
    print(COLOR_YELLOW .. "=== Pockets Inventory ===" .. COLOR_RESET)
    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    local ammo = Pockets.Services.InventoryState:GetAmmoCapacity()
    print(string.format("  Bags: %d/%d (%.1f%%)", capacity.used, capacity.total, capacity.utilization * 100))
    print(string.format("  Ammo: %d/%d", ammo.used, ammo.total))

    for key, item in pairs(Pockets.Services.InventoryState:GetItems()) do
        print(string.format("  [%s] %s x%s (%s)", tostring(key), item.name or ("item:" .. tostring(item.itemID)),
            tostring(item.quantity), tostring(item.categoryID)))
    end
    print(COLOR_YELLOW .. "==========================" .. COLOR_RESET)
end

function Debug:DumpCategories()
    print(COLOR_YELLOW .. "=== Pockets Categories ===" .. COLOR_RESET)
    for _, entry in ipairs(Pockets.API.GetCategorySummary()) do
        print(string.format("  %-14s %d", entry.label, entry.count))
    end
    print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
end

function Debug:DumpEstimator()
    local estimator = Pockets.Services.CapacityEstimator
    print(COLOR_YELLOW .. "=== Pockets Capacity Estimator ===" .. COLOR_RESET)
    print(string.format("  State: %s", estimator:GetState()))
    print(string.format("  Rate: %s slots/min", tostring(estimator:GetRate())))
    print(string.format("  ETA: %s seconds", tostring(estimator:GetETA())))
    print(string.format("  Confidence: %.2f", estimator:GetConfidence()))
    print(string.format("  Samples: %d", #estimator.samples))
    print(COLOR_YELLOW .. "===================================" .. COLOR_RESET)
end

function Debug:DumpEvents()
    print(COLOR_YELLOW .. "=== Pockets EventBus Subscribers ===" .. COLOR_RESET)
    for eventName, list in pairs(Pockets.Services.EventBus.subscribers) do
        print(string.format("  %s: %d subscriber(s)", eventName, #list))
    end
    print(COLOR_YELLOW .. "=====================================" .. COLOR_RESET)
end

function Debug:HandleCommand(args)
    local subCmd = (args[2] or ""):lower()
    if subCmd == "on" then
        Pockets.CharDB.debug.enabled = true
        print("[Pockets] Debug mode enabled")
    elseif subCmd == "off" then
        Pockets.CharDB.debug.enabled = false
        print("[Pockets] Debug mode disabled")
    elseif subCmd == "verbose" then
        local setting = (args[3] or ""):lower()
        if setting == "on" then
            Pockets.CharDB.debug.verbose = true
            print("[Pockets] Verbose logging enabled")
        elseif setting == "off" then
            Pockets.CharDB.debug.verbose = false
            print("[Pockets] Verbose logging disabled")
        else
            print("[Pockets] Usage: /pockets debug verbose on|off")
        end
    elseif subCmd == "inventory" then
        self:DumpInventory()
    elseif subCmd == "categories" then
        self:DumpCategories()
    elseif subCmd == "estimator" then
        self:DumpEstimator()
    elseif subCmd == "events" then
        self:DumpEvents()
    else
        print("[Pockets] Debug commands: on, off, verbose, inventory, categories, estimator, events")
    end
end

--------------------------------------------------
-- Test injection commands (TDD §23)
--------------------------------------------------

function Debug:HandleTestCommand(args)
    local subCmd = (args[2] or ""):lower()

    if subCmd == "run" then
        self:RunTests()
    elseif subCmd == "sample" then
        local used = tonumber(args[3])
        local total = tonumber(args[4])
        local secondsAgo = tonumber(args[5]) or 0
        if not used or not total then
            print("[Pockets] Usage: /pockets test sample <used> <total> <secondsAgo>")
        else
            Pockets.Services.CapacityEstimator:AddSample(GetTime() - secondsAgo, used, total)
            print(string.format("[Pockets] Injected sample used=%d total=%d secondsAgo=%d", used, total, secondsAgo))
        end
    elseif subCmd == "category" then
        local itemID = tonumber(args[3])
        if not itemID then
            print("[Pockets] Usage: /pockets test category <itemID>")
        else
            local meta = Pockets.Adapters.ItemAPI:GetItemMetadata(itemID)
            local category = Pockets.Services.ItemCategorizer:Categorize(meta and {
                itemID = itemID,
                classID = meta.classID,
                subclassID = meta.subclassID,
                quality = meta.quality,
            } or { itemID = itemID })
            print(string.format("[Pockets] item %d -> category %s", itemID, category))
        end
    elseif subCmd == "recent" then
        local itemID = tonumber(args[3])
        local quantity = tonumber(args[4]) or 1
        if not itemID then
            print("[Pockets] Usage: /pockets test recent <itemID> <quantity>")
        else
            Pockets.Services.RecentItems:Record({ itemID = itemID, quantity = quantity, timestamp = GetTime() })
            print(string.format("[Pockets] Recorded recent item %d x%d", itemID, quantity))
        end
    else
        print("[Pockets] Test commands: run, sample <used> <total> <secondsAgo>, category <itemID>, recent <itemID> <quantity>")
    end
end

function Debug:RunTests()
    print(COLOR_YELLOW .. "[Pockets Test Suite] Running tests..." .. COLOR_RESET)
    local passed, failed = Pockets.Tests.TestRunner:RunAll()
    local color = (failed == 0) and COLOR_GREEN or COLOR_RED
    print(string.format("%s[Pockets Test Suite] %d passed, %d failed%s", color, passed, failed, COLOR_RESET))
    return failed == 0
end
