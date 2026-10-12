--[[
    UI/Shell.lua - Single-frame Glance -> Menu -> Category -> All Items
    navigation shell (.plans/Pockets_Glance_UI.md)

    ONE OBJECT. ONE ROOT FRAME. CONTENT CHANGES IN PLACE.

    Replaces the previous HUD -> hover flyout -> item flyout -> separate
    full-inventory-window model. There is exactly one root frame
    (PocketsShellFrame); navigation moves it between four explicit states
    (Shell.STATE) rather than opening/closing adjacent windows. Only
    GLANCE is allowed unique geometry - MENU/CATEGORY/ALL share identical
    width, header height, body-viewport height, footer height, and screen
    position (§3 "Stable application shell"). Click is the only navigation
    mechanism; hover is reserved for ordinary WoW tooltips/button feedback.

    State transitions never rescan bags or recreate the root frame - every
    Render* function reads already-computed InventoryState/CapacityEstimator
    data (§14 Performance).
]]

-- luacheck: globals SecureHandlerWrapScript RegisterStateDriver UISpecialFrames

local _, Pockets = ...

Pockets.UI.Shell = Pockets.UI.Shell or {}
local Shell = Pockets.UI.Shell

local Layout = Pockets.UI.Layout
local Constants = Pockets.Constants
local L = Constants.LAYOUT
local FlowLayout = Pockets.UI.FlowLayout
local PositionStrategy = Pockets.UI.PositionStrategy
local PHUI = Pockets.UI.PHUI

Shell.STATE = {
    GLANCE = "GLANCE",
    MENU = "MENU",
    CATEGORY = "CATEGORY",
    ALL = "ALL",
    -- Glance Quick Search: Glance -> Search -> interact -> Glance. NOT
    -- inventory browsing - deliberately excluded from MENU/CATEGORY/ALL's
    -- shared footer/scrollbar body contract (see RenderSearch).
    SEARCH = "SEARCH",
    -- Loot Log: a peer view reached from Glance/Menu/Category chrome
    -- (scroll icon), not an inventory category. Back returns to wherever
    -- it was opened from (context.returnState), so it has no fixed
    -- ESCAPE_PARENT entry.
    LOOT = "LOOT",
}

-- Back (`<`) hierarchy (§4): CATEGORY/ALL -> MENU -> GLANCE, SEARCH ->
-- GLANCE. Escape does NOT use this map (top-bar/close pass) - Escape/X
-- dismiss straight to GLANCE from any expanded state; only the Back
-- button walks it stepwise.
local ESCAPE_PARENT = {
    [Shell.STATE.CATEGORY] = Shell.STATE.MENU,
    [Shell.STATE.ALL] = Shell.STATE.MENU,
    [Shell.STATE.MENU] = Shell.STATE.GLANCE,
    [Shell.STATE.SEARCH] = Shell.STATE.GLANCE,
}

-- Root total height for a given body height (UI layout pass §6): every
-- expanded state's body height is computed dynamically from actual
-- content (visible category count for Menu, laid-out items for
-- Category/All) - the shared invariant is TOPLEFT/width/header/footer
-- stability, not identical total height.
-- includeFooter defaults to true (Menu/Category/All's shared contract).
-- SEARCH passes false - Quick Search has "No footer" by design (product
-- intent: it is not another inventory-browsing surface), so its total
-- height must not reserve footer space that will never be shown.
local function TotalHeightForBody(bodyHeight, includeFooter)
    if includeFooter == false then
        return L.SHELL_HEADER_HEIGHT + bodyHeight
    end
    return L.SHELL_HEADER_HEIGHT + bodyHeight + L.SHELL_FOOTER_HEIGHT
end

-- The body viewport's width never actually varies (SHELL_WIDTH is
-- constant across every expanded state), so this is a fixed computation
-- rather than a live frame read - lets Category/All renderers plan their
-- layout (and thus their own dynamic height) before calling
-- ApplyDimensions, instead of needing the frame already sized first.
local function BodyViewportWidth()
    return L.SHELL_WIDTH - L.SHELL_PADDING * 2
end

-- SHELL_BODY_MIN_HEIGHT/MAX_HEIGHT are bodyHeight-shaped values (what
-- ApplyDimensions/TotalHeightForBody expect - i.e. already including the
-- SHELL_PADDING inset on both top and bottom of the scrollFrame
-- viewport), NOT raw content height. A renderer's actual laid-out
-- content (rows/items only) must be compared against - and, once
-- clamped, converted back into - bodyHeight through that same
-- 2*SHELL_PADDING offset, or the scrollFrame viewport ends up shorter
-- than the content it was just sized to hold, clipping the last
-- row/item behind the footer even though no scrollbar was judged
-- necessary (vertical sizing/scrolling fix).
local function MaxContentHeight()
    return L.SHELL_BODY_MAX_HEIGHT - L.SHELL_PADDING * 2
end

local function MinContentHeight()
    return math.max(L.SHELL_BODY_MIN_HEIGHT - L.SHELL_PADDING * 2, 0)
end

-- Clamps a CONTENT height (rows/items only) against an explicit max (or
-- MaxContentHeight() by default - Category List passes its own
-- row-count-based cap instead) and returns:
--   usedContentHeight - the (possibly capped) content height to actually
--     lay out/scroll within
--   bodyHeight - what to pass to ApplyDimensions
--   needsScrollbar - whether the real content overflowed the cap
-- minContentHeight defaults to MinContentHeight() (Grid/All's sensible
-- floor for a near-empty view); Menu/Category List pass 0 instead - a
-- real list row is never shorter than LIST_ROW_HEIGHT to begin with, so
-- padding a 1-row category up toward an unrelated pixel floor just made
-- it look disproportionately tall next to its own content (confirmed
-- regression: a 1-item category rendered ~1.6 rows tall).
local function ResolveDynamicHeight(contentHeight, maxContentHeight, minContentHeight)
    maxContentHeight = maxContentHeight or MaxContentHeight()
    minContentHeight = minContentHeight or MinContentHeight()
    local needsScrollbar = contentHeight > maxContentHeight
    local usedContentHeight = needsScrollbar and maxContentHeight or math.max(contentHeight, minContentHeight)
    return usedContentHeight, usedContentHeight + L.SHELL_PADDING * 2, needsScrollbar
end

-- Menu and Category List's shared cap (height-management pass): both
-- grow naturally until MAX_VISIBLE_LIST_ROWS complete rows are showing,
-- then cap at exactly that many whole rows and scroll - never a raw
-- pixel budget (MaxContentHeight/SHELL_BODY_MAX_HEIGHT) that could land
-- mid-row. Grid/All are explicitly out of scope for this pass and keep
-- using MaxContentHeight().
local function MaxListContentHeight()
    return L.MAX_VISIBLE_LIST_ROWS * L.LIST_ROW_HEIGHT
end

-- Thin wrapper around the shared UI/ScrollBar.lua component (scrollbar
-- redesign pass): scrollFrame's own rect NEVER changes based on whether
-- the bar is shown - it lives in the panel's existing right-edge padding
-- gutter instead of a reserved column. Callers just hand over the
-- contentHeight/usedContentHeight they already computed for
-- ApplyDimensions - the component itself decides show/hide and thumb
-- size/range from those two numbers; no caller narrows its own
-- rowWidth/usableWidth based on whether a scrollbar ends up showing
-- (that reservation was the old bulky Blizzard scrollbar's whole
-- "changes column count when it appears" problem).
local function SetScrollBarShown(shell, contentHeight, usedContentHeight)
    Pockets.UI.ScrollBar:Update(shell.scrollBar, contentHeight, usedContentHeight)
end

--------------------------------------------------
-- Pure predicates (unit-testable without a live frame)
--------------------------------------------------

-- An Ammo row/stat is shown only when an ammo-specialized bag is actually
-- equipped (ammo.total > 0), never merely because ammo items are being
-- carried in normal bags (TDD §7).
function Shell:ShouldShowAmmoRow(ammoCapacity)
    return (ammoCapacity and ammoCapacity.total or 0) > 0
end

function Shell:GetParentState(state)
    return ESCAPE_PARENT[state]
end

--------------------------------------------------
-- Menu row widget (click-only category navigation - no hover-flyout)
--------------------------------------------------

-- Fixed conceptual columns ICON | LABEL | FLEX | COUNT | CHEVRON (§3,
-- §11) - only the LABEL/FLEX region ever moves when rowWidth changes
-- (SetWidth below), everything else is anchored from a fixed edge so a
-- 3-digit count never shifts the label and the chevron never moves.
local function CreateMenuRow(parent, rowWidth)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(L.LIST_ROW_HEIGHT)
    row:SetWidth(rowWidth)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(L.LIST_ICON_SIZE, L.LIST_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", L.LIST_ROW_PADDING, 0)

    row.count = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.SMALL)
    row.count:SetPoint("RIGHT", row, "RIGHT", -(L.LIST_ROW_PADDING + L.LIST_ROW_CHEVRON_WIDTH + L.LIST_ROW_GAP), 0)
    row.count:SetWidth(L.LIST_ROW_COUNT_WIDTH)
    row.count:SetJustifyH("RIGHT")

    -- An unmistakable ">" navigation affordance, not the old ambiguous
    -- small guillemet - visually subordinate to the count (muted color)
    -- but sized to actually read as "this row goes deeper" (§2). Not its
    -- own click target - the whole row's OnClick (set per-render below)
    -- is what navigates; this is a label only.
    row.chevron = row:CreateFontString(nil, "OVERLAY")
    row.chevron:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    local mutedColor = PHUI.Colors.TEXT_MUTED
    row.chevron:SetTextColor(mutedColor[1], mutedColor[2], mutedColor[3], mutedColor[4] or 1)
    row.chevron:SetText(">")
    row.chevron:SetWidth(L.LIST_ROW_CHEVRON_WIDTH)
    row.chevron:SetJustifyH("CENTER")
    row.chevron:SetPoint("RIGHT", row, "RIGHT", -L.LIST_ROW_PADDING, 0)

    row.label = PHUI.CreateLabel(row, "primary", nil, PHUI.Fonts.SMALL)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", L.LIST_ROW_GAP, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -L.LIST_ROW_GAP, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- Same full-row hover treatment Category List rows get for free from
    -- ItemButtonTemplate (row unification pass §8) - the standard
    -- Blizzard button highlight, not a bespoke PHUI overlay, so both row
    -- types share one hover mechanism instead of two different-looking
    -- ones.
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    return row
end

