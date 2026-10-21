-- COOKIE F3 NEWBIE KIT SYSTEM V2
-- 시스템 관리 > 뉴비 보상 키트 내용물 관리
-- V2: 차량 보상(vehicle) 지원. 차량 모델은 qbx_core에 등록된 SpawnCode만 허용한다.

local MAX_REWARD_ROWS = 30
local DEFAULT_REWARDS = {
    { type = 'item', itemName = 'medikit',       itemCount = 2, amount = 0,     label = '구급상자 x2' },
    { type = 'item', itemName = 'armor',         itemCount = 1, amount = 0,     label = '방탄복 x1' },
    { type = 'item', itemName = 'oxy',           itemCount = 3, amount = 0,     label = '진통제 x3' },
    { type = 'item', itemName = 'energy_drink',  itemCount = 2, amount = 0,     label = '에너지 드링크 x2' },
    { type = 'bank', itemName = '',              itemCount = 0, amount = 50000, label = '정착지원금 50,000원' },
}

local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr == true)
end

local function auth(src)
    local admin = CookieAdminTeamAuth and CookieAdminTeamAuth(src, 'general') or nil
    if not admin or (tonumber(admin.admin_level) or 0) < 5 then return nil end
    return admin
end

local function cleanText(value, maxLen)
    local s = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > (maxLen or 80) then s = s:sub(1, maxLen or 80) end
    return s
end

local function normalizeVehicleModel(value)
    return cleanText(value, 60):lower():gsub('%s+', '')
end

local function ensureTables()
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
    ensureTables()
    local rows = MySQL.query.await([[
        SELECT id, sort_order, reward_type, item_name, item_count, amount, display_label
        FROM cookie_newbie_kit_reward
        ORDER BY sort_order ASC, id ASC
    ]]) or {}

    local out = {}
    for _, r in ipairs(rows) do
        local rewardType = tostring(r.reward_type or '')
        local storedName = tostring(r.item_name or '')
        out[#out + 1] = {
            id = tonumber(r.id),
            type = rewardType,
            itemName = rewardType == 'item' and storedName or '',
            vehicleModel = rewardType == 'vehicle' and storedName or '',
            itemCount = math.max(0, math.floor(tonumber(r.item_count) or 0)),
            amount = math.max(0, math.floor(tonumber(r.amount) or 0)),
            label = tostring(r.display_label or ''),
        }
    end
    return out
end

local function sendData(src, message, isError)
    TriggerClientEvent('cookie_admin:client:newbieKitSystemData', src, {
        rewards = loadRewards(),
        maxRows = MAX_REWARD_ROWS,
    }, message, isError == true)
end

local function validItem(name)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
    return ok and item ~= nil
end

local function validVehicle(model)
    model = normalizeVehicleModel(model)
    if model == '' or GetResourceState('qbx_core') ~= 'started' then return false end
    local ok, vehicle = pcall(function()
        return exports.qbx_core:GetVehiclesByName(model)
    end)
    return ok and vehicle ~= nil
end

local function sanitizeRewards(input)
    if type(input) ~= 'table' then return nil, '보상 목록이 올바르지 않습니다.' end
    if #input > MAX_REWARD_ROWS then return nil, ('보상은 최대 %d개까지 등록할 수 있습니다.'):format(MAX_REWARD_ROWS) end

    local out = {}
    for i, row in ipairs(input) do
        if type(row) == 'table' then
            local t = tostring(row.type or ''):lower()
            local label = cleanText(row.label, 80)

            if t == 'item' then
                local itemName = cleanText(row.itemName, 80):lower()
                local count = math.floor(tonumber(row.itemCount) or 0)
                if itemName == '' then return nil, ('%d번째 보상의 아이템 이름이 비어 있습니다.'):format(i) end
                if count < 1 or count > 999 then return nil, ('%d번째 아이템 개수는 1~999여야 합니다.'):format(i) end
                if not validItem(itemName) then return nil, ('존재하지 않는 아이템입니다: %s'):format(itemName) end
                out[#out + 1] = { type='item', itemName=itemName, itemCount=count, amount=0, label=label }

            elseif t == 'bank' or t == 'cash' then
                local amount = math.floor(tonumber(row.amount) or 0)
                if amount < 1 or amount > 1000000000 then
                    return nil, ('%d번째 금액은 1~1,000,000,000 범위여야 합니다.'):format(i)
                end
                out[#out + 1] = { type=t, itemName='', itemCount=0, amount=amount, label=label }

            elseif t == 'vehicle' then
                local model = normalizeVehicleModel(row.vehicleModel or row.itemName)
                if model == '' then return nil, ('%d번째 차량 SpawnCode가 비어 있습니다.'):format(i) end
                if not validVehicle(model) then return nil, ('등록되지 않은 차량 SpawnCode입니다: %s'):format(model) end
                out[#out + 1] = { type='vehicle', itemName=model, itemCount=1, amount=0, label=label }

            else
                return nil, ('%d번째 보상 유형이 올바르지 않습니다.'):format(i)
            end
        end
    end
    return out
end

CreateThread(function()
    Wait(1800)
    local ok, err = pcall(ensureTables)
    if ok then
        print('^2[cookie_admin]^7 newbie kit system V2 ready (item/money/vehicle)')
    else
        print(('^1[cookie_admin] newbie kit table init failed: %s^7'):format(tostring(err)))
    end
end)

RegisterNetEvent('cookie_admin:server:requestNewbieKitSystem', function()
    local src = source
    if not auth(src) then return notify(src, '시스템 관리 권한이 없습니다', true) end
    sendData(src)
end)

RegisterNetEvent('cookie_admin:server:saveNewbieKitSystem', function(data)
    local src = source
    local admin = auth(src)
    if not admin then return notify(src, '시스템 관리 권한이 없습니다', true) end

    local rewards, why = sanitizeRewards(type(data) == 'table' and data.rewards or nil)
    if not rewards then
        TriggerClientEvent('cookie_admin:client:newbieKitSystemSaved', src, false, why or '저장할 수 없습니다.')
        return
    end

    ensureTables()

    local statements = {
        { query = 'DELETE FROM cookie_newbie_kit_reward', values = {} },
    }
    for i, r in ipairs(rewards) do
        statements[#statements + 1] = {
            query = [[
                INSERT INTO cookie_newbie_kit_reward
                  (sort_order, reward_type, item_name, item_count, amount, display_label)
                VALUES (?, ?, ?, ?, ?, ?)
            ]],
            values = { i, r.type, r.itemName ~= '' and r.itemName or nil, r.itemCount, r.amount, r.label ~= '' and r.label or nil }
        }
    end
    statements[#statements + 1] = {
        query = 'UPDATE cookie_newbie_kit_config SET initialized=1, updated_by=? WHERE id=1',
        values = { tostring(admin.admin_name or '관리자') }
    }

    local ok, result = pcall(function()
        return MySQL.transaction.await(statements)
    end)
    if not ok or result == false then
        TriggerClientEvent('cookie_admin:client:newbieKitSystemSaved', src, false, 'DB 저장에 실패했습니다. 서버 콘솔을 확인하세요.')
        return
    end

    print(('[cookie_admin][newbie-kit] %s saved %d rewards'):format(tostring(admin.admin_name or src), #rewards))
    TriggerClientEvent('cookie_admin:client:newbieKitSystemSaved', src, true, ('뉴비 보상 키트 내용물 %d개를 저장했습니다.'):format(#rewards))
    sendData(src)
end)

exports('GetNewbieKitRewards', loadRewards)
