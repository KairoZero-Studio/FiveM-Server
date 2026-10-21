local pmMode = false
local cuffed = false
local vehicleSignalState = {}
local pmTargetVehicle = nil
local pmLastPlate = nil
local pmLastSpeed = nil
local pmLastDetected = nil

local function notify(message, isError)
    TriggerEvent('cookie_admin:client:notify', message, isError == true)
end

local function getClosestPlayer(maxDistance)
    local me = PlayerPedId()
    local pos = GetEntityCoords(me)
    local best, bestDist

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if DoesEntityExist(ped) then
                local dist = #(pos - GetEntityCoords(ped))
                if dist <= maxDistance and (not bestDist or dist < bestDist) then
                    best = GetPlayerServerId(player)
                    bestDist = dist
                end
            end
        end
    end

    return best
end

local function drivenVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
        notify('운전석에서 사용할 수 있습니다.', true)
        return nil
    end
    return veh
end

local function vehicleInFront(maxDistance)
    local ped = PlayerPedId()
    local ownVeh = GetVehiclePedIsIn(ped, false)
    local fromEntity = ownVeh ~= 0 and ownVeh or ped
    local from = GetEntityCoords(fromEntity)
    local forward = GetEntityForwardVector(fromEntity)
    local to = from + (forward * maxDistance)

    local ray = StartShapeTestCapsule(
        from.x, from.y, from.z + 0.4,
        to.x, to.y, to.z + 0.4,
        3.0, 10, fromEntity, 7
    )
    local _, hit, _, _, entity = GetShapeTestResult(ray)
    if hit == 1 and entity ~= 0 and IsEntityAVehicle(entity) then
        return entity
    end

    local best, bestScore
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh ~= ownVeh and DoesEntityExist(veh) then
            local delta = GetEntityCoords(veh) - from
            local dist = #(delta)
            if dist > 1.0 and dist <= maxDistance then
                local dot = (delta.x * forward.x + delta.y * forward.y + delta.z * forward.z) / math.max(dist, 0.001)
                if dot > 0.72 then
                    local score = dist - dot * 7.0
                    if not bestScore or score < bestScore then
                        best, bestScore = veh, score
                    end
                end
            end
        end
    end
    return best
end

local function loadAnim(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local untilAt = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilAt do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function applySignals(veh, lights, siren)
    if not DoesEntityExist(veh) then return end
    if lights then
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, not siren)
    else
        SetVehicleHasMutedSirens(veh, true)
        SetVehicleSiren(veh, false)
    end
end

RegisterNetEvent('cookie_police:client:authorizedVehicleSignal', function(kind)
    local veh = drivenVehicle()
    if not veh then return end

    local netId = VehToNet(veh)
    local state = vehicleSignalState[netId] or { lights = false, siren = false }

    if kind == 'lights' then
        state.lights = not state.lights
        if not state.lights then state.siren = false end
    elseif kind == 'siren' then
        state.siren = not state.siren
        if state.siren then state.lights = true end
    end

    vehicleSignalState[netId] = state
    applySignals(veh, state.lights, state.siren)
    TriggerServerEvent('cookie_police:server:syncVehicleSignal', netId, state.lights, state.siren)
end)

RegisterNetEvent('cookie_police:client:syncVehicleSignal', function(netId, lights, siren)
    vehicleSignalState[netId] = { lights = lights == true, siren = siren == true }
    local veh = NetToVeh(tonumber(netId) or 0)
    if veh ~= 0 then applySignals(veh, lights == true, siren == true) end
end)

RegisterNetEvent('cookie_police:client:authorizedPmToggle', function()
    if not drivenVehicle() then return end
    pmMode = not pmMode

    if not pmMode then
        pmTargetVehicle = nil
        pmLastPlate, pmLastSpeed, pmLastDetected = nil, nil, nil
    end

    SendNUIMessage({ action = 'pmVisible', visible = pmMode })
    if not pmMode then
        SendNUIMessage({ action = 'pmRadar', detected = false })
    end

    notify(pmMode and 'P.M 교통단속 시스템 ON · Y로 앞 차량 정차 요청' or 'P.M 교통단속 시스템 OFF', false)
end)

