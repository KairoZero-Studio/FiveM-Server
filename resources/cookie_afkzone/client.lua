local inAfkZone = false
local transferBusy = false
local lastActivity = GetGameTimer()
local lastCoords = nil
local lastHeading = nil
local healthFloor = nil
local previousInvincible = false

-- config.lua는 기본값, 서버 DB 동기화 값이 실제 동작 좌표가 됩니다.
local runtimeConfig = {
    MainPortal = {
        x=Config.MainPortal.x+0.0, y=Config.MainPortal.y+0.0,
        z=Config.MainPortal.z+0.0, h=Config.MainPortal.w+0.0,
    },
    AfkSpawn = {
        x=Config.AfkSpawn.x+0.0, y=Config.AfkSpawn.y+0.0,
        z=Config.AfkSpawn.z+0.0, h=Config.AfkSpawn.w+0.0,
    },
    AfkReturnPortal = {
        x=Config.AfkReturnPortal.x+0.0, y=Config.AfkReturnPortal.y+0.0,
        z=Config.AfkReturnPortal.z+0.0, h=0.0,
    },
    AfkZoneRadius = tonumber(Config.AfkZoneRadius) or 42.0,
}

local function readPoint(input, fallback)
    input = type(input) == 'table' and input or {}
    return {
        x=tonumber(input.x) or fallback.x,
        y=tonumber(input.y) or fallback.y,
        z=tonumber(input.z) or fallback.z,
        h=tonumber(input.h) or fallback.h or 0.0,
    }
end

RegisterNetEvent('cookie_afkzone:client:configSync', function(cfg)
    cfg = type(cfg) == 'table' and cfg or {}
    runtimeConfig.MainPortal = readPoint(cfg.MainPortal, runtimeConfig.MainPortal)
    runtimeConfig.AfkSpawn = readPoint(cfg.AfkSpawn, runtimeConfig.AfkSpawn)
    runtimeConfig.AfkReturnPortal = readPoint(cfg.AfkReturnPortal, runtimeConfig.AfkReturnPortal)
    runtimeConfig.AfkZoneRadius = math.max(5.0, math.min(1000.0, tonumber(cfg.AfkZoneRadius) or runtimeConfig.AfkZoneRadius))
end)

CreateThread(function()
    Wait(1200)
    TriggerServerEvent('cookie_afkzone:server:requestConfig')
end)

local function notify(message, isError)
    pcall(function()
        lib.notify({
            title = '잠수존',
            description = tostring(message or ''),
            type = isError and 'error' or 'inform',
            duration = 4500,
            position = 'top-right'
        })
    end)
end

RegisterNetEvent('cookie_afkzone:client:notify', notify)

RegisterNetEvent('cookie_afkzone:client:transferReset', function()
    transferBusy = false
end)

local function drawText3d(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255,255,255,235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x,y)
end

local function isDeadOrDown()
    local ped = PlayerPedId()
    return IsEntityDead(ped)
        or LocalPlayer.state.isDead == true
        or LocalPlayer.state.dead == true
        or LocalPlayer.state.laststand == true
end

RegisterNetEvent('cookie_afkzone:client:manualEnter', function()
    if inAfkZone or transferBusy then return end
    transferBusy = true
    TriggerServerEvent('cookie_afkzone:server:enter', 'manual', isDeadOrDown())
end)

RegisterNetEvent('cookie_afkzone:client:manualLeave', function()
    -- V14.2.3: 서버/StateBag 동기화가 잠깐 어긋나더라도
    -- 실제 퇴장 비콘에서 누른 E 입력은 서버까지 반드시 전달한다.
    -- 최종 퇴장 가능 여부는 서버가 위치/상태/라우팅 버킷으로 재검증한다.
    if transferBusy then return end
    transferBusy = true
    TriggerServerEvent('cookie_afkzone:server:leave')

    -- 서버 응답이 유실되더라도 조작이 영구 잠기지 않도록 안전 해제.
    SetTimeout(3500, function()
        if transferBusy then
            transferBusy = false
        end
    end)
end)

local function ensureOutOfVehicle(ped)
    if not IsPedInAnyVehicle(ped, false) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh and veh ~= 0 then
        TaskLeaveVehicle(ped, veh, 16)
        Wait(100)
    end
end

local function applyAfkProtection(on)
    local ped = PlayerPedId()
    if on then
        previousInvincible = GetPlayerInvincible(PlayerId()) == true
        healthFloor = math.max(1, GetEntityHealth(ped))
        SetPlayerInvincible(PlayerId(), true)
        SetEntityInvincible(ped, true)
        SetCurrentPedWeapon(ped, joaat('WEAPON_UNARMED'), true)
    else
        SetPlayerInvincible(PlayerId(), previousInvincible)
        SetEntityInvincible(ped, previousInvincible)
        healthFloor = nil
    end
end

local function syncAfkState(value)
    local nextState = value == true
    if inAfkZone == nextState then return end
    inAfkZone = nextState
    applyAfkProtection(inAfkZone)
    lastActivity = GetGameTimer()
    lastCoords = GetEntityCoords(PlayerPedId())
    lastHeading = GetEntityHeading(PlayerPedId())
end

AddStateBagChangeHandler('cookieAfkZone', nil, function(bagName, _, value)
    local mine = ('player:%s'):format(GetPlayerServerId(PlayerId()))
    if bagName ~= mine then return end
    syncAfkState(value)
end)