--------------------------------------------------
-- Frame construction
--------------------------------------------------

-- Compact metric-list HUD (Glance redesign pass) - NOT a centered status
-- card, NOT forced square. Structure, top to bottom: header ("pockets" +
-- Search), Bag/Gold/Ammo metric rows (Ammo optional, always last, built
-- via one shared MetricRow component), Recent Items strip. Every frame
-- below gets BOTH width and height set explicitly at creation (via the
-- component opts) - a frame anchored by a single point with only one
-- dimension known can resolve to a fully indeterminate position, which
-- is exactly what silently blanked every earlier version of this HUD.
function Shell:BuildGlance()
    local frame = self.root
    local T = Pockets.UI.GlanceFrame.TOKENS
    -- Fixed HUD size from the shared chassis tokens; never resized after.
    frame:SetSize(T.HUD_WIDTH, T.HUD_HEIGHT)
    local glance = CreateFrame("Frame", nil, frame)
    glance:SetAllPoints(frame)
    frame.glance = glance
    self.frame.glance = glance

    -- Header (title, ETA, Search/Log/Expand), bag capacity, money, five
    -- Recent icons and the specialized-bag tabs: see UI/PocketsGlance.lua.
    Pockets.UI.PocketsGlance:Build(glance, {
        openSearch = function() Shell:SetState(Shell.STATE.SEARCH) end,
        openLog = function() Shell:OpenLootLog() end,
        openAll = function() Shell:SetState(Shell.STATE.ALL) end,
    })
end

