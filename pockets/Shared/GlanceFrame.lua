--[[
    Shared/GlanceFrame.lua - Reusable Glance chassis (Forever Glance TDD §3)

    The compact horizontal HUD frame: fixed outer size, a header band
    (title, ETA block, right-aligned icon buttons), one content row built
    from sections/dividers, and a left-edge dock for attached tabs. It owns
    ONLY generic drawing/layout - no Pockets business logic, no dependency
    on the pH addon, no Pockets metrics. A future pH Glance supplies
    different content to the same chassis instead of copying this styling.

    Visual tokens (colors/fonts/backdrops) come from PHUI; the geometry
    tokens below are the chassis' own, in logical pixels at scale 1.
]]

local _, Pockets = ...

Pockets.UI.GlanceFrame = Pockets.UI.GlanceFrame or {}
local GlanceFrame = Pockets.UI.GlanceFrame
local PHUI = Pockets.UI.PHUI

-- Spacing/sizes from the approved Glance mockup (12px horizontal padding,
-- 4px vertical, 20px main icons, 16px tab icons, 6px gaps), at pH's real
-- expanded HUD width so the two HUDs stack flush. Width and header-button
-- size come straight from PHUI.
GlanceFrame.TOKENS = {
    HUD_WIDTH = PHUI.PH_HUD_WIDTH_EXPANDED,
    OUTER_INSET = 3,
    HEADER_HEIGHT = 28,
    CONTENT_HEIGHT = 32,
    PAD_X = PHUI.Spacing.PADDING,
    PAD_Y = PHUI.Spacing.PADDING_Y,
    -- Each side of the 1px divider; total group spacing = SECTION_SPACING.
    SECTION_GAP = math.ceil((PHUI.Spacing.SECTION_SPACING - 1) / 2),
    DIVIDER_WIDTH = 1,
    ICON_MAIN = PHUI.Spacing.ICON_MAIN,
    ICON_RECENT = PHUI.Spacing.ICON_MAIN,
    ICON_GAP = PHUI.Spacing.ICON_SPACING,
    HEADER_BUTTON_W = PHUI.Spacing.HEADER_BUTTON_W,
    HEADER_BUTTON_H = PHUI.Spacing.HEADER_BUTTON_H,
    HEADER_BUTTON_ICON = PHUI.Spacing.HEADER_BUTTON_ICON,
    HEADER_BUTTON_GAP = PHUI.Spacing.ICON_SPACING,
    ETA_GAP = 14,
    ETA_WIDTH = 72,
    TAB_HEIGHT = 34,
    TAB_MIN_WIDTH = 84,
    TAB_MAX_WIDTH = 140,
    TAB_GAP = 6,
    TAB_OFFSET_Y = -1, -- negative: overlaps the HUD bottom border 1px (reads as attached)
    TAB_ICON = PHUI.Spacing.ICON_TAB,
    TAB_BAR_HEIGHT = 3,
    -- Native PortraitFrameTemplate chrome, drawn at CHROME_SCALE so the
    -- ring/bars/portrait shrink together (no seams). Native portrait is
    -- 62x62 at TOPLEFT -5,+7 (measured on the live Forever
    -- ProfessionsFrame), so at 0.6 it spans x -3..34, y +4..-33 here.
    -- The header sits right of it; the content row starts right of it too
    -- and the portrait overlaps both rows.
    -- 0.77 * the native 62px portrait = 48px.
    CHROME_SCALE = 0.77, -- legacy; the portrait below is 48px (0.77 * 62)
    -- Round bag portrait overlapping the panel's top-left corner.
    CHROME_PORTRAIT_SIZE = 48,
    CHROME_PORTRAIT_ICON = 34,
    CHROME_PORTRAIT_X = -4,
    CHROME_PORTRAIT_Y = 5,
    -- One deliberate content start (frame x) right of the portrait (its
    -- right edge is ~44): title, bag count and attached tabs share it.
    CHROME_START_X = 48,
    CHROME_HEADER_TOP = 0,
    CHROME_HEADER_HEIGHT = 32,
    CHROME_CONTENT_HEIGHT = 40,
    CHROME_BUTTON = 24,
    CHROME_BUTTON_GAP = 4,
    CHROME_RIGHT_PAD = 8,
    CHROME_BOTTOM = 6,
}
local T = GlanceFrame.TOKENS
T.HUD_HEIGHT = T.OUTER_INSET * 2 + T.HEADER_HEIGHT + T.CONTENT_HEIGHT
-- Native chrome: 32px header, 40px body, bottom border.
T.CHROME_HUD_HEIGHT = T.CHROME_HEADER_TOP + T.CHROME_HEADER_HEIGHT + T.CHROME_CONTENT_HEIGHT + T.CHROME_BOTTOM

