--[[
    UI/TooltipCounts.lua - Adds a carried-count line to item tooltips (TDD §16, PRD §3.10)

    Read-only consumer of InventoryState. Never triggers a bag scan from
    tooltip rendering.
]]

local _, Pockets = ...

Pockets.UI.TooltipCounts = Pockets.UI.TooltipCounts or {}
local TooltipCounts = Pockets.UI.TooltipCounts

function TooltipCounts:Initialize()
    Pockets.Adapters.TooltipAPI:OnItemTooltipShow(function(tooltip, itemID)
        local quantity = Pockets.Services.InventoryState:GetCarriedQuantity(itemID)
        if quantity > 0 then
            tooltip:AddLine(string.format("Pockets: %d", quantity), 0.6, 0.8, 1.0)
            tooltip:Show()
        end
    end)
end
