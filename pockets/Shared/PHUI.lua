--[[
    Shared/PHUI.lua - Generic pH-brand UI primitives (colors, fonts,
    backdrops, panel/button/label factories).

    This library is intentionally addon-agnostic: it reads no Pockets
    namespace and writes only to _G.PHUI, guarded by version so a future
    second copy (e.g. loaded by the pH addon itself) doesn't reinitialize
    or fight over shared frames. Values below are copied from pH's actual
    rendered compact HUD (ph/ph/UI_HUD.lua), not pH's older/drifted brand
    color module, since UI_HUD.lua is what's actually on screen.

    Pockets-specific geometry (HUD width, flyout grid, etc.) does NOT
    belong here - that stays in Pockets/Constants.lua and UI/Layout.lua.
    This file only owns generic, reusable visual primitives.
]]

if _G.PHUI and (_G.PHUI.version or 0) >= 1 then
    return
end

local PHUI = _G.PHUI or {}
PHUI.version = 1
_G.PHUI = PHUI

--------------------------------------------------
-- Colors (ph/ph/UI_HUD.lua:42-61)
--------------------------------------------------
PHUI.Colors = {
    TEXT_PRIMARY = { 0.86, 0.82, 0.70 },
    TEXT_MUTED = { 0.62, 0.58, 0.50 },
    TEXT_DISABLED = { 0.45, 0.42, 0.38 },

    ACCENT_GOOD = { 0.25, 0.78, 0.42 },
    ACCENT_NEUTRAL = { 0.55, 0.70, 0.55 },
    ACCENT_BAD = { 0.85, 0.38, 0.32 },
    ACCENT_WARNING = { 0.90, 0.65, 0.20 },
    ACCENT_GOLD = { 1.00, 0.82, 0.00 },

    BG_DARK = { 0.08, 0.07, 0.06, 0.85 },
    BG_PARCHMENT = { 0.18, 0.16, 0.13, 0.85 },
    BORDER_BRONZE = { 0.52, 0.42, 0.28 },

    HOVER = { 0.22, 0.20, 0.17, 0.60 },
    SELECTED = { 0.35, 0.32, 0.26, 0.75 },
    DIVIDER = { 0.28, 0.25, 0.22, 0.50 },
}

--------------------------------------------------
-- Fonts (ph/ph/UI_HUD.lua: stock templates throughout; FRIZQT spec at
-- UI_HUD.lua:1355-1358 for header/glyph buttons)
--------------------------------------------------
PHUI.Fonts = {
    NORMAL = "GameFontNormal",
    SMALL = "GameFontNormalSmall",
    LARGE = "GameFontNormalLarge",
    HEADER = { "Fonts\\FRIZQT__.TTF", 12, "" },
    GLYPH_OUTLINE = { "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" },
}

--------------------------------------------------
-- Generic spacing tokens (not bag-specific geometry - that stays in
-- Pockets/Constants.lua's LAYOUT table)
--------------------------------------------------
PHUI.Spacing = {
    PADDING = 12,
    ICON_GAP = 2,
    PANEL_PADDING = 8,
}

--------------------------------------------------
-- Backdrops (ph/ph/UI_HUD.lua:825-830 - the dominant panel pattern used
-- throughout pH's UI)
--------------------------------------------------
PHUI.Backdrops = {
    PANEL = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
}

--------------------------------------------------
-- Backdrop application
--------------------------------------------------

-- Applies the shared panel backdrop (or opts.backdrop override) plus
-- bg/border colors (defaulting to BG_PARCHMENT/BORDER_BRONZE, pH's HUD
-- panel treatment) to any BackdropTemplate-mixin frame.
function PHUI.ApplyBackdrop(frame, opts)
    opts = opts or {}
    local backdrop = opts.backdrop or PHUI.Backdrops.PANEL
    local bgColor = opts.bgColor or PHUI.Colors.BG_PARCHMENT
    local borderColor = opts.borderColor or PHUI.Colors.BORDER_BRONZE

    frame:SetBackdrop(backdrop)
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], opts.bgAlpha or bgColor[4] or 1)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], opts.borderAlpha or borderColor[4] or 1)
end

-- Creates a plain themed panel frame.
function PHUI.CreatePanel(parent, width, height, opts)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if width and height then
        panel:SetSize(width, height)
    end
    PHUI.ApplyBackdrop(panel, opts)
    return panel
end

--------------------------------------------------
-- Text styling
--------------------------------------------------

