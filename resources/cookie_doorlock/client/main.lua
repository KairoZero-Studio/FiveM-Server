local Doors = {}
local DoorHashes = {}
local selecting = false
local doorActionBusy = false

local function notify(description, kind)
    lib.notify({
        title = 'COOKIE 문 관리',
        description = description,
        type = kind or 'inform'
    })
end

RegisterNetEvent('cookie_doorlock:client:notify', function(description, kind)
    notify(description, kind)
end)

local function midpoint(door)
    if not door or not door.leaves or #door.leaves == 0 then return nil end
    local x, y, z = 0.0, 0.0, 0.0
    for _, leaf in ipairs(door.leaves) do
        x = x + (tonumber(leaf.x) or 0.0)
        y = y + (tonumber(leaf.y) or 0.0)
        z = z + (tonumber(leaf.z) or 0.0)
    end
    local n = #door.leaves
    return vector3(x / n, y / n, z / n)
end

local function doorHash(id, idx)
    return GetHashKey(('cookie_door_%s_%s'):format(tostring(id), tostring(idx)))
end

local DoorEntityCache = {}
local LegacyClosedRotation = {}
local ClosingDoors = {}

-- 일반 회전문뿐 아니라 위/옆으로 이동하는 차고문·자동문도 찾습니다.
-- 자동문은 열린 뒤 등록 좌표에서 몇 m 이동할 수 있으므로 단순 GetClosestObjectOfType(1.5m)만으로는
-- 엔티티를 놓치는 경우가 있습니다. 우선 캐시를 사용하고, 실패하면 넓은 CObject 풀에서 같은 모델의
-- 가장 가까운 엔티티를 찾아 잠금 상태를 강제로 적용합니다.
local function findDoorEntity(leaf, cacheKey)
    local tx, ty, tz = tonumber(leaf.x) or 0.0, tonumber(leaf.y) or 0.0, tonumber(leaf.z) or 0.0
    local model = tonumber(leaf.model) or 0
    if model == 0 then return 0 end

    if cacheKey then
        local cached = DoorEntityCache[cacheKey]
        if cached and cached ~= 0 and DoesEntityExist(cached) and GetEntityModel(cached) == model then
            local c = GetEntityCoords(cached)
            if #(c - vector3(tx, ty, tz)) <= (tonumber(Config.AutoDoorSearchRadius) or 8.0) then
                return cached
            end
        end
        DoorEntityCache[cacheKey] = nil
    end

    local ent = GetClosestObjectOfType(tx, ty, tz, 2.25, model, false, false, false)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        if cacheKey then DoorEntityCache[cacheKey] = ent end
        return ent
    end

    local target = vector3(tx, ty, tz)
    local maxRadius = tonumber(Config.AutoDoorSearchRadius) or 8.0
    local best, bestDist
    local pool = GetGamePool('CObject') or {}
    for i = 1, #pool do
        local obj = pool[i]
        if obj and obj ~= 0 and DoesEntityExist(obj) and GetEntityModel(obj) == model then
            local dist = #(GetEntityCoords(obj) - target)
            if dist <= maxRadius and (not bestDist or dist < bestDist) then
                best, bestDist = obj, dist
            end
        end
    end

    if cacheKey and best then DoorEntityCache[cacheKey] = best end
    return best or 0
end

local function closedRotationForLeaf(cacheKey, leaf, ent)
    -- V1.5 이후 등록 문은 닫힌 상태의 전체 회전값을 저장합니다.
    if leaf.rotX ~= nil and leaf.rotY ~= nil and leaf.rotZ ~= nil then
        return vector3(tonumber(leaf.rotX) or 0.0, tonumber(leaf.rotY) or 0.0, tonumber(leaf.rotZ) or 0.0)
    end

    -- 구버전 등록문은 heading만 남아 있습니다.
    -- 예전 방식처럼 '잠그는 순간의 현재 회전'을 기억하면, 차고문이 열린 상태일 때
    -- 열린 각도를 닫힌 각도로 오인해서 그대로 얼어붙습니다.
    -- 그래서 구버전 문은 저장된 heading을 기준으로 평평한 닫힘 자세를 사용합니다.
    local heading = tonumber(leaf.heading)
    if heading ~= nil then
        local rot = vector3(0.0, 0.0, heading)
        if cacheKey then LegacyClosedRotation[cacheKey] = rot end
        return rot
    end

    return GetEntityRotation(ent, 2)
