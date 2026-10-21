

local function alog(...) if Config.Trucker.Debug then  end end

local MAX_SPAWN_PER_NPC = 10

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_trucker_spawn (
                id INT AUTO_INCREMENT PRIMARY KEY, npc_id INT NULL, label VARCHAR(60) NOT NULL,
                x DOUBLE, y DOUBLE, z DOUBLE, h DOUBLE DEFAULT 0,
                is_active TINYINT(1) DEFAULT 1, created_by VARCHAR(60), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_trucker_stock (
                id INT AUTO_INCREMENT PRIMARY KEY, npc_id INT NULL, label VARCHAR(60) NOT NULL,
                x DOUBLE, y DOUBLE, z DOUBLE, h DOUBLE DEFAULT 0, daily_limit INT NOT NULL DEFAULT 1000,
                is_active TINYINT(1) DEFAULT 1, created_by VARCHAR(60), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_trucker_stock_daily (
                stock_id INT NOT NULL, ymd DATE NOT NULL, taken INT NOT NULL DEFAULT 0,
                PRIMARY KEY (stock_id, ymd)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_trucker_dest (
                id INT AUTO_INCREMENT PRIMARY KEY, npc_id INT NULL, label VARCHAR(60) NOT NULL,
                x DOUBLE, y DOUBLE, z DOUBLE, image MEDIUMTEXT NULL, pay INT NULL,
                is_active TINYINT(1) DEFAULT 1, created_by VARCHAR(60), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ]])

        MySQL.query.await("ALTER TABLE cookie_trucker_spawn ADD COLUMN IF NOT EXISTS npc_id INT NULL")
        MySQL.query.await("ALTER TABLE cookie_trucker_stock ADD COLUMN IF NOT EXISTS npc_id INT NULL")
        MySQL.query.await("ALTER TABLE cookie_trucker_dest  ADD COLUMN IF NOT EXISTS npc_id INT NULL")
        MySQL.query.await("ALTER TABLE cookie_trucker_dest  ADD COLUMN IF NOT EXISTS image MEDIUMTEXT NULL")
        MySQL.query.await("ALTER TABLE cookie_trucker_dest  ADD COLUMN IF NOT EXISTS pay INT NULL")
    end)
    if ok then  else  end
end)

local function adminLevel(src)
    local ok, lv = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return (ok and tonumber(lv)) or 0
end
local function adminName(src)
    local ok, n = pcall(function() return exports.cookie_admin:getAdminName(src) end)
    return (ok and type(n) == 'string' and n) or ('src' .. tostring(src))
end
local function isAdmin(src) return adminLevel(src) >= 3 end
local function notify(src, msg, err) TriggerClientEvent('cookie_admin:client:notify', src, msg, err and true or false) end
local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return c.x, c.y, c.z, GetEntityHeading(ped)
end
local function nid(v) local n = tonumber(v); return (n and n > 0) and math.floor(n) or nil end

function CookieTruckerSpawns(npcId)
    if nid(npcId) then return MySQL.query.await('SELECT id,label,x,y,z,h FROM cookie_trucker_spawn WHERE is_active=1 AND npc_id=? ORDER BY id', { nid(npcId) }) or {} end
    return MySQL.query.await('SELECT id,label,x,y,z,h,npc_id FROM cookie_trucker_spawn WHERE is_active=1 ORDER BY id') or {}
end
function CookieTruckerStocks(npcId)
    if nid(npcId) then return MySQL.query.await('SELECT id,label,x,y,z,h,daily_limit FROM cookie_trucker_stock WHERE is_active=1 AND npc_id=? ORDER BY id', { nid(npcId) }) or {} end
    return MySQL.query.await('SELECT id,label,x,y,z,h,daily_limit,npc_id FROM cookie_trucker_stock WHERE is_active=1 ORDER BY id') or {}
end
function CookieTruckerDests(npcId)
    if nid(npcId) then return MySQL.query.await('SELECT id,label,x,y,z,image,pay FROM cookie_trucker_dest WHERE is_active=1 AND npc_id=? ORDER BY id', { nid(npcId) }) or {} end
    return MySQL.query.await('SELECT id,label,x,y,z,image,pay,npc_id FROM cookie_trucker_dest WHERE is_active=1 ORDER BY id') or {}
end

local function addSpawn(src, label, npcId)
    if nid(npcId) then
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM cookie_trucker_spawn WHERE is_active=1 AND npc_id=?', { nid(npcId) }) or 0
        if n >= MAX_SPAWN_PER_NPC then notify(src, ('출발지 슬롯은 NPC당 최대 %d개입니다'):format(MAX_SPAWN_PER_NPC), true); return false end
    end
    local x, y, z, h = coordsOf(src); if not x then return false end
    MySQL.insert.await('INSERT INTO cookie_trucker_spawn (npc_id,label,x,y,z,h,created_by) VALUES (?,?,?,?,?,?,?)', { nid(npcId), label, x, y, z, h, adminName(src) })
    return true
