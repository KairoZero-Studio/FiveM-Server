-- COOKIE LIMITED/PACKED INVENTORY + VEHICLE PACKING V2.0.0
-- 핵심 규칙:
-- 1) 개인 소유 차량은 월드 출고 상태에서만 포장 가능
-- 2) 포장 상태 차량만 시민 간 거래 가능 (cookie_interaction에서 강제)
-- 3) 차량 고유 UID(cookie_asset_uid/asset_uid)는 포장/거래/해제 후에도 유지
-- 4) DB 작업 실패 시 가능한 범위에서 자동 롤백 + cookie_recovery_log 기록

local PERSONAL_GARAGE = 'cookie_personal_v2'
local packLocks = {}
local unpackLocks = {}

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

local function notifyLimited(src, message, isWarn)
    TriggerClientEvent('cookie_admin:client:notify', src, message, isWarn == true)
end

local function currentPlayer(src)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return ok and p or nil
end

local function currentCitizenIdLimited(src)
    local p = currentPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function decodeMetaLimited(raw)
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, data = pcall(json.decode, raw)
    return ok and type(data) == 'table' and data or {}
end

local function stripPrefixOwned(v)
    v = tostring(v or '')
    local n = v:match('^packed:(%d+)$') or v:match('^(%d+)$')
    return tonumber(n)
end

local function trim(v)
    return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normPlate(v)
    return trim(v):upper():gsub('%s+', '')
end

local function normModel(v)
    return tostring(v or ''):lower():gsub('%s+', '')
end

local function safeScalar(sql, params)
    local ok, value = pcall(function() return MySQL.scalar.await(sql, params or {}) end)
    return ok and value or nil
end

local function safeSingle(sql, params)
    local ok, value = pcall(function() return MySQL.single.await(sql, params or {}) end)
    return ok and value or nil
end

local function safeUpdate(sql, params)
    local ok, value = pcall(function() return MySQL.update.await(sql, params or {}) end)
    return ok and tonumber(value or 0) or 0
end

local function recovery(category, cid, uid, payload)
    pcall(function()
        MySQL.insert.await(
            'INSERT INTO cookie_recovery_log(category,citizenid,asset_uid,payload_json) VALUES (?,?,?,?)',
            { category, cid, uid, json.encode(payload or {}) }
        )
    end)
end

