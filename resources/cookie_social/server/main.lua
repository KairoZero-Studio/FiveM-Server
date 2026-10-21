local pendingTarget = {}
local pendingSource = {}
local active = {}
local seq = 0

local function notify(src, msg, err)
    if GetPlayerName(src) then
        TriggerClientEvent('cookie_social:client:notify', src, msg, err == true)
    end
end

local function distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999.0 end
    local ca, cb = GetEntityCoords(pa), GetEntityCoords(pb)
    local dx, dy, dz = ca.x-cb.x, ca.y-cb.y, ca.z-cb.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function clearPending(target)
    local req = pendingTarget[target]
    if not req then return nil end
    pendingTarget[target] = nil
    if pendingSource[req.from] == target then pendingSource[req.from] = nil end
    return req
end

local function stopPair(src, message)
    local partner = active[src]
    if not partner then return end
    active[src] = nil
    active[partner] = nil

    if GetPlayerName(src) then
        TriggerClientEvent('cookie_social:client:carryStop', src, message or '업기를 종료했습니다.')
    end
    if GetPlayerName(partner) then
        TriggerClientEvent('cookie_social:client:carryStop', partner, message or '업기가 종료되었습니다.')
    end
end

RegisterNetEvent('cookie_social:server:carryRequest', function(target)
    local src = source
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return end

    if active[src] then return notify(src, '이미 업기 중입니다.', true) end
    if active[target] then return notify(src, '상대방이 이미 업기 중입니다.', true) end
    if pendingSource[src] then return notify(src, '이미 업기 요청을 보냈습니다.', true) end
    if pendingTarget[target] then return notify(src, '상대방이 다른 요청을 확인 중입니다.', true) end
    if distance(src, target) > (Config.CarryRequestDistance or 3.5) then
        return notify(src, '상대방이 너무 멀리 있습니다.', true)
    end

    seq = seq + 1
    local id = seq
    local timeout = Config.CarryRequestSeconds or 15

    pendingTarget[target] = { id=id, from=src, to=target, expires=os.time()+timeout }
    pendingSource[src] = target

    TriggerClientEvent('cookie_social:client:carryRequest', target, id, src, GetPlayerName(src) or ('ID '..src))
    notify(src, '업기 요청을 보냈습니다.', false)

    SetTimeout(timeout * 1000, function()
        local req = pendingTarget[target]
        if not req or req.id ~= id then return end
        clearPending(target)
        notify(src, '업기 요청 시간이 만료되었습니다.', true)
    end)
end)

RegisterNetEvent('cookie_social:server:carryResponse', function(requestId, accepted)
    local target = source
    local req = pendingTarget[target]
    if not req or tonumber(requestId) ~= req.id then return end
    clearPending(target)

    local src = req.from
    if not GetPlayerName(src) then return end
    if os.time() > req.expires then return notify(src, '업기 요청 시간이 만료되었습니다.', true) end

    if accepted ~= true then
        notify(src, '상대방이 업기 요청을 거절했습니다.', true)
        return
    end

    if active[src] or active[target] then
        notify(src, '업기를 시작할 수 없는 상태입니다.', true)
        notify(target, '업기를 시작할 수 없는 상태입니다.', true)
        return
    end

    if distance(src, target) > (Config.CarryRequestDistance or 3.5) then
        notify(src, '상대방이 너무 멀어졌습니다.', true)
        notify(target, '상대방이 너무 멀어졌습니다.', true)
        return
    end

    active[src] = target
    active[target] = src

    TriggerClientEvent('cookie_social:client:carryStart', src, 'carrier', target)
    TriggerClientEvent('cookie_social:client:carryStart', target, 'carried', src)
end)

RegisterNetEvent('cookie_social:server:carryStop', function()
    stopPair(source, '업기를 종료했습니다.')
end)

AddEventHandler('playerDropped', function()
    local src = source

    local target = pendingSource[src]
    if target then
        clearPending(target)
        notify(target, '업기 요청을 보낸 사용자가 나갔습니다.', true)
    end

    local req = pendingTarget[src]
    if req then
        clearPending(src)
        notify(req.from, '업기 요청 대상이 나갔습니다.', true)
    end

    if active[src] then
        stopPair(src, '상대방이 나가 업기가 종료되었습니다.')
    end
end)

print('^2[cookie_social]^7 V2.0.0 ready · right-side full motion HUD')
