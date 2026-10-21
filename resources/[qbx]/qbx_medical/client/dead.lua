local config = require 'config.client'
local sharedConfig = require 'config.shared'
local WEAPONS = exports.qbx_core:GetWeapons()
local allowRespawn = true
local plyState = LocalPlayer.state

local function playDeadAnimation()
    local deadAnimDict = 'dead'
    local playerData = QBX.PlayerData
    local metadata = playerData and playerData.metadata
    local deadAnim = metadata and metadata.ishandcuffed and 'dead_f' or 'dead_a'

    local deadVehAnimDict = 'veh@low@front_ps@idle_duck'
    local deadVehAnim = 'sit'

    if cache.vehicle then
        if not IsEntityPlayingAnim(cache.ped, deadVehAnimDict, deadVehAnim, 3) then
            lib.playAnim(cache.ped, deadVehAnimDict, deadVehAnim, 1.0, 1.0, -1, 1, 0, false, false, false)
        end
    elseif not IsEntityPlayingAnim(cache.ped, deadAnimDict, deadAnim, 3) then
        lib.playAnim(cache.ped, deadAnimDict, deadAnim, 1.0, 1.0, -1, 1, 0, false, false, false)
    end
end

exports('PlayDeadAnimation', playDeadAnimation)

---put player in death animation and make invincible
function OnDeath(attacker, weapon)
    SetDeathState(sharedConfig.deathState.DEAD)
    TriggerEvent('qbx_medical:client:onPlayerDied', attacker, weapon)
    TriggerServerEvent('qbx_medical:server:onPlayerDied', attacker, weapon)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'demo', 0.1)

    WaitForPlayerToStopMoving()

    CreateThread(function()
        while DeathState == sharedConfig.deathState.DEAD do
            DisableControls()
            SetCurrentPedWeapon(cache.ped, `WEAPON_UNARMED`, true)
            Wait(0)
        end
    end)
    plyState.invBusy = true

    ResurrectPlayer()
    playDeadAnimation()
    SetEntityInvincible(cache.ped, true)
    SetEntityHealth(cache.ped, GetEntityMaxHealth(cache.ped))
    CheckForRespawn()
end

exports('KillPlayer', OnDeath)

local function respawn()
    local success = lib.callback.await('qbx_medical:server:respawn')
    if not success then return end
    if QBX.PlayerData.metadata.ishandcuffed then
        TriggerEvent('police:client:GetCuffed', -1)
    end
    TriggerEvent('police:client:DeEscort')
    plyState.invBusy = false
end

---Allow player to respawn
function CheckForRespawn()
    RespawnHoldTime = 5
    while DeathState == sharedConfig.deathState.DEAD do
        if IsControlPressed(0, 38) and RespawnHoldTime <= 1 and allowRespawn then
            respawn()
            return
        end
        if IsControlPressed(0, 38) then
            RespawnHoldTime -= 1
        end
        if IsControlReleased(0, 38) then
            RespawnHoldTime = 5
        end
        if RespawnHoldTime <= 0 then
            RespawnHoldTime = 0
        end
        DeathTime -= 1

        -- COOKIE SERVER:
        -- Death timer reaching 0 must NEVER auto-respawn the player.
        -- This is especially important for AFK hunger/thirst deaths:
        -- the body stays where it died until the player manually holds E
        -- or EMS/admin explicitly revives them.
        if DeathTime <= 0 then
            DeathTime = 0
        end

        Wait(1000)
    end
end

function AllowRespawn()
    allowRespawn = true
end

exports('AllowRespawn', AllowRespawn)

exports('DisableRespawn', function()
    allowRespawn = false
end)

---log the death of a player along with the attacker and the weapon used.
---@param victim number ped
---@param attacker number ped
---@param weapon string weapon hash
local function logDeath(victim, attacker, weapon)
    local playerId = NetworkGetPlayerIndexFromPed(victim)
    local playerName = (' %s (%d)'):format(GetPlayerName(playerId), GetPlayerServerId(playerId)) or locale('info.self_death')
    local killerId = NetworkGetPlayerIndexFromPed(attacker)
    local killerName = ('%s (%d)'):format(GetPlayerName(killerId), GetPlayerServerId(killerId)) or locale('info.self_death')
    local weaponLabel = WEAPONS[weapon]?.label or 'Unknown'
    local weaponName = WEAPONS[weapon]?.name or 'Unknown'
    local message = locale('logs.death_log_message', killerName, playerName, weaponLabel, weaponName)

    lib.callback.await('qbx_medical:server:log', false, 'logDeath', message)
end

-- ★★ 쿠키서버 개조 (2026-07-14): 라스트스탠드(기절 후 재기상) 삭제 ★★
--
--   원래 qbx는 HP가 0이 되면 곧바로 죽이지 않았다.
--     1단계 LAST_STAND  체력 150으로 되살려서 바닥을 기게 만든다(writhe). 6분 버틴다.
--     2단계 DEAD        그 상태에서 한 번 더 맞아야 진짜 다운.
--
--   총격전에서 이게 '한 번 쓰러졌다 다시 일어서는' 것처럼 보였다. 실제로 그렇다
--   StartLastStand가 ResurrectPlayer()를 부르고 체력을 150으로 채워 넣기 때문이다.
--
--   → 쿠키서버는 1단계를 건너뛴다. 총이든 둔기든 주먹이든, HP 100 → 0 이면 그 자리에서 다운이다.
--     중간 상태가 없으니 '살아 있는데 못 움직인다'는 회색지대도 없다.
--
--   ⚠ StartLastStand 함수 자체는 지우지 않았다. laststand.lua가 export로 내보내고 있어서
--     지우면 다른 리소스가 부를 때 nil이 된다. '부르지 않는다'로 충분하다.
---@param event string
---@param data table
AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= 'CEventNetworkEntityDamage' then return end
    if not plyState.isLoggedIn then return end
    local victim, attacker, victimDied, weapon = data[1], data[2], data[4], data[7]
    if not IsEntityAPed(victim) or not victimDied or NetworkGetPlayerIndexFromPed(victim) ~= cache.playerId or not IsEntityDead(cache.ped) then return end

    -- 이미 다운이면 아무것도 안 한다. 시체를 두 번 죽이지 않는다.
    if DeathState ~= sharedConfig.deathState.ALIVE then return end

    logDeath(victim, attacker, weapon)
    DeathTime = config.deathTime
    OnDeath(attacker, weapon)
end)

function DisableControls()
    DisableAllControlActions(0)
    EnableControlAction(0, 1, true)
    EnableControlAction(0, 2, true)
    EnableControlAction(0, 245, true)
    EnableControlAction(0, 38, true)
    EnableControlAction(0, 0, true)
    EnableControlAction(0, 322, true)
    EnableControlAction(0, 288, true)
    EnableControlAction(0, 213, true)
    EnableControlAction(0, 249, true)
    EnableControlAction(0, 46, true)
    EnableControlAction(0, 47, true)
end