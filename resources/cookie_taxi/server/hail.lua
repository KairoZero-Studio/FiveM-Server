

local function hlog(...)
    if Config.Debug then  end
end

local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local cache = nil

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_taxi_call (
                id         INT AUTO_INCREMENT PRIMARY KEY,
                name       VARCHAR(60)  NOT NULL,          -- 손님 이름 (고정)
                px         DOUBLE       NULL,              -- 탑승 좌표
                py         DOUBLE       NULL,
                pz         DOUBLE       NULL,
                ph         DOUBLE       NOT NULL DEFAULT 0,
                dx         DOUBLE       NULL,              -- 하차 좌표
                dy         DOUBLE       NULL,
                dz         DOUBLE       NULL,
                model      VARCHAR(60)  NULL,              -- ped 모델(비우면 랜덤)
                is_active  TINYINT(1)   NOT NULL DEFAULT 1,
                created_by VARCHAR(60)  NULL,
                created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)

    if ok then

    else

    end
end)

local function loadAll()
    local rows = {}
    pcall(function()
        rows = MySQL.query.await(
            'SELECT * FROM cookie_taxi_call WHERE is_active = 1 ORDER BY id') or {}
    end)

    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id,
            name = r.name,
            model = r.model,

            hasPickup = (r.px ~= nil),
            hasDrop = (r.dx ~= nil),
            px = r.px, py = r.py, pz = r.pz, ph = r.ph or 0.0,
            dx = r.dx, dy = r.dy, dz = r.dz,
        }
    end

    cache = out
    return out
end

local function all()
    if not cache then loadAll() end
    return cache
end

function CookieTaxiCalls()
    local out = {}
    for _, c in ipairs(all()) do
        if c.hasPickup and c.hasDrop then out[#out + 1] = c end
    end
    return out
end

local function adminOk(src)
    if src == 0 then return true end
    local ok, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return ok and (tonumber(lv) or 0) >= 3
end

local function pushList(src)
    local rows = loadAll()

    local ready = 0
    for _, c in ipairs(rows) do
        if c.hasPickup and c.hasDrop then ready = ready + 1 end
    end

    TriggerClientEvent('cookie_taxi:client:hailList', src, {
        rows = rows,
        ready = ready,
    })
end

RegisterNetEvent('cookie_taxi:server:hailList', function()
    local src = source
    if not adminOk(src) then return end
    pushList(src)
end)

RegisterNetEvent('cookie_taxi:server:callAdd', function(p)
    local src = source
    if not adminOk(src) then return notify(src, '권한이 없습니다', true) end

    local name = tostring((p and p.name) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return notify(src, '손님 이름을 입력하세요', true) end

    local by = '-'
    pcall(function()
        local a = exports.cookie_admin:getAdminName(src)
        if a and a ~= '' then by = a end
    end)

    local id = MySQL.insert.await(
        'INSERT INTO cookie_taxi_call (name, created_by) VALUES (?, ?)',
        { name:sub(1, 60), by })

    cache = nil
    notify(src, ('%s 콜을 만들었습니다. 탑승/하차 좌표를 찍으세요'):format(name), false)

    pushList(src)
end)

RegisterNetEvent('cookie_taxi:server:callRename', function(p)
    local src = source
    if not adminOk(src) then return notify(src, '권한이 없습니다', true) end

    local id = math.floor(tonumber(p and p.id) or 0)
    local name = tostring((p and p.name) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if id <= 0 or name == '' then return notify(src, '이름을 입력하세요', true) end

    MySQL.update.await('UPDATE cookie_taxi_call SET name = ? WHERE id = ?', { name:sub(1, 60), id })
    cache = nil

    notify(src, ('이름을 바꿨습니다: %s'):format(name), false)
    pushList(src)
end)

RegisterNetEvent('cookie_taxi:server:callSetCoord', function(p)
    local src = source
    if not adminOk(src) then return notify(src, '권한이 없습니다', true) end

    local id = math.floor(tonumber(p and p.id) or 0)
    local kind = (p and p.kind == 'drop') and 'drop' or 'pickup'
    if id <= 0 then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local c = GetEntityCoords(ped)

    if kind == 'pickup' then
        local h = GetEntityHeading(ped)
        MySQL.update.await(
            'UPDATE cookie_taxi_call SET px = ?, py = ?, pz = ?, ph = ? WHERE id = ?',
            { c.x, c.y, c.z, h, id })
        notify(src, '탑승 좌표를 지금 자리로 잡았습니다', false)
    else
        MySQL.update.await(
            'UPDATE cookie_taxi_call SET dx = ?, dy = ?, dz = ? WHERE id = ?',
            { c.x, c.y, c.z, id })
        notify(src, '하차 좌표를 지금 자리로 잡았습니다', false)
    end

    cache = nil

    pushList(src)
end)

RegisterNetEvent('cookie_taxi:server:callDelete', function(id)
    local src = source
    if not adminOk(src) then return notify(src, '권한이 없습니다', true) end

    local n = math.floor(tonumber(id) or 0)
    if n <= 0 then return end

    MySQL.query.await('DELETE FROM cookie_taxi_call WHERE id = ?', { n })
    cache = nil

    notify(src, '콜을 삭제했습니다', false)
    pushList(src)
end)

RegisterCommand('taxihails', function(src)
    if src ~= 0 and not adminOk(src) then return end
    CreateThread(function()
        local rows = all()
        local ready = CookieTaxiCalls()

        for _, c in ipairs(rows) do

        end
    end)
end, false)