function Shell:BuildShell()
    local frame = self.expanded
    local shell = CreateFrame("Frame", nil, frame)
    -- shell fills frame's rect exactly - frame itself is the one thing
    -- Shell:ApplyDimensions ever resizes (§3 "one logical root frame").
    shell:SetAllPoints(frame)
    frame.shell = shell
    self.frame.shell = shell
    shell.menuRows = {}
    shell.categoryHeaders = {}
    shell.categoryListRows = {}

    -- Header: fixed [back][title][right] zones (§3 header contracts) -
    -- the control occupying a zone changes, the zone itself never moves.
    -- Anchored only to the shell's top edge (§8) - never repositioned by
    -- state changes, only its contents are reconfigured. Real PHUI
    -- backdrop+border (§1 of the polish pass) instead of a flat texture -
    -- slightly more opaque than the body so it reads as a distinct,
    -- structurally-bordered chrome band rather than a strip laid over it.
    local header = CreateFrame("Frame", nil, shell, "BackdropTemplate")
    header:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", shell, "TOPRIGHT", 0, 0)
    header:SetHeight(L.SHELL_HEADER_HEIGHT)
    shell.header = header
    PHUI.ApplyBackdrop(header, { bgAlpha = L.EXPANDED_CHROME_ALPHA })

    header.backButton = PHUI.CreateIconButton(header, L.SHELL_HEADER_SIDE_WIDTH, nil, {
        tooltipText = "Back",
        onClick = function() Shell:GoBack() end,
    })
    header.backButton:SetPoint("LEFT", header, "LEFT", L.SHELL_PADDING, 0)
    header.backButton.glyph = PHUI.CreateLabel(header.backButton, "primary", "\226\128\185", PHUI.Fonts.SMALL) -- "<"
    header.backButton.glyph:SetPoint("CENTER", 0, 0)

    header.titleText = PHUI.CreateLabel(header, "primary", "Pockets", PHUI.Fonts.TITLE)
    header.titleText:SetJustifyH("LEFT")
    header.titleText:SetWordWrap(false)

    -- X is always fixed at the far-right edge of every expanded state
    -- (top-bar/close pass §"TOP BAR") - dismisses Pockets straight to
    -- Glance, never through the Back/Escape hierarchy. Built and anchored
    -- once here, never hidden/recreated per state, so its position can
    -- never shift between Menu/Category/All.
    header.closeButton = PHUI.CreateCloseButton(header, {
        size = L.SHELL_HEADER_CLOSE_WIDTH,
        onClick = function() Shell:SetState(Shell.STATE.GLANCE) end,
    })
    header.closeButton:SetPoint("RIGHT", header, "RIGHT", -L.SHELL_PADDING, 0)

    -- Contextual action (+ / search) sits immediately LEFT of the
    -- always-present X, never in the far-right slot itself.
    header.plusButton = PHUI.CreateNativeIconButton(header, L.SHELL_HEADER_SIDE_WIDTH, PHUI.Icons.PLUS, {
        tooltipText = "All Items",
        onClick = function() Shell:SetState(Shell.STATE.ALL) end,
    })
    header.plusButton:SetPoint("RIGHT", header.closeButton, "LEFT", -L.SHELL_HEADER_ACTION_GAP, 0)

    -- Loot Log entry, immediately left of "+" (same boxed icon-button
    -- style/size as Glance's Search). Hidden wherever "+"'s slot is taken
    -- by something else (All's search box) or where it's already open.
    header.lootButton = PHUI.CreateIconButton(header, L.SHELL_HEADER_SIDE_WIDTH, PHUI.Icons.SCROLL, {
        tooltipText = "Loot Log",
        onClick = function() Shell:OpenLootLog() end,
    })
    header.lootButton:SetPoint("RIGHT", header.plusButton, "LEFT", -L.SHELL_HEADER_ACTION_GAP, 0)

    header.searchBox = CreateFrame("EditBox", nil, header, "InputBoxTemplate")
    -- Same height as Quick Search's own editBox (SEARCH_INPUT_HEIGHT) so
    -- both search inputs read as the same control, not two different sizes.
    header.searchBox:SetHeight(L.SEARCH_INPUT_HEIGHT)
    header.searchBox:SetWidth(L.SHELL_HEADER_RIGHT_WIDTH - 6)
    header.searchBox:SetPoint("RIGHT", header.closeButton, "LEFT", -L.SHELL_HEADER_ACTION_GAP, 0)
    header.searchBox:SetAutoFocus(false)
    header.searchBox:SetScript("OnTextChanged", function(box)
        Shell:RenderAll(box:GetText())
    end)
    -- Same reasoning as searchPanel.editBox's own OnEscapePressed below -
    -- this editbox must resolve Escape itself (clear focus, then dismiss)
    -- rather than leaving it to the raw keydown bubbling up to frame's
    -- OnKeyDown, since that handler now bails out entirely while any
    -- editbox holds keyboard focus (see EnableKeyboard note there).
    header.searchBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        Shell:HandleEscape()
    end)
    header.searchBox:Hide()

    -- Footer: anchored only to the shell's bottom edge (§8) - never moves
    -- when the body resizes above it. Same real PHUI backdrop+border
    -- treatment as the header (§1) - header/body/footer read as one
    -- connected panel since their left/right/shared edges are coincident
    -- with the root frame's own border, not offset from it.
    shell.footer = CreateFrame("Frame", nil, shell, "BackdropTemplate")
    shell.footer:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", 0, 0)
    shell.footer:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", 0, 0)
    shell.footer:SetHeight(L.SHELL_FOOTER_HEIGHT)
    PHUI.ApplyBackdrop(shell.footer, { bgAlpha = L.EXPANDED_CHROME_ALPHA })

    -- Footer metrics (Full Inventory redesign): reuse the SAME MetricRow/
    -- MoneyFormat components Glance's Bag/Gold/Ammo rows already use,
    -- rather than duplicated FontString formatting - icon/gap/font sizes
    -- are the same verified pH-sized defaults (GLANCE_METRIC_ICON_SIZE),
    -- just laid out horizontally instead of stacked. width starts at 1
    -- (unknown until text is set) - Shell:ConfigureFooter resizes each to
    -- its own measured content width every render, same pattern
    -- EnsureCategoryHeader/CategoryLabel already used.
    local function BuildFooterMetric(texture, iconOpts, primaryStyle)
        return Pockets.UI.MetricRow:Create(shell.footer, {
            width = 1,
            height = L.GLANCE_METRIC_ROW_HEIGHT,
            iconSize = L.GLANCE_METRIC_ICON_SIZE,
            gap = L.GLANCE_METRIC_ICON_TEXT_GAP,
            texture = texture,
            iconOpts = iconOpts,
            hasSecondary = false,
            primaryStyle = primaryStyle,
        })
    end

    shell.footerBagRow = BuildFooterMetric(Constants.HUD_ICON, { insetTexCoord = false }, "primary")
    shell.footerBagRow:SetPoint("LEFT", shell.footer, "LEFT", L.SHELL_PADDING, 0)

    shell.footerGoldRow = BuildFooterMetric(Constants.GOLD_ICON, { insetTexCoord = false }, "muted")

    -- Ammo is always the far-right metric, independent of Bag/Gold's
    -- measured widths (§ "Ammo disappears completely when irrelevant") -
    -- fixed to the footer's own right edge rather than chained after Gold.
    shell.footerAmmoRow = BuildFooterMetric(Constants.CATEGORY_ICON.ammo, nil, "primary")
    shell.footerAmmoRow:SetPoint("RIGHT", shell.footer, "RIGHT", -L.SHELL_PADDING, 0)
    shell.footerAmmoRow:Hide()

    -- Body: the ONE region whose height actually varies by state - it
    -- fills whatever space is left between header and footer once
    -- Shell:ApplyDimensions resizes the root frame (§8), so nothing here
    -- ever needs to be repositioned by hand per state. One scrolling
    -- viewport reused by Menu/Category/All (§3 "consistent body bounds").
    --
    -- Plain ScrollFrame, no template (scrollbar redesign pass) - Blizzard's
    -- UIPanelScrollFrameTemplate drags in a wide dedicated scrollbar column
    -- with big up/down arrow buttons, which read as a second toolbar next
    -- to the item grid and forced every RenderX function to narrow its own
    -- content width whenever a scrollbar appeared (reflowing the grid).
    -- The scrollFrame's own rect is now fixed - always inset by exactly
    -- SHELL_PADDING, regardless of whether a scrollbar is showing - and
    -- UI/ScrollBar.lua's compact custom Slider lives in that same existing
    -- padding gutter as a sibling, never reserving extra width itself.
    shell.scrollFrame = CreateFrame("ScrollFrame", "PocketsShellScrollFrame", shell)
    shell.scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", L.SHELL_PADDING, -L.SHELL_PADDING)
    shell.scrollFrame:SetPoint("BOTTOMRIGHT", shell.footer, "TOPRIGHT", -L.SHELL_PADDING, L.SHELL_PADDING)
    shell.scrollBar = Pockets.UI.ScrollBar:Create(shell.scrollFrame)

    shell.content = CreateFrame("Frame", nil, shell.scrollFrame)
    shell.content:SetWidth(L.SHELL_WIDTH - L.SHELL_PADDING * 2)
    shell.content:SetHeight(1)
    shell.scrollFrame:SetScrollChild(shell.content)

    -- A dedicated ItemButtonPool key (not `shell.content` itself, which
    -- Grid's own pool uses) - List rows are acquired ONCE and reused
    -- indefinitely (unlike Grid's per-render Acquire/ReleaseAll), and
    -- each one is resized/reparented for the row layout. Sharing Grid's
    -- pool key would let a resized List row get recycled back into Grid
    -- mode still shaped like a List row. MUST be parented under
    -- `shell.content` (not a sibling of it) - WoW only clips/scrolls a
    -- ScrollFrame's actual frame DESCENDANTS, not frames merely
    -- SetPoint-anchored relative to its scroll child. A sibling parent
    -- here previously let List rows render entirely unclipped, spilling
    -- past the panel and even the footer once a category had more items
    -- than fit the visible viewport.
    shell.categoryListPoolAnchor = CreateFrame("Frame", nil, shell.content)

    -- Loot Log rows (UI/LootLog.lua) live in the same scroll content, so
    -- they get the shared ScrollBar and clipping like every other body.
    shell.lootView = Pockets.UI.LootLog:Create(shell.content)

    -- SEARCH body (Glance Quick Search pass) - deliberately NOT the
    -- scrollFrame/content above: no footer, no scrollbar, capped at
    -- SEARCH_MAX_RESULT_ROWS rows, so it gets its own small non-scrolling
    -- panel anchored the same way scrollFrame is (under header, inset by
    -- SHELL_PADDING) but sized purely from its own content each render.
    shell.searchPanel = CreateFrame("Frame", nil, shell)
    shell.searchPanel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", L.SHELL_PADDING, -L.SHELL_PADDING)
    shell.searchPanel:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -L.SHELL_PADDING, -L.SHELL_PADDING)
    shell.searchPanel:Hide()

    shell.searchPanel.icon = shell.searchPanel:CreateTexture(nil, "ARTWORK")
    shell.searchPanel.icon:SetSize(L.SEARCH_ICON_SIZE, L.SEARCH_ICON_SIZE)
    shell.searchPanel.icon:SetPoint("TOPLEFT", shell.searchPanel, "TOPLEFT", 0, 0)
    shell.searchPanel.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

    shell.searchPanel.editBox = CreateFrame("EditBox", nil, shell.searchPanel, "InputBoxTemplate")
    shell.searchPanel.editBox:SetHeight(L.SEARCH_INPUT_HEIGHT)
    shell.searchPanel.editBox:SetPoint("LEFT", shell.searchPanel.icon, "RIGHT", L.SHELL_HEADER_ACTION_GAP, 0)
    shell.searchPanel.editBox:SetPoint("RIGHT", shell.searchPanel, "RIGHT", 0, 0)
    shell.searchPanel.editBox:SetAutoFocus(false)
    -- Cached/aggregated data only (product intent "PERFORMANCE") - every
    -- keystroke re-renders from API.GetAllAggregatedItems(), never a bag
    -- rescan or categorization pass.
    shell.searchPanel.editBox:SetScript("OnTextChanged", function()
        local ok, err = pcall(Shell.RenderSearch, Shell)
        if not ok and Pockets.Debug then
            Pockets.Debug:LogError("RenderSearch failed: " .. tostring(err))
        end
    end)
    shell.searchPanel.editBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        Shell:HandleEscape()
    end)

    -- 0-match / 3+-match feedback (mutually exclusive with the result
    -- rows below - RenderSearch shows exactly one of the three).
    shell.searchPanel.feedbackPrimary = PHUI.CreateLabel(shell.searchPanel, "primary", nil, PHUI.Fonts.NORMAL)
    shell.searchPanel.feedbackPrimary:SetPoint(
        "TOP", shell.searchPanel, "TOP", 0, -(L.SEARCH_INPUT_HEIGHT + L.SEARCH_ROW_GAP))
    shell.searchPanel.feedbackPrimary:Hide()

    shell.searchPanel.feedbackSecondary = PHUI.CreateLabel(shell.searchPanel, "muted", "Keep typing...", PHUI.Fonts.SMALL)
    shell.searchPanel.feedbackSecondary:SetPoint(
        "TOP", shell.searchPanel.feedbackPrimary, "BOTTOM", 0, -L.SEARCH_FEEDBACK_LINE_GAP)
    shell.searchPanel.feedbackSecondary:Hide()

    -- "and N more" trailer line, shown only when totalCount exceeds the
    -- SEARCH_MAX_RESULT_ROWS rows actually rendered (still under
    -- SEARCH_OVERFLOW_LIMIT, so real rows ARE showing) - anchored fresh
    -- every render in RenderSearch since which row it trails depends on
    -- how many rows are currently shown.
    shell.searchPanel.overflowLabel = PHUI.CreateLabel(shell.searchPanel, "muted", nil, PHUI.Fonts.SMALL)
    shell.searchPanel.overflowLabel:Hide()

    -- Result rows reuse the exact same List row / ItemButtonPool
    -- component Category List uses (CreateCategoryListRow) - real secure
    -- item buttons, not a second interaction implementation. Own pool key
    -- (not shell.content/categoryListPoolAnchor) since these never need
    -- ScrollFrame clipping (capped at SEARCH_MAX_RESULT_ROWS, no scroll).
    shell.searchPoolAnchor = CreateFrame("Frame", nil, shell.searchPanel)
    shell.searchRows = {}
end

function Shell:Initialize()
    if self.frame then
        return
    end

    -- Where item buttons are secure (Forever), both top-level frames are
    -- secure handlers too, so a restricted snippet can show/hide them in
    -- combat. Insecure code may still show/hide them out of combat.
    self.useSecure = Pockets.Adapters.BagAPI:UsesSecureItemAttributes() == true
    local frameTemplate = self.useSecure and "SecureHandlerBaseTemplate,BackdropTemplate" or "BackdropTemplate"
    local frame = CreateFrame("Button", "PocketsShellFrame", UIParent, frameTemplate)
    self.root = frame

    -- The expanded view (Menu/Category/All/Search/Loot) is its OWN top-level
    -- frame, not a child of the Glance root. Item buttons are protected in
    -- combat, and a frame in a protected button's anchor chain cannot be
    -- re-anchored or resized then. Keeping the expanded item buttons under a
    -- separate chain means Glance can still be touched, and the expanded
    -- frame is only ever shown/hidden in combat (never resized/re-anchored).
    local expanded = CreateFrame("Button", "PocketsExpandedFrame", UIParent, frameTemplate)
    expanded:Hide()
    self.expanded = expanded

    -- Legacy single-frame facade: `Shell.frame` forwards methods to whichever
    -- frame is currently on screen (expanded for non-Glance states) and
    -- carries the .glance/.shell fields. Use GetActiveFrame() whenever a real
    -- frame is required (anchoring, parenting).
    self.frame = setmetatable({}, {
        __index = function(_, key)
            return function(_, ...)
                local target = Shell:GetActiveFrame()
                return target[key](target, ...)
            end
        end,
    })

    for _, f in ipairs({ frame, expanded }) do
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        PHUI.ApplyBackdrop(f)

        f:SetScript("OnDragStart", function(self)
            -- StartMoving on a frame in a protected button's anchor chain
            -- is blocked in combat.
            if Pockets.UI.ItemButtonPool:IsStructurallyBlocked() then
                return
            end
            if not Pockets.CharDB.hud.locked then
                Shell.isDragging = true
                self:StartMoving()
            end
        end)
        f:SetScript("OnDragStop", function(self)
            if not Shell.isDragging then
                return
            end
            self:StopMovingOrSizing()
            Shell.isDragging = false
            Shell:SavePosition(self)
            -- Render() no-ops while isDragging is true (see Render's guard),
            -- so any state change requested by the SAME click (WoW fires
            -- OnDragStart/OnDragStop on every click, moving or not - see
            -- OnClick's note below) never got drawn. Flush it now.
            Shell:Render()
        end)
    end
    -- Growing DOWN/RIGHT from a fixed TOPLEFT must never depend on the
    -- frame's SIZE - no OnSizeChanged handler here re-anchors anything.
    -- Position is only ever written by a user drag (SavePosition) and
    -- only ever read/reapplied by Render's RestorePosition call (§1, §2,
    -- §15) - there is no other path that touches the root frame's point.

    -- Click is the only navigation mechanism (§1). Clicking Glance opens
    -- Menu; clicks inside Menu/Category/All are handled by their own
    -- child buttons/rows and never reach this handler.
    --
    -- WoW fires OnDragStart/OnDragStop on every mousedown/mouseup for any
    -- frame registered via RegisterForDrag, even a stationary click with
    -- zero movement - so this OnClick can run while StartMoving()'s
    -- cursor-follow is technically still active for the same click.
    -- SetState below would then resize the frame (Glance -> Menu) WHILE
    -- WoW's drag system is mid-commit, which corrupts the position
    -- StopMovingOrSizing() ends up saving (observed in practice: opening
    -- jumped the frame, closing jumped it again by roughly double).
    -- Render() defers itself while isDragging is true and OnDragStop
    -- flushes it once the drag has fully settled, so no resize can ever
    -- happen mid-move.
    frame:SetScript("OnClick", function()
        if Shell.state == Shell.STATE.GLANCE then
            Shell:SetState(Shell.STATE.MENU)
        end
    end)

    -- Escape dismisses straight to Glance (HandleEscape), never stepping
    -- backward through the hierarchy. Done with the standard WoW mechanism
    -- - a hidden frame registered in UISpecialFrames that is only SHOWN
    -- while an expanded state is open - so Escape closes it (and does not
    -- also open the Game Menu) and Pockets never captures the keyboard.
    -- The old approach (EnableKeyboard + SetPropagateKeyboardInput) kept
    -- Enter/typing from reaching chat on WoW Forever.
    local catcher = CreateFrame("Frame", "PocketsEscapeCatcher", UIParent)
    catcher:Hide()
    catcher:SetScript("OnHide", function(self)
        if not self.suppress then
            Shell:HandleEscape()
        end
    end)
    table.insert(UISpecialFrames, "PocketsEscapeCatcher")
    Shell.escapeCatcher = catcher

    self:BuildGlance()
    self:BuildShell()
    self:BuildSecureControls()
    self:RestorePosition()

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.ETA_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.INVENTORY_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.LOOT_LOGGED, function() self:RefreshLootLog() end, self)

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.COMBAT_STATE_CHANGED, function(payload)
        if payload and payload.inCombat == false then
            self:OnCombatEnded()
        end
    end, self)

    -- Learn (out of combat) whether item buttons are combat-protected.
    Pockets.UI.ItemButtonPool:Probe(UIParent)

    self.state = self.STATE.GLANCE
    self.context = {}
    self:Render()
