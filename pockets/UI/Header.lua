--[[
    UI/Header.lua - Compact "title (subtitle)  [icon] [icon]" header row
    (Glance's "pockets (8m) [search] [+]" row today; generic enough to
    reuse anywhere else Pockets needs a lightweight labeled header with a
    dynamic subtitle and trailing icon actions).

    Deliberately minimal - no back/close buttons, no chrome beyond the
    icon buttons' own. Both width and height are required opts and set
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

-- opts.icons: ordered LEFT-to-right as they read (icons[1] sits closest
-- to the title/subtitle text, icons[#icons] is flush against the
-- header's own right edge) - anchored right-to-left internally so
-- adding/removing a trailing icon never shifts anything except the
-- icons to its left. Each icon entry: { size, texture (OR glyph, e.g.
-- "+", mutually exclusive with texture - no native WoW texture for a
-- plain "+", matching the same text-glyph convention Shell's own
-- expanded header already uses for its own +/All Items button),
-- tooltipText, onClick }.
function Header:Create(parent, opts)
    opts = opts or {}

    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(opts.width, opts.height)

    header.titleText = PHUI.CreateLabel(header, opts.titleStyle or "muted", opts.title, opts.titleFont or PHUI.Fonts.SMALL)
    header.titleText:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.titleText:SetJustifyH("LEFT")

    -- A separate FontString (not baked into titleText's own SetText) so
    -- callers can update it independently every render (e.g. Glance's
    -- "(8m)"/"(Full)" time-to-full) without re-specifying the title.
    header.subtitleText = PHUI.CreateLabel(header, opts.subtitleStyle or "muted", nil, opts.subtitleFont or PHUI.Fonts.SMALL)
    header.subtitleText:SetPoint("LEFT", header.titleText, "RIGHT", opts.titleGap or 4, 0)
    header.subtitleText:SetJustifyH("LEFT")

    -- Subtitle never runs under the trailing icons: bounded by the
    -- leftmost icon and clipped (not overlapped) if it ever can't fit.
    header.subtitleText:SetWordWrap(false)

    function header:SetSubtitle(text)
        self.subtitleText:SetText(text or "")
    end

    header.icons = {}
    local iconGap = opts.iconGap or 4
    local previousAnchor
    for i = #(opts.icons or {}), 1, -1 do
        local iconOpts = opts.icons[i]
        local button
        if iconOpts.native then
            -- Real Blizzard texture, no backdrop/box (matches pH's own
            -- minMaxBtn/historyBtn - see PHUI.CreateNativeIconButton).
            button = PHUI.CreateNativeIconButton(header, iconOpts.size, iconOpts.texture, {
                tooltipText = iconOpts.tooltipText,
                onClick = iconOpts.onClick,
            })
        else
            button = PHUI.CreateIconButton(header, iconOpts.size, iconOpts.texture, {
                tooltipText = iconOpts.tooltipText,
                onClick = iconOpts.onClick,
            })
            if iconOpts.glyph then
                button.glyph = PHUI.CreateLabel(button, iconOpts.glyphStyle or "primary", iconOpts.glyph, iconOpts.glyphFont or PHUI.Fonts.SMALL)
                button.glyph:SetPoint("CENTER", 0, 0)
            end
        end
        if previousAnchor then
            button:SetPoint("RIGHT", previousAnchor, "LEFT", -iconGap, 0)
        else
            button:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        end
        header.icons[i] = button
        previousAnchor = button
    end
    -- header.iconButton always names the FIRST/leftmost icon (Glance's
    -- Search, the one pre-existing callers/tests already reference by
    -- this name) regardless of how many icons follow it.
    header.iconButton = header.icons[1]
    if header.icons[1] then
        header.subtitleText:SetPoint("RIGHT", header.icons[1], "LEFT", -iconGap, 0)
    end

    return header
end
