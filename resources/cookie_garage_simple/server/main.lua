local locks = {}
local function errorResult(message) return {ok=false,reason=message} end
local function getCid(src)
    local ok,player=pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok and player and player.PlayerData then return player.PlayerData.citizenid end
end
local function plateKey(value)
    return tostring(value or ''):upper():gsub('%s+','')
end
local function atGarage(src,key,dist)
    local cfg=Config.Garages[key]
    if not cfg then return end
    local ped=GetPlayerPed(src)
    if ped<=0 or not DoesEntityExist(ped) then return end
    if #(GetEntityCoords(ped)-cfg.coords)>dist then return end
    return cfg,ped
end
local function findLiveByPlate(plate)
    local target=plateKey(plate)
    if target=='' then return end
    for _,ent in ipairs(GetAllVehicles()) do
        if ent~=0 and DoesEntityExist(ent) and plateKey(GetVehicleNumberPlateText(ent))==target then
            return ent
        end
    end
end
local function findSpace(cfg)
    for _,point in ipairs(cfg.spawns) do
        local pos=vector3(point.x,point.y,point.z)
        local blocked=false
        for _,ent in ipairs(GetAllVehicles()) do
            if DoesEntityExist(ent) and #(GetEntityCoords(ent)-pos)<Config.SpawnClearance then
                blocked=true
                break
            end
        end
        if not blocked then return point end
    end
end
local function propsFor(row)
    local props={}
    if type(row.mods)=='string' and row.mods~='' then
        local ok,t=pcall(json.decode,row.mods)
        if ok and type(t)=='table' then props=t end
    end
    props.plate=row.plate
    props.model=joaat(row.vehicle)
    return props
end
local function withLock(src,fn)
    if locks[src] then return errorResult('이전 차고 처리가 끝나지 않았습니다.') end
    locks[src]=true
    local ok,r=pcall(fn)
    locks[src]=nil
    if not ok then
        print(('[cookie_garage_simple] error src=%s %s'):format(tostring(src),tostring(r)))
        return errorResult('차고 서버 오류가 발생했습니다. 콘솔의 cookie_garage_simple 로그를 확인해 주세요.')
    end
    return r
end

lib.callback.register('cookie_garage_simple:list',function(src,key)
    local cfg=atGarage(src,key,Config.ServerDistance)
    if not cfg then return errorResult('차고 위치에서 이용해 주세요.') end
    local cid=getCid(src)
    if not cid then return errorResult('캐릭터 정보가 아직 로드되지 않았습니다.') end
    local rows
    if Config.ShowAllOwned then
        rows=MySQL.query.await('SELECT id,vehicle,plate,garage,state FROM player_vehicles WHERE citizenid=? ORDER BY id DESC',{cid})
    else
        rows=MySQL.query.await('SELECT id,vehicle,plate,garage,state FROM player_vehicles WHERE citizenid=? AND garage=? ORDER BY id DESC',{cid,cfg.garageDbName})
    end
    local vehicles={}
    for _,row in ipairs(rows or {}) do
        vehicles[#vehicles+1]={
            id=tonumber(row.id), model=tostring(row.vehicle or 'unknown'),
            plate=tostring(row.plate or ''),state=tonumber(row.state) or 0,
            exists=findLiveByPlate(row.plate)~=nil
        }
    end
    return {ok=true,vehicles=vehicles}
end)