RegisterNetEvent('cookie_police:client:pullOverNotice', function(officerName)
    notify(('경찰이 정차를 요청했습니다. 안전한 장소에 차량을 세워주세요. (%s)'):format(officerName or '경찰'), false)
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

RegisterNetEvent('cookie_police:client:officerCuffAnim', function()
    local ped = PlayerPedId()
    if loadAnim('mp_arresting') then
        TaskPlayAnim(ped, 'mp_arresting', 'a_uncuff', 8.0, -8.0, 2200, 48, 0.0, false, false, false)
    end
end)

RegisterNetEvent('cookie_police:client:setCuffed', function(state)
    cuffed = state == true
    local ped = PlayerPedId()

    if cuffed then
        SetEnableHandcuffs(ped, true)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        if loadAnim('mp_arresting') then
            TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
        end
        notify('수갑이 채워졌습니다.', false)
    else
        SetEnableHandcuffs(ped, false)
        DetachEntity(ped, true, false)
        ClearPedSecondaryTask(ped)
        notify('수갑이 해제되었습니다.', false)
    end
end)

RegisterNetEvent('cookie_police:client:setEscorted', function(officerServerId)
    local ped = PlayerPedId()

    if not officerServerId then
        DetachEntity(ped, true, false)
        notify('호송이 해제되었습니다.', false)
        return
    end

    local player = GetPlayerFromServerId(tonumber(officerServerId))
    if player == -1 then return end
    local officerPed = GetPlayerPed(player)
    if not DoesEntityExist(officerPed) then return end

    AttachEntityToEntity(
        ped, officerPed, GetPedBoneIndex(officerPed, 11816),
        0.35, 0.45, 0.0, 0.0, 0.0, 0.0,
        false, false, false, false, 2, true
    )
    notify('끌려가는 중입니다.', false)
end)

RegisterNetEvent('cookie_police:client:miranda', function(officerName, text)
    TriggerEvent('chat:addMessage', {
        color = { 85, 155, 255 },
        multiline = true,
        args = { ('[미란다 고지] %s'):format(officerName or '경찰'), text or Config.MirandaText }
    })
end)

RegisterNetEvent('cookie_police:client:backup', function(data)
    if not data or not data.coords then return end
    notify(('지원 요청 · %s'):format(data.officerName or '경찰관'), false)

    local c = data.coords
    local blip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    -- 단순한 노란색 위치 표시: 빨간 원형/점멸 효과 사용 안 함
    SetBlipSprite(blip, 1)
    SetBlipScale(blip, 0.95)
    SetBlipColour(blip, 5)
    SetBlipFlashes(blip, false)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('지원 요청 위치 - %s'):format(data.officerName or '경찰관'))
    EndTextCommandSetBlipName(blip)

    CreateThread(function()
        Wait((Config.BackupBlipSeconds or 35) * 1000)
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

local function command(name, description, key, handler)
    RegisterCommand('+' .. name, handler, false)
    RegisterCommand('-' .. name, function() end, false)
    RegisterKeyMapping('+' .. name, description, 'keyboard', key)
end

command('cookie_police_lights', '경찰 - 경광등 ON/OFF', Config.Keys.lights, function()
    TriggerServerEvent('cookie_police:server:requestVehicleSignal', 'lights')
end)

command('cookie_police_siren', '경찰 - 사이렌 ON/OFF', Config.Keys.siren, function()
    TriggerServerEvent('cookie_police:server:requestVehicleSignal', 'siren')
end)

command('cookie_police_pm', '경찰 - P.M 정차 명령 모드', Config.Keys.pm, function()
    TriggerServerEvent('cookie_police:server:requestPmToggle')
end)

command('cookie_police_pullover', '경찰 - P.M 앞 차량 정차 요청', Config.Keys.pullOver, function()
    if not pmMode then return end
    local veh = drivenVehicle()
    if not veh then return end

    -- 화면에 현재 표시 중인 차량을 우선 사용한다.
    local target = pmTargetVehicle
    if not target or target == 0 or not DoesEntityExist(target) then
        target = vehicleInFront(Config.PullOverDistance)
    end

    if not target then
        return notify('앞쪽에서 정차 요청할 차량을 찾지 못했습니다.', true)
    end

    local ownPos = GetEntityCoords(veh)
    local targetPos = GetEntityCoords(target)
    if #(ownPos - targetPos) > (Config.PullOverDistance + 2.0) then
        return notify('표시된 차량이 정차 요청 거리에서 벗어났습니다.', true)
    end

    local netId = VehToNet(target)
    if netId == 0 then return notify('대상 차량 정보를 찾지 못했습니다.', true) end
    TriggerServerEvent('cookie_police:server:pullOver', netId)
end)

command('cookie_police_cuff', '팩션 - 수갑 사용/해제', Config.Keys.cuff, function()
    local target = getClosestPlayer(Config.TargetDistance)
    if not target then return notify('가까운 대상이 없습니다.', true) end
    TriggerServerEvent('cookie_police:server:toggleCuff', target)
end)

command('cookie_police_miranda', '경찰 - 미란다 고지', Config.Keys.miranda, function()
    local target = getClosestPlayer(Config.TargetDistance + 1.0)
    if not target then return notify('가까운 대상이 없습니다.', true) end
    TriggerServerEvent('cookie_police:server:miranda', target)
end)

command('cookie_police_escort', '팩션 - 끌고가기/해제', Config.Keys.escort, function()
    local target = getClosestPlayer(Config.TargetDistance + 0.5)
    if not target then return notify('가까운 대상이 없습니다.', true) end
    TriggerServerEvent('cookie_police:server:toggleEscort', target)
end)

command('cookie_police_backup', '경찰 - 지원 요청', Config.Keys.backup, function()
    TriggerServerEvent('cookie_police:server:backup')
end)

CreateThread(function()
    while true do
        if cuffed then
            local ped = PlayerPedId()
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 257, true)

            if not IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3) and not IsPedRagdoll(ped) then
                if loadAnim('mp_arresting') then
                    TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)
                end
            end
            Wait(0)
        else
            Wait(400)
        end
    end
