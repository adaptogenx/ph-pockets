--[[
    UI/Search.lua - Case-insensitive item-name search (TDD §15, PRD §3.7)

    Operates over InventoryState's current aggregate; never rescans bags.
    Only used from FullInventory - no persistent search box in the HUD or
    category flyout (PRD §3.7).
]]

local _, Pockets = ...

Pockets.UI.Search = Pockets.UI.Search or {}
local Search = Pockets.UI.Search

-- Returns items whose name contains `query` (case-insensitive substring).
-- Empty/nil query returns every carried item (TDD §15).
function Search:Filter(query)
    local items = Pockets.Services.InventoryState:GetItems()

    if not query or query == "" then
        return items
    end

    local needle = query:lower()
    local out = {}
    for key, item in pairs(items) do
        local name = item.name and item.name:lower()
        if name and name:find(needle, 1, true) then
            out[key] = item
        end
    end
    return out
end