RegisterNetEvent('cookie_afkzone:client:teleport', function(data)
    data = type(data) == 'table' and data or {}
    local ped = PlayerPedId()
    ensureOutOfVehicle(ped)

    if data.revive == true and isDeadOrDown() then
        local x,y,z = tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0
        NetworkResurrectLocalPlayer(x,y,z,tonumber(data.h) or 0.0,false,false)
        ped = PlayerPedId()
        ClearPedBloodDamage(ped)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
    end

    SetEntityCoordsNoOffset(ped, tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0, false, false, false)
    SetEntityHeading(ped, tonumber(data.h) or 0.0)
    ClearPedTasksImmediately(ped)

    transferBusy = false
    lastActivity = GetGameTimer()
    lastCoords = GetEntityCoords(ped)
    lastHeading = GetEntityHeading(ped)

    if data.mode == 'enter' then
        syncAfkState(true)
        if data.reason == 'idle' then
            notify(('%d분 동안 활동이 없어 잠수존으로 이동했습니다.'):format(tonumber(Config.IdleMinutes) or 20), false)
        else
            notify('잠수존에 입장했습니다. 허기·목마름·기력·산소·체력이 보호됩니다.', false)
        end
    else
        syncAfkState(false)
        notify('메인광장으로 이동했습니다.', false)
    end
end)

local function controlsActive()
    local ids = {21,22,23,24,25,30,31,32,33,34,35,37,38,44,47,51,75,140,141,142,143,249}
    for i=1,#ids do
        local id = ids[i]
        if IsControlPressed(0,id) or IsDisabledControlPressed(0,id) then return true end
    end
    if math.abs(GetControlNormal(0,1)) > 0.025 or math.abs(GetControlNormal(0,2)) > 0.025 then return true end
    return false
end

CreateThread(function()
    Wait(3500)
    syncAfkState(LocalPlayer.state.cookieAfkZone == true)
    local ped = PlayerPedId()
    lastCoords = GetEntityCoords(ped)
    lastHeading = GetEntityHeading(ped)
    lastActivity = GetGameTimer()

    while true do
        Wait(1000)
        ped = PlayerPedId()
        if not DoesEntityExist(ped) or not NetworkIsPlayerActive(PlayerId()) then
            lastActivity = GetGameTimer()
        elseif inAfkZone or transferBusy then
            lastActivity = GetGameTimer()
        elseif LocalPlayer.state.cookieDetained == true then
            -- 교도소/구금 중 잠수존 자동 이동은 하지 않는다.
            lastActivity = GetGameTimer()
        else
            local pos = GetEntityCoords(ped)
            local heading = GetEntityHeading(ped)
            local moved = lastCoords and #(pos-lastCoords) >= (tonumber(Config.ActivityMoveDistance) or 0.55)
            local turned = lastHeading and math.abs(heading-lastHeading) >= (tonumber(Config.ActivityHeadingDegrees) or 4.0)
            local nuiFocused = false
            pcall(function() nuiFocused = IsNuiFocused() == true end)

            if moved or turned or controlsActive() or nuiFocused then
                lastActivity = GetGameTimer()
                lastCoords = pos
                lastHeading = heading
            elseif (GetGameTimer()-lastActivity) >= ((tonumber(Config.IdleMinutes) or 20)*60*1000) then
                transferBusy = true
                TriggerServerEvent('cookie_afkzone:server:enter', 'idle', isDeadOrDown())
            end
        end
    end
end)

-- 잠수존 입장/퇴장 위치는 이제 F3 좌표 관리의
-- "잠수존 입장" / "잠수존 퇴장" 좌표가 담당합니다.

-- 잠수존 보호: 체력/기력/산소 고정 + 전투 금지 + 범위 이탈 방지.
local outsideSince = nil
CreateThread(function()
    while true do
        if not inAfkZone then
            Wait(600)
        else
            Wait(0)
            local ped = PlayerPedId()
            SetPlayerInvincible(PlayerId(), true)
            SetEntityInvincible(ped, true)
            RestorePlayerStamina(PlayerId(), 1.0)
            SetPlayerUnderwaterTimeRemaining(PlayerId(), 10.0)

            if healthFloor and GetEntityHealth(ped) < healthFloor and not IsEntityDead(ped) then
                SetEntityHealth(ped, healthFloor)
            end

            DisableControlAction(0,24,true)
            DisableControlAction(0,25,true)
            DisableControlAction(0,37,true)
            DisableControlAction(0,44,true)
            DisableControlAction(0,140,true)
            DisableControlAction(0,141,true)
            DisableControlAction(0,142,true)
            DisableControlAction(0,143,true)

            -- V13.9.2: F3에서 그린 sphere / box / poly 범위를 실제 잠수존 경계로 사용합니다.
            local currentZone = nil
            local targetZone = nil
            if GetResourceState('cookie_safezone') == 'started' then
                pcall(function() currentZone = exports.cookie_safezone:getCurrentAfkZone() end)
                if not currentZone then
                    pcall(function() targetZone = exports.cookie_safezone:getFirstAfkZone() end)
                end
            end

            if currentZone then
                outsideSince = nil
            elseif targetZone then
                outsideSince = outsideSince or GetGameTimer()
                if GetGameTimer() - outsideSince >= 900 then
                    SetEntityCoordsNoOffset(
                        ped,
                        tonumber(targetZone.cx) or 0.0,
                        tonumber(targetZone.cy) or 0.0,
                        tonumber(targetZone.cz) or 0.0,
                        false,false,false
                    )
                    SetEntityHeading(ped, tonumber(targetZone.heading) or 0.0)
                    outsideSince = nil
                    notify('잠수존 범위를 벗어날 수 없습니다.', true)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if inAfkZone then
        SetPlayerInvincible(PlayerId(), previousInvincible)
        SetEntityInvincible(PlayerPedId(), previousInvincible)
    end
end)

exports('IsInAfkZone', function() return inAfkZone end)

print('^2[cookie_afkzone]^7 AFK ZONE CLIENT V14.2.3 EXIT STATE RECOVERY ready')
