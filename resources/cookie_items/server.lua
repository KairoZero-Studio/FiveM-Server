-- COOKIE item server effects V1.4
-- 뉴비 보상 키트 내용물은 DB(cookie_newbie_kit_reward)에서 실시간으로 읽습니다.
-- V1.4: ox_inventory 단일 아이템 기준 연동 검사 + V1.3 뉴비 키트 안정화 유지.

local KIT_ITEM = 'newbie_reward_kit'
local PERSONAL_GARAGE = 'cookie_personal_v2'

-- V1.4: COOKIE 서버팩의 정적 아이템 ID는 ox_inventory를 단일 기준으로 사용합니다.
-- shared/items.lua는 참고용이며 실제 지급/조회/사용은 모두 ox_inventory exports를 사용합니다.
local COOKIE_OX_ITEM_IDS = {
    'armor',
    'casino_chip',
    'cookie_kuji_ticket',
    'diamond_ring',
    'energy_drink',
    'fish_baeksangaeo',
    'fish_bangeo',
    'fish_bass',
    'fish_beomgorae',
    'fish_bingeo',
    'fish_bluegill',
    'fish_bukbari',
    'fish_bulgasari',
    'fish_bungeo',
    'fish_byeongeo',
    'fish_chamchi',
    'fish_chamdom',
    'fish_cheolgapsangeo',
    'fish_cheongsaechi',
    'fish_cheongsangaeo',
    'fish_daegu',
    'fish_daewanggorae',
    'fish_dageumbari',
    'fish_dalgogi',
    'fish_doldom',
    'fish_domi',
    'fish_dotdom',
    'fish_euneo',
    'fish_gaebokchi',
    'fish_galchi',
    'fish_gamseongdom',
    'fish_gasibok',
    'fish_godeungeo',
    'fish_guisangaeo',
    'fish_gwangeo',
    'fish_haepari',
    'fish_hakkkongchi',
    'fish_hwangsaechi',
    'fish_hyangyugorae',
    'fish_ilgakgorae',
    'fish_ingeo',
    'fish_jangeo',
    'fish_jeoneo',
    'fish_jjukkumi',
    'fish_jwichi',
    'fish_kraken',
    'fish_leviathan',
    'fish_mansaegi',
    'fish_mantagaori',
    'fish_megalodon',
    'fish_megi',
    'fish_michuraji',
    'fish_minkgorae',
    'fish_minyeo',
    'fish_muneo',
    'fish_nongeo',
    'fish_noraemi',
    'fish_ojingeo',
    'fish_samchi',
    'fish_sangalchi',
    'fish_sireocaenseu',
    'fish_sungeo',
    'fish_urak',
    'fish_yeoneo',
    'fishingbait',
    'fishingbait_mid',
    'fishingbait_pro',
    'fishingrod',
    'fishingrod_mid',
    'fishingrod_pro',
    'medikit',
    'mineral_amethyst',
    'mineral_bauxite',
    'mineral_coal',
    'mineral_copper',
    'mineral_diamond',
    'mineral_emerald',
    'mineral_garnet',
    'mineral_gold',
    'mineral_iron',
    'mineral_lead',
    'mineral_nickel',
    'mineral_obsidian',
    'mineral_opal',
    'mineral_quartz',
    'mineral_ruby',
    'mineral_sapphire',
    'mineral_silver',
    'mineral_tin',
    'mineral_topaz',
    'mineral_zinc',
    'mining_pickaxe_basic',
    'mining_pickaxe_expert',
    'mining_pickaxe_skilled',
    'newbie_reward_kit',
    'oxy',
    'repairkit',
    'self_regenerator',
    'skin_packkit',
    'vehicle_packkit',
}

