--[[
    Tests/TestRunner.lua - Minimal in-addon test runner (TDD §24.2)

    Each test module registers itself with :Register(name, fn). fn returns
    (passed: boolean, message: string). Matches pH's `/pockets test run`
    pattern for tests that need addon runtime behavior.
]]

local _, Pockets = ...

Pockets.Tests.TestRunner = Pockets.Tests.TestRunner or { tests = {} }
local TestRunner = Pockets.Tests.TestRunner

local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff0000"
local COLOR_RESET = "|r"

function TestRunner:Register(name, fn)
    table.insert(self.tests, { name = name, fn = fn })
end

-- Prints every PASS/FAIL as it runs (unchanged), then a second,
-- clearly-bordered FAILURES-ONLY recap at the very end listing just the
-- failing test names + messages. Screenshotting/copy-pasting a WoW chat
-- frame with 250+ interleaved PASS lines to find the handful of FAILs
-- buried in it is painful (chat has no scroll-to-failure/export) - the
-- recap is the LAST thing printed, so it's what's on screen without any
-- scrolling once the run finishes.
function TestRunner:RunAll()
    local passed, failed = 0, 0
    local failures = {}
    for _, test in ipairs(self.tests) do
        local ok, resultOrErr, message = pcall(test.fn)
        local testPassed = ok and resultOrErr
        local testMessage = ok and (message or "OK") or ("ERROR: " .. tostring(resultOrErr))

        if testPassed then
            passed = passed + 1
        else
            failed = failed + 1
            table.insert(failures, { name = test.name, message = testMessage })
        end

        local color = testPassed and COLOR_GREEN or COLOR_RED
        local status = testPassed and "PASS" or "FAIL"
        print(string.format("%s[Test: %s] %s: %s%s", color, test.name, status, testMessage, COLOR_RESET))
    end

    if #failures > 0 then
        print(COLOR_RED .. string.format("======== %d FAILED TEST(S) ========", #failures) .. COLOR_RESET)
        for i, failure in ipairs(failures) do
            print(string.format("%s%d. %s%s", COLOR_RED, i, failure.name, COLOR_RESET))
            print("   " .. failure.message)
        end
        print(COLOR_RED .. "===================================" .. COLOR_RESET)
    end

    -- Persist the outcome so it can be read from the SavedVariables file
    -- (WTF/.../SavedVariables/Pockets.lua) after /reload, instead of
    -- screenshotting chat.
    if _G.PocketsDB then
        _G.PocketsDB.lastTestRun = { passed = passed, failed = failed, failures = failures }
    end

    return passed, failed
end
