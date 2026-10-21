-- COOKIE SERVER - 관리자 지급 우편함
local PERSONAL_GARAGE = 'cookie_personal_v2'

local function mailLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function trim(v, n)
    local s = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if n and #s > n then s = s:sub(1, n) end
    return s
end

local function mailNotify(src, msg, warn)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, warn == true)
end

local function currentAdmin(src, featureKey)
    local lic = mailLicense(src)
    if not lic then return nil, '관리자 식별 정보를 찾을 수 없습니다' end
    local row = MySQL.single.await([[
        SELECT a.admin_name, a.admin_level, a.license, f.min_level
        FROM cookie_admin a
        JOIN cookie_admin_feature f ON f.feature_key = ?
        WHERE a.license = ? AND a.is_active = 1
        LIMIT 1
    ]], { featureKey, lic })
    if not row or tonumber(row.admin_level or 0) < tonumber(row.min_level or 99) then
        return nil, '해당 지급 권한이 없습니다'
    end
    if type(CookieGetAdminState) == 'function' and CookieGetAdminState(src) ~= 'duty' then
        return nil, '관리 업무 시작 후 사용 가능합니다'
    end
    return row
end

local function targetInfo(serverId)
    local target = tonumber(serverId)
    if not target then return nil, '대상을 찾을 수 없습니다' end
    local p = exports.qbx_core:GetPlayer(target)
    if not p or not p.PlayerData or not p.PlayerData.citizenid then
        return nil, '대상을 찾을 수 없습니다'
    end
    local name = GetPlayerName(target) or ('#' .. target)
    local ok, nick = pcall(function() return exports.cookie_core:getNickname(target) end)
    if ok and type(nick) == 'string' and nick ~= '' then name = nick end
    return {
        source = target,
        player = p,
        citizenid = p.PlayerData.citizenid,
        name = name,
    }
end

local function itemInfo(name)
    name = trim(name, 80):lower()
    if name == '' then return nil end
    local ok, items = pcall(function() return exports.ox_inventory:Items() end)
    if not ok or type(items) ~= 'table' then return nil end
    local item = items[name]
    if not item then return nil end
    return { name = name, label = item.label or name }
end

local function vehicleInfo(model)
    model = trim(model, 60):lower():gsub('%s+', '')
    if model == '' then return nil end
    local coreVeh = exports.qbx_core:GetVehiclesByName(model)
    if not coreVeh then return nil end
    local limited = MySQL.single.await(
        'SELECT model, label FROM cookie_limited_vehicles WHERE LOWER(model) = ? AND active = 1 LIMIT 1',
        { model })
    if limited then
        return { model = model, label = limited.label or coreVeh.name or model, garageType = 'limited' }
    end
    local general = MySQL.single.await(
        'SELECT model, display_name FROM cookie_dealership_vehicles WHERE LOWER(model) = ? AND active = 1 LIMIT 1',
        { model })
    if general then
        return { model = model, label = general.display_name or coreVeh.name or model, garageType = 'general' }
    end
    return nil
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_mailbox` (
          `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `recipient_citizenid` VARCHAR(64) NOT NULL,
          `recipient_name` VARCHAR(80) NULL,
          `sender_type` VARCHAR(20) NOT NULL DEFAULT 'admin',
          `sender_name` VARCHAR(80) NOT NULL,
          `sender_license` VARCHAR(90) NULL,
          `mail_type` VARCHAR(20) NOT NULL,
          `reward_label` VARCHAR(120) NOT NULL,
          `account` VARCHAR(10) NULL,
          `amount` BIGINT NOT NULL DEFAULT 0,
          `item_name` VARCHAR(80) NULL,
          `quantity` INT NOT NULL DEFAULT 1,
          `vehicle_model` VARCHAR(60) NULL,
          `vehicle_type` VARCHAR(20) NULL,
          `reason` VARCHAR(240) NOT NULL,
          `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `claimed_at` DATETIME NULL,
          PRIMARY KEY (`id`),
          KEY `idx_mail_recipient` (`recipient_citizenid`,`status`,`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]], {})

    -- 지급 기능을 별도 탭으로 이동한다. 기존 DB에도 자동 반영.
    MySQL.query.await([[
        INSERT INTO cookie_admin_category (category_key, label, tab_min_level, sort_order)
        VALUES ('grant', '지급 관리', 3, 3)
        ON DUPLICATE KEY UPDATE label = VALUES(label), tab_min_level = VALUES(tab_min_level), sort_order = VALUES(sort_order)
    ]], {})

    local grantCat = MySQL.scalar.await("SELECT id FROM cookie_admin_category WHERE category_key='grant' LIMIT 1")
    if grantCat then
        MySQL.query.await([[
            INSERT INTO cookie_admin_feature
              (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
            VALUES
              (?, 'give_money', '돈 지급', 3, 0, 1, 1),
              (?, 'give_item', '아이템 지급', 3, 0, 1, 2),
              (?, 'veh_give', '차량 지급', 3, 0, 1, 3)
            ON DUPLICATE KEY UPDATE
              category_id=VALUES(category_id), label=VALUES(label), min_level=VALUES(min_level),
              danger_level=VALUES(danger_level), requires_target=VALUES(requires_target), sort_order=VALUES(sort_order)
        ]], { grantCat, grantCat, grantCat })
    end
end)

