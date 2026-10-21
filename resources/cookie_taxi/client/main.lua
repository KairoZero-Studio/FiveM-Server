
RegisterNetEvent('cookie_taxi:client:pricing', function(p)
    if type(p) ~= 'table' then return end
    T.BaseFare = tonumber(p.base_fare) or T.BaseFare
    T.FreeDist = tonumber(p.free_dist) or T.FreeDist
    T.StepDist = tonumber(p.step_dist) or T.StepDist
    T.StepFare = tonumber(p.step_fare) or T.StepFare
    T.IntercityFee = tonumber(p.intercity_fee) or T.IntercityFee
    T.MaxFare = tonumber(p.max_fare) or T.MaxFare
end)



local T = Config.Taxi

local calls = {}
local onDuty = false
local job = nil
local meter = nil
local badgeShown = false

local hasVehicle = false
local available = false
local npcCall = false
local inTaxi = false
local dlgOpen = false
local arrivedVeh = nil

local function notify(msg, isErr)
    TriggerEvent('cookie_admin:client:notify', msg, isErr and true or false)
end

local function loadModel(model)
    local hash = (type(model) == 'string') and joaat(model) or model
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - t > 5000 then return nil end
        Wait(0)
    end
    return hash
end

local function placePed(ped, x, y, z, h)
    if not DoesEntityExist(ped) then return end
    FreezeEntityPosition(ped, false)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, h)
    FreezeEntityPosition(ped, true)
end

