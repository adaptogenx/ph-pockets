--[[
    Shared/RadialLayout.lua - Pure geometry for a ring of satellites around
    an anchor (Outer Ring TDD §3, §6). No frames, no Pockets knowledge.

    Slots are fixed: slot 1 at the top, then clockwise every 360/count
    degrees, so data changes never reorder nodes. Y is up (WoW convention).
]]

local _, Pockets = ...

Pockets.UI.RadialLayout = Pockets.UI.RadialLayout or {}
local RadialLayout = Pockets.UI.RadialLayout

-- Math-convention angle in degrees: 90 (top), 45, 0, -45 ... clockwise.
function RadialLayout.Angle(slot, count)
    return 90 - (slot - 1) * (360 / count)
end

-- Offset of a slot's centre from the ring centre.
function RadialLayout.Position(slot, count, radius)
    local rad = math.rad(RadialLayout.Angle(slot, count))
    return radius * math.cos(rad), radius * math.sin(rad)
end

-- How far to slide the whole ring so its bounding box stays on screen.
-- (cx, cy) ring centre in screen units (y from the bottom); extent =
-- { left, right, top, bottom } reach from the centre; shifts are capped at
-- maxShift so satellites never collapse onto the centre.
function RadialLayout.ClampOffset(cx, cy, extent, screenW, screenH, maxShift)
    local dx, dy = 0, 0
    if cx - extent.left < 0 then
        dx = math.min(maxShift, extent.left - cx)
    elseif cx + extent.right > screenW then
        dx = -math.min(maxShift, cx + extent.right - screenW)
    end
    if cy + extent.top > screenH then
        dy = -math.min(maxShift, cy + extent.top - screenH)
    elseif cy - extent.bottom < 0 then
        dy = math.min(maxShift, extent.bottom - cy)
    end
    return dx, dy
end
