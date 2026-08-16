--[[
    UI/ItemButtonPool.lua - Reusable pool of REAL item buttons (TDD §13.4,
    §21; UI_SPEC §8, §10, §14)

    Flyouts and the full inventory view must not create new frames on every
    open; they Acquire()/ReleaseAll() from a shared pool per parent frame.

    Configure() is the single place that wires a pooled button to a live
    bag+slot via Adapters/BagAPI's pickup/use/tooltip wrappers, so
    click/right-click/shift-click/drag/tooltip behave normally. Shared by
    UI/ItemFlyout.lua and UI/FullInventory.lua so both stay in sync
    (UI_SPEC §10 "share item rendering/pooling code").
]]

local _, Pockets = ...

Pockets.UI.ItemButtonPool = Pockets.UI.ItemButtonPool or {}
local ItemButtonPool = Pockets.UI.ItemButtonPool

local BagAPI = Pockets.Adapters.BagAPI
local SIZE = Pockets.Constants.LAYOUT.ITEM_BUTTON_SIZE

-- pools[parentFrame] = { free = {}, active = {} }
ItemButtonPool.pools = ItemButtonPool.pools or {}

local function CreateItemButton(parent)
    local button = CreateFrame("Button", nil, parent, "ItemButtonTemplate,BackdropTemplate")
    button:SetSize(SIZE, SIZE)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:Hide()
    return button
end

function ItemButtonPool:GetPool(parent)
    self.pools[parent] = self.pools[parent] or { free = {}, active = {} }
    return self.pools[parent]
end

-- Returns a hidden button. Caller must call Configure() then Show() it.
function ItemButtonPool:Acquire(parent)
    local pool = self:GetPool(parent)
    local button = table.remove(pool.free)
    if not button then
        button = CreateItemButton(parent)
    end
    table.insert(pool.active, button)
    return button
end

-- Hides and recycles every button currently active for `parent`.
function ItemButtonPool:ReleaseAll(parent)
    local pool = self:GetPool(parent)
    for _, button in ipairs(pool.active) do
        button:Hide()
        button:ClearAllPoints()
        table.insert(pool.free, button)
    end
    pool.active = {}
end

-- record: a normalized item record (TDD §6) plus:
--   interactive - false for a Recent entry no longer carried (UI_SPEC §9);
--                 defaults to true when bagID/slotID are present.
-- Binds the button to record.bagID/record.slotID so every click/drag
-- resolves to the item's REAL current location, never a stale one
-- (UI_SPEC §8 "Stale-location safety") - callers re-Configure on every
-- render rather than reusing a button's previous binding.
function ItemButtonPool:Configure(button, record)
    local interactive = record.interactive ~= false and record.bagID ~= nil and record.slotID ~= nil

    if button.icon then
        button.icon:SetTexture(record.texture)
    end
    if button.Count then
        button.Count:SetText(record.quantity and record.quantity > 1 and tostring(record.quantity) or "")
    end
    if SetItemButtonDesaturated then
        SetItemButtonDesaturated(button, record.isLocked and true or false)
    end
    if button.IconBorder then
        local color = record.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[record.quality]
        if color and record.quality > 1 then
            button.IconBorder:SetVertexColor(color.r, color.g, color.b)
            button.IconBorder:Show()
        else
            button.IconBorder:Hide()
        end
    end

    button.bagID = record.bagID
    button.slotID = record.slotID
    button.itemLink = record.itemLink

    button:SetScript("OnClick", function(self, mouseButton)
        if not interactive then
            return
        end
        if IsModifiedClick and IsModifiedClick() then
            BagAPI:HandleModifiedItemClick(self.itemLink)
        elseif mouseButton == "RightButton" then
            BagAPI:UseItem(self.bagID, self.slotID)
        else
            BagAPI:PickupItem(self.bagID, self.slotID)
        end
    end)

    button:SetScript("OnDragStart", function(self)
        if interactive then
            BagAPI:PickupItem(self.bagID, self.slotID)
        end
    end)

    button:SetScript("OnReceiveDrag", function(self)
        if interactive then
            BagAPI:PickupItem(self.bagID, self.slotID)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if interactive then
            BagAPI:SetTooltipToBagItem(GameTooltip, self.bagID, self.slotID)
        elseif self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
        else
            GameTooltip:Hide()
            return
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
