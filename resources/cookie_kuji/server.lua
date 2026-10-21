local drawLocks = {}
local settingsCache = nil
local prizesCache = nil

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

local function decodeMetadata(raw)
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, value = pcall(json.decode, raw)
    return ok and type(value) == 'table' and value or {}
end

local function newKujiVehicleUid(seed)
    seed = math.max(0, math.floor(tonumber(seed) or 0))
    for _ = 1, 30 do
        local uid = ('CV-%s-%07d-%06d'):format(os.date('%Y%m%d'), seed % 10000000, math.random(0, 999999))
        local inGarage, inPacked = nil, nil
        pcall(function()
            inGarage = MySQL.single.await('SELECT id FROM player_vehicles WHERE cookie_asset_uid=? LIMIT 1', { uid })
        end)
        pcall(function()
            inPacked = MySQL.single.await("SELECT id FROM cookie_kuji_owned WHERE asset_uid=? AND reward_type='vehicle' AND state='packed' LIMIT 1", { uid })
        end)
        if not inGarage and not inPacked then return uid end
    end
    return nil
end

local function clampInt(v, lo, hi, fallback)
    v = math.floor(tonumber(v) or fallback or 0)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function trim(v, maxLen)
    local s = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function boolInt(v)
    return (v == true or tonumber(v) == 1) and 1 or 0
end

