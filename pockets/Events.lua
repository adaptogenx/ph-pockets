--[[
    Events.lua - WoW event wiring and startup sequence (TDD §20)

    Owns the single ADDON_LOADED/PLAYER_ENTERING_WORLD/bag-event frame.
    Bag events are debounced into one coalesced Refresh() rather than
    rescanning on every individual event (TDD §8.1, §21).
]]

-- luacheck: globals PocketsDB PocketsCharDB GetAddOnMetadata BAG_UPDATE_DELAY PLAYERBANKSLOTS_FIRST_ID

local ADDON_NAME, Pockets = ...

local mainFrame = CreateFrame("Frame", "PocketsMainFrame")

local BAG_UPDATE_EVENTS = {
    BAG_UPDATE = true,
    BAG_UPDATE_DELAYED = true,
    ITEM_LOCK_CHANGED = true,
    PLAYERBANKSLOTS_CHANGED = false, -- bank is explicitly out of scope (PRD §4)
}

local DEBOUNCE_SECONDS = 0.2
local pendingRefreshTimer = nil

local function EnsureSavedVariables()
    if not PocketsDB then
        PocketsDB = {
            version = 1,
            settings = {
                hud = {
                    point = Pockets.Constants.DEFAULT_SETTINGS.hud.point,
                    relativePoint = Pockets.Constants.DEFAULT_SETTINGS.hud.relativePoint,
                    x = Pockets.Constants.DEFAULT_SETTINGS.hud.x,
                    y = Pockets.Constants.DEFAULT_SETTINGS.hud.y,
                    locked = Pockets.Constants.DEFAULT_SETTINGS.hud.locked,
                },
            },
        }
    end
    if not PocketsDB.settings then
        PocketsDB.settings = { hud = Pockets.Constants.DEFAULT_SETTINGS.hud }
    end
    if not PocketsDB.settings.hud then
        PocketsDB.settings.hud = Pockets.Constants.DEFAULT_SETTINGS.hud
    end
    -- One-time migration: Pockets' V1 positioning uses a single fixed
    -- TOPLEFT anchor (UI layout pass §1). A position saved under the old
    -- CENTER-anchored scheme can't be meaningfully reprojected without a
    -- live frame, so it's reset to the TOPLEFT default rather than left
    -- to produce a mismatched anchor.
    if PocketsDB.settings.hud.point ~= "TOPLEFT" then
        local locked = PocketsDB.settings.hud.locked
        PocketsDB.settings.hud = {
            point = Pockets.Constants.DEFAULT_SETTINGS.hud.point,
            relativePoint = Pockets.Constants.DEFAULT_SETTINGS.hud.relativePoint,
            x = Pockets.Constants.DEFAULT_SETTINGS.hud.x,
            y = Pockets.Constants.DEFAULT_SETTINGS.hud.y,
            locked = locked or false,
        }
    end

    if not PocketsCharDB then
        PocketsCharDB = { debug = { enabled = false, verbose = false } }
    end
    if not PocketsCharDB.debug then
        PocketsCharDB.debug = { enabled = false, verbose = false }
    end

    Pockets.SavedSettings = PocketsDB.settings
    Pockets.CharDB = PocketsCharDB
end

local defaultBindingApplied = false

-- Binding APIs are not safe to call from ADDON_LOADED; the binding system
-- isn't fully initialized until around PLAYER_ENTERING_WORLD. Guarded by
-- defaultBindingApplied since PLAYER_ENTERING_WORLD can fire more than
-- once per session (zoning). Wrapped in pcall so a binding-API failure
-- degrades locally instead of breaking the rest of startup (TDD §22).
local function EnsureDefaultBinding()
    if defaultBindingApplied then
        return
    end
    defaultBindingApplied = true

    local ok, err = pcall(function()
        if GetBindingKey("POCKETS_TOGGLE_FULL_INVENTORY") then
            return
        end
        SetBinding("SHIFT-B", "POCKETS_TOGGLE_FULL_INVENTORY")
        SaveBindings(GetCurrentBindingSet() or 1)
    end)
    if not ok and Pockets.Debug then
        Pockets.Debug:LogError("EnsureDefaultBinding failed: " .. tostring(err))
    end
