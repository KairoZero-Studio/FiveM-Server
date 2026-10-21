

local function tlog(...)
    if Config.Debug then  end
end

local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

local T = Config.Taxi

local calls = {}
local jobs = {}
local nextCallId = 1

-- COOKIE PHONE 시민 택시 호출
local phoneCalls = {}
local phoneCallsByCustomer = {}
local nextPhoneCallId = 100000

local function activeHailCount()
    local n = 0
    for _, c in pairs(calls) do
        if not c.claimedBy then n = n + 1 end
    end
    return n
end

function CookieTaxiHasJob(src)
    return jobs[src] ~= nil
end

local function hasAcceptedCall(src)
    for _, c in pairs(calls) do
        if c.acceptedBy == src and not c.claimedBy then return true end
    end
    return false
end


local function hasAcceptedPhoneCall(src)
    for _, c in pairs(phoneCalls) do
        if c.acceptedBy == src and c.state ~= 'done' then return true end
    end
    return false
end

local function eligiblePhoneDriver(src)
    return CookieTaxiOnDuty(src)
        and CookieTaxiAssignedVeh(src) ~= nil
        and CookieTaxiAvailable(src)
        and jobs[src] == nil
        and not hasAcceptedCall(src)
        and not hasAcceptedPhoneCall(src)
end

local function phoneEmit(src, data)
    if not src or not GetPlayerName(src) then return end
    TriggerClientEvent('cookie_phone:client:taxiStatus', src, data or {})
end

local function currentPricing()
    local ok, row = pcall(function()
        return exports.cookie_taxi:getPricing()
    end)
    if ok and type(row) == 'table' then return row end
    return {
        base_fare = T.BaseFare or 5500,
        free_dist = T.FreeDist or 1000,
        step_dist = T.StepDist or 500,
        step_fare = T.StepFare or 200,
        intercity_fee = T.IntercityFee or 2000,
        max_fare = T.MaxFare or 200000,
    }
end

local function estimateFare(pickup, dest)
    if not pickup or not dest then return 0, 0 end
    local meters = #(vec3(pickup.x, pickup.y, pickup.z) - vec3(dest.x, dest.y, dest.z))
    local pc = currentPricing()
    local fare = tonumber(pc.base_fare) or T.BaseFare or 5500
    local free = tonumber(pc.free_dist) or T.FreeDist or 1000
    local step = tonumber(pc.step_dist) or T.StepDist or 500
    local stepFare = tonumber(pc.step_fare) or T.StepFare or 200

    if meters > free and step > 0 then
        fare = fare + math.floor((meters - free) / step) * stepFare
    end

    return math.min(math.floor(fare), tonumber(pc.max_fare) or T.MaxFare or 200000), meters
end

local function phoneDriverCount()
    local n = 0
    for _, sid in ipairs(CookieTaxiDrivers()) do
        if eligiblePhoneDriver(sid) then n = n + 1 end
    end
    return n
end

local function closePhoneOffers(callId)
    for _, sid in ipairs(CookieTaxiDrivers()) do
        TriggerClientEvent('cookie_taxi:client:offerClose', sid, { id = callId })
    end
end

local function clearPhoneCall(call, status)
    if not call then return end
    phoneCalls[call.id] = nil
    if phoneCallsByCustomer[call.customer] == call.id then
        phoneCallsByCustomer[call.customer] = nil
    end
    closePhoneOffers(call.id)

    if status and GetPlayerName(call.customer) then
        phoneEmit(call.customer, {
            state = status,
            callId = call.id,
            destination = call.dest and call.dest.label or '목적지',
        })
    end
end

local function eligible(src)
    return CookieTaxiOnDuty(src)
        and CookieTaxiAssignedVeh(src) ~= nil
        and CookieTaxiAvailable(src)
        and CookieTaxiNpcCall(src)
        and jobs[src] == nil
        and not hasAcceptedCall(src)
end

local function callPayload(c)
    return {
        id = c.id,
        x = c.hail.x, y = c.hail.y, z = c.hail.z, h = c.hail.h,
        model = c.model,
        guest = c.guest,
    }
end

