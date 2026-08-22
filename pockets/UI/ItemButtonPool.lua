--[[
    UI/ItemButtonPool.lua - Reusable pool of REAL item buttons (TDD §13.4,
    §21; UI_SPEC §8, §10, §14)

    Flyouts and the full inventory view must not create new frames on every
    open; they Acquire()/ReleaseAll() from a shared pool per parent frame.

    Configure() is the single place that wires a pooled button to a live
    bag+slot: left-click/drag/split/tooltip go through Adapters/BagAPI,
    and right-click use is bound via SecureActionButtonTemplate attributes
    (type2=item) so Blizzard's protected-action rules allow it. Do not wrap
    or replace OnClick - that taints the handler. Equipping armor can still
    succeed from tainted code; using a consumable cannot. Insecure
    pickup/modified-clicks belong on PreClick. Security
    stays on these pooled buttons - the Pockets root frame is not secure.
    Shared by every body Shell renders (Category grid, All Items flow) so
    both stay in sync (UI_SPEC §10 "share item rendering/pooling code").
]]

local _, Pockets = ...

Pockets.UI.ItemButtonPool = Pockets.UI.ItemButtonPool or {}
local ItemButtonPool = Pockets.UI.ItemButtonPool

local BagAPI = Pockets.Adapters.BagAPI
local CombatAPI = Pockets.Adapters.CombatAPI
local SIZE = Pockets.Constants.LAYOUT.ITEM_BUTTON_SIZE

-- pools[parentFrame] = { free = {}, active = {} }
ItemButtonPool.pools = ItemButtonPool.pools or {}

-- Buttons whose type2/item2 attributes could not be written during combat
-- and must be flushed on PLAYER_REGEN_ENABLED.
local pendingSecureButtons = {}

local function IsInCombat(inCombat)
    if inCombat ~= nil then
        return inCombat and true or false
    end
    return CombatAPI:IsInCombat()
end

-- Binds (or clears) the right-click secure use action. SetAttribute is
-- forbidden during combat, so a lockdown call only records the intended
-- bag/slot and waits for FlushPendingSecureBindings.
function ItemButtonPool.ApplySecureUseBinding(button, bagID, slotID, inCombat)
    if IsInCombat(inCombat) then
        button.pendingSecureBagID = bagID
        button.pendingSecureSlotID = slotID
        pendingSecureButtons[button] = true
        return
    end

    if bagID and slotID then
        button:SetAttribute("type2", "item")
        button:SetAttribute("item2", tostring(bagID) .. " " .. tostring(slotID))
    else
        button:SetAttribute("type2", nil)
        button:SetAttribute("item2", nil)
    end
    button.pendingSecureBagID = nil
    button.pendingSecureSlotID = nil
    pendingSecureButtons[button] = nil
end

function ItemButtonPool:FlushPendingSecureBindings(inCombat)
    if IsInCombat(inCombat) then
        return
    end
    local snapshot = {}
    for button in pairs(pendingSecureButtons) do
        snapshot[#snapshot + 1] = button
    end
    for i = 1, #snapshot do
        local button = snapshot[i]
        ItemButtonPool.ApplySecureUseBinding(
            button,
            button.pendingSecureBagID,
            button.pendingSecureSlotID,
            false
        )
    end
end

-- Secure attributes cannot change during combat; apply anything queued
-- the moment lockdown lifts. Localized here so the root frame stays
-- a normal (non-secure) Button.
local regenWatcher = CreateFrame("Frame")
regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
regenWatcher:SetScript("OnEvent", function()
    ItemButtonPool:FlushPendingSecureBindings()
end)

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

-- Insecure click path (wired on PreClick): pickup, split-stack, and
-- Blizzard modified-click (chat-link etc). Right-click use is not
-- handled here - UseContainerItem must run from the untainted
-- SecureActionButtonTemplate OnClick using attributes from Configure().
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

-- Scripts are wired once at create time. Re-SetScript during Configure
-- would fail in combat on a protected SecureActionButton. OnClick is
-- left as SecureActionButtonTemplate's Blizzard handler so item use
-- runs untainted; wrapping it is what made armor equip while potions
-- were blocked (SECURE_ACTIONS.item: EquipItemByName vs UseContainerItem).
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

local function CreateItemButton(parent)
    local button = CreateFrame(
        "Button",
        nil,
        parent,
        "ItemButtonTemplate,BackdropTemplate,SecureActionButtonTemplate"
    )
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
        -- Hide/ClearAllPoints are protected on SecureActionButtons;
        -- pcall so a combat recycle never throws out of ClearBody.
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
-- location (UI_SPEC §8 "Stale-location safety"). Right-click use cannot
-- re-resolve at click time (secure attributes must be set ahead of time),
-- so Configure binds type2/item2 to this render's physical bag/slot.
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
    button.interactive = interactive

    -- Right-click use: secure item attribute on the resolved physical
    -- slot from this render. Cleared when the button is non-interactive
    -- so a recycled pool button cannot use a previous item. Deferred
    -- until PLAYER_REGEN_ENABLED if this runs during combat lockdown.
    if interactive then
        ItemButtonPool.ApplySecureUseBinding(button, record.bagID, record.slotID)
    else
        ItemButtonPool.ApplySecureUseBinding(button, nil, nil)
    end
end