local WHITE = "Interface\\Buttons\\WHITE8X8"

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- Tab width: content-sized, clamped to [TAB_MIN_WIDTH, TAB_MAX_WIDTH].
function GlanceFrame.ComputeTabWidth(textWidth)
    local width = T.PAD_X + T.TAB_ICON + 6 + (textWidth or 0) + T.PAD_X
    return math.max(T.TAB_MIN_WIDTH, math.min(T.TAB_MAX_WIDTH, math.floor(width + 0.5)))
end

-- Clamp a fill fraction to 0..1; nil/NaN -> 0.
function GlanceFrame.ClampFraction(fraction)
    if type(fraction) ~= "number" or fraction ~= fraction then
        return 0
    end
    return math.max(0, math.min(1, fraction))
end

--------------------------------------------------
-- Fill bar (capacity bars: main 4px, tabs 3px)
--------------------------------------------------

function GlanceFrame:CreateBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, height)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    local d = PHUI.Colors.DIVIDER
    bar.track:SetColorTexture(d[1], d[2], d[3], 0.5)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.fill:SetWidth(0.001)
    bar.barWidth = width

    function bar:SetFraction(fraction)
        local f = GlanceFrame.ClampFraction(fraction)
        self.fraction = f
        -- A zero-width texture is invalid on some clients; keep a hair.
        self.fill:SetWidth(math.max(0.001, self.barWidth * f))
        self.fill:SetShown(f > 0)
    end
    function bar:SetColor(r, g, b)
        self.fill:SetColorTexture(r, g, b, 1)
    end
    return bar
end

