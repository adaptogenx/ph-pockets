--[[
    UI/CategoryHeader.lua - Full-width collapsible category header for
    Full Inventory ("<Name> (<count>)" left, chevron right, no icon -
    Full Inventory redesign).

    ONE shared component for every category (including Recent) so header
    shape/behavior is identical by construction, not by convention. The
    chevron is a real Blizzard texture (the standard +/- expand/collapse
    buttons, PHUI.Icons.PLUS/MINUS), NOT a text glyph: the UI font has no
    triangle glyphs (U+25B8/U+25BE rendered as empty boxes on Forever).
    Collapsed/expanded use same-sized textures so they never visibly
    differ in size. The whole header, not just the chevron, is the click
    target (it's a real Button).
]]

local _, Pockets = ...

Pockets.UI.CategoryHeader = Pockets.UI.CategoryHeader or {}
local CategoryHeader = Pockets.UI.CategoryHeader
local PHUI = Pockets.UI.PHUI

local CHEVRON_SIZE = 14

-- opts: width, height (both required, same reasoning as MetricRow -
-- resolved once at creation, never inferred later), onClick(categoryID).
function CategoryHeader:Create(parent, opts)
    opts = opts or {}

    local header = CreateFrame("Button", nil, parent)
    header:SetSize(opts.width, opts.height)
    header.isPocketsCategoryHeader = true -- marker: "built by this ONE component"

    header.chevron = header:CreateTexture(nil, "OVERLAY")
    header.chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
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
        self.chevron:SetTexture(self.collapsed and PHUI.Icons.PLUS or PHUI.Icons.MINUS)
    end

    if opts.onClick then
        header:SetScript("OnClick", opts.onClick)
    end

    header:SetCollapsed(false)

    return header
end
