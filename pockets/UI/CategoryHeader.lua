--[[
    UI/CategoryHeader.lua - Full-width collapsible category header for
    Full Inventory ("<Name> (<count>)" left, chevron right, no icon -
    Full Inventory redesign).

    ONE shared component for every category (including Recent) so header
    shape/behavior is identical by construction, not by convention. The
    chevron is a small FontString ("\226\150\184" / "\226\150\190" - the
    triangle glyphs U+25B8/U+25BE, not the letter "v") - both read as an
    arrow at a glance and share the same glyph metrics, so collapsed/
    expanded never visibly differ in size the way ">"/"v" did. The whole
    header, not just the chevron, is the click target (it's a real Button).
]]

local _, Pockets = ...

Pockets.UI.CategoryHeader = Pockets.UI.CategoryHeader or {}
local CategoryHeader = Pockets.UI.CategoryHeader
local PHUI = Pockets.UI.PHUI

local CHEVRON_COLLAPSED = "\226\150\184" -- "▸"
local CHEVRON_EXPANDED = "\226\150\190" -- "▾"

-- opts: width, height (both required, same reasoning as MetricRow -
-- resolved once at creation, never inferred later), onClick(categoryID).
function CategoryHeader:Create(parent, opts)
    opts = opts or {}

    local header = CreateFrame("Button", nil, parent)
    header:SetSize(opts.width, opts.height)
    header.isPocketsCategoryHeader = true -- marker: "built by this ONE component"

    header.chevron = header:CreateFontString(nil, "OVERLAY")
    header.chevron:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    local mutedColor = PHUI.Colors.TEXT_MUTED
    header.chevron:SetTextColor(mutedColor[1], mutedColor[2], mutedColor[3], mutedColor[4] or 1)
    header.chevron:SetWidth(Pockets.Constants.LAYOUT.LIST_ROW_CHEVRON_WIDTH)
    header.chevron:SetJustifyH("CENTER")
    header.chevron:SetPoint("RIGHT", header, "RIGHT", -Pockets.Constants.LAYOUT.LIST_ROW_PADDING, 0)

    header.label = PHUI.CreateLabel(header, "primary", nil, PHUI.Fonts.SMALL)
    header.label:SetPoint("LEFT", header, "LEFT", Pockets.Constants.LAYOUT.LIST_ROW_PADDING, 0)
    header.label:SetPoint("RIGHT", header.chevron, "LEFT", -Pockets.Constants.LAYOUT.LIST_ROW_GAP, 0)
    header.label:SetJustifyH("LEFT")
    header.label:SetWordWrap(false)

    header:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    function header:SetLabel(name, count)
        self.label:SetText(string.format("%s (%d)", name, count))
    end

    function header:SetCollapsed(collapsed)
        self.collapsed = collapsed and true or false
        self.chevron:SetText(self.collapsed and CHEVRON_COLLAPSED or CHEVRON_EXPANDED)
    end

    if opts.onClick then
        header:SetScript("OnClick", opts.onClick)
    end

    header:SetCollapsed(false)

    return header
end
