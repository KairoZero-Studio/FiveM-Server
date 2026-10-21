

local zones = nil

print('[cookie_safezone] V4.6.1 DB COLUMN COMPAT FIX loaded')

local SEED_LABEL = '필박스힐 광장 보호구역'

local function bootstrapTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_zone` (
          `id`          INT AUTO_INCREMENT PRIMARY KEY,
          `type`        VARCHAR(32)  NOT NULL,
          `shape`       VARCHAR(16)  NOT NULL,
          `center_x`    DOUBLE       NOT NULL,
          `center_y`    DOUBLE       NOT NULL,
          `center_z`    DOUBLE       NOT NULL,
          `size_length` DOUBLE       NULL,
          `size_width`  DOUBLE       NULL,
          `size_height` DOUBLE       NULL,
          `radius`      DOUBLE       NULL,
          `heading`     DOUBLE       NOT NULL DEFAULT 0,
          `label`       VARCHAR(64)  NOT NULL,
          `fishing_type` VARCHAR(16)  NULL,
          `fishing_region` VARCHAR(24) NULL,
          `poly_points` LONGTEXT NULL,
          `garage_kind` VARCHAR(16)  NULL,
          `beacon_r`    SMALLINT NULL,
          `beacon_g`    SMALLINT NULL,
          `beacon_b`    SMALLINT NULL,
          `beacon_a`    SMALLINT NULL,
          `teleport_x`  DOUBLE NULL,
          `teleport_y`  DOUBLE NULL,
          `teleport_z`  DOUBLE NULL,
          `teleport_h`  DOUBLE NULL,
          `is_active`   TINYINT(1)   NOT NULL DEFAULT 1,
          `created_by`  VARCHAR(64)  NULL,
          `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_type` (`type`),
          INDEX `idx_active` (`is_active`)
        )
    ]], {})
end

local function seedSafezone()
    local row = MySQL.single.await(
        'SELECT id FROM cookie_zone WHERE type = ? AND label = ?', { 'safezone', SEED_LABEL }
    )
    if row then return false end

    MySQL.insert.await([[
        INSERT INTO cookie_zone (type, shape, center_x, center_y, center_z,
                                 size_length, size_width, size_height, heading, label, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        'safezone', 'box',
        198.36, -929.65, 30.69,
        162.0, 92.5, 40.0,
        249.5,
        SEED_LABEL,
        'bootstrap',
    })
    return true
end


-- V13.9.6: 뉴비 업무는 '뉴비 인증' 비콘 하나로 통합한다.
-- 기존 주민번호/전화번호/운전면허 비콘은 위치 마이그레이션에만 사용하고 자동 비활성화한다.
local function seedNewbieVerifyBeacon()
    local legacy = MySQL.single.await([[
        SELECT id, shape,
               center_x AS cx, center_y AS cy, center_z AS cz,
               radius,
               size_length AS length, size_width AS width, size_height AS height,
               heading,
               beacon_r AS color_r, beacon_g AS color_g, beacon_b AS color_b, beacon_a AS color_a
        FROM cookie_zone
        WHERE type IN ('newbie_jumin','newbie_phone','newbie_license') AND is_active=1
        ORDER BY FIELD(type,'newbie_jumin','newbie_phone','newbie_license'), id
        LIMIT 1
    ]], {})

    local exists = MySQL.single.await("SELECT id FROM cookie_zone WHERE type='newbie_verify' AND is_active=1 LIMIT 1", {})
    local created = false

    if not exists and legacy then
        MySQL.insert.await([[
            INSERT INTO cookie_zone
              (type, shape, center_x, center_y, center_z,
               radius, size_length, size_width, size_height, heading, label,
               beacon_r, beacon_g, beacon_b, beacon_a, is_active, created_by)
            VALUES ('newbie_verify', ?, ?, ?, ?, ?, ?, ?, ?, ?, '뉴비 인증', ?, ?, ?, ?, 1, 'auto-migrate')
        ]], {
            legacy.shape or 'sphere',
            tonumber(legacy.cx) or 0.0,
            tonumber(legacy.cy) or 0.0,
            tonumber(legacy.cz) or 0.0,
            tonumber(legacy.radius) or 1.8,
            tonumber(legacy.length) or 1.8,
            tonumber(legacy.width) or 1.8,
            tonumber(legacy.height) or 2.5,
            tonumber(legacy.heading) or 0.0,
            tonumber(legacy.color_r) or 66,
            tonumber(legacy.color_g) or 133,
            tonumber(legacy.color_b) or 244,
            tonumber(legacy.color_a) or 130,
        })
        created = true
    end

    local disabled = MySQL.update.await([[
        UPDATE cookie_zone
        SET is_active=0
        WHERE type IN ('newbie_jumin','newbie_phone','newbie_license')
          AND is_active=1
    ]]) or 0

    return created, tonumber(disabled) or 0
end

local LEGACY_TYPE = {
    garage_lspd   = { type = 'garage',   faction = 'police' },
    garage_lssd   = { type = 'garage',   faction = 'sheriff' },
    wardrobe_lspd = { type = 'wardrobe', faction = 'police' },
    wardrobe_lssd = { type = 'wardrobe', faction = 'sheriff' },
    duty_lspd     = { type = 'duty',     faction = 'police' },
    armory_lspd   = { type = 'armory',   faction = 'police' },
}

local FACTION_TYPE = {
    duty = true, armory = true, garage = true, wardrobe = true,
}

local function migBoot(...)  end

local function migrateFactionColumn()
    MySQL.query.await(
        'ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `fishing_type` VARCHAR(16) NULL', {}
    )
    MySQL.query.await(
        'ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `fishing_region` VARCHAR(24) NULL', {}
    )
    local polyCol = MySQL.single.await([[
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cookie_zone' AND COLUMN_NAME = 'poly_points'
        LIMIT 1
    ]], {})
    if not polyCol then
        MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN `poly_points` LONGTEXT NULL', {})
    end
    MySQL.query.await(
        'ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `faction_id` INT NULL', {}
    )
    MySQL.query.await(
        'ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `garage_kind` VARCHAR(16) NULL', {}
    )
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_r` SMALLINT NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_g` SMALLINT NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_b` SMALLINT NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_a` SMALLINT NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_x` DOUBLE NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_y` DOUBLE NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_z` DOUBLE NULL', {})
    MySQL.query.await('ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_h` DOUBLE NULL', {})
    MySQL.query.await(
        'ALTER TABLE `cookie_zone` ADD INDEX IF NOT EXISTS `idx_faction` (`faction_id`)', {}
    )
    MySQL.update.await([[
        UPDATE cookie_zone SET fishing_region = CASE WHEN fishing_type='boat' THEN 'offshore' ELSE 'coast' END
        WHERE type='fishing' AND (fishing_region IS NULL OR fishing_region='')
    ]], {})

    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT id, faction_type FROM cookie_faction', {})
    end)
    if not ok or not rows then
        migBoot('^3팩션 테이블 없음 존 마이그레이션 보류(다음 부팅에 재시도)^7')
        return
    end

    local facByType = {}
    for _, f in ipairs(rows) do facByType[f.faction_type] = f.id end

    local moved = 0
    for oldType, m in pairs(LEGACY_TYPE) do
        local fid = facByType[m.faction]
        if fid then

            local n
            if m.type == 'garage' then
                n = MySQL.update.await(
                    "UPDATE cookie_zone SET type = ?, faction_id = ?, garage_kind = 'faction' WHERE type = ?",
                    { m.type, fid, oldType }
                ) or 0
            else
                n = MySQL.update.await(
                    'UPDATE cookie_zone SET type = ?, faction_id = ? WHERE type = ?',
                    { m.type, fid, oldType }
                ) or 0
            end
            if n > 0 then
                moved = moved + n
                migBoot(('%s → type=%s faction_id=%d (%d개)'):format(oldType, m.type, fid, n))
            end
        end
    end

    if moved == 0 then
        migBoot('옮길 옛 타입 없음(이미 완료)')
    end

    -- V4: 차고 종류를 존 자체에 저장한다.
    -- 기존 차고는 faction_id 유무를 기준으로 자동 마이그레이션한다.
    MySQL.update.await([[
        UPDATE cookie_zone
        SET garage_kind = 'faction'
        WHERE type = 'garage' AND faction_id IS NOT NULL
          AND (garage_kind IS NULL OR garage_kind = '' OR garage_kind NOT IN ('general','limited','faction'))
    ]], {})
    MySQL.update.await([[
        UPDATE cookie_zone
        SET garage_kind = 'general'
        WHERE type = 'garage' AND faction_id IS NULL
          AND (garage_kind IS NULL OR garage_kind = '' OR garage_kind NOT IN ('general','limited','faction'))
    ]], {})
    -- 혹시 테스트 중 garage_limited 타입을 만든 적이 있다면 정식 구조로 흡수.
    MySQL.update.await([[
        UPDATE cookie_zone SET type='garage', garage_kind='limited', faction_id=NULL
        WHERE type='garage_limited'
    ]], {})