end

-- Position and size are independent concerns (§2): this is the ONLY place
-- that ever anchors the root frame to UIParent. Every state transition
-- afterward touches SetSize only, so the anchor set here is what pins
-- Glance's TOPLEFT and every expanded state's TOPLEFT to the same point.
function Shell:RestorePosition()
    -- Re-anchoring is blocked in combat for frames in a protected button's
    -- anchor chain; the saved position only changes via a drag anyway.
    if Pockets.UI.ItemButtonPool:IsStructurallyBlocked() then
        return
    end
    PositionStrategy:ApplyRootPosition(self.root, Pockets.CharDB.hud)
    PositionStrategy:ApplyRootPosition(self.expanded, Pockets.CharDB.hud)
end

-- The frame currently on screen for the current state (Glance root, or the
-- expanded frame for every other state).
function Shell:GetActiveFrame()
    if self.state == nil or self.state == self.STATE.GLANCE then
        return self.root
    end
    return self.expanded
end

-- OnDragStart/OnDragStop fire on every click (moving or not), so this
-- runs far more often than an actual drag happens. Skip the write
-- entirely when the position hasn't meaningfully changed, so a
-- stationary click can never persist a fresh (and possibly slightly
-- different, e.g. from float rounding) value over a perfectly good one.
local NO_OP_MOVE_THRESHOLD = 0.5
function Shell:SavePosition(source)
    local hud = Pockets.CharDB.hud
    local captured = PositionStrategy:CaptureSavedPosition(source or self:GetActiveFrame())

    if math.abs(captured.x - (hud.x or 0)) < NO_OP_MOVE_THRESHOLD
        and math.abs(captured.y - (hud.y or 0)) < NO_OP_MOVE_THRESHOLD then
        return
    end

    hud.point = captured.point
    hud.relativePoint = captured.relativePoint
    hud.x = captured.x
    hud.y = captured.y
end

--------------------------------------------------
-- State machine (§4)
--------------------------------------------------

function Shell:GetState()
    return self.state
end

-- Cheap: never rescans bags, never recreates the root frame - every
-- Render* function below only reads already-computed domain state (§14).
function Shell:SetState(state, context)
    local previousState = self.state
    -- In combat nothing may be re-laid-out: hand straight to Render, which
    -- opens/closes the already laid-out view (RenderInCombat).
    if self:IsCombatBlocked() then
        self.state = state
        self.context = context or {}
        self:Render()
        return
    end
    local enteringSearch = state == self.STATE.SEARCH and previousState ~= self.STATE.SEARCH

    -- Cleared BEFORE Render() (not after) so the very first RenderSearch
    -- this transition triggers already reflects a blank query - Quick
    -- Search always starts fresh from Glance, never carrying over a
    -- previous session's leftover text/results.
    --
    -- ClearBody() also belongs ONLY here, on the actual state transition -
    -- not inside RenderSearch itself, which OnTextChanged also calls on
    -- every keystroke. ClearBody() hides searchPanel (see its own body),
    -- and hiding a frame that contains a focused EditBox drops its
    -- keyboard focus - doing that on every keystroke silently unfocused
    -- the box after the very first typed character, so every key after
    -- that fell through to normal keybinding dispatch instead of typing.
    if enteringSearch and self.frame then
        self.frame.shell.searchPanel.editBox:SetText("")
        self:ClearBody()
    end

    if previousState ~= state then
        self.lootRendered = false
    end
    self.state = state
    self.context = context or {}
    self:Render()

    -- Focus only on the Glance -> Search transition itself, never on a
    -- re-render while already in SEARCH (typing/data-change renders would
    -- otherwise steal focus/cursor position away from the player).
    if enteringSearch then
        self.frame.shell.searchPanel.editBox:SetFocus()
    end
end

function Shell:GoBack()
    if self.state == self.STATE.LOOT then
        -- Back to wherever Loot Log was opened from, with its context
        -- (e.g. the category being viewed).
        local returnState = self.context.returnState or self.STATE.GLANCE
        self:SetState(returnState, self.context.returnContext)
        return
    end
    local parent = self:GetParentState(self.state)
    if parent then
        self:SetState(parent)
    end
end

-- Escape = dismiss Pockets, not "navigate up" (top-bar/close pass
-- "Important semantic distinction"): one Escape from ANY expanded state
-- goes straight to Glance, same as clicking X, never stepping backward
-- through Category -> Menu -> Glance the way GoBack/Back does. A no-op
-- from Glance is handled upstream - keyboard capture is only enabled
-- outside GLANCE (see Render), so Pockets never even sees this key there.
-- Shown only while an expanded state is open (see Initialize). Hiding it
-- programmatically must not count as an Escape press.
function Shell:SetEscapeCatcherShown(shown)
    local catcher = self.escapeCatcher
    if not catcher then
        return
    end
    if shown then
        catcher:Show()
    else
        catcher.suppress = true
        catcher:Hide()
        catcher.suppress = false
    end
end

function Shell:HandleEscape()
    self:SetState(self.STATE.GLANCE)
end

function Shell:OnDataChanged()
    if self.frame then
        self:Render()
    end
end

-- Resizes the root frame only - never touches its anchor (§1/§2/§15).
-- Since the frame is TOPLEFT-anchored, growing/shrinking always extends
-- right/down from that fixed point.
function Shell:ApplyDimensions(bodyHeight, includeFooter)
    self.expanded:SetSize(L.SHELL_WIDTH, TotalHeightForBody(bodyHeight, includeFooter))
end

-- Explicit body-clear lifecycle step (§7): hides every kind of body
-- content Shell can render (Menu rows, Category/All item buttons,
-- category labels) and resets scroll/content cursor state, so a state
-- transition never leaves the previous state's widgets visible behind
-- the new one. Called before every RenderMenu/RenderCategory/RenderAll,
-- regardless of whether they were reached via SetState or (RenderAll's
-- case) a direct search-box re-render.
function Shell:ClearBody()
    local shell = self.frame.shell
    for _, row in ipairs(shell.menuRows) do
        row:Hide()
    end
    for _, widget in ipairs(shell.categoryHeaders) do
        widget:Hide()
    end
    -- Category List rows are long-lived real item buttons (created once
    -- per index, reconfigured on each render from their own dedicated
    -- pool key) rather than Acquire/ReleaseAll'd per render like Grid's,
    -- so they're hidden explicitly instead of through the pool.
    for _, row in ipairs(shell.categoryListRows) do
        row:Hide()
    end
    Pockets.UI.LootLog:Hide(shell.lootView)
    Pockets.UI.ItemButtonPool:ReleaseAll(shell.content)
    Pockets.UI.ScrollBar:ScrollToTop(shell.scrollBar)
    shell.content:SetHeight(1)

    -- Search rows are long-lived (same reasoning as categoryListRows
    -- above), and searchPanel itself must not linger visible behind
    -- Menu/Category/All when leaving SEARCH.
    shell.searchPanel:Hide()
    for _, row in ipairs(shell.searchRows) do
        row:Hide()
    end
end

-- Cheap and idempotent - every Render* function below only reads
-- already-computed domain state (§14), so it's always safe to just call
-- this again rather than trying to patch up a half-drawn state.
-- Combat lockdown + protected item buttons: showing/hiding/anchoring/
-- re-binding them is forbidden, so layout work cannot happen in combat
-- (M2 §11-§17). The expanded view therefore works like a bag in combat:
-- it can be opened and closed (the frame is only shown/hidden) and items
-- can be used, but it shows the LAST laid-out view (kept ready by Prewarm
-- while idle). Navigation/search/layout changes wait for combat to end.
function Shell:IsCombatBlocked()
    return Pockets.UI.ItemButtonPool:IsStructurallyBlocked()
end

