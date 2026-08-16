--[[
    Adapters/CombatAPI.lua - Isolates combat-lockdown state (TDD §3.1, §11, §22)

    Combat state must be checked at the moment of interaction, not cached
    at load/frame-creation time (TDD §14).
]]

local _, Pockets = ...

Pockets.Adapters.CombatAPI = Pockets.Adapters.CombatAPI or {}
local CombatAPI = Pockets.Adapters.CombatAPI

function CombatAPI:IsInCombat()
    return InCombatLockdown() and true or false
end

-- Hover-triggered expansion is disabled in combat; clicking is always allowed.
function CombatAPI:CanHoverExpand()
    return not self:IsInCombat()
end
