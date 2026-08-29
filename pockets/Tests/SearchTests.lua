--[[
    Tests/SearchTests.lua - Case-insensitive name matching (TDD §15, §24.1)
]]

local _, Pockets = ...

local Search = Pockets.UI.Search

Pockets.Tests.TestRunner:Register("Search: nil/empty query matches everything", function()
    local record = { name = "Linen Cloth" }
    local ok = Search:Matches(record, nil) and Search:Matches(record, "")
    return ok, ok and "OK" or "expected nil/empty query to match"
end)

Pockets.Tests.TestRunner:Register("Search: case-insensitive substring match", function()
    local record = { name = "Linen Cloth" }
    local ok = Search:Matches(record, "linen") and Search:Matches(record, "CLOTH") and Search:Matches(record, "en cl")
    return ok, ok and "OK" or "expected case-insensitive substring matches to succeed"
end)

Pockets.Tests.TestRunner:Register("Search: non-matching substring fails", function()
    local record = { name = "Linen Cloth" }
    local ok = Search:Matches(record, "silk") == false
    return ok, ok and "OK" or "expected non-matching substring to fail"
end)

Pockets.Tests.TestRunner:Register("Search: record with no name never matches a non-empty query", function()
    local record = { name = nil }
    local ok = Search:Matches(record, "anything") == false
    return ok, ok and "OK" or "expected nameless record to fail a non-empty query"
end)

--------------------------------------------------
-- RankedItemMatches (Glance Quick Search pass) - separate, stricter
-- matcher from Filter/Matches above; does not touch All Items' search.
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Search: RankedItemMatches nil/empty query matches nothing (no browse-everything mode)", function()
    local items = { { itemID = 1, name = "Linen Cloth" } }
    local matchesNil, countNil = Search:RankedItemMatches(items, nil)
    local matchesEmpty, countEmpty = Search:RankedItemMatches(items, "")
    local ok = #matchesNil == 0 and countNil == 0 and #matchesEmpty == 0 and countEmpty == 0
    return ok, ok and "OK" or "expected nil/empty query to match nothing"
end)

Pockets.Tests.TestRunner:Register("Search: RankedItemMatches ranks exact > prefix > substring", function()
    local items = {
        { itemID = 1, name = "Major Mana Potion" }, -- substring ("mana" inside, not prefix)
        { itemID = 2, name = "Mana" },               -- exact
        { itemID = 3, name = "Mana Biscuit" },        -- prefix
    }
    local matches, count = Search:RankedItemMatches(items, "mana")
    local ok = count == 3 and matches[1].itemID == 2 and matches[2].itemID == 3 and matches[3].itemID == 1
    return ok, ok and "OK" or string.format(
        "expected exact(2) > prefix(3) > substring(1) order, got %s",
        table.concat({ tostring(matches[1] and matches[1].itemID), tostring(matches[2] and matches[2].itemID),
            tostring(matches[3] and matches[3].itemID) }, ","))
end)

Pockets.Tests.TestRunner:Register("Search: RankedItemMatches is case-insensitive and sorts alphabetically within a rank", function()
    -- Both are substring matches (not prefix) for query "mana" - a tied
    -- rank, so alphabetical order decides Apple before Zebra.
    local items = {
        { itemID = 1, name = "Zebra Mana" },
        { itemID = 2, name = "Apple Mana" },
    }
    local matches, count = Search:RankedItemMatches(items, "MANA")
    local ok = count == 2 and matches[1].itemID == 2 and matches[2].itemID == 1
    return ok, ok and "OK" or "expected case-insensitive matching with alphabetical tie-break within a rank"
end)

Pockets.Tests.TestRunner:Register("Search: RankedItemMatches excludes non-matching items and items with no name", function()
    local items = {
        { itemID = 1, name = "Linen Cloth" },
        { itemID = 2, name = "Silk Cloth" },
        { itemID = 3, name = nil },
    }
    local matches, count = Search:RankedItemMatches(items, "linen")
    local ok = count == 1 and matches[1].itemID == 1
    return ok, ok and "OK" or "expected only the matching, named item to survive"
end)
