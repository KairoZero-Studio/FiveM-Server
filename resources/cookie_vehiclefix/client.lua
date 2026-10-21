local lastDrivenVehicle = 0
local wasDriving = false
local guardToken = 0
local applied = {}

local function dbg(msg)
    if Config.Debug then
        print(('^3[cookie_vehiclefix]^7 %s'):format(tostring(msg)))
    end
end

local function requestControl(vehicle, timeout)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if NetworkHasControlOfEntity(vehicle) then return true end

    NetworkRequestControlOfEntity(vehicle)
    local untilAt = GetGameTimer() + (timeout or 700)

    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < untilAt do
        Wait(0)
        NetworkRequestControlOfEntity(vehicle)
    end

    return NetworkHasControlOfEntity(vehicle)
end

local function forceUnlock(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    requestControl(vehicle, 300)

    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)

    if SetVehicleDoorsLockedForPlayer then
        SetVehicleDoorsLockedForPlayer(vehicle, PlayerId(), false)
    end

    if SetVehicleDoorsLockedForNonScriptPlayers then
        SetVehicleDoorsLockedForNonScriptPlayers(vehicle, false)
    end
end

local function startExitUnlockGuard(vehicle)
    if not Config.ExitUnlockFix then return end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    guardToken = guardToken + 1
    local myToken = guardToken
    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    if Config.EnsureQbxKeysOnExit and netId and netId ~= 0 then
        TriggerServerEvent('cookie_vehiclefix:server:ensureExitKeys', netId)
    end

    CreateThread(function()
        local untilAt = GetGameTimer() + math.max(500, tonumber(Config.ExitUnlockGuardMs) or 3500)
        local tick = math.max(50, tonumber(Config.ExitUnlockTickMs) or 125)

        while myToken == guardToken
            and GetGameTimer() < untilAt
            and DoesEntityExist(vehicle)
        do
            forceUnlock(vehicle)
            Wait(tick)
        end

        if myToken == guardToken and DoesEntityExist(vehicle) then
            forceUnlock(vehicle)
        end
    end)
end

local odinHashes = {}
CreateThread(function()
    for _, model in ipairs((Config.Odin and Config.Odin.models) or {}) do
        odinHashes[joaat(tostring(model):lower())] = true
    end
end)

local function isOdin(vehicle)
    if not Config.Odin or Config.Odin.enabled ~= true then return false end
    if vehicle == 0 or not DoesEntityExist(vehicle) then return false end

    local model = GetEntityModel(vehicle)
    if odinHashes[model] then return true end

    local display = tostring(GetDisplayNameFromVehicleModel(model) or ''):upper()
    for _, needle in ipairs(Config.Odin.displayNameContains or {}) do
        needle = tostring(needle or ''):upper()
        if needle ~= '' and display:find(needle, 1, true) then
            return true
        end
    end

    return false
end

local function lowerHandling(vehicle, field, target)
    target = tonumber(target)
    if not target then return end

    local current = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field)
    if current == nil or current <= 0.0 then
        -- 0은 이미 사실상 무데미지이므로 건드리지 않음.
        return
    end

    if current > target then
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, target + 0.0)
    end
end

