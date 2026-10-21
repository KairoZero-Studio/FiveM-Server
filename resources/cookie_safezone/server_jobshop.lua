-- COOKIE 시민직업 도구 상점
-- 비콘 타입: jobshop
-- 현재 버전에서는 기업/팩션 상점을 다루지 않는다.
-- 모든 jobshop 비콘은 공용이며, 플레이어의 현재 시민직업에 맞는 상품만 보여준다.

local function trim(v, maxLen)
    local s = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function lower(v)
    return tostring(v or ''):lower()
end

local function notify(src, message, isError)
    TriggerClientEvent('cookie_admin:client:notify', src, message, isError == true)
end

local function getPlayer(src)
    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(src)
    end)
    return ok and player or nil
end

local function jobConfig(jobName)
    local cfg = Config.JobShop or {}
    return (cfg.jobs or {})[lower(jobName)]
end

local function getItemDefinition(name)
    if GetResourceState('ox_inventory') ~= 'started' then return nil end
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
    return ok and item or nil
end

local function itemExists(name)
    return getItemDefinition(name) ~= nil
end

local function itemImage(name)
    local item = getItemDefinition(name)
    local client = item and item.client or nil
    return tostring((client and client.image) or (item and item.image) or (tostring(name) .. '.png'))
end

local function adminActor(src)
    if GetResourceState('cookie_admin') ~= 'started' then
        notify(src, 'cookie_admin이 실행 중이 아닙니다.', true)
        return nil
    end

    local ok, level = pcall(function()
        return exports.cookie_admin:getEffectiveLevel(src)
    end)
    if not ok or (tonumber(level) or 0) < 5 then
        notify(src, '직업 도구 상점 관리 권한이 부족합니다.', true)
        return nil
    end

    local name = GetPlayerName(src) or ('ID ' .. tostring(src))
    pcall(function()
        name = exports.cookie_admin:getAdminName(src) or name
    end)
    return name
end

