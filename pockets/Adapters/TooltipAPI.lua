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

-- Registers a callback invoked with (tooltip, itemID, itemLink) whenever an
-- item tooltip is shown. Safe to call multiple times; only hooks once.
function TooltipAPI:OnItemTooltipShow(callback)
    if self.hooked then
        return
    end
    self.hooked = true

    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
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
end
