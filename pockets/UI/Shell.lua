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

local _, Pockets = ...

Pockets.UI.Shell = Pockets.UI.Shell or {}
local Shell = Pockets.UI.Shell

local Layout = Pockets.UI.Layout
local Constants = Pockets.Constants
local L = Constants.LAYOUT
local FlowLayout = Pockets.UI.FlowLayout
local PositionStrategy = Pockets.UI.PositionStrategy

Shell.STATE = {
    GLANCE = "GLANCE",
    MENU = "MENU",
    CATEGORY = "CATEGORY",
    ALL = "ALL",
}

-- Escape hierarchy (§4): CATEGORY/ALL -> MENU -> GLANCE -> no-op.
local ESCAPE_PARENT = {
    [Shell.STATE.CATEGORY] = Shell.STATE.MENU,
    [Shell.STATE.ALL] = Shell.STATE.MENU,
    [Shell.STATE.MENU] = Shell.STATE.GLANCE,
}

-- Root total height for a given body height (UI layout pass §6): every
-- expanded state's body height is computed dynamically from actual
-- content (visible category count for Menu, laid-out items for
-- Category/All) - the shared invariant is TOPLEFT/width/header/footer
-- stability, not identical total height.
local function TotalHeightForBody(bodyHeight)
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
local function ResolveDynamicHeight(contentHeight, maxContentHeight)
    maxContentHeight = maxContentHeight or MaxContentHeight()
    local needsScrollbar = contentHeight > maxContentHeight
    local usedContentHeight = needsScrollbar and maxContentHeight or math.max(contentHeight, MinContentHeight())
    return usedContentHeight, usedContentHeight + L.SHELL_PADDING * 2, needsScrollbar
end

-- Conditional scrollbar (UI polish pass §4): shows/hides the REAL
-- Blizzard scrollbar widget UIPanelScrollFrameTemplate creates as
-- "<name>ScrollBar" - callers are responsible for sizing `content` to
-- leave (or not leave) room for it. Never just disabled/left as an empty
-- track - hidden entirely means zero layout width consumed.
local function SetScrollBarShown(scrollFrame, shown)
    local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
    if not scrollBar then
        return
    end
    if shown then
        scrollBar:Show()
    else
        scrollBar:Hide()
    end
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

