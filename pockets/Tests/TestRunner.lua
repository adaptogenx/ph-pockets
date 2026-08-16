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

function TestRunner:RunAll()
    local passed, failed = 0, 0
    for _, test in ipairs(self.tests) do
        local ok, resultOrErr, message = pcall(test.fn)
        local testPassed = ok and resultOrErr
        local testMessage = ok and (message or "OK") or ("ERROR: " .. tostring(resultOrErr))

        if testPassed then
            passed = passed + 1
        else
            failed = failed + 1
        end

        local color = testPassed and COLOR_GREEN or COLOR_RED
        local status = testPassed and "PASS" or "FAIL"
        print(string.format("%s[Test: %s] %s: %s%s", color, test.name, status, testMessage, COLOR_RESET))
    end
    return passed, failed
end
