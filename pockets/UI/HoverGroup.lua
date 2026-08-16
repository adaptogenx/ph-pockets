--[[
    UI/HoverGroup.lua - Shared open/close controller for HUD + CategoryFlyout
    + ItemFlyout (UI_SPEC §5, §13)

    Treats the HUD, category flyout, and item flyout as one interactive
    hover region. Rather than relying on each frame's own OnEnter/OnLeave
    (fragile across overlapping/adjacent frames, pixel gaps, and frame
    strata), this polls GetMouseFocus/GetMouseFoci against the group's
    registered frames (and their children, via the parent chain) on a
    short ticker. The pointer must be outside every member frame for the
    full grace period before onClose fires - crossing between two member
    frames, however it happens, never triggers a premature close.
]]

local _, Pockets = ...

Pockets.UI.HoverGroup = Pockets.UI.HoverGroup or {}
local HoverGroup = Pockets.UI.HoverGroup

local GRACE_SECONDS = Pockets.Constants.LAYOUT.HOVER_CLOSE_GRACE_SECONDS
local POLL_INTERVAL = 0.1

HoverGroup.members = HoverGroup.members or {}
HoverGroup.ticker = nil
HoverGroup.outsideSince = nil

-- Any frame whose hover should count as "inside" the group - register the
-- top-level HUD/CategoryFlyout/ItemFlyout frames only; their child rows
-- and item buttons are covered automatically via the parent-chain walk.
function HoverGroup:RegisterMember(frame)
    self.members[frame] = true
end

local function GetFocusFrame()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    elseif GetMouseFocus then
        return GetMouseFocus()
    end
    return nil
end

local function IsMouseOverGroup(self)
    local frame = GetFocusFrame()
    while frame do
        if self.members[frame] then
            return true
        end
        local ok, parent = pcall(frame.GetParent, frame)
        frame = ok and parent or nil
    end
    return false
end

-- Starts (or continues) watching. `onClose` fires once, at most, the next
-- time the pointer has been outside every member frame for the full grace
-- period. Safe to call repeatedly (e.g. every time a panel opens).
function HoverGroup:Watch(onClose)
    self.outsideSince = nil
    if self.ticker then
        return
    end
    self.ticker = C_Timer.NewTicker(POLL_INTERVAL, function()
        if IsMouseOverGroup(self) then
            self.outsideSince = nil
            return
        end
        if not self.outsideSince then
            self.outsideSince = GetTime()
            return
        end
        if GetTime() - self.outsideSince >= GRACE_SECONDS then
            self:StopWatching()
            onClose()
        end
    end)
end

function HoverGroup:StopWatching()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    self.outsideSince = nil
end