end

local function forceEntityClosed(cacheKey, leaf, ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    local x, y, z = tonumber(leaf.x) or 0.0, tonumber(leaf.y) or 0.0, tonumber(leaf.z) or 0.0
    local target = vector3(x, y, z)
    local current = GetEntityCoords(ent)
    local tolerance = tonumber(Config.AutoDoorPositionTolerance) or 0.025
    local savedRot = closedRotationForLeaf(cacheKey, leaf, ent)

    -- 차고문/슬라이딩 자동문은 열리면서 엔티티 위치 자체가 이동합니다.
    -- 등록 당시의 닫힌 좌표/회전으로 되돌린 뒤 고정합니다.
    if #(current - target) > tolerance then
        SetEntityCoordsNoOffset(ent, x, y, z, false, false, false)
    end

    SetEntityRotation(ent, savedRot.x, savedRot.y, savedRot.z, 2, true)
    FreezeEntityPosition(ent, true)
end

local function applyLeafState(door, idx, leaf)
    local hash = doorHash(door.id, idx)
    local cacheKey = ('%s:%s'):format(tostring(door.id), tostring(idx))
    DoorHashes[door.id] = DoorHashes[door.id] or {}
    DoorHashes[door.id][idx] = hash

    if not IsDoorRegisteredWithSystem(hash) then
        AddDoorToSystem(
            hash,
            tonumber(leaf.model) or 0,
            tonumber(leaf.x) or 0.0,
            tonumber(leaf.y) or 0.0,
            tonumber(leaf.z) or 0.0,
            false, false, false
        )
    end

    local closing = ClosingDoors[door.id] ~= nil

    -- 잠금 전환 중에는 먼저 '열림 상태 + openRatio 0'으로 닫히게 한 뒤 마지막에 잠급니다.
    -- 바로 state=1을 주면 일부 자동문/차고문은 현재 열린 위치에서 잠금 상태가 고정됩니다.
    if door.locked and closing then
        DoorSystemSetDoorState(hash, 0, false, true)
        DoorSystemSetOpenRatio(hash, 0.0, false, true)
    else
        DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, true)
        if door.locked then
            DoorSystemSetOpenRatio(hash, 0.0, false, true)
        end
    end

    if Config.FreezeEntityFallback then
        local ent = findDoorEntity(leaf, cacheKey)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            if door.locked and not closing then
                forceEntityClosed(cacheKey, leaf, ent)
            else
                FreezeEntityPosition(ent, false)
            end
        end
    end
end

local function applyDoorState(door)
    if not door or not door.leaves then return end
    for i, leaf in ipairs(door.leaves) do
        applyLeafState(door, i, leaf)
    end
end

