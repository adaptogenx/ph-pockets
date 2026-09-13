--[[
    UI/RecentItemStrip.lua - Compact horizontal strip of the most
    recently acquired unique items (Glance's Recent row).

    Reuses UI/ItemButtonPool.lua for the actual item buttons - same real
    secure buttons Category List/Grid/Search use, so tooltip/click/drag/
    split/quantity all work identically here with no second interaction
    implementation (UI_RULES.md #10). Each strip gets its own dedicated
    pool key (a private child frame, not shared with Grid/List/Search's
    own pool anchors) so a strip-sized (smaller) button can never get
    recycled back into a Grid/List render still shaped like a Recent icon
    - the same reasoning already documented for categoryListPoolAnchor/
    searchPoolAnchor in UI/Shell.lua.

    Width/height are required opts and set explicitly at creation (see
    UI/MetricRow.lua's header comment for why - same anchor-resolution
    hardening applies here).
]]

local _, Pockets = ...

Pockets.UI.RecentItemStrip = Pockets.UI.RecentItemStrip or {}
local RecentItemStrip = Pockets.UI.RecentItemStrip

-- opts: width (required), iconSize (required), gap (default 4).
function RecentItemStrip:Create(parent, opts)
    opts = opts or {}
    local iconSize = opts.iconSize or 20
    local gap = opts.gap or 4
    local width = opts.width or iconSize

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(width, iconSize)

    strip.poolAnchor = CreateFrame("Frame", nil, strip)
    strip._iconSize = iconSize
    strip._gap = gap
    strip._width = width

    -- Stock ItemButtonTemplate's NormalTexture/PushedTexture (the
    -- decorative slot-frame border) carry a FIXED absolute size baked
    -- into the Blizzard template - they do NOT shrink when the button's
    -- own frame is resized smaller via SetSize. At Category Grid's
    -- native 40px button size that oversized art just barely overhangs
    -- the visible slot; shrunk to Recent's compact iconSize it overhangs
    -- dramatically, reading as an oversized icon that bleeds past its
    -- intended padding (matches the LAYOUT/DENSITY and BAG ICON specs'
    -- "no double frame" intent, and mirrors Shell.lua's
    -- CreateCategoryListRow, which neutralizes the exact same texture
    -- for the same reason on List rows). SetColorTexture(0,0,0,0) is
    -- what actually works on this client - SetTexture(nil)/
    -- SetNormalTexture(nil) both throw. pcall'd so any further
    -- texture-API surprise here can never break a render.
    local function NeutralizeSlotChrome(button)
        pcall(function()
            local normalTexture = button.GetNormalTexture and button:GetNormalTexture()
            if normalTexture then
                normalTexture:SetColorTexture(0, 0, 0, 0)
            end
            local pushedTexture = button.GetPushedTexture and button:GetPushedTexture()
            if pushedTexture then
                pushedTexture:SetColorTexture(0, 0, 0, 0)
            end
        end)
        if button.icon then
            button.icon:ClearAllPoints()
            button.icon:SetAllPoints(button)
        end
        if button.IconBorder then
            button.IconBorder:ClearAllPoints()
            button.IconBorder:SetAllPoints(button)
        end
    end

    -- items: newest-first, unique-by-itemID records already resolved to
    -- current carried quantity (Pockets.API.GetAggregatedCategoryItems
    -- with Constants.CATEGORY.RECENT - no second bag scan here). Clamps
    -- to however many actually fit at this strip's own width rather than
    -- a hard-coded count (RECENT ITEMS + WIDTH spec) - returns the
    -- number actually shown.
    function strip:SetItems(items)
        local pool = Pockets.UI.ItemButtonPool
        pool:ReleaseAll(self.poolAnchor)

        local maxFit = math.max(0, math.floor((self._width + self._gap) / (self._iconSize + self._gap)))
        local count = math.min(#items, maxFit)

        for i = 1, count do
            local button = pool:Acquire(self.poolAnchor)
            button:SetSize(self._iconSize, self._iconSize)
            NeutralizeSlotChrome(button)
            pool:Configure(button, items[i])
            button:ClearAllPoints()
            button:SetPoint("LEFT", self, "LEFT", (i - 1) * (self._iconSize + self._gap), 0)
            button:Show()
        end

        return count
    end

    return strip
end
