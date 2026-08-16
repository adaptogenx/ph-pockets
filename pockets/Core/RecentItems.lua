--[[
    Core/RecentItems.lua - Bounded queue of true acquisitions (TDD §5.3, §8.2)

    Records acquisition deltas only - stack movement between bags must never
    appear here (PRD §3.3, TDD §8.2, §12.3). Callers (InventoryState's diff
    step) are responsible for distinguishing acquisition from movement
    before calling Record.
]]

local _, Pockets = ...

Pockets.Services.RecentItems = Pockets.Services.RecentItems or {}
local RecentItems = Pockets.Services.RecentItems

RecentItems.entries = RecentItems.entries or {}
RecentItems.revision = RecentItems.revision or 0

local MAX_ENTRIES = Pockets.Constants.RECENT_ITEMS_MAX

-- delta: { itemID, quantity, timestamp, itemLink }
function RecentItems:Record(delta)
    if not delta or not delta.itemID or not delta.quantity or delta.quantity <= 0 then
        return
    end

    table.insert(self.entries, 1, {
        itemID = delta.itemID,
        quantity = delta.quantity,
        timestamp = delta.timestamp or GetTime(),
        itemLink = delta.itemLink,
    })

    while #self.entries > MAX_ENTRIES do
        table.remove(self.entries)
    end

    self.revision = self.revision + 1
    Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.ITEM_ACQUIRED, delta)
end

-- Returns the `limit` most recent entries, newest first.
function RecentItems:GetRecent(limit)
    if not limit or limit >= #self.entries then
        return self.entries
    end
    local out = {}
    for i = 1, limit do
        out[i] = self.entries[i]
    end
    return out
end

function RecentItems:GetSince(timestamp)
    local out = {}
    for _, entry in ipairs(self.entries) do
        if entry.timestamp >= timestamp then
            table.insert(out, entry)
        end
    end
    return out
end

function RecentItems:Clear()
    self.entries = {}
    self.revision = self.revision + 1
end

function RecentItems:GetRevision()
    return self.revision
end
