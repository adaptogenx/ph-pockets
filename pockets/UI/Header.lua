--[[
    UI/Header.lua - Compact "title  [icon]" header row (Glance's "pockets
    [search]" row today; generic enough to reuse anywhere else Pockets
    needs a lightweight labeled header with one trailing icon action).

    Deliberately minimal - no back/close buttons, no chrome beyond the
    icon button's own. Both width and height are required opts and set
    explicitly at creation (not left for a later SetText/SetWidth to
    establish) - a frame anchored by a single point needs BOTH dimensions
    known for WoW to resolve its own rect, let alone anything anchored
    off it (see the Glance blank-render bug this pattern was hardened
    against).
]]

local _, Pockets = ...

Pockets.UI.Header = Pockets.UI.Header or {}
local Header = Pockets.UI.Header
local PHUI = Pockets.UI.PHUI

function Header:Create(parent, opts)
    opts = opts or {}

    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(opts.width, opts.height)

    header.titleText = PHUI.CreateLabel(header, opts.titleStyle or "muted", opts.title, opts.titleFont or PHUI.Fonts.SMALL)
    header.titleText:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.titleText:SetJustifyH("LEFT")

    header.iconButton = PHUI.CreateIconButton(header, opts.iconSize, opts.iconTexture, {
        tooltipText = opts.tooltipText,
        onClick = opts.onIconClick,
    })
    header.iconButton:SetPoint("RIGHT", header, "RIGHT", 0, 0)

    return header
end
