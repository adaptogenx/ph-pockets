--[[
    Shared/CircularPortrait.lua - Reusable circular portrait + count badge
    (Mini HUD TDD §2, §4)

    A round portrait (dark disc, circle-masked icon, drawn rim) plus an
    optional small text badge
    anchored over the portrait's bottom edge. Generic: no Pockets strings or
    inventory APIs - callers pass the icon and set the badge text.

    Frames are created once; SetIcon/SetBadgeText update in place.
]]

-- luacheck: globals C_Texture

local _, Pockets = ...

Pockets.UI.CircularPortrait = Pockets.UI.CircularPortrait or {}
local CircularPortrait = Pockets.UI.CircularPortrait
local PHUI = Pockets.UI.PHUI

-- Native Forever portrait ring: the NineSlice top-left corner of
-- PortraitFrameTemplate (`UI-Frame-PortraitMetal-CornerTopLeft`, 95x95).
-- Measured from /pockets debug ring: the circle's centre is (38.5, 38) in
-- the art, outer diameter ~60, inner hole ~51; its rails run off to the
-- right and bottom, so it is clipped to a circle slightly wider than the
-- ring (62) to cut them off.
local RING_ATLAS = "UI-Frame-PortraitMetal-CornerTopLeft"
local RING = { size = 95, cx = 38.5, cy = 38, outer = 60, mask = 62, hole = 51 }

local function HasRingAtlas()
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(RING_ATLAS) ~= nil
end

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- opts: size (portrait diameter), nativeRing (default true: the client's own portrait ring when available, else a drawn rim), icon (texture path/fileID), iconSize
-- (fallback icon px), badge = { width, height, overlap, font, bgColor,
-- borderColor, textColor } (omit for no badge).
-- Frame layout: portrait at the top, badge hanging off the bottom; the
-- frame is sized to exactly that footprint (no invisible hit area).
function CircularPortrait:Create(parent, opts)
    opts = opts or {}
    local size = opts.size or 48
    local badgeOpts = opts.badge
    local frame = CreateFrame("Frame", nil, parent)
    local height = size
    local width = size
    if badgeOpts then
        height = size - (badgeOpts.overlap or 0) + badgeOpts.height
        width = math.max(size, badgeOpts.width)
    end
    frame:SetSize(width, height)
    frame:EnableMouse(false)
    frame.size = size

    -- Portrait holder, horizontally centred in the footprint.
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(size, size)
    holder:SetPoint("TOP", frame, "TOP", 0, 0)
    holder:EnableMouse(false)
    frame.portrait = holder

    -- Dark disc + circle-masked icon. (The native template's ring is not
    -- usable on its own - it lives in the frame chrome - so the rim is
    -- drawn with the same segment technique as the capacity ring.)
    local iconSize = opts.iconSize or math.floor(size * 0.7)
    local native = opts.nativeRing ~= false and HasRingAtlas()
    local ringScale = size / RING.outer
    local disc = holder:CreateTexture(nil, "BACKGROUND")
    if native then
        -- Only fill the ring's inner hole.
        disc:SetSize(RING.hole * ringScale, RING.hole * ringScale)
        disc:SetPoint("CENTER", holder, "CENTER", 0, 0)
    else
        disc:SetAllPoints(holder)
    end
    disc:SetTexture(CIRCLE_MASK)
    local bg = PHUI.Colors.BG_DARK
    disc:SetVertexColor(bg[1], bg[2], bg[3], 1)
    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetSize(iconSize, iconSize)
    tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
    local coords = opts.iconTexCoord or { 0.08, 0.92, 0.08, 0.92 }
    tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    if tex.AddMaskTexture and holder.CreateMaskTexture then
        local mask = holder:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK)
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    end
    if native then
        local ring = holder:CreateTexture(nil, "OVERLAY")
        ring:SetAtlas(RING_ATLAS)
        ring:SetSize(RING.size * ringScale, RING.size * ringScale)
        ring:SetPoint("TOPLEFT", holder, "CENTER", -RING.cx * ringScale, RING.cy * ringScale)
        if ring.AddMaskTexture and holder.CreateMaskTexture then
            local ringMask = holder:CreateMaskTexture()
            ringMask:SetTexture(CIRCLE_MASK)
            ringMask:SetSize(RING.mask * ringScale, RING.mask * ringScale)
            ringMask:SetPoint("CENTER", holder, "CENTER", 0, 0)
            ring:AddMaskTexture(ringMask)
        end
        frame.nativeRing = ring
    elseif opts.rimColor then
        local rim = Pockets.UI.CapacityRing:Create(holder, { diameter = size, thickness = opts.rimThickness or 2, segments = 64 })
        rim:SetPoint("CENTER", holder, "CENTER", 0, 0)
        rim:SetFrameLevel(holder:GetFrameLevel() + 5)
        rim:SetColor(opts.rimColor[1], opts.rimColor[2], opts.rimColor[3])
        rim:SetFraction(1)
        frame.rim = rim
    end
    frame.icon = tex
    function frame:SetIcon(icon)
        tex:SetTexture(icon)
    end
    if opts.icon then
        frame:SetIcon(opts.icon)
    end

    if badgeOpts then
        local badge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        badge:SetSize(badgeOpts.width, badgeOpts.height)
        badge:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
        badge:SetFrameLevel(holder:GetFrameLevel() + 20)
        badge:EnableMouse(false)
        PHUI.ApplyBackdrop(badge, {
            backdrop = badgeOpts.backdrop,
            bgColor = badgeOpts.bgColor,
            borderColor = badgeOpts.borderColor,
        })
        local text = PHUI.CreateLabel(badge, "primary", nil, badgeOpts.font)
        text:SetPoint("CENTER", badge, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        local tc = badgeOpts.textColor
        if tc then
            text:SetTextColor(tc[1], tc[2], tc[3])
        end
        badge.text = text
        frame.badge = badge
        function frame:SetBadgeWidth(w)
            badge:SetWidth(w)
        end
        function frame:SetBadgeText(value)
            text:SetText(value or "")
        end
    end

    return frame
end
