local seatUiOpen = false
local doorMenuOpen = false
local currentSeatVehicle = 0
local seatbeltOn = false
local seatbeltVehicle = 0
local lastVehicle = 0

local previousSpeed = 0.0
local previousVelocity = vector3(0.0, 0.0, 0.0)

local manualEngineOff = {}

local function dbg(...)
    if Config.Debug then
        print('^5[cookie_vehicleui]^7', ...)
    end
end

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('~y~COOKIE 차량~s~\n%s'):format(message))
    EndTextCommandThefeedPostTicker(false, false)
end

local function requestControl(entity, timeoutMs)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    if NetworkHasControlOfEntity(entity) then
        return true
    end

    NetworkRequestControlOfEntity(entity)

    local untilTime = GetGameTimer() + (timeoutMs or 1000)
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < untilTime do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end

    return NetworkHasControlOfEntity(entity)
end

local function getVehicleLabel(vehicle)
    if not vehicle or vehicle == 0 then return '차량' end

    local display = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
    if not display or display == '' or display == 'CARNOTFOUND' then
        return '차량'
    end

    local label = GetLabelText(display)
    if not label or label == '' or label == 'NULL' then
        return display
    end

    return label
end

local function isRoadVehicle(vehicle)
    if not vehicle or vehicle == 0 then return false end

    local class = GetVehicleClass(vehicle)

    -- 8 motorcycles, 13 cycles, 14 boats, 15 heli, 16 plane, 21 trains
    if class == 8 or class == 13 or class == 14 or class == 15 or class == 16 or class == 21 then
        return false
    end

    return true
end

local function seatLabel(slot)
    if slot == 1 then return '운전석' end
    if slot == 2 then return '조수석' end

    local offset = slot - 3
    local row = math.floor(offset / 2) + 2
    local side = (offset % 2 == 0) and '좌측' or '우측'
    return ('%d열 %s'):format(row, side)
end

local function findMySeat(vehicle, count)
    local ped = PlayerPedId()

    for slot = 1, count do
        local seatIndex = slot - 2
        if GetPedInVehicleSeat(vehicle, seatIndex) == ped then
            return slot
        end
    end

    return nil
end

local function buildSeatData(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local count = tonumber(GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))) or 1
    count = math.max(1, math.min(count, tonumber(Config.MaxSeats) or 32))

    local seats = {}

    for slot = 1, count do
        local seatIndex = slot - 2
        local occupant = GetPedInVehicleSeat(vehicle, seatIndex)

        local status = 'empty'
        local statusText = '비어있음'

        if occupant and occupant ~= 0 then
            if occupant == PlayerPedId() then
                status = 'self'
                statusText = '내 좌석'
            else
                -- 강도 중 네임태그 숨김을 우회하지 않도록 이름/고번은 노출 안 함.
                status = 'occupied'
                statusText = '탑승중'
            end
        end

        seats[#seats + 1] = {
            slot = slot,
            label = seatLabel(slot),
            status = status,
            statusText = statusText,
        }
    end

    local lockState = GetVehicleDoorLockStatus(vehicle)
    local unlocked = lockState == 0 or lockState == 1

    return {
        vehicle = getVehicleLabel(vehicle),
        seatCount = count,
        seats = seats,
        engineOn = GetIsVehicleEngineRunning(vehicle),
        unlocked = unlocked,
        mySeat = findMySeat(vehicle, count),
        seatbelt = seatbeltOn and seatbeltVehicle == vehicle,
    }
end

local function closeSeatUi()
    if not seatUiOpen then return end
    seatUiOpen = false
    currentSeatVehicle = 0
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'seatClose' })
end

local function openSeatUi()
    if doorMenuOpen then
        doorMenuOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'doorClose' })
    end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        notify('차량에 탑승한 상태에서 사용할 수 있습니다.')
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local data = buildSeatData(vehicle)
    if not data then return end

    currentSeatVehicle = vehicle
    seatUiOpen = true

    SetNuiFocus(true, true)
    SetCursorLocation(0.84, 0.74)

    SendNUIMessage({
        action = 'seatOpen',
        data = data
    })
end

-- ---------------------------------------------------------
-- M: 좌석 UI
-- ---------------------------------------------------------
RegisterCommand('cookie_vehicle_seats', function()
    if seatUiOpen then
        closeSeatUi()
    else
        openSeatUi()
    end
end, false)

