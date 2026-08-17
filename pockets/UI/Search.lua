--[[
    UI/Search.lua - Case-insensitive item-name search (TDD §15, PRD §3.7)

    Operates over already-resolved item/aggregate records; never rescans
    bags. Only used from Shell's ALL state - no persistent search box in
    Glance, Menu, or Category (PRD §3.7).
]]

local _, Pockets = ...

Pockets.UI.Search = Pockets.UI.Search or {}
local Search = Pockets.UI.Search

-- True if `record.name` contains `query` as a case-insensitive substring.
-- nil/empty query always matches (TDD §15) - callers can pass this
-- straight through without special-casing "no active search".
function Search:Matches(record, query)
    if not query or query == "" then
        return true
    end
    local name = record and record.name and record.name:lower()
    return name ~= nil and name:find(query:lower(), 1, true) ~= nil
end

-- Returns items whose name contains `query` (case-insensitive substring).
-- Empty/nil query returns every carried item (TDD §15).
function Search:Filter(query)
    local items = Pockets.Services.InventoryState:GetItems()

    if not query or query == "" then
        return items
    end

    local out = {}
    for key, item in pairs(items) do
        if self:Matches(item, query) then
            out[key] = item
        end
    end
    return out
end
