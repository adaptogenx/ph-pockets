--[[
    Shared/RadialLayout.lua - Pure geometry for a ring of satellites around
    an anchor (Outer Ring TDD §3, §6). No frames, no Pockets knowledge.

    Y is up (WoW convention); angles are in degrees, 0 = east, 90 = up.
]]

local _, Pockets = ...

Pockets.UI.RadialLayout = Pockets.UI.RadialLayout or {}
local RadialLayout = Pockets.UI.RadialLayout

-- Offset of a point at `angle` degrees (math convention: 0 = east, 90 = up)
-- and `radius` from the ring centre.
function RadialLayout.PositionAt(angle, radius)
    local rad = math.rad(angle)
    return radius * math.cos(rad), radius * math.sin(rad)
end

-- Direction (degrees) the fan should face: away from the nearest screen
-- edge, so the HUD grows into the screen. (cx, cy) is the ring centre in
-- screen units (y from the bottom). Ties prefer left/right, then top.
function RadialLayout.EdgeAngle(cx, cy, screenW, screenH)
    local dl, dr, dt, db = cx, screenW - cx, screenH - cy, cy
    local nearest = math.min(dl, dr, dt, db)
    if dl == nearest then
        return 0 -- near the left edge: expand right
    elseif dr == nearest then
        return 180 -- near the right edge: expand left
    elseif dt == nearest then
        return -90 -- near the top edge: expand down
    end
    return 90 -- near the bottom edge: expand up
end

-- Angles for `count` satellites spread evenly across an arc of `span`
-- degrees centred on `center`, first node at the
-- top of the fan when facing right, each in the
-- middle of its own span/count wedge so none sits on the screen edge line.
function RadialLayout.ArcAngles(count, center, span)
    local angles = {}
    for i = 1, count do
        angles[i] = center + span / 2 - (i - 0.5) * span / count
    end
    return angles
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
