local config = require 'config.client'
local plyState = LocalPlayer.state

---Initialize health and armor settings on the player's ped
---@param ped number
---@param playerId number
---@param playerMetadata any
local function initHealthAndArmor(ped, playerId, playerMetadata)
    SetEntityMaxHealth(ped, 200)
    SetEntityHealth(ped, playerMetadata.health)
    SetPlayerHealthRechargeMultiplier(playerId, 0.0)
    SetPlayerHealthRechargeLimit(playerId, 0.0)
    SetPedArmour(ped, playerMetadata.armor)
end

---starts death or last stand based off of player's metadata
---@param metadata any
local function initDeathAndLastStand(metadata)
    if not plyState.isLoggedIn then return end

    -- 부상 시스템을 껐으니 남은 출혈도 없어야 한다.
    --   예전에 출혈이 박힌 채로 저장된 사람은, 접속하면 아무 이유 없이 피를 흘리다 쓰러진다.
    --   새로 생기지 않는 것과 이미 있는 걸 지우는 건 다른 일이다.
    NumInjuries = 0
    SetBleedLevel(0)

    -- ★ 쿠키서버: 라스트스탠드를 안 쓴다(dead.lua 참고).
    --   접속 전에 라스트스탠드로 저장된 사람이 남아 있을 수 있다 → 그냥 다운으로 올린다.
    --   여기서 StartLastStand를 부르면 없앤 기절 상태가 접속할 때마다 되살아난다.
    if metadata.isdead or metadata.inlaststand then
        DeathTime = config.deathTime
        OnDeath()
    end
end

---initialize settings from player object
local function onPlayerLoaded()
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    CreateThread(function()
        Wait(1000)
        initHealthAndArmor(cache.ped, cache.playerId, QBX.PlayerData.metadata)
        initDeathAndLastStand(QBX.PlayerData.metadata)
    end)
end

AddEventHandler('QBCore:Client:OnPlayerLoaded', onPlayerLoaded)

AddEventHandler('onResourceStart', function(resourceName)
    if cache.resource ~= resourceName then return end
    onPlayerLoaded()
end)