local function groundZ(x, y, fallbackZ)
    RequestCollisionAtCoord(x, y, fallbackZ)

    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() - t < 300 do
        RequestCollisionAtCoord(x, y, fallbackZ)
        Wait(0)
    end

    for _, probe in ipairs({ 1.0, 5.0, 15.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(x, y, fallbackZ + probe, false)
        if ok and math.abs(gz - fallbackZ) < 6.0 then return gz end
    end

    return fallbackZ
end

local function snapToRoadside(x, y, z)
    if not T.RoadSnap then return x, y, z, nil end

    local ok, node, heading = GetClosestVehicleNodeWithHeading(
        x, y, z, 1, 3.0, 0)
    if not ok then return x, y, z, nil end

    if #(vec3(x, y, z) - vec3(node.x, node.y, node.z)) > (T.RoadSnapMax or 60.0) then
        return x, y, z, nil
    end

    if math.abs(node.z - z) > (T.RoadSnapMaxDrop or 7.0) then
        return x, y, z, nil
    end

    local rad = math.rad(heading)
    local nx, ny = math.cos(rad), math.sin(rad)
    local off = T.RoadSideOffset or 3.2

    local ax, ay = node.x + nx * off, node.y + ny * off
    local bx, by = node.x - nx * off, node.y - ny * off

    local da = #(vec3(x, y, 0.0) - vec3(ax, ay, 0.0))
    local db = #(vec3(x, y, 0.0) - vec3(bx, by, 0.0))

    local px, py = (da <= db) and ax or bx, (da <= db) and ay or by

    local face = math.deg(math.atan2(node.y - py, node.x - px)) - 90.0

    return px, py, node.z, face % 360.0
end

local function spawnHail(c)
    if c.ped and DoesEntityExist(c.ped) then return end

    local hash = loadModel(c.data.model)
    if not hash then return end

    if not c.px then
        local px, py, pz, face = snapToRoadside(c.data.x, c.data.y, c.data.z)
        c.px, c.py, c.pz = px, py, groundZ(px, py, pz)
        c.ph = face or (c.data.h or 0.0)
    end

    if not c.zFixed then
        c.pz = groundZ(c.px, c.py, c.pz)
        c.zFixed = true
    end

    local ped = CreatePed(4, hash, c.px, c.py, c.pz + 0.15, c.ph, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdoll(ped, false)
    SetEntityHeading(ped, c.ph)

    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    c.ped = ped
end

local function despawnHail(c)
    if c.ped and DoesEntityExist(c.ped) then DeletePed(c.ped) end
    c.ped = nil
end

local function blipPos(c)
    if c.px then return c.px, c.py, c.pz end
    local px, py, pz, face = snapToRoadside(c.data.x, c.data.y, c.data.z)
    c.px, c.py, c.pz = px, py, groundZ(px, py, pz)
    c.ph = face or (c.data.h or 0.0)
    return c.px, c.py, c.pz
end

local function addBlip(c)
    if c.blip and DoesBlipExist(c.blip) then return end

    local bx, by, bz = blipPos(c)
    local b = AddBlipForCoord(bx, by, bz)
    SetBlipSprite(b, 280)
    SetBlipColour(b, 5)
    SetBlipScale(b, 0.9)
    SetBlipAsShortRange(b, false)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('손님 (' .. tostring(c.data.guest or '택시 콜') .. ')')
    EndTextCommandSetBlipName(b)
    c.blip = b

    SetNewWaypoint(bx, by)
end

local function removeBlip(c)
    if c.blip and DoesBlipExist(c.blip) then RemoveBlip(c.blip) end
    c.blip = nil
end

local function clearCalls()
    for id, c in pairs(calls) do
        despawnHail(c)
        removeBlip(c)
        calls[id] = nil
    end
end

RegisterNetEvent('cookie_taxi:client:calls', function(list)
    local seen = {}

    for _, d in ipairs(list or {}) do
        seen[d.id] = true
        if not calls[d.id] then
            calls[d.id] = { data = d, ped = nil, blip = nil }
            addBlip(calls[d.id])
        end
    end

    for id, c in pairs(calls) do
        if not seen[id] then
            despawnHail(c)
            removeBlip(c)
            calls[id] = nil
        end
    end
end)

RegisterNetEvent('cookie_taxi:client:duty', function(p)
    onDuty = (p and p.onDuty) == true
    if not onDuty then
        clearCalls()
        SendNUIMessage({ action = 'hud', show = false })
        SendNUIMessage({ action = 'offer', show = false })
        TriggerEvent('cookie_taxi:client:clearOffers')
    end
end)

CreateThread(function()
    while true do
        local wait = 700

        if onDuty and not job then
            local me = GetEntityCoords(PlayerPedId())

            for _, c in pairs(calls) do
                local hx, hy, hz = blipPos(c)
                local d = #(me - vec3(hx, hy, hz))

                if d <= (T.RenderDistance or 250.0) then
                    spawnHail(c)
                    wait = 0

                    DrawMarker(0, hx, hy, hz + 1.35, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                        0.45, 0.45, 0.55, 255, 184, 0, 190,
                        true, false, 2, nil, nil, false)
                else
                    despawnHail(c)
                end
            end
        else

            for _, c in pairs(calls) do despawnHail(c) end
        end

        Wait(wait)
    end
end)

local function nearestFreeCall(pos)
    local bestId, bestD = nil, (T.PickupRadius or 4.0)
    for id, c in pairs(calls) do
        if c.px then
            local d = #(pos - vec3(c.px, c.py, c.pz))
            if d < bestD then bestId, bestD = id, d end
        end
    end
    return bestId
end

local function showBadge(show, x, y, text)
    if show then
        SendNUIMessage({ action = 'pickBadge', show = true, x = x, y = y, text = text })
        badgeShown = true
    elseif badgeShown then
        SendNUIMessage({ action = 'pickBadge', show = false })
        badgeShown = false
    end
end

CreateThread(function()
    local lastPress = 0

    while true do
        local wait = 500

        if onDuty and not job then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                local pos = GetEntityCoords(ped)
                local id = nearestFreeCall(pos)

                if id then
                    wait = 0
                    local stopped = GetEntitySpeed(veh) < (T.StopSpeed or 2.0)
                    local c = calls[id]

                    if stopped then
                        if T.AutoPickup then
                            local now = GetGameTimer()
                            if now - lastPress > 1500 then
                                lastPress = now
                                TriggerServerEvent('cookie_taxi:server:claim', id)
                            end
                        else
                            local onScreen, sx, sy = World3dToScreen2d(c.px, c.py, c.pz + 0.95)
                            showBadge(onScreen, sx, sy, '손님 태우기')

                            if IsControlJustReleased(0, 38) then
                                local now = GetGameTimer()
                                if now - lastPress > 600 then
                                    lastPress = now
                                    showBadge(false)
                                    TriggerServerEvent('cookie_taxi:server:claim', id)
                                end
                            end
                        end
                    else
                        showBadge(false)
                    end
                else
                    showBadge(false)
                end
            else
                showBadge(false)
            end
        else
            showBadge(false)
        end

        Wait(wait)
    end
end)

local function gpsName(x, y, z)
    local s = GetStreetNameAtCoord(x + 0.0, y + 0.0, z + 0.0)
    local name = GetStreetNameFromHashKey(s)
    if not name or name == '' then
        name = GetLabelText(GetNameOfZone(x + 0.0, y + 0.0, z + 0.0))
    end
    if not name or name == '' then name = '목적지' end
    return name
end

local speech = nil

local function showSpeech(text, seconds)
    speech = { text = text, expire = GetGameTimer() + (seconds or 6) * 1000 }
end

local function hideSpeech()
    speech = nil
    SendNUIMessage({ action = 'speech', show = false })
end

CreateThread(function()
    while true do
        local wait = 250
        if speech and job and job.ped and DoesEntityExist(job.ped) then
            if GetGameTimer() >= speech.expire then
                hideSpeech()
            else
                wait = 0
                local pos = GetEntityCoords(job.ped)
                local onScreen, sx, sy = World3dToScreen2d(pos.x, pos.y, pos.z + 0.62)
                if onScreen then
                    SendNUIMessage({ action = 'speech', show = true, x = sx, y = sy, text = speech.text })
                else
                    SendNUIMessage({ action = 'speech', show = false })
                end
            end
        end
        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        local wait = 500

        if job and job.dest and not (meter and meter.arrived) then
            wait = 0
            local d = job.dest
            DrawMarker(1,
                d.x + 0.0, d.y + 0.0, d.z - 1.0,
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                4.0, 4.0, 1.5,
                255, 184, 0, 110,
                false, false, 2, false, nil, nil, false)
        end
        Wait(wait)
    end
end)

RegisterNetEvent('cookie_taxi:client:pickup', function(p)
    if not p then return end

    local c = calls[p.callId]
    local ped = c and c.ped

    job = { callId = p.callId, dest = p.dest, ped = ped, guest = p.guest }

    if c then removeBlip(c) end
    calls[p.callId] = nil

    for id, cc in pairs(calls) do
        despawnHail(cc)
        removeBlip(cc)
        calls[id] = nil
    end

    local myVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if ped and DoesEntityExist(ped) and myVeh and myVeh ~= 0 then
        FreezeEntityPosition(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
        SetPedCanRagdoll(ped, true)
        ClearPedTasksImmediately(ped)

        TaskEnterVehicle(ped, myVeh, 20000, 2, 2.0, 1, 0)

        CreateThread(function()
            local t = GetGameTimer()
            local retried = false
            local boarded = false

            while job and job.callId == p.callId do
                if not DoesEntityExist(ped) then break end

                if IsPedInAnyVehicle(ped, false) then
                    boarded = true
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    break
                end

                local el = GetGameTimer() - t

                if el > 12000 and not retried then
                    retried = true
                    local v = GetVehiclePedIsIn(PlayerPedId(), false)
                    if v and v ~= 0 then
                        ClearPedTasksImmediately(ped)
                        TaskEnterVehicle(ped, v, 20000, 2, 2.0, 1, 0)
                    end
                end

                if el > 30000 then break end
                Wait(300)
            end

            if job and job.callId == p.callId and not boarded then
                TriggerServerEvent('cookie_taxi:server:abortJob', '손님이 타지 못함')
            end
        end)
    end

    SetNewWaypoint(p.dest.x + 0.0, p.dest.y + 0.0)

    job.blip = AddBlipForCoord(p.dest.x + 0.0, p.dest.y + 0.0, p.dest.z + 0.0)
    SetBlipSprite(job.blip, 1)
    SetBlipColour(job.blip, 5)
    SetBlipRoute(job.blip, true)
    SetBlipRouteColour(job.blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('목적지: ' .. p.dest.label)
    EndTextCommandSetBlipName(job.blip)

    meter = { fare = p.baseFare or 0, meters = 0, dest = p.dest.label }
    SendNUIMessage({ action = 'hud', show = true, fare = meter.fare, meters = 0, dest = p.dest.label })

    job.destName = gpsName(p.dest.x, p.dest.y, p.dest.z)
    showSpeech(('%s로 가주세요!'):format(job.destName), 8)
end)

local meterCursor = false

local function setMeterCursor(on)
    if meterCursor == on then return end
    meterCursor = on

    SetNuiFocus(on, on)
    SendNUIMessage({ action = 'meterCursor', on = on })
end

RegisterNetEvent('cookie_taxi:client:meter', function(p)
    if not job or not p then return end
    meter = p
    p.action = 'meter'
    SendNUIMessage(p)
end)

RegisterNetEvent('cookie_taxi:client:arrived', function(p)
    if not job or not p then return end
    meter = p
    p.action = 'meter'
    SendNUIMessage(p)

    showSpeech('도착했네요. 요금 결제 부탁드려요!', 90)

    SendNUIMessage({
        action = 'bill',
        guest = job.guest or '손님',
        dest = job.destName or (job.dest and job.dest.label) or '목적지',
        fare = p.fare or 0,
        meters = p.meters or 0,
        intercity = p.intercity and true or false,
        intFee = p.intercity and (p.intFee or 0) or 0,
    })

    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)

    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh and veh ~= 0 then
        SetVehicleHandbrake(veh, true)
        FreezeEntityPosition(veh, true)
        arrivedVeh = veh
    end

end)

local function idleMeter()

    SendNUIMessage({
        action = 'meter', show = true,
        idle = true,
        started = false, intercity = false, arrived = false,
        available = available,
        npcCall = npcCall,
        fare = 0, meters = 0,
        base = T.BaseFare, intFee = T.IntercityFee,
        free = T.FreeDist, step = T.StepDist,
    })
end

CreateThread(function()
    while true do
        Wait(400)

        local was = inTaxi
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        inTaxi = hasVehicle and veh and veh ~= 0
            and GetPedInVehicleSeat(veh, -1) == ped
            and GetVehicleClass(veh) ~= nil

        if inTaxi and not job then
            idleMeter()
        elseif was and not inTaxi then

            if not job then
                setMeterCursor(false)
                SendNUIMessage({ action = 'meter', show = false })
            end
        end
    end
end)

local F2 = 289

CreateThread(function()
    while true do
        if (inTaxi or job) and not meterCursor then
            if IsControlJustPressed(0, F2) then
                setMeterCursor(true)
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

RegisterCommand('taximeter', function()
    if not (inTaxi or job) then return end
    setMeterCursor(not meterCursor)
end, false)

RegisterNUICallback('setAvailable', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:setAvailable', (data and data.on) == true)
end)

RegisterNUICallback('setNpcCall', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:setNpcCall', (data and data.on) == true)
end)

RegisterNUICallback('meterStart', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:meterStart', (data and data.intercity) == true)
end)

RegisterNUICallback('meterPay', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:pay')
end)

RegisterNUICallback('meterCursorOff', function(_, cb)
    cb({ ok = true })
    setMeterCursor(false)
end)

local offerQueue = {}
local offerNow = nil

local function showNextOffer()
    if offerNow then return end

    offerNow = table.remove(offerQueue, 1)
    if not offerNow then
        SendNUIMessage({ action = 'offer', show = false })
        return
    end

    offerNow.until_ = GetGameTimer() + (offerNow.ttl or 20) * 1000

    SendNUIMessage({
        action = 'offer', show = true,
        guest = offerNow.guest,
        dest = offerNow.dest,
        ttl = offerNow.ttl or 20,
    })
    PlaySoundFrontend(-1, 'Menu_Accept', 'Phone_SoundSet_Default', true)
end

local function closeOffer(id, silent)
    if offerNow and (id == nil or offerNow.id == id) then
        offerNow = nil
        SendNUIMessage({ action = 'offer', show = false })
    end

    if id then
        for i = #offerQueue, 1, -1 do
            if offerQueue[i].id == id then table.remove(offerQueue, i) end
        end
    end

    if not silent then showNextOffer() end
end

RegisterNetEvent('cookie_taxi:client:offer', function(p)
    if not p or not p.id then return end
    if job then return end

    if offerNow and offerNow.id == p.id then return end
    for _, o in ipairs(offerQueue) do
        if o.id == p.id then return end
    end

    offerQueue[#offerQueue + 1] = p
    showNextOffer()
end)

RegisterNetEvent('cookie_taxi:client:offerClose', function(p)
    if p and p.all then
        offerQueue = {}
        offerNow = nil
        SendNUIMessage({ action = 'offer', show = false })
        return
    end
    closeOffer(p and p.id)
end)

CreateThread(function()
    while true do
        if offerNow then
            if GetGameTimer() >= offerNow.until_ then
                local offer = offerNow
                local id = offer.id
                offerNow = nil
                SendNUIMessage({ action = 'offer', show = false })
                if offer.kind == 'player' then
                    TriggerServerEvent('cookie_taxi:server:phoneDecline', id)
                else
                    TriggerServerEvent('cookie_taxi:server:decline', id)
                end
                showNextOffer()
            end
            Wait(200)
        else
            Wait(500)
        end
    end
end)

RegisterCommand('taxiaccept', function()
    if not offerNow then return end

    local offer = offerNow
    local id = offer.id
    offerNow = nil
    offerQueue = {}

    SendNUIMessage({ action = 'offer', show = false })
    if offer.kind == 'player' then
        TriggerServerEvent('cookie_taxi:server:phoneAccept', id)
    else
        TriggerServerEvent('cookie_taxi:server:accept', id)
    end
end, false)

RegisterCommand('taxidecline', function()
    if not offerNow then return end
    local offer = offerNow
    local id = offer.id
    offerNow = nil
    SendNUIMessage({ action = 'offer', show = false })
    if offer.kind == 'player' then
        TriggerServerEvent('cookie_taxi:server:phoneDecline', id)
    else
        TriggerServerEvent('cookie_taxi:server:decline', id)
    end
    showNextOffer()
end, false)

RegisterKeyMapping('taxiaccept',  '택시 콜 수락', 'keyboard', 'ADD')
RegisterKeyMapping('taxidecline', '택시 콜 거절', 'keyboard', 'SUBTRACT')

-- 기존 F2 미터기 커서는 그대로 유지.
-- 콜이 떠 있을 때만 휠 위/아래를 수락/거절 단축키로 추가.
CreateThread(function()
    while true do
        if offerNow then
            if IsControlJustPressed(0, 241) then
                ExecuteCommand('taxiaccept')
                Wait(250)
            elseif IsControlJustPressed(0, 242) then
                ExecuteCommand('taxidecline')
                Wait(250)
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

AddEventHandler('cookie_taxi:client:clearOffers', function()
    offerQueue = {}
    offerNow = nil
    SendNUIMessage({ action = 'offer', show = false })
end)

local waitShown = false

AddEventHandler('cookie_taxi:client:dialogState', function(open)
    dlgOpen = open and true or false
end)

local lastStatus = nil

CreateThread(function()
    while true do
        Wait(500)

        local hasCall = next(calls) ~= nil
        local active = onDuty and hasVehicle and not dlgOpen and not IsPauseMenuActive()

        local status = nil
        if active then
            if job then
                status = 'driving'
            elseif hasCall then
                status = 'driving'
            elseif available and not offerNow and #offerQueue == 0 then
                status = 'waiting'
            end
        end

        if status ~= lastStatus then
            lastStatus = status
            SendNUIMessage({ action = 'status', status = status })
        end

    end
end)

CreateThread(function()
    while true do
        if job then
            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
            if veh and veh ~= 0 then

                if IsEntityDead(veh) or GetVehicleEngineHealth(veh) <= 0.0 then
                    TriggerServerEvent('cookie_taxi:server:abortJob', '차량 파손')
                end
            end
            Wait(700)
        else
            Wait(1500)
        end
    end
end)

local function endJob()
    if job then
        if job.blip and DoesBlipExist(job.blip) then
            SetBlipRoute(job.blip, false)
            RemoveBlip(job.blip)
        end
        if job.ped and DoesEntityExist(job.ped) then
            local p = job.ped
            SetEntityAsNoLongerNeeded(p)
            CreateThread(function()
                Wait(8000)
                if DoesEntityExist(p) then DeletePed(p) end
            end)
        end
    end

    if arrivedVeh and DoesEntityExist(arrivedVeh) then
        FreezeEntityPosition(arrivedVeh, false)
        SetVehicleHandbrake(arrivedVeh, false)
    end
    arrivedVeh = nil

    job = nil
    meter = nil
    setMeterCursor(false)
    hideSpeech()
    SendNUIMessage({ action = 'bill', show = false })
    SendNUIMessage({ action = 'meter', show = false })
    TriggerServerEvent('cookie_taxi:server:requestCalls')
end

RegisterNetEvent('cookie_taxi:client:receipt', function(p)
    if not p then return end

    SendNUIMessage({ action = 'bill', show = false })

    if job and job.ped and DoesEntityExist(job.ped) then
        TaskLeaveVehicle(job.ped, GetVehiclePedIsIn(PlayerPedId(), false), 0)
    end

    p.action = 'receipt'
    SendNUIMessage(p)

    endJob()

end)

RegisterNetEvent('cookie_taxi:client:cancel', function(p)
    if job and job.ped and DoesEntityExist(job.ped) then
        DeletePed(job.ped)
        job.ped = nil
    end
    endJob()

end)

RegisterNetEvent('cookie_taxi:client:line', function(text)
    SendNUIMessage({ action = 'sub', text = text })
end)

local function ghostVehicle(netId, seconds)
    CreateThread(function()
        local veh, t = 0, GetGameTimer()
        while GetGameTimer() - t < 3000 do
            if NetworkDoesNetworkIdExist(netId) then
                veh = NetToVeh(netId)
                if veh and veh ~= 0 and DoesEntityExist(veh) then break end
            end
            Wait(50)
        end
        if not veh or veh == 0 or not DoesEntityExist(veh) then return end

        SetEntityAlpha(veh, T.GhostAlpha or 160, false)

        local until_ = GetGameTimer() + (seconds or 5) * 1000
        while GetGameTimer() < until_ do
            if not DoesEntityExist(veh) then return end
            if IsPedInVehicle(PlayerPedId(), veh, false) then break end

            local pos = GetEntityCoords(veh)
            for _, ped in ipairs(GetGamePool('CPed')) do
                if DoesEntityExist(ped) and #(GetEntityCoords(ped) - pos) < 12.0 then
                    SetEntityNoCollisionEntity(veh, ped, true)
                    SetEntityNoCollisionEntity(ped, veh, true)
                end
            end

            Wait(0)
        end

        if DoesEntityExist(veh) then ResetEntityAlpha(veh) end
    end)
end


RegisterNetEvent('cookie_taxi:client:phoneAssigned', function(p)
    if not p or not p.callId or not p.pickup then return end

    if job and job.blip and DoesBlipExist(job.blip) then
        SetBlipRoute(job.blip, false)
        RemoveBlip(job.blip)
    end

    local blip = AddBlipForCoord(p.pickup.x + 0.0, p.pickup.y + 0.0, p.pickup.z + 0.0)
    SetBlipSprite(blip, 280)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.82)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('시민 택시 호출 · 승객')
    EndTextCommandSetBlipName(blip)

    job = {
        type = 'player',
        callId = p.callId,
        customer = p.customer,
        pickup = p.pickup,
        dest = p.dest,
        guest = p.guest or '시민 승객',
        blip = blip,
    }

    clearCalls()
    SendNUIMessage({ action = 'sub', text = '시민 승객 위치로 이동하세요.' })
end)

RegisterNetEvent('cookie_taxi:client:phoneBoarded', function(p)
    if not job or job.type ~= 'player' then return end

    if job.blip and DoesBlipExist(job.blip) then
        SetBlipRoute(job.blip, false)
        RemoveBlip(job.blip)
        job.blip = nil
    end

    local d = p and p.dest or job.dest
    if d then
        local blip = AddBlipForCoord(d.x + 0.0, d.y + 0.0, d.z + 0.0)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, 5)
        SetBlipScale(blip, 0.82)
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, 5)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(d.label or '승객 목적지')
        EndTextCommandSetBlipName(blip)
        job.blip = blip
    end

    SendNUIMessage({ action = 'sub', text = '승객이 탑승했습니다. 목적지로 이동하세요.' })
end)

RegisterNetEvent('cookie_taxi:client:phoneCancelled', function(p)
    if job and job.type == 'player' then
        if job.blip and DoesBlipExist(job.blip) then
            SetBlipRoute(job.blip, false)
            RemoveBlip(job.blip)
        end
        job = nil
        meter = nil
        SendNUIMessage({ action = 'meter', show = false })
        SendNUIMessage({ action = 'sub', text = '' })
    end
end)

RegisterNetEvent('cookie_taxi:client:assigned', function(p)
    if not p then return end
    notify(('%s 배정 (%s)'):format(p.label, p.plate), false)

    if p.netId then ghostVehicle(p.netId, p.ghost or 5) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearCalls()
    if job and job.ped and DoesEntityExist(job.ped) then DeletePed(job.ped) end
    if job and job.blip and DoesBlipExist(job.blip) then RemoveBlip(job.blip) end
    SetNuiFocus(false, false)
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('cookie_taxi:server:requestState')
    TriggerServerEvent('cookie_taxi:server:requestCalls')
end)

RegisterNetEvent('cookie_taxi:client:state', function(s)
    if type(s) ~= 'table' then return end

    local was = onDuty
    onDuty = (s.onDuty == true)
    hasVehicle = (s.assigned ~= nil)
    available = (s.available == true)
    npcCall = (s.npcCall == true)

    if was and not onDuty then clearCalls() end

    if inTaxi and not job then idleMeter() end
end)