--[[
    Tests/PositionStrategyTests.lua - V1 fixed-TOPLEFT anchor strategy
    (UI layout pass §1, §2)

    Needs a real frame (CreateFrame), so this runs in-client via
    /pockets test run like the rest of the frame-dependent suites.
]]

local _, Pockets = ...

local PositionStrategy = Pockets.UI.PositionStrategy

Pockets.Tests.TestRunner:Register("PositionStrategy: V1 anchor is TOPLEFT", function()
    local ok = PositionStrategy:GetRootAnchor() == "TOPLEFT"
    return ok, ok and "OK" or "expected V1 to report a fixed TOPLEFT anchor"
end)

Pockets.Tests.TestRunner:Register("PositionStrategy: ApplyRootPosition anchors TOPLEFT-to-TOPLEFT at the saved offset", function()
    local frame = CreateFrame("Frame", nil, UIParent)
    PositionStrategy:ApplyRootPosition(frame, { x = 42, y = -17 })

    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    local ok = point == "TOPLEFT" and relativeTo == UIParent and relativePoint == "TOPLEFT" and x == 42 and y == -17
    return ok, ok and "OK" or string.format(
        "expected TOPLEFT/UIParent/TOPLEFT at (42,-17), got %s/%s/%s at (%s,%s)",
        tostring(point), tostring(relativeTo), tostring(relativePoint), tostring(x), tostring(y))
end)

Pockets.Tests.TestRunner:Register("PositionStrategy: CaptureSavedPosition round-trips through ApplyRootPosition unchanged", function()
    local frame = CreateFrame("Frame", nil, UIParent)
    PositionStrategy:ApplyRootPosition(frame, { x = 10, y = -20 })

    local captured = PositionStrategy:CaptureSavedPosition(frame)
    local ok = captured.point == "TOPLEFT" and captured.relativePoint == "TOPLEFT"
        and captured.x == 10 and captured.y == -20
    return ok, ok and "OK" or "captured position did not match what was applied"
end)

Pockets.Tests.TestRunner:Register("PositionStrategy: resizing a positioned frame does not change its captured anchor", function()
    local frame = CreateFrame("Frame", nil, UIParent)
    PositionStrategy:ApplyRootPosition(frame, { x = 5, y = -5 })
    frame:SetSize(140, 90)
    local before = PositionStrategy:CaptureSavedPosition(frame)

    frame:SetSize(220, 300) -- simulates Glance -> expanded shell growth
    local after = PositionStrategy:CaptureSavedPosition(frame)

    local ok = before.x == after.x and before.y == after.y
        and before.point == after.point and before.relativePoint == after.relativePoint
    return ok, ok and "OK" or "resizing the frame shifted its TOPLEFT anchor"
end)