RegisterKeyMapping(
    'cookie_vehicle_seats',
    'COOKIE - 차량 좌석 정보',
    'keyboard',
    Config.SeatKey or 'M'
)

-- ---------------------------------------------------------
-- B: 안전벨트
-- ---------------------------------------------------------
local function toggleSeatbelt()
    if not Config.Seatbelt.enabled then return end

    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    if not isRoadVehicle(vehicle) then
        return
    end

    if seatbeltVehicle ~= vehicle then
        seatbeltOn = false
    end

    seatbeltOn = not seatbeltOn
    seatbeltVehicle = vehicle

    -- V2.2: 안전벨트는 조용히 ON/OFF.
    -- 효과음과 우측 알림 메시지는 출력하지 않음.

    if seatUiOpen and currentSeatVehicle == vehicle then
        local data = buildSeatData(vehicle)
        if data then
            SendNUIMessage({ action = 'seatUpdate', data = data })
        end
    end
end

RegisterCommand('cookie_vehicle_seatbelt', toggleSeatbelt, false)

RegisterKeyMapping(
    'cookie_vehicle_seatbelt',
    'COOKIE - 안전벨트',
    'keyboard',
    Config.SeatbeltKey or 'B'
)

-- ---------------------------------------------------------
-- K: 수동 시동
-- ---------------------------------------------------------
local function engineKey(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId and netId ~= 0 then
        return ('n:%s'):format(netId)
    end
    return ('e:%s'):format(vehicle)
end

RegisterCommand('cookie_vehicle_engine', function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        notify('차량에 탑승한 상태에서 사용할 수 있습니다.')
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('운전석에서만 시동을 조작할 수 있습니다.')
        return
    end

    requestControl(vehicle, 700)

    local running = GetIsVehicleEngineRunning(vehicle)
    local key = engineKey(vehicle)

    if running then
        manualEngineOff[key] = true
        SetVehicleEngineOn(vehicle, false, true, true)
        notify('시동을 껐습니다.')
    else
        manualEngineOff[key] = nil
        SetVehicleUndriveable(vehicle, false)
        SetVehicleEngineOn(vehicle, true, true, false)
        notify('시동을 걸었습니다.')
    end
end, false)

RegisterKeyMapping(
    'cookie_vehicle_engine',
    'COOKIE - 차량 시동 ON/OFF',
    'keyboard',
    Config.EngineKey or 'U'
)


-- ---------------------------------------------------------
-- M 좌석 UI: 마우스 클릭 + 숫자키 좌석 이동
-- ---------------------------------------------------------
local function getCurrentSeatIndex(vehicle, ped)
    local count = tonumber(GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))) or 1

    for seatIndex = -1, count - 2 do
        if GetPedInVehicleSeat(vehicle, seatIndex) == ped then
            return seatIndex
        end
    end

    return nil
end

local seatMoveBusy = false

local function warpPedToSeatReliable(ped, vehicle, seatIndex)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local currentSeat = getCurrentSeatIndex(vehicle, ped)

    if currentSeat == seatIndex then
        return true
    end

    local targetOccupant = GetPedInVehicleSeat(vehicle, seatIndex)
    if targetOccupant ~= 0 and targetOccupant ~= ped then
        return false
    end

    requestControl(vehicle, 1200)

    -- 한 번 클릭했을 때 내부적으로 계속 재시도.
    -- 일부 애드온 차량은 현재 좌석 상태가 한 프레임 이상 남아 있어
    -- SetPedIntoVehicle / TaskWarpPedIntoVehicle 한 번만으로 안 옮겨질 수 있음.
    local timeout = GetGameTimer() + 1200
    local attempt = 0

    while GetGameTimer() < timeout do
        if not DoesEntityExist(vehicle) then
            return false
        end

        local occupant = GetPedInVehicleSeat(vehicle, seatIndex)
        if occupant ~= 0 and occupant ~= ped then
            return false
        end

        if GetPedInVehicleSeat(vehicle, seatIndex) == ped then
            return true
        end

        attempt = attempt + 1

        -- 첫 시도와 이후 시도를 번갈아 사용.
        if attempt % 2 == 1 then
            ClearPedTasksImmediately(ped)
            Wait(0)
            SetPedIntoVehicle(ped, vehicle, seatIndex)
        else
            TaskWarpPedIntoVehicle(ped, vehicle, seatIndex)
        end

        Wait(75)

        if GetPedInVehicleSeat(vehicle, seatIndex) == ped then
            return true
        end
    end

    -- 마지막 강제 시도.
    ClearPedTasksImmediately(ped)
    Wait(0)
    SetPedIntoVehicle(ped, vehicle, seatIndex)
    Wait(150)

    if GetPedInVehicleSeat(vehicle, seatIndex) == ped then
        return true
    end

    -- 그래도 실패하면 원래 좌석으로 복구.
    if currentSeat ~= nil and IsVehicleSeatFree(vehicle, currentSeat, false) then
        SetPedIntoVehicle(ped, vehicle, currentSeat)
    end

    return false
