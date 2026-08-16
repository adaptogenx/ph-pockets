--[[
    UI/HoverGroup.lua - Shared open/close controller for HUD + CategoryFlyout
    + ItemFlyout (UI_SPEC §5, §13)

    Treats the HUD, category flyout, and currently open item flyout as one
    interactive hover region. Opening is always immediate (no timer) -
    callers just show their frame directly. Closing is debounced by a
    single shared grace-period timer so moving the pointer across the small
    gap between two panels never flicker-closes them: any member's OnEnter
    cancels the pending close; only when nothing in the group is hovered
    does the close actually fire.
]]

local _, Pockets = ...

Pockets.UI.HoverGroup = Pockets.UI.HoverGroup or {}
local HoverGroup = Pockets.UI.HoverGroup

local GRACE_SECONDS = Pockets.Constants.LAYOUT.HOVER_CLOSE_GRACE_SECONDS

HoverGroup.closeTimer = nil

-- Call from any group member's OnEnter. Cancels a pending close.
function HoverGroup:Enter()
    if self.closeTimer then
        self.closeTimer:Cancel()
        self.closeTimer = nil
    end
end

-- Call from any group member's OnLeave. Schedules onClose to run after the
-- grace period unless another member's OnEnter cancels it first.
function HoverGroup:Leave(onClose)
    self:Enter() -- cancel any prior pending close before scheduling a new one
    self.closeTimer = C_Timer.NewTimer(GRACE_SECONDS, function()
        self.closeTimer = nil
        onClose()
    end)
end