local function auditOxItemLinks()
    if GetResourceState('ox_inventory') ~= 'started' then
        print('^1[cookie_items]^7 ox_inventory가 실행 중이 아니어서 아이템 연동 검사를 건너뜁니다.')
        return
    end

    local missing = {}
    for _, itemName in ipairs(COOKIE_OX_ITEM_IDS) do
        local ok, item = pcall(function()
            return exports.ox_inventory:Items(itemName)
        end)
        if not ok or not item then
            missing[#missing + 1] = itemName
        end
    end

    if #missing == 0 then
        print(('^2[cookie_items]^7 ox_inventory item link OK (%d items)'):format(#COOKIE_OX_ITEM_IDS))
    else
        print(('^1[cookie_items]^7 ox_inventory missing items (%d): %s'):format(
            #missing, table.concat(missing, ', ')
        ))
    end
end

local DEFAULT_REWARDS = {
    { type = 'item', itemName = 'medikit',      itemCount = 2, amount = 0,     label = '구급상자 x2' },
    { type = 'item', itemName = 'armor',        itemCount = 1, amount = 0,     label = '방탄복 x1' },
    { type = 'item', itemName = 'oxy',          itemCount = 3, amount = 0,     label = '진통제 x3' },
    { type = 'item', itemName = 'energy_drink', itemCount = 2, amount = 0,     label = '에너지 드링크 x2' },
    { type = 'bank', itemName = '',             itemCount = 0, amount = 50000, label = '정착지원금 50,000원' },
}

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function notify(src, message, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = '뉴비 보상 키트',
        description = message,
        type = kind or 'inform'
    })
end

local function normalizeVehicleModel(value)
    return tostring(value or ''):lower():gsub('%s+', '')
end

local function ensureRewardTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_newbie_kit_config (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            initialized TINYINT(1) NOT NULL DEFAULT 0,
            updated_by VARCHAR(80) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_newbie_kit_reward (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            sort_order INT UNSIGNED NOT NULL DEFAULT 0,
            reward_type VARCHAR(12) NOT NULL,
            item_name VARCHAR(80) NULL,
            item_count INT UNSIGNED NOT NULL DEFAULT 0,
            amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            display_label VARCHAR(80) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_newbie_kit_sort(sort_order, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[INSERT IGNORE INTO cookie_newbie_kit_config (id, initialized) VALUES (1, 0)]])
    local cfg = MySQL.single.await('SELECT initialized FROM cookie_newbie_kit_config WHERE id=1 LIMIT 1')
    if not cfg or tonumber(cfg.initialized) ~= 1 then
        local countRow = MySQL.single.await('SELECT COUNT(*) AS n FROM cookie_newbie_kit_reward')
        if tonumber(countRow and countRow.n or 0) == 0 then
            for i, r in ipairs(DEFAULT_REWARDS) do
                MySQL.insert.await([[
                    INSERT INTO cookie_newbie_kit_reward
                      (sort_order, reward_type, item_name, item_count, amount, display_label)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]], { i, r.type, r.itemName, r.itemCount, r.amount, r.label })
            end
        end
        MySQL.update.await('UPDATE cookie_newbie_kit_config SET initialized=1 WHERE id=1')
    end
end

local function loadRewards()
    ensureRewardTables()
    local rows = MySQL.query.await([[
        SELECT reward_type, item_name, item_count, amount, display_label
        FROM cookie_newbie_kit_reward
        ORDER BY sort_order ASC, id ASC
    ]]) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local t = tostring(row.reward_type or ''):lower()
        if t == 'item' then
            local name = tostring(row.item_name or ''):lower()
            local count = math.max(0, math.floor(tonumber(row.item_count) or 0))
            if name ~= '' and count > 0 then
                out[#out + 1] = {
                    type = 'item', itemName = name, itemCount = count, amount = 0,
                    label = tostring(row.display_label or '')
                }
            end
        elseif t == 'bank' or t == 'cash' then
            local amount = math.max(0, math.floor(tonumber(row.amount) or 0))
            if amount > 0 then
                out[#out + 1] = {
                    type = t, itemName = '', itemCount = 0, amount = amount,
                    label = tostring(row.display_label or '')
                }
            end
        elseif t == 'vehicle' then
            local model = normalizeVehicleModel(row.item_name)
            if model ~= '' then
                out[#out + 1] = {
                    type = 'vehicle', itemName = model, vehicleModel = model,
                    itemCount = 1, amount = 0,
                    label = tostring(row.display_label or '')
                }
            end
        end
    end
    return out
end

local function validVehicle(model)
    model = normalizeVehicleModel(model)
    if model == '' or GetResourceState('qbx_core') ~= 'started' then return false end
    local ok, vehicle = pcall(function()
        return exports.qbx_core:GetVehiclesByName(model)
    end)
    return ok and vehicle ~= nil
end

local function rollbackOpenLock(license)
    if not license then return end
    pcall(function()
        MySQL.update.await('UPDATE cookie_newbie_progress SET reward_opened_at=NULL WHERE license=?', { license })
    end)
end

local function rollbackDelivered(src, player, deliveredItems, deliveredMoney, deliveredVehicles)
    for i = #deliveredItems, 1, -1 do
        local r = deliveredItems[i]
        pcall(function() exports.ox_inventory:RemoveItem(src, r.itemName, r.itemCount) end)
    end

    for i = #deliveredMoney, 1, -1 do
        local r = deliveredMoney[i]
        pcall(function() player.Functions.RemoveMoney(r.type, r.amount, '뉴비 보상 키트 지급 실패 롤백') end)
    end

    for i = #deliveredVehicles, 1, -1 do
        local r = deliveredVehicles[i]
        pcall(function()
            MySQL.update.await('DELETE FROM player_vehicles WHERE id=? AND citizenid=?', { r.vehicleId, r.citizenid })
        end)
    end
end

local function restoreKit(src)
    local ok, result = pcall(function()
        return exports.ox_inventory:AddItem(src, KIT_ITEM, 1)
    end)
    if not ok or not result then
        print(('^1[cookie_items] CRITICAL: failed to restore newbie kit for src=%s after reward rollback^7'):format(tostring(src)))
        return false
    end
    return true
end

local function createRewardVehicle(src, player, model)
    model = normalizeVehicleModel(model)
    if GetResourceState('qbx_vehicles') ~= 'started' then
        return nil, 'qbx_vehicles가 실행 중이 아닙니다.'
    end
    if not validVehicle(model) then
        return nil, ('등록되지 않은 차량 SpawnCode입니다: %s'):format(model)
    end

    local citizenid = player and player.PlayerData and player.PlayerData.citizenid
    if not citizenid then return nil, '시민 정보를 찾지 못했습니다.' end

    local ok, vehicleId = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = citizenid,
            garage = PERSONAL_GARAGE,
        })
    end)
    vehicleId = tonumber(vehicleId)
    if not ok or not vehicleId then
        return nil, ('%s 차량 소유권 등록에 실패했습니다.'):format(model)
    end

    -- 어떤 qbx_vehicles 버전에서도 쿠키 개인 차고 보관 상태로 맞춘다.
    pcall(function()
        MySQL.update.await('UPDATE player_vehicles SET garage=?, state=1 WHERE id=? AND citizenid=?', {
            PERSONAL_GARAGE, vehicleId, citizenid
        })
    end)

    -- 쿠키 차량 포장/거래 시스템에서 사용하는 영구 UID를 즉시 부여한다.
    local assetUid = nil
    if GetResourceState('cookie_admin') == 'started' then
        local uidOk, uid = pcall(function()
            return exports.cookie_admin:EnsureVehicleAssetUid(vehicleId)
        end)
        if uidOk then assetUid = uid end
    end

    if not assetUid or tostring(assetUid) == '' then
        pcall(function()
            MySQL.update.await('DELETE FROM player_vehicles WHERE id=? AND citizenid=?', { vehicleId, citizenid })
        end)
        return nil, ('%s 차량 고유 ID 생성에 실패했습니다.'):format(model)
    end

    -- 번호판 중복이 생긴 비정상 케이스는 즉시 롤백한다.
    local created = MySQL.single.await('SELECT plate FROM player_vehicles WHERE id=? AND citizenid=? LIMIT 1', { vehicleId, citizenid })
    if created and created.plate then
        local dup = tonumber(MySQL.scalar.await(
            "SELECT COUNT(*) FROM player_vehicles WHERE REPLACE(UPPER(plate),' ','') = REPLACE(UPPER(?),' ','')",
            { created.plate }
        ) or 0)
        if dup > 1 then
            pcall(function()
                MySQL.update.await('DELETE FROM player_vehicles WHERE id=? AND citizenid=?', { vehicleId, citizenid })
            end)
            return nil, ('%s 차량 번호판 중복이 감지되어 지급을 취소했습니다.'):format(model)
        end
    end

    return {
        vehicleId = vehicleId,
        citizenid = citizenid,
        model = model,
        assetUid = tostring(assetUid),
    }