end
local function addStock(src, label, limit, npcId)
    local x, y, z, h = coordsOf(src); if not x then return false end
    MySQL.insert.await('INSERT INTO cookie_trucker_stock (npc_id,label,x,y,z,h,daily_limit,created_by) VALUES (?,?,?,?,?,?,?,?)', { nid(npcId), label, x, y, z, h, limit, adminName(src) })
    return true
end
local function addDest(src, label, npcId)
    local x, y, z = coordsOf(src); if not x then return false end

    MySQL.insert.await('INSERT INTO cookie_trucker_dest (npc_id,label,x,y,z,created_by) VALUES (?,?,?,?,?,?)', { nid(npcId), label, x, y, z, adminName(src) })
    return true
end
local TBL = { spawn = 'cookie_trucker_spawn', stock = 'cookie_trucker_stock', dest = 'cookie_trucker_dest' }
local function delCoord(kind, id)
    local t = TBL[kind]; if not t then return false end
    MySQL.update.await(('UPDATE %s SET is_active=0 WHERE id=?'):format(t), { id })
    return true
end

local function fmtRows(rows)
    local o = {}
    for _, r in ipairs(rows) do
        o[#o+1] = { id = r.id, label = r.label, x = r.x, y = r.y, z = r.z, has = (r.x ~= nil), limit = r.daily_limit }
    end
    return o
end

local function fmtDests(rows)
    local o = {}
    for _, r in ipairs(rows) do
        o[#o+1] = { id = r.id, label = r.label, x = r.x, y = r.y, z = r.z, has = (r.x ~= nil),
                    hasImg = (r.image ~= nil and r.image ~= ''), pay = r.pay }
    end
    return o
end
local function pushList(src, npcId)
    TriggerClientEvent('cookie_trucker:client:coordList', src, {
        npcId = nid(npcId),
        spawn = fmtRows(CookieTruckerSpawns(npcId)),
        stock = fmtRows(CookieTruckerStocks(npcId)),
        dest  = fmtDests(CookieTruckerDests(npcId)),
    })
end

RegisterNetEvent('cookie_trucker:server:coordList', function(npcId)
    local src = source
    if not isAdmin(src) then return end
    CreateThread(function() pushList(src, npcId) end)
end)

RegisterNetEvent('cookie_trucker:server:coordAdd', function(kind, label, limit, npcId)
    local src = source
    if not isAdmin(src) then return notify(src, '권한이 없습니다', true) end
    if not nid(npcId) then return notify(src, '먼저 NPC를 선택하세요', true) end
    label = tostring(label or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 60)
    if label == '' then return notify(src, '이름을 입력하세요', true) end
    CreateThread(function()
        local okAdd = false
        if kind == 'spawn' then okAdd = addSpawn(src, label, npcId)
        elseif kind == 'stock' then okAdd = addStock(src, label, math.max(1, math.floor(tonumber(limit) or 1000)), npcId)
        elseif kind == 'dest' then okAdd = addDest(src, label, npcId) end
        if okAdd then notify(src, '등록했습니다: ' .. label, false) end
        pushList(src, npcId)
    end)
end)

RegisterNetEvent('cookie_trucker:server:coordRename', function(kind, id, name, npcId)
    local src = source
    if not isAdmin(src) then return end
    local t = TBL[kind]; if not t then return end
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 60)
    if name == '' then return notify(src, '이름을 입력하세요', true) end
    CreateThread(function()
        MySQL.update.await(('UPDATE %s SET label=? WHERE id=?'):format(t), { name, math.floor(tonumber(id) or 0) })
        notify(src, '이름을 바꿨습니다', false); pushList(src, npcId)
    end)
end)

RegisterNetEvent('cookie_trucker:server:coordSetCoord', function(kind, id, npcId)
    local src = source
    if not isAdmin(src) then return end
    local t = TBL[kind]; if not t then return end
    local x, y, z, h = coordsOf(src); if not x then return end
    CreateThread(function()
        if kind == 'dest' then
            MySQL.update.await(('UPDATE %s SET x=?,y=?,z=? WHERE id=?'):format(t), { x, y, z, math.floor(tonumber(id) or 0) })
        else
            MySQL.update.await(('UPDATE %s SET x=?,y=?,z=?,h=? WHERE id=?'):format(t), { x, y, z, h, math.floor(tonumber(id) or 0) })
        end
        notify(src, '좌표를 지금 자리로 잡았습니다', false); pushList(src, npcId)
    end)
end)

RegisterNetEvent('cookie_trucker:server:coordSetLimit', function(id, limit, npcId)
    local src = source
    if not isAdmin(src) then return end
    CreateThread(function()
        MySQL.update.await('UPDATE cookie_trucker_stock SET daily_limit=? WHERE id=?',
            { math.max(1, math.floor(tonumber(limit) or 1000)), math.floor(tonumber(id) or 0) })
        notify(src, '하루 한도를 저장했습니다', false); pushList(src, npcId)
    end)
end)

