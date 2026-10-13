--[[
    Tests/RadialGlanceTests.lua - Outer Ring TDD §8: stable slot geometry,
    semantic slot assignment, recent ordering/overflow, gold formatting,
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
local S = RadialGlance.SLOT

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

TestRunner:Register("Radial: eight slots start at the top and run clockwise, all distinct", function()
    local n = L.RADIAL_SLOTS
    local x1, y1 = RadialLayout.Position(1, n, 72)
    local x3, y3 = RadialLayout.Position(3, n, 72)
    local x5, y5 = RadialLayout.Position(5, n, 72)
    local x7, y7 = RadialLayout.Position(7, n, 72)
    local seen, unique = {}, true
    for slot = 1, n do
        local x, y = RadialLayout.Position(slot, n, 72)
        local key = string.format("%.3f,%.3f", x, y)
        if seen[key] then unique = false end
        seen[key] = true
        if not Near(math.sqrt(x * x + y * y), 72) then unique = false end
    end
    local ok = n == 8 and Near(x1, 0) and Near(y1, 72) and Near(x3, 72) and Near(y3, 0)
        and Near(x5, 0) and Near(y5, -72) and Near(x7, -72) and Near(y7, 0) and unique
    return ok, ok and "OK" or "bad radial geometry"
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

TestRunner:Register("Radial: slots are semantic - missing ammo/bags leave blanks, recents stay put", function()
    local none = RadialGlance.BuildModel(5, {}, Items(2))
    local withAmmo = RadialGlance.BuildModel(5, {
        { class = "ammo", used = 1, total = 18, utilization = 1 / 18, label = "Ammo" },
    }, Items(2))
    local ok = none[S.GOLD].kind == "gold" and none[S.AMMO] == nil and none[S.SPEC_1] == nil
        and none[S.RECENT_FIRST].item.itemID == 1 and none[S.RECENT_FIRST + 1].item.itemID == 2
        and withAmmo[S.AMMO].isAmmo and withAmmo[S.RECENT_FIRST].item.itemID == 1
        and withAmmo[S.SPEC_1] == nil
    return ok, ok and "OK" or "slot reshuffle"
end)

TestRunner:Register("Radial: at most two specialized bags; zero-total bags are not shown", function()
    local caps = {
        { class = "ammo", used = 0, total = 0 },
        { class = "reagents", used = 1, total = 36, label = "Reagents" },
        { class = "herbs", used = 2, total = 20, label = "Herbs" },
        { class = "mining", used = 3, total = 20, label = "Mining" },
    }
    local m = RadialGlance.BuildModel(0, caps, {})
    local ok = m[S.AMMO] == nil and m[S.SPEC_1].cap.class == "reagents" and m[S.SPEC_2].cap.class == "herbs"
    return ok, ok and "OK" or "bad specialized slots"
end)

TestRunner:Register("Radial: recents fill slots 5-8 then unused ammo/bag slots; none when empty", function()
    local empty = RadialGlance.BuildModel(0, {}, {})
    local two = RadialGlance.BuildModel(0, {}, Items(2))
    local many = RadialGlance.BuildModel(0, {}, Items(20))
    local oneBag = RadialGlance.BuildModel(0, {
        { class = "herbs", used = 1, total = 20, label = "Herbs" },
    }, Items(20))
    local ok = empty[5] == nil and empty[2] == nil
        and two[5].item.itemID == 1 and two[6].item.itemID == 2 and two[7] == nil and two[2] == nil
        and many[8].item.itemID == 4 and many[2].item.itemID == 5 and many[3].item.itemID == 6
        and many[4].item.itemID == 7 and many[1].kind == "gold"
        and oneBag[3].kind == "bag" and oneBag[2].item.itemID == 5 and oneBag[4].item.itemID == 6
    return ok, ok and "OK" or "bad recent fill"
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
    local hidden = not Shell.radial.nodes[1]:IsShown()
    local ok2 = nodeCount == L.RADIAL_SLOTS and #Shell.radial.nodes == nodeCount
    return ok and hidden and ok2, (ok and hidden and ok2) and "OK" or "radial mode state wrong"
end)

TestRunner:Register("Radial: centre click opens the list; recent node opens Recent; nodes have no item actions", function()
    local results = WithMode(Mode.RADIAL, function()
        local r = {}
        Shell.root:Click()
        r.center = Shell:GetState() == Shell.STATE.MENU
        Shell:SetState(Shell.STATE.GLANCE)
        local node = Shell.radial.nodes[S.RECENT_FIRST]
        r.hasItemNode = node:IsShown()
        if r.hasItemNode then
            node:Click()
            r.recent = Shell:GetState() == Shell.STATE.CATEGORY
                and Shell.context.categoryID == Constants.CATEGORY.RECENT
        end
        r.noItemUse = node:GetAttribute("type") == nil and node:GetAttribute("item") == nil
        return r
    end)
    -- Recent may legitimately be empty in the test environment.
    local ok = results.center and results.noItemUse and (not results.hasItemNode or results.recent)
    return ok, ok and "OK" or string.format("center=%s recent=%s noItemUse=%s",
        tostring(results.center), tostring(results.recent), tostring(results.noItemUse))
end)

TestRunner:Register("Radial: loose ammo (no quiver) shows an Ammo node with the summed count", function()
    local arrows = { { itemID = 1, texture = 9, quantity = 60 }, { itemID = 2, texture = 8, quantity = 40 } }
    local loose = RadialGlance.BuildModel(0, {}, {}, arrows)
    local quiver = RadialGlance.BuildModel(0, {
        { class = "ammo", used = 2, total = 18, utilization = 2 / 18, label = "Ammo" },
    }, {}, arrows)
    local none = RadialGlance.BuildModel(0, {}, {}, {})
    local ok = loose[S.AMMO].kind == "ammo" and loose[S.AMMO].ammoCount == 100
        and quiver[S.AMMO].kind == "bag" and quiver[S.AMMO].ammoCount == 100
        and none[S.AMMO] == nil and RadialGlance.FormatCount(100) == "100"
        and RadialGlance.FormatCount(12500) == "12k"
    return ok, ok and "OK" or "bad ammo model"
end)

TestRunner:Register("Radial: recent node hover shows the big preview only when enabled", function()
    local node = Shell.radial.nodes[S.RECENT_FIRST]
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