local TEXT_STYLE_COLOR = {
    primary = "TEXT_PRIMARY",
    muted = "TEXT_MUTED",
    disabled = "TEXT_DISABLED",
    good = "ACCENT_GOOD",
    bad = "ACCENT_BAD",
    warning = "ACCENT_WARNING",
    gold = "ACCENT_GOLD",
}

local TEXT_STYLE_FONT = {
    primary = PHUI.Fonts.NORMAL,
    muted = PHUI.Fonts.SMALL,
    disabled = PHUI.Fonts.SMALL,
    good = PHUI.Fonts.NORMAL,
    bad = PHUI.Fonts.NORMAL,
    warning = PHUI.Fonts.NORMAL,
    gold = PHUI.Fonts.NORMAL,
}

-- Applies a named text style (font template + color) to an existing
-- FontString. styleName: "primary" | "muted" | "disabled" | "good" |
-- "bad" | "warning" | "gold".
function PHUI.ApplyTextStyle(fontString, styleName)
    local colorKey = TEXT_STYLE_COLOR[styleName] or TEXT_STYLE_COLOR.primary
    local color = PHUI.Colors[colorKey]
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    return fontString
end

-- Creates a FontString with a named style applied. Font template is
-- fixed per style (see TEXT_STYLE_FONT); pass fontTemplate to override.
function PHUI.CreateLabel(parent, styleName, text, fontTemplate)
    local template = fontTemplate or TEXT_STYLE_FONT[styleName] or PHUI.Fonts.NORMAL
    local fontString = parent:CreateFontString(nil, "OVERLAY", template)
    PHUI.ApplyTextStyle(fontString, styleName)
    if text then
        fontString:SetText(text)
    end
    return fontString
end

-- Thin wrapper over Blizzard's stock close-button template so every PHUI
-- panel gets the same close-button treatment instead of each caller
-- re-declaring "UIPanelCloseButton" + a size by hand.
function PHUI.CreateCloseButton(parent, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    button:SetSize(opts.size or 20, opts.size or 20)
    if opts.onClick then
        button:SetScript("OnClick", opts.onClick)
    end
    return button
end

--------------------------------------------------
-- Disabled-state helper (ph/ph/UI_HUD.lua:1049 - overflow menu items,
-- alpha 0.45 when disabled)
--------------------------------------------------
function PHUI.SetDisabled(frame, isDisabled)
    frame.isActionDisabled = isDisabled and true or false
    frame:SetAlpha(frame.isActionDisabled and 0.45 or 1.0)
end

--------------------------------------------------
-- Buttons
--------------------------------------------------

-- Chrome text button: backdrop panel + centered label + hover
-- border-color highlight to ACCENT_GOLD (matches pH's stop/primary
-- button treatment, UI_HUD.lua:1124-1139).
function PHUI.CreateButton(parent, width, height, text, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    PHUI.ApplyBackdrop(button, opts)

    button.text = PHUI.CreateLabel(button, opts.textStyle or "primary", text, PHUI.Fonts.SMALL)
    button.text:SetPoint("CENTER", 0, 0)

    local borderColor = opts.borderColor or PHUI.Colors.BORDER_BRONZE
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(PHUI.Colors.ACCENT_GOLD[1], PHUI.Colors.ACCENT_GOLD[2], PHUI.Colors.ACCENT_GOLD[3], 1.0)
        if opts.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltipText)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1.0)
        if opts.tooltipText then
            GameTooltip:Hide()
        end
    end)
    if opts.onClick then
        button:SetScript("OnClick", function(self)
            if not self.isActionDisabled then
                opts.onClick(self)
            end
        end)
    end

    return button
end

-- Chrome icon button: backdrop panel + centered icon (trimmed with the
-- 0.08/0.92 texcoord inset pH uses to crop default icon padding) + hover
-- border-color highlight + optional tooltip/disabled support. Mirrors
-- pH's CreateMenuIconButton (UI_HUD.lua:1323-1379).
function PHUI.CreateIconButton(parent, size, texturePath, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(size, size)
    PHUI.ApplyBackdrop(button, opts)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    if texturePath then
        button.icon:SetTexture(texturePath)
    end
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local borderColor = opts.borderColor or PHUI.Colors.BORDER_BRONZE
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(PHUI.Colors.ACCENT_GOLD[1], PHUI.Colors.ACCENT_GOLD[2], PHUI.Colors.ACCENT_GOLD[3], 1.0)
        if opts.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltipText)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1.0)
        if opts.tooltipText then
            GameTooltip:Hide()
        end
    end)
    if opts.onClick then
        button:SetScript("OnClick", function(self)
            if not self.isActionDisabled then
                opts.onClick(self)
            end
        end)
    end

    return button
end