-- Guard for every layout function: in combat none of them may run (they
-- hide/anchor/resize frames in the protected buttons' chains). Marks a
-- re-render for combat end and keeps counts/stale flags fresh meanwhile.
-- Returns true when the caller must stop.
function Shell:DeferIfItemsBlocked()
    if not self:IsCombatBlocked() then
        return false
    end
    local pool = Pockets.UI.ItemButtonPool
    self.renderDeferred = true
    pool:ValidateAll()
    pool:RefreshCounts()
    return true
end

-- PLAYER_REGEN_ENABLED: repair secure bindings from current state, then
-- paint whatever was deferred.
function Shell:OnCombatEnded()
    self:UpdateCombatBindings()
    local pool = Pockets.UI.ItemButtonPool
    local hadDeferred = pool:Reconcile()
    if self.renderDeferred or hadDeferred then
        self.renderDeferred = false
        self:Render()
    end
end

-- Shows exactly one of root (Glance) / expanded for the current state.
-- Plain Show/Hide only - allowed in combat.
function Shell:ApplyVisibility()
    local showExpanded = self.state ~= self.STATE.GLANCE
    -- Insecure show/hide of these frames is blocked in combat; there only
    -- the secure controls (BuildSecureControls) change visibility.
    if self:IsCombatBlocked() then
        return
    end
    -- Expanded is hidden BEFORE root: its secure OnHide wrap shows root.
    if self.userHidden then
        self.expanded:Hide()
        self.root:Hide()
        return
    end
    if showExpanded then
        self.expanded:Show()
        self.root:Hide()
    else
        self.expanded:Hide()
        self.root:Show()
    end
end

-- In combat, visibility is changed only by the secure controls; state just
-- follows what is actually on screen.
function Shell:SyncStateFromVisibility()
    if self.expanded:IsShown() then
        local shown = self.displayedState
        if not shown or shown == self.STATE.GLANCE then
            shown = self.STATE.ALL
        end
        self.state = shown
        self.context = self.displayedContext or {}
        self.userHidden = false
        self.expandedVisible = true
    else
        self.state = self.STATE.GLANCE
        self.expandedVisible = false
    end
    self:SetEscapeCatcherShown(self.state ~= self.STATE.GLANCE)
end

function Shell:RenderInCombat()
    local pool = Pockets.UI.ItemButtonPool
    self.renderDeferred = true
    pool:ValidateAll()
    pool:RefreshCounts()
    self:SyncStateFromVisibility()
end

-- Secure show/hide controls (Forever, protected item buttons). Restricted
-- snippets may show/hide protected frames in combat; insecure code may not.
--   * PocketsSecureToggle: bound to the Toggle Full Inventory key(s) while
--     in combat (state driver below).
--   * "+" on Glance (open) and X on the expanded header (close): secure
--     overlays that exist only in combat, over the normal buttons.
--   * Escape: the expanded frame is in UISpecialFrames, so Blizzard's own
--     secure code hides it.
local TOGGLE_SNIPPET = [[
    local e = self:GetFrameRef("expanded")
    local r = self:GetFrameRef("root")
    local action = self:GetAttribute("pocketsaction") or "toggle"
    local open
    if action == "open" then
        open = true
    elseif action == "close" then
        open = false
    else
        open = not e:IsShown()
    end
    if open then
        e:Show()
        r:Hide()
    else
        e:Hide()
        r:Show()
    end
]]

function Shell:OnSecureToggle()
    self:SyncStateFromVisibility()
    self:Render()
end

local function MakeSecureClicker(name, parent, action)
    local b = CreateFrame("Button", name, parent, "SecureHandlerClickTemplate")
    b:SetFrameRef("expanded", Shell.expanded)
    b:SetFrameRef("root", Shell.root)
    b:SetAttribute("pocketsaction", action)
    b:SetAttribute("_onclick", TOGGLE_SNIPPET)
    b:RegisterForClicks("AnyUp")
    b:HookScript("PostClick", function() Shell:OnSecureToggle() end)
    return b
end

function Shell:BuildSecureControls()
    if not self.useSecure or not SecureHandlerWrapScript then
        return
    end

    local toggle = MakeSecureClicker("PocketsSecureToggle", UIParent, "toggle")
    toggle:SetSize(1, 1)
    self.secureToggle = toggle

    -- Whenever the expanded frame hides (X, Escape, toggle), Glance returns.
    SecureHandlerWrapScript(self.expanded, "OnHide", toggle,
        [[ local r = owner:GetFrameRef("root") if r then r:Show() end ]])
    self.expanded:HookScript("OnHide", function()
        if Shell:IsCombatBlocked() then
            Shell:Render()
        end
    end)
    table.insert(UISpecialFrames, "PocketsExpandedFrame")

    local function Overlay(target, action)
        if not target then
            return
        end
        local o = MakeSecureClicker(nil, target, action)
        o:SetAllPoints(target)
        o:SetFrameLevel(target:GetFrameLevel() + 10)
        o:Hide()
        RegisterStateDriver(o, "visibility", "[combat] show; hide")
    end
    Overlay(self.frame.glance.header.plusButton, "open")
    Overlay(self.frame.glance.bagRow, "open")
    for _, tab in ipairs(self.frame.glance.tabs) do
        Overlay(tab, "open")
    end
    Overlay(self.frame.shell.header.closeButton, "close")
    -- Back would need a re-layout to Menu; in combat it closes instead.
    Overlay(self.frame.shell.header.backButton, "close")

    -- Key binding -> secure toggle, active only in combat; out of combat
    -- the normal binding runs Pockets_ToggleFullInventory (full behavior).
    local driver = CreateFrame("Frame", "PocketsBindingDriver", UIParent, "SecureHandlerStateTemplate")
    driver:SetAttribute("_onstate-pcombat", [[
        if newstate == "combat" then
            for i = 1, 2 do
                local key = self:GetAttribute("key" .. i)
                if key then
                    self:SetBindingClick(true, key, "PocketsSecureToggle", "LeftButton")
                end
            end
        else
            self:ClearBindings()
        end
    ]])
    RegisterStateDriver(driver, "pcombat", "[combat] combat; nocombat")
    self.bindingDriver = driver
    self:UpdateCombatBindings()
end

-- Out of combat only (SetAttribute on a protected frame).
function Shell:UpdateCombatBindings()
    if not self.bindingDriver or Pockets.Adapters.CombatAPI:IsInCombat() then
        return
    end
    local key1, key2 = GetBindingKey("POCKETS_TOGGLE_FULL_INVENTORY")
    self.bindingDriver:SetAttribute("key1", key1)
    self.bindingDriver:SetAttribute("key2", key2)
end

-- Out-of-combat only: lay out All Items into the (hidden) expanded frame so
-- it is ready to be shown in combat. Cheap to skip; coalesced by
-- SchedulePrewarm.
function Shell:Prewarm()
    if self.state ~= self.STATE.GLANCE or self:IsCombatBlocked() or self.isDragging then
        return
    end
    local savedState, savedContext = self.state, self.context
    self.state, self.context = self.STATE.ALL, {}
    local ok, err = pcall(function()
        self:RenderExpandedContent(self.STATE.ALL)
    end)
    self.state, self.context = savedState, savedContext
    if ok then
        self.laidOutState, self.laidOutContext = self.STATE.ALL, {}
    elseif Pockets.Debug then
        Pockets.Debug:LogError("Shell Prewarm failed: " .. tostring(err))
    end
end

function Shell:SchedulePrewarm()
    if self.prewarmPending or not C_Timer then
        return
    end
    self.prewarmPending = true
    C_Timer.After(0.4, function()
        self.prewarmPending = false
        if self.state == self.STATE.GLANCE then
            self:Prewarm()
        end
    end)
end

function Shell:Render()
    -- Fully deferred while a drag is in progress (§1/§2/§15): WoW's
    -- StartMoving() is live-updating the frame's screen position from the
    -- cursor for as long as isDragging is true, and ANY resize while
    -- that's active (not just a stray SetPoint) can corrupt the final
    -- position StopMovingOrSizing() commits - see OnClick's note in
    -- Initialize for how a plain click can trigger this. self.state is
    -- still updated by SetState even when deferred; OnDragStop flushes a
    -- fresh Render() once the drag has fully settled.
    if self.isDragging then
        return
    end
    -- The Escape catcher is a plain (non-protected) frame, so it follows
    -- the state even in combat - Escape keeps working.
    self:SetEscapeCatcherShown(self.state ~= self.STATE.GLANCE)

    if self:IsCombatBlocked() then
        self:RenderInCombat()
        return
    end

    local state = self.state
    self.renderDeferred = false

    -- Single root position ownership (§1/§2): every state - GLANCE
    -- included - reapplies the exact same saved TOPLEFT anchor through
    -- the one PositionStrategy-backed function before anything else runs.
    -- The rest of Render only ever calls SetSize afterward, so a state
    -- transition can resize the frame but can never drift its origin.
    self:RestorePosition()
    self:ApplyVisibility()
    self.expandedVisible = state ~= self.STATE.GLANCE and not self.userHidden

    if state == self.STATE.GLANCE then
        self:SetEscapeCatcherShown(false)
        PHUI.ApplyBackdrop(self.root, { bgAlpha = L.GLANCE_ALPHA })
        self:RenderGlance()
        self:SchedulePrewarm()
        return
    end

    self:SetEscapeCatcherShown(true)
    self:RenderExpandedContent(state)
    self.displayedState, self.displayedContext = state, self.context
    self.laidOutState, self.laidOutContext = state, self.context
end

-- Lays out one expanded state into the expanded frame. Does not touch
-- visibility; used by Render and Prewarm.
function Shell:RenderExpandedContent(state)
    local frame = self.frame
    PHUI.ApplyBackdrop(self.expanded, { bgAlpha = L.EXPANDED_BODY_ALPHA })

    self:ConfigureHeader()

    -- Every branch here computes its own actual content height and calls
    -- ApplyDimensions itself (dynamic height pass) - none of them just
    -- claim a fixed/maximum height regardless of what's actually shown.
    if state == self.STATE.MENU then
        self:RenderMenu()
    elseif state == self.STATE.CATEGORY then
        self:RenderCategory(self.context.categoryID)
    elseif state == self.STATE.ALL then
        self:RenderAll(frame.shell.header.searchBox:GetText())
    elseif state == self.STATE.SEARCH then
        self:RenderSearch()
    elseif state == self.STATE.LOOT then
        self:RenderLoot()
    end

    -- "No footer" is Quick Search's own explicit layout rule (product
    -- intent - it must never look like another inventory-browsing
    -- surface); every other expanded state keeps the shared footer.
    --
    -- scrollFrame (and our own compact scrollbar it owns) is hidden right
    -- alongside it - Search uses its own non-scrolling searchPanel
    -- instead, but scrollFrame's rect overlaps that panel (both anchored
    -- under header), and a scrollbar left shown from a previous Menu/
    -- Category/All visit rendered its thumb straight over Search's
    -- header/input (native scrollbar bug pass).
    if state == self.STATE.SEARCH then
        frame.shell.footer:Hide()
        frame.shell.scrollFrame:Hide()
        Pockets.UI.ScrollBar:Update(frame.shell.scrollBar, 0, 0)
    else
        frame.shell.footer:Show()
        frame.shell.scrollFrame:Show()
        self:ConfigureFooter()
    end
end

--------------------------------------------------
-- GLANCE
--------------------------------------------------

function Shell:RenderGlance()
    if self:DeferIfItemsBlocked() then
        return
    end
    -- Values only: the HUD's size and anchor never change here.
    Pockets.UI.PocketsGlance:Render(self.frame.glance)
