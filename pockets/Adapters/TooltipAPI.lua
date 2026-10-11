--[[
    Adapters/TooltipAPI.lua - Isolates tooltip hooking (TDD §3.1, §16)

    Conservatively hooks item tooltips to add a single carried-count line.
    Any failure here must not break inventory state or the rest of the UI
    (TDD §22 Error Handling).
]]

local _, Pockets = ...

Pockets.Adapters.TooltipAPI = Pockets.Adapters.TooltipAPI or {}
local TooltipAPI = Pockets.Adapters.TooltipAPI

TooltipAPI.hooked = false
-- False when the client has no legacy item-tooltip handler (WoW Forever /
-- modern tooltip pipeline). The carried-count line is then unavailable;
-- modern TooltipDataProcessor integration is deferred to M3 (Forever §26).
TooltipAPI.supported = nil

-- Pure-ish feature check: does this tooltip still have the legacy handler?
function TooltipAPI:HasLegacyItemHandler(tooltip)
    if not tooltip or not tooltip.HookScript then
        return false
    end
    if tooltip.HasScript then
        local ok, has = pcall(tooltip.HasScript, tooltip, "OnTooltipSetItem")
        return ok and has == true
    end
    return true
end

-- Registers a callback invoked with (tooltip, itemID, itemLink) whenever an
-- item tooltip is shown. Safe to call multiple times; only hooks once.
-- Silently does nothing (supported = false) where the legacy handler is gone.
function TooltipAPI:OnItemTooltipShow(callback)
    if self.hooked then
        return
    end
    self.hooked = true

    if not self:HasLegacyItemHandler(GameTooltip) then
        self.supported = false
        return
    end

    local hookOk, hookErr = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip)
        local ok, err = pcall(function()
            local _, itemLink = tooltip:GetItem()
            if not itemLink then
                return
            end
            local itemID = tonumber(itemLink:match("item:(%d+)"))
            if not itemID then
                return
            end
            callback(tooltip, itemID, itemLink)
        end)
        if not ok and Pockets.Debug then
            Pockets.Debug:LogError("TooltipAPI hook failed: " .. tostring(err))
        end
    end)
    self.supported = hookOk
    if not hookOk and Pockets.Debug then
        Pockets.Debug:LogError("TooltipAPI hook unavailable: " .. tostring(hookErr))
    end
end