-- Compact always-visible HUD: icon left, "59 / 76" / "13m" stacked to
-- its right, both vertically centered against the icon (LEFT-anchoring
-- textBlock to icon's RIGHT centers it automatically). No header, no
-- Ammo (Glance compactness pass) - just the two numbers the frame exists
-- to answer.
function Shell:BuildGlance()
    local frame = self.frame
    local glance = CreateFrame("Frame", nil, frame)
    glance:SetAllPoints(frame)
    frame.glance = glance

    glance.icon = glance:CreateTexture(nil, "ARTWORK")
    glance.icon:SetSize(L.GLANCE_ICON_SIZE, L.GLANCE_ICON_SIZE)
    glance.icon:SetPoint("LEFT", glance, "LEFT", L.GLANCE_PADDING, 0)
    glance.icon:SetTexture(Constants.HUD_ICON)
    glance.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    glance.textBlock = CreateFrame("Frame", nil, glance)
    glance.textBlock:SetPoint("LEFT", glance.icon, "RIGHT", L.GLANCE_TEXT_GAP_X, 0)
    glance.textBlock:SetSize(L.GLANCE_TEXT_BLOCK_WIDTH, L.GLANCE_ICON_SIZE)

    glance.capacityText = PHUI.CreateLabel(glance.textBlock, "primary", nil, PHUI.Fonts.NORMAL)
    glance.capacityText:SetPoint("TOPLEFT", glance.textBlock, "TOPLEFT", 0, 0)
    glance.capacityText:SetJustifyH("LEFT")

    glance.etaText = PHUI.CreateLabel(glance.textBlock, "muted", nil, PHUI.Fonts.SMALL)
    glance.etaText:SetPoint("TOPLEFT", glance.capacityText, "BOTTOMLEFT", 0, -L.GLANCE_TEXT_GAP_Y)
    glance.etaText:SetJustifyH("LEFT")
end

function Shell:BuildShell()
    local frame = self.frame
    local shell = CreateFrame("Frame", nil, frame)
    -- shell fills frame's rect exactly - frame itself is the one thing
    -- Shell:ApplyDimensions ever resizes (§3 "one logical root frame").
    shell:SetAllPoints(frame)
    frame.shell = shell
    shell.menuRows = {}
    shell.categoryLabels = {}
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

    header.titleText = PHUI.CreateLabel(header, "primary", "Pockets", PHUI.Fonts.NORMAL)
    header.titleText:SetJustifyH("LEFT")
    header.titleText:SetWordWrap(false)

    header.plusButton = PHUI.CreateIconButton(header, 20, nil, {
        tooltipText = "All Items",
        onClick = function() Shell:SetState(Shell.STATE.ALL) end,
    })
    header.plusButton:SetPoint("RIGHT", header, "RIGHT", -L.SHELL_PADDING, 0)
    header.plusButton.glyph = PHUI.CreateLabel(header.plusButton, "primary", "+", PHUI.Fonts.SMALL)
    header.plusButton.glyph:SetPoint("CENTER", 0, 0)

    header.searchBox = CreateFrame("EditBox", nil, header, "InputBoxTemplate")
    header.searchBox:SetHeight(18)
    header.searchBox:SetWidth(L.SHELL_HEADER_RIGHT_WIDTH - 6)
    header.searchBox:SetPoint("RIGHT", header, "RIGHT", -L.SHELL_PADDING, 0)
    header.searchBox:SetAutoFocus(false)
    header.searchBox:SetScript("OnTextChanged", function(box)
        Shell:RenderAll(box:GetText())
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

    shell.footerBagsText = PHUI.CreateLabel(shell.footer, "primary", nil, PHUI.Fonts.SMALL)
    shell.footerBagsText:SetPoint("LEFT", shell.footer, "LEFT", L.SHELL_PADDING, 0)

    shell.footerEtaText = PHUI.CreateLabel(shell.footer, "muted", nil, PHUI.Fonts.SMALL)
    shell.footerEtaText:SetPoint("LEFT", shell.footerBagsText, "RIGHT", 4, 0)

    shell.footerAmmoText = PHUI.CreateLabel(shell.footer, "primary", nil, PHUI.Fonts.SMALL)
    shell.footerAmmoText:SetPoint("RIGHT", shell.footer, "RIGHT", -L.SHELL_PADDING, 0)
    shell.footerAmmoText:Hide()

    -- Body: the ONE region whose height actually varies by state - it
    -- fills whatever space is left between header and footer once
    -- Shell:ApplyDimensions resizes the root frame (§8), so nothing here
    -- ever needs to be repositioned by hand per state. One scrolling
    -- viewport reused by Menu/Category/All (§3 "consistent body bounds").
    -- Named (not nil) so the real Blizzard scrollbar child can be looked
    -- up by name and shown/hidden - the scrollFrame's own outer rect
    -- never reserves gutter width; SetScrollBarShown/each RenderX
    -- function decide `content`'s width per §4's conditional-scrollbar
    -- rule instead.
    shell.scrollFrame = CreateFrame("ScrollFrame", "PocketsShellScrollFrame", shell, "UIPanelScrollFrameTemplate")
    shell.scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", L.SHELL_PADDING, -L.SHELL_PADDING)
    shell.scrollFrame:SetPoint("BOTTOMRIGHT", shell.footer, "TOPRIGHT", -L.SHELL_PADDING, L.SHELL_PADDING)

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
end

function Shell:Initialize()
    if self.frame then
        return
    end

    local frame = CreateFrame("Button", "PocketsShellFrame", UIParent, "BackdropTemplate")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    PHUI.ApplyBackdrop(frame)

    frame:SetScript("OnDragStart", function(self)
        if not Pockets.SavedSettings.hud.locked then
            Shell.isDragging = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Shell.isDragging = false
        Shell:SavePosition()
        -- Render() no-ops while isDragging is true (see Render's guard),
        -- so any state change requested by the SAME click (WoW fires
        -- OnDragStart/OnDragStop on every click, moving or not - see
        -- OnClick's note below) never got drawn. Flush it now.
        Shell:Render()
    end)
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

    -- Escape hierarchy (§4). Keyboard capture is only enabled outside
    -- GLANCE (see SetState) so Escape never fights other UI while
    -- collapsed, and any other key just propagates through untouched.
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            Shell:HandleEscape()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    self.frame = frame
    self:BuildGlance()
    self:BuildShell()
    self:RestorePosition()

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.ETA_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.INVENTORY_CHANGED, function() self:OnDataChanged() end, self)

    self.state = self.STATE.GLANCE
    self.context = {}
    self:Render()
end

-- Position and size are independent concerns (§2): this is the ONLY place
-- that ever anchors the root frame to UIParent. Every state transition
-- afterward touches SetSize only, so the anchor set here is what pins
-- Glance's TOPLEFT and every expanded state's TOPLEFT to the same point.
function Shell:RestorePosition()
    PositionStrategy:ApplyRootPosition(self.frame, Pockets.SavedSettings.hud)
end

-- OnDragStart/OnDragStop fire on every click (moving or not), so this
-- runs far more often than an actual drag happens. Skip the write
-- entirely when the position hasn't meaningfully changed, so a
-- stationary click can never persist a fresh (and possibly slightly
-- different, e.g. from float rounding) value over a perfectly good one.
local NO_OP_MOVE_THRESHOLD = 0.5
function Shell:SavePosition()
    local hud = Pockets.SavedSettings.hud
    local captured = PositionStrategy:CaptureSavedPosition(self.frame)

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
    self.state = state
    self.context = context or {}
    self:Render()
end

function Shell:GoBack()
    local parent = self:GetParentState(self.state)
    if parent then
        self:SetState(parent)
    end
end

function Shell:HandleEscape()
    self:GoBack()
end

function Shell:OnDataChanged()
    if self.frame then
        self:Render()
    end
end

-- Resizes the root frame only - never touches its anchor (§1/§2/§15).
-- Since the frame is TOPLEFT-anchored, growing/shrinking always extends
-- right/down from that fixed point.
function Shell:ApplyDimensions(bodyHeight)
    self.frame:SetSize(L.SHELL_WIDTH, TotalHeightForBody(bodyHeight))
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
    for _, widget in ipairs(shell.categoryLabels) do
        widget:Hide()
    end
    -- Category List rows are long-lived real item buttons (created once
    -- per index, reconfigured on each render from their own dedicated
    -- pool key) rather than Acquire/ReleaseAll'd per render like Grid's,
    -- so they're hidden explicitly instead of through the pool.
    for _, row in ipairs(shell.categoryListRows) do
        row:Hide()
    end
    Pockets.UI.ItemButtonPool:ReleaseAll(shell.content)
    shell.scrollFrame:SetVerticalScroll(0)
    shell.content:SetHeight(1)
end

-- Cheap and idempotent - every Render* function below only reads
-- already-computed domain state (§14), so it's always safe to just call
-- this again rather than trying to patch up a half-drawn state.
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

    local frame = self.frame
    local state = self.state

    -- Single root position ownership (§1/§2): every state - GLANCE
    -- included - reapplies the exact same saved TOPLEFT anchor through
    -- the one PositionStrategy-backed function before anything else runs.
    -- The rest of Render only ever calls SetSize afterward, so a state
    -- transition can resize the frame but can never drift its origin.
    self:RestorePosition()

    if state == self.STATE.GLANCE then
        frame.shell:Hide()
        frame.glance:Show()
        frame:EnableKeyboard(false)
        PHUI.ApplyBackdrop(frame, { bgAlpha = L.GLANCE_ALPHA })
        self:RenderGlance()
        return
    end

    frame.glance:Hide()
    frame.shell:Show()
    frame:EnableKeyboard(true)
    PHUI.ApplyBackdrop(frame, { bgAlpha = L.EXPANDED_BODY_ALPHA })

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
    end

    self:ConfigureFooter()
end

--------------------------------------------------
-- GLANCE
--------------------------------------------------

function Shell:RenderGlance()
    local glance = self.frame.glance

    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)
    glance.capacityText:SetText(string.format("%d / %d", capacity.used, capacity.total))
    glance.capacityText:SetTextColor(color.r, color.g, color.b)

    local estimator = Pockets.Services.CapacityEstimator
    local estimatorState = estimator:GetState()
    local confidenceOK = estimator:GetConfidence() >= 0.5
    if estimatorState == Constants.ESTIMATOR_STATE.FULL then
        glance.etaText:SetText("Full")
    elseif estimatorState == Constants.ESTIMATOR_STATE.FILLING and confidenceOK then
        -- Prefer omission to a noisy/fabricated number (§2, §9).
        glance.etaText:SetText(Layout:FormatCompactETA(estimator:GetETA()) or "")
    else
        glance.etaText:SetText("")
    end

    -- Ammo intentionally omitted from Glance (Glance compactness pass) -
    -- it stays available in Menu/Category/All's footer.
    self.frame:SetSize(L.GLANCE_WIDTH, L.GLANCE_HEIGHT)
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

-- Reconfigures the ONE header (left/title/right zones never move, only
-- what occupies them does - §4, §6). The back button is a single
-- reused widget whose onClick (Shell:GoBack, wired once in BuildShell)
-- already resolves MENU -> GLANCE, CATEGORY -> MENU, and ALL -> MENU via
-- the same ESCAPE_PARENT map Escape uses (§5 "same navigation method").
function Shell:ConfigureHeader()
    local header = self.frame.shell.header
    local state = self.state

    header.backButton:Show()
    header.titleText:ClearAllPoints()
    header.titleText:SetPoint("LEFT", header, "LEFT", TITLE_LEFT_OFFSET, 0)
    header.titleText:SetPoint("RIGHT", header, "RIGHT", -(L.SHELL_HEADER_RIGHT_WIDTH + L.SHELL_PADDING), 0)

    if state == self.STATE.MENU then
        header.titleText:SetText("Pockets")
        header.plusButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.CATEGORY then
        header.titleText:SetText(Constants.CATEGORY_LABEL[self.context.categoryID] or "")
        header.plusButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.ALL then
        header.titleText:SetText("All")
        header.plusButton:Hide() -- already in All Items - its slot becomes Search (§3)
        header.searchBox:Show()
    end
end

--------------------------------------------------
-- MENU (§3 STATE 2)
--------------------------------------------------

function Shell:RenderMenu()
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

    local viewportWidth = BodyViewportWidth()
    local contentHeight = #visible * L.LIST_ROW_HEIGHT
    local _, bodyHeight, needsScrollbar = ResolveDynamicHeight(contentHeight)
    local rowWidth = needsScrollbar and (viewportWidth - L.SCROLLBAR_RESERVE) or viewportWidth

    self:ApplyDimensions(bodyHeight)
    content:SetWidth(rowWidth)
    SetScrollBarShown(shell.scrollFrame, needsScrollbar)

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
    local shell = self.frame.shell
    local content = shell.content
    local pool = Pockets.UI.ItemButtonPool

    local items = Pockets.API.GetAggregatedCategoryItems(categoryID)

    -- Conditional scrollbar (§4): FlowLayout:PlanFlat is a pure geometry
    -- function (no widget creation), so it's cheap to try at the full
    -- viewport width first and only redo it narrower - once - if that
    -- would actually overflow the MAX body height. Real item buttons
    -- only ever get created/positioned once, from whichever plan is
    -- final. Width is a constant (BodyViewportWidth), not read off the
    -- live frame, so this can run before the frame is sized for this
    -- render at all (dynamic height pass - ApplyDimensions runs below,
    -- once the actual content height is known).
    local viewportWidth = BodyViewportWidth()

    local plan = FlowLayout:PlanFlat(#items, { rowWidth = viewportWidth, itemSize = L.ITEM_BUTTON_SIZE, gap = L.ITEM_BUTTON_GAP })
    local needsScrollbar = plan.contentHeight > MaxContentHeight()
    local usableWidth = viewportWidth
    if needsScrollbar then
        usableWidth = viewportWidth - L.SCROLLBAR_RESERVE
        plan = FlowLayout:PlanFlat(#items, { rowWidth = usableWidth, itemSize = L.ITEM_BUTTON_SIZE, gap = L.ITEM_BUTTON_GAP })
    end

    local _, bodyHeight = ResolveDynamicHeight(plan.contentHeight)
    self:ApplyDimensions(bodyHeight)
    content:SetWidth(usableWidth)
    SetScrollBarShown(shell.scrollFrame, needsScrollbar)

    for _, placement in ipairs(plan.itemPlacements) do
        local button = pool:Acquire(content)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", content, "TOPLEFT", placement.x, -placement.y)
        pool:Configure(button, items[placement.index])
        button:Show()
    end

    content:SetHeight(math.max(plan.contentHeight, 1))
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

        -- Reserves the same trailing CHEVRON column Menu rows use, left
        -- empty here (item rows never navigate deeper - §7), so the
        -- count/qty column sits at the exact same X coordinate in both
        -- row types regardless of the chevron only existing in one of
        -- them.
        row.qty = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.SMALL)
        row.qty:SetPoint("RIGHT", row, "RIGHT", -(L.LIST_ROW_PADDING + L.LIST_ROW_CHEVRON_WIDTH + L.LIST_ROW_GAP), 0)
        row.qty:SetWidth(L.LIST_ROW_COUNT_WIDTH)
        row.qty:SetJustifyH("RIGHT")

        row.name:SetPoint("RIGHT", row.qty, "LEFT", -L.LIST_ROW_GAP, 0)
    end

    return row
end

function Shell:RenderCategoryList(categoryID)
    local shell = self.frame.shell
    local content = shell.content

    local items = Pockets.API.GetAggregatedCategoryItems(categoryID)

    -- List max-height pass: capped by row COUNT
    -- (CATEGORY_LIST_MAX_VISIBLE_ROWS), not the generic Grid/All pixel
    -- budget (SHELL_BODY_MAX_HEIGHT) - 8 whole rows should be visible
    -- before a scrollbar appears, not however many happen to fit under an
    -- unrelated pixel cap. Fixed row height makes this pure arithmetic,
    -- no FlowLayout call needed. Width is a constant (dynamic height pass
    -- - see RenderCategoryGrid's note).
    local viewportWidth = BodyViewportWidth()
    local contentHeight = #items * L.LIST_ROW_HEIGHT
    local maxVisibleHeight = L.CATEGORY_LIST_MAX_VISIBLE_ROWS * L.LIST_ROW_HEIGHT
    local _, bodyHeight, needsScrollbar = ResolveDynamicHeight(contentHeight, maxVisibleHeight)
    local rowWidth = needsScrollbar and (viewportWidth - L.SCROLLBAR_RESERVE) or viewportWidth

    self:ApplyDimensions(bodyHeight)
    content:SetWidth(rowWidth)
    SetScrollBarShown(shell.scrollFrame, needsScrollbar)

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
end

--------------------------------------------------
-- ALL ITEMS (§3 STATE 4) - categorized dynamic flow + search, ported
-- from the previous FullInventory window onto Shell's shared body.
--------------------------------------------------

local function EnsureCategoryLabel(content, labels, index)
    local widget = labels[index]
    if widget then
        return widget
    end

    widget = CreateFrame("Frame", nil, content)
    widget:SetHeight(L.FULL_INVENTORY_LABEL_HEIGHT)

    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetSize(L.FULL_INVENTORY_LABEL_ICON_SIZE, L.FULL_INVENTORY_LABEL_ICON_SIZE)
    widget.icon:SetPoint("LEFT", widget, "LEFT", 0, 0)

    widget.text = PHUI.CreateLabel(widget, "muted", nil, PHUI.Fonts.SMALL)
    widget.text:SetPoint("LEFT", widget.icon, "RIGHT", L.FULL_INVENTORY_LABEL_ICON_GAP, 0)

    function widget:Measure()
        return L.FULL_INVENTORY_LABEL_ICON_SIZE + L.FULL_INVENTORY_LABEL_ICON_GAP + (self.text:GetStringWidth() or 0)
    end

    labels[index] = widget
    return widget
end

local function BuildCategorySections()
    local sections = {}
    for _, categoryID in ipairs(Constants.CATEGORY_ORDER) do
        local items = Pockets.API.GetAggregatedCategoryItems(categoryID)
        if #items > 0 then
            table.insert(sections, {
                categoryID = categoryID,
                label = Constants.CATEGORY_LABEL[categoryID],
                icon = Constants.CATEGORY_ICON[categoryID],
                buttonRecords = items,
            })
        end
    end
    return sections
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
    self:ClearBody()
    local shell = self.frame.shell
    local content = shell.content
    local pool = Pockets.UI.ItemButtonPool

    local itemSize = L.ITEM_BUTTON_SIZE
    local gap = L.ITEM_BUTTON_GAP
    local hasQuery = query ~= nil and query ~= ""

    -- Conditional scrollbar (§4): try the full viewport width first (both
    -- FlowLayout functions are pure geometry, no widget creation), redo
    -- once narrower only if that would actually overflow the MAX body
    -- height. Real widgets only ever get created/positioned once, from
    -- the final plan. Width is a constant, not read off the live frame
    -- (dynamic height pass - RenderAll can also be called directly from
    -- the search box, bypassing Shell:Render(), so it must be able to
    -- size itself unconditionally here too).
    local viewportWidth = BodyViewportWidth()

    if hasQuery then
        local items = BuildFlatSearchResults(query)
        local plan = FlowLayout:PlanFlat(#items, { rowWidth = viewportWidth, itemSize = itemSize, gap = gap })
        local needsScrollbar = plan.contentHeight > MaxContentHeight()
        local usableWidth = viewportWidth
        if needsScrollbar then
            usableWidth = viewportWidth - L.SCROLLBAR_RESERVE
            plan = FlowLayout:PlanFlat(#items, { rowWidth = usableWidth, itemSize = itemSize, gap = gap })
        end
        local _, bodyHeight = ResolveDynamicHeight(plan.contentHeight)
        self:ApplyDimensions(bodyHeight)
        content:SetWidth(usableWidth)
        SetScrollBarShown(shell.scrollFrame, needsScrollbar)

        for _, placement in ipairs(plan.itemPlacements) do
            local button = pool:Acquire(content)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", content, "TOPLEFT", placement.x, -placement.y)
            pool:Configure(button, items[placement.index])
            button:Show()
        end
        content:SetHeight(math.max(plan.contentHeight, 1))
        return
    end

    local sections = BuildCategorySections()

    local labelIndex = 0
    local planCategories = {}
    local labelWidgetByCategoryID = {}
    for _, section in ipairs(sections) do
        labelIndex = labelIndex + 1
        local widget = EnsureCategoryLabel(content, shell.categoryLabels, labelIndex)
        widget.icon:SetTexture(section.icon)
        widget.text:SetText(string.format("%s (%d)", section.label, #section.buttonRecords))
        labelWidgetByCategoryID[section.categoryID] = widget

        table.insert(planCategories, {
            categoryID = section.categoryID,
            labelWidth = widget:Measure(),
            itemCount = #section.buttonRecords,
        })
    end

    local plan = FlowLayout:Plan(planCategories, {
        rowWidth = viewportWidth,
        itemSize = itemSize,
        gap = gap,
        labelHeight = L.FULL_INVENTORY_LABEL_HEIGHT,
    })
    local needsScrollbar = plan.contentHeight > MaxContentHeight()
    local usableWidth = viewportWidth
    if needsScrollbar then
        usableWidth = viewportWidth - L.SCROLLBAR_RESERVE
        plan = FlowLayout:Plan(planCategories, {
            rowWidth = usableWidth,
            itemSize = itemSize,
            gap = gap,
            labelHeight = L.FULL_INVENTORY_LABEL_HEIGHT,
        })
    end
    local _, bodyHeight = ResolveDynamicHeight(plan.contentHeight)
    self:ApplyDimensions(bodyHeight)
    content:SetWidth(usableWidth)
    SetScrollBarShown(shell.scrollFrame, needsScrollbar)

    local buttonRecordsByCategoryID = {}
    for _, section in ipairs(sections) do
        buttonRecordsByCategoryID[section.categoryID] = section.buttonRecords
    end

    for _, categoryPlacement in ipairs(plan.categoryPlacements) do
        local widget = labelWidgetByCategoryID[categoryPlacement.categoryID]
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", content, "TOPLEFT", categoryPlacement.labelX, -categoryPlacement.labelY)
        widget:SetWidth(categoryPlacement.labelWidth)
        widget:Show()

        local buttonRecords = buttonRecordsByCategoryID[categoryPlacement.categoryID]
        for _, itemPlacement in ipairs(categoryPlacement.itemPlacements) do
            local button = pool:Acquire(content)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", content, "TOPLEFT", itemPlacement.x, -itemPlacement.y)
            pool:Configure(button, buttonRecords[itemPlacement.index])
            button:Show()
        end
    end

    content:SetHeight(math.max(plan.contentHeight, 1))
end

--------------------------------------------------
-- Footer (shared by MENU/CATEGORY/ALL)
--------------------------------------------------

function Shell:ConfigureFooter()
    local shell = self.frame.shell
    local InventoryState = Pockets.Services.InventoryState

    local capacity = InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)
    shell.footerBagsText:SetText(string.format("%d/%d", capacity.used, capacity.total))
    shell.footerBagsText:SetTextColor(color.r, color.g, color.b)

    local estimator = Pockets.Services.CapacityEstimator
    local estimatorState = estimator:GetState()
    local confidenceOK = estimator:GetConfidence() >= 0.5
    if estimatorState == Constants.ESTIMATOR_STATE.FULL then
        shell.footerEtaText:SetText(" \194\183 Full")
    elseif estimatorState == Constants.ESTIMATOR_STATE.FILLING and confidenceOK then
        shell.footerEtaText:SetText(Layout:FormatETASuffix(estimator:GetETA()))
    else
        shell.footerEtaText:SetText("")
    end

    local ammoCapacity = InventoryState:GetAmmoCapacity()
    if self:ShouldShowAmmoRow(ammoCapacity) then
        shell.footerAmmoText:SetText(string.format("%d/%d", ammoCapacity.used, ammoCapacity.total))
        shell.footerAmmoText:Show()
    else
        shell.footerAmmoText:Hide()
    end
end

--------------------------------------------------
-- Visibility (independent of state - /pockets show)
--------------------------------------------------

function Shell:Show()
    if self.frame then
        self.frame:Show()
    end
end

function Shell:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function Shell:Toggle()
    if not self.frame then
        return
    end
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Shift-B / the old "expand" action jump directly to All Items (§4),
-- toggling back to Menu if All Items is already open.
function Shell:ToggleAllItems()
    if self.state == self.STATE.ALL then
        self:SetState(self.STATE.MENU)
    else
        self:SetState(self.STATE.ALL)
    end
end