local function beginCloseAndLockDoor(door)
    if not door or not door.id or not door.leaves then return end

    local id = tonumber(door.id)
    local token = (tonumber(ClosingDoors[id]) or 0) + 1
    ClosingDoors[id] = token

    CreateThread(function()
        local duration = math.max(150, tonumber(Config.AutoDoorCloseBeforeLockMs) or 650)
        local deadline = GetGameTimer() + duration

        -- 1단계: 잠금은 아직 걸지 않고, DoorSystem에 닫힘(openRatio=0)을 반복 요청합니다.
        -- 자동문 자체 스크립트가 문을 열려고 해도 이 구간에서는 계속 닫힘을 우선시합니다.
        while GetGameTimer() < deadline do
            local currentDoor = Doors[id]
            if ClosingDoors[id] ~= token or not currentDoor or currentDoor.locked ~= true then
                return
            end

            for i, leaf in ipairs(currentDoor.leaves or {}) do
                local hash = doorHash(id, i)
                local cacheKey = ('%s:%s'):format(tostring(id), tostring(i))

                if not IsDoorRegisteredWithSystem(hash) then
                    AddDoorToSystem(
                        hash,
                        tonumber(leaf.model) or 0,
                        tonumber(leaf.x) or 0.0,
                        tonumber(leaf.y) or 0.0,
                        tonumber(leaf.z) or 0.0,
                        false, false, false
                    )
                end

                DoorSystemSetDoorState(hash, 0, false, true)
                DoorSystemSetOpenRatio(hash, 0.0, false, true)

                if Config.FreezeEntityFallback then
                    local ent = findDoorEntity(leaf, cacheKey)
                    if ent and ent ~= 0 and DoesEntityExist(ent) then
                        FreezeEntityPosition(ent, false)
                    end
                end
            end

            Wait(40)
        end

        local currentDoor = Doors[id]
        if ClosingDoors[id] ~= token or not currentDoor or currentDoor.locked ~= true then
            return
        end

        -- 2단계: 마지막에 등록 당시의 닫힌 좌표/회전을 강제로 맞춘 뒤 잠금 + Freeze.
        -- 이 단계 때문에 차고문이 열린 채로 잠기는 현상을 막습니다.
        for i, leaf in ipairs(currentDoor.leaves or {}) do
            local hash = doorHash(id, i)
            local cacheKey = ('%s:%s'):format(tostring(id), tostring(i))
            local ent = findDoorEntity(leaf, cacheKey)

            if ent and ent ~= 0 and DoesEntityExist(ent) and Config.FreezeEntityFallback then
                forceEntityClosed(cacheKey, leaf, ent)
            end

            DoorSystemSetOpenRatio(hash, 0.0, false, true)
            DoorSystemSetDoorState(hash, 1, false, true)
        end

        if ClosingDoors[id] == token then
            ClosingDoors[id] = nil
        end
    end)
end