end)

-- P.M 전방 차량 레이더
-- NUM9로 켜져 있는 동안 전방 차량 번호판/실시간 속도를 NUI에 갱신한다.
CreateThread(function()
    while true do
        if pmMode then
            local myPed = PlayerPedId()
            local myVeh = GetVehiclePedIsIn(myPed, false)

            -- 운전석에서 내리면 P.M을 자동 종료한다.
            if myVeh == 0 or GetPedInVehicleSeat(myVeh, -1) ~= myPed then
                pmMode = false
                pmTargetVehicle = nil
                pmLastPlate, pmLastSpeed, pmLastDetected = nil, nil, nil
                SendNUIMessage({ action = 'pmVisible', visible = false })
                SendNUIMessage({ action = 'pmRadar', detected = false })
                notify('차량에서 내려 P.M 교통단속 시스템이 종료되었습니다.', false)
                Wait(500)
            else
                local target = vehicleInFront(Config.PullOverDistance)
                pmTargetVehicle = target

                if target and target ~= 0 and DoesEntityExist(target) then
                    local rawPlate = GetVehicleNumberPlateText(target) or ''
                    local cleanPlate = rawPlate:gsub('^%s*(.-)%s*$', '%1')
                    if cleanPlate == '' then cleanPlate = 'UNKNOWN' end
                    local kmh = math.floor((GetEntitySpeed(target) * 3.6) + 0.5)

                    -- 값이 변했을 때만 NUI 메시지를 보내 불필요한 호출을 줄인다.
                    if pmLastDetected ~= true or pmLastPlate ~= cleanPlate or pmLastSpeed ~= kmh then
                        pmLastDetected = true
                        pmLastPlate = cleanPlate
                        pmLastSpeed = kmh
                        SendNUIMessage({
                            action = 'pmRadar',
                            detected = true,
                            plate = cleanPlate,
                            speed = kmh
                        })
                    end
                else
                    if pmLastDetected ~= false then
                        pmLastDetected = false
                        pmLastPlate, pmLastSpeed = nil, nil
                        SendNUIMessage({ action = 'pmRadar', detected = false })
                    end
                end

                Wait(Config.PMRadarRefreshMs or 100)
            end
        else
            Wait(350)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'pmVisible', visible = false })
end)
