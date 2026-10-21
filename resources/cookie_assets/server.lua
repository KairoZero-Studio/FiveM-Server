local placed = {}
local workReady = false
local seated = {}

local function notify(src, msg, bad)
    TriggerClientEvent('cookie_admin:client:notify', src, tostring(msg or ''), bad == true)
end

local function playerCid(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData and tostring(p.PlayerData.citizenid or '') or nil
end

local function decodeFurnitureKey(key)
    key = tostring(key or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local prefix, model = key:match('^(%a+)%:(.+)$')
    if prefix == 'chair' or prefix == 'decor' then
        return model, prefix == 'chair'
    end
    return key, true
end

local function decodeCosmeticKey(key)
    key = tostring(key or ''):lower():gsub('%s+', '')
    local slot, drawable, texture = key:match('^prop:(%d+):(%-?%d+):(%d+)$')
    slot, drawable, texture = tonumber(slot), tonumber(drawable), tonumber(texture)
    if not slot or not drawable or not texture then return nil end
    if slot < 0 or slot > (Config.Cosmetic.MaxPropSlot or 7) then return nil end
    return {
        slot = slot,
        drawable = drawable,
        texture = texture,
        slotKey = ('prop:%d'):format(slot),
        raw = key
    }
end

local function refreshStorage(src)
    if GetResourceState('cookie_admin') ~= 'started' then return end
    local ok, data = pcall(function()
        return exports.cookie_admin:GetPersonalStorage(src)
    end)
    if ok and data then
        TriggerClientEvent('cookie_admin:client:personalStorage', src, data)
    end
end

local function loadPlaced()
    placed = {}
    local rows = MySQL.query.await([[
        SELECT id,citizenid,owned_id,model,label,x,y,z,heading,sit_enabled
        FROM cookie_furniture_placed
        ORDER BY id
    ]]) or {}
    for _, r in ipairs(rows) do
        placed[tonumber(r.id)] = {
            id = tonumber(r.id),
            citizenid = tostring(r.citizenid or ''),
            ownedId = tonumber(r.owned_id),
            model = tostring(r.model or ''),
            label = tostring(r.label or r.model or '가구'),
            x = tonumber(r.x) or 0.0,
            y = tonumber(r.y) or 0.0,
            z = tonumber(r.z) or 0.0,
            heading = tonumber(r.heading) or 0.0,
            sit = tonumber(r.sit_enabled) == 1
        }
    end
end

local function syncAll(target)
    TriggerClientEvent('cookie_assets:client:syncFurniture', target or -1, placed)
end

CreateThread(function()
    Wait(1200)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_furniture_placed (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(64) NOT NULL,
            owned_id BIGINT UNSIGNED NOT NULL,
            model VARCHAR(100) NOT NULL,
            label VARCHAR(100) NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            heading FLOAT NOT NULL DEFAULT 0,
            sit_enabled TINYINT(1) NOT NULL DEFAULT 1,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_cookie_furniture_owned (owned_id),
            KEY idx_cookie_furniture_owner (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_cosmetic_equipped (
            citizenid VARCHAR(64) NOT NULL,
            slot_key VARCHAR(24) NOT NULL,
            owned_id BIGINT UNSIGNED NOT NULL,
            reward_key VARCHAR(100) NOT NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (citizenid,slot_key),
            UNIQUE KEY uq_cookie_cosmetic_owned (owned_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    loadPlaced()
    workReady = true
    syncAll(-1)
    print('^2[cookie_assets]^7 furniture + cosmetic V1.0.0 ready')
end)

lib.callback.register('cookie_assets:validateFurniture', function(src, ownedId)
    local cid = playerCid(src)
    ownedId = tonumber(ownedId)
    if not cid or not ownedId then return { ok=false, message='가구 정보를 확인할 수 없습니다.' } end

    local r = MySQL.single.await([[
        SELECT id,reward_key,label,state
        FROM cookie_kuji_owned
        WHERE id=? AND citizenid=? AND reward_type='furniture'
        LIMIT 1
    ]], { ownedId, cid })

    if not r then return { ok=false, message='보유한 의자·가구가 아닙니다.' } end
    if tostring(r.state or '') ~= 'packed' then
        return { ok=false, message='이미 설치되어 있거나 사용할 수 없는 상태입니다.' }
    end

    local model, sit = decodeFurnitureKey(r.reward_key)
    if model == '' then return { ok=false, message='가구 모델 코드가 비어 있습니다.' } end
    return { ok=true, ownedId=ownedId, model=model, sit=sit, label=tostring(r.label or model) }
end)

RegisterNetEvent('cookie_assets:server:requestSync', function()
    local src = source
    syncAll(src)

    local cid = playerCid(src)
    if not cid then return end
    TriggerClientEvent('cookie_assets:client:setOwnCitizenid', src, cid)
    local cosmetics = MySQL.query.await([[
        SELECT slot_key,reward_key,owned_id
        FROM cookie_cosmetic_equipped
        WHERE citizenid=?
    ]], { cid }) or {}
    TriggerClientEvent('cookie_assets:client:syncCosmetics', src, cosmetics)
end)

RegisterNetEvent('cookie_assets:server:placeFurniture', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local cid = playerCid(src)
    local ownedId = tonumber(data.ownedId)
    if not cid or not ownedId then return end

    local row = MySQL.single.await([[
        SELECT id,reward_key,label,state
        FROM cookie_kuji_owned
        WHERE id=? AND citizenid=? AND reward_type='furniture'
        LIMIT 1
    ]], { ownedId, cid })
    if not row or tostring(row.state or '') ~= 'packed' then
        return notify(src, '설치할 수 없는 가구입니다.', true)
    end

    local model, sit = decodeFurnitureKey(row.reward_key)
    local x,y,z,h = tonumber(data.x), tonumber(data.y), tonumber(data.z), tonumber(data.heading)
    if not x or not y or not z or not h then return notify(src, '설치 좌표가 올바르지 않습니다.', true) end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local pc = GetEntityCoords(ped)
        local dx,dy,dz = pc.x-x, pc.y-y, pc.z-z
        if math.sqrt(dx*dx+dy*dy+dz*dz) > (Config.Furniture.MaxPlaceDistance or 4.0) then
            return notify(src, '너무 먼 곳에는 설치할 수 없습니다.', true)
        end
    end

    local changed = MySQL.update.await([[
        UPDATE cookie_kuji_owned
        SET state='placed'
        WHERE id=? AND citizenid=? AND reward_type='furniture' AND state='packed'
    ]], { ownedId, cid })
    if not changed or changed < 1 then return notify(src, '가구 상태가 변경되어 설치하지 못했습니다.', true) end

    local ok, newId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO cookie_furniture_placed
              (citizenid,owned_id,model,label,x,y,z,heading,sit_enabled)
            VALUES (?,?,?,?,?,?,?,?,?)
        ]], { cid, ownedId, model, tostring(row.label or model), x,y,z,h, sit and 1 or 0 })
    end)
    if not ok or not newId then
        MySQL.update.await("UPDATE cookie_kuji_owned SET state='packed' WHERE id=? AND citizenid=?", { ownedId, cid })
        return notify(src, '가구 설치 저장에 실패했습니다.', true)
    end

    local info = {
        id=tonumber(newId), citizenid=cid, ownedId=ownedId, model=model,
        label=tostring(row.label or model), x=x,y=y,z=z,heading=h,sit=sit
    }
    placed[tonumber(newId)] = info
    TriggerClientEvent('cookie_assets:client:addFurniture', -1, info)
    refreshStorage(src)
    notify(src, ('%s을(를) 설치했습니다.'):format(info.label), false)
end)

RegisterNetEvent('cookie_assets:server:pickupFurniture', function(id)
    local src = source
    local cid = playerCid(src)
    id = tonumber(id)
    local r = id and placed[id] or nil
    if not cid or not r then return end
    if r.citizenid ~= cid then return notify(src, '본인 소유 가구만 회수할 수 있습니다.', true) end

    for sid, fid in pairs(seated) do
        if tonumber(fid) == id then
            return notify(src, '현재 누군가 앉아 있는 의자는 회수할 수 없습니다.', true)
        end
    end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local pc = GetEntityCoords(ped)
        local dx,dy,dz = pc.x-r.x, pc.y-r.y, pc.z-r.z
        if math.sqrt(dx*dx+dy*dy+dz*dz) > (Config.Furniture.PickupDistance or 2.25) + 1.0 then
            return notify(src, '가구 가까이에서 회수해주세요.', true)
        end
    end

    MySQL.query.await('DELETE FROM cookie_furniture_placed WHERE id=? AND citizenid=?', { id, cid })
    MySQL.update.await("UPDATE cookie_kuji_owned SET state='packed' WHERE id=? AND citizenid=?", { r.ownedId, cid })
    placed[id] = nil
    TriggerClientEvent('cookie_assets:client:removeFurniture', -1, id)
    refreshStorage(src)
    notify(src, '가구를 보관함으로 회수했습니다.', false)
end)

RegisterNetEvent('cookie_assets:server:toggleCosmetic', function(rawOwnedId)
    local src = source
    local cid = playerCid(src)
    local ownedId = tonumber(rawOwnedId)
    if not cid or not ownedId then return end

    local row = MySQL.single.await([[
        SELECT id,reward_key,label,state
        FROM cookie_kuji_owned
        WHERE id=? AND citizenid=? AND reward_type='cosmetic'
        LIMIT 1
    ]], { ownedId, cid })
    if not row then return notify(src, '보유한 치장이 아닙니다.', true) end

    local cos = decodeCosmeticKey(row.reward_key)
    if not cos then
        return notify(src, '치장 코드 형식이 올바르지 않습니다. prop:슬롯:drawable:texture 형식을 사용하세요.', true)
    end

    local current = MySQL.single.await([[
        SELECT owned_id,reward_key FROM cookie_cosmetic_equipped
        WHERE citizenid=? AND slot_key=? LIMIT 1
    ]], { cid, cos.slotKey })

    if current and tonumber(current.owned_id) == ownedId then
        MySQL.query.await('DELETE FROM cookie_cosmetic_equipped WHERE citizenid=? AND slot_key=?', { cid, cos.slotKey })
        MySQL.update.await("UPDATE cookie_kuji_owned SET state='packed' WHERE id=? AND citizenid=?", { ownedId, cid })
        TriggerClientEvent('cookie_assets:client:clearCosmetic', src, cos.slot)
        refreshStorage(src)
        return notify(src, ('%s 치장을 해제했습니다.'):format(tostring(row.label or '')), false)
    end

    if current and tonumber(current.owned_id) then
        MySQL.update.await("UPDATE cookie_kuji_owned SET state='packed' WHERE id=? AND citizenid=?", { tonumber(current.owned_id), cid })
    end

    MySQL.query.await([[
        INSERT INTO cookie_cosmetic_equipped (citizenid,slot_key,owned_id,reward_key)
        VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE owned_id=VALUES(owned_id),reward_key=VALUES(reward_key)
    ]], { cid, cos.slotKey, ownedId, cos.raw })
    MySQL.update.await("UPDATE cookie_kuji_owned SET state='equipped' WHERE id=? AND citizenid=?", { ownedId, cid })

    TriggerClientEvent('cookie_assets:client:applyCosmetic', src, cos)
    refreshStorage(src)
    notify(src, ('%s 치장을 장착했습니다.'):format(tostring(row.label or '')), false)
end)

RegisterNetEvent('cookie_assets:server:seatState', function(furnitureId, isSeated)
    local src = source
    if not isSeated then
        seated[src] = nil
        return
    end

    local id = tonumber(furnitureId)
    local info = id and placed[id] or nil
    if not info or info.sit ~= true then
        seated[src] = nil
        return
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pc = GetEntityCoords(ped)
    local dx,dy,dz = pc.x-info.x, pc.y-info.y, pc.z-info.z
    if math.sqrt(dx*dx+dy*dy+dz*dz) > 3.0 then
        seated[src] = nil
        return
    end
    seated[src] = id
end)

CreateThread(function()
    while true do
        Wait(math.max(10, math.floor(tonumber(Config.Furniture.RecoverEverySeconds) or 60)) * 1000)
        for src, id in pairs(seated) do
            src = tonumber(src)
            local info = placed[tonumber(id)]
            local player = src and exports.qbx_core:GetPlayer(src) or nil
            local ped = src and GetPlayerPed(src) or 0
            local valid = info and info.sit == true and player and ped and ped ~= 0
            if valid then
                local pc = GetEntityCoords(ped)
                local dx,dy,dz = pc.x-info.x, pc.y-info.y, pc.z-info.z
                valid = math.sqrt(dx*dx+dy*dy+dz*dz) <= 3.0
            end

            if not valid then
                seated[src] = nil
            else
                local meta = player.PlayerData and player.PlayerData.metadata or {}
                local hunger = tonumber(meta.hunger) or 100
                local thirst = tonumber(meta.thirst) or 100
                local addH = math.max(0, tonumber(Config.Furniture.RecoverHunger) or 5)
                local addT = math.max(0, tonumber(Config.Furniture.RecoverThirst) or 5)
                if hunger < 100 then player.Functions.SetMetaData('hunger', math.min(100, hunger + addH)) end
                if thirst < 100 then player.Functions.SetMetaData('thirst', math.min(100, thirst + addT)) end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    seated[source] = nil
end)

AddEventHandler('onResourceStart', function(name)
    if name == GetCurrentResourceName() and workReady then
        syncAll(-1)
    end
end)