end

--------------------------------------------------
-- Header (§3 header contracts)
--------------------------------------------------

-- Fixed title left offset (past the back-button zone) - a constant, not
-- derived from header.backButton's actual rendered position, so the
-- title never shifts based on whether/how the back button happens to be
-- configured (§6 "give the title its own stable region or stable
-- x-offset"). Every expanded state shows the back button now (§4), but
-- the offset is a constant on principle regardless.
local TITLE_LEFT_OFFSET = L.SHELL_PADDING + L.SHELL_HEADER_SIDE_WIDTH + 4

-- Reserves BOTH the contextual-action zone AND the always-present X zone,
-- regardless of which contextual control (if any) is actually shown -
-- the title must never move based on which contextual controls exist
-- (top-bar/close pass §"TOP BAR").
local TITLE_RIGHT_OFFSET = L.SHELL_PADDING + L.SHELL_HEADER_CLOSE_WIDTH + L.SHELL_HEADER_ACTION_GAP
    + L.SHELL_HEADER_RIGHT_WIDTH

-- Reconfigures the ONE header (left/title/right zones never move, only
-- what occupies them does - §4, §6). The back button is a single
-- reused widget whose onClick (Shell:GoBack, wired once in BuildShell)
-- already resolves MENU -> GLANCE, CATEGORY -> MENU, and ALL -> MENU via
-- the same ESCAPE_PARENT map GoBack uses. X (close), by contrast, always
-- dismisses straight to Glance (Shell:SetState(GLANCE), wired once in
-- BuildShell) - Back = navigate up, X/Escape = dismiss Pockets.
function Shell:ConfigureHeader()
    local header = self.frame.shell.header
    local state = self.state

    header.backButton:Show()
    header.closeButton:Show()
    header.titleText:ClearAllPoints()
    header.titleText:SetPoint("LEFT", header, "LEFT", TITLE_LEFT_OFFSET, 0)
    header.titleText:SetPoint("RIGHT", header, "RIGHT", -TITLE_RIGHT_OFFSET, 0)

    if state == self.STATE.MENU then
        header.titleText:SetText("Pockets")
        header.plusButton:Show()
        header.lootButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.CATEGORY then
        header.titleText:SetText(Constants.CATEGORY_LABEL[self.context.categoryID] or "")
        header.plusButton:Show()
        header.lootButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.ALL then
        header.titleText:SetText("All")
        header.plusButton:Hide() -- already in All Items - its slot becomes Search (§3)
        header.lootButton:Hide() -- the search box occupies that zone
        header.searchBox:Show()
    elseif state == self.STATE.LOOT then
        -- Just [ < ] Loot Log [ X ] - nothing contextual.
        header.titleText:SetText("Loot Log")
        header.plusButton:Hide()
        header.lootButton:Hide()
        header.searchBox:Hide()
    elseif state == self.STATE.SEARCH then
        -- No contextual action here (Glance Quick Search pass) - just
        -- [ < ] Search [ X ]. header.searchBox is All Items' OWN search
        -- field, not this one; Quick Search has its own dedicated
        -- EditBox in searchPanel (see RenderSearch).
        header.titleText:SetText("Search")
        header.plusButton:Hide()
        header.lootButton:Hide()
        header.searchBox:Hide()
    end
end

--------------------------------------------------
-- MENU (§3 STATE 2)
--------------------------------------------------

function Shell:RenderMenu()
    if self:DeferIfItemsBlocked() then
        return
    end
    self:ClearBody()
    local shell = self.frame.shell
    local content = shell.content

    -- Zero-count categories are absent, not shown as empty rows (§10) -
    -- Menu's height (and thus, in practice, whether it can ever overflow
    -- at all) is entirely a function of how many categories are actually
    -- visible right now, never the fixed full taxonomy.
    local visible = {}
    for _, entry in ipairs(Pockets.API.GetCategorySummary()) do
        if entry.count > 0 then
            table.insert(visible, entry)
        end
    end

    local rowWidth = BodyViewportWidth()
    local contentHeight = #visible * L.LIST_ROW_HEIGHT
    local usedContentHeight, bodyHeight = ResolveDynamicHeight(contentHeight, MaxListContentHeight(), 0)

    self:ApplyDimensions(bodyHeight)
    content:SetWidth(rowWidth)

    local y = 0
    for index, entry in ipairs(visible) do
        local row = shell.menuRows[index]
        if not row then
            row = CreateMenuRow(content, rowWidth)
            shell.menuRows[index] = row
        end

        row.categoryID = entry.categoryID
        row.icon:SetTexture(entry.icon)
        row.label:SetText(entry.label)
        row.count:SetText(tostring(entry.count))
        row:SetWidth(rowWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetScript("OnClick", function()
            Shell:SetState(Shell.STATE.CATEGORY, { categoryID = entry.categoryID })
        end)
        row:Show()

        y = y + L.LIST_ROW_HEIGHT
    end

    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
end

--------------------------------------------------
-- CATEGORY (§3 STATE 3) - one navigation state, two body presentations
-- (Category List/Grid view pass). Header/footer/root/navigation/capacity
-- status stay identical between them; only the body renderer differs.
--------------------------------------------------

-- Dispatches to whichever body renderer the persisted preference names,
-- falling back to Grid for anything else (matches the SavedVariables
-- validation in Events.lua - belt and suspenders against a bad value).
-- ClearBody runs exactly once here, before either renderer, so switching
-- Grid<->List (or Menu/All -> Category) never leaves the other
-- presentation's widgets on screen.
function Shell:RenderCategory(categoryID)
    if self:DeferIfItemsBlocked() then
        return
    end
    self:ClearBody()
    if Pockets.SavedSettings.categoryViewMode == Constants.CATEGORY_VIEW_MODE.LIST then
        self:RenderCategoryList(categoryID)
    else
        self:RenderCategoryGrid(categoryID)
    end
end

-- Persists the Category view preference and, if Category is currently
-- the visible state, re-renders it immediately - no reload, no state
-- transition, no anchor/header/footer change (§2, §11).
function Shell:SetCategoryViewMode(mode)
    local Mode = Constants.CATEGORY_VIEW_MODE
    if mode ~= Mode.GRID and mode ~= Mode.LIST then
        return
    end
    Pockets.SavedSettings.categoryViewMode = mode
    if self.frame and self.state == self.STATE.CATEGORY then
        self:RenderCategory(self.context.categoryID)
    end
end

-- Grid: unchanged from before this pass (§4 "preserve exactly") - same
-- pooled real item-button component All Items uses.
function Shell:RenderCategoryGrid(categoryID)
    if self:DeferIfItemsBlocked() then
        return
    end
    local shell = self.frame.shell
    local content = shell.content
    local pool = Pockets.UI.ItemButtonPool

    local items = Pockets.API.GetAggregatedCategoryItems(categoryID)

    -- Width is a constant (BodyViewportWidth) regardless of whether a
    -- scrollbar ends up showing (scrollbar redesign pass - our compact bar
    -- lives in the existing padding gutter, never a reserved column), so
    -- column count/grid width never changes when one appears.
    local usableWidth = BodyViewportWidth()

    local plan = FlowLayout:PlanFlat(#items, { rowWidth = usableWidth, itemSize = L.ITEM_BUTTON_SIZE, gap = L.ITEM_BUTTON_GAP })

    local usedContentHeight, bodyHeight = ResolveDynamicHeight(plan.contentHeight)
    self:ApplyDimensions(bodyHeight)
    content:SetWidth(usableWidth)

    Pockets.UI.ItemGrid:Render(pool, content, items,
        { x = 0, y = 0, width = usableWidth, itemSize = L.ITEM_BUTTON_SIZE, gap = L.ITEM_BUTTON_GAP })

    content:SetHeight(math.max(plan.contentHeight, 1))
    SetScrollBarShown(shell, plan.contentHeight, usedContentHeight)
end

-- List: one row per aggregate item - [icon] [full name] [total qty] -
-- same compact grammar as Menu rows (§5). The row itself IS the real
-- item button (ItemButtonPool.Configure wires it, same as Grid), just
-- resized/reparented so the whole row - not only the icon - is the
-- interaction target (§8), with name/qty labels anchored onto it.
local function CreateCategoryListRow(poolAnchor)
    local row = Pockets.UI.ItemButtonPool:Acquire(poolAnchor)
    row:SetHeight(L.LIST_ROW_HEIGHT)

    if not row.categoryListInitialized then
        row.categoryListInitialized = true

        -- The button's OWN icon/border regions default to filling the
        -- whole button (fine at Grid's fixed 40x40) - re-anchored to a
        -- small square on the left so widening the row (below) doesn't
        -- stretch the item art across the whole row.
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", L.LIST_ROW_PADDING, 0)
        row.icon:SetSize(L.LIST_ICON_SIZE, L.LIST_ICON_SIZE)
        if row.IconBorder then
            row.IconBorder:ClearAllPoints()
            row.IconBorder:SetAllPoints(row.icon)
        end
        -- ItemButtonTemplate's own slot-border art (NormalTexture) also
        -- defaults to SetAllPoints(button) - left alone, it stretches
        -- into a long repeating slot-frame graphic across the wide row.
        -- List rows use plain Menu-style rows with no button chrome, so
        -- it's just made invisible rather than reanchored to nothing
        -- useful. Both SetNormalTexture(nil) AND Texture:SetTexture(nil)
        -- throw "Usage: self:SetNormalTexture(asset)" on this client -
        -- SetColorTexture(0,0,0,0) (fully transparent, plain numeric
        -- args, no asset-path validation) is what actually works.
        -- pcall'd regardless, so any further texture-API surprise here
        -- can never crash a render/EventBus subscriber again.
        pcall(function()
            local normalTexture = row.GetNormalTexture and row:GetNormalTexture()
            if normalTexture then
                normalTexture:SetColorTexture(0, 0, 0, 0)
            end
            local pushedTexture = row.GetPushedTexture and row:GetPushedTexture()
            if pushedTexture then
                pushedTexture:SetColorTexture(0, 0, 0, 0)
            end
        end)
        -- HighlightTexture is left alone deliberately - it already
        -- covers the full (now row-width) button via SetAllPoints,
        -- giving a whole-row hover glow for free, matching Menu rows'
        -- own hover highlight.

        row.name = PHUI.CreateLabel(row, "primary", nil, PHUI.Fonts.SMALL)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", L.LIST_ROW_GAP, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        -- Item rows never navigate deeper (§7), so - unlike Menu rows -
        -- they don't reserve a trailing chevron column: that was 20px of
        -- permanently dead space on every row, worse once a scrollbar
        -- narrows the row further (wasted-space pass). qty sits flush
        -- against the row's own right edge instead, reclaiming that
        -- width for the name column.
        row.qty = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.SMALL)
        row.qty:SetPoint("RIGHT", row, "RIGHT", -L.LIST_ROW_PADDING, 0)
        row.qty:SetWidth(L.LIST_ROW_COUNT_WIDTH)
        row.qty:SetJustifyH("RIGHT")

        row.name:SetPoint("RIGHT", row.qty, "LEFT", -L.LIST_ROW_GAP, 0)
    end

    return row
end

function Shell:RenderCategoryList(categoryID)
    if self:DeferIfItemsBlocked() then
        return
    end
    local shell = self.frame.shell
    local content = shell.content

    local items = Pockets.API.GetAggregatedCategoryItems(categoryID)

    -- Height-management pass: capped by row COUNT
    -- (MAX_VISIBLE_LIST_ROWS, shared with Menu), not the generic
    -- Grid/All pixel budget (SHELL_BODY_MAX_HEIGHT) - whole rows should
    -- be visible before a scrollbar appears, never however many happen
    -- to fit under an unrelated pixel cap. Fixed row height makes this
    -- pure arithmetic, no FlowLayout call needed. Width is a constant
    -- (dynamic height pass - see RenderCategoryGrid's note).
    local rowWidth = BodyViewportWidth()
    local contentHeight = #items * L.LIST_ROW_HEIGHT
    local usedContentHeight, bodyHeight = ResolveDynamicHeight(contentHeight, MaxListContentHeight(), 0)

    self:ApplyDimensions(bodyHeight)
    content:SetWidth(rowWidth)

    for index, item in ipairs(items) do
        local row = shell.categoryListRows[index]
        if not row then
            row = CreateCategoryListRow(shell.categoryListPoolAnchor)
            shell.categoryListRows[index] = row
        end

        row:SetWidth(rowWidth)
        row.name:SetText(item.name or item.itemLink or ("item:" .. tostring(item.itemID)))
        local qualityColor = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if qualityColor and item.quality > 1 then
            row.name:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b)
        else
            PHUI.ApplyTextStyle(row.name, "primary")
        end
        row.qty:SetText(tostring(item.quantity))

        Pockets.UI.ItemButtonPool:Configure(row, item)
        -- Configure() shows the button's own built-in stack-count badge
        -- (anchored to the button's own corner, meant for a 40x40 square
        -- button) - redundant and badly placed on a wide row that
        -- already has its own right-aligned qty column above.
        if row.Count then
            row.Count:Hide()
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * L.LIST_ROW_HEIGHT)
        row:Show()
    end

    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
end

--------------------------------------------------
-- SEARCH (Glance Quick Search) - Glance -> Search -> interact -> Glance.
-- Deliberately NOT inventory browsing: no footer, no scrollbar, at most
-- SEARCH_MAX_RESULT_ROWS rows ever shown; 3+ matches collapses to compact
-- centered feedback instead of ever becoming a second item grid. Result
-- rows reuse CreateCategoryListRow/ItemButtonPool - the same real secure
-- item buttons Category List uses - so tooltip/click/drag/split/quantity
-- all work identically with no second interaction implementation.
--------------------------------------------------

function Shell:RenderSearch()
    if self:DeferIfItemsBlocked() then
        return
    end
    -- GLANCE's own transition just hides the whole `shell` frame (§1/§2 -
    -- see Render) rather than releasing its children, so Menu/Category/
    -- All content from an earlier visit stays :Show()n underneath and
    -- reappears the moment `shell` is shown again for Search unless it's
    -- explicitly cleared - done once in SetState's enteringSearch branch
    -- (not here - this runs on every keystroke too, and re-clearing the
    -- body on every keystroke drops the search box's own keyboard focus,
    -- see SetState's comment).
    local shell = self.frame.shell
    local panel = shell.searchPanel
    panel:Show()

    local rowWidth = BodyViewportWidth()
    panel:SetWidth(rowWidth)

    local query = panel.editBox:GetText()
    local matches, totalCount
    if query == "" then
        matches, totalCount = {}, 0
    else
        -- Cached/aggregated snapshot only (product intent "PERFORMANCE") -
        -- never a bag rescan or categorization pass on keystroke.
        matches, totalCount = Pockets.UI.Search:RankedItemMatches(Pockets.API.GetAllAggregatedItems(), query)
    end

    for _, row in ipairs(shell.searchRows) do
        row:Hide()
    end
    panel.feedbackPrimary:Hide()
    panel.feedbackSecondary:Hide()
    panel.overflowLabel:Hide()

    local extraHeight
    if query == "" then
        -- Blank field: no rows, no feedback (product intent "No
        -- persistent empty body height").
        extraHeight = 0
    elseif totalCount == 0 then
        panel.feedbackPrimary:SetText("No items found")
        panel.feedbackPrimary:Show()
        extraHeight = L.SEARCH_ROW_GAP + L.SEARCH_FEEDBACK_LINE_HEIGHT
    elseif totalCount > L.SEARCH_OVERFLOW_LIMIT then
        -- Too many matches even to list a trailer count usefully -
        -- deliberately restrictive (product intent) - nudge the player to
        -- narrow the query instead of ever becoming another item grid.
        panel.feedbackPrimary:SetText(string.format("%d items found", totalCount))
        panel.feedbackSecondary:SetText("Keep typing...")
        panel.feedbackPrimary:Show()
        panel.feedbackSecondary:Show()
        extraHeight = L.SEARCH_ROW_GAP + L.SEARCH_FEEDBACK_LINE_HEIGHT
            + L.SEARCH_FEEDBACK_LINE_GAP + L.SEARCH_FEEDBACK_LINE_HEIGHT
    else
        local shownCount = math.min(totalCount, L.SEARCH_MAX_RESULT_ROWS)
        for index = 1, shownCount do
            local item = matches[index]
            local row = shell.searchRows[index]
            if not row then
                row = CreateCategoryListRow(shell.searchPoolAnchor)
                shell.searchRows[index] = row
            end

            row:SetWidth(rowWidth)
            row.name:SetText(item.name or item.itemLink or ("item:" .. tostring(item.itemID)))
            local qualityColor = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
            if qualityColor and item.quality > 1 then
                row.name:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b)
            else
                PHUI.ApplyTextStyle(row.name, "primary")
            end
            row.qty:SetText(tostring(item.quantity))

            Pockets.UI.ItemButtonPool:Configure(row, item)
            -- Same reasoning as RenderCategoryList: the button's own
            -- corner count badge is redundant next to the row's qty
            -- column.
            if row.Count then
                row.Count:Hide()
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 0,
                -(L.SEARCH_INPUT_HEIGHT + L.SEARCH_ROW_GAP + (index - 1) * L.LIST_ROW_HEIGHT))
            row:Show()
        end

        extraHeight = L.SEARCH_ROW_GAP + shownCount * L.LIST_ROW_HEIGHT
        local remaining = totalCount - shownCount
        if remaining > 0 then
            panel.overflowLabel:SetText(string.format("and %d more. Keep typing to filter.", remaining))
            panel.overflowLabel:ClearAllPoints()
            panel.overflowLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", L.LIST_ROW_PADDING,
                -(L.SEARCH_INPUT_HEIGHT + L.SEARCH_ROW_GAP + shownCount * L.LIST_ROW_HEIGHT + L.SEARCH_ROW_GAP))
            panel.overflowLabel:Show()
            extraHeight = extraHeight + L.SEARCH_ROW_GAP + L.SEARCH_FEEDBACK_LINE_HEIGHT
        end
    end

    local contentHeight = L.SEARCH_INPUT_HEIGHT + extraHeight
    panel:SetHeight(contentHeight)
    self:ApplyDimensions(contentHeight + L.SHELL_PADDING * 2, false)