end

local function rewardLabel(r)
    if r.label and r.label ~= '' then return r.label end
    if r.type == 'item' then return ('%s x%d'):format(r.itemName, r.itemCount) end
    if r.type == 'vehicle' then return ('차량 %s'):format(r.vehicleModel or r.itemName) end
    return ('%s %s원'):format(r.type == 'bank' and '계좌' or '현금', r.amount)
end

RegisterNetEvent('cookie_items:server:openNewbieRewardKit', function()
    local src = source
    if not src or src <= 0 then return end

    if GetResourceState('ox_inventory') ~= 'started' then
        return notify(src, 'ox_inventory가 실행 중이 아닙니다.', 'error')
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return notify(src, '플레이어 정보를 찾지 못했습니다.', 'error')
    end

    local license = getLicense(src)
    if not license then
        return notify(src, '플레이어 식별에 실패했습니다.', 'error')
    end

    local row = MySQL.single.await([[
        SELECT reward_claimed_at, reward_opened_at
        FROM cookie_newbie_progress
        WHERE license=?
        LIMIT 1
    ]], { license })

    if not row or not row.reward_claimed_at then
        return notify(src, '정상적으로 지급된 뉴비 보상 키트가 아닙니다.', 'error')
    end
    if row.reward_opened_at then
        return notify(src, '뉴비 보상 키트는 계정당 한 번만 개봉할 수 있습니다.', 'error')
    end

    local count = exports.ox_inventory:Search(src, 'count', KIT_ITEM) or 0
    if tonumber(count) < 1 then
        return notify(src, '인벤토리에 뉴비 보상 키트가 없습니다.', 'error')
    end

    local rewards = loadRewards()
    if #rewards == 0 then
        return notify(src, '현재 뉴비 보상 키트 내용물이 설정되어 있지 않습니다. 관리자에게 문의해주세요.', 'error')
    end

    -- 지급 전에 '존재 여부'만 검증한다.
    -- 공간/무게는 키트 1개를 먼저 제거한 뒤 실제 AddItem 결과로 판단해야
    -- 키트가 마지막 슬롯을 차지한 경우의 잘못된 "인벤토리 꽉 참" 판정을 피할 수 있다.
    for _, r in ipairs(rewards) do
        if r.type == 'item' then
            local okItem, item = pcall(function() return exports.ox_inventory:Items(r.itemName) end)
            if not okItem or not item then
                return notify(src, ('보상 아이템 설정 오류: %s'):format(r.itemName), 'error')
            end
        elseif r.type == 'vehicle' then
            if GetResourceState('qbx_vehicles') ~= 'started' then
                return notify(src, '차량 보상 시스템(qbx_vehicles)이 실행 중이 아닙니다.', 'error')
            end
            if not validVehicle(r.vehicleModel or r.itemName) then
                return notify(src, ('보상 차량 설정 오류: %s'):format(r.vehicleModel or r.itemName), 'error')
            end
        end
    end

    -- 중복 이벤트/매크로를 DB에서 먼저 잠금 처리한다.
    local changed = MySQL.update.await([[
        UPDATE cookie_newbie_progress
        SET reward_opened_at=NOW()
        WHERE license=? AND reward_claimed_at IS NOT NULL AND reward_opened_at IS NULL
    ]], { license })

    if tonumber(changed) ~= 1 then
        return notify(src, '이미 처리 중이거나 개봉이 완료된 키트입니다.', 'error')
    end

    -- 키트를 먼저 제거해서 슬롯/무게를 실제로 확보한다.
    local removed = exports.ox_inventory:RemoveItem(src, KIT_ITEM, 1)
    if not removed then
        rollbackOpenLock(license)
        return notify(src, '보상 키트를 확인하지 못했습니다. 다시 시도해주세요.', 'error')
    end

    local deliveredItems, deliveredMoney, deliveredVehicles = {}, {}, {}

    for _, r in ipairs(rewards) do
        if r.type == 'item' then
            local okAdd, success = pcall(function()
                return exports.ox_inventory:AddItem(src, r.itemName, r.itemCount)
            end)
            if not okAdd or not success then
                rollbackDelivered(src, player, deliveredItems, deliveredMoney, deliveredVehicles)
                restoreKit(src)
                rollbackOpenLock(license)
                return notify(src, '실제로 보상을 넣을 공간/무게가 부족해 지급을 취소하고 키트를 복구했습니다.', 'error')
            end
            deliveredItems[#deliveredItems + 1] = r

        elseif r.type == 'vehicle' then
            local vehicleRow, vehicleErr = createRewardVehicle(src, player, r.vehicleModel or r.itemName)
            if not vehicleRow then
                rollbackDelivered(src, player, deliveredItems, deliveredMoney, deliveredVehicles)
                restoreKit(src)
                rollbackOpenLock(license)
                return notify(src, vehicleErr or '차량 보상 지급 중 오류가 발생해 키트를 복구했습니다.', 'error')
            end
            deliveredVehicles[#deliveredVehicles + 1] = vehicleRow

        else
            local okMoney, success = pcall(function()
                return player.Functions.AddMoney(r.type, r.amount, '뉴비 보상 키트')
            end)
            if not okMoney or not success then
                rollbackDelivered(src, player, deliveredItems, deliveredMoney, deliveredVehicles)
                restoreKit(src)
                rollbackOpenLock(license)
                return notify(src, '지원금 지급 중 오류가 발생해 키트를 복구했습니다.', 'error')
            end
            deliveredMoney[#deliveredMoney + 1] = r
        end
    end

    local names = {}
    for i = 1, math.min(#rewards, 4) do names[#names + 1] = rewardLabel(rewards[i]) end
    local suffix = #rewards > 4 and (' 외 %d개'):format(#rewards - 4) or ''
    notify(src, ('뉴비 보상 지급 완료! %s%s'):format(table.concat(names, ', '), suffix), 'success')
end)

CreateThread(function()
    Wait(1200)
    auditOxItemLinks()

    pcall(function()
        MySQL.query.await('ALTER TABLE cookie_newbie_progress ADD COLUMN IF NOT EXISTS reward_opened_at DATETIME NULL AFTER reward_claimed_at')
    end)
    local ok, err = pcall(ensureRewardTables)
    if ok then
        print('^2[cookie_items]^7 newbie reward V1.3 ready (inventory fix + vehicle reward)')
    else
        print(('^1[cookie_items] newbie reward DB init failed: %s^7'):format(tostring(err)))
    end
end)
