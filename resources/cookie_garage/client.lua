print('^2[cookie_garage]^7 V5.0.0 standalone client ready')

local currentZoneId = nil
local currentMode = 'civilian'
local opening = false
local token = 0
local storing = false

local function notify(msg, err)
    TriggerEvent('cookie_admin:client:notify', tostring(msg or ''), err == true)
end

local function uiFocus(on)
    local resourceName = GetCurrentResourceName()

    if on then
        if GetResourceState('cookie_core') == 'started' then
            local ok, owner = exports.cookie_core:Acquire(resourceName, false)
            if ok ~= true then return false, owner end
        end

        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
        return true
    end

    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end

    if GetResourceState('cookie_core') == 'started' then
        pcall(function()
            exports.cookie_core:Release(resourceName)
        end)
    end

    return true
end

local function closeUi()
    opening = false
    uiFocus(false)
    SendNUIMessage({ action = 'close' })
end

local function forceDeleteLocalVehicle(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    NetworkRequestControlOfEntity(veh)
    local untilAt = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < untilAt do
        NetworkRequestControlOfEntity(veh)
        Wait(0)
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
end

local function storeCurrentVehicle(zoneId)
    if storing then return true end

    local veh = cache.vehicle
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end

    if GetPedInVehicleSeat(veh, -1) ~= PlayerPedId() then
        notify('운전석에서만 차량을 입고할 수 있습니다', true)
        return true
    end

    storing = true

    CreateThread(function()
        local props = lib.getVehicleProperties(veh) or {}
        props.engineHealth = GetVehicleEngineHealth(veh)
        props.bodyHealth = GetVehicleBodyHealth(veh)

        local netId = NetworkGetNetworkIdFromEntity(veh)
        if not netId or netId == 0 then
            storing = false
            notify('차량 네트워크 정보를 찾지 못했습니다', true)
            return
        end

        for seat = -1, 12 do
            local ped = GetPedInVehicleSeat(veh, seat)
            if ped and ped ~= 0 then TaskLeaveVehicle(ped, veh, 0) end
        end

        SetVehicleDoorsLocked(veh, 2)
        Wait(700)

        local result = lib.callback.await(
            'cookie_garage:server:storeVehicle',
            false,
            tonumber(zoneId),
            netId,
            props
        )

        storing = false

        if type(result) ~= 'table' or result.ok ~= true then
            if DoesEntityExist(veh) then
                SetVehicleDoorsLocked(veh, 1)
                SetVehicleDoorsLockedForAllPlayers(veh, false)
            end
            notify((type(result) == 'table' and result.message) or '차량 입고에 실패했습니다', true)
            return
        end

        Wait(150)
        forceDeleteLocalVehicle(veh)
        notify(('%s에 차량을 입고했습니다'):format(result.label or '차고'), false)
    end)

    return true
end

RegisterNetEvent('cookie_garage:client:interact', function(zoneId)
    currentZoneId = tonumber(zoneId)

    if not currentZoneId then
        notify('차고 비콘 정보를 찾을 수 없습니다', true)
        return
    end

    if cache.vehicle and cache.vehicle ~= 0 then
        storeCurrentVehicle(currentZoneId)
        return
    end

    opening = true
    token = token + 1
    local my = token

    local ok, owner = uiFocus(true)
    if ok == false then
        opening = false
        notify(('다른 UI(%s)가 열려 있습니다. 먼저 닫아주세요.'):format(tostring(owner or 'unknown')), true)
        return
    end

    SendNUIMessage({
        action = 'loading',
        title = '쿠키 차고',
        text = '차고 정보를 불러오는 중입니다...'
    })

    TriggerServerEvent('cookie_garage:server:requestOpen', currentZoneId)

    CreateThread(function()
        Wait(7000)
        if opening and my == token then
            notify('차고 서버 응답이 없습니다. /cookiegaragediag를 확인해주세요.', true)
            closeUi()
        end
    end)
end)

RegisterNetEvent('cookie_garage:client:openData', function(data)
    opening = false
    currentMode = tostring(data and data.mode or 'civilian')
    uiFocus(true)
    SendNUIMessage({ action = 'open', data = data or {} })
end)

RegisterNetEvent('cookie_garage:client:openFailed', function(message)
    if message and message ~= '' then notify(message, true) end
    closeUi()
end)

RegisterNetEvent('cookie_garage:client:purchaseResult', function(ok, msg)
    notify(msg or (ok and '구매 완료' or '구매 실패'), not ok)
    if ok and currentZoneId then
        opening = true
        TriggerServerEvent('cookie_garage:server:requestOpen', currentZoneId)
    else
        SendNUIMessage({ action = 'unlock' })
    end
end)

RegisterNetEvent('cookie_garage:client:saleResult', function(ok, msg)
    notify(msg or (ok and '차량 판매 완료' or '차량 판매 실패'), not ok)
    SendNUIMessage({ action = 'saleResult', ok = ok, message = msg or '' })
    if ok and currentZoneId then
        opening = true
        TriggerServerEvent('cookie_garage:server:requestOpen', currentZoneId)
    else
        SendNUIMessage({ action = 'unlock' })
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb('ok')
    closeUi()
end)

RegisterNUICallback('refresh', function(_, cb)
    cb('ok')
    if not currentZoneId then return end
    opening = true
    SendNUIMessage({
        action = 'loading',
        title = '쿠키 차고',
        text = '차량 목록을 새로고침하는 중입니다...'
    })
    TriggerServerEvent('cookie_garage:server:requestOpen', currentZoneId)
end)

RegisterNUICallback('buyGeneral', function(data, cb)
    cb('ok')
    TriggerServerEvent('cookie_garage:server:buyGeneral', data and data.model)
end)

RegisterNUICallback('buyFaction', function(_, cb)
    cb('ok')
    notify('팩션 차량은 관리자 팩션 함대에서 관리합니다', true)
    SendNUIMessage({ action = 'unlock' })
end)

RegisterNUICallback('sellGeneral', function(data, cb)
    cb('ok')
    TriggerServerEvent('cookie_garage:server:sellGeneral', data and data.id)
end)

RegisterNUICallback('spawnOwned', function(data, cb)
    cb('ok')

    local id = tonumber(data and data.id)
    if not id or not currentZoneId then
        notify('출고할 차량 또는 차고 정보가 올바르지 않습니다', true)
        SendNUIMessage({ action = 'unlock' })
        return
    end

    CreateThread(function()
        local result = lib.callback.await('cookie_garage:server:spawnOwned', false, id, currentZoneId)

        if type(result) ~= 'table' or result.ok ~= true or not result.netId then
            notify((type(result) == 'table' and result.message) or '차량 출고에 실패했습니다', true)
            SendNUIMessage({ action = 'unlock' })
            return
        end

        closeUi()

        local netId = tonumber(result.netId)
        local veh = lib.waitFor(function()
            if netId and NetworkDoesEntityExistWithNetworkId(netId) then
                local entity = NetToVeh(netId)
                if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
            end
        end, '차량 네트워크 동기화 실패', 12000)

        if not veh or veh == 0 then
            TriggerServerEvent('cookie_garage:server:spawnClientFailed', id, netId)
            notify('차량 생성 후 동기화에 실패해 자동으로 차고에 복구했습니다', true)
            return
        end

        NetworkRequestControlOfEntity(veh)
        local untilAt = GetGameTimer() + 2000
        while not NetworkHasControlOfEntity(veh) and GetGameTimer() < untilAt do
            NetworkRequestControlOfEntity(veh)
            Wait(0)
        end

        if type(result.props) == 'table' then
            pcall(function() lib.setVehicleProperties(veh, result.props) end)
        end

        SetVehicleDoorsLocked(veh, 1)
        SetVehicleDoorsLockedForAllPlayers(veh, false)
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, true, true, false)

        local ped = PlayerPedId()
        for _ = 1, 30 do
            if IsPedInVehicle(ped, veh, false) then break end
            SetPedIntoVehicle(ped, veh, -1)
            Wait(100)
        end

        if GetResourceState('cookie_vehicleui') == 'started' then
            pcall(function() exports.cookie_vehicleui:InitializeSpawnedVehicle(veh) end)
        end

        if result.plate then TriggerEvent('vehiclekeys:client:SetOwner', result.plate) end

        notify(currentMode == 'faction' and '팩션 차량을 출고했습니다' or '차량을 출고했습니다', false)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then uiFocus(false) end
end)