end

local function ScheduleRefresh(reason)
    if pendingRefreshTimer then
        return
    end
    pendingRefreshTimer = C_Timer.NewTimer(DEBOUNCE_SECONDS, function()
        pendingRefreshTimer = nil
        Pockets.Services.InventoryState:Refresh(reason)
    end)
end

local function InitializeAddon()
    EnsureSavedVariables()

    Pockets.UI.Shell:Initialize()
    Pockets.UI.TooltipCounts:Initialize()

    Pockets.Services.InventoryState:Refresh("initial_load")

    Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.READY, nil)

    local version = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"
    print(string.format("|cff00ff00[Pockets]|r Version %s loaded. Type /pockets help for commands.", version))
end

mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("BAG_UPDATE")
mainFrame:RegisterEvent("BAG_UPDATE_DELAYED")
mainFrame:RegisterEvent("ITEM_LOCK_CHANGED")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

mainFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == ADDON_NAME then
            InitializeAddon()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        EnsureDefaultBinding()
        ScheduleRefresh("player_entering_world")
    elseif event == "PLAYER_REGEN_DISABLED" then
        Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.COMBAT_STATE_CHANGED, { inCombat = true })
    elseif event == "PLAYER_REGEN_ENABLED" then
        Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.COMBAT_STATE_CHANGED, { inCombat = false })
    elseif BAG_UPDATE_EVENTS[event] ~= nil then
        if BAG_UPDATE_EVENTS[event] then
            ScheduleRefresh(event)
        end
    else
        ScheduleRefresh(event)
    end
end)

--------------------------------------------------
-- Slash commands
--------------------------------------------------

local function ShowHelp()
    print("|cff00ff00=== Pockets Commands ===|r")
    print("|cffffff00/pockets show|r - Show/hide the HUD")
    print("|cffffff00/pockets toggle|r - Toggle the full inventory view")
    print("|cffffff00/pockets help|r - Show this help")
    print("|cffffff00/pockets help dev|r - Show debug/testing commands")
    print("=========================")
end

local function ShowDevHelp()
    print("|cff00ff00=== Pockets Developer Commands ===|r")
    print("|cffffff00/pockets debug on|off|r - Enable/disable debug mode")
    print("|cffffff00/pockets debug verbose on|off|r - Enable/disable verbose logging")
    print("|cffffff00/pockets debug inventory|r - Dump current inventory state")
    print("|cffffff00/pockets debug categories|r - Dump category summary")
    print("|cffffff00/pockets debug estimator|r - Dump capacity estimator state")
    print("|cffffff00/pockets debug events|r - Dump EventBus subscriber counts")
    print("|cffffff00/pockets test run|r - Run automated test suite")
    print("|cffffff00/pockets test sample <used> <total> <secondsAgo>|r - Inject a capacity sample")
    print("|cffffff00/pockets test category <itemID>|r - Print the category for an item")
    print("|cffffff00/pockets test recent <itemID> <quantity>|r - Inject a Recent Items entry")
    print("===============================")
end

local function HandleCommand(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    local cmd = (args[1] or "help"):lower()

    if cmd == "show" then
        Pockets.UI.Shell:Toggle()
    elseif cmd == "toggle" then
        Pockets.API.Toggle()
    elseif cmd == "debug" then
        Pockets.Debug:HandleCommand(args)
    elseif cmd == "test" then
        Pockets.Debug:HandleTestCommand(args)
    elseif cmd == "help" then
        if (args[2] or ""):lower() == "dev" then
            ShowDevHelp()
        else
            ShowHelp()
        end
    else
        print("[Pockets] Unknown command. Type /pockets help for usage.")
    end
end

SLASH_POCKETS1 = "/pockets"
SLASH_POCKETS2 = "/pk"
SlashCmdList["POCKETS"] = HandleCommand