end

local function moveToVehicleSeat(slot)
    if seatMoveBusy then
        return false, 'busy'
    end

    seatMoveBusy = true

    local function finish(ok, reason)
        seatMoveBusy = false
        return ok, reason
    end

    local ped = PlayerPedId()

    if not seatUiOpen then
        return finish(false, 'ui_closed')
    end

    if not IsPedInAnyVehicle(ped, false) then
        closeSeatUi()
        return finish(false, 'not_in_vehicle')
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 or vehicle ~= currentSeatVehicle then
        closeSeatUi()
        return finish(false, 'vehicle_changed')
    end

    slot = tonumber(slot)
    if not slot then
        return finish(false, 'invalid_slot')
    end

    local seatCount = tonumber(GetVehicleModelNumberOfSeats(GetEntityModel(vehicle))) or 1
    seatCount = math.max(1, math.min(seatCount, tonumber(Config.MaxSeats) or 32))

    if slot < 1 or slot > seatCount then
        return finish(false, 'slot_out_of_range')
    end

    local seatIndex = slot - 2
    local occupant = GetPedInVehicleSeat(vehicle, seatIndex)

    if occupant ~= 0 and occupant ~= ped then
        return finish(false, 'occupied')
    end

    if occupant == ped then
        return finish(true, 'already_here')
    end

    seatbeltOn = false
    seatbeltVehicle = vehicle

    print(('[cookie_vehicleui] seat click -> slot %s / seatIndex %s'):format(slot, seatIndex))

    local success = warpPedToSeatReliable(ped, vehicle, seatIndex)

    print(('[cookie_vehicleui] seat move result -> %s'):format(success and 'SUCCESS' or 'FAILED'))

    if success then
        local data = buildSeatData(vehicle)
        if data then
            SendNUIMessage({
                action = 'seatUpdate',
                data = data
            })
        end
    end

    return finish(success, success and 'ok' or 'move_failed')
end

RegisterNUICallback('seatMove', function(data, cb)
    local slot = tonumber(data and (data.slot or data.seatSlot))

    -- 이전 UI 호환: seatIndex를 넘겨온 경우 slot으로 환산.
    if not slot and data and data.seatIndex ~= nil then
        slot = tonumber(data.seatIndex) + 2
    end

    local ok, reason = moveToVehicleSeat(slot)

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    cb({
        ok = ok,
        reason = reason,
        data = vehicle ~= 0 and buildSeatData(vehicle) or nil
    })
end)

RegisterNUICallback('seatNumber', function(data, cb)
    local slot = tonumber(data and data.number)
    local ok, reason = moveToVehicleSeat(slot)

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    cb({
        ok = ok,
        reason = reason,
        data = vehicle ~= 0 and buildSeatData(vehicle) or nil
    })
end)

RegisterNUICallback('seatMenuClose', function(_, cb)
    closeSeatUi()
    cb({ ok = true })
end)

-- ---------------------------------------------------------
-- J: 문 / 보닛 / 트렁크 메뉴
-- ---------------------------------------------------------
local doorDefs = {
    { id = 0, bone = 'door_dside_f', label = '운전석 문', type = 'door' },
    { id = 1, bone = 'door_pside_f', label = '조수석 문', type = 'door' },
    { id = 2, bone = 'door_dside_r', label = '좌측 뒷문', type = 'door' },
    { id = 3, bone = 'door_pside_r', label = '우측 뒷문', type = 'door' },
    { id = 4, bone = 'bonnet',       label = '보닛',      type = 'hood' },
    { id = 5, bone = 'boot',         label = '트렁크',    type = 'trunk' },
}

