local Doors = {}
local Ready = false

local function notify(src, description, kind)
    TriggerClientEvent('cookie_doorlock:client:notify', src, description, kind or 'inform')
end

local function refreshAdminUi(target)
    TriggerClientEvent('cookie_doorlock:client:adminRefresh', target or -1)
end

local function safeDecode(v, fallback)
    if type(v) == 'table' then return v end
    if not v or v == '' then return fallback end
    local ok, data = pcall(json.decode, v)
    if ok and type(data) == 'table' then return data end
    return fallback
end

local function normalizeDoorRow(row)
    return {
        id = tonumber(row.id),
        label = tostring(row.label or ('문 #' .. tostring(row.id))),
        leaves = safeDecode(row.leaves, {}),
        jobs = safeDecode(row.jobs, {}),
        minGrade = math.max(0, tonumber(row.min_grade) or 0),
        requireDuty = row.require_duty == 1 or row.require_duty == true,
        locked = row.locked == 1 or row.locked == true,
        interactDistance = math.max(1.0, math.min(6.0, tonumber(row.interact_distance) or Config.DefaultInteractDistance)),
    }
end

local function serializeDoors()
    local out = {}
    for _, door in pairs(Doors) do
        out[#out + 1] = door
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

local function loadDoors()
    local rows = MySQL.query.await('SELECT * FROM cookie_doorlock ORDER BY id ASC', {}) or {}
    Doors = {}
    for _, row in ipairs(rows) do
        local door = normalizeDoorRow(row)
        Doors[door.id] = door
    end
    Ready = true
    TriggerClientEvent('cookie_doorlock:client:setDoors', -1, serializeDoors())
end

local function isDoorAdmin(src)
    src = tonumber(src)
    if not src or src <= 0 then return true end

    if GetResourceState('cookie_admin') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_admin:isAdminDuty(src, Config.AdminMinLevel or 3)
        end)
        if ok and allowed then return true end
    end

    return IsPlayerAceAllowed(src, Config.AdminAce or 'cookie.doorlock.admin')
end

local function jobGradeLevel(job)
    if not job then return 0 end
    if type(job.grade) == 'number' then return tonumber(job.grade) or 0 end
    if type(job.grade) == 'table' then
        return tonumber(job.grade.level or job.grade.grade or job.grade.id) or 0
    end
    return 0
end

local function canUseDoor(src, door)
    if not door then return false end
    if Config.AdminBypass and isDoorAdmin(src) then return true end

    local jobs = door.jobs or {}
    local allowAll = false
    for _, name in ipairs(jobs) do
        if tostring(name) == '*' then
            allowAll = true
            break
        end
    end
    if allowAll then return true end
    if #jobs == 0 then return false end

    -- 관리자 역할은 일반 Qbox job과 별개로 문별 허용 대상으로 사용할 수 있습니다.
    -- 뉴비가이드/스태프는 다른 팩션 직업을 유지한 채 겸직하므로 관리자 출근 상태를 기준으로 판정합니다.
    if GetResourceState('cookie_admin') == 'started' then
        for _, name in ipairs(jobs) do
            local required = nil
            if tostring(name) == '@newbieguide' then required = 1 end
            if tostring(name) == '@staff' then required = 2 end
            if required then
                local ok, allowed = pcall(function()
                    return exports.cookie_admin:isAdminDuty(src, required)
                end)
                if ok and allowed then return true end
            end
        end
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player or not player.PlayerData then return false end
    local job = player.PlayerData.job
    if not job or not job.name then return false end

    local match = false
    for _, name in ipairs(jobs) do
        if tostring(name) == tostring(job.name) then
            match = true
            break
        end
    end
    if not match then return false end
    if jobGradeLevel(job) < (door.minGrade or 0) then return false end
    if door.requireDuty and job.onduty ~= true then return false end
    return true
end

