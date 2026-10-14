--[[
    Tests/RadialGlanceTests.lua - Radial semicircle: arc geometry and edge
    orientation, metric-only satellites, recent strip, gold formatting,
    edge clamping, mode persistence, click routing, no item actions.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Shell = Pockets.UI.Shell
local RadialGlance = Pockets.UI.RadialGlance
local RadialLayout = Pockets.UI.RadialLayout
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

local function Items(n)
    local out = {}
    for i = 1, n do
        out[i] = { itemID = i, texture = i, quantity = i }
    end
    return out
end

local function Near(a, b) return math.abs(a - b) < 1e-6 end

TestRunner:Register("Radial: arc angles spread evenly across 180 degrees, none on the edge line", function()
    local one = RadialLayout.ArcAngles(1, 0, 180)
    local four = RadialLayout.ArcAngles(4, 0, 180)
    local up = RadialLayout.ArcAngles(3, 90, 180)
    local ok = #one == 1 and Near(one[1], 0)
        and Near(four[1], 67.5) and Near(four[2], 22.5) and Near(four[3], -22.5) and Near(four[4], -67.5)
        and Near(up[1], 150) and Near(up[2], 90) and Near(up[3], 30)
    return ok, ok and "OK" or "bad arc angles"
end)

TestRunner:Register("Radial: satellites face away from the nearest screen edge", function()
    local W, H = 1000, 800
    local ok = RadialLayout.EdgeAngle(50, 400, W, H) == 0 -- left edge: expand right
        and RadialLayout.EdgeAngle(950, 400, W, H) == 180 -- right edge: expand left
        and RadialLayout.EdgeAngle(500, 780, W, H) == -90 -- top edge: expand down
        and RadialLayout.EdgeAngle(500, 20, W, H) == 90 -- bottom edge: expand up
    local x, y = RadialLayout.PositionAt(0, 74)
    local x2, y2 = RadialLayout.PositionAt(90, 74)
    ok = ok and Near(x, 74) and Near(y, 0) and Near(x2, 0) and Near(y2, 74)
    return ok, ok and "OK" or "bad orientation/position"
end)

TestRunner:Register("Radial: ring slides to stay on screen but never past the max shift", function()
    local ext = { left = 90, right = 90, top = 90, bottom = 100 }
    local dx0, dy0 = RadialLayout.ClampOffset(500, 500, ext, 1000, 800, 24)
    local dxl, dyb = RadialLayout.ClampOffset(50, 50, ext, 1000, 800, 24)
    local dxr, dyt = RadialLayout.ClampOffset(990, 790, ext, 1000, 800, 24)
    local dxs = RadialLayout.ClampOffset(80, 400, ext, 1000, 800, 24)
    local ok = dx0 == 0 and dy0 == 0 and dxl == 24 and dyb == 24 and dxr == -24 and dyt == -24 and dxs == 10
    return ok, ok and "OK" or string.format("%s %s %s %s %s", dxl, dyb, dxr, dyt, dxs)
end)

TestRunner:Register("Radial: only available metrics appear - gold always, ammo and bags when present", function()
    local none = RadialGlance.BuildModel(5, {}, {})
    local ammo = RadialGlance.BuildModel(5, {
        { class = "ammo", used = 1, total = 18, utilization = 1 / 18, label = "Ammo" },
    }, {})
    local caps = {
        { class = "ammo", used = 0, total = 0 },
        { class = "reagents", used = 1, total = 36, label = "Reagents" },
        { class = "herbs", used = 2, total = 20, label = "Herbs" },
        { class = "mining", used = 3, total = 20, label = "Mining" },
    }
    local bags = RadialGlance.BuildModel(0, caps, {})
    local ok = #none == 1 and none[1].kind == "gold"
        and #ammo == 2 and ammo[2].isAmmo
        and #bags == 3 and bags[2].cap.class == "reagents" and bags[3].cap.class == "herbs"
    return ok, ok and "OK" or "bad metric list"
end)

TestRunner:Register("Radial: loose ammo (no quiver) shows an Ammo node with the summed count", function()
    local arrows = { { itemID = 1, texture = 9, quantity = 60 }, { itemID = 2, texture = 8, quantity = 40 } }
    local loose = RadialGlance.BuildModel(0, {}, arrows)
    local quiver = RadialGlance.BuildModel(0, {
        { class = "ammo", used = 2, total = 18, utilization = 2 / 18, label = "Ammo" },
    }, arrows)
    local none = RadialGlance.BuildModel(0, {}, {})
    local ok = loose[2].kind == "ammo" and loose[2].ammoCount == 100
        and quiver[2].kind == "bag" and quiver[2].ammoCount == 100
        and #none == 1 and RadialGlance.FormatCount(100) == "100"
        and RadialGlance.FormatCount(12500) == "12k"
    return ok, ok and "OK" or "bad ammo model"
end)

TestRunner:Register("Radial: recent strip keeps the newest five in order; empty gives none", function()
    local five = RadialGlance.BuildRecent(Items(20))
    local two = RadialGlance.BuildRecent(Items(2))
    local ok = #five == 5 and five[1].itemID == 1 and five[5].itemID == 5
        and #two == 2 and #RadialGlance.BuildRecent({}) == 0 and #RadialGlance.BuildRecent(nil) == 0
    return ok, ok and "OK" or "bad recent list"
end)

TestRunner:Register("Radial: strip is 136x30 with exact 24px icons; satellites sit on the arc", function()
    local ok = WithMode(Mode.RADIAL, function()
        local strip = Shell.radial.strip
        local w, h = strip:GetSize()
        local iw, ih = strip.icons[1]:GetSize()
        local span = L.RADIAL_STRIP_PAD_X * 2 + 5 * L.RADIAL_STRIP_ICON + 4 * L.RADIAL_STRIP_GAP
        return w == 136 and h == 30 and iw == 24 and ih == 24 and #strip.icons == 5 and span == w
            and L.RADIAL_SLOTS == 4
    end)
    return ok, ok and "OK" or "bad strip geometry"
end)

TestRunner:Register("Radial: gold stays compact and keeps its denomination", function()
    local F = RadialGlance.FormatGold
    local ok = F(0) == "0c" and F(45) == "45c" and F(1200) == "12s" and F(1520000) == "152g"
        and F(124000000) == "12.4kg" and F(12000000000) == "1.2mg" and F(-5) == "0c" and F(nil) == "0c"
    return ok, ok and "OK" or string.format("%s %s %s", F(1520000), F(124000000), F(12000000000))
end)

TestRunner:Register("Radial: mode persists, centre keeps Mini footprint and anchor, nodes build once", function()
    local p0, _, rp0, x0, y0 = Shell.root:GetPoint()
    local nodeCount = #Shell.radial.nodes
    local ok = WithMode(Mode.RADIAL, function()
        local w, h = Shell.root:GetSize()
        local p1, _, rp1, x1, y1 = Shell.root:GetPoint()
        return Shell:IsRadial() and Pockets.SavedSettings.hudMode == Mode.RADIAL
            and w == L.MINI_WIDTH and h == L.MINI_HEIGHT and Shell.mini:IsShown()
            and p0 == p1 and rp0 == rp1 and x0 == x1 and y0 == y1
            and Shell.radial.nodes[1]:IsShown()
    end)
    local hidden = not Shell.radial.nodes[1]:IsShown() and not Shell.radial.strip:IsShown()
    local ok2 = nodeCount == L.RADIAL_SLOTS and #Shell.radial.nodes == nodeCount
    return ok and hidden and ok2, (ok and hidden and ok2) and "OK" or "radial mode state wrong"
end)

TestRunner:Register("Radial: centre click opens the list; recent icon opens Recent; no item actions", function()
    local results = WithMode(Mode.RADIAL, function()
        local r = {}
        Shell.root:Click()
        r.center = Shell:GetState() == Shell.STATE.MENU
        Shell:SetState(Shell.STATE.GLANCE)
        local icon = Shell.radial.strip.icons[1]
        r.hasItem = icon:IsShown()
        if r.hasItem then
            icon:Click()
            r.recent = Shell:GetState() == Shell.STATE.CATEGORY
                and Shell.context.categoryID == Constants.CATEGORY.RECENT
        end
        r.noItemUse = icon:GetAttribute("type") == nil and icon:GetAttribute("item") == nil
        return r
    end)
    -- Recent may legitimately be empty in the test environment.
    local ok = results.center and results.noItemUse and (not results.hasItem or results.recent)
    return ok, ok and "OK" or string.format("center=%s recent=%s noItemUse=%s",
        tostring(results.center), tostring(results.recent), tostring(results.noItemUse))
end)

TestRunner:Register("Radial: satellites dim when idle and brighten on hover", function()
    local radial = Shell.radial
    radial.hovered = false
    RadialGlance:ApplyAlpha(radial)
    local idle = radial.nodes[1]:GetAlpha()
    radial.hovered = true
    RadialGlance:ApplyAlpha(radial)
    local hot = radial.nodes[1]:GetAlpha()
    radial.hovered = false
    RadialGlance:ApplyAlpha(radial)
    local ok = math.abs(idle - L.RADIAL_IDLE_ALPHA) < 0.01 and hot == 1
    return ok, ok and "OK" or string.format("idle=%s hot=%s", idle, hot)
end)

TestRunner:Register("Radial: recent node hover shows the big preview only when enabled", function()
    local node = Shell.radial.strip.icons[1]
    local settings = Pockets.SavedSettings
    local original = settings.recentItemPreviewEnabled
    local record = { itemID = 6948, texture = "Interface\\Icons\\INV_Misc_Rune_01", quantity = 1 }
    local enter, leave = RadialGlance.ItemHover(record)
    settings.recentItemPreviewEnabled = false
    enter(node)
    local frame = Pockets.UI.ItemPreview.frame
    local offOK = not (frame and frame:IsShown())
    settings.recentItemPreviewEnabled = true
    enter(node)
    local onOK = Pockets.UI.ItemPreview.frame:IsShown()
    leave(node)
    local hidden = not Pockets.UI.ItemPreview.frame:IsShown()
    GameTooltip:Hide()
    settings.recentItemPreviewEnabled = original
    local ok = offOK and onOK and hidden
    return ok, ok and "OK" or string.format("off=%s on=%s hidden=%s", tostring(offOK), tostring(onOK), tostring(hidden))
end)