local function buildDoorData(vehicle)
    local controls = {}

    for _, def in ipairs(doorDefs) do
        local boneIndex = GetEntityBoneIndexByName(vehicle, def.bone)

        if boneIndex ~= -1 then
            local ratio = GetVehicleDoorAngleRatio(vehicle, def.id)
            controls[#controls + 1] = {
                id = def.id,
                label = def.label,
                type = def.type,
                open = ratio > 0.1
            }
        end
    end

    return {
        vehicle = getVehicleLabel(vehicle),
        controls = controls
    }
end

local function closeDoorMenu()
    if not doorMenuOpen then return end

    doorMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'doorClose' })
end

local function openDoorMenu()
    if seatUiOpen then
        closeSeatUi()
    end

    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then
        notify('차량에 탑승한 상태에서 사용할 수 있습니다.')
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)

    doorMenuOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'doorOpen',
        data = buildDoorData(vehicle)
    })
end

RegisterCommand('cookie_vehicle_doors', function()
    if doorMenuOpen then
        closeDoorMenu()
    else
        openDoorMenu()
    end
end, false)

RegisterKeyMapping(
    'cookie_vehicle_doors',
    'COOKIE - 차량 문/트렁크/보닛',
    'keyboard',
    Config.DoorMenuKey or 'J'
)