end

local function loadZones()
    local rows = MySQL.query.await(
        'SELECT id, type, shape, center_x, center_y, center_z, size_length, size_width, size_height, radius, heading, label, faction_id, fishing_type, fishing_region, poly_points, garage_kind, beacon_r, beacon_g, beacon_b, beacon_a, teleport_x, teleport_y, teleport_z, teleport_h FROM cookie_zone WHERE is_active = 1',
        {}
    )
    local out = {}
    local byType = {}
    for _, r in ipairs(rows or {}) do
        out[#out + 1] = {
            id = r.id,
            type = r.type,
            shape = r.shape,
            cx = r.center_x, cy = r.center_y, cz = r.center_z,
            length = r.size_length, width = r.size_width, height = r.size_height,
            radius = r.radius,
            heading = r.heading,
            label = r.label,
            factionId = r.faction_id,
            fishingType = r.fishing_type,
            fishingRegion = r.fishing_region,
            polyPoints = (function()
                if not r.poly_points or r.poly_points == '' then return nil end
                local ok, pts = pcall(json.decode, r.poly_points)
                return ok and type(pts) == 'table' and pts or nil
            end)(),
            garageKind = r.garage_kind,
            beaconR = r.beacon_r, beaconG = r.beacon_g, beaconB = r.beacon_b, beaconA = r.beacon_a,
            teleportX = r.teleport_x, teleportY = r.teleport_y, teleportZ = r.teleport_z, teleportH = r.teleport_h,
        }
        byType[r.type] = (byType[r.type] or 0) + 1
    end

    local parts = {}
    for t, n in pairs(byType) do parts[#parts + 1] = ('%s=%d'):format(t, n) end

    return out
end

local function boot(...)  end

boot('server.lua 로드됨')

local bootstrapLogTable

CreateThread(function()
    local ok, err = pcall(function()
        bootstrapTable()
        bootstrapLogTable()

        migrateFactionColumn()

        local seeded = seedSafezone()
        boot(seeded and ('시드 INSERT: ' .. SEED_LABEL) or ('시드 스킵(이미 존재): ' .. SEED_LABEL))

        local newbieSeeded, legacyDisabled = seedNewbieVerifyBeacon()
        if newbieSeeded then boot('기존 뉴비 비콘 위치에 통합 뉴비 인증 비콘 자동 생성') end
        if legacyDisabled > 0 then
            boot(('중복 뉴비 발급 비콘 %d개 자동 비활성화'):format(legacyDisabled))
        end

        zones = loadZones()
        boot(('로드 완료: 존 %d개'):format(#zones))
    end)

    if not ok then
        print(('^1[cookie_safezone] 초기화 오류: %s^7'):format(tostring(err)))
        zones = {}
    end
end)

-- 서버 측 상호작용 검증 공용 함수. 클라이언트 UI가 열렸다는 사실만 믿지 않는다.
function CookieSafezoneAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

function CookieSafezonePlayerNearType(src, zoneType, margin)
    src = tonumber(src)
    zoneType = tostring(zoneType or '')
    margin = math.max(0.0, tonumber(margin) or 3.0)
    if not src or zoneType == '' then return false end
    while zones == nil do Wait(25) end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    for _, z in ipairs(zones or {}) do
        if tostring(z.type or '') == zoneType then
            local dx, dy, dz = pos.x - (tonumber(z.cx) or 0.0), pos.y - (tonumber(z.cy) or 0.0), pos.z - (tonumber(z.cz) or 0.0)
            local radius = margin + 3.0
            if z.shape == 'sphere' then
                radius = math.max(1.0, tonumber(z.radius) or 1.0) + margin
            elseif z.shape == 'box' then
                local hl = math.max(0.5, (tonumber(z.length) or 2.0) * 0.5)
                local hw = math.max(0.5, (tonumber(z.width) or 2.0) * 0.5)
                radius = math.sqrt(hl * hl + hw * hw) + margin
            elseif z.shape == 'poly' and type(z.polyPoints) == 'table' then
                local maxR = 0.0
                for _, point in ipairs(z.polyPoints) do
                    local px = tonumber(point.x or point[1])
                    local py = tonumber(point.y or point[2])
                    if px and py then
                        local rx, ry = px - (tonumber(z.cx) or 0.0), py - (tonumber(z.cy) or 0.0)
                        maxR = math.max(maxR, math.sqrt(rx * rx + ry * ry))
                    end
                end
                radius = math.max(3.0, maxR) + margin
            end
            if math.sqrt(dx * dx + dy * dy) <= radius and math.abs(dz) <= math.max(8.0, margin + 5.0) then
                return true, z
            end
        end
    end
    return false
end


-- V13.9.2: 잠수존 리소스가 좌표관리의 실제 존 데이터를 사용하도록 제공한다.
exports('GetZoneByType', function(zoneType)
    zoneType = tostring(zoneType or '')
    while zones == nil do Wait(25) end
    for _, z in ipairs(zones or {}) do
        if tostring(z.type or '') == zoneType then
            return z
        end
    end
    return nil
end)

exports('PlayerNearType', function(src, zoneType, margin)
    return CookieSafezonePlayerNearType(src, zoneType, margin)
end)

local function respondZones(src, replyEvent)
    while zones == nil do Wait(50) end
    CookieLoadFactionMap()

    -- 삭제/비활성화된 팩션을 가리키는 기존 비콘은 자동으로 공용으로 전환.
    pcall(function()
        MySQL.update.await([[
            UPDATE cookie_zone z
            LEFT JOIN cookie_faction f ON f.id = z.faction_id AND f.is_active = 1
            SET z.faction_id = NULL
            WHERE z.faction_id IS NOT NULL AND f.id IS NULL
        ]], {})
    end)
    zones = loadZones()

    TriggerClientEvent(replyEvent, src, zones, CookieFactionMap)
end

RegisterNetEvent('cookie_safezone:server:requestZones', function()
    respondZones(source, 'cookie_safezone:client:zones')
end)

RegisterNetEvent('cookie_safezone:server:requestZoneList', function()
    respondZones(source, 'cookie_safezone:client:zoneList')
end)

function bootstrapLogTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_zone_log` (
          `id`            INT AUTO_INCREMENT PRIMARY KEY,
          `actor_license` VARCHAR(255) NOT NULL,
          `actor_name`    VARCHAR(60)  NOT NULL,
          `action`        VARCHAR(16)  NOT NULL,   -- 'create' | 'delete' | 'update'
          `zone_id`       INT          NOT NULL,
          `zone_type`     VARCHAR(32)  NOT NULL,
          `zone_label`    VARCHAR(64)  NOT NULL,
          `created_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_zone` (`zone_id`),
          INDEX `idx_created` (`created_at`)
        )
    ]], {})
end

local function authorizeZoneWrite(src, what)

    local ok, res = pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    if not ok then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한 확인 실패 (cookie_admin 재시작 필요)', true)
        return nil
    end

    local level = tonumber(res) or 0
    if level < 5 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return nil
    end

    local name
    local ok2, res2 = pcall(function() return exports.cookie_admin:getAdminName(src) end)
    if ok2 then name = res2 end

    local license = GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
    return { license = license or 'unknown', name = name or GetPlayerName(src) or 'unknown' }
end

local function auditZone(actor, action, zone)
end

local VALID_TYPE = {

    safezone = true,
    charzone = true,
    mapmark = true,
    fishing = true,
    mining = true,
    afkzone = true,
    afk_enter = true,
    afk_leave = true,

    garage = true,
    wardrobe = true,
    convenience = true,
    jobshop = true,
    tuningshop = true,
    atm = true,
    duty = true,
    armory = true,
    kuji = true,
    newbie_verify = true,
    teleport = true,

    garage_lspd = true, garage_lssd = true,
    wardrobe_lspd = true, wardrobe_lssd = true,
    duty_lspd = true, armory_lspd = true,
}
local VALID_SHAPE = { box = true, sphere = true, poly = true }

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function clamp(n, lo, hi)
    if n < lo then return lo elseif n > hi then return hi end
    return n
end

local function sanitizeZone(p)
    if type(p) ~= 'table' then return nil, '입력이 올바르지 않습니다' end
    if not VALID_TYPE[p.type] then return nil, '알 수 없는 존 타입입니다' end
    if not VALID_SHAPE[p.shape] then return nil, '알 수 없는 도형입니다' end

    local label = type(p.label) == 'string' and p.label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #label == 0 then return nil, '이름을 입력하세요' end
    if #label > 64 then label = label:sub(1, 64) end

    if not (finite(p.cx) and finite(p.cy) and finite(p.cz)) then return nil, '좌표가 올바르지 않습니다' end

    local z = {
        type = p.type, shape = p.shape, label = label,
        cx = p.cx, cy = p.cy, cz = p.cz,
        heading = finite(p.heading) and (p.heading % 360) or 0.0,
    }

    if p.type == 'fishing' then
        local ft = tostring(p.fishingType or 'normal')
        if ft ~= 'normal' and ft ~= 'boat' then return nil, '낚시 유형이 올바르지 않습니다' end
        local fr = tostring(p.fishingRegion or ((ft == 'boat') and 'offshore' or 'coast'))
        local validRegion = { freshwater=true, coast=true, north=true, west=true, south=true, east=true, city=true, offshore=true }
        if not validRegion[fr] then return nil, '낚시 포인트 서식지가 올바르지 않습니다' end
        z.fishingType = ft
        z.fishingRegion = fr
    else
        z.fishingType = nil
        z.fishingRegion = nil
    end

    -- 차고는 일반 / 한정 / 팩션 3종을 명시적으로 분리한다.
    if p.type == 'garage' then
        local kind = tostring(p.garageKind or ''):lower()
        if kind == '' then
            kind = (tonumber(p.factionId) and tonumber(p.factionId) > 0) and 'faction' or 'general'
        end
        if kind ~= 'general' and kind ~= 'limited' and kind ~= 'faction' then
            return nil, '차고 종류가 올바르지 않습니다'
        end
        z.garageKind = kind
    else
        z.garageKind = nil
    end

    local fid = tonumber(p.factionId)
    if p.type == 'jobshop' then
        -- 시민직업 도구 상점은 기업/팩션 상점과 분리된 공용 비콘이다.
        z.factionId = nil
    elseif p.type == 'garage' and z.garageKind ~= 'faction' then
        -- 일반/한정 차고는 특정 팩션과 절대 묶지 않는다.
        z.factionId = nil
    elseif fid and fid > 0 then
        local exists = MySQL.single.await('SELECT id FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
        if not exists then return nil, '없는 소속입니다' end
        z.factionId = fid
    else
        z.factionId = nil
    end

    if p.type == 'garage' and z.garageKind == 'faction' and not z.factionId then
        return nil, '팩션 차고는 소속을 반드시 선택해야 합니다'
    end

    local function colorByte(v)
        v = tonumber(v)
        if not v then return nil end
        return math.floor(clamp(v, 0, 255))
    end
    z.beaconR, z.beaconG, z.beaconB, z.beaconA = colorByte(p.beaconR), colorByte(p.beaconG), colorByte(p.beaconB), colorByte(p.beaconA)
    if z.beaconR and z.beaconG and z.beaconB and not z.beaconA then z.beaconA = 130 end

    if p.type == 'teleport' then
        if not (finite(p.teleportX) and finite(p.teleportY) and finite(p.teleportZ)) then
            return nil, '텔레포트 목적지 X/Y/Z 좌표를 입력하세요'
        end
        z.teleportX = clamp(p.teleportX, -20000.0, 20000.0)
        z.teleportY = clamp(p.teleportY, -20000.0, 20000.0)
        z.teleportZ = clamp(p.teleportZ, -2000.0, 10000.0)
        z.teleportH = finite(p.teleportH) and (p.teleportH % 360.0) or 0.0
    else
        z.teleportX, z.teleportY, z.teleportZ, z.teleportH = nil, nil, nil, nil
    end

    if p.shape == 'sphere' then
        if not finite(p.radius) then return nil, '반경이 올바르지 않습니다' end
        z.radius = clamp(p.radius, 1.0, 1000.0)
    elseif p.shape == 'box' then
        if not (finite(p.length) and finite(p.width)) then return nil, '크기가 올바르지 않습니다' end
        z.length = clamp(p.length, 1.0, 1000.0)
        z.width = clamp(p.width, 1.0, 1000.0)
        z.height = finite(p.height) and clamp(p.height, 4.0, 400.0) or 40.0
    else
        -- 이동형(다각형) 범위는 보호구역/낚시 포인트/광산/잠수존에서 사용한다.
        if p.type ~= 'safezone' and p.type ~= 'fishing' and p.type ~= 'mining' and p.type ~= 'afkzone' then
            return nil, '이동형 범위는 보호구역/낚시 포인트/광산/잠수존에서만 사용할 수 있습니다'
        end
        if type(p.points) ~= 'table' or #p.points < 3 then return nil, '다각형 지점이 3개 이상 필요합니다' end
        local pts, sx, sy, sz = {}, 0.0, 0.0, 0.0
        for i, pt in ipairs(p.points) do
            local x, y, pz = tonumber(pt.x or pt[1]), tonumber(pt.y or pt[2]), tonumber(pt.z or pt[3])
            if not (finite(x) and finite(y) and finite(pz)) then return nil, ('%d번 지점 좌표가 올바르지 않습니다'):format(i) end
            x, y, pz = clamp(x,-20000.0,20000.0), clamp(y,-20000.0,20000.0), clamp(pz,-2000.0,10000.0)
            pts[#pts+1] = { x=x, y=y, z=pz }
            sx, sy, sz = sx+x, sy+y, sz+pz
        end
        z.polyPoints = pts
        z.cx, z.cy, z.cz = sx/#pts, sy/#pts, sz/#pts
        z.height = finite(p.height) and clamp(p.height, 4.0, 400.0) or 40.0
    end
    return z
end

local function rowFor(id, z)
    return {
        id = id, type = z.type, shape = z.shape, label = z.label,
        cx = z.cx, cy = z.cy, cz = z.cz,
        length = z.length, width = z.width, height = z.height,
        radius = z.radius, heading = z.heading,
        factionId = z.factionId,
        fishingType = z.fishingType,
        fishingRegion = z.fishingRegion,
        polyPoints = z.polyPoints,
        garageKind = z.garageKind,
        beaconR = z.beaconR, beaconG = z.beaconG, beaconB = z.beaconB, beaconA = z.beaconA,
        teleportX = z.teleportX, teleportY = z.teleportY, teleportZ = z.teleportZ, teleportH = z.teleportH,
    }
end

RegisterNetEvent('cookie_safezone:server:createZone', function(payload)
    local src = source
    local z, why = sanitizeZone(payload)
    if not z then
        TriggerClientEvent('cookie_admin:client:notify', src, why, true)
        return
    end

    local actor = authorizeZoneWrite(src, 'create ' .. z.label)
    if not actor then return end

    if z.type == 'afkzone' then
        local existing = MySQL.single.await("SELECT id,label FROM cookie_zone WHERE type='afkzone' AND is_active=1 LIMIT 1")
        if existing then
            TriggerClientEvent('cookie_admin:client:notify', src,
                ('잠수존 범위는 1개만 사용할 수 있습니다. 기존 "%s" 을(를) 편집하거나 삭제하세요.'):format(existing.label or ('#'..tostring(existing.id))), true)
            return
        end
    end

    local okInsert, id = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO cookie_zone (type, shape, center_x, center_y, center_z,
                                     size_length, size_width, size_height, radius, heading, label,
                                     faction_id, fishing_type, fishing_region, poly_points, garage_kind, beacon_r, beacon_g, beacon_b, beacon_a,
                                     teleport_x, teleport_y, teleport_z, teleport_h, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            z.type, z.shape, z.cx, z.cy, z.cz,
            z.length, z.width, z.height, z.radius, z.heading, z.label,
            z.factionId, z.fishingType, z.fishingRegion, z.polyPoints and json.encode(z.polyPoints) or nil, z.garageKind, z.beaconR, z.beaconG, z.beaconB, z.beaconA,
            z.teleportX, z.teleportY, z.teleportZ, z.teleportH, actor.name,
        })
    end)

    if not okInsert or not id then
        TriggerClientEvent('cookie_admin:client:notify', src, '비콘/좌표 DB 저장에 실패했습니다. 서버 콘솔을 확인하세요.', true)
        return
    end

    zones = loadZones()

    TriggerClientEvent('cookie_safezone:client:zoneAdded', -1, rowFor(id, z))
    TriggerClientEvent('cookie_admin:client:notify', src, ('존 "%s" 을(를) 생성했습니다'):format(z.label), false)
    cookieRegisterGarages()
end)

RegisterNetEvent('cookie_safezone:server:updateZone', function(zoneId, payload)
    local src = source
    local id = tonumber(zoneId)
    if not id then return end

    local z, why = sanitizeZone(payload)
    if not z then
        TriggerClientEvent('cookie_admin:client:notify', src, why, true)
        return
    end

    local actor = authorizeZoneWrite(src, 'update id=' .. id)
    if not actor then return end

    local existing = MySQL.single.await('SELECT id FROM cookie_zone WHERE id = ?', { id })
    if not existing then
        TriggerClientEvent('cookie_admin:client:notify', src, '존을 찾을 수 없습니다', true)
        return
    end

    MySQL.update.await([[
        UPDATE cookie_zone SET type = ?, shape = ?, center_x = ?, center_y = ?, center_z = ?,
               size_length = ?, size_width = ?, size_height = ?, radius = ?, heading = ?, label = ?,
               faction_id = ?, fishing_type = ?, fishing_region = ?, poly_points = ?, garage_kind = ?, beacon_r = ?, beacon_g = ?, beacon_b = ?, beacon_a = ?,
               teleport_x = ?, teleport_y = ?, teleport_z = ?, teleport_h = ?
        WHERE id = ?
    ]], {
        z.type, z.shape, z.cx, z.cy, z.cz,
        z.length, z.width, z.height, z.radius, z.heading, z.label,
        z.factionId, z.fishingType, z.fishingRegion, z.polyPoints and json.encode(z.polyPoints) or nil, z.garageKind, z.beaconR, z.beaconG, z.beaconB, z.beaconA,
        z.teleportX, z.teleportY, z.teleportZ, z.teleportH, id,
    })

    zones = loadZones()

    TriggerClientEvent('cookie_safezone:client:zoneUpdated', -1, rowFor(id, z))
    TriggerClientEvent('cookie_admin:client:notify', src, ('존 "%s" 을(를) 수정했습니다'):format(z.label), false)
    cookieRegisterGarages()
end)

RegisterNetEvent('cookie_safezone:server:updateFishingSettings', function(zoneId, fishingType, fishingRegion)
    local src = source
    local id = tonumber(zoneId)
    if not id then return end
    local actor = authorizeZoneWrite(src, 'updateFishingSettings id=' .. id)
    if not actor then return end

    local row = MySQL.single.await('SELECT id, type, label FROM cookie_zone WHERE id = ?', { id })
    if not row or row.type ~= 'fishing' then
        TriggerClientEvent('cookie_admin:client:notify', src, '낚시 포인트를 찾을 수 없습니다', true)
        return
    end

    local ft = tostring(fishingType or 'normal')
    if ft ~= 'normal' and ft ~= 'boat' then
        TriggerClientEvent('cookie_admin:client:notify', src, '낚시 유형이 올바르지 않습니다', true)
        return
    end
    local fr = tostring(fishingRegion or ((ft == 'boat') and 'offshore' or 'coast'))
    local validRegion = { freshwater=true, coast=true, north=true, west=true, south=true, east=true, city=true, offshore=true }
    if not validRegion[fr] then
        TriggerClientEvent('cookie_admin:client:notify', src, '서식지 설정이 올바르지 않습니다', true)
        return
    end

    MySQL.update.await('UPDATE cookie_zone SET fishing_type = ?, fishing_region = ? WHERE id = ?', { ft, fr, id })
    zones = loadZones()
    local updated = nil
    for _, z in ipairs(zones or {}) do if tonumber(z.id) == id then updated = z break end end
    if updated then TriggerClientEvent('cookie_safezone:client:zoneUpdated', -1, updated) end
    TriggerClientEvent('cookie_admin:client:notify', src, ('낚시 포인트 "%s" 설정을 저장했습니다'):format(row.label), false)
end)

RegisterNetEvent('cookie_safezone:server:setZoneFaction', function(zoneId, factionId)
    local src = source
    local id = tonumber(zoneId)
    if not id then return end

    local actor = authorizeZoneWrite(src, 'setFaction id=' .. id)
    if not actor then return end

    local row = MySQL.single.await('SELECT id, type, label, garage_kind FROM cookie_zone WHERE id = ?', { id })
    if not row then
        TriggerClientEvent('cookie_admin:client:notify', src, '존을 찾을 수 없습니다', true)
        return
    end

    local fid = tonumber(factionId)
    if fid and fid > 0 then
        local exists = MySQL.single.await('SELECT id FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
        if not exists then
            TriggerClientEvent('cookie_admin:client:notify', src, '없는 소속입니다', true)
            return
        end
    else
        fid = nil
    end

    if row.type == 'garage' then
        local kind = fid and 'faction' or ((row.garage_kind == 'limited') and 'limited' or 'general')
        MySQL.update.await('UPDATE cookie_zone SET faction_id = ?, garage_kind = ? WHERE id = ?', { fid, kind, id })
    else
        MySQL.update.await('UPDATE cookie_zone SET faction_id = ? WHERE id = ?', { fid, id })
    end

    zones = loadZones()
    cookieRegisterGarages()

    local fresh
    for _, z in ipairs(zones) do
        if z.id == id then fresh = z break end
    end
    if fresh then
        TriggerClientEvent('cookie_safezone:client:zoneUpdated', -1, fresh)
    end

    TriggerClientEvent('cookie_safezone:client:zoneList', src, zones, CookieFactionMap)
    TriggerClientEvent('cookie_admin:client:notify', src,
        ('존 "%s" 의 소속을 바꿨습니다'):format(row.label), false)
end)

RegisterNetEvent('cookie_safezone:server:deleteZone', function(zoneId)
    local src = source
    local id = tonumber(zoneId)
    if not id then return end

    local actor = authorizeZoneWrite(src, 'delete id=' .. id)
    if not actor then return end

    local row = MySQL.single.await('SELECT id, type, label FROM cookie_zone WHERE id = ?', { id })
    if not row then
        TriggerClientEvent('cookie_admin:client:notify', src, '이미 삭제된 존입니다', true)
        return
    end

    MySQL.query.await('DELETE FROM cookie_zone WHERE id = ?', { id })
    -- 콘텐츠별 존 설정도 함께 정리한다. 해당 테이블/리소스가 아직 없어도 존 삭제는 계속 진행.
    pcall(function() MySQL.query.await('DELETE FROM cookie_fishing_zone_fish WHERE zone_id = ?', { id }) end)
    pcall(function() MySQL.query.await('DELETE FROM cookie_mining_zone_mineral WHERE zone_id = ?', { id }) end)

    zones = loadZones()

    TriggerClientEvent('cookie_safezone:client:zoneRemoved', -1, id)
    TriggerClientEvent('cookie_admin:client:notify', src, ('존 "%s" 을(를) 삭제했습니다'):format(row.label), false)
    cookieRegisterGarages()
end)


-- ── 뉴비 발급 비콘 ─────────────────────────────────────────────
-- 진행도/교육 시스템 없이, 비콘을 누르는 순간 해당 정보만 발급한다.
local newbieUseCooldown = {}

local function newbieReady(src)
    if GetResourceState('cookie_core') ~= 'started' then
        return false, 'cookie_core가 실행 중이 아닙니다'
    end

    local ok, onboarded = pcall(function()
        return exports.cookie_core:isOnboarded(src)
    end)
    if not ok then return false, '온보딩 상태를 확인하지 못했습니다' end
    if not onboarded then return false, '먼저 최초 이용 동의와 별명 설정을 완료하세요' end
    return true
end

local function newbieThrottle(src, key)
    local now = GetGameTimer()
    local k = ('%s:%s'):format(src, key)
    local untilAt = newbieUseCooldown[k] or 0
    if now < untilAt then return false end
    newbieUseCooldown[k] = now + 1200
    return true
end

local function newbieNotify(src, msg, isError)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isError and true or false)
end

RegisterNetEvent('cookie_safezone:server:issueNewbieJumin', function()
    local src = source
    if not newbieThrottle(src, 'jumin') then return end
    local ready, why = newbieReady(src)
    if not ready then newbieNotify(src, why, true) return end

    local ok, res = pcall(function()
        return exports.cookie_core:issueNewbieJumin(src)
    end)
    if not ok or type(res) ~= 'table' or not res.ok then
        newbieNotify(src, (type(res) == 'table' and res.reason) or '주민번호 발급에 실패했습니다', true)
        return
    end

    newbieNotify(src, ('주민번호가 발급되었습니다: %s'):format(tostring(res.jumin or '-')), false)
end)

RegisterNetEvent('cookie_safezone:server:issueNewbiePhone', function()
    local src = source
    if not newbieThrottle(src, 'phone') then return end
    local ready, why = newbieReady(src)
    if not ready then newbieNotify(src, why, true) return end

    local ok, res = pcall(function()
        return exports.cookie_core:issuePhone(src)
    end)
    if not ok or type(res) ~= 'table' or not res.ok then
        newbieNotify(src, (type(res) == 'table' and res.reason) or '전화번호 발급에 실패했습니다', true)
        return
    end

    newbieNotify(src, ('전화번호가 발급되었습니다: %s'):format(tostring(res.phone or '-')), false)
end)

RegisterNetEvent('cookie_safezone:server:issueNewbieLicense', function()
    local src = source
    if not newbieThrottle(src, 'license') then return end
    local ready, why = newbieReady(src)
    if not ready then newbieNotify(src, why, true) return end

    if GetResourceState('cookie_license') ~= 'started' then
        newbieNotify(src, 'cookie_license가 실행 중이 아닙니다', true)
        return
    end

    local ok, row = pcall(function()
        local r = exports.cookie_license:IssueForSource(src)
        return r
    end)
    if not ok or type(row) ~= 'table' then
        newbieNotify(src, '운전면허 발급에 실패했습니다', true)
        return
    end

    newbieNotify(src, ('운전면허가 발급되었습니다: %s'):format(tostring(row.licenseNo or '-')), false)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local prefix = tostring(src) .. ':'
    for k in pairs(newbieUseCooldown) do
        if k:sub(1, #prefix) == prefix then newbieUseCooldown[k] = nil end
    end
end)

exports('getZones', function()
    while zones == nil do Wait(25) end
    return zones or {}
end)

local COOKIE_GARAGE_TYPES = { garage = true, garage_lspd = true }

CookieFactionMap = {}

function CookieLoadFactionMap()
    local ok, rows = pcall(function()
        return MySQL.query.await(
            'SELECT id, name, faction_key, faction_type, job_name, garage_key FROM cookie_faction WHERE is_active = 1', {}
        )
    end)
    if not ok or not rows then return end

    local map = {}
    for _, f in ipairs(rows) do

        local gkey = (f.garage_key and f.garage_key ~= '' and f.garage_key)
            or ((f.faction_type == 'police') and 'cookie_lspd')
            or ('cookie_' .. tostring(f.faction_key))

        local job = (f.job_name and f.job_name ~= '' and f.job_name) or f.faction_key

        map[tostring(f.id)] = {
            id = f.id,
            name = f.name,
            garageKey = gkey,
            jobKey = job,
        }
    end
    CookieFactionMap = map

    local n = 0
    for _ in pairs(map) do n = n + 1 end
    if n == 0 then

    else

    end
end

AddEventHandler('cookie_safezone:server:reloadFactionMap', function()
    CookieLoadFactionMap()
    pcall(function()
        MySQL.update.await([[
            UPDATE cookie_zone z
            LEFT JOIN cookie_faction f ON f.id = z.faction_id AND f.is_active = 1
            SET z.faction_id = NULL
            WHERE z.faction_id IS NOT NULL AND f.id IS NULL
        ]], {})
    end)
    zones = loadZones()
    TriggerClientEvent('cookie_safezone:client:zoneUpdated', -1, {})
end)

function cookieRegisterGarages()
    if GetResourceState('cookie_garage') == 'started' then
        TriggerEvent('cookie_garage:server:invalidateAccessPoints')
    end
end

RegisterCommand('garagediag', function(src)
    local function out(s)
        if src == 0 then  else TriggerClientEvent('chat:addMessage', src, { args = { '^5[차고진단]', s } }) end
    end

    CookieLoadFactionMap()

    out('── 등록된 팩션 ──')
    local n = 0
    for id, f in pairs(CookieFactionMap) do
        n = n + 1
        out(('  id=%d  %s  job=%s  차고=%s'):format(id, f.name, tostring(f.jobKey), tostring(f.garageKey)))
    end
    if n == 0 then out('  ^1없음 이게 원인이다. 차고가 하나도 등록되지 않는다^7') end

    out('── 차고 존 ──')
    local gz = 0
    for _, z in ipairs(zones or {}) do
        if COOKIE_GARAGE_TYPES[z.type] then
            gz = gz + 1
            out(('  #%d %s (type=%s, garageKind=%s, faction=%s)'):format(z.id, z.label, z.type, tostring(z.garageKind), tostring(z.factionId)))
        end
    end
    if gz == 0 then out('  ^1없음 차고 존이 없으면 접근점이 없어 차고가 등록되지 않는다^7') end

    out('── player_vehicles (팩션 차량) ──')
    local rows = MySQL.query.await([[
        SELECT garage, state, COUNT(*) AS cnt
        FROM player_vehicles
        WHERE citizenid LIKE 'FACTION\_%' OR citizenid = 'LSPD_FLEET'
        GROUP BY garage, state
    ]], {}) or {}
    if #rows == 0 then
        out('  ^1차량이 하나도 없다 구매/투입 기록 자체가 없다^7')
    end
    for _, r in ipairs(rows) do
        local st = (r.state == 1) and 'GARAGED(정상)' or ('^1state=' .. tostring(r.state) .. ' (밖에 있음 → 차고에 안 보인다)^7')
        out(('  차고=%s  %s  %d대'):format(tostring(r.garage), st, r.cnt))
    end
end, false)

CreateThread(function()
    -- 일반/한정 차고 조회용 테이블을 자체 보장.
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_dealership_vehicles (
              id INT AUTO_INCREMENT PRIMARY KEY,
              model VARCHAR(60) NOT NULL,
              brand VARCHAR(40) NOT NULL DEFAULT '일반',
              display_name VARCHAR(80) NOT NULL,
              price BIGINT NOT NULL DEFAULT 0,
              category VARCHAR(30) DEFAULT NULL,
              spec VARCHAR(120) DEFAULT NULL,
              image LONGTEXT DEFAULT NULL,
              sort_order INT NOT NULL DEFAULT 0,
              active TINYINT(1) NOT NULL DEFAULT 1,
              added_by VARCHAR(60) DEFAULT NULL,
              created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
              UNIQUE KEY uniq_model (model)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]], {})
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_limited_vehicles (
              id INT AUTO_INCREMENT PRIMARY KEY,
              model VARCHAR(60) NOT NULL,
              label VARCHAR(80) NOT NULL,
              active TINYINT(1) NOT NULL DEFAULT 1,
              added_by VARCHAR(60) DEFAULT NULL,
              created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
              UNIQUE KEY uniq_model (model)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]], {})
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_vehicle_image (
              model VARCHAR(60) NOT NULL PRIMARY KEY,
              image MEDIUMTEXT NOT NULL,
              updated_by VARCHAR(60) NULL,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]], {})
    end)
end)

CreateThread(function()
    while type(zones) ~= 'table' do Wait(200) end
    local tries = 0
    while GetResourceState('qbx_garages') ~= 'started' and tries < 60 do Wait(500); tries = tries + 1 end
    Wait(1000)
    cookieRegisterGarages()
end)


-- F3 > 전시 관리에 등록된 일반 차량 = 일반 차고 구매 목록
lib.callback.register('cookie_safezone:server:limitedModels', function(src)
    local rows = MySQL.query.await('SELECT model FROM cookie_limited_vehicles WHERE active = 1', {}) or {}
    local map = {}
    for _, r in ipairs(rows) do map[tostring(r.model):lower()] = true end
    return map
end)



lib.callback.register('cookie_safezone:server:generalGarageCatalog', function(src)
    -- 중요:
    -- await를 pcall/export 경계 안에서 실행하면 FiveM Lua에서 응답이 멈출 수 있다.
    -- F3 전시 관리가 저장하는 동일 테이블을 여기서 직접 읽는다.
    local rows = MySQL.query.await([[
        SELECT id, model, display_name, price, category, spec, image
        FROM cookie_dealership_vehicles
        WHERE active = 1
        ORDER BY sort_order, id
    ]], {}) or {}

    -- 차량 이미지는 별도 테이블에 저장된 것이 있으면 덮어쓴다.
    -- 이것도 pcall 없이 정상 await 경로로 처리.
    local imgs = MySQL.query.await('SELECT model, image FROM cookie_vehicle_image', {}) or {}
    local imageMap = {}
    for _, r in ipairs(imgs) do
        imageMap[tostring(r.model or ''):lower()] = r.image
    end

    for _, r in ipairs(rows) do
        local model = tostring(r.model or ''):lower()
        r.model = model
        r.image = imageMap[model] or r.image
    end

    return rows
end)

lib.callback.register('cookie_safezone:server:buyGeneralVehicle', function(src, model)
    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then return { ok = false, message = '차량 정보가 올바르지 않습니다' } end

    local row = MySQL.single.await([[
        SELECT model, display_name, price
        FROM cookie_dealership_vehicles
        WHERE model = ? AND active = 1
    ]], { model })
    if not row then return { ok = false, message = '판매 중인 일반 차량이 아닙니다' } end

    local price = math.max(0, math.floor(tonumber(row.price) or 0))
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return { ok = false, message = '플레이어 정보를 찾을 수 없습니다' } end

    local pd = player.PlayerData or {}
    local citizenid = pd.citizenid
    if not citizenid then return { ok = false, message = '캐릭터 정보를 찾을 수 없습니다' } end

    if price > 0 then
        local paid = player.Functions.RemoveMoney('bank', price, '일반 차고 차량 구매')
        if not paid then
            paid = player.Functions.RemoveMoney('cash', price, '일반 차고 차량 구매')
        end
        if not paid then return { ok = false, message = '구매할 돈이 부족합니다' } end
    end

    local okCreate, vehicleId = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = citizenid,
            garage = 'cookie_personal_v2',
        })
    end)

    if not okCreate or not vehicleId then
        if price > 0 then player.Functions.AddMoney('bank', price, '일반 차고 차량 구매 실패 환불') end
        return { ok = false, message = '차량 등록에 실패했습니다' }
    end

    return {
        ok = true,
        message = (row.display_name or model) .. ' 구매 완료',
        vehicleId = vehicleId,
    }
end)

lib.callback.register('cookie_safezone:server:vehCards', function(src, models)
    local res = { cards = {}, myGrade = -1, myRank = nil }
    if type(models) ~= 'table' or #models == 0 then return res end

    local mem
    local okM, m = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    if okM then mem = m end
    if mem then
        res.myGrade = mem.grade or 0
        res.myRank = mem.rankName
    end

    local marks = {}
    for i = 1, #models do marks[i] = '?' end
    local inClause = table.concat(marks, ',')

    local okI, imgs = pcall(function()
        return MySQL.query.await(
            ('SELECT model, image FROM cookie_vehicle_image WHERE model IN (%s)'):format(inClause), models)
    end)
    if okI and imgs then
        for _, r in ipairs(imgs) do
            res.cards[r.model] = res.cards[r.model] or {}
            res.cards[r.model].image = r.image
        end
    end

    if mem and mem.id then
        local params = { }
        for i = 1, #models do params[i] = models[i] end
        params[#params + 1] = mem.id

        local okL, rows = pcall(function()
            return MySQL.query.await(([[
                SELECT s.model, s.label, s.min_grade, r.rank_name
                FROM cookie_faction_shop s
                LEFT JOIN cookie_faction_rank r
                       ON r.faction_id = s.faction_id AND r.grade = s.min_grade
                WHERE s.model IN (%s) AND s.faction_id = ?
            ]]):format(inClause), params)
        end)
        if okL and rows then
            for _, r in ipairs(rows) do
                res.cards[r.model] = res.cards[r.model] or {}
                res.cards[r.model].label = r.label
                res.cards[r.model].minGrade = r.min_grade or 0
                res.cards[r.model].rankName = r.rank_name
            end
        end

        local okR, ranks = pcall(function()
            return MySQL.query.await(
                'SELECT grade, rank_name FROM cookie_faction_rank WHERE faction_id = ? ORDER BY grade ASC',
                { mem.id })
        end)
        if okR and ranks then
            res.ranks = {}
            for _, r in ipairs(ranks) do
                res.ranks[#res.ranks + 1] = { grade = r.grade, name = r.rank_name }
            end
        end
    end

    return res
end)

print('^2[cookie_safezone]^7 AFKZONE DRAWABLE COORD V13.9.2 ready')

print('^2[cookie_safezone]^7 NEWBIE SINGLE BEACON V13.9.6 ready')

print('^2[cookie_safezone]^7 POLY POINT LIMIT REMOVED V13.9.10 ready')
