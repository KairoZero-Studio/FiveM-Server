-- COOKIE 편의점 공용 상품 / 구매 시스템
-- 모든 convenience 비콘은 이 공용 카탈로그를 사용합니다.

local function trim(v, maxLen)
    local s = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function notify(src, msg, isError)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isError and true or false)
end

local function bootstrapConvenience()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_convenience_food` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `item_name` VARCHAR(80) NOT NULL,
          `label` VARCHAR(80) NOT NULL,
          `price` INT NOT NULL DEFAULT 0,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `sort_order` INT NOT NULL DEFAULT 0,
          `added_by` VARCHAR(60) NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          UNIQUE KEY `uniq_cookie_convenience_item` (`item_name`),
          INDEX `idx_cookie_convenience_active` (`active`, `sort_order`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})
end

CreateThread(function()
    local ok, err = pcall(bootstrapConvenience)
    if not ok then
        print(('[cookie_safezone] 편의점 상품 테이블 생성 실패: %s'):format(tostring(err)))
    end
end)

local function adminActor(src)
    if GetResourceState('cookie_admin') ~= 'started' then
        notify(src, 'cookie_admin이 실행 중이 아닙니다', true)
        return nil
    end

    local ok, level = pcall(function()
        return exports.cookie_admin:getEffectiveLevel(src)
    end)
    if not ok or (tonumber(level) or 0) < 5 then
        notify(src, '편의점 상품 관리 권한이 부족합니다', true)
        return nil
    end

    local name = GetPlayerName(src) or ('ID ' .. tostring(src))
    pcall(function()
        name = exports.cookie_admin:getAdminName(src) or name
    end)
    return name
end

local function itemExists(itemName)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    local ok, item = pcall(function()
        return exports.ox_inventory:Items(itemName)
    end)
    return ok and item ~= nil
end

local function sendAdminList(src)
    local rows = MySQL.query.await([[
        SELECT id, item_name, label, price, active, sort_order
        FROM cookie_convenience_food
        ORDER BY sort_order ASC, id ASC
    ]], {}) or {}
    TriggerClientEvent('cookie_safezone:client:convenienceAdmin', src, rows)
end

RegisterNetEvent('cookie_safezone:server:requestConvenienceAdmin', function()
    local src = source
    if not adminActor(src) then return end
    sendAdminList(src)
end)

RegisterNetEvent('cookie_safezone:server:saveConvenienceFood', function(data)
    local src = source
    local actor = adminActor(src)
    if not actor or type(data) ~= 'table' then return end

    local id = math.floor(tonumber(data.id) or 0)
    local itemName = trim(data.itemName or data.item_name, 80):lower()
    local label = trim(data.label, 80)
    local price = math.floor(tonumber(data.price) or 0)
    local sortOrder = math.floor(tonumber(data.sortOrder or data.sort_order) or 0)
    local active = (data.active == false or data.active == 0 or data.active == '0') and 0 or 1

    if itemName == '' or not itemName:match('^[%w_%-%.]+$') then
        notify(src, '올바른 아이템 코드를 입력하세요', true)
        return
    end
    if label == '' then
        notify(src, '상품 표시 이름을 입력하세요', true)
        return
    end
    if price < 0 or price > 2000000000 then
        notify(src, '가격이 올바르지 않습니다', true)
        return
    end
    if not itemExists(itemName) then
        notify(src, ('ox_inventory에 "%s" 아이템이 없습니다'):format(itemName), true)
        return
    end

    local ok, err = pcall(function()
        if id > 0 then
            MySQL.update.await([[
                UPDATE cookie_convenience_food
                SET item_name = ?, label = ?, price = ?, active = ?, sort_order = ?
                WHERE id = ?
            ]], { itemName, label, price, active, sortOrder, id })
        else
            MySQL.insert.await([[
                INSERT INTO cookie_convenience_food
                    (item_name, label, price, active, sort_order, added_by)
                VALUES (?, ?, ?, ?, ?, ?)
            ]], { itemName, label, price, active, sortOrder, actor })
        end
    end)

    if not ok then
        local text = tostring(err or '')
        if text:lower():find('duplicate', 1, true) then
            notify(src, '이미 등록된 아이템 코드입니다', true)
        else
            notify(src, '편의점 상품 저장에 실패했습니다', true)
            print(('[cookie_safezone] 편의점 상품 저장 실패: %s'):format(text))
        end
        return
    end

    notify(src, id > 0 and '편의점 상품을 수정했습니다' or '편의점 상품을 추가했습니다', false)
    sendAdminList(src)
end)

RegisterNetEvent('cookie_safezone:server:deleteConvenienceFood', function(rowId)
    local src = source
    if not adminActor(src) then return end
    local id = math.floor(tonumber(rowId) or 0)
    if id <= 0 then return end

    MySQL.query.await('DELETE FROM cookie_convenience_food WHERE id = ?', { id })
    notify(src, '편의점 상품을 삭제했습니다', false)
    sendAdminList(src)
end)

RegisterNetEvent('cookie_safezone:server:requestConvenienceCatalog', function()
    local src = source
    if not CookieSafezoneAllowAction(src, 'shop_catalog', 500, 2) then return end
    if not CookieSafezonePlayerNearType(src, 'convenience', 4.0) then return end
    local rows = MySQL.query.await([[
        SELECT id, item_name, label, price
        FROM cookie_convenience_food
        WHERE active = 1
        ORDER BY sort_order ASC, id ASC
    ]], {}) or {}
    TriggerClientEvent('cookie_safezone:client:openConvenienceCatalog', src, rows)
end)

RegisterNetEvent('cookie_safezone:server:buyConvenienceFood', function(rowId, quantity)
    local src = source
    if not CookieSafezoneAllowAction(src, 'shop_buy', 700, 1) then return end
    if not CookieSafezonePlayerNearType(src, 'convenience', 4.0) then return notify(src, '편의점 근처에서만 구매할 수 있습니다', true) end
    local id = math.floor(tonumber(rowId) or 0)
    local qty = math.floor(tonumber(quantity) or 1)
    if id <= 0 then return end
    if qty < 1 then qty = 1 elseif qty > 20 then qty = 20 end

    local row = MySQL.single.await([[
        SELECT id, item_name, label, price
        FROM cookie_convenience_food
        WHERE id = ? AND active = 1
        LIMIT 1
    ]], { id })
    if not row then
        notify(src, '현재 판매하지 않는 상품입니다', true)
        return
    end

    if not itemExists(row.item_name) then
        notify(src, '상품 아이템 설정에 문제가 있습니다. 관리자에게 문의하세요', true)
        return
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player or not player.Functions then return end

    local price = math.max(0, math.floor(tonumber(row.price) or 0))
    local total = price * qty

    local canCarry = false
    local okCarry = pcall(function()
        canCarry = exports.ox_inventory:CanCarryItem(src, row.item_name, qty)
    end)
    if not okCarry or not canCarry then
        notify(src, '인벤토리 공간이 부족합니다', true)
        return
    end

    if total > 0 then
        local paid = player.Functions.RemoveMoney('cash', total, '편의점 구매')
        if not paid then
            notify(src, ('현금이 부족합니다. 필요 금액: %s원'):format(total), true)
            return
        end
    end

    local added = false
    pcall(function()
        added = exports.ox_inventory:AddItem(src, row.item_name, qty) == true
    end)

    if not added then
        if total > 0 then
            player.Functions.AddMoney('cash', total, '편의점 구매 실패 환불')
        end
        notify(src, '상품 지급에 실패했습니다. 결제 금액은 환불됐습니다', true)
        return
    end

    notify(src, ('%s x%d 구매 완료 (-%s원)'):format(row.label, qty, total), false)
end)
