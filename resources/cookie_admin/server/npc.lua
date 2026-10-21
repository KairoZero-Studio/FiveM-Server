

local function nlog(...)
    if Config.Debug then  end
end

local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_npc (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                label       VARCHAR(60)  NOT NULL,
                model       VARCHAR(60)  NOT NULL,
                x           DOUBLE       NOT NULL,
                y           DOUBLE       NOT NULL,
                z           DOUBLE       NOT NULL,
                heading     DOUBLE       NOT NULL DEFAULT 0,
                scenario    VARCHAR(60)  NULL,
                components  TEXT         NULL,   -- JSON. 의상 덮어쓰기
                job_key     VARCHAR(40)  NULL,   -- 다음 단계(상호작용)용. 지금은 비워둔다
                is_active   TINYINT(1)   NOT NULL DEFAULT 1,
                created_by  VARCHAR(60)  NULL,
                created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)

    if ok then

    else

    end
end)

local function allNpcs()
    return MySQL.query.await(
        'SELECT * FROM cookie_npc WHERE is_active = 1 ORDER BY id') or {}
end

local function npcAuth(src)
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin then return nil end
    if (admin.admin_level or 0) < (Config.NpcEditMinLevel or 3) then return nil end
    return admin
end

local function npcJobKeys()
    local out, hasFishing, hasMining = {}, false, false
    for _, j in ipairs(Config.NpcJobKeys or {}) do
        out[#out + 1] = j
        if j.key == 'fishing' then hasFishing = true end
        if j.key == 'mining' then hasMining = true end
    end
    if not hasFishing then out[#out + 1] = { key = 'fishing', label = '낚시 관리인' } end
    if not hasMining then out[#out + 1] = { key = 'mining', label = '광물 관리인' } end
    return out
end

local function normalizeJobKey(v)
    if type(v) ~= 'string' or v == '' then return nil end
    for _, j in ipairs(npcJobKeys()) do
        if j.key ~= '' and j.key == v then return v end
    end
    return nil
end

local function adminPayload()
    return {
        rows = allNpcs(),
        peds = Config.NpcPeds,
        scenarios = Config.NpcScenarios,
        components = Config.NpcComponents,
        jobKeys = npcJobKeys(),
    }
end

local function broadcast()
    TriggerClientEvent('cookie_admin:client:npcList', -1, allNpcs())
end

RegisterNetEvent('cookie_admin:server:requestNpcs', function(reason)
    local src=source
    local rows=allNpcs()
    print(('[cookie_admin] NPC sync -> src=%s count=%d reason=%s'):format(src,#rows,tostring(reason or '-')))
    TriggerClientEvent('cookie_admin:client:npcList', src, rows)
end)

RegisterNetEvent('cookie_admin:server:requestNpcAdmin', function()
    local src = source
    if not npcAuth(src) then return notify(src, ('LV%d 이상만 NPC를 다룰 수 있습니다'):format(Config.NpcEditMinLevel or 3), true) end

    TriggerClientEvent('cookie_admin:client:npcAdmin', src, adminPayload())
end)

RegisterNetEvent('cookie_admin:server:npcSave', function(p)
    local src = source
    local admin = npcAuth(src)
    if not admin then return notify(src, '권한이 없습니다', true) end
    if type(p) ~= 'table' then return end

    local label = tostring(p.label or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local model = tostring(p.model or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if label == '' then return notify(src, 'NPC 이름을 입력하세요', true) end
    if model == '' then return notify(src, 'ped 모델을 고르세요', true) end

    local x, y, z = tonumber(p.x), tonumber(p.y), tonumber(p.z)
    if not (x and y and z) then return notify(src, '좌표가 올바르지 않습니다', true) end

    local heading = tonumber(p.heading) or 0.0
    local scenario = (type(p.scenario) == 'string' and p.scenario ~= '') and p.scenario:sub(1, 60) or nil

    local comps = nil
    if type(p.components) == 'table' and next(p.components) then
        comps = json.encode(p.components)
    end

    local jobKey = normalizeJobKey(p.job_key)

    local id = tonumber(p.id)

    if id and id > 0 then
        MySQL.update.await([[
            UPDATE cookie_npc
               SET label = ?, model = ?, x = ?, y = ?, z = ?, heading = ?,
                   scenario = ?, components = ?, job_key = ?
             WHERE id = ?
        ]], { label:sub(1, 60), model:sub(1, 60), x, y, z, heading, scenario, comps, jobKey, id })
        notify(src, ('%s NPC를 수정했습니다'):format(label), false)

    else
        id = MySQL.insert.await([[
            INSERT INTO cookie_npc (label, model, x, y, z, heading, scenario, components, job_key, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], { label:sub(1, 60), model:sub(1, 60), x, y, z, heading, scenario, comps, jobKey,
              admin.admin_name or '-' })
        notify(src, ('%s NPC를 배치했습니다'):format(label), false)

    end

    broadcast()
    TriggerEvent('cookie_admin:server:npcAdminRefresh', src)
end)

AddEventHandler('cookie_admin:server:npcAdminRefresh', function(src)
    if not npcAuth(src) then return end
    TriggerClientEvent('cookie_admin:client:npcAdmin', src, adminPayload())
end)

RegisterNetEvent('cookie_admin:server:npcDelete', function(npcId)
    local src = source
    if not npcAuth(src) then return notify(src, '권한이 없습니다', true) end

    local id = math.floor(tonumber(npcId) or 0)
    if id <= 0 then return end

    local row = MySQL.single.await('SELECT label FROM cookie_npc WHERE id = ?', { id })
    MySQL.query.await('DELETE FROM cookie_npc WHERE id = ?', { id })

    notify(src, ('%s NPC를 제거했습니다'):format((row and row.label) or ''), false)

    broadcast()
    TriggerEvent('cookie_admin:server:npcAdminRefresh', src)
end)
