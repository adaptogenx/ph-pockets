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

--------------------------------------------------
-- Glance Quick Search (top-bar/quick-search pass) - a SEPARATE, stricter
-- matcher from Filter/Matches above. Quick Search is not inventory
-- browsing: it ranks exact > prefix > substring (no fuzzy matching) so
-- the single best-named item surfaces first, and it never falls back to
-- "show everything" for an empty query the way Filter does. Operates on
-- an already-aggregated record list the caller supplies (e.g.
-- API.GetAllAggregatedItems()) - no bag rescan, no categorization pass.
--------------------------------------------------

local RANK_EXACT, RANK_PREFIX, RANK_SUBSTRING = 1, 2, 3

local function MatchRank(name, lowerQuery)
    if not name then
        return nil
    end
    local lowerName = name:lower()
    if lowerName == lowerQuery then
        return RANK_EXACT
    end
    local startIndex = lowerName:find(lowerQuery, 1, true)
    if startIndex == 1 then
        return RANK_PREFIX
    elseif startIndex ~= nil then
        return RANK_SUBSTRING
    end
    return nil
end

-- Returns (matches, totalCount): every `items` record whose name ranks
-- against `query`, sorted exact -> prefix -> substring (alphabetical
-- within a rank). Empty/nil query matches nothing - Quick Search has no
-- "browse everything" mode.
function Search:RankedItemMatches(items, query)
    if not query or query == "" then
        return {}, 0
    end

    local lowerQuery = query:lower()
    local ranked = {}
    for _, item in ipairs(items) do
        local rank = MatchRank(item.name, lowerQuery)
        if rank then
            table.insert(ranked, { item = item, rank = rank })
        end
    end

    table.sort(ranked, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return (a.item.name or ""):lower() < (b.item.name or ""):lower()
    end)

    local out = {}
    for _, entry in ipairs(ranked) do
        table.insert(out, entry.item)
    end
    return out, #out
end