local function restorePlayerVehicleExact(row)
    if type(row) ~= 'table' then return false end
    local ok, restored = pcall(function()
        local cols = MySQL.query.await('SHOW COLUMNS FROM player_vehicles') or {}
        local allowed = {}; for _, c in ipairs(cols) do allowed[c.Field] = true end
        local names, values, marks = {}, {}, {}
        for k, v in pairs(row) do
            if allowed[k] and v ~= nil then
                names[#names+1] = '`' .. k .. '`'; values[#values+1] = v; marks[#marks+1] = '?'
            end
        end
        if #names == 0 then return false end
        local sql = ('INSERT INTO player_vehicles (%s) VALUES (%s)'):format(table.concat(names, ','), table.concat(marks, ','))
        return MySQL.insert.await(sql, values) ~= nil
    end)
    return ok and restored == true
end

local function schemaColumnExists(tableName, columnName)
    local row = MySQL.single.await([[
        SELECT 1 AS x FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
        LIMIT 1
    ]], { tableName, columnName })
    return row ~= nil
end

local function schemaIndexExists(tableName, indexName)
    local row = MySQL.single.await([[
        SELECT 1 AS x FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
        LIMIT 1
    ]], { tableName, indexName })
    return row ~= nil
end

local function ensureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_recovery_log (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      category VARCHAR(50) NOT NULL,
      citizenid VARCHAR(64) NULL,
      asset_uid VARCHAR(40) NULL,
      payload_json LONGTEXT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_cookie_recovery_asset(asset_uid),
      INDEX idx_cookie_recovery_cid(citizenid,created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    if not schemaColumnExists('player_vehicles', 'cookie_asset_uid') then
        MySQL.query.await('ALTER TABLE player_vehicles ADD COLUMN cookie_asset_uid VARCHAR(40) NULL')
    end
    if not schemaColumnExists('cookie_kuji_owned', 'asset_uid') then
        MySQL.query.await('ALTER TABLE cookie_kuji_owned ADD COLUMN asset_uid VARCHAR(40) NULL')
    end
    if not schemaIndexExists('cookie_kuji_owned', 'idx_cookie_kuji_owned_asset_uid') then
        MySQL.query.await('CREATE INDEX IF NOT EXISTS idx_cookie_kuji_owned_asset_uid ON cookie_kuji_owned(asset_uid)')
    end
    if not schemaIndexExists('player_vehicles', 'uq_player_vehicle_cookie_asset_uid') then
        MySQL.query.await('CREATE UNIQUE INDEX IF NOT EXISTS uq_player_vehicle_cookie_asset_uid ON player_vehicles(cookie_asset_uid)')
    end
end

local function uidCollision(uid, ignoreVehicleId, ignoreOwnedId)
    uid = trim(uid)
    if uid == '' then return true end

    local pv = safeSingle([[
        SELECT id FROM player_vehicles
        WHERE cookie_asset_uid=? AND (? IS NULL OR id<>?)
        LIMIT 1
    ]], { uid, ignoreVehicleId, ignoreVehicleId })
    if pv then return true, 'garage', pv.id end

    local po = safeSingle([[
        SELECT id FROM cookie_kuji_owned
        WHERE asset_uid=? AND reward_type='vehicle' AND state='packed'
          AND (? IS NULL OR id<>?)
        LIMIT 1
    ]], { uid, ignoreOwnedId, ignoreOwnedId })
    if po then return true, 'packed', po.id end

    return false
end

local function newAssetUid(seed)
    seed = math.max(0, math.floor(tonumber(seed) or 0))
    for _ = 1, 30 do
        local uid = ('CV-%s-%07d-%06d'):format(
            os.date('%Y%m%d'),
            seed % 10000000,
            math.random(0, 999999)
        )
        if not uidCollision(uid) then return uid end
    end
    return nil
end

local function ensureAssetUid(veh)
    if type(veh) ~= 'table' or not tonumber(veh.id) then return nil, 'vehicle' end
    local existing = trim(veh.cookie_asset_uid)

    if existing ~= '' then
        local collision, where, otherId = uidCollision(existing, tonumber(veh.id), nil)
        if collision then
            recovery('vehicle_uid_collision', veh.citizenid, existing, {
                vehicleId = veh.id,
                collision = where,
                otherId = otherId,
                plate = veh.plate,
                model = veh.vehicle,
            })
            return nil, 'duplicate'
        end
        return existing
    end

    for _ = 1, 10 do
        local uid = newAssetUid(veh.id)
        if not uid then break end
        local changed = safeUpdate([[
            UPDATE player_vehicles
            SET cookie_asset_uid=?
            WHERE id=? AND (cookie_asset_uid IS NULL OR cookie_asset_uid='')
        ]], { uid, veh.id })
        if changed > 0 then
            veh.cookie_asset_uid = uid
            return uid
        end

        local row = safeSingle('SELECT cookie_asset_uid FROM player_vehicles WHERE id=? LIMIT 1', { veh.id })
        if row and trim(row.cookie_asset_uid) ~= '' then
            veh.cookie_asset_uid = row.cookie_asset_uid
            return ensureAssetUid(veh)
        end
    end
    return nil, 'generate'
end

local function backfillAssetUids()
    -- 기존 차고 차량에 고유 UID 부여. 여러 프레임에 나눠 처리해 서버 시작 부하를 줄인다.
    for _ = 1, 100 do
        local rows = MySQL.query.await([[
            SELECT id,citizenid,vehicle,plate,cookie_asset_uid
            FROM player_vehicles
            WHERE cookie_asset_uid IS NULL OR cookie_asset_uid=''
            ORDER BY id ASC LIMIT 150
        ]]) or {}
        if #rows == 0 then break end
        for _, row in ipairs(rows) do
            local uid = ensureAssetUid(row)
            if not uid then
                recovery('vehicle_uid_backfill_failed', row.citizenid, nil, row)
            end
        end
        Wait(0)
    end

    -- 예전 포장 차량에 UID가 없는 경우 보충한다.
    local packed = MySQL.query.await([[
        SELECT id,citizenid,reward_key,metadata_json,asset_uid
        FROM cookie_kuji_owned
        WHERE reward_type='vehicle' AND state='packed'
          AND (asset_uid IS NULL OR asset_uid='')
        ORDER BY id ASC LIMIT 2000
    ]]) or {}

    for _, row in ipairs(packed) do
        local meta = decodeMetaLimited(row.metadata_json)
        local uid = trim(meta.asset_uid)
        if uid == '' or uidCollision(uid, nil, row.id) then
            uid = newAssetUid(row.id)
        end
        if uid then
            meta.asset_uid = uid
            meta.model = meta.model or row.reward_key
            meta.packaged_vehicle = true
            safeUpdate([[
                UPDATE cookie_kuji_owned SET asset_uid=?, metadata_json=?
                WHERE id=? AND reward_type='vehicle' AND state='packed'
            ]], { uid, json.encode(meta), row.id })
        else
            recovery('packed_uid_backfill_failed', row.citizenid, nil, row)
        end
    end

    -- unique index는 백필 후 한 번만 생성한다. 이미 존재하면 정상 상태로 간주한다.
    if not schemaIndexExists('cookie_kuji_owned', 'uq_cookie_kuji_owned_asset_uid') then
        local ok, err = pcall(function()
            MySQL.query.await('CREATE UNIQUE INDEX IF NOT EXISTS uq_cookie_kuji_owned_asset_uid ON cookie_kuji_owned(asset_uid)')
        end)
        if not ok then
            -- 실제 UID 중복 등으로 인덱스를 만들 수 없는 경우에만 경고한다.
            print(('^3[cookie_admin]^7 packed vehicle UID unique index warning: %s'):format(tostring(err)))
        end
    end

    local dup = MySQL.query.await([[
        SELECT uid,COUNT(*) AS cnt FROM (
            SELECT cookie_asset_uid AS uid FROM player_vehicles WHERE cookie_asset_uid IS NOT NULL AND cookie_asset_uid<>''
            UNION ALL
            SELECT asset_uid AS uid FROM cookie_kuji_owned WHERE reward_type='vehicle' AND state='packed' AND asset_uid IS NOT NULL AND asset_uid<>''
        ) x GROUP BY uid HAVING COUNT(*)>1 LIMIT 50
    ]]) or {}
    for _, r in ipairs(dup) do
        recovery('vehicle_uid_duplicate_audit', nil, r.uid, { count = tonumber(r.cnt) or 0 })
        print(('^1[cookie_admin]^7 VEHICLE UID DUPLICATE: %s x%s'):format(tostring(r.uid), tostring(r.cnt)))
    end
end

CreateThread(function()
    Wait(1200)
    ensureSchema()
    local ok, err = pcall(backfillAssetUids)
    if not ok then
        print(('^3[cookie_admin]^7 vehicle UID migration warning: %s'):format(tostring(err)))
    end
    -- 신규 DB에서 cookie_kuji가 뒤늦게 테이블을 만든 경우를 위한 1회 재시도.
    Wait(9000)
    ensureSchema()
    local ok2, err2 = pcall(backfillAssetUids)
    if not ok2 then
        print(('^3[cookie_admin]^7 vehicle UID migration retry warning: %s'):format(tostring(err2)))
    end
end)

local function fetchOwnedSkinById(citizenid, ownedId)
    return MySQL.single.await([[
        SELECT id,reward_key,label,metadata_json,state
        FROM cookie_kuji_owned
        WHERE id=? AND citizenid=? AND reward_type='skin'
        LIMIT 1
    ]], { ownedId, citizenid })
end

RegisterNetEvent('cookie_admin:server:equipLimitedSkin', function(rawOwnedId)
    local src = source
    if not cookieAllowAction(src, 'skin_equip', 800, 1) then return end
    local citizenid = currentCitizenIdLimited(src)
    local ownedId = stripPrefixOwned(rawOwnedId)
    if not citizenid or not ownedId then return end

    local row = fetchOwnedSkinById(citizenid, ownedId)
    if not row then return notifyLimited(src, '해당 스킨을 찾을 수 없습니다.', true) end

    local meta = decodeMetaLimited(row.metadata_json)
    local model = tostring(meta.model_name or meta.model or row.reward_key or '')
    if model == '' then return notifyLimited(src, '스킨 모델 정보가 없습니다.', true) end

    local ok = MySQL.transaction.await({
        { query = [[UPDATE cookie_kuji_owned SET state='packed' WHERE citizenid=? AND reward_type='skin' AND state='equipped']], values = { citizenid } },
        { query = [[UPDATE cookie_kuji_owned SET state='equipped' WHERE id=? AND citizenid=? AND reward_type='skin']], values = { ownedId, citizenid } },
    })
    if not ok then return notifyLimited(src, '스킨 상태 저장에 실패했습니다.', true) end

    TriggerClientEvent('cookie_admin:client:applySkin', src, model)
    notifyLimited(src, ('%s 장착 완료'):format(tostring(row.label or model)), false)
    TriggerClientEvent('cookie_admin:client:personalStorage', src, CookieBuildPersonalStorage(src))
end)

RegisterNetEvent('cookie_admin:server:useSkinPackKit', function()
    local src = source
    if not cookieAllowAction(src, 'skin_pack', 1200, 1) then return end
    local citizenid = currentCitizenIdLimited(src)
    if not citizenid then return end

    local equipped = MySQL.single.await([[
        SELECT id,label FROM cookie_kuji_owned
        WHERE citizenid=? AND reward_type='skin' AND state='equipped'
        ORDER BY id DESC LIMIT 1
    ]], { citizenid })
    if not equipped then return notifyLimited(src, '현재 장착 중인 한정 스킨이 없습니다.', true) end

    local removed = GetResourceState('ox_inventory') == 'started'
        and exports.ox_inventory:RemoveItem(src, 'skin_packkit', 1) == true
    if not removed then return notifyLimited(src, '스킨 포장키트가 필요합니다.', true) end

    local changed = safeUpdate([[
        UPDATE cookie_kuji_owned SET state='packed'
        WHERE id=? AND citizenid=? AND reward_type='skin' AND state='equipped'
    ]], { equipped.id, citizenid })
    if changed < 1 then
        pcall(function() exports.ox_inventory:AddItem(src, 'skin_packkit', 1) end)
        return notifyLimited(src, '스킨 포장 상태 저장에 실패했습니다.', true)
    end

    TriggerClientEvent('cookie_admin:client:restoreSkinNow', src)
    notifyLimited(src, ('%s 스킨을 보관함으로 되돌렸습니다.'):format(tostring(equipped.label or '한정 스킨')), false)
    TriggerClientEvent('cookie_admin:client:personalStorage', src, CookieBuildPersonalStorage(src))
end)

local function getVehicleByPlate(citizenid, plate)
    local p = normPlate(plate)
    if p == '' then return nil end
    return MySQL.single.await([[
        SELECT * FROM player_vehicles
        WHERE citizenid=? AND REPLACE(UPPER(plate),' ','')=?
        ORDER BY id DESC LIMIT 1
    ]], { citizenid, p })
end

local function vehicleCatalogInfo(model)
    model = normModel(model)
    if model == '' then return nil end

    local limited = safeSingle([[
        SELECT l.label,COALESCE(i.image,'') AS image
        FROM cookie_limited_vehicles l
        LEFT JOIN cookie_vehicle_image i ON LOWER(i.model)=LOWER(l.model)
        WHERE LOWER(l.model)=? AND l.active=1 LIMIT 1
    ]], { model })
    if limited then
        return { label = limited.label or model, image = limited.image or '', limited = true }
    end

    local general = safeSingle([[
        SELECT d.display_name AS label,COALESCE(NULLIF(d.image,''),i.image,'') AS image
        FROM cookie_dealership_vehicles d
        LEFT JOIN cookie_vehicle_image i ON LOWER(i.model)=LOWER(d.model)
        WHERE LOWER(d.model)=? LIMIT 1
    ]], { model })
    if general then
        return { label = general.label or model, image = general.image or '', limited = false }
    end

    return { label = model, image = '', limited = false }
end


-- V13.9.15: 일반차량/뉴비차량은 차량 포장을 금지합니다.
-- 한정차량은 기존대로 허용하며, 과거 DB에 일반/한정이 겹친 모델은 active 한정 등록을 우선합니다.
local function qbxVehicleCategory(model)
    if GetResourceState('qbx_core') ~= 'started' then return '' end
    local ok, vehicle = pcall(function()
        return exports.qbx_core:GetVehiclesByName(model)
    end)
    if not ok or type(vehicle) ~= 'table' then return '' end
    return normModel(vehicle.category)
end

local function isNewbieVehicleModel(model)
    model = normModel(model)
    if model == '' then return false end

    -- 현재 뉴비 보상 키트에 차량으로 등록된 모델은 뉴비차량으로 취급합니다.
    local reward = safeSingle([[
        SELECT id
        FROM cookie_newbie_kit_reward
        WHERE reward_type='vehicle' AND LOWER(REPLACE(item_name,' ',''))=?
        LIMIT 1
    ]], { model })
    if reward then return true end

    -- qbx 차량 등록 category가 newbie 계열인 경우도 자동 차단합니다.
    local category = qbxVehicleCategory(model)
    return category == 'newbie'
        or category == 'newbievehicle'
        or category == 'starter'
        or category == 'startervehicle'
end

local function vehiclePackBlockedClass(model)
    model = normModel(model)
    if model == '' then return nil end

    if isNewbieVehicleModel(model) then
        return 'newbie'
    end

    -- active 한정 등록이 있으면 한정차량으로 우선 취급하여 포장 허용.
    local limited = safeSingle([[
        SELECT id
        FROM cookie_limited_vehicles
        WHERE LOWER(model)=? AND active=1
        LIMIT 1
    ]], { model })
    if limited then return nil end

    -- 시민차량 판매 테이블에 등록된 모델은 일반차량으로 취급.
    local general = safeSingle([[
        SELECT id
        FROM cookie_dealership_vehicles
        WHERE LOWER(model)=?
        LIMIT 1
    ]], { model })
    if general then return 'general' end

    local category = qbxVehicleCategory(model)
    if category == 'normal' or category == 'general' then
        return 'general'
    end

    return nil
end

local function isFactionVehicleModel(model)
    local row = safeSingle([[
        SELECT fs.id FROM cookie_faction_shop fs
        JOIN cookie_faction f ON f.id=fs.faction_id AND f.is_active=1
        WHERE LOWER(fs.model)=? AND fs.active=1 LIMIT 1
    ]], { normModel(model) })
    return row ~= nil
end

local function validateWorldVehicle(src, netId, wantedPlate)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return false, nil, '차량 네트워크 정보를 확인할 수 없습니다.' end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, nil, '현재 출고된 차량을 찾을 수 없습니다.'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, nil, '플레이어 정보를 확인할 수 없습니다.' end

    local okDist, dist = pcall(function()
        return #(GetEntityCoords(ped) - GetEntityCoords(entity))
    end)
    if not okDist or dist > 8.0 then return false, nil, '차량과 너무 멀리 떨어져 있습니다.' end

    local okSeat, driver = pcall(function() return GetPedInVehicleSeat(entity, -1) end)
    if okSeat and driver and driver ~= 0 and driver ~= ped then
        return false, nil, '운전석에서만 차량을 포장할 수 있습니다.'
    end

    local okPlate, actualPlate = pcall(function() return GetVehicleNumberPlateText(entity) end)
    if okPlate and normPlate(actualPlate) ~= '' and normPlate(actualPlate) ~= normPlate(wantedPlate) then
        return false, nil, '차량 번호판 검증에 실패했습니다.'
    end

    return true, entity
end

RegisterNetEvent('cookie_admin:server:useVehiclePackKit', function(payload)
    local src = source
    if not cookieAllowAction(src, 'vehicle_pack', 1800, 1) then return end
    if packLocks[src] then return notifyLimited(src, '차량 포장을 처리 중입니다.', true) end
    packLocks[src] = true

    local function finish()
        packLocks[src] = nil
    end

    local citizenid = currentCitizenIdLimited(src)
    if not citizenid then finish(); return end

    payload = type(payload) == 'table' and payload or {}
    local plate = trim(payload.plate)
    local netId = tonumber(payload.netId)
    if plate == '' then finish(); return notifyLimited(src, '포장할 차량 번호판을 확인할 수 없습니다.', true) end

    local veh = getVehicleByPlate(citizenid, plate)
    if not veh then finish(); return notifyLimited(src, '본인 소유 차량만 포장할 수 있습니다.', true) end

    if tonumber(veh.state) ~= 0 then
        finish(); return notifyLimited(src, '차고에서 출고한 차량에 탑승한 상태에서 포장키트를 사용하세요.', true)
    end

    local actualModel = normModel(veh.vehicle)
    if actualModel == '' then finish(); return notifyLimited(src, '차량 모델 정보를 확인할 수 없습니다.', true) end

    if isFactionVehicleModel(actualModel) then
        finish(); return notifyLimited(src, '팩션 차량은 개인 포장/거래할 수 없습니다.', true)
    end

    local blockedClass = vehiclePackBlockedClass(actualModel)
    if blockedClass == 'newbie' then
        finish(); return notifyLimited(src, '뉴비차량은 포장할 수 없습니다.', true)
    elseif blockedClass == 'general' then
        finish(); return notifyLimited(src, '일반차량은 포장할 수 없습니다.', true)
    end

    local validWorld, entity, why = validateWorldVehicle(src, netId, veh.plate or plate)
    if not validWorld then finish(); return notifyLimited(src, why or '출고 차량 검증에 실패했습니다.', true) end

    local assetUid, uidErr = ensureAssetUid(veh)
    if not assetUid then
        finish()
        return notifyLimited(src, uidErr == 'duplicate' and '차량 고유 ID 중복이 감지되어 포장을 차단했습니다. 관리자에게 문의하세요.' or '차량 고유 ID 생성에 실패했습니다.', true)
    end

    local info = vehicleCatalogInfo(actualModel)
    local removed = false
    if GetResourceState('ox_inventory') == 'started' then
        local ok, ret = pcall(function() return exports.ox_inventory:RemoveItem(src, 'vehicle_packkit', 1) end)
        removed = ok and ret == true
    end
    if not removed then finish(); return notifyLimited(src, '차량 포장키트가 필요합니다.', true) end

    local metadata = {
        asset_uid = assetUid,
        model = actualModel,
        plate = tostring(veh.plate or plate),
        garage = tostring(veh.garage or PERSONAL_GARAGE),
        state = tonumber(veh.state) or 0,
        props = veh.mods or veh.mods_json or veh.vehiclemods or nil,
        packaged_vehicle = true,
        limited = info and info.limited == true or false,
        image = info and tostring(info.image or '') or '',
        source_row = veh,
        packed_at = os.time(),
    }

    -- V13.9.14:
    -- 한 번 포장했다가 해제한 차량은 cookie_kuji_owned에 동일 asset_uid의
    -- state='unpacked' 행이 남아 있습니다. asset_uid는 UNIQUE이므로 새 INSERT를 하면
    -- 재포장 시 중복키로 실패합니다. 기존 unpacked 행이 있으면 packed로 되돌려 재사용합니다.
    local previousOwned = safeSingle([[
        SELECT id,state,citizenid
        FROM cookie_kuji_owned
        WHERE asset_uid=? AND reward_type='vehicle'
        LIMIT 1
    ]], { assetUid })

    local packOwnedQuery
    local packOwnedValues

    if previousOwned then
        if tostring(previousOwned.state or '') ~= 'unpacked' then
            finish()
            return notifyLimited(src, '이미 포장 상태인 차량입니다.', true)
        end

        packOwnedQuery = [[
            UPDATE cookie_kuji_owned
            SET citizenid=?, source_draw_id=NULL, reward_key=?, label=?,
                state='packed', metadata_json=?
            WHERE id=? AND asset_uid=? AND reward_type='vehicle' AND state='unpacked'
        ]]
        packOwnedValues = {
            citizenid,
            actualModel,
            tostring(info and info.label or actualModel),
            json.encode(metadata),
            previousOwned.id,
            assetUid,
        }
    else
        packOwnedQuery = [[
            INSERT INTO cookie_kuji_owned
                (citizenid,source_draw_id,reward_type,reward_key,label,state,metadata_json,asset_uid)
            VALUES (?,NULL,'vehicle',?,?,'packed',?,?)
        ]]
        packOwnedValues = {
            citizenid,
            actualModel,
            tostring(info and info.label or actualModel),
            json.encode(metadata),
            assetUid,
        }
    end

    local txOk, txResult = pcall(function()
        return MySQL.transaction.await({
            {
                query = packOwnedQuery,
                values = packOwnedValues,
            },
            {
                query = [[DELETE FROM player_vehicles WHERE id=? AND citizenid=? AND state=0]],
                values = { veh.id, citizenid }
            }
        })
    end)

    if not txOk or txResult ~= true then
        pcall(function() exports.ox_inventory:AddItem(src, 'vehicle_packkit', 1) end)
        recovery('vehicle_pack_transaction_failed', citizenid, assetUid, { vehicle = veh, error = tostring(txResult) })
        finish()
        return notifyLimited(src, '차량 포장 저장에 실패해 포장키트를 돌려드렸습니다.', true)
    end

    local packed = safeSingle([[
        SELECT id,state FROM cookie_kuji_owned
        WHERE citizenid=? AND reward_type='vehicle' AND state='packed' AND asset_uid=? LIMIT 1
    ]], { citizenid, assetUid })
    local stillOriginal = safeSingle('SELECT id FROM player_vehicles WHERE id=? LIMIT 1', { veh.id })
    if not packed or stillOriginal then
        -- 트랜잭션 호출 자체가 true를 반환해도 조건부 DELETE/UPDATE가 0행일 수 있다.
        -- 그래서 최종 상태를 다시 읽고, 중간 상태가 남으면 안전한 쪽(원본 차량 유지)으로 되돌린다.
        local restoredOriginal = stillOriginal ~= nil
        if stillOriginal and packed then
            safeUpdate([[DELETE FROM cookie_kuji_owned
                         WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed' AND asset_uid=?]],
                       { packed.id, citizenid, assetUid })
        elseif not packed and not stillOriginal then
            restoredOriginal = restorePlayerVehicleExact(veh)
        end
        -- 성공 상태(packed 있음 + original 없음)가 아닌 모든 경우 포장키트는 소모시키지 않는다.
        pcall(function() exports.ox_inventory:AddItem(src, 'vehicle_packkit', 1) end)
        recovery('vehicle_pack_postcheck_failed', citizenid, assetUid, {
            vehicle = veh,
            packed = packed,
            original = stillOriginal,
            restoredOriginal = restoredOriginal,
            restoredKit = true,
        })
        finish()
        return notifyLimited(src, restoredOriginal
            and '차량 포장 무결성 검사에 실패해 원본 차량/포장키트를 자동 복구했습니다.'
            or '차량 포장 복구에 실패했습니다. 복구 로그를 확인해주세요.', true)
    end

    TriggerClientEvent('cookie_admin:client:deletePackVehicle', src, netId or 0, tostring(veh.plate or plate))
    -- 클라이언트 삭제 실패 대비 서버에서 한 번 더 정리한다.
    SetTimeout(1200, function()
        pcall(function()
            if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
        end)
    end)

    notifyLimited(src, ('%s 차량을 포장했습니다. 포장 상태에서만 거래할 수 있습니다.'):format(tostring(info and info.label or actualModel)), false)
    TriggerClientEvent('cookie_admin:client:personalStorage', src, CookieBuildPersonalStorage(src))
    finish()
end)

local function playerVehicleColumns()
    local cols = MySQL.query.await('SHOW COLUMNS FROM player_vehicles') or {}
    local allowed = {}
    for _, c in ipairs(cols) do allowed[c.Field] = true end
    return allowed
end

local function insertSourceRowTransaction(row, sourceRow, uid, citizenid)
    local allowed = playerVehicleColumns()
    sourceRow = type(sourceRow) == 'table' and sourceRow or {}
    sourceRow.id = nil
    sourceRow.citizenid = citizenid
    sourceRow.garage = PERSONAL_GARAGE
    sourceRow.state = 1
    sourceRow.cookie_asset_uid = uid

    local names, vals, qs = {}, {}, {}
    for k, v in pairs(sourceRow) do
        if allowed[k] and k ~= 'id' then
            names[#names+1] = '`' .. k .. '`'
            vals[#vals+1] = v
            qs[#qs+1] = '?'
        end
    end
    if #names == 0 or not sourceRow.vehicle then return false, 'source' end

    local insertSql = ('INSERT INTO player_vehicles (%s) VALUES (%s)'):format(table.concat(names, ','), table.concat(qs, ','))
    local ok, result = pcall(function()
        return MySQL.transaction.await({
            { query = insertSql, values = vals },
            {
                query = [[UPDATE cookie_kuji_owned SET state='unpacked'
                          WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed' AND asset_uid=?]],
                values = { row.id, citizenid, uid }
            }
        })
    end)
    if not ok or result ~= true then return false, result end

    -- 조건부 UPDATE가 실제로 적용됐는지 반드시 사후 검증한다.
    local restored = safeSingle([[SELECT id,citizenid,state FROM player_vehicles
                                  WHERE citizenid=? AND cookie_asset_uid=? LIMIT 1]], { citizenid, uid })
    local ownedState = safeSingle([[SELECT state FROM cookie_kuji_owned
                                    WHERE id=? AND citizenid=? AND asset_uid=? LIMIT 1]],
                                  { row.id, citizenid, uid })
    if restored and ownedState and tostring(ownedState.state) == 'unpacked' then
        return true, restored.id
    end

    -- 포장 상태 전환이 실패한 경우 새로 삽입된 차고 행만 제거해서 복제 상태를 남기지 않는다.
    if restored then
        safeUpdate('DELETE FROM player_vehicles WHERE id=? AND citizenid=? AND cookie_asset_uid=?',
                   { restored.id, citizenid, uid })
    end
    return false, 'postcheck'
end

local function createFreshKujiVehicle(row, meta, uid, citizenid)
    if GetResourceState('qbx_vehicles') ~= 'started' then
        return false, 'qbx_vehicles가 실행 중이 아닙니다.'
    end

    local model = normModel(meta.model or row.reward_key)
    if model == '' then return false, '차량 모델 정보가 없습니다.' end

    local okCreate, vehicleId = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = citizenid,
            garage = PERSONAL_GARAGE,
        })
    end)
    if not okCreate or not vehicleId then return false, '차량 소유권 생성에 실패했습니다.' end

    local changedUid = safeUpdate([[
        UPDATE player_vehicles SET cookie_asset_uid=?, garage=?, state=1
        WHERE id=? AND citizenid=?
    ]], { uid, PERSONAL_GARAGE, vehicleId, citizenid })
    if changedUid < 1 then
        safeUpdate('DELETE FROM player_vehicles WHERE id=? AND citizenid=?', { vehicleId, citizenid })
        return false, '차량 고유 ID 저장에 실패했습니다.'
    end

    local changedOwned = safeUpdate([[
        UPDATE cookie_kuji_owned SET state='unpacked'
        WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed' AND asset_uid=?
    ]], { row.id, citizenid, uid })
    if changedOwned < 1 then
        safeUpdate('DELETE FROM player_vehicles WHERE id=? AND citizenid=?', { vehicleId, citizenid })
        return false, '포장 상태 변경에 실패해 차량 생성을 되돌렸습니다.'
    end

    return true, vehicleId
end

RegisterNetEvent('cookie_admin:server:unpackLimitedVehicle', function(rawOwnedId)
    local src = source
    if not cookieAllowAction(src, 'vehicle_unpack', 1500, 1) then return end
    local citizenid = currentCitizenIdLimited(src)
    local ownedId = stripPrefixOwned(rawOwnedId)
    if not citizenid or not ownedId then return end
    if unpackLocks[ownedId] then return notifyLimited(src, '해당 차량을 처리 중입니다.', true) end
    unpackLocks[ownedId] = src

    local function finish() unpackLocks[ownedId] = nil end

    local row = MySQL.single.await([[
        SELECT * FROM cookie_kuji_owned
        WHERE id=? AND citizenid=? AND reward_type='vehicle' AND state='packed' LIMIT 1
    ]], { ownedId, citizenid })
    if not row then finish(); return notifyLimited(src, '포장 차량을 찾을 수 없습니다.', true) end

    local meta = decodeMetaLimited(row.metadata_json)
    local uid = trim(row.asset_uid or meta.asset_uid)
    if uid == '' then
        uid = newAssetUid(row.id)
        if not uid then finish(); return notifyLimited(src, '차량 고유 ID 생성에 실패했습니다.', true) end
        meta.asset_uid = uid
        safeUpdate('UPDATE cookie_kuji_owned SET asset_uid=?,metadata_json=? WHERE id=?', { uid, json.encode(meta), row.id })
    end

    local collision, where, otherId = uidCollision(uid, nil, row.id)
    if collision then
        recovery('vehicle_unpack_uid_collision', citizenid, uid, { ownedId = row.id, collision = where, otherId = otherId })
        finish()
        return notifyLimited(src, '같은 고유 ID의 차량이 이미 존재해 포장 해제를 차단했습니다.', true)
    end

    local sourceRow = type(meta.source_row) == 'table' and meta.source_row or nil
    if sourceRow then
        local plate = trim(meta.plate or sourceRow.plate)
        if plate ~= '' then
            local dupPlate = safeSingle([[
                SELECT id FROM player_vehicles WHERE REPLACE(UPPER(plate),' ','')=? LIMIT 1
            ]], { normPlate(plate) })
            if dupPlate then
                finish(); return notifyLimited(src, '같은 번호판 차량이 이미 존재합니다. 관리자에게 문의하세요.', true)
            end
        end

        sourceRow.cookie_asset_uid = uid
        local ok, why = insertSourceRowTransaction(row, sourceRow, uid, citizenid)
        if not ok then
            recovery('vehicle_unpack_transaction_failed', citizenid, uid, { owned = row, meta = meta, error = tostring(why) })
            finish(); return notifyLimited(src, '차량 차고 등록에 실패했습니다. 포장 상태는 유지됩니다.', true)
        end
    else
        local ok, why = createFreshKujiVehicle(row, meta, uid, citizenid)
        if not ok then
            recovery('vehicle_unpack_kuji_failed', citizenid, uid, { owned = row, meta = meta, error = tostring(why) })
            finish(); return notifyLimited(src, why or '차량 차고 등록에 실패했습니다.', true)
        end
    end

    notifyLimited(src, ('%s 차량을 개인 차고에 등록했습니다.'):format(tostring(row.label or row.reward_key)), false)
    TriggerClientEvent('cookie_admin:client:personalStorage', src, CookieBuildPersonalStorage(src))
    finish()
end)

exports('EnsureVehicleAssetUid', function(vehicleId)
    vehicleId = tonumber(vehicleId)
    if not vehicleId then return nil end
    local row = safeSingle('SELECT * FROM player_vehicles WHERE id=? LIMIT 1', { vehicleId })
    if not row then return nil end
    return ensureAssetUid(row)
end)

exports('AuditVehicleAssetUid', function(uid)
    uid = trim(uid)
    if uid == '' then return { ok = false } end
    local garage = MySQL.query.await('SELECT id,citizenid,vehicle,plate,state FROM player_vehicles WHERE cookie_asset_uid=?', { uid }) or {}
    local packed = MySQL.query.await("SELECT id,citizenid,reward_key,label,state FROM cookie_kuji_owned WHERE asset_uid=? AND reward_type='vehicle'", { uid }) or {}
    return { ok = true, uid = uid, garage = garage, packed = packed }
end)

print('^2[cookie_admin]^7 VEHICLE PACK V2.0.2 GENERAL+NEWBIE BLOCK V13.9.15 ready')
