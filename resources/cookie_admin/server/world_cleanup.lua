-- COOKIE: restricted server-side cleanup, V2.
-- Deletes world entities only; does not modify player_vehicles / item / garage DB.
local lastRun = 0
local inProgress = false

local function notify(src, message)
    TriggerClientEvent('cookie_admin:client:cleanupResult', src, message)
end

local function authorized(src)
    -- Match cookie_admin's effective LV, including the existing admin-password rule.
    local success, effectiveLevel = pcall(function()
        return exports.cookie_admin:getEffectiveLevel(src)
    end)
    return success and (tonumber(effectiveLevel) or 0) >= 5
end

local function getOccupiedVehicles()
    local result = {}
    -- Both player and NPC drivers/passengers count as occupied.
    for _, ped in ipairs(GetAllPeds()) do
        if DoesEntityExist(ped) then
            local ok, vehicle = pcall(GetVehiclePedIsIn, ped, false)
            if ok and vehicle and vehicle ~= 0 then result[vehicle] = true end
        end
    end
    -- Explicitly cover each connected player ped as well.
    for _, playerId in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(tonumber(playerId))
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local ok, vehicle = pcall(GetVehiclePedIsIn, ped, false)
            if ok and vehicle and vehicle ~= 0 then result[vehicle] = true end
        end
    end
    return result
end

local function isPlayerAttached(entity)
    if not DoesEntityExist(entity) then return true end
    if not IsEntityAttached(entity) then return false end
    local attached = GetEntityAttachedTo(entity)
    if attached and attached ~= 0 and DoesEntityExist(attached) then
        return GetEntityType(attached) == 1
    end
    return false
end

RegisterNetEvent('cookie_admin:server:cleanupWorldEntities', function(mode, confirmation)
    local src = source
    if mode ~= 'vehicles' and mode ~= 'objects' then return end
    if confirmation ~= (mode == 'vehicles' and '차량삭제' or '오브젝트삭제') then return end

    if not authorized(src) then
        notify(src, '정리 권한이 없습니다. 관리자 LV5 및 관리자 인증을 확인해 주세요.')
        return
    end
    if inProgress then
        notify(src, '다른 관리자 정리 작업이 진행 중입니다.')
        return
    end
    local now = os.time()
    if now - lastRun < 30 then
        notify(src, ('정리 작업은 30초 간격으로 실행할 수 있습니다. %d초 후 다시 시도해 주세요.'):format(30 - (now - lastRun)))
        return
    end
    lastRun = now
    inProgress = true

    CreateThread(function()
        local ok, err = pcall(function()
            local entities = mode == 'vehicles' and GetAllVehicles() or GetAllObjects()
            local removed, skipped, failed = 0, 0, 0
            local occupied = {}
            for i, entity in ipairs(entities) do
                if i % 25 == 1 and mode == 'vehicles' then
                    occupied = getOccupiedVehicles()
                end
                if DoesEntityExist(entity) then
                    local canDelete = mode == 'vehicles'
                        and not occupied[entity]
                        or mode == 'objects' and not isPlayerAttached(entity)
                    if canDelete then
                        local success = pcall(DeleteEntity, entity)
                        if success and not DoesEntityExist(entity) then
                            removed = removed + 1
                        else
                            failed = failed + 1
                        end
                    else
                        skipped = skipped + 1
                    end
                end
                if i % 25 == 0 then Wait(0) end
            end
            local name = mode == 'vehicles' and '빈 차량' or '네트워크 오브젝트'
            local message = ('%s 삭제 완료: %d대/개 삭제 · %d개 보호 · %d개 실패 (DB 변경 없음)')
                :format(name, removed, skipped, failed)
            notify(src, message)
            print(('[COOKIE CLEANUP] admin=%s id=%d mode=%s removed=%d protected=%d failed=%d')
                :format(GetPlayerName(src) or '?', src, mode, removed, skipped, failed))
        end)
        inProgress = false
        if not ok then
            print('[COOKIE CLEANUP] ERROR: ' .. tostring(err))
            notify(src, '삭제 중 서버 오류가 발생했습니다. txAdmin 콘솔을 확인해 주세요.')
        end
    end)
end)