local function bootstrapJobShop()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_jobshop_item` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `job_name` VARCHAR(40) NOT NULL,
          `item_name` VARCHAR(80) NOT NULL,
          `label` VARCHAR(80) NOT NULL,
          `price` INT NOT NULL DEFAULT 0,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `sort_order` INT NOT NULL DEFAULT 0,
          `added_by` VARCHAR(60) NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          UNIQUE KEY `uniq_cookie_jobshop_job_item` (`job_name`, `item_name`),
          INDEX `idx_cookie_jobshop_job_active` (`job_name`, `active`, `sort_order`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})

    local cfg = Config.JobShop or {}
    for _, seed in ipairs(cfg.initialItems or {}) do
        local jobName = lower(seed.job)
        local itemName = lower(seed.item)
        if jobConfig(jobName) and itemName ~= '' then
            MySQL.insert.await([[
                INSERT IGNORE INTO cookie_jobshop_item
                    (job_name, item_name, label, price, active, sort_order, added_by)
                VALUES (?, ?, ?, ?, 1, ?, 'config seed')
            ]], {
                jobName,
                itemName,
                trim(seed.label or itemName, 80),
                math.max(0, math.floor(tonumber(seed.price) or 0)),
                math.floor(tonumber(seed.sortOrder) or 0),
            })
        end
    end
end

CreateThread(function()
    local ok, err = pcall(bootstrapJobShop)
    if not ok then
        print(('[cookie_safezone] 직업 도구 상점 테이블 생성 실패: %s'):format(tostring(err)))
    end
end)

local function getCurrentCivilJob(src)
    local player = getPlayer(src)
    if not player then return nil, nil, '플레이어 정보를 찾을 수 없습니다.' end

    local job = player.PlayerData and player.PlayerData.job or {}
    local jobName = lower(job.name)
    local def = jobConfig(jobName)
    if not def then
        return player, nil, '현재 직업은 시민직업 도구 상점을 이용할 수 없습니다.'
    end
    return player, { name = jobName, label = tostring(def.label or job.label or jobName) }, nil
end

local function buildCatalog(src, beaconLabel)
    local _, job, why = getCurrentCivilJob(src)
    if not job then return nil, why end

    local rows = MySQL.query.await([[
        SELECT id, job_name, item_name, label, price, active, sort_order
        FROM cookie_jobshop_item
        WHERE job_name = ? AND active = 1
        ORDER BY sort_order ASC, id ASC
    ]], { job.name }) or {}

    local valid = {}
    for _, row in ipairs(rows) do
        if itemExists(row.item_name) then
            valid[#valid + 1] = {
                id = tonumber(row.id),
                item_name = tostring(row.item_name),
                label = tostring(row.label or row.item_name),
                price = math.max(0, math.floor(tonumber(row.price) or 0)),
                image = itemImage(row.item_name),
            }
        end
    end

    if #valid == 0 then
        return nil, ('%s용 판매 도구가 아직 등록되지 않았습니다.'):format(job.label)
    end

    return {
        title = trim(beaconLabel, 80) ~= '' and trim(beaconLabel, 80) or (job.label .. ' 도구 상점'),
        subtitle = job.label .. ' 업무에 사용하는 시민직업 도구',
        jobName = job.name,
        rows = valid,
    }
end

local function sendAdminList(src)
    local rows = MySQL.query.await([[
        SELECT id, job_name, item_name, label, price, active, sort_order
        FROM cookie_jobshop_item
        ORDER BY job_name ASC, sort_order ASC, id ASC
    ]], {}) or {}

    TriggerClientEvent('cookie_safezone:client:jobShopAdmin', src, {
        rows = rows,
        jobs = (Config.JobShop and Config.JobShop.jobs) or {},
    })
end

RegisterNetEvent('cookie_safezone:server:requestJobShopAdmin', function()
    local src = source
    if not adminActor(src) then return end
    sendAdminList(src)
end)

RegisterNetEvent('cookie_safezone:server:saveJobShopItem', function(data)
    local src = source
    local actor = adminActor(src)
    if not actor or type(data) ~= 'table' then return end

    local id = math.floor(tonumber(data.id) or 0)
    local jobName = lower(trim(data.jobName or data.job_name, 40))
    local itemName = lower(trim(data.itemName or data.item_name, 80))
    local label = trim(data.label, 80)
    local price = math.floor(tonumber(data.price) or 0)
    local sortOrder = math.floor(tonumber(data.sortOrder or data.sort_order) or 0)
    local active = (data.active == false or data.active == 0 or data.active == '0') and 0 or 1

    if not jobConfig(jobName) then
        notify(src, '등록된 시민직업을 선택하세요.', true)
        return
    end
    if itemName == '' or not itemName:match('^[%w_%-%.]+$') then
        notify(src, '올바른 아이템 코드를 입력하세요.', true)
        return
    end
    if label == '' then
        notify(src, '상품 표시 이름을 입력하세요.', true)
        return
    end
    if price < 0 or price > 2000000000 then
        notify(src, '가격이 올바르지 않습니다.', true)
        return
    end
    if not itemExists(itemName) then
        notify(src, ('ox_inventory에 "%s" 아이템이 없습니다.'):format(itemName), true)
        return
    end

    local ok, err = pcall(function()
        if id > 0 then
            MySQL.update.await([[
                UPDATE cookie_jobshop_item
                SET job_name = ?, item_name = ?, label = ?, price = ?, active = ?, sort_order = ?
                WHERE id = ?
            ]], { jobName, itemName, label, price, active, sortOrder, id })
        else
            MySQL.insert.await([[
                INSERT INTO cookie_jobshop_item
                    (job_name, item_name, label, price, active, sort_order, added_by)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ]], { jobName, itemName, label, price, active, sortOrder, actor })
        end
    end)

    if not ok then
        local text = tostring(err or '')
        if text:lower():find('duplicate', 1, true) then
            notify(src, '해당 직업에 이미 등록된 아이템입니다.', true)
        else
            notify(src, '직업 도구 상품 저장에 실패했습니다.', true)
            print(('[cookie_safezone] 직업 도구 상품 저장 실패: %s'):format(text))
        end
        return
    end

    notify(src, id > 0 and '직업 도구 상품을 수정했습니다.' or '직업 도구 상품을 추가했습니다.', false)
    sendAdminList(src)
end)

RegisterNetEvent('cookie_safezone:server:deleteJobShopItem', function(rowId)
    local src = source
    if not adminActor(src) then return end
    local id = math.floor(tonumber(rowId) or 0)
    if id <= 0 then return end

    MySQL.query.await('DELETE FROM cookie_jobshop_item WHERE id = ?', { id })
    notify(src, '직업 도구 상품을 삭제했습니다.', false)
    sendAdminList(src)
end)

RegisterNetEvent('cookie_safezone:server:requestJobShopCatalog', function(payload)
    local src = source
    if not CookieSafezoneAllowAction(src, 'jobshop_catalog', 500, 2) then return end
    if not CookieSafezonePlayerNearType(src, 'jobshop', 4.0) then return notify(src, '직업 상점 근처에서만 이용할 수 있습니다.', true) end
    payload = type(payload) == 'table' and payload or {}
    local data, why = buildCatalog(src, payload.label)
    if not data then return notify(src, why or '직업 상점을 열 수 없습니다.', true) end
    TriggerClientEvent('cookie_safezone:client:openJobShopCatalog', src, data)
end)

RegisterNetEvent('cookie_safezone:server:buyJobShopItem', function(payload)
    local src = source
    if not CookieSafezoneAllowAction(src, 'jobshop_buy', 700, 1) then return end
    if not CookieSafezonePlayerNearType(src, 'jobshop', 4.0) then return notify(src, '직업 상점 근처에서만 구매할 수 있습니다.', true) end
    payload = type(payload) == 'table' and payload or {}

    local cfg = Config.JobShop or {}
    local maxQty = math.max(1, math.floor(tonumber(cfg.maxQuantity) or 20))
    local qty = math.floor(tonumber(payload.quantity) or 1)
    if qty < 1 then qty = 1 elseif qty > maxQty then qty = maxQty end

    local itemName = lower(payload.itemName or payload.item_name)
    if itemName == '' then return end

    local data, why = buildCatalog(src, payload.label)
    if not data then return notify(src, why or '직업 상점을 이용할 수 없습니다.', true) end

    local selected
    for _, row in ipairs(data.rows or {}) do
        if lower(row.item_name) == itemName then
            selected = row
            break
        end
    end
    if not selected then return notify(src, '현재 판매 중인 상품이 아닙니다.', true) end

    local canCarry = false
    local okCarry = pcall(function()
        canCarry = exports.ox_inventory:CanCarryItem(src, selected.item_name, qty)
    end)
    if not okCarry or not canCarry then
        return notify(src, '인벤토리 공간이 부족합니다.', true)
    end

    local player = getPlayer(src)
    if not player or not player.Functions then return end

    local total = selected.price * qty
    local payType = tostring(cfg.payType or 'cash')
    if total > 0 then
        local paid = player.Functions.RemoveMoney(payType, total, 'COOKIE 시민직업 도구 상점 구매')
        if not paid then
            return notify(src, ('%s이 부족합니다. 필요 금액: %s원'):format(payType == 'cash' and '현금' or '잔액', total), true)
        end
    end

    local added = false
    pcall(function()
        added = exports.ox_inventory:AddItem(src, selected.item_name, qty) == true
    end)

    if not added then
        if total > 0 then
            player.Functions.AddMoney(payType, total, '직업 도구 상점 구매 실패 환불')
        end
        return notify(src, '상품 지급에 실패했습니다. 결제 금액은 환불됐습니다.', true)
    end

    notify(src, ('%s x%d 구매 완료 (-%s원)'):format(selected.label, qty, total), false)
end)
