--[[
    Adapters/ItemAPI.lua - Isolates direct item-info lookups (TDD §3.1, §9)

    Normalizes GetItemInfo's asynchronous/nil-until-cached behavior into a
    small metadata cache with a "pending" state, so the rest of Pockets
    never has to special-case missing item data.
]]

local _, Pockets = ...

Pockets.Adapters.ItemAPI = Pockets.Adapters.ItemAPI or {}
local ItemAPI = Pockets.Adapters.ItemAPI

-- ItemCache[itemID] = { status = "ready" | "pending", name, quality, classID, subclassID, maxStack, texture, itemLink }
ItemAPI.ItemCache = ItemAPI.ItemCache or {}

-- Returns cached metadata for an item, requesting it from the WoW API if
-- not already cached. Never blocks; returns a pending entry when the
-- client hasn't cached the item yet.
function ItemAPI:GetItemMetadata(itemID, itemLink)
    if not itemID then
        return nil
    end

    local cached = self.ItemCache[itemID]
    if cached and cached.status == "ready" then
        return cached
    end

    local name, link, quality, _, _, itemClass, itemSubClass, maxStack, _, texture, _, classID, subclassID,
        _, _, _, isCraftingReagent = GetItemInfo(itemLink or itemID)

    if not name then
        if not cached then
            self.ItemCache[itemID] = { status = "pending" }
        end
        return self.ItemCache[itemID]
    end

    local entry = {
        status = "ready",
        name = name,
        itemLink = link,
        quality = quality,
        classID = classID,
        subclassID = subclassID,
        itemClass = itemClass,
        itemSubClass = itemSubClass,
        maxStack = maxStack,
        texture = texture,
        isCraftingReagent = isCraftingReagent,
    }
    self.ItemCache[itemID] = entry
    return entry
end

-- Returns true if the item's metadata is not yet resolved.
function ItemAPI:IsPending(itemID)
    local cached = self.ItemCache[itemID]
    return cached == nil or cached.status == "pending"
end

-- Returns whether an item is currently a quest item (WoW Classic quest flag).
function ItemAPI:IsQuestItem(itemID, itemLink)
    local _, _, _, _, _, itemClass = GetItemInfo(itemLink or itemID)
    return itemClass == (ITEM_CLASS_QUEST or "Quest")
end

-- Clears the metadata cache. Intended for tests/debug only.
function ItemAPI:ResetCache()
    self.ItemCache = {}
end