local function playerInfo(src)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData then return nil end
    local pd = p.PlayerData
    local ci = pd.charinfo or {}
    return {
        player = p,
        citizenid = tostring(pd.citizenid or ''),
        name = trim(((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', ''), 80),
        license = GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license'),
    }
end


local function columnExists(tableName, columnName)
    local n = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
          AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    return tonumber(n) and tonumber(n) > 0
end

local function ensureColumn(tableName, columnName, definition)
    if columnExists(tableName, columnName) then return end
    MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    print(('^3[cookie_kuji]^7 DB migration: %s.%s added'):format(tableName, columnName))
end

local function migrateOldSchema()
    -- CREATE TABLE IF NOT EXISTS는 기존 테이블의 컬럼을 추가해주지 않기 때문에
    -- 이전 개발 버전 테이블이 남아 있어도 자동으로 최신 스키마로 보정한다.
    ensureColumn('cookie_kuji_config', 'enabled', "TINYINT(1) NOT NULL DEFAULT 1")
    ensureColumn('cookie_kuji_config', 'title', "VARCHAR(80) NOT NULL DEFAULT 'COOKIE 월간 쿠지'")
    ensureColumn('cookie_kuji_config', 'season_month', "CHAR(7) NOT NULL DEFAULT '2026-09'")
    ensureColumn('cookie_kuji_config', 'ticket_item', "VARCHAR(80) NOT NULL DEFAULT 'cookie_kuji_ticket'")
    ensureColumn('cookie_kuji_config', 'beacon_x', "DOUBLE NOT NULL DEFAULT 190.0")
    ensureColumn('cookie_kuji_config', 'beacon_y', "DOUBLE NOT NULL DEFAULT -932.09")
    ensureColumn('cookie_kuji_config', 'beacon_z', "DOUBLE NOT NULL DEFAULT 30.69")
    ensureColumn('cookie_kuji_config', 'beacon_r', "SMALLINT NOT NULL DEFAULT 255")
    ensureColumn('cookie_kuji_config', 'beacon_g', "SMALLINT NOT NULL DEFAULT 190")
    ensureColumn('cookie_kuji_config', 'beacon_b', "SMALLINT NOT NULL DEFAULT 45")
    ensureColumn('cookie_kuji_config', 'beacon_a', "SMALLINT NOT NULL DEFAULT 155")
    ensureColumn('cookie_kuji_config', 'updated_at', "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")

    ensureColumn('cookie_kuji_prize', 'season_month', "CHAR(7) NOT NULL DEFAULT '2026-09'")
    ensureColumn('cookie_kuji_prize', 'grade', "VARCHAR(12) NOT NULL DEFAULT 'C'")
    ensureColumn('cookie_kuji_prize', 'label', "VARCHAR(100) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_prize', 'reward_type', "VARCHAR(24) NOT NULL DEFAULT 'item'")
    ensureColumn('cookie_kuji_prize', 'reward_key', "VARCHAR(100) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_prize', 'amount', "INT NOT NULL DEFAULT 1")
    ensureColumn('cookie_kuji_prize', 'stock_total', "INT NOT NULL DEFAULT 1")
    ensureColumn('cookie_kuji_prize', 'stock_remaining', "INT NOT NULL DEFAULT 1")
    ensureColumn('cookie_kuji_prize', 'image', "VARCHAR(500) NULL")
    ensureColumn('cookie_kuji_prize', 'metadata_json', "LONGTEXT NULL")
    ensureColumn('cookie_kuji_prize', 'sort_order', "INT NOT NULL DEFAULT 0")
    ensureColumn('cookie_kuji_prize', 'created_at', "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")
    ensureColumn('cookie_kuji_prize', 'updated_at', "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")

    ensureColumn('cookie_kuji_draw', 'season_month', "CHAR(7) NOT NULL DEFAULT '2026-09'")
    ensureColumn('cookie_kuji_draw', 'citizenid', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_draw', 'license', "VARCHAR(100) NULL")
    ensureColumn('cookie_kuji_draw', 'player_name', "VARCHAR(80) NULL")
    ensureColumn('cookie_kuji_draw', 'prize_id', "BIGINT UNSIGNED NULL")
    ensureColumn('cookie_kuji_draw', 'grade', "VARCHAR(12) NOT NULL DEFAULT 'C'")
    ensureColumn('cookie_kuji_draw', 'label', "VARCHAR(100) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_draw', 'reward_type', "VARCHAR(24) NOT NULL DEFAULT 'item'")
    ensureColumn('cookie_kuji_draw', 'reward_key', "VARCHAR(100) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_draw', 'amount', "INT NOT NULL DEFAULT 1")
    ensureColumn('cookie_kuji_draw', 'created_at', "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")

    ensureColumn('cookie_kuji_owned', 'citizenid', "VARCHAR(64) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_owned', 'source_draw_id', "BIGINT UNSIGNED NULL")
    ensureColumn('cookie_kuji_owned', 'reward_type', "VARCHAR(24) NOT NULL DEFAULT 'item'")
    ensureColumn('cookie_kuji_owned', 'reward_key', "VARCHAR(100) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_owned', 'label', "VARCHAR(100) NOT NULL DEFAULT ''")
    ensureColumn('cookie_kuji_owned', 'state', "VARCHAR(24) NOT NULL DEFAULT 'packed'")
    ensureColumn('cookie_kuji_owned', 'metadata_json', "LONGTEXT NULL")
    ensureColumn('cookie_kuji_owned', 'asset_uid', "VARCHAR(40) NULL")
    ensureColumn('cookie_kuji_owned', 'created_at', "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")
    ensureColumn('cookie_kuji_owned', 'updated_at', "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")
end

local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_kuji_config` (
          `id` TINYINT UNSIGNED NOT NULL DEFAULT 1,
          `enabled` TINYINT(1) NOT NULL DEFAULT 1,
          `title` VARCHAR(80) NOT NULL DEFAULT 'COOKIE 월간 쿠지',
          `season_month` CHAR(7) NOT NULL,
          `ticket_item` VARCHAR(80) NOT NULL DEFAULT 'cookie_kuji_ticket',
          `beacon_x` DOUBLE NOT NULL DEFAULT 190.0,
          `beacon_y` DOUBLE NOT NULL DEFAULT -932.09,
          `beacon_z` DOUBLE NOT NULL DEFAULT 30.69,
          `beacon_r` SMALLINT NOT NULL DEFAULT 255,
          `beacon_g` SMALLINT NOT NULL DEFAULT 190,
          `beacon_b` SMALLINT NOT NULL DEFAULT 45,
          `beacon_a` SMALLINT NOT NULL DEFAULT 155,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_kuji_prize` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `season_month` CHAR(7) NOT NULL,
          `grade` VARCHAR(12) NOT NULL DEFAULT 'C',
          `label` VARCHAR(100) NOT NULL,
          `reward_type` VARCHAR(24) NOT NULL,
          `reward_key` VARCHAR(100) NOT NULL,
          `amount` INT NOT NULL DEFAULT 1,
          `stock_total` INT NOT NULL DEFAULT 1,
          `stock_remaining` INT NOT NULL DEFAULT 1,
          `image` VARCHAR(500) NULL,
          `metadata_json` LONGTEXT NULL,
          `sort_order` INT NOT NULL DEFAULT 0,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_kuji_prize_season` (`season_month`,`sort_order`,`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_kuji_draw` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `season_month` CHAR(7) NOT NULL,
          `citizenid` VARCHAR(64) NOT NULL,
          `license` VARCHAR(100) NULL,
          `player_name` VARCHAR(80) NULL,
          `prize_id` BIGINT UNSIGNED NULL,
          `grade` VARCHAR(12) NOT NULL,
          `label` VARCHAR(100) NOT NULL,
          `reward_type` VARCHAR(24) NOT NULL,
          `reward_key` VARCHAR(100) NOT NULL,
          `amount` INT NOT NULL DEFAULT 1,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_kuji_draw_cid` (`citizenid`,`created_at`),
          KEY `idx_kuji_draw_season` (`season_month`,`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- 향후 cookie_collection이 그대로 읽을 수 있는 영구보상 보관 테이블.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_kuji_owned` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `citizenid` VARCHAR(64) NOT NULL,
          `source_draw_id` BIGINT UNSIGNED NULL,
          `reward_type` VARCHAR(24) NOT NULL,
          `reward_key` VARCHAR(100) NOT NULL,
          `label` VARCHAR(100) NOT NULL,
          `state` VARCHAR(24) NOT NULL DEFAULT 'packed',
          `metadata_json` LONGTEXT NULL,
          `asset_uid` VARCHAR(40) NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_kuji_owned_cid` (`citizenid`,`reward_type`,`state`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    migrateOldSchema()

    local d = Config.Default
    MySQL.insert.await([[
        INSERT IGNORE INTO cookie_kuji_config
          (id,enabled,title,season_month,ticket_item,beacon_x,beacon_y,beacon_z,beacon_r,beacon_g,beacon_b,beacon_a)
        VALUES (1,?,?,?,?,?,?,?,?,?,?,?)
    ]], {
        d.enabled and 1 or 0, d.title, d.seasonMonth, d.ticketItem,
        d.beacon.x, d.beacon.y, d.beacon.z,
        d.beaconColor.r, d.beaconColor.g, d.beaconColor.b, d.beaconColor.a
    })

    local cfg = MySQL.single.await('SELECT season_month FROM cookie_kuji_config WHERE id=1')
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM cookie_kuji_prize WHERE season_month=?', { cfg.season_month }) or 0
    if tonumber(count) == 0 then
        for _, p in ipairs(Config.DefaultPrizes or {}) do
            MySQL.insert.await([[
                INSERT INTO cookie_kuji_prize
                  (season_month,grade,label,reward_type,reward_key,amount,stock_total,stock_remaining,image,sort_order)
                VALUES (?,?,?,?,?,?,?,?,?,?)
            ]], { cfg.season_month, p.grade, p.label, p.rewardType, p.rewardKey, p.amount or 1, p.stock or 1, p.stock or 1, p.image or '', p.sortOrder or 0 })
        end
    end
end

local function invalidate()
    settingsCache = nil
    prizesCache = nil
end

local function loadSettings(force)
    if settingsCache and not force then return settingsCache end
    local r = MySQL.single.await('SELECT * FROM cookie_kuji_config WHERE id=1')
    if not r then return nil end
    local enabledValue = r.enabled
    local enabled = enabledValue == true
        or tonumber(enabledValue) == 1
        or tostring(enabledValue) == '1'

    settingsCache = {
        enabled = enabled,
        title = r.title,
        seasonMonth = r.season_month,
        ticketItem = r.ticket_item,
        beacon = { x = tonumber(r.beacon_x), y = tonumber(r.beacon_y), z = tonumber(r.beacon_z) },
        beaconColor = { r = tonumber(r.beacon_r), g = tonumber(r.beacon_g), b = tonumber(r.beacon_b), a = tonumber(r.beacon_a) },
    }
    return settingsCache
end

local function loadPrizes(force)
    local cfg = loadSettings(force)
    if not cfg then return {} end
    if prizesCache and not force then return prizesCache end
    local rows = MySQL.query.await([[
        SELECT id,grade,label,reward_type,reward_key,amount,stock_total,stock_remaining,image,metadata_json,sort_order
        FROM cookie_kuji_prize WHERE season_month=? ORDER BY sort_order,id
    ]], { cfg.seasonMonth }) or {}
    prizesCache = rows
    return rows
end

local function ticketCount(src, item)
    local ok, n = pcall(function() return exports.ox_inventory:GetItemCount(src, item) end)
    return ok and tonumber(n) or 0
end

local function publicState(src, includeHistory)
    local cfg = loadSettings(false)
    local rows = loadPrizes(false)
    local total, remaining = 0, 0
    local prizes = {}
    for _, r in ipairs(rows) do
        total = total + (tonumber(r.stock_total) or 0)
        remaining = remaining + (tonumber(r.stock_remaining) or 0)
        prizes[#prizes+1] = {
            id = tonumber(r.id), grade = r.grade, label = r.label,
            rewardType = r.reward_type, rewardKey = r.reward_key,
            amount = tonumber(r.amount) or 1,
            stock = tonumber(r.stock_total) or 0,
            remaining = tonumber(r.stock_remaining) or 0,
            image = r.image or '', sortOrder = tonumber(r.sort_order) or 0,
        }
    end
    local history = {}
    if includeHistory then
        local pi = playerInfo(src)
        if pi then
            local h = MySQL.query.await([[
                SELECT grade,label,reward_type,amount,created_at FROM cookie_kuji_draw
                WHERE citizenid=? ORDER BY id DESC LIMIT 12
            ]], { pi.citizenid }) or {}
            history = h
        end
    end
    return {
        enabled = cfg and cfg.enabled or false,
        title = cfg and cfg.title or 'COOKIE 월간 쿠지',
        seasonMonth = cfg and cfg.seasonMonth or '',
        ticketItem = cfg and cfg.ticketItem or 'cookie_kuji_ticket',
        tickets = cfg and ticketCount(src, cfg.ticketItem) or 0,
        total = total,
        remaining = remaining,
        prizes = prizes,
        history = history,
        beacon = cfg and cfg.beacon or nil,
        beaconColor = cfg and cfg.beaconColor or nil,
    }
end

local function pushState(src)
    TriggerClientEvent('cookie_kuji:client:state', src, publicState(src, true))
end

local function choosePrize(rows)
    local total = 0
    for _, r in ipairs(rows) do
        local n = tonumber(r.stock_remaining) or 0
        if n > 0 then total = total + n end
    end
    if total <= 0 then return nil end
    local pick = math.random(1, total)
    local acc = 0
    for _, r in ipairs(rows) do
        local n = tonumber(r.stock_remaining) or 0
        if n > 0 then
            acc = acc + n
            if pick <= acc then return r end
        end
    end
    return nil
end

local permanentTypes = {
    vehicle = true, skin = true, cosmetic = true, furniture = true, collectible = true,
}

local function deliverReward(src, info, prize, drawId)
    local rtype = tostring(prize.reward_type or ''):lower()
    local key = tostring(prize.reward_key or '')
    local amount = math.max(1, tonumber(prize.amount) or 1)

    if rtype == 'item' then
        local ok, ret = pcall(function()
            return exports.ox_inventory:AddItem(src, key, amount, {
                kujiSeason = loadSettings(false).seasonMonth,
                kujiPrize = prize.label,
            })
        end)
        return ok and ret == true, ok and nil or tostring(ret)
    elseif rtype == 'money' then
        local moneyType = (key == 'bank') and 'bank' or 'cash'
        info.player.Functions.AddMoney(moneyType, amount, 'cookie-kuji')
        return true
    elseif permanentTypes[rtype] then
        local metadata = prize.metadata_json
        local assetUid = nil
        if rtype == 'vehicle' then
            local meta = decodeMetadata(metadata)
            assetUid = newKujiVehicleUid(drawId or os.time())
            if not assetUid then return false, '차량 고유 ID 생성 실패' end
            meta.asset_uid = assetUid
            meta.model = tostring(meta.model or key):lower()
            meta.packaged_vehicle = true
            meta.kuji_vehicle = true
            meta.kuji_draw_id = drawId
            metadata = json.encode(meta)
        end

        local id = MySQL.insert.await([[
            INSERT INTO cookie_kuji_owned
              (citizenid,source_draw_id,reward_type,reward_key,label,state,metadata_json,asset_uid)
            VALUES (?,?,?,?,?,'packed',?,?)
        ]], { info.citizenid, drawId, rtype, key, prize.label, metadata, assetUid })
        return id ~= nil
    end
    return false, '지원하지 않는 보상 타입'
end

RegisterNetEvent('cookie_kuji:server:requestOpen', function()
    local src = source
    pushState(src)
end)

RegisterNetEvent('cookie_kuji:server:requestBootstrap', function()
    local src = source
    local d = publicState(src, false)
    TriggerClientEvent('cookie_kuji:client:bootstrap', src, {
        enabled = d.enabled,
        title = d.title,
        seasonMonth = d.seasonMonth,
        beacon = d.beacon,
        beaconColor = d.beaconColor,
    })
end)

RegisterNetEvent('cookie_kuji:server:draw', function(requestedCount)
    local src = source
    if not cookieAllowAction(src, 'kuji_draw', 1200, 1) then return end
    if drawLocks[src] then return end
    drawLocks[src] = true

    local function finish()
        drawLocks[src] = nil
    end

    local count = tonumber(requestedCount) or 1
    if count ~= 1 and count ~= 5 and count ~= 10 then count = 1 end

    local cfg = loadSettings(true)
    if not cfg or not cfg.enabled then
        TriggerClientEvent('cookie_kuji:client:result', src, { ok=false, message='현재 쿠지가 운영 중이 아닙니다.' })
        finish(); return
    end

    local info = playerInfo(src)
    if not info then finish(); return end

    local tickets = ticketCount(src, cfg.ticketItem)
    if tickets < count then
        TriggerClientEvent('cookie_kuji:client:result', src, { ok=false, message=('쿠지 티켓이 부족합니다. (%d/%d장)'):format(tickets, count) })
        finish(); return
    end

    local remainingNow = 0
    for _, r in ipairs(loadPrizes(true)) do
        remainingNow = remainingNow + math.max(0, tonumber(r.stock_remaining) or 0)
    end
    if remainingNow < count then
        TriggerClientEvent('cookie_kuji:client:result', src, { ok=false, message=('남은 경품이 부족합니다. (%d개 남음 / %d회 요청)'):format(remainingNow, count) })
        finish(); return
    end

    local okRemove, retRemove = pcall(function()
        return exports.ox_inventory:RemoveItem(src, cfg.ticketItem, count)
    end)
    if not (okRemove and retRemove == true) then
        TriggerClientEvent('cookie_kuji:client:result', src, { ok=false, message='쿠지 티켓을 사용할 수 없습니다.' })
        finish(); return
    end

    local results = {}
    local refundTickets = 0
    local errors = {}

    for drawIndex = 1, count do
        local chosen = nil
        for _ = 1, 8 do
            local rows = loadPrizes(true)
            chosen = choosePrize(rows)
            if not chosen then break end
            local changed = MySQL.update.await([[
                UPDATE cookie_kuji_prize SET stock_remaining=stock_remaining-1
                WHERE id=? AND season_month=? AND stock_remaining>0
            ]], { chosen.id, cfg.seasonMonth })
            if tonumber(changed) and tonumber(changed) > 0 then break end
            chosen = nil
        end

        if not chosen then
            refundTickets = refundTickets + (count - drawIndex + 1)
            errors[#errors+1] = '남은 경품을 확보하지 못했습니다.'
            break
        end

        local drawId = MySQL.insert.await([[
            INSERT INTO cookie_kuji_draw
              (season_month,citizenid,license,player_name,prize_id,grade,label,reward_type,reward_key,amount)
            VALUES (?,?,?,?,?,?,?,?,?,?)
        ]], { cfg.seasonMonth, info.citizenid, info.license, info.name, chosen.id, chosen.grade, chosen.label, chosen.reward_type, chosen.reward_key, chosen.amount })

        local delivered, err = deliverReward(src, info, chosen, drawId)
        if not delivered then
            MySQL.update.await('UPDATE cookie_kuji_prize SET stock_remaining=LEAST(stock_total,stock_remaining+1) WHERE id=?', { chosen.id })
            if drawId then MySQL.update.await('DELETE FROM cookie_kuji_draw WHERE id=?', { drawId }) end
            refundTickets = refundTickets + 1
            errors[#errors+1] = tostring(err or '보상 지급 오류')
        else
            results[#results+1] = {
                grade = chosen.grade,
                label = chosen.label,
                rewardType = chosen.reward_type,
                amount = tonumber(chosen.amount) or 1,
                image = chosen.image or '',
                permanent = permanentTypes[tostring(chosen.reward_type or ''):lower()] == true,
            }
        end
    end

    if refundTickets > 0 then
        pcall(function() exports.ox_inventory:AddItem(src, cfg.ticketItem, refundTickets, { source='쿠지 실패 환불' }) end)
    end

    invalidate()
    local state = publicState(src, true)

    if #results == 0 then
        TriggerClientEvent('cookie_kuji:client:result', src, {
            ok=false,
            message=('뽑기에 실패했습니다. 티켓 %d장을 돌려드렸습니다.%s'):format(refundTickets, #errors>0 and ('\n'..table.concat(errors, '\n')) or ''),
            state=state,
            results={},
        })
        finish(); return
    end

    TriggerClientEvent('cookie_kuji:client:result', src, {
        ok=true,
        count=#results,
        requested=count,
        refunded=refundTickets,
        results=results,
        prize=(#results == 1) and results[1] or nil,
        message=(refundTickets > 0) and (('일부 실패로 티켓 %d장을 환불했습니다.'):format(refundTickets)) or nil,
        state=state,
    })
    finish()
end)

AddEventHandler('playerDropped', function() drawLocks[source] = nil end)

-- ===== 관리자 API (cookie_admin에서 호출) =====
local function adminData()
    local s = publicState(0, false)
    s.tickets = nil
    s.history = nil
    return s
end

exports('GetAdminData', function()
    return adminData()
end)

exports('SaveAdminData', function(payload)
    payload = type(payload) == 'table' and payload or {}
    local cfg = loadSettings(true)
    if not cfg then return false, '설정을 불러올 수 없습니다.' end

    local title = trim(payload.title, 80)
    if title == '' then title = cfg.title end
    local ticketItem = trim(payload.ticketItem, 80)
    if ticketItem == '' then return false, '티켓 아이템명을 입력하세요.' end

    local b = type(payload.beacon) == 'table' and payload.beacon or cfg.beacon
    local c = type(payload.beaconColor) == 'table' and payload.beaconColor or cfg.beaconColor
    MySQL.update.await([[
        UPDATE cookie_kuji_config SET enabled=?,title=?,ticket_item=?,
          beacon_x=?,beacon_y=?,beacon_z=?,beacon_r=?,beacon_g=?,beacon_b=?,beacon_a=? WHERE id=1
    ]], {
        boolInt(payload.enabled), title, ticketItem,
        tonumber(b.x) or cfg.beacon.x, tonumber(b.y) or cfg.beacon.y, tonumber(b.z) or cfg.beacon.z,
        clampInt(c.r,0,255,cfg.beaconColor.r), clampInt(c.g,0,255,cfg.beaconColor.g),
        clampInt(c.b,0,255,cfg.beaconColor.b), clampInt(c.a,20,255,cfg.beaconColor.a)
    })

    local keep = {}
    local rows = type(payload.prizes) == 'table' and payload.prizes or {}
    if #rows < 1 then return false, '경품을 1개 이상 추가하세요.' end

    -- 새 행을 조용히 버리지 않는다. 하나라도 미완성이면 저장 자체를 중단한다.
    for i, p in ipairs(rows) do
        local label = trim(p.label, 100)
        local rtype = trim(p.rewardType, 24):lower()
        local key = trim(p.rewardKey, 100)
        if label == '' then return false, ('%d번째 경품 이름을 입력하세요.'):format(i) end
        if rtype == '' then return false, ('%d번째 경품 타입을 선택하세요.'):format(i) end
        if key == '' then return false, ('%d번째 경품 키/코드를 입력하세요.'):format(i) end
    end

    for i, p in ipairs(rows) do
        local id = tonumber(p.id)
        local grade = trim(p.grade, 12); if grade == '' then grade = 'C' end
        local label = trim(p.label, 100)
        local rtype = trim(p.rewardType, 24):lower()
        local key = trim(p.rewardKey, 100)
        local amount = clampInt(p.amount,1,1000000000,1)
        local stock = clampInt(p.stock,1,100000,1)
        local image = trim(p.image,500)
        local sortOrder = clampInt(p.sortOrder,-100000,100000,i*10)
        do
            if id then
                local old = MySQL.single.await('SELECT stock_total,stock_remaining FROM cookie_kuji_prize WHERE id=? AND season_month=?', { id, cfg.seasonMonth })
                if old then
                    local drawn = math.max(0, (tonumber(old.stock_total) or 0) - (tonumber(old.stock_remaining) or 0))
                    local remain = math.max(0, stock - drawn)
                    MySQL.update.await([[
                        UPDATE cookie_kuji_prize SET grade=?,label=?,reward_type=?,reward_key=?,amount=?,stock_total=?,stock_remaining=?,image=?,sort_order=?
                        WHERE id=? AND season_month=?
                    ]], { grade,label,rtype,key,amount,stock,remain,image,sortOrder,id,cfg.seasonMonth })
                    keep[id] = true
                end
            else
                local newId = MySQL.insert.await([[
                    INSERT INTO cookie_kuji_prize
                      (season_month,grade,label,reward_type,reward_key,amount,stock_total,stock_remaining,image,sort_order)
                    VALUES (?,?,?,?,?,?,?,?,?,?)
                ]], { cfg.seasonMonth,grade,label,rtype,key,amount,stock,stock,image,sortOrder })
                if newId then keep[tonumber(newId)] = true end
            end
        end
    end

    local existing = MySQL.query.await('SELECT id FROM cookie_kuji_prize WHERE season_month=?', { cfg.seasonMonth }) or {}
    for _, r in ipairs(existing) do
        local id = tonumber(r.id)
        if id and not keep[id] then
            MySQL.update.await('DELETE FROM cookie_kuji_prize WHERE id=? AND season_month=?', { id, cfg.seasonMonth })
        end
    end

    invalidate()
    TriggerClientEvent('cookie_kuji:client:settingsChanged', -1, publicState(0, false))
    return true, '저장했습니다.'
end)

-- F3 게임내 설치 모드에서 쿠지 비콘 좌표를 직접 생성/이동한다.
exports('SetBeacon', function(coords)
    if type(coords) ~= 'table' then return false, '좌표가 올바르지 않습니다.' end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return false, '좌표가 올바르지 않습니다.' end

    MySQL.update.await([[
        UPDATE cookie_kuji_config
        SET enabled=1, beacon_x=?, beacon_y=?, beacon_z=?
        WHERE id=1
    ]], { x, y, z })

    invalidate()
    local pushed = publicState(0, false)
    TriggerClientEvent('cookie_kuji:client:settingsChanged', -1, pushed)
    TriggerClientEvent('cookie_kuji:client:forceBeacon', -1, { x=x, y=y, z=z }, pushed.beaconColor, pushed.title)
    return true, ('쿠지 비콘을 설치했습니다. (%.2f, %.2f, %.2f)'):format(x, y, z)
end)

exports('ResetStock', function()
    local cfg = loadSettings(true)
    if not cfg then return false, '설정 오류' end
    MySQL.update.await('UPDATE cookie_kuji_prize SET stock_remaining=stock_total WHERE season_month=?', { cfg.seasonMonth })
    invalidate()
    TriggerClientEvent('cookie_kuji:client:settingsChanged', -1, publicState(0, false))
    return true, '현재 월 경품 재고를 초기화했습니다.'
end)

exports('StartMonth', function(payload)
    payload = type(payload) == 'table' and payload or {}
    local month = trim(payload.seasonMonth, 7)
    if not month:match('^%d%d%d%d%-%d%d$') then return false, '월은 YYYY-MM 형식이어야 합니다.' end
    local cfg = loadSettings(true)
    local title = trim(payload.title,80); if title == '' then title = cfg.title end

    -- 화면에 편집 중인 경품 구성을 새 월의 풀로 복제한다.
    local rows = type(payload.prizes) == 'table' and payload.prizes or {}
    if #rows == 0 then return false, '경품을 1개 이상 설정하세요.' end

    MySQL.update.await('UPDATE cookie_kuji_config SET season_month=?,title=? WHERE id=1', { month, title })
    MySQL.update.await('DELETE FROM cookie_kuji_prize WHERE season_month=?', { month })
    for i, p in ipairs(rows) do
        local grade = trim(p.grade,12); if grade == '' then grade='C' end
        local label = trim(p.label,100)
        local rtype = trim(p.rewardType,24):lower()
        local key = trim(p.rewardKey,100)
        local amount = clampInt(p.amount,1,1000000000,1)
        local stock = clampInt(p.stock,1,100000,1)
        if label ~= '' and rtype ~= '' and key ~= '' then
            MySQL.insert.await([[
                INSERT INTO cookie_kuji_prize
                  (season_month,grade,label,reward_type,reward_key,amount,stock_total,stock_remaining,image,sort_order)
                VALUES (?,?,?,?,?,?,?,?,?,?)
            ]], { month,grade,label,rtype,key,amount,stock,stock,trim(p.image,500),clampInt(p.sortOrder,-100000,100000,i*10) })
        end
    end
    invalidate()
    TriggerClientEvent('cookie_kuji:client:settingsChanged', -1, publicState(0, false))
    return true, month .. ' 쿠지를 시작했습니다.'
end)

-- 출석/이벤트 등 다른 리소스에서 사용할 수 있는 티켓 지급 export.
exports('GiveTickets', function(src, count, reason)
    local cfg = loadSettings(false)
    count = clampInt(count,1,1000,1)
    local ok, ret = pcall(function()
        return exports.ox_inventory:AddItem(src, cfg.ticketItem, count, { source = trim(reason,80) })
    end)
    return ok and ret == true
end)

exports('GetOwnedRewards', function(citizenid)
    return MySQL.query.await([[
        SELECT id,reward_type,reward_key,label,state,metadata_json,created_at
        FROM cookie_kuji_owned WHERE citizenid=? ORDER BY id DESC
    ]], { tostring(citizenid or '') }) or {}
end)

CreateThread(function()
    createTables()
    invalidate()
    print('^2[cookie_kuji]^7 V1.4.0 loaded - admin prize editor + 1/5/10 draws')
end)