--------------------------------------------------
-- Native chrome (Forever's PortraitFrameTemplate)
--------------------------------------------------

-- Chrome for the Glance HUD: a themed panel filling `frame` plus a round
-- bag portrait overlapping its top-left corner (the same CircularPortrait
-- the Mini uses). This replaces Forever's PortraitFrameTemplate, whose own
-- border/title pieces sit at very high frame levels and whose ~95px corner
-- art overlaps itself on a frame this short (measured with
-- /pockets debug portrait). Always returns a frame; our own header supplies
-- the title and buttons.
function GlanceFrame:CreateChrome(frame, portrait, alpha)
    local chrome = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    chrome:SetAllPoints(frame)
    chrome:SetFrameLevel(frame:GetFrameLevel())
    chrome:EnableMouse(false)
    PHUI.ApplyBackdrop(chrome, { bgAlpha = alpha })

    local round = Pockets.UI.CircularPortrait:Create(chrome, {
        size = T.CHROME_PORTRAIT_SIZE,
        icon = portrait,
        iconSize = T.CHROME_PORTRAIT_ICON,
        iconTexCoord = { 0, 1, 0, 1 },
        rimColor = PHUI.Colors.BORDER_BRONZE,
    })
    round:SetPoint("TOPLEFT", chrome, "TOPLEFT", T.CHROME_PORTRAIT_X, T.CHROME_PORTRAIT_Y)
    round:SetFrameLevel(chrome:GetFrameLevel() + 5)
    chrome.portrait = round
    return chrome
end

--------------------------------------------------
-- Chassis
--------------------------------------------------

-- Builds the header + content row inside `frame` (an existing, already
-- sized HUD frame) and returns the chassis table.
-- opts: title (string), chrome (bool: native portrait frame - header sits
-- beside the portrait, content row below it), buttons (array,
-- left-to-right as they read: { texture, native?, tooltipText, onClick }).
function GlanceFrame:Build(frame, opts)
    opts = opts or {}
    local chassis = { frame = frame }

    local innerWidth = T.HUD_WIDTH - T.OUTER_INSET * 2

    local header = CreateFrame("Frame", nil, frame)
    if opts.chrome then
        header:SetSize(T.HUD_WIDTH - T.CHROME_START_X, T.CHROME_HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", T.CHROME_START_X, -T.CHROME_HEADER_TOP)
        chassis.height = T.CHROME_HUD_HEIGHT
    else
        header:SetSize(innerWidth, T.HEADER_HEIGHT)
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", T.OUTER_INSET, -T.OUTER_INSET)
        chassis.height = T.HUD_HEIGHT
    end
    chassis.header = header
    -- Text/icons sit flush to the header's own edges inside native chrome
    -- (the frame border already provides the margin).
    local headerPadX = opts.chrome and 0 or T.PAD_X
    local rightPad = opts.chrome and T.CHROME_RIGHT_PAD or T.PAD_X
    local contentHeight = opts.chrome and T.CHROME_CONTENT_HEIGHT or T.CONTENT_HEIGHT
    local buttonW = opts.chrome and T.CHROME_BUTTON or T.HEADER_BUTTON_W
    local buttonH = opts.chrome and T.CHROME_BUTTON or T.HEADER_BUTTON_H
    local buttonGap = opts.chrome and T.CHROME_BUTTON_GAP or T.HEADER_BUTTON_GAP

    header.titleText = PHUI.CreateLabel(header, "primary", opts.title, opts.chrome and PHUI.Fonts.TITLE_COMPACT or PHUI.Fonts.TITLE)
    header.titleText:SetPoint("LEFT", header, "LEFT", headerPadX, 0)
    header.titleText:SetJustifyH("LEFT")

    -- ETA block: fixed width so the header never changes when the value
    -- comes and goes; value then small muted suffix on one line.
    local eta = CreateFrame("Frame", nil, header)
    eta:SetSize(T.ETA_WIDTH, T.HEADER_HEIGHT - 2)
    eta:SetPoint("LEFT", header.titleText, "RIGHT", T.ETA_GAP, 0)
    header.etaBlock = eta
    header.etaValue = PHUI.CreateLabel(eta, "primary", nil, PHUI.Fonts.ETA_VALUE)
    header.etaValue:SetPoint("LEFT", eta, "LEFT", 0, 0)
    header.etaValue:SetJustifyH("LEFT")
    header.etaSuffix = PHUI.CreateLabel(eta, "muted", nil, PHUI.Fonts.ETA_SUFFIX)
    header.etaSuffix:SetPoint("BOTTOMLEFT", header.etaValue, "BOTTOMRIGHT", 4, 0)
    header.etaSuffix:SetJustifyH("LEFT")

    function header:SetEta(value, suffix)
        self.etaValue:SetText(value or "")
        self.etaSuffix:SetText(suffix or "")
    end

    header.icons = {}
    local previous
    local list = opts.buttons or {}
    for i = #list, 1, -1 do
        local spec = list[i]
        local button
        if spec.native then
            -- Native Blizzard button face (the texture IS the box): square.
            button = PHUI.CreateNativeIconButton(header, buttonH, spec.texture, {
                tooltipText = spec.tooltipText, onClick = spec.onClick,
            })
        else
            button = PHUI.CreateIconButton(header, buttonH, spec.texture, {
                tooltipText = spec.tooltipText, onClick = spec.onClick,
            })
            -- Wider box with the icon padded inside it (mockup).
            button:SetSize(buttonW, buttonH)
            button.icon:ClearAllPoints()
            button.icon:SetSize(T.HEADER_BUTTON_ICON, T.HEADER_BUTTON_ICON)
            button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
        end
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -buttonGap, 0)
        else
            button:SetPoint("RIGHT", header, "RIGHT", -rightPad, 0)
        end
        header.icons[i] = button
        previous = button
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetSize(innerWidth, contentHeight)
    if opts.chrome then
        content:SetPoint("TOPLEFT", frame, "TOPLEFT", T.OUTER_INSET, -(T.CHROME_HEADER_TOP + T.CHROME_HEADER_HEIGHT))
    else
        content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    end
    chassis.content = content
    content.nextX = opts.chrome and (T.CHROME_START_X - T.OUTER_INSET) or T.PAD_X
    content.sections = {}

    -- Appends a section of `width` (or, with nil, one filling the rest of
    -- the row) after the previous one, with a subtle divider between them.
    function chassis:AddSection(width)
        local x = content.nextX
        if #content.sections > 0 then
            local divider = content:CreateTexture(nil, "ARTWORK")
            local d = PHUI.Colors.DIVIDER
            divider:SetColorTexture(d[1], d[2], d[3], d[4])
            divider:SetSize(T.DIVIDER_WIDTH, contentHeight - T.PAD_Y * 2)
            divider:SetPoint("LEFT", content, "LEFT", x + T.SECTION_GAP, 0)
            x = x + T.SECTION_GAP + T.DIVIDER_WIDTH + T.SECTION_GAP
        end
        local section = CreateFrame("Frame", nil, content)
        local resolved = width or (innerWidth - rightPad - x)
        section:SetSize(resolved, contentHeight)
        section:SetPoint("LEFT", content, "LEFT", x, 0)
        content.nextX = x + resolved
        table.insert(content.sections, section)
        return section
    end

    -- Where attached tabs start (frame x): the content start.
    chassis.startX = opts.chrome and T.CHROME_START_X or T.PAD_X
    chassis.tabs = {}
    return chassis
end

--------------------------------------------------
-- Attached tabs (docked under the HUD, left edge + PAD_X)
--------------------------------------------------

-- Creates one reusable tab frame (hidden). Parent is the HUD frame so the
-- tab's anchor follows it; it extends below the HUD's own rect.
function GlanceFrame:CreateTab(frame)
    local tab = CreateFrame("Button", nil, frame, "BackdropTemplate")
    tab:SetSize(T.TAB_MIN_WIDTH, T.TAB_HEIGHT)
    PHUI.ApplyBackdrop(tab, { backdrop = PHUI.Backdrops.ICON_BUTTON })

    tab.icon = PHUI.CreateNativeIcon(tab, T.TAB_ICON, nil)
    tab.icon:SetPoint("LEFT", tab, "LEFT", T.PAD_X, 0)

    -- Value above, small label below; fill bar along the bottom edge.
    tab.valueText = PHUI.CreateLabel(tab, "primary", nil, PHUI.Fonts.TAB_VALUE)
    tab.valueText:SetPoint("TOPLEFT", tab, "TOPLEFT", T.PAD_X + T.TAB_ICON + 6, -7)
    tab.valueText:SetJustifyH("LEFT")
    tab.labelText = PHUI.CreateLabel(tab, "muted", nil, PHUI.Fonts.TAB_LABEL)
    tab.labelText:SetPoint("TOPLEFT", tab.valueText, "BOTTOMLEFT", 0, -1)
    tab.labelText:SetJustifyH("LEFT")

    tab.bar = self:CreateBar(tab, T.TAB_MIN_WIDTH - T.PAD_X * 2, T.TAB_BAR_HEIGHT)
    tab.bar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", T.PAD_X, 5)

    -- data: { texture, value, label, fraction, color = {r,g,b} }
    function tab:SetData(data)
        if data.texture then
            self.icon:SetTexture(data.texture)
        end
        self.valueText:SetText(data.value or "")
        self.labelText:SetText(data.label or "")
        local textWidth = math.max(self.valueText:GetStringWidth() or 0, self.labelText:GetStringWidth() or 0)
        local width = GlanceFrame.ComputeTabWidth(textWidth)
        self:SetWidth(width)
        local barWidth = width - T.PAD_X * 2
        self.bar.barWidth = barWidth
        self.bar:SetWidth(barWidth)
        self.bar:SetFraction(data.fraction)
        local c = data.color
        if c then
            self.bar:SetColor(c.r, c.g, c.b)
        end
    end
    tab:Hide()
    return tab
end

-- Anchors the first `count` tabs left-to-right below the HUD. Tabs never
-- touch the HUD's own size/anchor.
function GlanceFrame:LayoutTabs(frame, tabs, count, startX)
    local previous
    for i, tab in ipairs(tabs) do
        if i <= count then
            tab:ClearAllPoints()
            if previous then
                tab:SetPoint("TOPLEFT", previous, "TOPRIGHT", T.TAB_GAP, 0)
            else
                tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", startX or T.PAD_X, -T.TAB_OFFSET_Y)
            end
            tab:Show()
            previous = tab
        else
            tab:Hide()
        end
    end
end