RegisterNetEvent('cookie_admin:server:requestGrantItems', function()
    local src = source
    local admin, err = currentAdmin(src, 'give_item')
    if not admin then
        TriggerClientEvent('cookie_admin:client:grantItems', src, {}, err)
        return
    end
    local ok, all = pcall(function() return exports.ox_inventory:Items() end)
    local rows = {}
    if ok and type(all) == 'table' then
        for name, item in pairs(all) do
            -- 무기는 기존 무기 관리에서 지급. 일반 아이템/탄약/티켓/음식 등은 여기에 표시.
            if not tostring(name):lower():match('^weapon_') then
                rows[#rows + 1] = { name = name, label = item.label or name }
            end
        end
        table.sort(rows, function(a, b) return tostring(a.label) < tostring(b.label) end)
    end
    TriggerClientEvent('cookie_admin:client:grantItems', src, rows, nil)
end)

RegisterNetEvent('cookie_admin:server:sendGrantMail', function(data)
    local src = source
    data = type(data) == 'table' and data or {}
    local mailType = trim(data.type, 20):lower()
    local featureKey = ({ money = 'give_money', item = 'give_item', vehicle = 'veh_give' })[mailType]
    if not featureKey then return mailNotify(src, '잘못된 지급 유형입니다', true) end

    local admin, err = currentAdmin(src, featureKey)
    if not admin then return mailNotify(src, err, true) end
    local target, terr = targetInfo(data.targetServerId)
    if not target then return mailNotify(src, terr, true) end

    local reason = trim(data.reason, 240)
    if reason == '' then reason = '사유 없음' end

    local row = {
        mailType = mailType,
        label = '', account = nil, amount = 0, item = nil, quantity = 1, vehicle = nil, vehicleType = nil,
    }

    if mailType == 'money' then
        local account = trim(data.account, 10):lower()
        if account ~= 'cash' and account ~= 'bank' then return mailNotify(src, '현금 또는 계좌를 선택해주세요', true) end
        local amount = math.floor(tonumber(data.amount) or 0)
        if amount < 1 or amount > 10000000000 then return mailNotify(src, '지급 금액을 확인해주세요', true) end
        row.account = account
        row.amount = amount
        row.label = (account == 'cash' and '현금 ' or '계좌 ') .. ('$' .. tostring(amount))
    elseif mailType == 'item' then
        local it = itemInfo(data.itemName)
        if not it then return mailNotify(src, '등록되지 않은 아이템입니다', true) end
        local qty = math.floor(tonumber(data.quantity) or 0)
        if qty < 1 or qty > 9999 then return mailNotify(src, '아이템 수량은 1~9999개로 입력해주세요', true) end
        row.item = it.name
        row.quantity = qty
        row.label = ('%s × %d'):format(it.label, qty)
    elseif mailType == 'vehicle' then
        local veh = vehicleInfo(data.vehicleModel)
        if not veh then return mailNotify(src, '일반/한정 차량 목록에 등록된 차량만 지급할 수 있습니다', true) end
        row.vehicle = veh.model
        row.vehicleType = veh.garageType
        row.label = ('%s (%s)'):format(veh.label, veh.garageType == 'limited' and '한정 차량' or '일반 차량')
    end

    local id = MySQL.insert.await([[
        INSERT INTO cookie_mailbox
          (recipient_citizenid, recipient_name, sender_type, sender_name, sender_license,
           mail_type, reward_label, account, amount, item_name, quantity, vehicle_model, vehicle_type, reason, status)
        VALUES (?, ?, 'admin', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
    ]], {
        target.citizenid, target.name, admin.admin_name or '관리자', admin.license,
        row.mailType, row.label, row.account, row.amount, row.item, row.quantity, row.vehicle, row.vehicleType, reason
    })
    if not id then return mailNotify(src, '우편 발송에 실패했습니다', true) end

    mailNotify(src, ('%s님 우편함으로 %s 발송 완료'):format(target.name, row.label), false)
    TriggerClientEvent('cookie_admin:client:mailArrived', target.source, admin.admin_name or '관리자', row.label)
    TriggerClientEvent('cookie_admin:client:grantMailResult', src, true)
end)

local function loadMailbox(src)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.citizenid then return {} end
    return MySQL.query.await([[
        SELECT id, sender_type, sender_name, mail_type, reward_label, account, amount,
               item_name, quantity, vehicle_model, vehicle_type, reason, status, created_at, claimed_at
        FROM cookie_mailbox
        WHERE recipient_citizenid = ?
        ORDER BY (status='pending') DESC, id DESC
        LIMIT 100
    ]], { p.PlayerData.citizenid }) or {}
end

RegisterNetEvent('cookie_admin:server:requestMailbox', function()
    local src = source
    TriggerClientEvent('cookie_admin:client:mailboxData', src, loadMailbox(src))
end)

RegisterNetEvent('cookie_admin:server:deleteMailbox', function(mailId)
    local src = source
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.citizenid then return end

    local cid = p.PlayerData.citizenid
    local id = math.floor(tonumber(mailId) or 0)
    if id < 1 then return end

    -- 보상을 실제로 수령 완료한 본인 우편만 삭제할 수 있다.
    local deleted = MySQL.update.await([[
        DELETE FROM cookie_mailbox
        WHERE id = ? AND recipient_citizenid = ? AND status = 'claimed'
    ]], { id, cid }) or 0

    if deleted > 0 then
        mailNotify(src, '수령 완료된 우편을 삭제했습니다', false)
    else
        mailNotify(src, '수령 완료된 우편만 삭제할 수 있습니다', true)
    end

    TriggerClientEvent('cookie_admin:client:mailboxData', src, loadMailbox(src))
end)

RegisterNetEvent('cookie_admin:server:claimMailbox', function(mailId)
    local src = source
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.citizenid then return end
    local cid = p.PlayerData.citizenid
    local id = math.floor(tonumber(mailId) or 0)
    if id < 1 then return end

    local locked = MySQL.update.await([[
        UPDATE cookie_mailbox SET status='processing'
        WHERE id=? AND recipient_citizenid=? AND status='pending'
    ]], { id, cid }) or 0
    if locked < 1 then
        mailNotify(src, '이미 수령했거나 처리 중인 우편입니다', true)
        TriggerClientEvent('cookie_admin:client:mailboxData', src, loadMailbox(src))
        return
    end

    local m = MySQL.single.await([[
        SELECT * FROM cookie_mailbox WHERE id=? AND recipient_citizenid=? LIMIT 1
    ]], { id, cid })
    if not m then return end

    local ok, err = false, '지급 처리에 실패했습니다'
    if m.mail_type == 'money' then
        local account = (m.account == 'bank') and 'bank' or 'cash'
        local amount = math.floor(tonumber(m.amount) or 0)
        if amount > 0 then
            local result = p.Functions.AddMoney(account, amount, '관리자 우편 지급')
            ok = result ~= false
            if not ok then err = '돈 지급에 실패했습니다' end
        end
    elseif m.mail_type == 'item' then
        local qty = math.floor(tonumber(m.quantity) or 0)
        if qty > 0 and itemInfo(m.item_name) then
            local added = exports.ox_inventory:AddItem(src, m.item_name, qty)
            ok = added and true or false
            if not ok then err = '인벤토리 공간/무게를 확인해주세요' end
        else
            err = '현재 서버에 존재하지 않는 아이템입니다'
        end
    elseif m.mail_type == 'vehicle' then
        local veh = vehicleInfo(m.vehicle_model)
        if not veh then
            err = '현재 차량 목록에서 제거된 차량입니다'
        else
            if veh.garageType == 'general' then
                local dup = MySQL.single.await([[
                    SELECT id FROM player_vehicles WHERE citizenid=? AND LOWER(vehicle)=? LIMIT 1
                ]], { cid, veh.model })
                if dup then
                    err = '이미 같은 일반 차량을 보유하고 있습니다'
                else
                    local success, vehicleId = pcall(function()
                        return exports.qbx_vehicles:CreatePlayerVehicle({ model = veh.model, citizenid = cid, garage = PERSONAL_GARAGE })
                    end)
                    ok = success and vehicleId ~= nil
                    if not ok then err = '차량 차고 지급에 실패했습니다' end
                end
            else
                local success, vehicleId = pcall(function()
                    return exports.qbx_vehicles:CreatePlayerVehicle({ model = veh.model, citizenid = cid, garage = PERSONAL_GARAGE })
                end)
                ok = success and vehicleId ~= nil
                if not ok then err = '차량 차고 지급에 실패했습니다' end
            end
        end
    end

    if ok then
        MySQL.update.await("UPDATE cookie_mailbox SET status='claimed', claimed_at=NOW() WHERE id=? AND recipient_citizenid=?", { id, cid })
        mailNotify(src, '우편 보상을 수령했습니다: ' .. tostring(m.reward_label or ''), false)
    else
        MySQL.update.await("UPDATE cookie_mailbox SET status='pending' WHERE id=? AND recipient_citizenid=? AND status='processing'", { id, cid })
        mailNotify(src, err, true)
    end
    TriggerClientEvent('cookie_admin:client:mailboxData', src, loadMailbox(src))
end)