RegisterNUICallback('doorToggle', function(data, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local doorId = tonumber(data and data.id)

    if vehicle == 0 or doorId == nil or doorId < 0 or doorId > 5 then
        cb({ ok = false })
        return
    end

    requestControl(vehicle, 700)

    local ratio = GetVehicleDoorAngleRatio(vehicle, doorId)
    if ratio > 0.1 then
        SetVehicleDoorShut(vehicle, doorId, false)
    else
        SetVehicleDoorOpen(vehicle, doorId, false, false)
    end

    Wait(80)

    cb({
        ok = true,
        data = buildDoorData(vehicle)
    })
end)

RegisterNUICallback('doorCloseAll', function(_, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 then
        requestControl(vehicle, 700)
        for i = 0, 5 do
            SetVehicleDoorShut(vehicle, i, false)
        end
    end

    cb({
        ok = true,
        data = vehicle ~= 0 and buildDoorData(vehicle) or nil
    })
end)

RegisterNUICallback('doorMenuClose', function(_, cb)
    closeDoorMenu()
    cb({ ok = true })
end)

-- ---------------------------------------------------------
-- L: 잠금 / 해제
-- qbx_vehiclekeys 등 외부 시스템이 있으면 양보
-- ---------------------------------------------------------
local function externalVehicleKeysRunning()
    if not Config.PreferExternalVehicleKeys then return false end

    for _, resource in ipairs(Config.ExternalVehicleKeyResources or {}) do
        if GetResourceState(resource) == 'started' then
            return true
        end
    end

    return false
end

local function getLockVehicle()
    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        return GetVehiclePedIsIn(ped, false)
    end

    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 6.0, 0, 71)

    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        return vehicle
    end

    return 0
end

RegisterCommand('cookie_vehicle_lock', function()
    -- 외부 키 시스템에도 L 바인딩이 있으므로 COOKIE 쪽은 아무것도 하지 않음.
    if externalVehicleKeysRunning() then
        return
    end

    local vehicle = getLockVehicle()
    if vehicle == 0 then
        notify('주변에 차량이 없습니다.')
        return
    end

    requestControl(vehicle, 700)

    local state = GetVehicleDoorLockStatus(vehicle)
    local unlocked = state == 0 or state == 1

    if unlocked then
        SetVehicleDoorsLocked(vehicle, 2)
        SetVehicleDoorsLockedForAllPlayers(vehicle, true)
        PlayVehicleDoorCloseSound(vehicle, 1)
        notify('차량을 잠갔습니다.')
    else
        SetVehicleDoorsLocked(vehicle, 1)
        SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        PlayVehicleDoorOpenSound(vehicle, 0)
        notify('차량 잠금을 해제했습니다.')
    end
end, false)

RegisterKeyMapping(
    'cookie_vehicle_lock',
    'COOKIE - 차량 잠금/해제',
    'keyboard',
    Config.LockKey or 'L'
)

-- ---------------------------------------------------------
-- 차고 출고 초기화
-- ---------------------------------------------------------
local function initializeSpawnedVehicle(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    requestControl(vehicle, 1200)

    local function apply()
        if not DoesEntityExist(vehicle) then return end

        if Config.SpawnUnlocked then
            SetVehicleDoorsLocked(vehicle, 1)
            SetVehicleDoorsLockedForAllPlayers(vehicle, false)
        end

        if Config.SpawnEngineOn then
            SetVehicleUndriveable(vehicle, false)
            SetVehicleEngineOn(vehicle, true, true, false)
            manualEngineOff[engineKey(vehicle)] = nil
        end
    end

    -- qbx_garages 등 다른 리소스가 출고 직후 상태를 한 번 더 적용해도
    -- COOKIE 설정이 마지막에 유지되도록 짧게 재적용.
    apply()
    CreateThread(function()
        Wait(250)
        apply()
        Wait(750)
        apply()
    end)

    return true
end

exports('InitializeSpawnedVehicle', initializeSpawnedVehicle)

RegisterNetEvent('cookie_vehicleui:client:initializeVehicle', function(netId)
    netId = tonumber(netId)
    if not netId then return end

    local untilTime = GetGameTimer() + 6000
    while GetGameTimer() < untilTime do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                initializeSpawnedVehicle(vehicle)
                return
            end
        end
        Wait(100)
    end
end)

-- ---------------------------------------------------------
-- Main vehicle state thread
-- ---------------------------------------------------------
CreateThread(function()
    while true do
        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)

            if lastVehicle ~= vehicle then
                lastVehicle = vehicle
                previousSpeed = GetEntitySpeed(vehicle)
                previousVelocity = GetEntityVelocity(vehicle)

                -- 차량이 바뀌면 안전벨트는 기본 해제.
                seatbeltOn = false
                seatbeltVehicle = vehicle
            end

            -- 안전벨트 착용 시 F 하차 방지.
            if seatbeltOn and seatbeltVehicle == vehicle then
                DisableControlAction(0, 75, true)
                DisableControlAction(27, 75, true)
            end

            -- K로 수동 OFF한 차량은 운전석에 있는 동안 GTA 자동 시동을 막음.
            if GetPedInVehicleSeat(vehicle, -1) == ped then
                local key = engineKey(vehicle)
                if manualEngineOff[key] then
                    SetVehicleEngineOn(vehicle, false, false, true)
                end
            end

            -- 안전벨트 미착용 급감속 튕김
            if Config.Seatbelt.enabled
                and isRoadVehicle(vehicle)
                and not seatbeltOn
            then
                local speed = GetEntitySpeed(vehicle)
                local speedKmh = speed * 3.6
                local prevKmh = previousSpeed * 3.6
                local drop = prevKmh - speedKmh

                local minimum = tonumber(Config.Seatbelt.minSpeedKmh) or 65.0
                local ratio = tonumber(Config.Seatbelt.decelerationRatio) or 0.58
                local minimumDrop = tonumber(Config.Seatbelt.minimumSpeedDropKmh) or 35.0

                if previousSpeed > (minimum / 3.6)
                    and speed < previousSpeed * ratio
                    and drop >= minimumDrop
                then
                    local coords = GetEntityCoords(ped)
                    local forward = GetEntityForwardVector(vehicle)

                    SetEntityCoords(
                        ped,
                        coords.x + forward.x * 1.0,
                        coords.y + forward.y * 1.0,
                        coords.z + 0.15,
                        true, true, true, false
                    )

                    SetEntityVelocity(
                        ped,
                        previousVelocity.x,
                        previousVelocity.y,
                        previousVelocity.z + 1.2
                    )

                    SetPedToRagdoll(ped, 2200, 2200, 0, false, false, false)
                end

                previousSpeed = speed
                previousVelocity = GetEntityVelocity(vehicle)
            else
                previousSpeed = GetEntitySpeed(vehicle)
                previousVelocity = GetEntityVelocity(vehicle)
            end

            -- 좌석 UI 갱신
            if seatUiOpen then
                if currentSeatVehicle ~= vehicle then
                    closeSeatUi()
                else
                    local data = buildSeatData(vehicle)
                    if data then
                        SendNUIMessage({
                            action = 'seatUpdate',
                            data = data
                        })
                    end
                end
            end

            Wait(50)
        else
            if seatUiOpen then closeSeatUi() end
            if doorMenuOpen then closeDoorMenu() end

            if seatbeltOn then
                seatbeltOn = false
                seatbeltVehicle = 0
            end

            lastVehicle = 0
            previousSpeed = 0.0
            previousVelocity = vector3(0.0, 0.0, 0.0)

            Wait(300)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    SetNuiFocus(false, false)
end)

print('^2[cookie_vehicleui]^7 V3.0 loaded - one click M seat switch / B belt / K engine / J doors / L lock')