end

--------------------------------------------------
-- ALL ITEMS (§3 STATE 4) - categorized dynamic flow + search, ported
-- from the previous FullInventory window onto Shell's shared body.
--------------------------------------------------

-- OnClick is NOT set here - a pooled index's categoryID can change
-- between renders (categories appear/disappear), so the caller must
-- reassign it every render (same reasoning CreateMenuRow's onClick gets
-- reassigned in RenderMenu, not just at creation).
local function EnsureCategoryHeader(content, headers, index)
    local widget = headers[index]
    if widget then
        return widget
    end

    widget = Pockets.UI.CategoryHeader:Create(content, {
        width = BodyViewportWidth(),
        height = L.CATEGORY_HEADER_HEIGHT,
    })
    headers[index] = widget
    return widget
end

-- Recent is capped tighter than every other category (§ "what did I just
-- pick up", not another full category to browse) - API.GetAggregatedCategoryItems
-- already returns Recent newest-first/deduped-by-itemID, so this is a
-- plain slice, not a re-sort.
local function BuildCategorySections()
    local sections = {}
    for _, categoryID in ipairs(Constants.CATEGORY_ORDER) do
        local items = Pockets.API.GetAggregatedCategoryItems(categoryID)
        if categoryID == Constants.CATEGORY.RECENT and #items > L.FULL_INVENTORY_RECENT_LIMIT then
            local capped = {}
            for i = 1, L.FULL_INVENTORY_RECENT_LIMIT do
                capped[i] = items[i]
            end
            items = capped
        end
        if #items > 0 then
            table.insert(sections, {
                categoryID = categoryID,
                label = Constants.CATEGORY_LABEL[categoryID],
                buttonRecords = items,
            })
        end
    end
    return sections
end

-- Pure sequential layout (no widget creation): every category always
-- starts a fresh row (Full Inventory redesign - the old <50%-inline
-- packing heuristic is gone). Header -> ITEM_BUTTON_GAP -> its own grid
-- (if expanded) -> PHUI.Spacing.PANEL_PADDING -> next header.
local function PlanCategorySections(sections, collapsedByID, rowWidth)
    local cursorY = 0
    local placements = {}
    for i, section in ipairs(sections) do
        if i > 1 then
            cursorY = cursorY + PHUI.Spacing.PANEL_PADDING
        end
        local headerY = cursorY
        cursorY = cursorY + L.CATEGORY_HEADER_HEIGHT

        local collapsed = collapsedByID[section.categoryID] and true or false
        local gridY, gridHeight, gridPlan
        if not collapsed then
            gridY = cursorY + L.ITEM_BUTTON_GAP
            gridPlan = FlowLayout:PlanFlat(#section.buttonRecords,
                { rowWidth = rowWidth, itemSize = L.ITEM_BUTTON_SIZE, gap = L.ITEM_BUTTON_GAP })
            gridHeight = gridPlan.contentHeight
            cursorY = gridY + gridHeight
        end

        table.insert(placements, {
            categoryID = section.categoryID,
            headerY = headerY,
            collapsed = collapsed,
            gridY = gridY,
            gridHeight = gridHeight,
        })
    end
    return { contentHeight = cursorY, placements = placements }
end

-- Flat, name-matching aggregate list across every category (no
-- per-category grouping) - the "temporarily flatten" search mode (§11).
local function BuildFlatSearchResults(query)
    local Search = Pockets.UI.Search
    local out = {}
    local seen = {}
    for _, categoryID in ipairs(Constants.CATEGORY_ORDER) do
        for _, item in ipairs(Pockets.API.GetAggregatedCategoryItems(categoryID)) do
            if Search:Matches(item, query) and not seen[item.itemID] then
                seen[item.itemID] = true
                table.insert(out, item)
            end
        end
    end
    return out
end

function Shell:RenderAll(query)
    if self:DeferIfItemsBlocked() then
        return
    end
    self:ClearBody()
    local shell = self.frame.shell
    local content = shell.content
    local pool = Pockets.UI.ItemButtonPool

    local itemSize = L.ITEM_BUTTON_SIZE
    local gap = L.ITEM_BUTTON_GAP
    local hasQuery = query ~= nil and query ~= ""

    -- Width is a constant (BodyViewportWidth), not read off the live frame
    -- (dynamic height pass - RenderAll can also be called directly from
    -- the search box, bypassing Shell:Render(), so it must be able to
    -- size itself unconditionally here too) - and, since the scrollbar
    -- redesign pass, it never narrows based on whether a scrollbar ends up
    -- showing (our compact bar lives in the existing padding gutter, never
    -- a reserved column), so column count/grid width never changes when
    -- one appears.
    local usableWidth = BodyViewportWidth()

    if hasQuery then
        local items = BuildFlatSearchResults(query)
        local plan = FlowLayout:PlanFlat(#items, { rowWidth = usableWidth, itemSize = itemSize, gap = gap })
        local usedContentHeight, bodyHeight = ResolveDynamicHeight(plan.contentHeight)
        self:ApplyDimensions(bodyHeight)
        content:SetWidth(usableWidth)

        Pockets.UI.ItemGrid:Render(pool, content, items, { x = 0, y = 0, width = usableWidth, itemSize = itemSize, gap = gap })
        content:SetHeight(math.max(plan.contentHeight, 1))
        SetScrollBarShown(shell, plan.contentHeight, usedContentHeight)
        return
    end

    -- Categorized flow (Full Inventory redesign): every category always
    -- starts a fresh row (no <50%-width inline packing).
    local sections = BuildCategorySections()
    local collapsedByID = Pockets.CharDB.collapsedCategories

    local plan = PlanCategorySections(sections, collapsedByID, usableWidth)
    local usedContentHeight, bodyHeight = ResolveDynamicHeight(plan.contentHeight)
    self:ApplyDimensions(bodyHeight)
    content:SetWidth(usableWidth)

    local buttonRecordsByCategoryID = {}
    for _, section in ipairs(sections) do
        buttonRecordsByCategoryID[section.categoryID] = section.buttonRecords
    end

    for index, placement in ipairs(plan.placements) do
        local categoryID = placement.categoryID
        local section = sections[index]
        local header = EnsureCategoryHeader(content, shell.categoryHeaders, index)
        header:SetScript("OnClick", function()
            collapsedByID[categoryID] = not collapsedByID[categoryID]
            Shell:RenderAll(query)
        end)
        header:SetWidth(usableWidth)
        header:SetLabel(section.label, #section.buttonRecords)
        header:SetCollapsed(placement.collapsed)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -placement.headerY)
        header:Show()

        if not placement.collapsed then
            Pockets.UI.ItemGrid:Render(pool, content, buttonRecordsByCategoryID[categoryID],
                { x = 0, y = placement.gridY, width = usableWidth, itemSize = itemSize, gap = gap })
        end
    end

    content:SetHeight(math.max(plan.contentHeight, 1))
    SetScrollBarShown(shell, plan.contentHeight, usedContentHeight)
end

--------------------------------------------------
-- Footer (shared by MENU/CATEGORY/ALL)
--------------------------------------------------

-- Measure-after-set + resize, same pattern established elsewhere
-- (EnsureCategoryHeader/the old EnsureCategoryLabel) - a MetricRow's
-- width isn't known until its text is set, and footer metrics are laid
-- out left-to-right by actual measured width, not a fixed column.
local function ResizeFooterMetric(row)
    row:SetWidth(L.GLANCE_METRIC_ICON_SIZE + L.GLANCE_METRIC_ICON_TEXT_GAP + (row.primaryText:GetStringWidth() or 0))
end

function Shell:ConfigureFooter()
    local shell = self.frame.shell
    local InventoryState = Pockets.Services.InventoryState

    local capacity = InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)
    shell.footerBagRow:SetPrimary(string.format("%d/%d", capacity.used, capacity.total))
    shell.footerBagRow:SetPrimaryColor(color.r, color.g, color.b)
    ResizeFooterMetric(shell.footerBagRow)

    shell.footerGoldRow:SetPrimary(Pockets.UI.MoneyFormat:Format(Pockets.Adapters.MoneyAPI:GetMoney()))
    ResizeFooterMetric(shell.footerGoldRow)
    shell.footerGoldRow:ClearAllPoints()
    -- Same gap the Gold icon already keeps against ITS OWN text
    -- (GLANCE_METRIC_ICON_TEXT_GAP) - using the smaller ACTION_GAP here
    -- left the coin sitting lopsided: barely any breathing room after
    -- Bag's count, then a bigger gap before Gold's own text.
    shell.footerGoldRow:SetPoint("LEFT", shell.footerBagRow, "RIGHT", L.GLANCE_METRIC_ICON_TEXT_GAP, 0)

    local ammoCapacity = InventoryState:GetAmmoCapacity()
    if self:ShouldShowAmmoRow(ammoCapacity) then
        shell.footerAmmoRow:SetPrimary(string.format("%d/%d", ammoCapacity.used, ammoCapacity.total))
        ResizeFooterMetric(shell.footerAmmoRow)
        shell.footerAmmoRow:Show()
    else
        shell.footerAmmoRow:Hide()
    end
end

--------------------------------------------------
-- LOOT LOG
--------------------------------------------------

-- Opens Loot Log from the current state, remembering where to return.
-- Opened from Loot Log itself is a no-op (button is hidden there anyway).
function Shell:OpenLootLog()
    if self.state == self.STATE.LOOT then
        return
    end
    self:SetState(self.STATE.LOOT, { returnState = self.state, returnContext = self.context })
end

function Shell:RenderLoot()
    if self:DeferIfItemsBlocked() then
        return
    end
    local shell = self.frame.shell
    local content = shell.content

    -- A re-render while already viewing the log (new event, item cache
    -- resolved) keeps the player's scroll position; opening starts at the
    -- top, i.e. the newest entries. At offset 0 a new entry therefore
    -- stays visible by construction.
    local keepOffset = self.lootRendered and shell.scrollFrame:GetVerticalScroll() or 0

    self:ClearBody()

    local rowWidth = BodyViewportWidth()
    local entries = Pockets.Services.LootLog:GetEntries()
    local contentHeight = Pockets.UI.LootLog:Render(shell.lootView, entries, rowWidth)
    local usedContentHeight, bodyHeight = ResolveDynamicHeight(contentHeight)

    self:ApplyDimensions(bodyHeight)
    content:SetWidth(rowWidth)
    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
    if keepOffset > 0 then
        Pockets.UI.ScrollBar:SetScroll(shell.scrollBar, keepOffset)
    end
    self.lootRendered = true
end

-- Coalesces bursts (AoE loot, container opens, quest turn-ins) into one
-- re-render shortly after the last event, and does nothing at all while
-- Loot Log isn't the visible state - the log stays lightweight hidden.
local LOOT_REFRESH_DELAY = 0.1
function Shell:RefreshLootLog()
    if not self.frame or self.state ~= self.STATE.LOOT or self.lootRefreshPending then
        return
    end
    self.lootRefreshPending = true
    C_Timer.After(LOOT_REFRESH_DELAY, function()
        self.lootRefreshPending = false
        if self.state == self.STATE.LOOT then
            self:Render()
        end
    end)
end

--------------------------------------------------
-- Visibility (independent of state - /pockets show)
--------------------------------------------------

function Shell:Show()
    if self.frame and not self:IsCombatBlocked() then
        self.userHidden = false
        self:ApplyVisibility()
    end
end

function Shell:Hide()
    if self.frame and not self:IsCombatBlocked() then
        self.userHidden = true
        self:ApplyVisibility()
        self.expandedVisible = false
    end
end

function Shell:Toggle()
    if not self.frame then
        return
    end
    if self.userHidden then
        self:Show()
    else
        self:Hide()
    end
end

-- Shift-B / the old "expand" action jump directly to All Items (§4),
-- closing to Glance if All Items is already open.
function Shell:ToggleAllItems()
    -- In combat there is no re-layout to step back to Menu: toggling closes.
    if self:IsCombatBlocked() and self.state ~= self.STATE.GLANCE then
        self:SetState(self.STATE.GLANCE)
    elseif self.state == self.STATE.ALL then
        self:SetState(self.STATE.GLANCE)
    else
        self:SetState(self.STATE.ALL)
    end
end