RegisterNetEvent('cookie_trucker:server:coordDelete', function(kind, id, npcId)
    local src = source
    if not isAdmin(src) then return end
    CreateThread(function()
        delCoord(kind, math.floor(tonumber(id) or 0))
        notify(src, '삭제했습니다', false); pushList(src, npcId)
    end)
end)

RegisterNetEvent('cookie_trucker:server:destImage', function(id, dataUrl, npcId)
    local src = source
    if not isAdmin(src) then return notify(src, '권한이 없습니다', true) end
    if type(dataUrl) ~= 'string' or #dataUrl < 32 or #dataUrl > 6000000 then
        return notify(src, '이미지 데이터가 올바르지 않습니다', true)
    end
    if not dataUrl:find('^data:image/') then return notify(src, '이미지 형식이 아닙니다', true) end
    CreateThread(function()
        MySQL.update.await('UPDATE cookie_trucker_dest SET image=? WHERE id=?', { dataUrl, math.floor(tonumber(id) or 0) })
        notify(src, '배송지 장면을 저장했습니다', false); pushList(src, npcId)
    end)
end)

RegisterNetEvent('cookie_trucker:server:destPay', function(id, pay, npcId)
    local src = source
    if not isAdmin(src) then return end
    CreateThread(function()
        local p = tonumber(pay)
        if p and p > 0 then p = math.floor(p) else p = nil end
        MySQL.update.await('UPDATE cookie_trucker_dest SET pay=? WHERE id=?', { p, math.floor(tonumber(id) or 0) })
        notify(src, p and ('보수 ₩' .. p .. ' 저장') or '보수 자동(거리)으로 되돌렸습니다', false); pushList(src, npcId)
    end)
end)


-- ===== 트럭 급여 설정 =====
local TRUCK_PAY_DEFAULT = {
    cargo_min = (Config.Trucker.Cargo and Config.Trucker.Cargo.PriceMin) or 315,
    cargo_max = (Config.Trucker.Cargo and Config.Trucker.Cargo.PriceMax) or 450,
    per_km = Config.Trucker.PerKmReward or 500,
    max_pay = Config.Trucker.MaxPay or 300000,
}

local function applyTruckPay(r)
    if not r then return end
    Config.Trucker.Cargo.PriceMin = tonumber(r.cargo_min) or TRUCK_PAY_DEFAULT.cargo_min
    Config.Trucker.Cargo.PriceMax = tonumber(r.cargo_max) or TRUCK_PAY_DEFAULT.cargo_max
    Config.Trucker.PerKmReward = tonumber(r.per_km) or TRUCK_PAY_DEFAULT.per_km
    Config.Trucker.MaxPay = tonumber(r.max_pay) or TRUCK_PAY_DEFAULT.max_pay
end

function CookieTruckerPayCfg()
    local r=MySQL.single.await('SELECT cargo_min,cargo_max,per_km,max_pay FROM cookie_trucker_paycfg WHERE id=1')
    if r then applyTruckPay(r); return r end
    return TRUCK_PAY_DEFAULT
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_trucker_paycfg (
            id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,
            cargo_min INT NOT NULL DEFAULT 315,
            cargo_max INT NOT NULL DEFAULT 450,
            per_km INT NOT NULL DEFAULT 500,
            max_pay INT NOT NULL DEFAULT 300000,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.insert.await('INSERT IGNORE INTO cookie_trucker_paycfg(id,cargo_min,cargo_max,per_km,max_pay) VALUES(1,?,?,?,?)',
        {TRUCK_PAY_DEFAULT.cargo_min,TRUCK_PAY_DEFAULT.cargo_max,TRUCK_PAY_DEFAULT.per_km,TRUCK_PAY_DEFAULT.max_pay})
    CookieTruckerPayCfg()
end)

RegisterNetEvent('cookie_trucker:server:adminPayGet',function()
    local src=source
    if not isAdmin(src) then return end
    TriggerClientEvent('cookie_trucker:client:adminPay',src,CookieTruckerPayCfg())
end)

RegisterNetEvent('cookie_trucker:server:adminPaySave',function(d)
    local src=source
    if not isAdmin(src) or type(d)~='table' then return end
    local mn=math.max(0,math.floor(tonumber(d.cargoMin) or TRUCK_PAY_DEFAULT.cargo_min))
    local mx=math.max(mn,math.floor(tonumber(d.cargoMax) or TRUCK_PAY_DEFAULT.cargo_max))
    local km=math.max(0,math.floor(tonumber(d.perKm) or TRUCK_PAY_DEFAULT.per_km))
    local cap=math.max(0,math.floor(tonumber(d.maxPay) or TRUCK_PAY_DEFAULT.max_pay))
    MySQL.update.await('UPDATE cookie_trucker_paycfg SET cargo_min=?,cargo_max=?,per_km=?,max_pay=? WHERE id=1',{mn,mx,km,cap})
    local r=CookieTruckerPayCfg()
    notify(src,'트럭 급여 설정을 저장했습니다.',false)
    TriggerClientEvent('cookie_trucker:client:adminPay',src,r)
end)
