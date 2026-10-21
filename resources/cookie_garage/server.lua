print('^2[cookie_garage]^7 V5.0.0 standalone server loading')

local PERSONAL_GARAGE = 'cookie_personal_v2'
local GENERAL_RESALE_RATE = 0.40

local zoneContexts = {}
local spawnLocks = {}
local storeLocks = {}
local saleLocks = {}

math.randomseed(os.time())

CreateThread(function()
    pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_tow_impound (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, faction_id INT NOT NULL, vehicle_id INT NOT NULL,
            citizenid VARCHAR(64) NOT NULL, plate VARCHAR(32) NOT NULL, model VARCHAR(80) NOT NULL, reason VARCHAR(300) NOT NULL,
            fee BIGINT NOT NULL DEFAULT 0, active TINYINT(1) NOT NULL DEFAULT 1, impounded_by VARCHAR(64) NOT NULL,
            impounded_name VARCHAR(100) NOT NULL, released_by VARCHAR(64) DEFAULT NULL, released_name VARCHAR(100) DEFAULT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, released_at TIMESTAMP NULL DEFAULT NULL,
            INDEX idx_active_vehicle (vehicle_id,active), INDEX idx_faction_active (faction_id,active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end)
end)

local function rstate(name) return GetResourceState(name) end
local function started(name) return rstate(name) == 'started' end

local function q(sql, params)
    local ok, result = pcall(function() return MySQL.query.await(sql, params or {}) end)
    if not ok then
        print(('[cookie_garage] DB ERROR: %s'):format(tostring(result)))
        return nil
    end
    return result
end

local function one(sql, params)
    local ok, result = pcall(function() return MySQL.single.await(sql, params or {}) end)
    if not ok then
        print(('[cookie_garage] DB ERROR: %s'):format(tostring(result)))
        return nil
    end
    return result
end

local function scalar(sql, params)
    local ok, result = pcall(function() return MySQL.scalar.await(sql, params or {}) end)
    if not ok then
        print(('[cookie_garage] DB ERROR: %s'):format(tostring(result)))
        return nil
    end
    return result
end

local function player(src)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return ok and p or nil
end

local function cid(src)
    local p = player(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function normModel(v) return tostring(v or ''):lower():gsub('%s+', '') end
local function trimPlate(v) return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '') end
local function plateKey(v) return trimPlate(v):upper():gsub('%s+', '') end

local function samePlate(a, b)
    local aa, bb = plateKey(a), plateKey(b)
    return aa ~= '' and aa == bb
end

local function vecDistance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function nearZone(src, ctx, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not ctx or not ctx.coords then return false end
    return vecDistance(GetEntityCoords(ped), vec3(ctx.coords.x, ctx.coords.y, ctx.coords.z)) <= (maxDistance or 12.0)
end

local function allowAction(src, key, windowMs, maxCount)
    if started('cookie_core') then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

local function factionGarageKey(row)
    if not row then return nil end
    if row.garage_key and row.garage_key ~= '' then return row.garage_key end
    if row.faction_type == 'police' then return 'cookie_lspd' end
    return 'cookie_' .. tostring(row.faction_key or row.faction_id or row.id)
end

local function membership(citizenid, wantedFactionId)
    if not citizenid then return nil end
    local row = one([[
        SELECT m.faction_id AS id,m.grade,m.duty,r.rank_name,
               f.name,f.faction_key,f.faction_type,f.garage_key
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id=m.faction_id AND f.is_active=1
        LEFT JOIN cookie_faction_rank r ON r.faction_id=m.faction_id AND r.grade=m.grade
        WHERE m.citizenid=? AND m.status='active'
        LIMIT 1
    ]], {citizenid})

    if not row then return nil end
    if wantedFactionId and tonumber(row.id) ~= tonumber(wantedFactionId) then return nil end
    return row
end

local function garageZones()
    return q([[
        SELECT z.id,z.center_x,z.center_y,z.center_z,z.heading,z.label,z.type,z.faction_id,
               f.name AS faction_name,f.faction_key,f.faction_type,f.garage_key
        FROM cookie_zone z
        LEFT JOIN cookie_faction f ON f.id=z.faction_id AND f.is_active=1
        WHERE z.is_active=1 AND z.type IN ('garage','garage_lspd','garage_lssd')
        ORDER BY z.id
    ]], {}) or {}
end

local function refreshZoneContexts()
    local contexts = {}
    for _, z in ipairs(garageZones()) do
        local fid = tonumber(z.faction_id)
        local isFaction = fid and fid > 0 and z.faction_name ~= nil
        local garageName = PERSONAL_GARAGE
        local label = z.label or '쿠키 차고'

        if isFaction then
            garageName = factionGarageKey(z)
            label = (z.faction_name or label) .. ' 차고'
        end

        contexts[tonumber(z.id)] = {
            zoneId = tonumber(z.id),
            mode = isFaction and 'faction' or 'civilian',
            factionId = isFaction and fid or nil,
            factionName = isFaction and z.faction_name or nil,
            garageName = garageName,
            label = label,
            coords = vec4(
                tonumber(z.center_x) or 0.0,
                tonumber(z.center_y) or 0.0,
                tonumber(z.center_z) or 0.0,
                tonumber(z.heading) or 0.0
            )
        }
    end

    zoneContexts = contexts
    local count = 0
    for _ in pairs(zoneContexts) do count = count + 1 end
    print(('[cookie_garage] zone cache ready: %d beacon(s) · qbx_garages/qbx_vehicles not required'):format(count))
    return count
end

local function context(zoneId)
    zoneId = tonumber(zoneId)
    if not zoneId then return nil end
    if zoneContexts[zoneId] then return zoneContexts[zoneId] end
    refreshZoneContexts()
    return zoneContexts[zoneId]
end

AddEventHandler('cookie_garage:server:invalidateAccessPoints', refreshZoneContexts)

local function imgs()
    local out = {}
    for _, r in ipairs(q('SELECT model,image FROM cookie_vehicle_image', {}) or {}) do
        out[normModel(r.model)] = r.image
    end
    return out
end

local function generalCatalog(image)
    local rows = q([[
        SELECT id,LOWER(model) AS model,display_name AS label,price,spec,image,sort_order
        FROM cookie_dealership_vehicles
        WHERE active=1
        ORDER BY sort_order,id
    ]], {}) or {}

    for _, v in ipairs(rows) do
        v.model = normModel(v.model)
        v.price = math.max(0, math.floor(tonumber(v.price) or 0))
        v.image = image[v.model] or v.image
    end
    return rows
end

local function limitedMap(image)
    local out = {}
    for _, v in ipairs(q("SELECT LOWER(model) AS model,label FROM cookie_limited_vehicles WHERE active=1", {}) or {}) do
        local model = normModel(v.model)
        out[model] = {model=model,label=v.label or model,image=image[model]}
    end
    return out
end

local function buildCivilian(ctx, citizenid, image)
    local general = generalCatalog(image)
    local gmap = {}
    for _, v in ipairs(general) do gmap[v.model] = v end
    local limited = limitedMap(image)

    local owned = q([[
        SELECT pv.id,pv.vehicle AS model,pv.plate,pv.garage,pv.state
        FROM player_vehicles pv
        WHERE pv.citizenid=? AND pv.state=1
          AND NOT EXISTS (SELECT 1 FROM cookie_tow_impound ti WHERE ti.vehicle_id=pv.id AND ti.active=1)
        ORDER BY pv.id DESC
    ]], {citizenid}) or {}

    local allModels = q("SELECT DISTINCT vehicle AS model FROM player_vehicles WHERE citizenid=?", {citizenid}) or {}
    local ownedModels = {}
    for _, r in ipairs(allModels) do
        local m = normModel(r.model)
        if m ~= '' then ownedModels[#ownedModels + 1] = m end
    end

    local ownedGeneral, ownedLimited = {}, {}

    for _, r in ipairs(owned) do
        local model = normModel(r.model)
        local dealer = gmap[model]

        if limited[model] then
            ownedLimited[#ownedLimited + 1] = {
                id=tonumber(r.id),model=model,plate=r.plate,image=image[model],
                label=limited[model].label or (dealer and dealer.label) or model
            }
        else
            local buyPrice = dealer and (tonumber(dealer.price) or 0) or 0
            ownedGeneral[#ownedGeneral + 1] = {
                id=tonumber(r.id),model=model,plate=r.plate,
                image=(dealer and dealer.image) or image[model],
                label=(dealer and dealer.label) or model,
                buyPrice=buyPrice,
                sellPrice=math.floor(buyPrice * GENERAL_RESALE_RATE),
                sellRate=GENERAL_RESALE_RATE,
                canSell=buyPrice > 0
            }
        end
    end

    return {
        mode='civilian',
        title=ctx.label or '쿠키 차고',
        garageName=PERSONAL_GARAGE,
        general=general,
        ownedGeneral=ownedGeneral,
        ownedLimited=ownedLimited,
        ownedModels=ownedModels
    }
end

local function buildFaction(ctx, citizenid, image)
    local mem = membership(citizenid, ctx.factionId)
    if not mem then return nil, '해당 팩션 소속만 이 차고를 사용할 수 있습니다' end

    local fid = tonumber(ctx.factionId)
    local grade = math.max(0, math.floor(tonumber(mem.grade) or 0))
    local ownerCid = 'FACTION_' .. tostring(fid)

    local rows = q([[
        SELECT pv.id,LOWER(pv.vehicle) AS model,pv.plate,pv.garage,pv.state,
               COALESCE(fs.label,pv.vehicle) AS label,
               COALESCE(fv.min_grade,fs.min_grade,0) AS min_grade,
               rr.rank_name
        FROM player_vehicles pv
        JOIN cookie_faction_vehicle fv ON fv.faction_id=? AND LOWER(fv.model)=LOWER(pv.vehicle)
        LEFT JOIN cookie_faction_shop fs ON fs.faction_id=? AND fs.active=1 AND LOWER(fs.model)=LOWER(pv.vehicle)
        LEFT JOIN cookie_faction_rank rr ON rr.faction_id=? AND rr.grade=COALESCE(fv.min_grade,fs.min_grade,0)
        WHERE pv.citizenid=? AND pv.state=1
          AND COALESCE(fv.min_grade,fs.min_grade,0)<=?
        ORDER BY COALESCE(fv.min_grade,fs.min_grade,0),label,pv.id
    ]], {fid,fid,fid,ownerCid,grade}) or {}

    for _, v in ipairs(rows) do
        v.model=normModel(v.model)
        v.id=tonumber(v.id)
        v.min_grade=tonumber(v.min_grade) or 0
        v.image=image[v.model]
    end

    return {
        mode='faction',
        title=(ctx.factionName or mem.name or '팩션') .. ' 차고',
        garageName=ctx.garageName,
        faction={id=fid,name=ctx.factionName or mem.name or '팩션',grade=grade,rankName=mem.rank_name},
        ownedFaction=rows
    }
end

local function build(src, zoneId)
    local citizenid = cid(src)
    if not citizenid then return nil, '캐릭터 정보를 불러오지 못했습니다' end

    local ctx = context(zoneId)
    if not ctx then return nil, '등록되지 않은 차고 비콘입니다' end
    if not nearZone(src, ctx, 12.0) then return nil, '차고 비콘에서 너무 멉니다' end

    local image = imgs()
    if ctx.mode == 'faction' then return buildFaction(ctx, citizenid, image) end
    return buildCivilian(ctx, citizenid, image)
end

RegisterNetEvent('cookie_garage:server:requestOpen', function(zoneId)
    local src=source
    local ok,data,err=pcall(function()
        local d,e=build(src,zoneId)
        return d,e
    end)

    if not ok then
        print(('[cookie_garage] open exception src=%s: %s'):format(src,tostring(data)))
        TriggerClientEvent('cookie_garage:client:openFailed',src,'차고 정보를 불러오는 중 서버 오류가 발생했습니다')
        return
    end

    if not data then
        TriggerClientEvent('cookie_garage:client:openFailed',src,err or '차고를 열 수 없습니다')
        return
    end

    TriggerClientEvent('cookie_garage:client:openData',src,data)
end)

local function decodeProps(row)
    local props={}
    if type(row.mods)=='string' and row.mods~='' then
        local ok,decoded=pcall(json.decode,row.mods)
        if ok and type(decoded)=='table' then props=decoded end
    elseif type(row.mods)=='table' then
        props=row.mods
    end

    local modelHash=joaat(normModel(row.vehicle))
    props.model=modelHash
    props.plate=trimPlate(row.plate)
    if props.engineHealth==nil then props.engineHealth=tonumber(row.engine) or 1000.0 end
    if props.bodyHealth==nil then props.bodyHealth=tonumber(row.body) or 1000.0 end
    if props.fuelLevel==nil then props.fuelLevel=tonumber(row.fuel) or 100.0 end
    props.lockState=1
    return props,modelHash
end

local function isAlreadySpawned(vehicleId, plate)
    for _, veh in ipairs(GetAllVehicles()) do
        if veh and veh~=0 and DoesEntityExist(veh) then
            if tonumber(Entity(veh).state.vehicleid)==tonumber(vehicleId) then return true end
            if samePlate(GetVehicleNumberPlateText(veh),plate) then return true end
        end
    end
    return false
end

local function pointClear(point)
    local pos=vec3(point.x,point.y,point.z)
    for _, veh in ipairs(GetAllVehicles()) do
        if veh and veh~=0 and DoesEntityExist(veh) and vecDistance(GetEntityCoords(veh),pos)<3.0 then
            return false
        end
    end
    return true
end

local function chooseSpawn(base)
    local h=tonumber(base.w) or 0.0
    local r=math.rad(h)
    local fx,fy=-math.sin(r),math.cos(r)
    local rx,ry=math.cos(r),math.sin(r)

    for _,off in ipairs({
        {0.0,0.0},{0.0,3.8},{0.0,-3.8},{4.5,0.0},{-4.5,0.0},
        {4.5,3.8},{-4.5,-3.8},{8.0,0.0},{-8.0,0.0}
    }) do
        local forward,right=off[1],off[2]
        local p=vec4(base.x+fx*forward+rx*right,base.y+fy*forward+ry*right,base.z,h)
        if pointClear(p) then return p end
    end
    return nil
end

local function vehicleType(modelName)
    local ok,catalog=pcall(function() return exports.qbx_core:GetVehiclesByName() end)
    if ok and type(catalog)=='table' then
        local def=catalog[modelName] or catalog[normModel(modelName)]
        if def and def.type then return def.type end
    end
    return 'automobile'
end

local function createVehicle(src,row,props,spawn)
    local modelName=normModel(row.vehicle)
    local hash=tonumber(props.model) or joaat(modelName)

    local veh=CreateVehicleServerSetter(
        hash,vehicleType(modelName),
        spawn.x+0.0,spawn.y+0.0,spawn.z+0.0,(spawn.w or 0.0)+0.0
    )

    local untilAt=GetGameTimer()+5000
    while (not veh or veh==0 or not DoesEntityExist(veh)) and GetGameTimer()<untilAt do Wait(0) end
    if not veh or veh==0 or not DoesEntityExist(veh) then
        return nil,nil,'차량 엔티티 생성에 실패했습니다'
    end

    local bucket=GetPlayerRoutingBucket(src)
    if bucket and bucket>0 then SetEntityRoutingBucket(veh,bucket) end

    SetEntityOrphanMode(veh,2)
    SetVehicleNumberPlateText(veh,trimPlate(row.plate))
    Entity(veh).state:set('vehicleid',tonumber(row.id),true)
    Entity(veh).state:set('initVehicle',true,true)

    local netId=NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId==0 then
        DeleteEntity(veh)
        return nil,nil,'차량 네트워크 ID 생성에 실패했습니다'
    end

    TriggerClientEvent('qbx_core:client:setVehicleProperties',src,netId,props)
    pcall(function() exports.qbx_core:EnablePersistence(veh) end)

    if started('qbx_vehiclekeys') then
        local okKey,errKey=pcall(function() exports.qbx_vehiclekeys:GiveKeys(src,veh,true) end)
        if not okKey then
            print(('[cookie_garage] GiveKeys warning id=%s: %s'):format(tostring(row.id),tostring(errKey)))
        end
    end
    TriggerClientEvent('vehiclekeys:client:SetOwner',src,trimPlate(row.plate))

    return netId,veh,nil
end

local function ownerFor(ctx,citizenid)
    if ctx.mode=='faction' then return 'FACTION_'..tostring(ctx.factionId) end
    return tostring(citizenid)
end

lib.callback.register('cookie_garage:server:spawnOwned',function(src,vehicleId,zoneId)
    vehicleId=tonumber(vehicleId)
    zoneId=tonumber(zoneId)
    if not vehicleId or not zoneId then return {ok=false,message='출고 요청 정보가 올바르지 않습니다'} end
    if spawnLocks[vehicleId] then return {ok=false,message='이 차량은 이미 출고 처리 중입니다'} end
    spawnLocks[vehicleId]=true

    local function done(v) spawnLocks[vehicleId]=nil return v end

    local ok,result=pcall(function()
        local citizenid=cid(src)
        if not citizenid then return {ok=false,message='시민 정보를 찾을 수 없습니다'} end

        local ctx=context(zoneId)
        if not ctx then return {ok=false,message='차고 비콘 정보를 찾을 수 없습니다'} end
        if not nearZone(src,ctx,12.0) then return {ok=false,message='차고 비콘에서 너무 멉니다'} end
        if ctx.mode=='faction' and not membership(citizenid,ctx.factionId) then
            return {ok=false,message='해당 팩션 소속만 출고할 수 있습니다'}
        end

        local owner=ownerFor(ctx,citizenid)
        local row=one([[
            SELECT id,citizenid,vehicle,plate,mods,garage,state,fuel,engine,body,hash
            FROM player_vehicles
            WHERE id=? AND citizenid=?
            LIMIT 1
        ]],{vehicleId,owner})

        if not row then return {ok=false,message='본인 소유 차량을 찾을 수 없습니다'} end
        if scalar('SELECT id FROM cookie_tow_impound WHERE vehicle_id=? AND active=1 LIMIT 1',{vehicleId}) then
            return {ok=false,message='렉카에 압류 중인 차량입니다. 압류 해제 후 출고할 수 있습니다'}
        end
        if tonumber(row.state)~=1 then return {ok=false,message='이미 출고 중인 차량입니다'} end
        if normModel(row.vehicle)=='' or trimPlate(row.plate)=='' then return {ok=false,message='차량 DB 정보가 손상되어 있습니다'} end

        if isAlreadySpawned(vehicleId,row.plate) then
            MySQL.update.await('UPDATE player_vehicles SET state=0 WHERE id=?',{vehicleId})
            return {ok=false,message='이 차량은 이미 월드에 출고되어 있습니다'}
        end

        local spawn=chooseSpawn(ctx.coords)
        if not spawn then return {ok=false,message='출고 위치가 막혀 있습니다. 주변 차량을 이동해주세요'} end

        local props,modelHash=decodeProps(row)

        local changed=MySQL.update.await([[
            UPDATE player_vehicles
            SET state=0,garage=?,mods=?,hash=?
            WHERE id=? AND citizenid=? AND state=1
        ]],{ctx.garageName or PERSONAL_GARAGE,json.encode(props),tostring(modelHash),vehicleId,owner})

        if tonumber(changed or 0)<1 then return {ok=false,message='차량 상태가 변경되어 출고를 취소했습니다'} end

        local netId,veh,spawnErr=createVehicle(src,row,props,spawn)
        if not netId or not veh then
            MySQL.update.await('UPDATE player_vehicles SET state=1 WHERE id=? AND citizenid=?',{vehicleId,owner})
            return {ok=false,message=spawnErr or '차량 생성에 실패했습니다'}
        end

        return {ok=true,netId=netId,vehicleId=vehicleId,plate=trimPlate(row.plate),model=row.vehicle,props=props}
    end)

    if not ok then
        print(('[cookie_garage] spawn exception vehicle=%s: %s'):format(tostring(vehicleId),tostring(result)))
        return done({ok=false,message='차량 출고 처리 중 서버 오류가 발생했습니다'})
    end
    return done(result)
end)

RegisterNetEvent('cookie_garage:server:spawnClientFailed',function(vehicleId,netId)
    local src=source
    vehicleId=tonumber(vehicleId)
    netId=tonumber(netId)
    if not vehicleId then return end

    local citizenid=cid(src)
    if not citizenid then return end
    local row=one('SELECT id,citizenid FROM player_vehicles WHERE id=? LIMIT 1',{vehicleId})
    if not row then return end

    local allowed=tostring(row.citizenid)==tostring(citizenid) or tostring(row.citizenid):match('^FACTION_')~=nil
    if not allowed then return end

    if netId and netId>0 then
        local veh=NetworkGetEntityFromNetworkId(netId)
        if veh and veh~=0 and DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    MySQL.update.await('UPDATE player_vehicles SET state=1 WHERE id=?',{vehicleId})
    print(('[cookie_garage] client sync failed -> recovered id=%s'):format(vehicleId))
end)

local function findStoreRow(src,ctx,veh,props)
    local citizenid=cid(src)
    if not citizenid then return nil,'시민 정보를 찾을 수 없습니다' end
    local owner=ownerFor(ctx,citizenid)

    local stateId=Entity(veh).state.vehicleid
    if stateId then
        local row=one([[
            SELECT id,citizenid,vehicle,plate,mods,state,garage,fuel,engine,body
            FROM player_vehicles WHERE id=? AND citizenid=? LIMIT 1
        ]],{tonumber(stateId),owner})
        if row then return row end
    end

    local plate=plateKey(GetVehicleNumberPlateText(veh))
    if plate=='' and type(props)=='table' then plate=plateKey(props.plate) end
    if plate=='' then return nil,'차량 번호판을 확인할 수 없습니다' end

    local row=one([[
        SELECT id,citizenid,vehicle,plate,mods,state,garage,fuel,engine,body
        FROM player_vehicles
        WHERE citizenid=? AND REPLACE(UPPER(plate),' ','')=?
        LIMIT 1
    ]],{owner,plate})

    if not row then return nil,'이 차고에 넣을 수 있는 소유 차량이 아닙니다' end
    return row
end

lib.callback.register('cookie_garage:server:storeVehicle',function(src,zoneId,netId,props)
    zoneId=tonumber(zoneId)
    netId=tonumber(netId)
    if not zoneId or not netId then return {ok=false,message='입고 요청 정보가 올바르지 않습니다'} end

    local ctx=context(zoneId)
    if not ctx then return {ok=false,message='차고 비콘 정보를 찾을 수 없습니다'} end
    if not nearZone(src,ctx,14.0) then return {ok=false,message='차고 비콘에서 너무 멉니다'} end

    local citizenid=cid(src)
    if not citizenid then return {ok=false,message='시민 정보를 찾을 수 없습니다'} end
    if ctx.mode=='faction' and not membership(citizenid,ctx.factionId) then
        return {ok=false,message='해당 팩션 소속만 이 차고를 사용할 수 있습니다'}
    end

    local veh=NetworkGetEntityFromNetworkId(netId)
    if not veh or veh==0 or not DoesEntityExist(veh) then
        return {ok=false,message='입고할 차량 엔티티를 찾을 수 없습니다'}
    end

    local row,err=findStoreRow(src,ctx,veh,props)
    if not row then return {ok=false,message=err or '소유 차량을 찾을 수 없습니다'} end

    local vehicleId=tonumber(row.id)
    if storeLocks[vehicleId] then return {ok=false,message='이 차량은 이미 입고 처리 중입니다'} end
    storeLocks[vehicleId]=true

    local function done(v) storeLocks[vehicleId]=nil return v end

    local ok,result=pcall(function()
        local clean=type(props)=='table' and props or {}
        clean.model=joaat(normModel(row.vehicle))
        clean.plate=trimPlate(row.plate)

        local fuel=tonumber(clean.fuelLevel) or tonumber(row.fuel) or 100.0
        local engine=tonumber(clean.engineHealth) or tonumber(row.engine) or 1000.0
        local body=tonumber(clean.bodyHealth) or tonumber(row.body) or 1000.0

        local changed=MySQL.update.await([[
            UPDATE player_vehicles
            SET state=1,garage=?,mods=?,hash=?,fuel=?,engine=?,body=?
            WHERE id=?
        ]],{ctx.garageName or PERSONAL_GARAGE,json.encode(clean),tostring(clean.model),fuel,engine,body,vehicleId})

        if changed==nil or changed==false then return {ok=false,message='차량 상태 DB 저장에 실패했습니다'} end
        if DoesEntityExist(veh) then DeleteEntity(veh) end

        return {
            ok=true,
            vehicleId=vehicleId,
            label=ctx.mode=='faction' and ((ctx.factionName or '팩션')..' 차고') or '시민 차고'
        }
    end)

    if not ok then
        print(('[cookie_garage] store exception id=%s: %s'):format(tostring(vehicleId),tostring(result)))
        return done({ok=false,message='차량 입고 처리 중 서버 오류가 발생했습니다'})
    end
    return done(result)
end)

local function tableColumns()
    local cols=q('SHOW COLUMNS FROM player_vehicles',{}) or {}
    local out={}
    for _,c in ipairs(cols) do out[c.Field]=c end
    return out
end

local function uniquePlate()
    for _=1,80 do
        local plate=('CK%06d'):format(math.random(0,999999))
        if not one("SELECT id FROM player_vehicles WHERE REPLACE(UPPER(plate),' ','')=? LIMIT 1",{plateKey(plate)}) then
            return plate
        end
    end
    return nil
end

local function insertVehicleDirect(p,model)
    local pd=p and p.PlayerData or {}
    local citizenid=pd.citizenid
    local license=pd.license or ''
    if not citizenid then return nil,'시민 정보를 찾을 수 없습니다' end

    local plate=uniquePlate()
    if not plate then return nil,'번호판 생성에 실패했습니다' end

    local hash=joaat(model)
    local props={model=hash,plate=plate,fuelLevel=100.0,engineHealth=1000.0,bodyHealth=1000.0,lockState=1}
    local values={
        license=license,citizenid=citizenid,vehicle=model,hash=tostring(hash),mods=json.encode(props),
        plate=plate,garage=PERSONAL_GARAGE,fuel=100,engine=1000,body=1000,state=1,
        depotprice=0,drivingdistance=0,status='',balance=0,paymentamount=0,paymentsleft=0,financetime=0
    }

    local cols=tableColumns()
    local names,marks,params={},{},{}
    for _,name in ipairs({
        'license','citizenid','vehicle','hash','mods','plate','garage','fuel',
        'engine','body','state','depotprice','drivingdistance','status',
        'balance','paymentamount','paymentsleft','financetime'
    }) do
        if cols[name] then
            names[#names+1]=name
            marks[#marks+1]='?'
            params[#params+1]=values[name]
        end
    end

    if not cols.citizenid or not cols.vehicle or not cols.plate then
        return nil,'player_vehicles 테이블 구조가 올바르지 않습니다'
    end

    local sql=('INSERT INTO player_vehicles (%s) VALUES (%s)'):format(table.concat(names,','),table.concat(marks,','))
    local ok,id=pcall(function() return MySQL.insert.await(sql,params) end)
    if not ok or not id then
        print(('[cookie_garage] direct insert failed model=%s err=%s'):format(model,tostring(id)))
        return nil,'차량 소유권 등록에 실패했습니다'
    end
    return tonumber(id)
end

local function charge(p,amount,reason)
    amount=math.max(0,math.floor(tonumber(amount) or 0))
    if amount==0 then return true,nil end
    if p.Functions.RemoveMoney('bank',amount,reason) then return true,'bank' end
    if p.Functions.RemoveMoney('cash',amount,reason) then return true,'cash' end
    return false
end

RegisterNetEvent('cookie_garage:server:buyGeneral',function(model)
    local src=source
    if not allowAction(src,'garage_buy',1500,1) then return end
    model=normModel(model)

    local row=one([[
        SELECT model,display_name,price
        FROM cookie_dealership_vehicles
        WHERE LOWER(model)=? AND active=1
        LIMIT 1
    ]],{model})

    if not row then return TriggerClientEvent('cookie_garage:client:purchaseResult',src,false,'판매 중인 일반 차량이 아닙니다') end

    local p=player(src)
    local citizenid=cid(src)
    if not p or not citizenid then return TriggerClientEvent('cookie_garage:client:purchaseResult',src,false,'시민 정보를 찾을 수 없습니다') end

    if one('SELECT id FROM player_vehicles WHERE citizenid=? AND LOWER(vehicle)=? LIMIT 1',{citizenid,model}) then
        return TriggerClientEvent('cookie_garage:client:purchaseResult',src,false,'이미 보유 중인 차량입니다')
    end

    local price=math.max(0,math.floor(tonumber(row.price) or 0))
    local paid,account=charge(p,price,'쿠키 일반차고 구매')
    if not paid then return TriggerClientEvent('cookie_garage:client:purchaseResult',src,false,'돈이 부족합니다') end

    local id,err=insertVehicleDirect(p,model)
    if not id then
        if price>0 and account then p.Functions.AddMoney(account,price,'쿠키 일반차고 구매 실패 환불') end
        return TriggerClientEvent('cookie_garage:client:purchaseResult',src,false,err or '차량 등록에 실패했습니다')
    end

    TriggerClientEvent('cookie_garage:client:purchaseResult',src,true,(row.display_name or model)..' 구매 완료')
end)

RegisterNetEvent('cookie_garage:server:buyFaction',function()
    TriggerClientEvent('cookie_garage:client:purchaseResult',source,false,'팩션 차량은 관리자 팩션 함대에서 관리합니다')
end)

RegisterNetEvent('cookie_garage:server:sellGeneral',function(vehicleId)
    local src=source
    if not allowAction(src,'garage_sell',1500,1) then return end
    vehicleId=tonumber(vehicleId)
    if not vehicleId then return TriggerClientEvent('cookie_garage:client:saleResult',src,false,'판매할 차량 정보가 올바르지 않습니다') end
    if saleLocks[src] then return TriggerClientEvent('cookie_garage:client:saleResult',src,false,'차량 판매를 처리 중입니다') end

    saleLocks[src]=true
    local function finish(ok,msg)
        saleLocks[src]=nil
        TriggerClientEvent('cookie_garage:client:saleResult',src,ok,msg)
    end

    local citizenid=cid(src)
    local p=player(src)
    if not citizenid or not p then return finish(false,'시민 정보를 불러오지 못했습니다') end

    local owned=one('SELECT * FROM player_vehicles WHERE id=? AND citizenid=? LIMIT 1',{vehicleId,citizenid})
    if not owned then return finish(false,'본인 소유 차량을 찾을 수 없습니다') end
    if tonumber(owned.state)~=1 then return finish(false,'차량을 차고에 입고한 뒤 판매할 수 있습니다') end

    local model=normModel(owned.vehicle)
    local dealer=one('SELECT display_name,price FROM cookie_dealership_vehicles WHERE LOWER(model)=? AND active=1 LIMIT 1',{model})
    if not dealer then return finish(false,'일반 판매 가격이 등록되지 않은 차량입니다') end

    local refund=math.floor(math.max(0,tonumber(dealer.price) or 0)*GENERAL_RESALE_RATE)
    if refund<=0 then return finish(false,'판매 환급액을 계산할 수 없습니다') end

    local deleted=MySQL.update.await('DELETE FROM player_vehicles WHERE id=? AND citizenid=? AND state=1',{vehicleId,citizenid})
    if tonumber(deleted or 0)<1 then return finish(false,'차량 소유권 삭제에 실패했습니다') end

    local paid=p.Functions.AddMoney('bank',refund,'COOKIE 일반차량 중고 판매')
    if paid==false then return finish(false,'판매 대금 지급에 실패했습니다. 관리자에게 문의해주세요') end

    finish(true,('%s 판매 완료 · %s원이 은행 계좌로 지급되었습니다'):format(tostring(dealer.display_name or model),tostring(refund)))
end)

local function worldHasPlate(plate)
    for _,veh in ipairs(GetAllVehicles()) do
        if veh and veh~=0 and DoesEntityExist(veh) and samePlate(GetVehicleNumberPlateText(veh),plate) then return true end
    end
    return false
end

local function recoverOrphans()
    local rows=q('SELECT id,plate FROM player_vehicles WHERE state=0',{}) or {}
    local repaired=0
    for _,row in ipairs(rows) do
        if not worldHasPlate(row.plate) then
            local changed=MySQL.update.await('UPDATE player_vehicles SET state=1 WHERE id=? AND state=0',{row.id})
            if tonumber(changed or 0)>0 then repaired=repaired+1 end
        end
    end
    if repaired>0 then print(('[cookie_garage] orphan recovery: %d vehicle(s) returned to garage'):format(repaired)) end
end

RegisterCommand('cookiegaragediag',function(src)
    refreshZoneContexts()
    local zones=0
    for _ in pairs(zoneContexts) do zones=zones+1 end

    local stored=tonumber(scalar('SELECT COUNT(*) FROM player_vehicles WHERE state=1',{}) or 0)
    local out=tonumber(scalar('SELECT COUNT(*) FROM player_vehicles WHERE state=0',{}) or 0)
    local general=tonumber(scalar('SELECT COUNT(*) FROM cookie_dealership_vehicles WHERE active=1',{}) or 0)
    local limited=tonumber(scalar('SELECT COUNT(*) FROM cookie_limited_vehicles WHERE active=1',{}) or 0)

    local msg=('V5 zones=%d stored=%d out=%d general=%d limited=%d qbx_core=%s qbx_garages=%s(optional) qbx_vehicles=%s(optional) keys=%s')
        :format(zones,stored,out,general,limited,rstate('qbx_core'),rstate('qbx_garages'),rstate('qbx_vehicles'),rstate('qbx_vehiclekeys'))

    if src==0 then print('[cookie_garage] '..msg)
    else TriggerClientEvent('chat:addMessage',src,{args={'^5[cookie_garage]',msg}}) end
end,false)

AddEventHandler('playerDropped',function() saleLocks[source]=nil end)

CreateThread(function()
    Wait(2500)
    refreshZoneContexts()
    Wait(1500)
    recoverOrphans()
    print('^2[cookie_garage]^7 V5.0.0 ready · standalone spawn/store/list')
end)