local function unregisterDoor(id)
    ClosingDoors[id] = nil
    local hashes = DoorHashes[id]
    if hashes then
        for _, hash in pairs(hashes) do
            if IsDoorRegisteredWithSystem(hash) then
                RemoveDoorFromSystem(hash)
            end
        end
    end
    DoorHashes[id] = nil
    local prefix = tostring(id) .. ':'
    for key in pairs(DoorEntityCache) do
        if key:sub(1, #prefix) == prefix then
            DoorEntityCache[key] = nil
            LegacyClosedRotation[key] = nil
        end
    end
    for key in pairs(LegacyClosedRotation) do
        if key:sub(1, #prefix) == prefix then
            LegacyClosedRotation[key] = nil
        end
    end
end

local function setDoors(list)
    for id in pairs(Doors) do unregisterDoor(id) end
    Doors = {}
    for _, door in ipairs(list or {}) do
        door.id = tonumber(door.id)
        if door.id then
            Doors[door.id] = door
            applyDoorState(door)
        end
    end
end

RegisterNetEvent('cookie_doorlock:client:setDoors', setDoors)

RegisterNetEvent('cookie_doorlock:client:addDoor', function(door)
    if not door or not door.id then return end
    door.id = tonumber(door.id)
    Doors[door.id] = door
    applyDoorState(door)
end)

RegisterNetEvent('cookie_doorlock:client:replaceDoor', function(door)
    if not door or not door.id then return end
    door.id = tonumber(door.id)
    unregisterDoor(door.id)
    Doors[door.id] = door
    applyDoorState(door)
end)

RegisterNetEvent('cookie_doorlock:client:updateState', function(id, locked)
    id = tonumber(id)
    local door = id and Doors[id]
    if not door then return end

    local wasLocked = door.locked == true
    door.locked = locked == true

    if door.locked and not wasLocked then
        beginCloseAndLockDoor(door)
    else
        ClosingDoors[id] = nil
        applyDoorState(door)
    end
end)

RegisterNetEvent('cookie_doorlock:client:removeDoor', function(id)
    id = tonumber(id)
    if not id then return end
    local door = Doors[id]
    if door and Config.FreezeEntityFallback then
        for _, leaf in ipairs(door.leaves or {}) do
            local ent = findDoorEntity(leaf, ('%s:%s'):format(tostring(id), tostring(_)))
            if ent and ent ~= 0 and DoesEntityExist(ent) then FreezeEntityPosition(ent, false) end
        end
    end
    unregisterDoor(id)
    Doors[id] = nil
end)

local function rotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function dot(a, b)
    return (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
end

-- CodeWalker/YMAP/MLO 커스텀 문 대응용 오브젝트 검색.
-- 커스텀 맵은 LOS 레이캐스트가 문을 별도 entity로 돌려주지 않고
-- 정적 맵 충돌만 맞는 경우가 있어서 CObject 풀에서 후보를 한 번 더 찾는다.
local function findObjectNearRay(camCoord, dir, hitPos, maxDistance)
    local pool = GetGamePool('CObject') or {}
    local bestEntity, bestScore
    local hitRadius = tonumber(Config.CaptureFallbackRadius) or 2.25
    local rayRadius = tonumber(Config.CaptureRayRadius) or 0.85
    local maxDist = (maxDistance or Config.CaptureDistance) + 1.5

    for i = 1, #pool do
        local entity = pool[i]
        if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 3 then
            local c = GetEntityCoords(entity)
            local toObj = c - camCoord
            local forward = dot(toObj, dir)

            if forward > 0.05 and forward <= maxDist then
                local closestOnRay = camCoord + (dir * forward)
                local lateral = #(c - closestOnRay)
                local hitDist = hitPos and #(c - hitPos) or 999.0

                -- 1) 실제 충돌점 가까이에 있는 오브젝트
                -- 2) 카메라 중앙 광선에 매우 가까운 오브젝트
                if hitDist <= hitRadius or lateral <= rayRadius then
                    local score = (math.min(hitDist, hitRadius * 2.0) * 0.65) + (lateral * 1.35) + (forward * 0.01)
                    if not bestScore or score < bestScore then
                        bestEntity = entity
                        bestScore = score
                    end
                end
            end
        end
    end

    return bestEntity
end

local function runShapeProbe(camCoord, dest, traceFlags, optionFlags)
    -- 비동기 shape test를 만든 직후 바로 결과를 읽으면 PENDING(1) 상태가 나올 수 있다.
    -- 선택 모드에서만 짧게 결과 완료를 기다려 안정적으로 entity를 얻는다.
    local handle = StartShapeTestLosProbe(
        camCoord.x, camCoord.y, camCoord.z,
        dest.x, dest.y, dest.z,
        traceFlags,
        PlayerPedId(),
        optionFlags
    )

    local status, hit, endCoords, surfaceNormal, entity = GetShapeTestResult(handle)
    local deadline = GetGameTimer() + 35
    while status == 1 and GetGameTimer() < deadline do
        Wait(0)
        status, hit, endCoords, surfaceNormal, entity = GetShapeTestResult(handle)
    end

    return hit == 1, endCoords, entity
end

local function raycastDoor(maxDistance)
    local camCoord = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local dir = rotationToDirection(camRot)
    local dist = maxDistance or Config.CaptureDistance
    local dest = camCoord + (dir * dist)

    -- 중요: optionFlags=0.
    -- 기존 값 7은 glass / see-through / no-collision 계열을 무시하므로
    -- 유리문이나 일부 커스텀 맵 문을 그대로 통과해버릴 수 있다.
    local hit, endCoords, entity = runShapeProbe(camCoord, dest, 511, 0)

    if entity and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 3 then
        return entity, endCoords, 'direct'
    end

    -- 월드 지오메트리만 맞았거나 entity handle이 0인 경우,
    -- 맞은 지점/카메라 중앙선 주변의 CObject를 추가 탐색한다.
    local fallback = findObjectNearRay(camCoord, dir, hit and endCoords or nil, dist)
    if fallback and fallback ~= 0 then
        return fallback, endCoords, 'fallback'
    end

    return nil, endCoords, hit and 'world' or 'none'
end

local function captureOneDoor(prompt)
    if selecting then return nil end
    selecting = true
    lib.showTextUI((prompt or '문을 바라보세요') .. '  |  [E] 선택  [BACKSPACE] 취소', { position = 'top-center' })

    local selected = nil
    while selecting do
        Wait(0)
        local entity, hitPos, captureMode = raycastDoor(Config.CaptureDistance)
        if entity then
            local c = GetEntityCoords(entity)
            local r, g, b = 255, 190, 45
            if captureMode == 'fallback' then r, g, b = 70, 210, 255 end
            DrawMarker(28, c.x, c.y, c.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.20, 0.20, 0.20, r, g, b, 220, false, false, 2, false, nil, nil, false)
        elseif hitPos then
            DrawMarker(28, hitPos.x, hitPos.y, hitPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.08, 0.08, 0.08, 255, 80, 80, 170, false, false, 2, false, nil, nil, false)
        end

        if IsControlJustPressed(0, 38) then
            if entity then
                local c = GetEntityCoords(entity)
                local rot = GetEntityRotation(entity, 2)
                selected = {
                    model = GetEntityModel(entity),
                    x = c.x, y = c.y, z = c.z,
                    heading = GetEntityHeading(entity),
                    rotX = rot.x, rotY = rot.y, rotZ = rot.z,
                    captureMode = captureMode or 'direct',
                }
                selecting = false
            else
                notify('분리된 문 오브젝트를 찾지 못했습니다. 문 중앙을 가까이서 바라보세요. 건물 모델에 문이 합쳐져 있으면 등록할 수 없습니다.', 'error')
            end
        elseif IsControlJustPressed(0, 177) then
            selecting = false
        end
    end

    lib.hideTextUI()
    return selected
end

local function parseJobs(text)
    local out, seen = {}, {}
    for job in tostring(text or ''):gmatch('[^,]+') do
        job = job:lower():gsub('^%s+', ''):gsub('%s+$', '')
        if job ~= '' and not seen[job] then seen[job] = true; out[#out + 1] = job end
    end
    return out
end

local function jobsToText(jobs)
    return table.concat(jobs or {}, ',')
end

local function openCreateDialog(leaves)
    local input = lib.inputDialog('문 잠금 설정', {
        { type = 'input', label = '문 이름', placeholder = '예: 경찰청 정문', required = true, min = 1, max = 80 },
        { type = 'input', label = '허용 직업', description = '쉼표로 여러 개 입력 / * = 모두 / 비우면 관리자만', placeholder = 'police,security' },
        { type = 'number', label = '최소 직급', default = 0, min = 0, max = 99 },
        { type = 'checkbox', label = '근무 중일 때만 사용', checked = false },
        { type = 'checkbox', label = '처음부터 잠금', checked = true },
        { type = 'number', label = '상호작용 거리', default = Config.DefaultInteractDistance, min = 1.0, max = 6.0, step = 0.1 },
    })
    if not input then return end
    TriggerServerEvent('cookie_doorlock:server:adminCreate', {
        label = input[1],
        jobs = parseJobs(input[2]),
        minGrade = tonumber(input[3]) or 0,
        requireDuty = input[4] == true,
        locked = input[5] == true,
        interactDistance = tonumber(input[6]) or Config.DefaultInteractDistance,
        leaves = leaves,
    })
end

local function captureLeaves(mode)
    mode = mode == 'double' and 'double' or 'single'
    if selecting then
        notify('이미 문 선택 중입니다.', 'error')
        return nil
    end

    Wait(120)
    local first = captureOneDoor(mode == 'double' and '첫 번째 문을 바라보세요' or '등록할 문을 바라보세요')
    if not first then return nil end

    if mode == 'single' then
        return { first }
    end

    Wait(120)
    local second = captureOneDoor('두 번째 문을 바라보세요')
    if not second then return nil end

    local d = #(vector3(first.x, first.y, first.z) - vector3(second.x, second.y, second.z))
    if d < 0.25 then
        notify('같은 문을 두 번 선택했습니다.', 'error')
        return nil
    end
    return { first, second }
end

exports('CaptureLeaves', captureLeaves)

local function createSingleDoor()
    lib.hideContext()
    local leaves = captureLeaves('single')
    if leaves then openCreateDialog(leaves) end
end

local function createDoubleDoor()
    lib.hideContext()
    local leaves = captureLeaves('double')
    if leaves then openCreateDialog(leaves) end
end

local function doorDescription(door)
    local jobs = door.jobs or {}
    local perm
    if #jobs == 0 then perm = '관리자만'
    elseif #jobs == 1 and jobs[1] == '*' then perm = '모두'
    else perm = table.concat(jobs, ', ') .. (' / G%s+'):format(door.minGrade or 0) end
    if door.requireDuty then perm = perm .. ' / 근무중' end
    return ('#%s · %s · %s'):format(door.id, door.locked and '🔒 잠김' or '🔓 열림', perm)
end

local function editDoor(door)
    local input = lib.inputDialog(('문 #%s 설정'):format(door.id), {
        { type = 'input', label = '문 이름', default = door.label or '', required = true, min = 1, max = 80 },
        { type = 'input', label = '허용 직업', description = '쉼표 구분 / * = 모두 / 비우면 관리자만', default = jobsToText(door.jobs) },
        { type = 'number', label = '최소 직급', default = door.minGrade or 0, min = 0, max = 99 },
        { type = 'checkbox', label = '근무 중일 때만 사용', checked = door.requireDuty == true },
        { type = 'number', label = '상호작용 거리', default = door.interactDistance or Config.DefaultInteractDistance, min = 1.0, max = 6.0, step = 0.1 },
    })
    if not input then return end
    TriggerServerEvent('cookie_doorlock:server:adminUpdate', door.id, {
        label = input[1], jobs = parseJobs(input[2]), minGrade = tonumber(input[3]) or 0,
        requireDuty = input[4] == true, interactDistance = tonumber(input[5]) or Config.DefaultInteractDistance,
    })
end

local function openDoorManage(door)
    if not door then return end
    local ctx = ('cookie_doorlock_manage_%s'):format(door.id)
    lib.registerContext({
        id = ctx,
        title = door.label or ('문 #' .. tostring(door.id)),
        menu = 'cookie_doorlock_nearby',
        options = {
            {
                title = door.locked and '잠금 해제' or '잠그기',
                description = door.locked and '관리자 권한으로 이 문을 엽니다.' or '관리자 권한으로 이 문을 잠급니다.',
                icon = door.locked and 'lock-open' or 'lock',
                onSelect = function()
                    TriggerServerEvent('cookie_doorlock:server:adminSetState', door.id, not door.locked)
                end
            },
            {
                title = '권한/이름 수정',
                description = doorDescription(door),
                icon = 'pen',
                onSelect = function() editDoor(door) end
            },
            {
                title = '문 삭제',
                description = 'DB와 모든 클라이언트에서 이 문 설정을 제거합니다.',
                icon = 'trash',
                onSelect = function()
                    local alert = lib.alertDialog({
                        header = '문 삭제',
                        content = ('정말 **%s** 문 설정을 삭제할까요?'):format(door.label or ('#' .. door.id)),
                        centered = true,
                        cancel = true,
                        labels = { confirm = '삭제', cancel = '취소' }
                    })
                    if alert == 'confirm' then TriggerServerEvent('cookie_doorlock:server:adminDelete', door.id) end
                end
            },
        }
    })
    lib.showContext(ctx)
end

local function openNearbyDoors()
    local pos = GetEntityCoords(PlayerPedId())
    local rows = {}
    for _, door in pairs(Doors) do
        local c = midpoint(door)
        if c then
            local dist = #(pos - c)
            if dist <= Config.AdminListDistance then
                rows[#rows + 1] = { door = door, dist = dist }
            end
        end
    end
    table.sort(rows, function(a, b) return a.dist < b.dist end)

    local options = {}
    for _, row in ipairs(rows) do
        local door = row.door
        options[#options + 1] = {
            title = door.label,
            description = ('%.1fm · %s'):format(row.dist, doorDescription(door)),
            icon = door.locked and 'lock' or 'lock-open',
            onSelect = function() openDoorManage(door) end
        }
    end
    if #options == 0 then
        options[1] = { title = '근처에 등록된 문이 없습니다.', disabled = true }
    end

    lib.registerContext({ id = 'cookie_doorlock_nearby', title = '근처 문 관리', menu = 'cookie_doorlock_admin', options = options })
    lib.showContext('cookie_doorlock_nearby')
end

local function openAdminMenu()
    lib.registerContext({
        id = 'cookie_doorlock_admin',
        title = 'COOKIE 문 잠금 관리',
        options = {
            { title = '단일 문 등록', description = '카메라로 문 하나를 선택해 등록합니다.', icon = 'door-closed', onSelect = createSingleDoor },
            { title = '양문 등록', description = '좌/우 문 두 개를 하나의 잠금장치로 등록합니다.', icon = 'door-open', onSelect = createDoubleDoor },
            { title = '근처 문 관리', description = ('반경 %.0fm의 등록된 문을 수정/삭제합니다.'):format(Config.AdminListDistance), icon = 'list', onSelect = openNearbyDoors },
        }
    })
    lib.showContext('cookie_doorlock_admin')
end

RegisterCommand('dooradmin', function()
    local allowed = lib.callback.await('cookie_doorlock:server:isAdmin', false)
    if not allowed then return notify('문 관리 권한이 없습니다. 관리자 근무 상태를 확인해주세요.', 'error') end
    openAdminMenu()
end, false)

CreateThread(function()
    Wait(1000)
    local list = lib.callback.await('cookie_doorlock:server:getDoors', false) or {}
    setDoors(list)
end)

-- 잠금 상태 유지 및 스트리밍 후 문 엔티티에도 상태 재적용.
-- 잠긴 자동문/차고문은 주변에 플레이어가 접근하면 매우 짧은 간격으로 닫힌 좌표를 재강제합니다.
-- 일반 문은 기존과 동일하게 DoorSystem + FreezeEntity fallback으로 동작합니다.
CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local near = false
        local hasLockedNear = false
        for _, door in pairs(Doors) do
            local c = midpoint(door)
            if c and #(pos - c) < (tonumber(Config.AutoDoorEnforceDistance) or 45.0) then
                near = true
                if door.locked then hasLockedNear = true end
                applyDoorState(door)
            end
        end

        if hasLockedNear then
            Wait(math.max(25, tonumber(Config.AutoDoorEnforceInterval) or 75))
        else
            Wait(near and 900 or 2500)
        end
    end
end)

-- 일반 플레이어 상호작용
CreateThread(function()
    local currentId = nil
    while true do
        local sleep = 600
        local pos = GetEntityCoords(PlayerPedId())
        local nearest, nearestDist
        for _, door in pairs(Doors) do
            local c = midpoint(door)
            if c then
                local d = #(pos - c)
                local limit = (door.interactDistance or Config.DefaultInteractDistance)
                if d <= limit and (not nearestDist or d < nearestDist) then
                    nearest, nearestDist = door, d
                end
            end
        end

        if nearest then
            sleep = 0
            if currentId ~= nearest.id then
                if currentId then lib.hideTextUI() end
                currentId = nearest.id
                lib.showTextUI(('[E] %s  ·  %s'):format(nearest.label, nearest.locked and '🔒 잠김' or '🔓 열림'), { position = 'left-center' })
            end
            if IsControlJustPressed(0, 38) and not doorActionBusy then
                doorActionBusy = true

                local doorId = nearest.id
                local wasLocked = nearest.locked == true
                local actionDuration = math.max(500, tonumber(Config.ActionDuration) or 3000)
                local actionSeconds = actionDuration / 1000.0
                local secondsText = (actionSeconds % 1 == 0) and tostring(math.floor(actionSeconds)) or string.format('%.1f', actionSeconds)
                local actionLabel = wasLocked
                    and ('문 여는 중... (%s초)'):format(secondsText)
                    or ('문 잠그는 중... (%s초)'):format(secondsText)

                -- 진행 중에는 기존 [E] 안내를 잠깐 숨기고,
                -- ox_lib 진행 UI + 키/도어 조작 애니메이션을 3초간 표시합니다.
                lib.hideTextUI()
                currentId = nil

                local completed = lib.progressCircle({
                    duration = actionDuration,
                    position = Config.ActionProgressPosition or 'bottom',
                    label = actionLabel,
                    useWhileDead = false,
                    canCancel = false,
                    disable = {
                        move = true,
                        car = true,
                        combat = true,
                    },
                    anim = {
                        dict = Config.ActionAnimDict or 'anim@mp_player_intmenu@key_fob@',
                        clip = Config.ActionAnimClip or 'fob_click',
                        flag = tonumber(Config.ActionAnimFlag) or 49,
                    },
                })

                if completed then
                    -- 3초 사이 다른 사람이 먼저 문 상태를 바꿨다면
                    -- 서버에서 expected state 검증 후 중복 토글을 막습니다.
                    TriggerServerEvent('cookie_doorlock:server:toggle', doorId, wasLocked)
                end

                Wait(150)
                doorActionBusy = false
            end
        elseif currentId then
            lib.hideTextUI()
            currentId = nil
        end
        Wait(sleep)
    end
end)



-- 잠긴 문 위에 NUI 배지를 표시합니다.
-- 기본 GTA DrawText는 한글/이모지 표시가 환경에 따라 깨질 수 있어
-- 화면 좌표로 변환한 뒤 투명 NUI에 렌더링합니다.
CreateThread(function()
    local lastJson = nil
    while true do
        if not Config.LockIndicatorEnabled then
            if lastJson ~= '[]' then
                lastJson = '[]'
                SendNUIMessage({ action = 'doorIndicators', items = {} })
            end
            Wait(1000)
        else
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local items = {}
            local maxDist = tonumber(Config.LockIndicatorDistance) or 12.0
            local zOffset = tonumber(Config.LockIndicatorHeight) or 1.35

            for _, door in pairs(Doors) do
                if door.locked then
                    local c = midpoint(door)
                    if c then
                        local dist = #(pos - c)
                        if dist <= maxDist then
                            local visible, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + zOffset)
                            if visible then
                                items[#items + 1] = {
                                    id = door.id,
                                    label = door.label or '문',
                                    x = sx,
                                    y = sy,
                                    distance = dist,
                                }
                            end
                        end
                    end
                end
            end

            table.sort(items, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
            local payloadJson = json.encode(items)
            if payloadJson ~= lastJson then
                lastJson = payloadJson
                SendNUIMessage({ action = 'doorIndicators', items = items })
            end
            Wait(#items > 0 and 80 or 250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if selecting then lib.hideTextUI() end
    SendNUIMessage({ action = 'doorIndicators', items = {} })
    for id, door in pairs(Doors) do
        if Config.FreezeEntityFallback then
            for _, leaf in ipairs(door.leaves or {}) do
                local ent = findDoorEntity(leaf, ('%s:%s'):format(tostring(id), tostring(_)))
                if ent and ent ~= 0 and DoesEntityExist(ent) then FreezeEntityPosition(ent, false) end
            end
        end
        unregisterDoor(id)
    end
end)
