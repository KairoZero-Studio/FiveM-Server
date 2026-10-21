local M=Config.Mechanic

local function auth(src)
    local ok,lv=pcall(function() return exports.cookie_admin:getEffectiveLevel(src) end)
    return ok and (tonumber(lv) or 0)>=3
end
local function notify(src,msg,err) TriggerClientEvent('cookie_admin:client:notify',src,msg,err==true) end
local function pos(src)
    local ped=GetPlayerPed(src); if ped==0 then return nil end
    local p=GetEntityCoords(ped)
    return p.x,p.y,p.z,GetEntityHeading(ped)
end

CreateThread(function()
    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS cookie_mechanic_task(
        id INT AUTO_INCREMENT PRIMARY KEY,
        npc_id INT NOT NULL,
        label VARCHAR(80) NOT NULL,
        ped_model VARCHAR(60) NOT NULL DEFAULT 'a_m_m_business_01',
        vehicle_model VARCHAR(60) NOT NULL DEFAULT 'blista',
        reward BIGINT NOT NULL DEFAULT 70000,
        repair_seconds INT NOT NULL DEFAULT 12,
        engine_health DOUBLE NOT NULL DEFAULT 280,
        body_health DOUBLE NOT NULL DEFAULT 650,
        customer_x DOUBLE NULL, customer_y DOUBLE NULL, customer_z DOUBLE NULL, customer_h DOUBLE NOT NULL DEFAULT 0,
        vehicle_x DOUBLE NULL, vehicle_y DOUBLE NULL, vehicle_z DOUBLE NULL, vehicle_h DOUBLE NOT NULL DEFAULT 0,
        is_active TINYINT(1) NOT NULL DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_mech_npc(npc_id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- V1 호환
    for _,q in ipairs({
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS ped_model VARCHAR(60) NOT NULL DEFAULT 'a_m_m_business_01'",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS customer_x DOUBLE NULL",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS customer_y DOUBLE NULL",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS customer_z DOUBLE NULL",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS customer_h DOUBLE NOT NULL DEFAULT 0",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS vehicle_x DOUBLE NULL",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS vehicle_y DOUBLE NULL",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS vehicle_z DOUBLE NULL",
      "ALTER TABLE cookie_mechanic_task ADD COLUMN IF NOT EXISTS vehicle_h DOUBLE NOT NULL DEFAULT 0"
    }) do pcall(function() MySQL.query.await(q) end) end

    MySQL.query.await([[
      CREATE TABLE IF NOT EXISTS cookie_mechanic_paycfg(
        id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,
        base_fare INT NOT NULL DEFAULT 10000,
        free_dist DOUBLE NOT NULL DEFAULT 1000,
        step_dist DOUBLE NOT NULL DEFAULT 500,
        step_fare INT NOT NULL DEFAULT 3000,
        repair_fee INT NOT NULL DEFAULT 30000,
        max_fare INT NOT NULL DEFAULT 250000,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    local P=M.PlayerPricing
    MySQL.insert.await('INSERT IGNORE INTO cookie_mechanic_paycfg(id,base_fare,free_dist,step_dist,step_fare,repair_fee,max_fare) VALUES(1,?,?,?,?,?,?)',
      {P.BaseFare,P.FreeDist,P.StepDist,P.StepFare,P.RepairFee,P.MaxFare})
end)

local function pricing()
    return MySQL.single.await('SELECT base_fare,free_dist,step_dist,step_fare,repair_fee,max_fare FROM cookie_mechanic_paycfg WHERE id=1') or {
      base_fare=M.PlayerPricing.BaseFare,free_dist=M.PlayerPricing.FreeDist,step_dist=M.PlayerPricing.StepDist,
      step_fare=M.PlayerPricing.StepFare,repair_fee=M.PlayerPricing.RepairFee,max_fare=M.PlayerPricing.MaxFare
    }
end

local function rows(npcId)
    return MySQL.query.await([[
      SELECT id,npc_id,label,ped_model,vehicle_model,reward,repair_seconds,engine_health,body_health,
             customer_x,customer_y,customer_z,customer_h,vehicle_x,vehicle_y,vehicle_z,vehicle_h
      FROM cookie_mechanic_task WHERE npc_id=? AND is_active=1 ORDER BY id
    ]],{tonumber(npcId)}) or {}
end

local function payload(npcId)
    local r=rows(npcId)
    for _,v in ipairs(r) do
      v.hasCustomer=v.customer_x~=nil and v.customer_y~=nil and v.customer_z~=nil
      v.hasVehicle=v.vehicle_x~=nil and v.vehicle_y~=nil and v.vehicle_z~=nil
    end
    return {npcId=tonumber(npcId),rows=r,pricing=pricing()}
end
local function push(src,npcId) TriggerClientEvent('cookie_mechanic:client:adminData',src,payload(npcId)) end

RegisterNetEvent('cookie_mechanic:server:adminList',function(npcId)local src=source;if auth(src)then push(src,npcId)end end)

RegisterNetEvent('cookie_mechanic:server:adminAdd',function(d)
    local src=source;if not auth(src)or type(d)~='table'then return end
    local npcId=tonumber(d.npcId);if not npcId then return end
    MySQL.insert.await([[INSERT INTO cookie_mechanic_task(npc_id,label,ped_model,vehicle_model,reward,repair_seconds,engine_health,body_health)
      VALUES(?,?,?,?,?,?,?,?)]],{
      npcId,tostring(d.label or '현장 정비'):sub(1,80),tostring(d.pedModel or M.DefaultPed):sub(1,60),
      tostring(d.model or M.DefaultVehicle):sub(1,60),math.max(0,math.floor(tonumber(d.reward)or M.DefaultNpcReward)),
      math.max(3,math.min(120,math.floor(tonumber(d.seconds)or M.DefaultRepairSeconds))),
      tonumber(d.engineHealth)or M.DefaultEngineHealth,tonumber(d.bodyHealth)or M.DefaultBodyHealth})
    notify(src,'NPC 현장 정비 작업을 생성했습니다. 고객/차량 위치를 각각 저장하세요.',false);push(src,npcId)
end)

RegisterNetEvent('cookie_mechanic:server:adminUpdate',function(d)
    local src=source;if not auth(src)or type(d)~='table'then return end
    MySQL.update.await([[UPDATE cookie_mechanic_task SET label=?,ped_model=?,vehicle_model=?,reward=?,repair_seconds=?,engine_health=?,body_health=? WHERE id=? AND npc_id=?]],{
      tostring(d.label or '현장 정비'):sub(1,80),tostring(d.pedModel or M.DefaultPed):sub(1,60),tostring(d.model or M.DefaultVehicle):sub(1,60),
      math.max(0,math.floor(tonumber(d.reward)or M.DefaultNpcReward)),math.max(3,math.min(120,math.floor(tonumber(d.seconds)or M.DefaultRepairSeconds))),
      math.max(50,math.min(1000,tonumber(d.engineHealth)or M.DefaultEngineHealth)),math.max(50,math.min(1000,tonumber(d.bodyHealth)or M.DefaultBodyHealth)),
      tonumber(d.id),tonumber(d.npcId)})
    push(src,d.npcId)
end)

RegisterNetEvent('cookie_mechanic:server:adminSetPoint',function(d)
    local src=source;if not auth(src)or type(d)~='table'then return end
    local x,y,z,h=pos(src);if not x then return end
    if d.kind=='customer' then
      MySQL.update.await('UPDATE cookie_mechanic_task SET customer_x=?,customer_y=?,customer_z=?,customer_h=? WHERE id=? AND npc_id=?',{x,y,z,h,tonumber(d.id),tonumber(d.npcId)})
      notify(src,'고객 NPC 등장 위치를 저장했습니다.',false)
    elseif d.kind=='vehicle' then
      MySQL.update.await('UPDATE cookie_mechanic_task SET vehicle_x=?,vehicle_y=?,vehicle_z=?,vehicle_h=? WHERE id=? AND npc_id=?',{x,y,z,h,tonumber(d.id),tonumber(d.npcId)})
      notify(src,'고장 차량 등장 위치/방향을 저장했습니다.',false)
    end
    push(src,d.npcId)
end)

RegisterNetEvent('cookie_mechanic:server:adminDelete',function(d)
    local src=source;if not auth(src)or type(d)~='table'then return end
    MySQL.update.await('UPDATE cookie_mechanic_task SET is_active=0 WHERE id=? AND npc_id=?',{tonumber(d.id),tonumber(d.npcId)});push(src,d.npcId)
end)

RegisterNetEvent('cookie_mechanic:server:adminPricingSave',function(d)
    local src=source;if not auth(src)or type(d)~='table'then return end
    local base=math.max(0,math.floor(tonumber(d.baseFare)or 10000))
    local free=math.max(0,tonumber(d.freeDist)or 1000)
    local step=math.max(1,tonumber(d.stepDist)or 500)
    local sf=math.max(0,math.floor(tonumber(d.stepFare)or 3000))
    local rf=math.max(0,math.floor(tonumber(d.repairFee)or 30000))
    local mx=math.max(0,math.floor(tonumber(d.maxFare)or 250000))
    MySQL.update.await('UPDATE cookie_mechanic_paycfg SET base_fare=?,free_dist=?,step_dist=?,step_fare=?,repair_fee=?,max_fare=? WHERE id=1',{base,free,step,sf,rf,mx})
    notify(src,'플레이어 정비 요금 설정을 저장했습니다.',false);push(src,d.npcId)
end)

exports('tasksForNpc',rows)
exports('pricing',pricing)
