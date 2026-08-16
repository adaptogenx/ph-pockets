--[[
    Adapters/BindingsAPI.lua - Isolates keybinding registration (TDD §3.1, §17)

    Defines the binding header/name strings consumed by Bindings.xml and
    routes the bound action to Pockets.API so the binding is never coupled
    directly to a frame instance.
]]

local _, Pockets = ...

Pockets.Adapters.BindingsAPI = Pockets.Adapters.BindingsAPI or {}

-- Binding header shown in Key Bindings UI, and the action name/label.
_G.BINDING_HEADER_POCKETS = "Pockets"
_G.BINDING_NAME_POCKETS_TOGGLE_FULL_INVENTORY = "Toggle Full Inventory"

-- Called by Bindings.xml via the POCKETS_TOGGLE_FULL_INVENTORY binding action.
function Pockets_ToggleFullInventory()
    if Pockets.API and Pockets.API.ToggleFullInventory then
        Pockets.API.ToggleFullInventory()
    end
end
