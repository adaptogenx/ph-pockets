--[[
    Tests/RecentItemsTests.lua - Recent-item queue behavior (TDD §24.1)
]]

local _, Pockets = ...

local RecentItems = Pockets.Services.RecentItems

Pockets.Tests.TestRunner:Register("RecentItems: newest first", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 1, quantity = 1, timestamp = 1 })
    RecentItems:Record({ itemID = 2, quantity = 1, timestamp = 2 })

    local recent = RecentItems:GetRecent(2)
    local ok = recent[1].itemID == 2 and recent[2].itemID == 1
    return ok, ok and "OK" or "expected newest-first ordering"
end)

Pockets.Tests.TestRunner:Register("RecentItems: preserves acquired quantity", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 5, quantity = 7, timestamp = 1 })

    local recent = RecentItems:GetRecent(1)
    local ok = recent[1].quantity == 7
    return ok, ok and "OK" or string.format("expected quantity 7, got %s", tostring(recent[1].quantity))
end)

Pockets.Tests.TestRunner:Register("RecentItems: bounded history queue", function()
    RecentItems:Clear()
    local max = Pockets.Constants.RECENT_ITEMS_MAX
    for i = 1, max + 10 do
        RecentItems:Record({ itemID = i, quantity = 1, timestamp = i })
    end

    local count = #RecentItems:GetRecent(max + 10)
    local ok = count == max
    return ok, ok and "OK" or string.format("expected bounded to %d, got %d", max, count)
end)

Pockets.Tests.TestRunner:Register("RecentItems: rejects zero/negative quantity", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 9, quantity = 0, timestamp = 1 })
    RecentItems:Record({ itemID = 9, quantity = -1, timestamp = 1 })

    local count = #RecentItems:GetRecent(10)
    local ok = count == 0
    return ok, ok and "OK" or string.format("expected 0 entries, got %d", count)
end)