lib.callback.register('cookie_garage_simple:spawn',function(src,key,vehicleId)
    return withLock(src,function()
        local cfg,ped=atGarage(src,key,Config.ServerDistance)
        if not cfg then return errorResult('차고 근처로 이동해 주세요.') end
        local cid=getCid(src)
        if not cid then return errorResult('캐릭터 정보가 없습니다.') end
        local id=math.floor(tonumber(vehicleId) or 0)
        if id<1 then return errorResult('잘못된 차량 ID입니다.') end
        if GetResourceState('qbx_vehiclekeys')~='started' then
            return errorResult('차량 열쇠 리소스(qbx_vehiclekeys)가 실행되지 않았습니다.')
        end
        if not qbx or type(qbx.spawnVehicle)~='function' then
            return errorResult('QBOX 차량 생성 함수가 로드되지 않았습니다.')
        end
        local row=MySQL.single.await(
            'SELECT id,vehicle,plate,garage,state,mods FROM player_vehicles WHERE id=? AND citizenid=? LIMIT 1',
            {id,cid})
        if not row then return errorResult('소유 차량 기록을 찾지 못했습니다.') end
        local state=tonumber(row.state) or 0
        if state==2 then return errorResult('압류 차량은 출고할 수 없습니다.') end
        if state~=0 and state~=1 then return errorResult('지원하지 않는 차량 상태입니다.') end
        if findLiveByPlate(row.plate) then
            return errorResult('동일 번호판 차량이 이미 맵에 있습니다. 중복 생성을 차단했습니다.')
        end
        if state==0 and not Config.RecoverMissingOutVehicles then
            return errorResult('출고 중으로 기록된 차량입니다.')
        end
        local spawn=findSpace(cfg)
        if not spawn then return errorResult('출고 공간이 막혀 있습니다. 빈 주차칸을 확인해 주세요.') end
        if not row.vehicle or row.vehicle=='' then return errorResult('차량 모델 코드가 비어 있습니다.') end
        local netId,entity
        local ok,why=pcall(function()
            netId,entity=qbx.spawnVehicle({
                model=joaat(row.vehicle),
                spawnSource=spawn,
                warp=ped,
                props=propsFor(row),
                bucket=GetPlayerRoutingBucket(src)
            })
        end)
        if not ok or not entity or entity==0 or not DoesEntityExist(entity) then
            print(('[cookie_garage_simple] spawn model=%s id=%d detail=%s'):format(tostring(row.vehicle),id,tostring(why)))
            return errorResult('차량 생성 실패: 모델이나 출고 좌표를 확인해 주세요.')
        end

        SetVehicleNumberPlateText(entity,tostring(row.plate))
        Entity(entity).state:set('vehicleid',id,true)

        -- 기존 state=0이면 값이 바뀌지 않아 UPDATE가 0행을 반환할 수 있음.
        -- 따라서 0행을 실패로 보지 않고, nil/false(실제 SQL 오류)만 실패로 취급함.
        local updated=MySQL.update.await('UPDATE player_vehicles SET state=0 WHERE id=? AND citizenid=?',{id,cid})
        if updated==nil or updated==false then
            DeleteEntity(entity)
            return errorResult('DB 출고 상태 저장에 실패했습니다.')
        end

        local keysOk,keysErr=pcall(function()
            exports.qbx_vehiclekeys:GiveKeys(src,entity,true)
        end)
        if not keysOk then
            print(('[cookie_garage_simple] GiveKeys failed %s: %s'):format(tostring(row.plate),tostring(keysErr)))
            DeleteEntity(entity)
            -- state=0으로 이전부터 기록돼 있었을 경우 무조건 1로 바꾸면 안 됨
            if state==1 then
                MySQL.update.await('UPDATE player_vehicles SET state=1 WHERE id=? AND citizenid=?',{id,cid})
            end
            return errorResult('열쇠 지급 실패. 출고가 취소되었습니다.')
        end
        if Config.Debug then print(('[cookie_garage_simple] spawn id=%d stateWas=%d'):format(id,state)) end
        return {ok=true,netId=netId,recovered=state==0}
    end)
end)

lib.callback.register('cookie_garage_simple:store',function(src,key,netId,props)
    return withLock(src,function()
        local cfg,ped=atGarage(src,key,Config.StoreDistance)
        if not cfg then return errorResult('차고 근처에서만 입고할 수 있습니다.') end
        local cid=getCid(src)
        if not cid then return errorResult('캐릭터 정보가 없습니다.') end
        local entity=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
        if not entity or entity==0 or not DoesEntityExist(entity) or GetEntityType(entity)~=2 then
            return errorResult('차량이 월드에 없습니다.')
        end
        if #(GetEntityCoords(entity)-GetEntityCoords(ped))>9 then
            return errorResult('차량 가까이에서 입고해 주세요.')
        end
        if #(GetEntityCoords(entity)-cfg.coords)>Config.StoreDistance+3 then
            return errorResult('차고 근처에 차량을 세워 주세요.')
        end
        local plate=plateKey(GetVehicleNumberPlateText(entity))
        local row=MySQL.single.await(
            "SELECT id,vehicle,plate FROM player_vehicles WHERE REPLACE(UPPER(plate),' ','')=? AND citizenid=? LIMIT 1",
            {plate,cid})
        if not row then return errorResult('본인 소유 차량만 입고할 수 있습니다.') end
        if joaat(row.vehicle)~=GetEntityModel(entity) then
            return errorResult('차량 모델이 소유 기록과 일치하지 않습니다.')
        end
        if type(props)~='table' then props={} end
        props.model=joaat(row.vehicle)
        props.plate=row.plate
        local saved=false
        if GetResourceState('qbx_vehicles')=='started' then
            local ok,res=pcall(function()
                return exports.qbx_vehicles:SaveVehicle(entity,{
                    garage=cfg.garageDbName,
                    state=1,
                    props=props
                })
            end)
            saved=ok and res==true
        end
        if not saved then
            local changed=MySQL.update.await(
                'UPDATE player_vehicles SET garage=?,state=1,mods=? WHERE id=? AND citizenid=?',
                {cfg.garageDbName,json.encode(props),row.id,cid})
            saved=changed~=nil and changed~=false
        end
        if not saved then return errorResult('DB 입고 저장에 실패했습니다.') end
        DeleteEntity(entity)
        return {ok=true}
    end)
end)

AddEventHandler('playerDropped',function() locks[source]=nil end)
CreateThread(function()
    Wait(1500)
    print('[cookie_garage_simple] V1.0.1 loaded - direct spawn / keys / recovery')
end)