local function midpoint(door)
    local leaves = door and door.leaves or {}
    if #leaves == 0 then return nil end
    local x, y, z = 0.0, 0.0, 0.0
    for _, leaf in ipairs(leaves) do
        x = x + (tonumber(leaf.x) or 0.0)
        y = y + (tonumber(leaf.y) or 0.0)
        z = z + (tonumber(leaf.z) or 0.0)
    end
    local n = #leaves
    return vector3(x / n, y / n, z / n)
end

local function playerNearDoor(src, door)
    local center = midpoint(door)
    if not center then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local c = GetEntityCoords(ped)
    return #(c - center) <= ((door.interactDistance or Config.DefaultInteractDistance) + 3.0)
end

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_doorlock` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `label` VARCHAR(80) NOT NULL,
          `leaves` LONGTEXT NOT NULL,
          `jobs` LONGTEXT NULL,
          `min_grade` INT NOT NULL DEFAULT 0,
          `require_duty` TINYINT(1) NOT NULL DEFAULT 0,
          `locked` TINYINT(1) NOT NULL DEFAULT 1,
          `interact_distance` FLOAT NOT NULL DEFAULT 2.0,
          `created_by` VARCHAR(80) NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]], {})
    loadDoors()
end)

lib.callback.register('cookie_doorlock:server:getDoors', function()
    if not Ready then return {} end
    return serializeDoors()
end)

local function doorPermissionOptions()
    local options = {
        { key = '@newbieguide', label = '🐣 뉴비가이드', kind = 'admin_role' },
        { key = '@staff', label = '⭐ 스태프', kind = 'admin_role' },
    }
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT name, job_name, faction_type, emoji
            FROM cookie_faction
            WHERE is_active = 1 AND COALESCE(job_name, '') <> ''
            ORDER BY name, id
        ]], {}) or {}
    end)
    if ok then
        local seen = {}
        for _, row in ipairs(rows) do
            local key = tostring(row.job_name or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
            if key ~= '' and not seen[key] then
                seen[key] = true
                local prefix = tostring(row.emoji or '')
                if prefix ~= '' then prefix = prefix .. ' ' end
                options[#options + 1] = {
                    key = key,
                    label = prefix .. tostring(row.name or key),
                    kind = 'job',
                    factionType = tostring(row.faction_type or '')
                }
            end
        end
    end
    return options
end

lib.callback.register('cookie_doorlock:server:getAdminDoors', function(src)
    if not isDoorAdmin(src) then return nil end
    if not Ready then return { rows = {}, permissions = doorPermissionOptions() } end
    return { rows = serializeDoors(), permissions = doorPermissionOptions() }
end)

lib.callback.register('cookie_doorlock:server:isAdmin', function(src)
    return isDoorAdmin(src)
end)

RegisterNetEvent('cookie_doorlock:server:toggle', function(id, expectedLocked)
    local src = source
    id = tonumber(id)
    local door = id and Doors[id]
    if not door then return end
    if not playerNearDoor(src, door) then
        return notify(src, '문에서 너무 멀리 떨어져 있습니다.', 'error')
    end
    if not canUseDoor(src, door) then
        return notify(src, '이 문을 잠금/해제할 권한이 없습니다.', 'error')
    end

    -- 3초 연출 중 다른 플레이어가 먼저 같은 문을 바꿨을 경우
    -- 두 번째 요청이 다시 원래 상태로 되돌리는 것을 방지합니다.
    if expectedLocked ~= nil and door.locked ~= (expectedLocked == true) then
        return notify(src, '진행 중 문 상태가 이미 변경되었습니다.', 'inform')
    end

    door.locked = not door.locked
    MySQL.update('UPDATE cookie_doorlock SET locked = ? WHERE id = ?', { door.locked and 1 or 0, id })
    TriggerClientEvent('cookie_doorlock:client:updateState', -1, id, door.locked)
    refreshAdminUi(-1)
    notify(src, ('%s: %s'):format(door.label, door.locked and '잠금' or '잠금 해제'), 'success')
end)

RegisterNetEvent('cookie_doorlock:server:adminCreate', function(payload)
    local src = source
    if not isDoorAdmin(src) then return end
    if type(payload) ~= 'table' or type(payload.leaves) ~= 'table' then return end
    if #payload.leaves < 1 or #payload.leaves > 2 then return end

    local cleanLeaves = {}
    for _, leaf in ipairs(payload.leaves) do
        local model = tonumber(leaf.model)
        local x, y, z = tonumber(leaf.x), tonumber(leaf.y), tonumber(leaf.z)
        if not model or not x or not y or not z then return end
        cleanLeaves[#cleanLeaves + 1] = {
            model = model,
            x = x, y = y, z = z,
            heading = tonumber(leaf.heading) or 0.0,
            rotX = tonumber(leaf.rotX),
            rotY = tonumber(leaf.rotY),
            rotZ = tonumber(leaf.rotZ),
        }
    end

    local jobs = {}
    if type(payload.jobs) == 'table' then
        local seen = {}
        for _, j in ipairs(payload.jobs) do
            j = tostring(j or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
            if j ~= '' and not seen[j] then
                seen[j] = true
                jobs[#jobs + 1] = j
            end
        end
    end

    local label = tostring(payload.label or '문'):sub(1, 80)
    local minGrade = math.max(0, math.floor(tonumber(payload.minGrade) or 0))
    local requireDuty = payload.requireDuty == true
    local locked = payload.locked ~= false
    local interactDistance = math.max(1.0, math.min(6.0, tonumber(payload.interactDistance) or Config.DefaultInteractDistance))
    local createdBy = GetPlayerName(src) or ('src:' .. tostring(src))

    local id = MySQL.insert.await([[
        INSERT INTO cookie_doorlock
        (label, leaves, jobs, min_grade, require_duty, locked, interact_distance, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        label, json.encode(cleanLeaves), json.encode(jobs), minGrade,
        requireDuty and 1 or 0, locked and 1 or 0, interactDistance, createdBy
    })
    if not id then return notify(src, '문 저장에 실패했습니다.', 'error') end

    Doors[id] = {
        id = id,
        label = label,
        leaves = cleanLeaves,
        jobs = jobs,
        minGrade = minGrade,
        requireDuty = requireDuty,
        locked = locked,
        interactDistance = interactDistance,
    }
    TriggerClientEvent('cookie_doorlock:client:addDoor', -1, Doors[id])
    refreshAdminUi(-1)
    notify(src, ('문을 등록했습니다. (#%s %s)'):format(id, label), 'success')
end)


local function leafDistance(a, b)
    return #(vector3(tonumber(a.x) or 0.0, tonumber(a.y) or 0.0, tonumber(a.z) or 0.0)
        - vector3(tonumber(b.x) or 0.0, tonumber(b.y) or 0.0, tonumber(b.z) or 0.0))
end

local function findSingleDoorByLeaf(target)
    local targetModel = tonumber(target and target.model)
    if not targetModel then return nil end
    local best, bestDist
    for _, door in pairs(Doors) do
        if type(door.leaves) == 'table' and #door.leaves == 1 then
            local leaf = door.leaves[1]
            if tonumber(leaf.model) == targetModel then
                local d = leafDistance(leaf, target)
                if d <= 0.80 and (not bestDist or d < bestDist) then
                    best, bestDist = door, d
                end
            end
        end
    end
    return best
end

-- 이미 단문 2개로 등록된 양문을 한 개의 door record(leaf 2개)로 합칩니다.
RegisterNetEvent('cookie_doorlock:server:adminMergeByLeaves', function(leaves)
    local src = source
    if not isDoorAdmin(src) then return end
    if type(leaves) ~= 'table' or #leaves ~= 2 then
        return notify(src, '양문으로 묶을 문 두 개를 선택해주세요.', 'error')
    end

    local first = findSingleDoorByLeaf(leaves[1])
    local second = findSingleDoorByLeaf(leaves[2])
    if not first or not second then
        return notify(src, '선택한 문 중 등록된 단문을 찾지 못했습니다. 두 문이 먼저 단문으로 등록되어 있어야 합니다.', 'error')
    end
    if first.id == second.id then
        return notify(src, '같은 문을 두 번 선택했습니다.', 'error')
    end

    -- 첫 번째로 선택한 문의 권한/이름/상호작용 설정을 기준으로 사용합니다.
    -- 잠금 상태는 둘 중 하나라도 잠겨 있으면 잠김으로 통일합니다.
    local mergedLeaves = { first.leaves[1], second.leaves[1] }
    first.leaves = mergedLeaves
    first.locked = first.locked == true or second.locked == true

    MySQL.transaction.await({
        {
            query = 'UPDATE cookie_doorlock SET leaves = ?, locked = ? WHERE id = ?',
            values = { json.encode(mergedLeaves), first.locked and 1 or 0, first.id }
        },
        {
            query = 'DELETE FROM cookie_doorlock WHERE id = ?',
            values = { second.id }
        }
    })

    Doors[second.id] = nil
    TriggerClientEvent('cookie_doorlock:client:removeDoor', -1, second.id)
    TriggerClientEvent('cookie_doorlock:client:replaceDoor', -1, first)
    refreshAdminUi(-1)
    notify(src, ('%s: 단문 2개를 양문으로 묶었습니다. 이제 한 번만 눌러 두 문이 같이 작동합니다.'):format(first.label), 'success')
end)

RegisterNetEvent('cookie_doorlock:server:adminSetState', function(id, locked)
    local src = source
    if not isDoorAdmin(src) then return end
    id = tonumber(id)
    local door = id and Doors[id]
    if not door then return end
    door.locked = locked == true
    MySQL.update('UPDATE cookie_doorlock SET locked = ? WHERE id = ?', { door.locked and 1 or 0, id })
    TriggerClientEvent('cookie_doorlock:client:updateState', -1, id, door.locked)
    refreshAdminUi(-1)
end)

RegisterNetEvent('cookie_doorlock:server:adminUpdate', function(id, payload)
    local src = source
    if not isDoorAdmin(src) then return end
    id = tonumber(id)
    local door = id and Doors[id]
    if not door or type(payload) ~= 'table' then return end

    local jobs = {}
    if type(payload.jobs) == 'table' then
        local seen = {}
        for _, j in ipairs(payload.jobs) do
            j = tostring(j or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
            if j ~= '' and not seen[j] then seen[j] = true; jobs[#jobs + 1] = j end
        end
    end

    door.label = tostring(payload.label or door.label):sub(1, 80)
    door.jobs = jobs
    door.minGrade = math.max(0, math.floor(tonumber(payload.minGrade) or 0))
    door.requireDuty = payload.requireDuty == true
    door.interactDistance = math.max(1.0, math.min(6.0, tonumber(payload.interactDistance) or Config.DefaultInteractDistance))

    MySQL.update([[
        UPDATE cookie_doorlock
        SET label = ?, jobs = ?, min_grade = ?, require_duty = ?, interact_distance = ?
        WHERE id = ?
    ]], {
        door.label, json.encode(door.jobs), door.minGrade, door.requireDuty and 1 or 0,
        door.interactDistance, id
    })
    TriggerClientEvent('cookie_doorlock:client:replaceDoor', -1, door)
    refreshAdminUi(-1)
    notify(src, '문 설정을 저장했습니다.', 'success')
end)

RegisterNetEvent('cookie_doorlock:server:adminDelete', function(id)
    local src = source
    if not isDoorAdmin(src) then return end
    id = tonumber(id)
    local door = id and Doors[id]
    if not door then return end
    MySQL.update('DELETE FROM cookie_doorlock WHERE id = ?', { id })
    Doors[id] = nil
    TriggerClientEvent('cookie_doorlock:client:removeDoor', -1, id)
    refreshAdminUi(-1)
    notify(src, ('%s 문을 삭제했습니다.'):format(door.label), 'success')
end)
