--[[
    UI/ItemButtonPool.lua - Reusable pool of REAL item buttons (TDD §13.4,
    §21; UI_SPEC §8, §10, §14)

    Flyouts and the full inventory view must not create new frames on every
    open; they Acquire()/ReleaseAll() from a shared pool per parent frame.

    Configure() is the single place that wires a pooled button to a live
    bag+slot via Adapters/BagAPI's pickup/use/tooltip wrappers, so
    click/right-click/shift-click/drag/tooltip behave normally. Shared by
    every body Shell renders (Category grid, All Items flow) so both stay
    in sync (UI_SPEC §10 "share item rendering/pooling code").
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

-- Converts one InventoryState:AggregateRecords() aggregate ({ itemID,
-- itemLink, texture, quality, totalQuantity, stacks = {...} }) into the
-- flat record shape Configure() expects below (quantity, not
-- totalQuantity), bound to a representative physical stack. Prefers the
-- SMALLEST unlocked stack (Glance UI §7 - less disruptive to manipulate,
-- matches InventoryState:ResolveSmallestStack's resolver used again at
-- interaction time), falling back to any locked stack only if nothing is
-- unlocked. Shared by Shell's Category/All rendering so every item grid
-- collapses identical itemIDs into one button the same way.
function ItemButtonPool.ToButtonRecord(agg)
    local representative
    for _, stack in ipairs(agg.stacks) do
        if not stack.isLocked and (not representative or (stack.quantity or 0) < (representative.quantity or 0)) then
            representative = stack
        end
    end
    representative = representative or agg.stacks[1]

    return {
        itemID = agg.itemID,
        itemLink = agg.itemLink,
        name = agg.name,
        texture = agg.texture,
        quality = agg.quality,
        quantity = agg.totalQuantity,
        isLocked = representative and representative.isLocked,
        bagID = representative and representative.bagID,
        slotID = representative and representative.slotID,
        interactive = representative ~= nil,
    }
end

-- Re-resolves a button's physical stack at the moment of interaction
-- rather than trusting whatever bagID/slotID it was Configure()'d with
-- (Glance UI §7 "resolve the physical stack when the interaction occurs" /
-- "reject stale location"). If the bound stack is still valid, use it
-- unchanged (stable target for repeated clicks); otherwise fall back to
-- InventoryState's smallest-current-stack resolver. Returns
-- bagID, slotID, quantity (quantity of that specific physical stack, not
-- the aggregate total - needed for split-stack's max amount).
local function ResolveInteractionStack(button)
    local InventoryState = Pockets.Services.InventoryState
    if InventoryState:IsValidStack(button.bagID, button.slotID, button.itemID) then
        local record = InventoryState:GetItem(button.bagID .. ":" .. button.slotID)
        return button.bagID, button.slotID, record and record.quantity
    end
    local resolved = InventoryState:ResolveSmallestStack(button.itemID)
    if resolved then
        return resolved.bagID, resolved.slotID, resolved.quantity
    end
    return nil, nil, nil
end

-- record: a normalized item record (TDD §6) plus:
--   interactive - false for a Recent entry no longer carried (UI_SPEC §9);
--                 defaults to true when bagID/slotID are present.
-- Binds the button to record.itemID (used to re-resolve a fresh physical
-- stack at interaction time via ResolveInteractionStack above) rather than
-- trusting record.bagID/slotID forever - callers re-Configure on every
-- render, but interactions between renders must never act on a stale
-- location (UI_SPEC §8 "Stale-location safety").
function ItemButtonPool:Configure(button, record)
    local interactive = record.interactive ~= false and record.bagID ~= nil and record.slotID ~= nil

    if button.icon then
        button.icon:SetTexture(record.texture)
    end
    -- SetItemButtonCount (not a raw button.Count:SetText()) is what
    -- actually shows/hides the count fontstring - it starts hidden, and
    -- a bare :SetText() alone never makes it visible again.
    local quantity = record.quantity or 0
    if SetItemButtonCount then
        SetItemButtonCount(button, quantity)
    elseif button.Count then
        button.Count:SetText(quantity > 1 and tostring(quantity) or "")
        if quantity > 1 then button.Count:Show() else button.Count:Hide() end
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
    button.itemID = record.itemID
    button.itemLink = record.itemLink
    button.quantity = record.quantity

    -- SplitStack is the callback contract OpenStackSplitFrame calls once
    -- the player confirms an amount (standard WoW stack-split UI).
    button.SplitStack = function(self, amount)
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:SplitStack(bagID, slotID, amount)
        end
    end

    button:SetScript("OnClick", function(self, mouseButton)
        if not interactive then
            return
        end
        if IsModifiedClick and IsModifiedClick("SPLITSTACK") and OpenStackSplitFrame then
            local bagID, slotID, quantity = ResolveInteractionStack(self)
            if bagID and quantity and quantity > 1 then
                self.bagID, self.slotID = bagID, slotID
                OpenStackSplitFrame(quantity, self, "BOTTOMLEFT", "TOPLEFT")
            end
        elseif IsModifiedClick and IsModifiedClick() then
            -- Chat-link/delete-confirm/etc - Blizzard's own handler,
            -- never intercepted by Pockets navigation (Glance UI §6).
            BagAPI:HandleModifiedItemClick(self.itemLink)
        elseif mouseButton == "RightButton" then
            local bagID, slotID = ResolveInteractionStack(self)
            if bagID then
                BagAPI:UseItem(bagID, slotID)
            end
        else
            local bagID, slotID = ResolveInteractionStack(self)
            if bagID then
                BagAPI:PickupItem(bagID, slotID)
            end
        end
    end)

    button:SetScript("OnDragStart", function(self)
        if not interactive then
            return
        end
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:PickupItem(bagID, slotID)
        end
    end)

    button:SetScript("OnReceiveDrag", function(self)
        if not interactive then
            return
        end
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:PickupItem(bagID, slotID)
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