local function pushMyCall(src)
    local list = {}
    for _, c in pairs(calls) do
        if c.acceptedBy == src and not c.claimedBy then
            list[#list + 1] = callPayload(c)
        end
    end
    TriggerClientEvent('cookie_taxi:client:calls', src, list)
end

local function offerCall(c)
    if c.acceptedBy or c.claimedBy then return end

    for _, src in ipairs(CookieTaxiDrivers()) do
        if eligible(src) and not c.declined[src] and not c.offered[src] then
            c.offered[src] = true
            TriggerClientEvent('cookie_taxi:client:offer', src, {
                id    = c.id,
                guest = c.guest,
                dest  = c.dest.label,
                ttl   = T.OfferTTL or 20,
            })
        end
    end
end

local function makeCall()
    local presets = CookieTaxiCalls and CookieTaxiCalls() or {}
    if #presets == 0 then

        return
    end

    local used = {}
    for _, c in pairs(calls) do
        if not c.claimedBy then used[c.presetId] = true end
    end

    local pool = {}
    for _, p in ipairs(presets) do
        if not used[p.id] then pool[#pool + 1] = p end
    end
    if #pool == 0 then return end

    local pick = pool[math.random(#pool)]

    local hail = { x = pick.px, y = pick.py, z = pick.pz, h = pick.ph or 0.0 }
    local dest = { label = pick.name .. ' 하차지', x = pick.dx, y = pick.dy, z = pick.dz }

    local peds = T.HailPeds or { 'a_m_y_stwhi_01' }

    local c = {
        id = nextCallId,
        presetId = pick.id,
        hail = hail,
        dest = dest,
        guest = pick.name,
        model = (pick.model and pick.model ~= '' and pick.model)
            or peds[math.random(#peds)],
        declined = {},
        offered = {},
        acceptedBy = nil,
        born = os.time(),
        claimedBy = nil,
    }
    nextCallId = nextCallId + 1
    calls[c.id] = c

    offerCall(c)
end

local function waitingDrivers()
    local n = 0
    for _, src in ipairs(CookieTaxiDrivers()) do
        if eligible(src) then n = n + 1 end
    end
    return n
end

local nextCallAt = 0

CreateThread(function()
    Wait(10000)
    nextCallAt = os.time() + math.random(10, 25)

    while true do
        Wait(2000)

        local now = os.time()

        if waitingDrivers() == 0 then
            nextCallAt = now + 15
        elseif activeHailCount() >= (T.MaxActiveHails or 3) then

            nextCallAt = now + 15
        elseif now >= nextCallAt then
            makeCall()

            local gap = math.random(T.CallInterval.min or 90, T.CallInterval.max or 240)

            if waitingDrivers() > 0 and activeHailCount() == 0 then
                gap = math.min(gap, T.IdleCallMax or 45)
            end

            nextCallAt = now + gap

        end
    end
end)

AddEventHandler('cookie_taxi:server:driverReady', function()
    if activeHailCount() == 0 then
        local soon = os.time() + math.random(8, 20)
        if soon < nextCallAt then
            nextCallAt = soon

        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)

        local now = os.time()

        for id, c in pairs(calls) do
            if not c.acceptedBy and not c.claimedBy then

                if (now - c.born) > (T.HailTTL or 600) then
                    calls[id] = nil

                else
                    offerCall(c)
                end
            end
        end
    end
end)

local pendingRespawn = 0

local function dropDeadCall(c)
    if c.acceptedBy or c.claimedBy then return false end

    local anyLeft = false
    for _, src in ipairs(CookieTaxiDrivers()) do
        if eligible(src) and not c.declined[src] then anyLeft = true break end
    end
    if anyLeft then return false end

    calls[c.id] = nil

    pendingRespawn = os.time() + math.random(T.RespawnAfterDecline.min or 15,
                                             T.RespawnAfterDecline.max or 40)
    return true
end

CreateThread(function()
    while true do
        Wait(2000)
        if pendingRespawn > 0 and os.time() >= pendingRespawn then
            pendingRespawn = 0
            if #GetPlayers() < (T.NpcCallMaxPlayers or 50)
                and activeHailCount() < (T.MaxActiveHails or 3) then
                makeCall()
            end
        end
    end
end)


RegisterNetEvent('cookie_taxi:server:phoneInfo', function()
    local src = source
    local pc = currentPricing()
    local callId = phoneCallsByCustomer[src]
    local call = callId and phoneCalls[callId] or nil
    local state = 'idle'

    if call then
        if call.acceptedBy then state = call.boarded and 'riding' or 'assigned'
        else state = 'searching' end
    end

    phoneEmit(src, {
        state = state,
        callId = call and call.id or nil,
        destination = call and call.dest and call.dest.label or nil,
        estimate = call and call.estimate or nil,
        drivers = phoneDriverCount(),
        pricing = pc,
    })
end)

RegisterNetEvent('cookie_taxi:server:phoneRequest', function(data)
    local customer = source
    if type(data) ~= 'table' or type(data.pickup) ~= 'table' or type(data.dest) ~= 'table' then return end

    if phoneCallsByCustomer[customer] then
        return phoneEmit(customer, { state = 'error', message = '이미 택시를 호출한 상태입니다.' })
    end

    local px, py, pz = tonumber(data.pickup.x), tonumber(data.pickup.y), tonumber(data.pickup.z)
    local dx, dy, dz = tonumber(data.dest.x), tonumber(data.dest.y), tonumber(data.dest.z)
    if not (px and py and pz and dx and dy and dz) then
        return phoneEmit(customer, { state = 'error', message = '호출 위치 또는 목적지가 올바르지 않습니다.' })
    end

    local ped = GetPlayerPed(customer)
    if not ped or ped == 0 then return end
    local actual = GetEntityCoords(ped)
    if #(actual - vec3(px, py, pz)) > 35.0 then
        return phoneEmit(customer, { state = 'error', message = '현재 위치를 다시 불러온 뒤 호출하세요.' })
    end

    if phoneDriverCount() <= 0 then
        return phoneEmit(customer, {
            state = 'unavailable',
            message = '현재 배차 가능한 택시기사가 없습니다.',
            drivers = 0,
            pricing = currentPricing(),
        })
    end

    nextPhoneCallId = nextPhoneCallId + 1
    local estimate, meters = estimateFare(
        {x=px,y=py,z=pz},
        {x=dx,y=dy,z=dz}
    )

    local call = {
        id = nextPhoneCallId,
        kind = 'player',
        customer = customer,
        pickup = {
            x = px, y = py, z = pz,
            label = tostring(data.pickupLabel or '현재 위치'):sub(1, 60)
        },
        dest = {
            x = dx, y = dy, z = dz,
            label = tostring(data.destLabel or '지도 목적지'):sub(1, 60)
        },
        estimate = estimate,
        straightMeters = meters,
        acceptedBy = nil,
        declined = {},
        offered = {},
        created = os.time(),
        state = 'searching',
        boarded = false,
    }

    phoneCalls[call.id] = call
    phoneCallsByCustomer[customer] = call.id

    local customerName = ('시민 #%s'):format(customer)
    for _, sid in ipairs(CookieTaxiDrivers()) do
        if eligiblePhoneDriver(sid) then
            call.offered[sid] = true
            TriggerClientEvent('cookie_taxi:client:offer', sid, {
                id = call.id,
                kind = 'player',
                guest = customerName,
                dest = call.dest.label,
                ttl = math.max(20, T.OfferTTL or 20),
            })
        end
    end

    phoneEmit(customer, {
        state = 'searching',
        callId = call.id,
        destination = call.dest.label,
        estimate = estimate,
        drivers = phoneDriverCount(),
        pricing = currentPricing(),
    })

    SetTimeout(60000, function()
        local current = phoneCalls[call.id]
        if current and not current.acceptedBy then
            clearPhoneCall(current, 'expired')
        end
    end)
end)

RegisterNetEvent('cookie_taxi:server:phoneAccept', function(callId)
    local driver = source
    local call = phoneCalls[tonumber(callId) or 0]
    if not call then return end

    if not eligiblePhoneDriver(driver) then
        TriggerClientEvent('cookie_taxi:client:offerClose', driver, { id = call.id })
        return notify(driver, '지금은 시민 택시 콜을 받을 수 없습니다.', true)
    end

    if call.acceptedBy then
        TriggerClientEvent('cookie_taxi:client:offerClose', driver, { id = call.id })
        return notify(driver, '다른 기사가 먼저 접수했습니다.', true)
    end

    call.acceptedBy = driver
    call.state = 'assigned'
    call.acceptedAt = os.time()
    closePhoneOffers(call.id)

    local dPed = GetPlayerPed(driver)
    local dPos = dPed and dPed ~= 0 and GetEntityCoords(dPed) or vec3(call.pickup.x, call.pickup.y, call.pickup.z)

    jobs[driver] = {
        type = 'player',
        callId = call.id,
        customer = call.customer,
        pickup = call.pickup,
        dest = call.dest,
        guest = ('시민 #%s'):format(call.customer),
        meters = 0.0,
        lastPos = dPos,
        boarded = false,
        boardedAt = nil,
        acceptedAt = os.time(),
        started = false,
        startedAt = nil,
        intercity = false,
        arrived = false,
        outOfVehSince = nil,
        tick = 0,
    }

    TriggerClientEvent('cookie_taxi:client:phoneAssigned', driver, {
        callId = call.id,
        customer = call.customer,
        pickup = call.pickup,
        dest = call.dest,
        guest = jobs[driver].guest,
    })

    local driverPed = GetPlayerPed(driver)
    local pickup = vec3(call.pickup.x, call.pickup.y, call.pickup.z)
    local driverDist = driverPed and driverPed ~= 0 and #(GetEntityCoords(driverPed) - pickup) or 0

    phoneEmit(call.customer, {
        state = 'assigned',
        callId = call.id,
        destination = call.dest.label,
        estimate = call.estimate,
        driverDistance = math.floor(driverDist),
    })

    notify(driver, '시민 택시 콜을 접수했습니다. 승객 위치로 이동하세요.', false)
end)

RegisterNetEvent('cookie_taxi:server:phoneDecline', function(callId)
    local driver = source
    local call = phoneCalls[tonumber(callId) or 0]
    if not call or call.acceptedBy then return end

    call.declined[driver] = true
    TriggerClientEvent('cookie_taxi:client:offerClose', driver, { id = call.id })

    local left = 0
    for _, sid in ipairs(CookieTaxiDrivers()) do
        if eligiblePhoneDriver(sid) and not call.declined[sid] then
            left = left + 1
        end
    end
    if left <= 0 then
        clearPhoneCall(call, 'unavailable')
    end
end)

RegisterNetEvent('cookie_taxi:server:phoneCancel', function()
    local customer = source
    local callId = phoneCallsByCustomer[customer]
    local call = callId and phoneCalls[callId]
    if not call then
        return phoneEmit(customer, { state = 'idle' })
    end

    if call.boarded then
        return phoneEmit(customer, { state = 'error', message = '탑승 후에는 기사에게 하차를 요청하세요.' })
    end

    if call.acceptedBy and jobs[call.acceptedBy] and jobs[call.acceptedBy].callId == call.id then
        local driver = call.acceptedBy
        jobs[driver] = nil
        TriggerClientEvent('cookie_taxi:client:phoneCancelled', driver, { reason = '승객 호출 취소' })
        notify(driver, '승객이 택시 호출을 취소했습니다.', true)
    end

    clearPhoneCall(call, nil)
    phoneEmit(customer, { state = 'cancelled' })
end)

RegisterNetEvent('cookie_taxi:server:accept', function(callId)
    local src = source
    local c = calls[tonumber(callId) or 0]
    if not c then return end

    if not eligible(src) then
        TriggerClientEvent('cookie_taxi:client:offerClose', src, { id = callId })
        return notify(src, '지금은 콜을 받을 수 없습니다', true)
    end

    if c.acceptedBy then
        TriggerClientEvent('cookie_taxi:client:offerClose', src, { id = c.id })
        return notify(src, '다른 기사가 먼저 접수했습니다', true)
    end

    c.acceptedBy = src

    for _, other in ipairs(CookieTaxiDrivers()) do
        if other ~= src then
            TriggerClientEvent('cookie_taxi:client:offerClose', other, { id = c.id })
        end
    end

    TriggerClientEvent('cookie_taxi:client:offerClose', src, { id = c.id, accepted = true })
    pushMyCall(src)

    notify(src, ('콜을 접수했습니다. %s님을 태우러 가세요'):format(c.guest), false)

end)

RegisterNetEvent('cookie_taxi:server:decline', function(callId)
    local src = source
    local c = calls[tonumber(callId) or 0]
    if not c then return end

    c.declined[src] = true
    TriggerClientEvent('cookie_taxi:client:offerClose', src, { id = c.id })

    notify(src, '콜을 거절했습니다', true)

    dropDeadCall(c)
end)

RegisterNetEvent('cookie_taxi:server:claim', function(callId)
    local src = source

    if not CookieTaxiOnDuty(src) then return notify(src, '출근한 택시기사만 손님을 태울 수 있습니다', true) end

    local myVeh = CookieTaxiAssignedVeh(src)
    if not myVeh then return notify(src, '배정받은 택시가 없습니다', true) end

    if jobs[src] then return notify(src, '이미 손님을 태우고 있습니다', true) end

    local c = calls[tonumber(callId) or 0]
    if not c then return end
    if c.claimedBy then
        return notify(src, '다른 기사가 먼저 태웠습니다', true)
    end

    if c.acceptedBy ~= src then
        return notify(src, '접수하지 않은 콜입니다', true)
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local pos = GetEntityCoords(ped)
    local d = #(pos - vec3(c.hail.x, c.hail.y, c.hail.z))
    if d > (T.ClaimTolerance or 40.0) then
        return notify(src, '손님에게 더 가까이 대세요', true)
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 or veh ~= myVeh then
        return notify(src, '배정받은 택시에 탑승한 상태여야 합니다', true)
    end

    c.claimedBy = src
    jobs[src] = {
        callId = c.id,
        dest = c.dest,
        guest = c.guest,
        meters = 0.0,
        lastPos = pos,
        boardedAt = os.time(),

        started = false,
        startedAt = nil,
        intercity = false,
        arrived = false,
        outOfVehSince = nil,
        tick = 0,
    }

    TriggerClientEvent('cookie_taxi:client:pickup', src, {
        callId = c.id,
        hail = c.hail,
        dest = c.dest,
        guest = c.guest,
        baseFare = T.BaseFare,
    })

end)

local function fareOf(job)
    if not job.started then return 0 end

    local fare = T.BaseFare or 0
    local free = T.FreeDist or 1000.0
    local step = T.StepDist or 500.0

    if step > 0 and job.meters > free then
        local steps = math.floor((job.meters - free) / step)
        fare = fare + steps * (T.StepFare or 0)
    end

    if job.intercity then fare = fare + (T.IntercityFee or 0) end

    return math.min(fare, T.MaxFare or 200000)
end

local function meterPayload(job)
    return {
        show      = true,
        started   = job.started,
        intercity = job.intercity,
        arrived   = job.arrived,
        fare      = fareOf(job),
        meters    = math.floor(job.meters),
        dest      = job.dest.label,
        guest     = job.guest,
        base      = T.BaseFare,
        intFee    = T.IntercityFee,
        free      = T.FreeDist,
        step      = T.StepDist,
        elapsed   = job.startedAt and (os.time() - job.startedAt) or 0,
    }
end

local function pushMeter(src, job)
    TriggerClientEvent('cookie_taxi:client:meter', src, meterPayload(job))
end

RegisterNetEvent('cookie_taxi:server:meterStart', function(intercity, only)
    local src = source
    if not cookieAllowAction(src, 'taxi_meter', 700, 1) then return end
    local job = jobs[src]
    if not job then return end
    if job.arrived then return end

    if job.type == 'player' and not job.boarded then
        return notify(src, '승객이 택시에 탑승한 뒤 미터기를 켜세요.', true)
    end

    job.intercity = (intercity == true)

    if only ~= true and not job.started then
        job.started = true
        job.startedAt = os.time()

        notify(src, '미터기를 켰습니다', false)
    else

    end

    pushMeter(src, job)
end)

CreateThread(function()
    local tickMs = T.MeterTick or 250
    local pushEvery = T.PushEvery or 4

    while true do
        Wait(tickMs)

        for src, job in pairs(jobs) do
            local ped = GetPlayerPed(src)

            if not ped or ped == 0 then
                jobs[src] = nil
            else
                local veh = GetVehiclePedIsIn(ped, false)
                local myVeh = CookieTaxiAssignedVeh(src)
                local inTaxi = myVeh and veh and veh ~= 0 and veh == myVeh

                local pos = GetEntityCoords(ped)

                if job.type == 'player' then
                    local call = phoneCalls[job.callId]
                    local customerPed = job.customer and GetPlayerPed(job.customer) or 0

                    if not call or not customerPed or customerPed == 0 then
                        CookieTaxiCancelJob(src, '승객 접속 종료')
                        goto continue
                    end

                    if not job.boarded then
                        local customerVeh = GetVehiclePedIsIn(customerPed, false)
                        if myVeh and customerVeh and customerVeh ~= 0 and customerVeh == myVeh then
                            job.boarded = true
                            job.boardedAt = os.time()
                            call.boarded = true
                            call.state = 'riding'
                            TriggerClientEvent('cookie_taxi:client:phoneBoarded', src, {
                                dest = job.dest,
                                guest = job.guest,
                            })
                            phoneEmit(job.customer, {
                                state = 'riding',
                                callId = job.callId,
                                destination = job.dest.label,
                                estimate = call.estimate,
                            })
                            notify(src, '승객이 탑승했습니다. 목적지로 이동하세요.', false)
                        else
                            local cpos = GetEntityCoords(customerPed)
                            local distToCustomer = #(pos - cpos)
                            if distToCustomer <= 12.0 and not job.arrivalNotified then
                                job.arrivalNotified = true
                                phoneEmit(job.customer, {
                                    state = 'driver_arrived',
                                    callId = job.callId,
                                    destination = job.dest.label,
                                })
                                notify(src, '승객 근처에 도착했습니다.', false)
                            end
                        end
                    end
                end

                if inTaxi then
                    job.outOfVehSince = nil

                    if job.started and not job.arrived then
                        local d = #(pos - job.lastPos)

                        if d >= (T.MeterMinMove or 0.05) and d <= (T.MaxTickMove or 60.0) then
                            job.meters = job.meters + d
                        end
                    end
                    job.lastPos = pos
                else

                    job.outOfVehSince = job.outOfVehSince or os.time()
                    if (os.time() - job.outOfVehSince) > (T.OutOfVehLimit or 60) then
                        CookieTaxiCancelJob(src, '차량 이탈')
                        goto continue
                    end
                end

                if job.started and not job.arrived then
                    local dd = #(pos - vec3(job.dest.x, job.dest.y, job.dest.z))
                    if dd <= (T.DropRadius or 20.0) then
                        job.arrived = true

                        TriggerClientEvent('cookie_taxi:client:arrived', src, meterPayload(job))
                    end
                end

                local timeoutBase = job.boardedAt or job.acceptedAt or os.time()
                if (os.time() - timeoutBase) > (T.JobTimeout or 900) then
                    CookieTaxiCancelJob(src, '시간 초과')
                    goto continue
                end

                job.tick = job.tick + 1
                if job.tick % pushEvery == 0 then
                    pushMeter(src, job)
                end
            end

            ::continue::
        end
    end
end)

RegisterNetEvent('cookie_taxi:server:pay', function()
    local src = source
    if not cookieAllowAction(src, 'taxi_pay', 1500, 1) then return end
    local job = jobs[src]
    if not job then return end

    if not job.started then
        return notify(src, '미터기를 켜지 않았습니다', true)
    end

    local p = exports.qbx_core:GetPlayer(src)
    local ped = GetPlayerPed(src)
    if not p or not ped or ped == 0 then return end

    local pos = GetEntityCoords(ped)
    local d = #(pos - vec3(job.dest.x, job.dest.y, job.dest.z))
    if d > ((T.DropRadius or 20.0) + 5.0) then
        return notify(src, '아직 목적지가 아닙니다', true)
    end

    local fare = fareOf(job)

    if job.type == 'player' then
        local cp = job.customer and exports.qbx_core:GetPlayer(job.customer) or nil
        if not cp then return notify(src, '승객이 접속해 있지 않습니다.', true) end

        local customerPed = GetPlayerPed(job.customer)
        local myVeh = CookieTaxiAssignedVeh(src)
        if not customerPed or customerPed == 0 or not myVeh or GetVehiclePedIsIn(customerPed, false) ~= myVeh then
            return notify(src, '승객이 택시에 탑승한 상태여야 결제할 수 있습니다.', true)
        end

        local bank = cp.Functions.GetMoney and cp.Functions.GetMoney('bank') or 0
        if bank < fare then
            phoneEmit(job.customer, { state = 'payment_failed', fare = fare })
            return notify(src, '승객의 은행 잔액이 부족합니다.', true)
        end

        local removed = cp.Functions.RemoveMoney('bank', fare, '택시 이용 요금')
        if removed == false then
            return notify(src, '승객 요금 결제에 실패했습니다.', true)
        end
    end

    local unlockedLevel = 1
    pcall(function()
        unlockedLevel = exports.cookie_admin:getCivilLevel(src, T.Job or T.Skill) or 1
    end)
    unlockedLevel = math.max(1, math.min(5, math.floor(tonumber(unlockedLevel) or 1)))

    local bonus = nil
    pcall(function() bonus = exports.cookie_skill:bonusAtLevel(T.Skill, unlockedLevel) end)
    local mult = (type(bonus) == 'table' and tonumber(bonus.fare)) or 1.0
    local tipRate = (type(bonus) == 'table' and tonumber(bonus.tip)) or 0.0

    local paid = math.floor(fare * mult)

    local tip = 0
    if math.random() < tipRate then
        local lo, hi = (T.TipMin or 0.05), (T.TipMax or 0.20)
        tip = math.floor(paid * (lo + math.random() * (hi - lo)))
    end

    local total = math.min(paid + tip, T.MaxFare or 200000)

    local exp = T.ExpPerRide or 1

    -- 승객 결제 후 기사 지급까지 성공해야 승차 상태를 종료한다.
    local okDriverPay, driverPaid = pcall(function() return p.Functions.AddMoney('cash', total, '택시 요금') end)
    if not okDriverPay or driverPaid == false then
        if job.type == 'player' and job.customer then
            local cpRefund = exports.qbx_core:GetPlayer(job.customer)
            if cpRefund then pcall(function() cpRefund.Functions.AddMoney('bank', fare, '택시 결제 실패 환불') end) end
        end
        return notify(src, '택시 요금 지급에 실패했습니다. 승객 결제는 복구했습니다.', true)
    end

    local elapsed = job.startedAt and (os.time() - job.startedAt) or 0

    local callId = job.callId
    local rideType = job.type
    local rideCustomer = job.customer
    local snapshot = {
        guest     = job.guest,
        dest      = job.dest.label,
        meters    = math.floor(job.meters),
        intercity = job.intercity,
        base      = T.BaseFare,
        intFee    = job.intercity and (T.IntercityFee or 0) or 0,
        elapsed   = elapsed,
    }
    jobs[src] = nil
    if calls[callId] then calls[callId] = nil end
    if rideType == 'player' and phoneCalls[callId] then
        local pc = phoneCalls[callId]
        phoneCalls[callId] = nil
        if phoneCallsByCustomer[pc.customer] == callId then
            phoneCallsByCustomer[pc.customer] = nil
        end
    end

    pcall(function() exports.cookie_skill:addExp(src, T.Skill, exp) end)
    pcall(function() exports.cookie_skill:record(src, T.Skill, total) end)

    TriggerClientEvent('cookie_taxi:client:receipt', src, {
        guest     = snapshot.guest,
        dest      = snapshot.dest,
        meters    = snapshot.meters,
        elapsed   = snapshot.elapsed,
        base      = snapshot.base,
        intercity = snapshot.intercity,
        intFee    = snapshot.intFee,
        fare      = fare,
        mult      = mult,
        tip       = tip,
        total     = total,
        exp       = exp,
    })
    CookieTaxiPushState(src)

    if rideType == 'player' and rideCustomer and GetPlayerName(rideCustomer) then
        phoneEmit(rideCustomer, {
            state = 'completed',
            fare = fare,
            destination = snapshot.dest,
        })
        notify(rideCustomer, ('택시 요금 %s원이 은행에서 결제되었습니다.'):format(CookieTaxiComma(fare)), false)
    end

    if CookieTaxiSetAvailable then CookieTaxiSetAvailable(src, true, true) end

end)

function CookieTaxiCancelJob(src, reason)
    local job = jobs[src]
    if not job then return end

    local callId = job.callId
    local customer = job.customer
    local rideType = job.type
    jobs[src] = nil
    if calls[callId] then calls[callId] = nil end
    if rideType == 'player' and phoneCalls[callId] then
        local pc = phoneCalls[callId]
        phoneCalls[callId] = nil
        if phoneCallsByCustomer[pc.customer] == callId then phoneCallsByCustomer[pc.customer] = nil end
        if customer and GetPlayerName(customer) then
            phoneEmit(customer, { state = 'cancelled', message = reason or '택시 운행이 취소되었습니다.' })
        end
    end

    TriggerClientEvent('cookie_taxi:client:cancel', src, { reason = reason or '취소' })
    if reason and reason ~= '접속 종료' then
        notify(src, ('콜이 취소되었습니다 (%s)'):format(reason), true)
    end

end

function CookieTaxiReleaseCalls(src)
    for _, c in pairs(calls) do
        if c.acceptedBy == src and not c.claimedBy then
            c.acceptedBy = nil
            c.offered = {}

        end
    end
    TriggerClientEvent('cookie_taxi:client:calls', src, {})
    TriggerClientEvent('cookie_taxi:client:offerClose', src, { all = true })
end

RegisterNetEvent('cookie_taxi:server:abortJob', function(reason)
    local src = source
    if not jobs[src] then return end
    CookieTaxiCancelJob(src, tostring(reason or '중단'))
end)

AddEventHandler('playerDropped', function()
    local src = source

    local customerCallId = phoneCallsByCustomer[src]
    if customerCallId and phoneCalls[customerCallId] then
        local pc = phoneCalls[customerCallId]
        if pc.acceptedBy and jobs[pc.acceptedBy] and jobs[pc.acceptedBy].callId == pc.id then
            CookieTaxiCancelJob(pc.acceptedBy, '승객 접속 종료')
        else
            clearPhoneCall(pc, nil)
        end
    end

    if jobs[src] then
        local callId = jobs[src].callId
        jobs[src] = nil
        if calls[callId] then calls[callId] = nil end
    end

    for _, c in pairs(calls) do
        if c.acceptedBy == src then
            c.acceptedBy = nil
            c.offered = {}

        end
        c.declined[src] = nil
        c.offered[src] = nil
    end
end)

local function pushCallsTo(src)
    if not CookieTaxiOnDuty(src) then
        return TriggerClientEvent('cookie_taxi:client:calls', src, {})
    end
    pushMyCall(src)
end

RegisterNetEvent('cookie_taxi:server:requestCalls', function()
    pushCallsTo(source)
end)

AddEventHandler('cookie_taxi:server:pushCallsTo', function(src)
    if src then pushCallsTo(src) end
end)

local function adminOk(src)
    local ok, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return ok and (tonumber(lv) or 0) >= 3
end

RegisterCommand('taxidest', function(src)
    if src == 0 or not adminOk(src) then return end
    local c = GetEntityCoords(GetPlayerPed(src))

    notify(src, '목적지 좌표를 서버 콘솔에 찍었습니다', false)
end, false)

RegisterCommand('taxidiag', function(src)

    if src ~= 0 and not adminOk(src) then return end

    CreateThread(function()

    local function tableOk(name)
        local ok, row = pcall(function()
            return MySQL.single.await(
                'SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
                { name })
        end)
        if not ok or not row then return nil end
        return (tonumber(row.n) or 0) > 0
    end

    local function count(name)
        local ok, row = pcall(function()
            return MySQL.single.await(('SELECT COUNT(*) AS n FROM %s'):format(name))
        end)
        return (ok and row and tonumber(row.n)) or 0
    end

    for _, t in ipairs({ 'cookie_skill', 'cookie_taxi_debt', 'cookie_npc' }) do
        local has = tableOk(t)
        if has == nil then

        elseif has then

        else

        end
    end

    local ok, jobs = pcall(function() return exports.qbx_core:GetJobs() end)
    local tx = ok and jobs and jobs.taxi
    if not tx then

    else
        local grades = 0
        for _ in pairs(tx.grades or {}) do grades = grades + 1 end
        local fresh = (tx.label == '택시기사') and (grades == 1) and (tx.defaultDuty == false)

        if not fresh then

        end
    end

    for _, r in ipairs({ 'cookie_skill', 'cookie_admin', 'qbx_vehiclekeys' }) do
        local st = GetResourceState(r)

    end

    for _, v in ipairs(T.Vehicles or {}) do
        local okv, info = pcall(function() return exports.qbx_core:GetVehiclesByName(v.model) end)

    end

    local hails, drivers = 0, #CookieTaxiDrivers()
    for _, c in pairs(calls) do if not c.claimedBy then hails = hails + 1 end end

    end)
end, false)

RegisterCommand('taxicall', function(src)
    if src ~= 0 and not adminOk(src) then return end

    CreateThread(function()
        local before = activeHailCount()
        makeCall()
        local after = activeHailCount()

        if after > before then
            local msg = ('콜을 강제로 만들었습니다 (대기 콜 %d개, 대기 기사 %d명)')
                :format(after, waitingDrivers())

            if src ~= 0 then notify(src, msg, false) end
        else
            local msg = '콜 생성 실패 빈 승차지가 없거나 목적지 후보가 없습니다'

            if src ~= 0 then notify(src, msg, true) end
        end
    end)
end, false)

