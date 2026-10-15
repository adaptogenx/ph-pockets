--[[
    Tests/SidecarHUDTests.lua - Sidecar HUD: layout tokens, gold fixed /
    ammo conditional, content-sized recent strip, no radial satellites,
    mode persistence, anchor, and click routing.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Shell = Pockets.UI.Shell
local SidecarHUD = Pockets.UI.SidecarHUD
local RadialGlance = Pockets.UI.RadialGlance
local Constants = Pockets.Constants
local L = Constants.LAYOUT
local Mode = Constants.HUD_MODE

local function WithMode(mode, fn)
    local previous = Shell:GetHudMode()
    Shell:SetState(Shell.STATE.GLANCE)
    Shell:SetHudMode(mode)
    local ok, a = pcall(fn)
    Shell:SetHudMode(previous)
    Shell:SetState(Shell.STATE.GLANCE)
    if not ok then
        error(a)
    end
    return a
end

TestRunner:Register("Sidecar: layout tokens match the spec", function()
    local S = SidecarHUD.STRIP_SPEC
    local ok = L.SIDECAR_BADGE_WIDTH == 42 and L.SIDECAR_BADGE_HEIGHT == 18 and L.SIDECAR_BADGE_GAP == 3
        and L.SIDECAR_MINI_GAP == 4 and S.icon == 18 and S.gap == 3 and S.padX == 4 and S.height == 26
        and L.SIDECAR_STRIP_BELOW == 3 and S.icons == 5
        and S.height == S.icon + 8 -- 4px vertical padding
        and RadialGlance.StripWidth(5, S) <= L.MINI_WIDTH + L.SIDECAR_MINI_GAP + L.SIDECAR_BADGE_WIDTH + 4
    return ok, ok and "OK" or "bad sidecar tokens"
end)

TestRunner:Register("Sidecar: gold always present; ammo only when applicable", function()
    local none = SidecarHUD.BuildModel(5, {}, {})
    local quiver = SidecarHUD.BuildModel(5, {
        { class = "ammo", used = 1, total = 18, label = "Ammo" },
    }, {})
    local loose = SidecarHUD.BuildModel(5, {}, { { itemID = 1, texture = 9, quantity = 187 } })
    local bagOnly = SidecarHUD.BuildModel(5, {
        { class = "herbs", used = 1, total = 20, label = "Herbs" },
    }, {})
    local ok = none.gold == 5 and none.ammo == nil and quiver.ammo ~= nil and quiver.ammo.isAmmo
        and loose.ammo and loose.ammo.ammoCount == 187 and bagOnly.ammo == nil
    return ok, ok and "OK" or "bad sidecar model"
end)

TestRunner:Register("Sidecar: badge is 42px minimum and grows with long text; strip is content-sized", function()
    local S = SidecarHUD.STRIP_SPEC
    local ok = SidecarHUD.BadgeWidth(10) == 42 and SidecarHUD.BadgeWidth(40) > 42
        and RadialGlance.StripWidth(5, S) == 2 * 4 + 5 * 18 + 4 * 3
        and RadialGlance.StripWidth(2, S) == 2 * 4 + 2 * 18 + 3
        and RadialGlance.StripWidth(2, S) < RadialGlance.StripWidth(5, S)
    return ok, ok and "OK" or "bad widths"
end)

TestRunner:Register("Sidecar: mode keeps the Mini footprint and anchor; no radial satellites", function()
    local p0, _, rp0, x0, y0 = Shell.root:GetPoint()
    local ok = WithMode(Mode.SIDECAR, function()
        local w, h = Shell.root:GetSize()
        local p1, _, rp1, x1, y1 = Shell.root:GetPoint()
        local radialShown = false
        for _, node in ipairs(Shell.radial.nodes) do
            radialShown = radialShown or node:IsShown()
        end
        return Shell:IsSidecar() and Pockets.SavedSettings.hudMode == Mode.SIDECAR
            and w == L.MINI_WIDTH and h == L.MINI_HEIGHT and Shell.mini:IsShown()
            and p0 == p1 and rp0 == rp1 and x0 == x1 and y0 == y1
            and Shell.sidecar.gold:IsShown() and not radialShown and not Shell.radial.strip:IsShown()
    end)
    local hidden = not Shell.sidecar.gold:IsShown() and not Shell.sidecar.ammo:IsShown()
        and not Shell.sidecar.strip:IsShown()
    return ok and hidden, (ok and hidden) and "OK" or "sidecar mode state wrong"
end)

TestRunner:Register("Sidecar: gold centres on the Mini when ammo hides; Mini click opens the list", function()
    local result = WithMode(Mode.SIDECAR, function()
        local sidecar = Shell.sidecar
        local InventoryState = Pockets.Services.InventoryState
        local original = InventoryState.GetSpecializedCapacities
        InventoryState.GetSpecializedCapacities = function()
            return { { class = "ammo", used = 1, total = 18, utilization = 1 / 18, label = "Ammo", texture = 1 } }
        end
        SidecarHUD:Render(sidecar)
        local _, _, _, _, gy1 = sidecar.gold:GetPoint()
        local ammoShown = sidecar.ammo:IsShown()
        InventoryState.GetSpecializedCapacities = function() return {} end
        local api = Pockets.API.GetAggregatedCategoryItems
        Pockets.API.GetAggregatedCategoryItems = function() return {} end
        SidecarHUD:Render(sidecar)
        local _, _, _, _, gy2 = sidecar.gold:GetPoint()
        local ammoHidden = not sidecar.ammo:IsShown()
        local stripHidden = not sidecar.strip:IsShown()
        Pockets.API.GetAggregatedCategoryItems = api
        InventoryState.GetSpecializedCapacities = original
        Shell.root:Click()
        local centred = math.abs(gy2 + (L.MINI_PORTRAIT_SIZE - L.SIDECAR_BADGE_HEIGHT) / 2) < 0.01
        return ammoShown and ammoHidden and stripHidden and centred and gy1 > gy2
            and Shell:GetState() == Shell.STATE.MENU
    end)
    return result, result and "OK" or "ammo/gold/strip/click behavior wrong"
end)