local function applyDurability(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local key = netId and netId ~= 0 and ('n:' .. netId) or ('e:' .. vehicle)
    local odin = isOdin(vehicle)

    -- 네트워크 소유권이 바뀌는 경우를 고려해 운전 중 주기적으로 재적용하므로
    -- applied는 단순 진단/로그용으로만 사용.
    local g = Config.GlobalDurability or {}
    if g.enabled == true then
        lowerHandling(vehicle, 'fCollisionDamageMult', g.collision)
        lowerHandling(vehicle, 'fDeformationDamageMult', g.deformation)
        lowerHandling(vehicle, 'fEngineDamageMult', g.engine)
        lowerHandling(vehicle, 'fWeaponDamageMult', g.weapon)
    end

    if odin then
        local o = Config.Odin
        lowerHandling(vehicle, 'fCollisionDamageMult', o.collision)
        lowerHandling(vehicle, 'fDeformationDamageMult', o.deformation)
        lowerHandling(vehicle, 'fEngineDamageMult', o.engine)
        lowerHandling(vehicle, 'fWeaponDamageMult', o.weapon)

        if o.strong == true and SetVehicleStrong then
            SetVehicleStrong(vehicle, true)
        end

        if o.disableEngineDegrade == true and SetVehicleEngineCanDegrade then
            SetVehicleEngineCanDegrade(vehicle, false)
        end

        if o.tyresCanBurst ~= nil then
            SetVehicleTyresCanBurst(vehicle, o.tyresCanBurst == true)
        end
    end

    if not applied[key] or applied[key] ~= (odin and 'odin' or 'global') then
        applied[key] = odin and 'odin' or 'global'
        dbg(('durability applied vehicle=%s tier=%s'):format(vehicle, applied[key]))
    end
end

-- 하차 직전 F 입력을 잡아서 qbx 키를 보장하고 잠금 해제를 시작.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            lastDrivenVehicle = vehicle
            wasDriving = true

            applyDurability(vehicle)

            local leavePressed =
                IsControlJustPressed(0, 75)
                or IsDisabledControlJustPressed(0, 75)

            if leavePressed then
                startExitUnlockGuard(vehicle)
            end

            Wait(100)
        else
            if wasDriving and lastDrivenVehicle ~= 0 then
                -- F 입력을 다른 리소스가 먹었거나 강제 하차된 경우에도 확실히 처리.
                startExitUnlockGuard(lastDrivenVehicle)
            end

            wasDriving = false
            Wait(250)
        end
    end
end)

-- 주행 중 내구도 값이 다른 리소스에 의해 덮이는 경우 재적용.
CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
            applyDurability(vehicle)
            Wait(1000)
        else
            Wait(1200)
        end
    end
end)

-- 차고 출고 리소스에서 호출할 수도 있는 수동 복구 이벤트.
RegisterNetEvent('cookie_vehiclefix:client:unlockVehicle', function(netId)
    netId = tonumber(netId)
    if not netId then return end

    local untilAt = GetGameTimer() + 5000
    while GetGameTimer() < untilAt do
        if NetworkDoesEntityExistWithNetworkId(netId) then
            local vehicle = NetToVeh(netId)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                forceUnlock(vehicle)
                applyDurability(vehicle)
                return
            end
        end
        Wait(100)
    end
end)

RegisterCommand('cookie_vehiclefix_status', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 and lastDrivenVehicle ~= 0 and DoesEntityExist(lastDrivenVehicle) then
        vehicle = lastDrivenVehicle
    end

    if vehicle == 0 then
        print('^3[cookie_vehiclefix]^7 차량을 찾지 못했습니다.')
        return
    end

    local model = GetEntityModel(vehicle)
    local display = GetDisplayNameFromVehicleModel(model)
    local lock = GetVehicleDoorLockStatus(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    local body = GetVehicleBodyHealth(vehicle)

    local collision = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fCollisionDamageMult')
    local deformation = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fDeformationDamageMult')
    local engineMult = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fEngineDamageMult')
    local weapon = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fWeaponDamageMult')

    print(('^2[cookie_vehiclefix]^7 model=%s hash=%s odin=%s lock=%s engine=%.1f body=%.1f collision=%.4f deformation=%.4f engineMult=%.4f weapon=%.4f')
        :format(
            tostring(display),
            tostring(model),
            tostring(isOdin(vehicle)),
            tostring(lock),
            engine,
            body,
            collision,
            deformation,
            engineMult,
            weapon
        ))
end, false)

RegisterCommand('cookie_vehicle_unlockfix', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 and lastDrivenVehicle ~= 0 and DoesEntityExist(lastDrivenVehicle) then
        vehicle = lastDrivenVehicle
    end

    if vehicle == 0 then return end
    startExitUnlockGuard(vehicle)
end, false)

print('^2[cookie_vehiclefix]^7 V1.0.0 exit unlock + durability + Odin ready')
