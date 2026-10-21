-- Cookie faction shop NPCs
-- V2: streamed client peds + editable idle scenario + custom shop HUD support.
-- Catalog price/item identity stays server-authoritative.

local MAX_NPCS_PER_FACTION = 15
local MAX_BUY_QTY = 20

local function validAdmin(src, fid)
    local a = CookieAdminTeamAuth(src, 'faction')
    fid = tonumber(fid)
    if not a or not fid or fid % 1 ~= 0 or fid < 1 then return nil end
    local ok = MySQL.scalar.await('SELECT id FROM cookie_faction WHERE id=? AND is_active=1', { fid })
    return ok and fid or nil
end

local function validId(v)
    v = tonumber(v)
    if not v or v % 1 ~= 0 or v < 1 then return nil end
    return v
end

local function validModel(value)
    local model = tostring(value or 'a_m_y_business_01')
    if #model < 3 or #model > 60 or not model:match('^[%w_]+$') then return nil end
    return model
end

local function validScenario(value)
    local scenario = tostring(value or 'WORLD_HUMAN_STAND_MOBILE'):upper()
    if scenario == '' or scenario == 'NONE' then return 'NONE' end
    if #scenario < 3 or #scenario > 64 or not scenario:match('^[A-Z0-9_]+$') then return nil end
    return scenario
end

local function npcRows(where, args)
    return MySQL.query.await(([=[
        SELECT n.id,n.faction_id,n.label,n.model,n.scenario,n.x,n.y,n.z,n.heading,
               f.name AS faction_name,f.color AS faction_color,f.emoji AS faction_emoji
        FROM cookie_faction_npc n
        INNER JOIN cookie_faction f ON f.id=n.faction_id
        WHERE f.is_active=1 %s
        ORDER BY n.id
    ]=]):format(where or ''), args or {}) or {}
end

local function broadcast()
    TriggerClientEvent('cookie_admin:factionNpcSync', -1, npcRows())
end

local function adminData(src, fid)
    TriggerClientEvent('cookie_admin:factionNpcAdminData', src, fid,
        MySQL.query.await([[SELECT id,label,model,scenario,x,y,z,heading
            FROM cookie_faction_npc WHERE faction_id=? ORDER BY id]], { fid }) or {})
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_faction_npc (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        faction_id INT NOT NULL,
        label VARCHAR(60) NOT NULL,
        model VARCHAR(60) NOT NULL,
        scenario VARCHAR(64) NOT NULL DEFAULT 'WORLD_HUMAN_STAND_MOBILE',
        x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,heading DOUBLE NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY faction_idx (faction_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[ALTER TABLE cookie_faction_npc
        ADD COLUMN IF NOT EXISTS scenario VARCHAR(64) NOT NULL DEFAULT 'WORLD_HUMAN_STAND_MOBILE' AFTER model]])
    Wait(1000)
    broadcast()
end)

RegisterNetEvent('cookie_admin:factionNpcSyncRequest', function()
    TriggerClientEvent('cookie_admin:factionNpcSync', source, npcRows())
end)

RegisterNetEvent('cookie_admin:factionNpcAdminList', function(fid)
    local src = source
    fid = validAdmin(src, fid)
    if not fid then return end
    adminData(src, fid)
end)

-- Create a new NPC or move an existing NPC to the admin's current position/heading.
RegisterNetEvent('cookie_admin:factionNpcAdminPlace', function(d)
    local src = source
    if type(d) ~= 'table' then return end
    local fid = validAdmin(src, d.factionId)
    if not fid then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pos = GetEntityCoords(ped)
    if not pos then return end
    local heading = GetEntityHeading(ped)

    local id = validId(d.id)
    if id then
        MySQL.update.await([[UPDATE cookie_faction_npc SET x=?,y=?,z=?,heading=?
            WHERE id=? AND faction_id=?]], { pos.x, pos.y, pos.z, heading, id, fid })
    else
        local label = tostring(d.label or '팩션 판매 담당자'):sub(1, 60)
        local model = validModel(d.model)
        local scenario = validScenario(d.scenario)
        if not model or not scenario then return end

        local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cookie_faction_npc WHERE faction_id=?', { fid })) or 0
        if count >= MAX_NPCS_PER_FACTION then return end

        MySQL.insert.await([[INSERT INTO cookie_faction_npc
            (faction_id,label,model,scenario,x,y,z,heading) VALUES (?,?,?,?,?,?,?,?)]],
            { fid, label, model, scenario, pos.x, pos.y, pos.z, heading })
    end

    adminData(src, fid)
    broadcast()
end)

