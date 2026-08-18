--[[
    Tests/PositionStrategyTests.lua - V1 fixed-TOPLEFT anchor strategy
    (UI layout pass §1, §2)

    Needs a real frame (CreateFrame), so this runs in-client via
    /pockets test run like the rest of the frame-dependent suites.
]]

local _, Pockets = ...

local PositionStrategy = Pockets.UI.PositionStrategy

-- GetPoint() coordinates round-trip through UIParent's effective scale
-- (screen pixels <-> UI units), so a value SetPoint with as a plain Lua
-- number can come back a few millionths off (e.g. 42 -> 41.999996) even
-- though nothing actually moved. Compare with a tolerance well below one
-- screen pixel, not exact equality, whenever a literal/arithmetic value
-- is being checked against a value read back off a live frame.
local EPSILON = 0.01
local function ApproxEqual(a, b)
    return math.abs(a - b) < EPSILON
end

Pockets.Tests.TestRunner:Register("PositionStrategy: V1 anchor is TOPLEFT", function()
    local ok = PositionStrategy:GetRootAnchor() == "TOPLEFT"
    return ok, ok and "OK" or "expected V1 to report a fixed TOPLEFT anchor"
end)

Pockets.Tests.TestRunner:Register("PositionStrategy: ApplyRootPosition anchors TOPLEFT-to-TOPLEFT at the saved offset", function()
    local frame = CreateFrame("Frame", nil, UIParent)
    PositionStrategy:ApplyRootPosition(frame, { x = 42, y = -17 })

    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    local ok = point == "TOPLEFT" and relativeTo == UIParent and relativePoint == "TOPLEFT"
        and ApproxEqual(x, 42) and ApproxEqual(y, -17)
    return ok, ok and "OK" or string.format(
        "expected TOPLEFT/UIParent/TOPLEFT at (42,-17), got %s/%s/%s at (%s,%s)",
        tostring(point), tostring(relativeTo), tostring(relativePoint), tostring(x), tostring(y))
end)

Pockets.Tests.TestRunner:Register("PositionStrategy: CaptureSavedPosition round-trips through ApplyRootPosition unchanged", function()
    local frame = CreateFrame("Frame", nil, UIParent)
    PositionStrategy:ApplyRootPosition(frame, { x = 10, y = -20 })

    local captured = PositionStrategy:CaptureSavedPosition(frame)
    local ok = captured.point == "TOPLEFT" and captured.relativePoint == "TOPLEFT"
        and ApproxEqual(captured.x, 10) and ApproxEqual(captured.y, -20)
    return ok, ok and "OK" or "captured position did not match what was applied"
end)

Pockets.Tests.TestRunner:Register("PositionStrategy: CaptureSavedPosition is correct even if the frame's live anchor isn't TOPLEFT/UIParent", function()
    -- Models the real bug: a live in-game drag left saved y=+88 (positive
    -- - literally above the top of the screen, impossible for a
    -- TOPLEFT/UIParent/TOPLEFT anchor), meaning frame:GetPoint()'s
    -- reported point/relativeTo/offset after WoW's own
    -- StartMoving()/StopMovingOrSizing() drag commit could not be trusted
    -- verbatim. `frame` here is anchored to a DIFFERENT relativeTo (not
    -- UIParent) at zero offset, landing at the exact same on-screen spot
    -- TOPLEFT/UIParent/TOPLEFT(30,-40) would - proving capture is derived
    -- from absolute position, not naively trusted off GetPoint()'s fields.
    local reference = CreateFrame("Frame", nil, UIParent)
    PositionStrategy:ApplyRootPosition(reference, { x = 30, y = -40 })

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetPoint("TOPLEFT", reference, "TOPLEFT", 0, 0)

    local captured = PositionStrategy:CaptureSavedPosition(frame)
    local ok = ApproxEqual(captured.x, 30) and ApproxEqual(captured.y, -40)
        and captured.point == "TOPLEFT" and captured.relativePoint == "TOPLEFT"
    return ok, ok and "OK" or string.format(
        "expected (30,-40) derived from absolute position regardless of relativeTo, got (%s,%s)",
        tostring(captured.x), tostring(captured.y))
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
