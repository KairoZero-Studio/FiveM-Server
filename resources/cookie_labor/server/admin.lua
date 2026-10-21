
local L = Config.Labor

local function notify(src, msg, err)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, err and true or false)
end

local function auth(src)
    local ok, a = pcall(function()
        return exports.cookie_admin:getEffectiveLevel(src)
    end)
    return ok and (tonumber(a) or 0) >= 3
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_labor_task (
            id          INT AUTO_INCREMENT PRIMARY KEY,
            npc_id      INT NOT NULL,
            label       VARCHAR(80) NOT NULL,
            box_count   INT NOT NULL DEFAULT 5,
            reward      BIGINT NOT NULL DEFAULT 25000,

            source_x    DOUBLE NULL,
            source_y    DOUBLE NULL,
            source_z    DOUBLE NULL,

            dest_x      DOUBLE NULL,
            dest_y      DOUBLE NULL,
            dest_z      DOUBLE NULL,

            sort_order  INT NOT NULL DEFAULT 0,
            is_active   TINYINT(1) NOT NULL DEFAULT 1,
            created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

            INDEX idx_labor_npc (npc_id),
            INDEX idx_labor_active (is_active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})
end)

local function rowsFor(npcId)
    npcId = math.floor(tonumber(npcId) or 0)
    if npcId <= 0 then return {} end

    local rows = MySQL.query.await([[
        SELECT id, npc_id, label, box_count, reward,
               source_x, source_y, source_z,
               dest_x, dest_y, dest_z,
               sort_order, is_active
        FROM cookie_labor_task
        WHERE npc_id = ? AND is_active = 1
        ORDER BY sort_order, id
    ]], { npcId }) or {}

    for _, r in ipairs(rows) do
        r.hasSource = r.source_x ~= nil and r.source_y ~= nil and r.source_z ~= nil
        r.hasDest = r.dest_x ~= nil and r.dest_y ~= nil and r.dest_z ~= nil
    end
    return rows
end

local function push(src, npcId)
    TriggerClientEvent('cookie_labor:client:adminData', src, {
        npcId = tonumber(npcId),
        rows = rowsFor(npcId),
    })
end

RegisterNetEvent('cookie_labor:server:adminList', function(npcId)
    local src = source
    if not auth(src) then return end
    push(src, npcId)
end)

RegisterNetEvent('cookie_labor:server:adminAdd', function(data)
    local src = source
    if not auth(src) or type(data) ~= 'table' then return end

    local npcId = math.floor(tonumber(data.npcId) or 0)
    if npcId <= 0 then return end

    local label = tostring(data.label or '상자 운반'):gsub('^%s+', ''):gsub('%s+$', '')
    if label == '' then label = '상자 운반' end

    local count = math.max(L.MinCount or 1, math.min(L.MaxCount or 30, math.floor(tonumber(data.count) or L.DefaultCount or 5)))
    local reward = math.max(L.MinReward or 0, math.min(L.MaxReward or 1000000, math.floor(tonumber(data.reward) or L.DefaultReward or 25000)))

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local pos = GetEntityCoords(ped)

    MySQL.insert.await([[
        INSERT INTO cookie_labor_task
            (npc_id, label, box_count, reward, source_x, source_y, source_z)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { npcId, label:sub(1,80), count, reward, pos.x, pos.y, pos.z })

    notify(src, '건설 작업을 만들었습니다. 현재 위치가 상자 더미 위치로 저장됐습니다.', false)
    push(src, npcId)
end)

RegisterNetEvent('cookie_labor:server:adminUpdate', function(data)
    local src = source
    if not auth(src) or type(data) ~= 'table' then return end

    local id = math.floor(tonumber(data.id) or 0)
    local npcId = math.floor(tonumber(data.npcId) or 0)
    if id <= 0 or npcId <= 0 then return end

    local label = tostring(data.label or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if label == '' then return notify(src, '작업 이름을 입력하세요', true) end

    local count = math.max(L.MinCount or 1, math.min(L.MaxCount or 30, math.floor(tonumber(data.count) or L.DefaultCount or 5)))
    local reward = math.max(L.MinReward or 0, math.min(L.MaxReward or 1000000, math.floor(tonumber(data.reward) or L.DefaultReward or 25000)))

    MySQL.update.await([[
        UPDATE cookie_labor_task
        SET label = ?, box_count = ?, reward = ?
        WHERE id = ? AND npc_id = ?
    ]], { label:sub(1,80), count, reward, id, npcId })

    notify(src, '건설 작업 설정을 저장했습니다.', false)
    push(src, npcId)
end)

RegisterNetEvent('cookie_labor:server:adminSetCoord', function(data)
    local src = source
    if not auth(src) or type(data) ~= 'table' then return end

    local id = math.floor(tonumber(data.id) or 0)
    local npcId = math.floor(tonumber(data.npcId) or 0)
    local kind = tostring(data.kind or '')
    if id <= 0 or npcId <= 0 or (kind ~= 'source' and kind ~= 'dest') then return end

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local p = GetEntityCoords(ped)

    if kind == 'source' then
        MySQL.update.await([[
            UPDATE cookie_labor_task SET source_x = ?, source_y = ?, source_z = ?
            WHERE id = ? AND npc_id = ?
        ]], { p.x, p.y, p.z, id, npcId })
        notify(src, '상자 더미 위치를 현재 위치로 저장했습니다.', false)
    else
        MySQL.update.await([[
            UPDATE cookie_labor_task SET dest_x = ?, dest_y = ?, dest_z = ?
            WHERE id = ? AND npc_id = ?
        ]], { p.x, p.y, p.z, id, npcId })
        notify(src, '운반 목적지를 현재 위치로 저장했습니다.', false)
    end

    push(src, npcId)
end)

RegisterNetEvent('cookie_labor:server:adminDelete', function(data)
    local src = source
    if not auth(src) or type(data) ~= 'table' then return end

    local id = math.floor(tonumber(data.id) or 0)
    local npcId = math.floor(tonumber(data.npcId) or 0)
    if id <= 0 or npcId <= 0 then return end

    MySQL.update.await('UPDATE cookie_labor_task SET is_active = 0 WHERE id = ? AND npc_id = ?', { id, npcId })
    notify(src, '건설 작업을 삭제했습니다.', false)
    push(src, npcId)
end)

exports('tasksForNpc', rowsFor)