-- Edit an installed NPC without needing to delete/recreate it.
RegisterNetEvent('cookie_admin:factionNpcAdminUpdate', function(d)
    local src = source
    if type(d) ~= 'table' then return end
    local fid = validAdmin(src, d.factionId)
    local id = validId(d.id)
    if not fid or not id then return end

    local label = tostring(d.label or '팩션 판매 담당자'):sub(1, 60)
    local model = validModel(d.model)
    local scenario = validScenario(d.scenario)
    if #label < 1 or not model or not scenario then return end

    MySQL.update.await([[UPDATE cookie_faction_npc SET label=?,model=?,scenario=?
        WHERE id=? AND faction_id=?]], { label, model, scenario, id, fid })
    adminData(src, fid)
    broadcast()
end)

RegisterNetEvent('cookie_admin:factionNpcAdminDelete', function(d)
    local src = source
    if type(d) ~= 'table' then return end
    local fid = validAdmin(src, d.factionId)
    local id = validId(d.id)
    if not fid or not id then return end
    MySQL.update.await('DELETE FROM cookie_faction_npc WHERE id=? AND faction_id=?', { id, fid })
    adminData(src, fid)
    broadcast()
end)

local lastOpen = {}
lib.callback.register('cookie_admin:factionNpcItems', function(src, npcId)
    npcId = validId(npcId)
    if not npcId then return { error = 'NPC를 찾지 못했습니다.' } end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { error = '플레이어를 찾지 못했습니다.' } end

    local npc = MySQL.single.await([[SELECT n.*,f.name AS faction_name,f.color AS faction_color,
            f.emoji AS faction_emoji
        FROM cookie_faction_npc n
        INNER JOIN cookie_faction f ON f.id=n.faction_id
        WHERE n.id=? AND f.is_active=1]], { npcId })
    if not npc then return { error = '비활성화된 NPC입니다.' } end

    local p = GetEntityCoords(ped)
    if #(p - vector3(npc.x, npc.y, npc.z)) > 4.0 then return { error = 'NPC에서 너무 멉니다.' } end

    -- Keep the existing faction-shop rule: only members of this faction can use its NPC shop.
    local ok, membership = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    if not ok or not membership or tonumber(membership.id) ~= tonumber(npc.faction_id) then
        return { error = '지정된 팩션 소속자만 사용할 수 있습니다.' }
    end

    local now = os.time()
    if lastOpen[src] and now - lastOpen[src] < 1 then return { error = '잠시 후 다시 시도하세요.' } end
    lastOpen[src] = now

    local items = MySQL.query.await([[SELECT item_code,label,description,price
        FROM cookie_intranet_catalog
        WHERE faction_id=? AND active=1
        ORDER BY id DESC LIMIT 200]], { npc.faction_id }) or {}

    -- Reuse ox_inventory artwork in the custom shop HUD.
    for _, item in ipairs(items) do
        local defOk, definition = pcall(function() return exports.ox_inventory:Items(item.item_code) end)
        if defOk and definition then
            local client = type(definition.client) == 'table' and definition.client or {}
            item.image = tostring(client.image or definition.image or (tostring(item.item_code) .. '.png'))
        else
            item.image = tostring(item.item_code) .. '.png'
        end
    end

    local cash = 0
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.money then
        cash = tonumber(player.PlayerData.money.cash) or 0
    end

    return {
        npcId = npc.id,
        label = npc.label,
        factionName = npc.faction_name,
        factionColor = npc.faction_color,
        factionEmoji = npc.faction_emoji,
        cash = cash,
        items = items,
    }
end)

-- Infinite-stock cash shop. Never trust client item, price, distance or membership.
local buyBusy = {}
local buyLast = {}

local function purchaseResult(ok, msg, extra)
    local r = { ok = ok, message = msg }
    if type(extra) == 'table' then
        for k, v in pairs(extra) do r[k] = v end
    end
    return r
end

local function playerAtNpc(src, npcId)
    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed == 0 then return nil, '플레이어를 찾을 수 없습니다.' end

    local npc = MySQL.single.await([[SELECT n.id,n.faction_id,n.x,n.y,n.z,n.label
        FROM cookie_faction_npc n
        INNER JOIN cookie_faction f ON f.id=n.faction_id
        WHERE n.id=? AND f.is_active=1]], { npcId })
    if not npc then return nil, '사용할 수 없는 NPC입니다.' end

    local pos = GetEntityCoords(playerPed)
    if not pos or #(pos - vector3(tonumber(npc.x), tonumber(npc.y), tonumber(npc.z))) > 4.0 then
        return nil, 'NPC 근처에서 이용해 주세요.'
    end

    local ok, membership = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    if not ok or not membership or tonumber(membership.id) ~= tonumber(npc.faction_id) then
        return nil, '이 팩션에 소속된 직원만 이용할 수 있습니다.'
    end
    return npc
