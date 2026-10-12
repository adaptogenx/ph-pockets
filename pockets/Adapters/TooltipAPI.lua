--[[
    Adapters/TooltipAPI.lua - Isolates tooltip hooking (TDD §3.1, §16)

    Conservatively hooks item tooltips to add a single carried-count line.
    Any failure here must not break inventory state or the rest of the UI
    (TDD §22 Error Handling).
]]

-- luacheck: globals TooltipDataProcessor Enum ItemRefTooltip

local _, Pockets = ...

Pockets.Adapters.TooltipAPI = Pockets.Adapters.TooltipAPI or {}
local TooltipAPI = Pockets.Adapters.TooltipAPI

TooltipAPI.hooked = false
-- True when some item-tooltip integration is active (legacy script hook or
-- modern TooltipDataProcessor post-call); false when neither is available.
TooltipAPI.supported = nil
-- "modern" | "legacy" | nil. Diagnostic only (Forever M3 §22).
TooltipAPI.mode = nil

-- Pure-ish: is the modern tooltip-data pipeline present?
function TooltipAPI:HasModernPipeline()
    return TooltipDataProcessor ~= nil
        and TooltipDataProcessor.AddTooltipPostCall ~= nil
        and Enum ~= nil
        and Enum.TooltipDataType ~= nil
        and Enum.TooltipDataType.Item ~= nil
end

-- Pure: pull a usable itemID/itemLink out of tooltip data. Secret or
-- non-numeric ids yield nil (never unwrapped). Split out for tests.
function TooltipAPI.ExtractItem(data, isSecret)
    if type(data) ~= "table" then
        return nil
    end
    local id, link = data.id, data.hyperlink
    if isSecret and (isSecret(id) or isSecret(link)) then
        return nil
    end
    if type(id) ~= "number" then
        return nil
    end
    if type(link) ~= "string" then
        link = nil
    end
    return id, link
end

-- Pure-ish feature check: does this tooltip still have the legacy handler?
function TooltipAPI:HasLegacyItemHandler(tooltip)
    if not tooltip or not tooltip.HookScript then
        return false
    end
    if tooltip.HasScript then
        local ok, has = pcall(tooltip.HasScript, tooltip, "OnTooltipSetItem")
        return ok and has == true
    end
    return true
end

-- Registers a callback invoked with (tooltip, itemID, itemLink) whenever an
-- item tooltip is shown. Safe to call multiple times; only hooks once.
-- Silently does nothing (supported = false) where the legacy handler is gone.
function TooltipAPI:OnItemTooltipShow(callback)
    if self.hooked then
        return
    end
    self.hooked = true

    if self:HasModernPipeline() then
        local isSecret = function(v)
            return Pockets.Adapters.ClientAPI:IsSecret(v)
        end
        local addOk, addErr = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip, data)
            -- Only the main/ref tooltips; skip shopping/comparison and
            -- every other tooltip that renders item data.
            if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then
                return
            end
            local ok, err = pcall(function()
                local itemID, itemLink = TooltipAPI.ExtractItem(data, isSecret)
                if itemID then
                    callback(tooltip, itemID, itemLink)
                end
            end)
            if not ok and Pockets.Debug then
                Pockets.Debug:LogError("TooltipAPI callback failed: " .. tostring(err))
            end
        end)
        self.supported = addOk
        self.mode = addOk and "modern" or nil
        if not addOk and Pockets.Debug then
            Pockets.Debug:LogError("TooltipAPI modern hook unavailable: " .. tostring(addErr))
        end
        return
    end

    if not self:HasLegacyItemHandler(GameTooltip) then
        self.supported = false
        return
    end

    local hookOk, hookErr = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip)
        local ok, err = pcall(function()
            local _, itemLink = tooltip:GetItem()
            if not itemLink then
                return
            end
            local itemID = tonumber(itemLink:match("item:(%d+)"))
            if not itemID then
                return
            end
            callback(tooltip, itemID, itemLink)
        end)
        if not ok and Pockets.Debug then
            Pockets.Debug:LogError("TooltipAPI hook failed: " .. tostring(err))
        end
    end)
    self.supported = hookOk
    self.mode = hookOk and "legacy" or nil
    if not hookOk and Pockets.Debug then
        Pockets.Debug:LogError("TooltipAPI hook unavailable: " .. tostring(hookErr))
    end
end
