--[[
    UI/ItemButtonPool.lua - Reusable pool of item buttons/rows (TDD §13.4, §21)

    Flyouts and the full inventory view must not create new frames on every
    open; they Acquire()/ReleaseAll() from a shared pool per parent frame.
]]

local _, Pockets = ...

Pockets.UI.ItemButtonPool = Pockets.UI.ItemButtonPool or {}
local ItemButtonPool = Pockets.UI.ItemButtonPool

-- pools[parentFrame] = { free = {}, active = {} }
ItemButtonPool.pools = ItemButtonPool.pools or {}

local function CreateItemButton(parent)
    local button = CreateFrame("Button", nil, parent, "ItemButtonTemplate,BackdropTemplate")
    button:SetSize(Pockets.UI.Layout.ITEM_BUTTON_SIZE, Pockets.UI.Layout.ITEM_BUTTON_SIZE)
    button:Hide()
    return button
end

function ItemButtonPool:GetPool(parent)
    self.pools[parent] = self.pools[parent] or { free = {}, active = {} }
    return self.pools[parent]
end

-- Returns a hidden, ready-to-configure button. Caller must Show() it.
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