end

lib.callback.register('cookie_admin:factionNpcPurchase', function(src, npcId, itemCode, quantity)
    npcId = validId(npcId)
    quantity = tonumber(quantity)
    if not npcId or type(itemCode) ~= 'string' or #itemCode > 80 or not itemCode:match('^[%w_:%-]+$')
        or not quantity or quantity % 1 ~= 0 or quantity < 1 or quantity > MAX_BUY_QTY then
        return purchaseResult(false, ('잘못된 구매 요청입니다. (1~%d개)'):format(MAX_BUY_QTY))
    end

    if buyBusy[src] then return purchaseResult(false, '이전 구매를 처리 중입니다.') end
    local now = GetGameTimer()
    if buyLast[src] and now - buyLast[src] < 500 then return purchaseResult(false, '잠시 후 다시 시도해 주세요.') end

    buyBusy[src] = true
    buyLast[src] = now

    local ok, result = pcall(function()
        local npc, reason = playerAtNpc(src, npcId)
        if not npc then return purchaseResult(false, reason) end

        local catalog = MySQL.single.await([[SELECT item_code,label,price
            FROM cookie_intranet_catalog
            WHERE faction_id=? AND item_code=? AND active=1 LIMIT 1]], { npc.faction_id, itemCode })
        if not catalog then return purchaseResult(false, '현재 판매하지 않는 품목입니다.') end

        local price = tonumber(catalog.price)
        if not price or price < 0 or price % 1 ~= 0 or price > 2000000000 then
            return purchaseResult(false, '판매 가격 설정이 올바르지 않습니다.')
        end
        local total = price * quantity
        if total > 2000000000 then return purchaseResult(false, '한 번에 구매할 수 있는 금액을 초과했습니다.') end

        local existsOk, definition = pcall(function() return exports.ox_inventory:Items(itemCode) end)
        if not existsOk or not definition then
            return purchaseResult(false, ('아이템 코드 %s 가 ox_inventory에 등록되지 않았습니다.'):format(itemCode))
        end

        local carryOk, canCarry = pcall(function() return exports.ox_inventory:CanCarryItem(src, itemCode, quantity) end)
        if not carryOk or not canCarry then return purchaseResult(false, '인벤토리 공간이나 무게가 부족합니다.') end

        local player = exports.qbx_core:GetPlayer(src)
        if not player or not player.Functions then return purchaseResult(false, '플레이어 정보를 불러오지 못했습니다.') end

        if total > 0 then
            local paidOk, paid = pcall(function()
                return player.Functions.RemoveMoney('cash', total, '팩션 NPC 구매')
            end)
            if not paidOk or not paid then
                local money = player.PlayerData and player.PlayerData.money or {}
                return purchaseResult(false, ('현금이 부족합니다. 필요 금액: %d원'):format(total), {
                    cash = tonumber(money and money.cash) or 0
                })
            end
        end

        local giveOk, given = pcall(function() return exports.ox_inventory:AddItem(src, itemCode, quantity) end)
        if not giveOk or not given then
            if total > 0 then
                local refundedOk, refunded = pcall(function()
                    return player.Functions.AddMoney('cash', total, '팩션 NPC 지급 실패 환불')
                end)
                if not refundedOk or not refunded then
                    print(('[cookie_admin] CRITICAL factionNpc refund failure player=%d npc=%d item=%s total=%d')
                        :format(src, npcId, itemCode, total))
                    return purchaseResult(false, '지급 오류와 환불 실패가 발생했습니다. 관리자에게 문의해 주세요.')
                end
            end
            return purchaseResult(false, '아이템 지급에 실패하여 결제가 환불됐습니다.')
        end

        local money = player.PlayerData and player.PlayerData.money or {}
        local cash = tonumber(money and money.cash) or 0
        print(('[cookie_admin] factionNpc purchase player=%d npc=%d faction=%d item=%s qty=%d cash=%d')
            :format(src, npcId, npc.faction_id, itemCode, quantity, total))
        return purchaseResult(true, ('%s %d개 구매 완료'):format(tostring(catalog.label), quantity), {
            cash = cash,
            paid = total,
            itemCode = itemCode,
            quantity = quantity,
        })
    end)

    buyBusy[src] = nil
    if not ok then
        print(('[cookie_admin] factionNpc purchase error player=%d: %s'):format(src, tostring(result)))
        return purchaseResult(false, '구매 처리 중 서버 오류가 발생했습니다.')
    end
    return result
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastOpen[src] = nil
    buyBusy[src] = nil
    buyLast[src] = nil
end)
