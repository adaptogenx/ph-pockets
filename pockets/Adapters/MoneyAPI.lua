--[[
    Adapters/MoneyAPI.lua - Isolates the player-money read (Loot Log).

    PLAYER_MONEY is the one authoritative signal for every money change
    (mob coin, quest reward, vendor sale/buy, repair, taxi, mail, AH):
    Core/LootLog diffs successive GetMoney() values instead of parsing
    chat text, so a locale or message-format change can never break it.
]]

local _, Pockets = ...

Pockets.Adapters.MoneyAPI = Pockets.Adapters.MoneyAPI or {}
local MoneyAPI = Pockets.Adapters.MoneyAPI

function MoneyAPI:GetMoney()
    return GetMoney() or 0
end
