local cuffed = {}
local escorts = {}

local function cookiePoliceActionLog(category, title, description, fields, options)
    if GetResourceState('cookie_logs') ~= 'started' then return end
    pcall(function()
        exports.cookie_logs:Log(category, title, description, fields or {}, options or {})
    end)
end



local function notify(src, message, isError)
    TriggerClientEvent('cookie_admin:client:notify', src, message, isError == true)
end

local function factionMember(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok, member = pcall(function()
        return exports.cookie_admin:getFactionMember(src)
    end)
    return ok and member or nil
end

local function hasAccess(src)
    local member = factionMember(src)
    if not member then return false, nil end

    local factionType = tostring(member.type or ''):lower()
    if not Config.AllowedFactionTypes[factionType] then return false, member end
    if Config.RequireDuty and member.duty ~= true then return false, member end

    return true, member
end

local function requireAccess(src)
    local ok, member = hasAccess(src)
    if not ok then
        notify(src, '경찰/보안국 근무 중에만 사용할 수 있습니다.', true)
        return nil
    end
    return member
end

local function requireRestraintAccess(src)
    local member=factionMember(src)
    if not member then notify(src,'수갑/끌고가기 권한이 없습니다.',true); return nil end
    local t=tostring(member.type or ''):lower()
    if t=='crime' then return member end
    local ok,allowed=hasAccess(src)
    if not ok then notify(src,'경찰/보안국은 출근 중에만 수갑/끌고가기를 사용할 수 있습니다.',true); return nil end
    return allowed
end

local function displayName(src)
    local ok, name = pcall(function()
        return exports.cookie_core:getNickname(src)
    end)
    if ok and name and name ~= '' then return name end

    local player = exports.qbx_core:GetPlayer(src)
    local ci = player and player.PlayerData and player.PlayerData.charinfo
    if ci then
        local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if n ~= '' then return n end
    end
    return GetPlayerName(src) or ('#' .. tostring(src))
end

local function distance(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if pa == 0 or pb == 0 then return 9999.0 end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

local function validTarget(src, target, maxDist)
    target = tonumber(target)
    return target and target ~= src and GetPlayerName(target) and distance(src, target) <= maxDist
end

RegisterNetEvent('cookie_police:server:requestVehicleSignal', function(kind)
    local src = source
    if not requireAccess(src) then return end
    if kind ~= 'lights' and kind ~= 'siren' then return end
    TriggerClientEvent('cookie_police:client:authorizedVehicleSignal', src, kind)
end)

RegisterNetEvent('cookie_police:server:syncVehicleSignal', function(netId, lights, siren)
    local src = source
    if not requireAccess(src) then return end
    netId = tonumber(netId)
    if not netId then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    local ped = GetPlayerPed(src)
    if veh == 0 or ped == 0 then return end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return end

    TriggerClientEvent('cookie_police:client:syncVehicleSignal', -1, netId, lights == true, siren == true)
end)

RegisterNetEvent('cookie_police:server:requestPmToggle', function()
    local src = source
    if not requireAccess(src) then return end
    TriggerClientEvent('cookie_police:client:authorizedPmToggle', src)
end)

RegisterNetEvent('cookie_police:server:pullOver', function(netId)
    local src = source
    if not requireAccess(src) then return end
    netId = tonumber(netId)
    if not netId then return end

    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh == 0 or not DoesEntityExist(veh) then
        return notify(src, '대상 차량을 찾지 못했습니다.', true)
    end

    local officerPed = GetPlayerPed(src)
    if officerPed == 0 then return end
    if #(GetEntityCoords(officerPed) - GetEntityCoords(veh)) > (Config.PullOverDistance + 15.0) then
        return notify(src, '대상 차량이 너무 멉니다.', true)
    end

    local driverPed = GetPedInVehicleSeat(veh, -1)
    if driverPed == 0 then
        return notify(src, '대상 차량에 운전자가 없습니다.', true)
    end

    local owner = NetworkGetEntityOwner(driverPed)
    if not owner or owner <= 0 or not GetPlayerName(owner) then
        return notify(src, 'NPC 차량에는 정차 요청을 보낼 수 없습니다.', true)
    end

    TriggerClientEvent('cookie_police:client:pullOverNotice', owner, displayName(src))
    notify(src, ('%s님 차량에 정차 요청을 보냈습니다.'):format(displayName(owner)), false)

    -- V3 도주 시스템: NUM9 P.M 모드에서 Y 정차 요청이 실제 플레이어 차량에 전달된 경우만 카운트.
    -- 같은 대상에게 3회 초과(4번째) 요청 시 server/mdt.lua가 자동 도주 20분을 등록한다.
    TriggerEvent('cookie_police:internal:pullOverRecorded', src, owner)
end)

RegisterNetEvent('cookie_police:server:toggleCuff', function(target)
    local src = source
    if not requireRestraintAccess(src) then return end
    target = tonumber(target)
    if not validTarget(src, target, Config.TargetDistance + 1.0) then
        return notify(src, '수갑 대상이 너무 멀거나 유효하지 않습니다.', true)
    end

    local state = not cuffed[target]
    cuffed[target] = state or nil

    local playerObject = Player(target)
    if playerObject and playerObject.state then
        playerObject.state:set('cookieCuffed', state, true)
    end

    if not state and escorts[target] then
        escorts[target] = nil
        TriggerClientEvent('cookie_police:client:setEscorted', target, nil)
    end

    TriggerClientEvent('cookie_police:client:officerCuffAnim', src)
    TriggerClientEvent('cookie_police:client:setCuffed', target, state)
    notify(src, state and '대상에게 수갑을 채웠습니다.' or '대상의 수갑을 해제했습니다.', false)
end)

RegisterNetEvent('cookie_police:server:toggleEscort', function(target)
    local src = source
    if not requireRestraintAccess(src) then return end
    target = tonumber(target)
    if not validTarget(src, target, Config.TargetDistance + 1.5) then
        return notify(src, '호송 대상이 너무 멀거나 유효하지 않습니다.', true)
    end

    local stateBag = Player(target) and Player(target).state
    if not cuffed[target] and not (stateBag and stateBag.cookieCuffed == true) then
        return notify(src, '수갑이 채워진 대상만 호송할 수 있습니다.', true)
    end

    if escorts[target] == src then
        escorts[target] = nil
        TriggerClientEvent('cookie_police:client:setEscorted', target, nil)
        return notify(src, '호송을 해제했습니다.', false)
    end

    if escorts[target] and escorts[target] ~= src then
        return notify(src, '이미 다른 사람이 끌고가는 중입니다.', true)
    end

    escorts[target] = src
    TriggerClientEvent('cookie_police:client:setEscorted', target, src)
    notify(src, '호송을 시작했습니다.', false)
end)

RegisterNetEvent('cookie_police:server:miranda', function(target)
    local src = source
    if not requireAccess(src) then return end
    target = tonumber(target)
    if not validTarget(src, target, Config.TargetDistance + 2.0) then
        return notify(src, '미란다 고지 대상이 너무 멉니다.', true)
    end

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local origin = GetEntityCoords(ped)
    local officerName = displayName(src)

    for _, rawId in ipairs(GetPlayers()) do
        local id = tonumber(rawId)
        local otherPed = GetPlayerPed(id)
        if otherPed ~= 0 and #(origin - GetEntityCoords(otherPed)) <= Config.MirandaRadius then
            TriggerClientEvent('cookie_police:client:miranda', id, officerName, Config.MirandaText)
        end
    end

    notify(src, ('%s님에게 미란다 원칙을 고지했습니다.'):format(displayName(target)), false)
end)

RegisterNetEvent('cookie_police:server:backup', function()
    local src = source
    local member = requireAccess(src)
    if not member then return end

    cookiePoliceActionLog('backup','지원 요청','F1 현장 지원 요청',{
        {name='팩션',value=tostring(member.name or member.id or '-'),inline=true},
    },{
        actorSrc=src,
        actorLabel='요청자',
        eventKey='backup'
    })

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local coords = GetEntityCoords(ped)

    local data = {
        officerName = displayName(src),
        factionId = tonumber(member.id),
        coords = { x = coords.x, y = coords.y, z = coords.z }
    }

    for _, rawId in ipairs(GetPlayers()) do
        local id = tonumber(rawId)
        local allowed, other = hasAccess(id)
        -- 지원요청은 같은 치안 팩션 인원에게 우선 전송.
        if allowed and other and tonumber(other.id) == tonumber(member.id) then
            TriggerClientEvent('cookie_police:client:backup', id, data)
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    cuffed[src] = nil
    escorts[src] = nil

    for target, officer in pairs(escorts) do
        if officer == src then
            escorts[target] = nil
            TriggerClientEvent('cookie_police:client:setEscorted', target, nil)
        end
    end
end)

exports('IsCuffed', function(src)
    local bag = Player(src) and Player(src).state
    return cuffed[src] == true or (bag and bag.cookieCuffed == true)
end)

print('^2[cookie_police]^7 police/security shortcuts loaded')

-- MDT/구금 시스템에서 안전하게 수갑 상태를 정리할 때 사용.
exports('ForceSetCuffed', function(target, state)
    target = tonumber(target)
    if not target or not GetPlayerName(target) then return false end
    state = state == true
    cuffed[target] = state or nil
    local bag = Player(target)
    if bag and bag.state then bag.state:set('cookieCuffed', state, true) end
    if not state and escorts[target] then
        escorts[target] = nil
        TriggerClientEvent('cookie_police:client:setEscorted', target, nil)
    end
    TriggerClientEvent('cookie_police:client:setCuffed', target, state)
    return true
end)
