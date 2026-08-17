--[[
    UI/PositionStrategy.lua - Root-frame anchor strategy (UI layout pass §2)

    Position and size are independent concerns: Shell resizes the root
    frame per state, this module owns where that frame's origin sits on
    screen. V1 is a single fixed TOPLEFT anchor/growth strategy - Glance
    and every expanded state share the same screen-space TOPLEFT, and
    resizing always grows right/down from it, never recenters.

    A future pass may pick the anchor/growth direction from where the
    player actually parked the frame (left edge -> grow right, bottom ->
    grow up, etc.) - that's why this is a seam (GetRootAnchor/
    ApplyRootPosition/CaptureSavedPosition) instead of Shell hardcoding
    "TOPLEFT" inline in multiple places.
]]

local _, Pockets = ...

Pockets.UI.PositionStrategy = Pockets.UI.PositionStrategy or {}
local PositionStrategy = Pockets.UI.PositionStrategy

-- V1: always TOPLEFT. A future strategy could inspect saved position vs.
-- screen bounds and return a different anchor per corner/edge.
function PositionStrategy:GetRootAnchor()
    return "TOPLEFT"
end

-- Anchors `frame` to UIParent using the strategy's anchor on both sides,
-- so SetSize()-driven growth always extends away from that one fixed
-- point (right/down for TOPLEFT) regardless of current dimensions.
function PositionStrategy:ApplyRootPosition(frame, savedPosition)
    local anchor = self:GetRootAnchor()
    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, anchor, savedPosition.x or 0, savedPosition.y or 0)
end

-- Reads the frame's current anchor offset back out, in the same
-- anchor/relativeAnchor terms ApplyRootPosition used - safe to call after
-- a user drag, since dragging a TOPLEFT-anchored frame only ever mutates
-- that anchor's x/y, never its anchor points.
function PositionStrategy:CaptureSavedPosition(frame)
    local anchor = self:GetRootAnchor()
    local _, _, _, x, y = frame:GetPoint()
    return { point = anchor, relativePoint = anchor, x = x, y = y }
end
