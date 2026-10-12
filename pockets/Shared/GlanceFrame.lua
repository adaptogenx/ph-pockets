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

-- Scaled to pH's real HUD (ph/UI_HUD.lua): 266px collapsed width, 12px
-- title, 20px header buttons. Width/button size come straight from PHUI so
-- the two HUDs can never drift apart.
GlanceFrame.TOKENS = {
    HUD_WIDTH = PHUI.PH_HUD_WIDTH,
    OUTER_INSET = 3,
    HEADER_HEIGHT = 24,
    CONTENT_HEIGHT = 26,
    PAD_X = 8,
    PAD_Y = 3,
    SECTION_GAP = 4,
    DIVIDER_WIDTH = 1,
    ICON_MAIN = 14,
    ICON_RECENT = 18,
    ICON_GAP = 2,
    HEADER_BUTTON = PHUI.Spacing.ICON_BUTTON_SIZE,
    HEADER_BUTTON_GAP = 4,
    ETA_GAP = 8,
    ETA_WIDTH = 62,
    TAB_HEIGHT = 28,
    TAB_MIN_WIDTH = 80,
    TAB_MAX_WIDTH = 130,
    TAB_GAP = 4,
    TAB_OFFSET_Y = 3,
    TAB_ICON = 16,
    TAB_BAR_HEIGHT = 2,
}
local T = GlanceFrame.TOKENS
T.HUD_HEIGHT = T.OUTER_INSET * 2 + T.HEADER_HEIGHT + T.CONTENT_HEIGHT

local WHITE = "Interface\\Buttons\\WHITE8X8"

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- Tab width: content-sized, clamped to [TAB_MIN_WIDTH, TAB_MAX_WIDTH].
function GlanceFrame.ComputeTabWidth(textWidth)
    local width = T.PAD_X + T.TAB_ICON + 5 + (textWidth or 0) + T.PAD_X
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
-- Chassis
--------------------------------------------------

-- Builds the header + content row inside `frame` (an existing, already
-- sized HUD frame) and returns the chassis table.
-- opts: title (string), buttons (array, left-to-right as they read:
-- { texture, native?, tooltipText, onClick }).
function GlanceFrame:Build(frame, opts)
    opts = opts or {}
    local chassis = { frame = frame }

    local innerWidth = T.HUD_WIDTH - T.OUTER_INSET * 2

    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(innerWidth, T.HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", T.OUTER_INSET, -T.OUTER_INSET)
    chassis.header = header

    header.titleText = PHUI.CreateLabel(header, "primary", opts.title, PHUI.Fonts.TITLE)
    header.titleText:SetPoint("LEFT", header, "LEFT", T.PAD_X, 0)
    header.titleText:SetJustifyH("LEFT")

    -- ETA block: fixed width so the header never changes when the value
    -- comes and goes; value then a small muted suffix on one line.
    local eta = CreateFrame("Frame", nil, header)
    eta:SetSize(T.ETA_WIDTH, T.HEADER_HEIGHT - 6)
    eta:SetPoint("LEFT", header.titleText, "RIGHT", T.ETA_GAP, 0)
    header.etaBlock = eta
    header.etaValue = PHUI.CreateLabel(eta, "primary", nil, PHUI.Fonts.ETA_VALUE)
    header.etaValue:SetPoint("LEFT", eta, "LEFT", 0, 0)
    header.etaValue:SetJustifyH("LEFT")
    header.etaSuffix = PHUI.CreateLabel(eta, "muted", nil, PHUI.Fonts.ETA_SUFFIX)
    header.etaSuffix:SetPoint("LEFT", header.etaValue, "RIGHT", 3, 0)
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
            button = PHUI.CreateNativeIconButton(header, T.HEADER_BUTTON, spec.texture, {
                tooltipText = spec.tooltipText, onClick = spec.onClick,
            })
        else
            button = PHUI.CreateIconButton(header, T.HEADER_BUTTON, spec.texture, {
                tooltipText = spec.tooltipText, onClick = spec.onClick,
            })
        end
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -T.HEADER_BUTTON_GAP, 0)
        else
            button:SetPoint("RIGHT", header, "RIGHT", -T.PAD_X, 0)
        end
        header.icons[i] = button
        previous = button
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetSize(innerWidth, T.CONTENT_HEIGHT)
    content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    chassis.content = content
    content.nextX = T.PAD_X
    content.sections = {}

    -- Appends a section of `width` (or, with nil, one filling the rest of
    -- the row) after the previous one, with a subtle divider between them.
    function chassis:AddSection(width)
        local x = content.nextX
        if #content.sections > 0 then
            local divider = content:CreateTexture(nil, "ARTWORK")
            local d = PHUI.Colors.DIVIDER
            divider:SetColorTexture(d[1], d[2], d[3], d[4])
            divider:SetSize(T.DIVIDER_WIDTH, T.CONTENT_HEIGHT - T.PAD_Y * 2 - 6)
            divider:SetPoint("LEFT", content, "LEFT", x + T.SECTION_GAP, 0)
            x = x + T.SECTION_GAP + T.DIVIDER_WIDTH + T.SECTION_GAP
        end
        local section = CreateFrame("Frame", nil, content)
        local resolved = width or (innerWidth - T.PAD_X - x)
        section:SetSize(resolved, T.CONTENT_HEIGHT)
        section:SetPoint("LEFT", content, "LEFT", x, 0)
        content.nextX = x + resolved
        table.insert(content.sections, section)
        return section
    end

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
    tab.icon:SetPoint("LEFT", tab, "LEFT", T.PAD_X, 1)

    tab.valueText = PHUI.CreateLabel(tab, "primary", nil, PHUI.Fonts.TAB_VALUE)
    tab.valueText:SetPoint("TOPLEFT", tab.icon, "TOPRIGHT", 5, 3)
    tab.valueText:SetJustifyH("LEFT")
    tab.labelText = PHUI.CreateLabel(tab, "muted", nil, PHUI.Fonts.TAB_LABEL)
    tab.labelText:SetPoint("TOPLEFT", tab.valueText, "BOTTOMLEFT", 0, -1)
    tab.labelText:SetJustifyH("LEFT")

    tab.bar = self:CreateBar(tab, T.TAB_MIN_WIDTH - T.PAD_X * 2, T.TAB_BAR_HEIGHT)
    tab.bar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", T.PAD_X, 4)

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
function GlanceFrame:LayoutTabs(frame, tabs, count)
    local previous
    for i, tab in ipairs(tabs) do
        if i <= count then
            tab:ClearAllPoints()
            if previous then
                tab:SetPoint("TOPLEFT", previous, "TOPRIGHT", T.TAB_GAP, 0)
            else
                tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", T.PAD_X, -T.TAB_OFFSET_Y)
            end
            tab:Show()
            previous = tab
        else
            tab:Hide()
        end
    end
end
