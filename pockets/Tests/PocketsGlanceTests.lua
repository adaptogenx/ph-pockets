--[[
    Tests/PocketsGlanceTests.lua - Forever Glance TDD acceptance cases
    (§9): fixed chassis size, header order, no Recent label, capacity
    formatting/colors, ETA text, bag classification, mixed-bag capacity,
    tab models, and that tabs/updates never change the HUD's size/anchor.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Shell = Pockets.UI.Shell
local PocketsGlance = Pockets.UI.PocketsGlance
local GlanceFrame = Pockets.UI.GlanceFrame
local BagAPI = Pockets.Adapters.BagAPI
local Layout = Pockets.UI.Layout
local T = GlanceFrame.TOKENS

local function Reset()
    Shell:SetState(Shell.STATE.GLANCE)
end

-- Collects every FontString text under a frame (recursively).
local function CollectTexts(frame, out)
    out = out or {}
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetText and region:GetText() then
            table.insert(out, region:GetText())
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        CollectTexts(child, out)
    end
    return out
end

TestRunner:Register("Glance: HUD width equals pH's expanded HUD width; height comes from the shared tokens", function()
    Reset()
    local w, h = Shell.root:GetSize()
    local ok = w == T.HUD_WIDTH and h == T.HUD_HEIGHT and T.HUD_WIDTH == Pockets.UI.PHUI.PH_HUD_WIDTH_EXPANDED
        and T.OUTER_INSET * 2 + T.HEADER_HEIGHT + T.CONTENT_HEIGHT == T.HUD_HEIGHT
    return ok, ok and "OK" or string.format("got %sx%s", tostring(w), tostring(h))
end)

TestRunner:Register("Glance: header buttons are Search, Log, Expand (+), header-button size, right-aligned", function()
    Reset()
    local header = Shell.frame.glance.header
    local icons = header.icons
    local ok = #icons == 3 and header.iconButton == icons[1] and header.lootButton == icons[2]
        and header.plusButton == icons[3]
        and icons[1]:GetWidth() == T.HEADER_BUTTON and icons[3]:GetPoint() == "RIGHT"
    return ok, ok and "OK" or "unexpected header buttons"
end)

TestRunner:Register("Glance: no 'Recent' label and no '>>' button", function()
    Reset()
    local texts = CollectTexts(Shell.frame.glance)
    local hasRecent = false
    for _, text in ipairs(texts) do
        if tostring(text):lower():find("recent", 1, true) then hasRecent = true end
    end
    local ok = not hasRecent and Shell.frame.glance.recentStrip.moreButton == nil
    return ok, ok and "OK" or "found a Recent label or a >> button"
end)

TestRunner:Register("Glance: five Recent slots from the shared tokens", function()
    local strip = Shell.frame.glance.recentStrip
    local slots = math.floor((strip._width + strip._gap) / (strip._iconSize + strip._gap))
    local ok = slots == 5 and strip._iconSize == T.ICON_RECENT and strip._gap == T.ICON_GAP
    return ok, ok and "OK" or string.format("slots=%d", slots)
end)

TestRunner:Register("Glance: capacity text handles empty/unknown totals without dividing", function()
    local F = PocketsGlance.FormatCapacity
    local ok = F(33, 44) == "33 / 44" and F(0, 0) == "\226\128\148 / \226\128\148"
        and F(nil, nil) == "\226\128\148 / \226\128\148" and F(0, 20) == "0 / 20" and F(20, 20) == "20 / 20"
    return ok, ok and "OK" or "bad FormatCapacity"
end)

TestRunner:Register("Glance: ETA header text - value only when filling with confidence, dash otherwise", function()
    local E = PocketsGlance.FormatEta
    local v1, s1 = E(false, true, true, "18m")
    local v2, s2 = E(false, true, false, "18m")
    local v3, s3 = E(false, false, true, nil)
    local v4, s4 = E(true, false, true, nil)
    local dash = "\226\128\148"
    local ok = v1 == "18m" and s1 == "to full" and v2 == dash and s2 == "to full"
        and v3 == dash and s3 == "to full" and v4 == "Full" and s4 == ""
    return ok, ok and "OK" or "bad FormatEta"
end)

TestRunner:Register("Glance: capacity colors switch at 70% and 90%", function()
    local good = Layout:GetCapacityColor(0.69)
    local warn = Layout:GetCapacityColor(0.70)
    local warnHi = Layout:GetCapacityColor(0.89)
    local bad = Layout:GetCapacityColor(0.90)
    local C = Pockets.UI.PHUI.Colors
    local ok = good.g == C.ACCENT_GOOD[2] and warn.g == C.ACCENT_WARNING[2]
        and warnHi.g == C.ACCENT_WARNING[2] and bad.g == C.ACCENT_BAD[2]
    return ok, ok and "OK" or "bad thresholds"
end)

TestRunner:Register("Glance: fill fraction clamps to 0..1", function()
    local C = GlanceFrame.ClampFraction
    local ok = C(-1) == 0 and C(2) == 1 and C(0.5) == 0.5 and C(nil) == 0 and C(0 / 0) == 0
    return ok, ok and "OK" or "bad clamp"
end)

TestRunner:Register("Glance: tab width is content-sized within the min/max tokens", function()
    local W = GlanceFrame.ComputeTabWidth
    local ok = W(0) == T.TAB_MIN_WIDTH and W(1000) == T.TAB_MAX_WIDTH
        and W(70) > T.TAB_MIN_WIDTH and W(70) < T.TAB_MAX_WIDTH
    return ok, ok and "OK" or "bad ComputeTabWidth"
end)

TestRunner:Register("BagAPI: bag item class/subclass -> specialized class", function()
    local C = BagAPI.ClassifyBagItem
    local ok = C(11, 2) == "ammo" and C(11, 3) == "ammo" and C(1, 0) == nil
        and C(1, 1) == "soul" and C(1, 2) == "herbs" and C(1, 3) == "enchanting"
        and C(1, 6) == "mining" and C(1, 7) == "skinning" and C(2, 0) == nil and C(nil, nil) == nil
    return ok, ok and "OK" or "bad ClassifyBagItem"
end)

TestRunner:Register("BagAPI: main capacity excludes ammo/reagent/profession bags, each class pooled once", function()
    local r = BagAPI:ClassifyCapacity({
        { slotCount = 16, usedSlots = 10 },                                  -- backpack
        { slotCount = 10, usedSlots = 4 },                                   -- plain bag
        { bagClass = "ammo", slotCount = 18, usedSlots = 3, bagID = 3 },
        { bagClass = "reagents", slotCount = 36, usedSlots = 20, bagID = 5 },
        { bagClass = "herbs", slotCount = 20, usedSlots = 5, bagID = 2 },
        { bagClass = "herbs", slotCount = 10, usedSlots = 1, bagID = 4 },    -- second herb bag merges
    })
    local ok = r.general.total == 26 and r.general.used == 14
        and r.ammo.total == 18 and r.ammo.used == 3
        and r.specialized.reagents.total == 36 and r.specialized.reagents.used == 20
        and r.specialized.herbs.total == 30 and r.specialized.herbs.used == 6
        and #r.specialized.herbs.bagIDs == 2
    return ok, ok and "OK" or "bad mixed-bag classification"
end)

TestRunner:Register("BagAPI: no equipped specialized bags -> no specialized pools; empty inventory is 0 used", function()
    local r = BagAPI:ClassifyCapacity({ { slotCount = 16, usedSlots = 0 } })
    local ok = next(r.specialized) == nil and r.general.total == 16 and r.general.used == 0 and r.ammo.total == 0
    return ok, ok and "OK" or "unexpected specialized pools"
end)

TestRunner:Register("Glance: tab models keep stable order, labels and 'used / total'", function()
    local models = PocketsGlance.BuildTabModels({
        { class = "ammo", label = "Ammo", used = 3, total = 18, utilization = 3 / 18, texture = 1 },
        { class = "reagents", label = "Reagents", used = 36, total = 36, utilization = 1, texture = 2 },
    }, function() return { r = 1, g = 1, b = 1 } end)
    local ok = #models == 2 and models[1].label == "Ammo" and models[1].value == "3 / 18"
        and models[2].label == "Reagents" and models[2].fraction == 1
        and #PocketsGlance.BuildTabModels(nil, function() end) == 0
    return ok, ok and "OK" or "bad tab models"
end)

TestRunner:Register("Glance: tabs appear/disappear without changing the HUD's size or anchor", function()
    Reset()
    local InventoryState = Pockets.Services.InventoryState
    local original = InventoryState.GetSpecializedCapacities
    local glance = Shell.frame.glance
    local w0, h0 = Shell.root:GetSize()
    local p0, _, rp0, x0, y0 = Shell.root:GetPoint()

    local function counts() return glance.tabCount end
    InventoryState.GetSpecializedCapacities = function()
        return {
            { class = "ammo", label = "Ammo", used = 3, total = 18, utilization = 3 / 18, texture = 1 },
            { class = "reagents", label = "Reagents", used = 5, total = 36, utilization = 5 / 36, texture = 2 },
        }
    end
    PocketsGlance:Render(glance)
    local withTabs = counts() == 2 and glance.tabs[1]:IsShown() and glance.tabs[2]:IsShown() and not glance.tabs[3]:IsShown()
    local w1, h1 = Shell.root:GetSize()
    local p1, _, rp1, x1, y1 = Shell.root:GetPoint()

    InventoryState.GetSpecializedCapacities = function() return {} end
    PocketsGlance:Render(glance)
    local noTabs = counts() == 0 and not glance.tabs[1]:IsShown()
    local w2, h2 = Shell.root:GetSize()

    InventoryState.GetSpecializedCapacities = original
    PocketsGlance:Render(glance)

    local stable = w0 == w1 and h0 == h1 and w1 == w2 and h1 == h2
        and p0 == p1 and rp0 == rp1 and x0 == x1 and y0 == y1
    local ok = withTabs and noTabs and stable
    return ok, ok and "OK" or string.format("withTabs=%s noTabs=%s stable=%s",
        tostring(withTabs), tostring(noTabs), tostring(stable))
end)

TestRunner:Register("Glance: clicking the bag group or a tab opens All Items directly", function()
    Reset()
    Shell.frame.glance.bagRow:Click()
    local fromBag = Shell:GetState() == Shell.STATE.ALL
    Reset()
    local tab = Shell.frame.glance.tabs[1]
    tab:Show()
    tab:Click()
    local fromTab = Shell:GetState() == Shell.STATE.ALL
    Reset()
    local ok = fromBag and fromTab
    return ok, ok and "OK" or string.format("fromBag=%s fromTab=%s", tostring(fromBag), tostring(fromTab))
end)
