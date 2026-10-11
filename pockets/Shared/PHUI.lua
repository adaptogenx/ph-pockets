--[[
    Shared/PHUI.lua - Generic pH-brand UI primitives (colors, fonts,
    backdrops, panel/button/label factories).

    Lives entirely inside Pockets' own namespace (Pockets.UI.PHUI) - NOT
    published to any cross-addon global (no _G.PHUI). Pockets and pH are
    separate installed addons that both run in WoW's single shared Lua
    global environment, so a file that wrote to _G.PHUI here would be
    silently visible to - and silently overridden by - pH's own separate
    copy of a same-named file, in whichever load order the two addons
    happen to land in. That already caused one real bug (a Pockets-only
    addition to this file went missing whenever pH's copy loaded first).
    This is meant to become a genuinely separate, published shared UI
    library later; until then it's proven out here, Pockets-local only,
    like every other Pockets module. Values below are copied from pH's
    actual rendered compact HUD (ph/ph/UI_HUD.lua), not pH's older/
    drifted brand color module, since UI_HUD.lua is what's actually on
    screen.

    Pockets-specific geometry (HUD width, flyout grid, etc.) does NOT
    belong here - that stays in Pockets/Constants.lua and UI/Layout.lua.
    This file only owns generic, reusable visual primitives.
]]

local _, Pockets = ...

Pockets.UI.PHUI = Pockets.UI.PHUI or {}
local PHUI = Pockets.UI.PHUI

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
    -- Two distinct default icon sizes, BOTH verified against pH's real,
    -- installed UI_HUD.lua (not guessed) - conflating them, or picking a
    -- number that merely "looks about right," is what caused Glance's
    -- metric-row icons to render visibly larger than pH's own equivalent
    -- icons side-by-side, and separately caused Glance's header "+" to
    -- mismatch Shell's own +/back/close buttons. Every UI pass must
    -- reuse ONE of these two, never invent or eyeball a third:
    --   ICON_SIZE - a PLAIN icon with no button chrome, sitting directly
    --     on a panel surface (Glance's Bag/Gold/Ammo metric-row icons).
    --     ph/UI_HUD.lua:1238 - micro-bar metric-tile icon, "12px for
    --     ultra-compact" (verbatim comment in pH's own source).
    ICON_SIZE = 12,
    --   ICON_BUTTON_SIZE - a bordered, clickable CreateIconButton/
    --     CreateCloseButton (back/close/+/Search - anything with a
    --     backdrop+border and a hover highlight). ph/UI_HUD.lua:110 -
    --     "local ICON_SIZE = 20 -- Match stop button height (20px)",
    --     pH's own button-icon size (minMaxBtn/historyBtn/overflowBtn).
    --     This is the established size already used throughout Shell's
    --     expanded header (back/close/+) - Glance's header buttons must
    --     match it too, not the smaller plain-icon size.
    -- Pockets/Constants.lua's GLANCE_*/SHELL_HEADER_* size constants are
    -- meant to equal these (Constants.lua loads before this file, so it
    -- can't read them directly at load time - see the "Must match"
    -- comments on those constants).
    ICON_BUTTON_SIZE = 20,
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
    -- Scaled-down border for small (~20px) icon buttons, verified against
    -- pH's own overflowBtn (ph/UI_HUD.lua:996-1000). PANEL's edgeSize=12/
    -- insets=3 is sized for full HUD panels - on a 20px button it eats
    -- most of the icon's usable space, making the glyph look shrunk next
    -- to pH's real buttons even when the outer button size matches.
    ICON_BUTTON = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
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
-- pH's own close button (ph/UI_History.lua:156-157) never calls SetSize
-- at all - it renders at UIPanelCloseButton's native/default size (32px).
-- Forcing this template down to a small size (it was 20px here before)
-- doesn't scale cleanly - the template's border/glow art is fixed-inset,
-- not proportional, so a forced-small button visibly doesn't match pH's
-- real X even though it's the same template. Default to that native
-- size unless a caller has a real reason to override it.
PHUI.NATIVE_CLOSE_BUTTON_SIZE = 32

-- pH's own collapsed HUD frame width (ph/UI_HUD.lua:2629/2834 -
-- hudFrame:SetWidth(266)). Pockets' own Glance stays intentionally
-- narrower (sized to its actual content, not a pH clone), but any
-- Pockets view meant to visually align/match pH's real HUD footprint
-- (Shell's expanded Search/Menu/Category/All) should use this exact
-- value, not an independently-chosen one.
PHUI.PH_HUD_WIDTH = 266

-- WoW Forever's UIPanelCloseButton art renders visibly larger than
-- Classic's at the same size (user report: X too big), so it gets a
-- smaller box there. Classic keeps pH's native 32.
PHUI.FOREVER_CLOSE_BUTTON_SIZE = 24

function PHUI.CreateCloseButton(parent, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    local size = opts.size or PHUI.NATIVE_CLOSE_BUTTON_SIZE
    local ClientAPI = Pockets.Adapters.ClientAPI
    if ClientAPI and ClientAPI:IsForever() then
        size = PHUI.FOREVER_CLOSE_BUTTON_SIZE
    end
    button:SetSize(size, size)
    if opts.onClick then
        button:SetScript("OnClick", opts.onClick)
    end
    return button
end

--------------------------------------------------
-- Native icon presentation: a plain texture meant to sit directly on a
-- panel surface (Glance's bag/ammo icons) - never wrapped in an
-- ItemButton/bordered-slot treatment. Shares the same 0.08/0.92 texcoord
-- inset CreateIconButton's icon uses, since that's what crops the black
-- padding baked into most stock WoW icon art. Pass insetTexCoord = false
-- for art (e.g. the backpack button texture) that's already clean at the
-- edges.
--------------------------------------------------
function PHUI.CreateNativeIcon(parent, size, texture, opts)
    opts = opts or {}
    local icon = parent:CreateTexture(nil, opts.layer or "ARTWORK")
    icon:SetSize(size, size)
    if texture then
        icon:SetTexture(texture)
    end
    if opts.insetTexCoord ~= false then
        local inset = opts.texCoordInset or 0.08
        icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
    end
    return icon
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
    PHUI.ApplyBackdrop(button, { backdrop = opts.backdrop or PHUI.Backdrops.ICON_BUTTON,
        bgColor = opts.bgColor, borderColor = opts.borderColor, bgAlpha = opts.bgAlpha })

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

--------------------------------------------------
-- Icon texture paths (ph/UI_HUD.lua:103-108) - real Blizzard icon art
-- pH uses directly. Any Pockets element meaning the same thing must use
-- the exact same texture, never a font-drawn character standing in for
-- it - a font glyph never visually matches Blizzard's own icon art (the
-- "+" mismatch this table exists to fix).
--------------------------------------------------
PHUI.Icons = {
    PLUS = "Interface\\Buttons\\UI-PlusButton-Up",
    MINUS = "Interface\\Buttons\\UI-MinusButton-Up",
    -- Loot Log entry point. Pockets-only affordance (pH's History button
    -- is a quest-log BOOK, deliberately a different thing), so a stock
    -- Blizzard scroll item icon; boxed via CreateIconButton like Search
    -- because item icon art carries baked-in padding.
    SCROLL = "Interface\\Icons\\INV_Scroll_03",
}

--- Borderless icon button: a plain Blizzard texture with no backdrop/box
--- chrome, matching pH's own minMaxBtn/historyBtn (ph/UI_HUD.lua:956-990)
--- - those have zero SetBackdrop call; their "border" is baked into the
--- texture art itself. Use this (not CreateIconButton) for any icon that
--- has a real Blizzard texture equivalent (e.g. PHUI.Icons.PLUS). Keep
--- using CreateIconButton's boxed style only for Pockets-only affordances
--- with no pH element to match (e.g. Search).
function PHUI.CreateNativeIconButton(parent, size, texturePath, opts)
    opts = opts or {}
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:SetNormalTexture(texturePath)
    if opts.pushedTexture then
        button:SetPushedTexture(opts.pushedTexture)
    end
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    if opts.tooltipText then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(opts.tooltipText)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if opts.onClick then
        button:SetScript("OnClick", function(self)
            if not self.isActionDisabled then
                opts.onClick(self)
            end
        end)
    end
    return button
end
