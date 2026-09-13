--[[
    UI/ItemButtonPool.lua - Reusable pool of REAL item buttons (TDD §13.4,
    §21; UI_SPEC §8, §10, §14)

    Flyouts and the full inventory view must not create new frames on every
    open; they Acquire()/ReleaseAll() from a shared pool per parent frame.

    Configure() is the single place that wires a pooled button to a live
    bag+slot: left-click/drag/split/tooltip go through Adapters/BagAPI on
    PreClick, and right-click use/equip/disenchant-target is Blizzard's own
    ContainerFrameItemButtonTemplate OnClick - never wrapped or replaced,
    only ever HookScript'd non-destructively if ever needed. That template
    resolves bag/slot itself, live at click time, via
    self:GetParent():GetID() (bagID) and self:GetID() (slotID) - the same
    mechanism Blizzard's own bag UI and every bag-replacement addon
    (confirmed against Baganator's real source) relies on, including native
    combat-safety and disenchant/enchant spell-targeting, with no custom
    secure-attribute bookkeeping required on our end. Pockets' pools are
    item-major (one grid mixes items from many bags), unlike a bag-major
    index frame, so each pooled button gets its own tiny bagIndexFrame
    wrapper carrying the bagID via SetID - see Acquire/Configure below.
    Shared by every body Shell renders (Category grid, All Items flow) so
    both stay in sync (UI_SPEC §10 "share item rendering/pooling code").
]]

local _, Pockets = ...

Pockets.UI.ItemButtonPool = Pockets.UI.ItemButtonPool or {}
local ItemButtonPool = Pockets.UI.ItemButtonPool

local BagAPI = Pockets.Adapters.BagAPI
local SIZE = Pockets.Constants.LAYOUT.ITEM_BUTTON_SIZE

-- pools[parentFrame] = { free = {}, active = {} }
ItemButtonPool.pools = ItemButtonPool.pools or {}

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

-- Pickup/split-stack/modified-click path (wired on PreClick). Right-click
-- use is not handled here - it's Blizzard's own inherited OnClick (see
-- CreateItemButton), resolved from the button's own bagIndexFrame/self ID.
function ItemButtonPool.HandleInsecureClick(self, mouseButton)
    if not self.interactive then
        return
    end
    if IsModifiedClick and IsModifiedClick("SPLITSTACK") and OpenStackSplitFrame then
        local bagID, slotID, quantity = ResolveInteractionStack(self)
        if bagID and quantity and quantity > 1 then
            self.bagID, self.slotID = bagID, slotID
            OpenStackSplitFrame(quantity, self, "BOTTOMLEFT", "TOPLEFT")
        end
        return
    end
    if IsModifiedClick and IsModifiedClick() then
        -- Chat-link/delete-confirm/etc - Blizzard's own handler,
        -- never intercepted by Pockets navigation (Glance UI §6).
        BagAPI:HandleModifiedItemClick(self.itemLink)
        return
    end
    if mouseButton == "RightButton" then
        return
    end
    local bagID, slotID = ResolveInteractionStack(self)
    if bagID then
        BagAPI:PickupItem(bagID, slotID)
    end
end

-- Scripts are wired once at create time. OnClick is deliberately never
-- SetScript'd/replaced - it stays ContainerFrameItemButtonTemplate's own
-- Blizzard handler, which performs left-click pickup, right-click use/
-- equip, disenchant/enchant spell-targeting, and split-stack natively
-- (resolved from self:GetParent():GetID()/self:GetID() - see
-- CreateItemButton/Configure). PreClick only adds Pockets' own modified-
-- click (chat-link) and split-stack-frame handling on top.
local function WireItemButtonScripts(button)
    if button.pocketsScriptsWired then
        return
    end
    button.pocketsScriptsWired = true

    button:SetScript("PreClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local modified = IsModifiedClick and IsModifiedClick()
            if self.interactive and not modified then
                return
            end
        end
        ItemButtonPool.HandleInsecureClick(self, mouseButton)
    end)

    button.SplitStack = function(self, amount)
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:SplitStack(bagID, slotID, amount)
        end
    end

    button:SetScript("OnDragStart", function(self)
        if not self.interactive then
            return
        end
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:PickupItem(bagID, slotID)
        end
    end)

    button:SetScript("OnReceiveDrag", function(self)
        if not self.interactive then
            return
        end
        local bagID, slotID = ResolveInteractionStack(self)
        if bagID then
            BagAPI:PickupItem(bagID, slotID)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.interactive then
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

-- ContainerFrameItemButtonTemplate resolves bag/slot via
-- self:GetParent():GetID() (bagID) / self:GetID() (slotID), same as
-- Blizzard's real bag frames and every bag-replacement addon that
-- inherits it (confirmed against Baganator's live source). Pockets'
-- pools are item-major (one grid mixes items from many bags), unlike a
-- bag-major index frame, so each button gets its OWN tiny bagIndexFrame
-- wrapper carrying the bagID - see Configure, which sets both IDs fresh
-- every render.
local function CreateItemButton(parent)
    local bagIndexFrame = CreateFrame("Frame", nil, parent)

    local button = CreateFrame(
        "Button",
        nil,
        bagIndexFrame,
        "ContainerFrameItemButtonTemplate,BackdropTemplate"
    )
    button.bagIndexFrame = bagIndexFrame
    button:SetSize(SIZE, SIZE)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    WireItemButtonScripts(button)
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
        -- pcall'd defensively so a recycle can never throw out of
        -- ClearBody regardless of template/combat quirks.
        pcall(function()
            button:Hide()
            button:ClearAllPoints()
        end)
        table.insert(pool.free, button)
    end
    pool.active = {}
end

-- record: a normalized item record (TDD §6) plus:
--   interactive - false for a Recent entry no longer carried (UI_SPEC §9);
--                 defaults to true when bagID/slotID are present.
-- Binds the button to record.itemID (used to re-resolve a fresh physical
-- stack at interaction time via ResolveInteractionStack above) rather than
-- trusting record.bagID/slotID forever - callers re-Configure on every
-- render, but interactions between renders must never act on a stale
-- location (UI_SPEC §8 "Stale-location safety"). Right-click use/equip/
-- disenchant-target resolves bag/slot itself, live at click time, via
-- ContainerFrameItemButtonTemplate's own OnClick reading
-- bagIndexFrame:GetID()/button:GetID() - so binding those here just keeps
-- them in sync with this render's physical location, the same as every
-- other field on the button.
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
    -- ContainerFrameItemButtonTemplate (unlike the old bare
    -- ItemButtonTemplate Pockets used before) ships several Blizzard
    -- attention/decoration overlays Pockets never asked for and never
    -- managed - identified via /pockets debug regions against a real
    -- button rather than guessed at: "flash" (a 90x90 glow, oversized at
    -- every Pockets button size) and "BattlepayItemTexture" (a shop-item
    -- ribbon) were both found rendering unconditionally regardless of
    -- item type. Explicitly hidden every render alongside NewItemTexture
    -- rather than left at whatever the inherited template defaults to.
    if button.NewItemTexture then
        button.NewItemTexture:Hide()
    end
    if button.flash then
        button.flash:Hide()
    end
    if button.BattlepayItemTexture then
        button.BattlepayItemTexture:Hide()
    end

    button.bagID = record.bagID
    button.slotID = record.slotID
    button.itemID = record.itemID
    button.itemLink = record.itemLink
    button.quantity = record.quantity
    button.interactive = interactive

    -- 0/0 when non-interactive so a recycled pool button can never
    -- resolve to a previous item's slot (same "reject stale location"
    -- intent as button.bagID/slotID above, just for Blizzard's own
    -- click resolution instead of Pockets').
    if interactive then
        button.bagIndexFrame:SetID(record.bagID)
        button:SetID(record.slotID)
    else
        button.bagIndexFrame:SetID(0)
        button:SetID(0)
    end
end
