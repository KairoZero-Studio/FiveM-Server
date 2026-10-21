print('^2[cookie_mechanic] V2 client loaded^7')
local M=Config.Mechanic
local npcId,state,offer,task=nil,{},nil,nil
local npcVehicle,npcCustomer,blip=nil,nil,nil
local playerOffer=nil
local dialog=false

local function clearBlip()if blip and DoesBlipExist(blip)then RemoveBlip(blip)end;blip=nil end
local function route(c,label)clearBlip();blip=AddBlipForCoord(c.x,c.y,c.z);SetBlipSprite(blip,M.Blip.sprite);SetBlipColour(blip,M.Blip.colour);SetBlipRoute(blip,true);BeginTextCommandSetBlipName('STRING');AddTextComponentString(label);EndTextCommandSetBlipName(blip)end
local function delNpcStuff()
 if npcCustomer and DoesEntityExist(npcCustomer)then DeletePed(npcCustomer)end;npcCustomer=nil
 if npcVehicle and DoesEntityExist(npcVehicle)then DeleteVehicle(npcVehicle)end;npcVehicle=nil
end
local function model(hash)RequestModel(hash);local t=GetGameTimer()+6000;while not HasModelLoaded(hash)and GetGameTimer()<t do Wait(20)end;return HasModelLoaded(hash)end
local function spawnNpcTask(a)
 delNpcStuff()
 local pm=joaat(a.pedModel or M.DefaultPed);local vm=joaat(a.vehicleModel or M.DefaultVehicle)
 if not model(pm)or not model(vm)then return false end
 local c=a.customer;local v=a.vehicle
 npcCustomer=CreatePed(4,pm,c.x,c.y,c.z,c.h or 0,false,false);FreezeEntityPosition(npcCustomer,true);SetEntityInvincible(npcCustomer,true);TaskStartScenarioInPlace(npcCustomer,'WORLD_HUMAN_STAND_IMPATIENT',0,true)
 npcVehicle=CreateVehicle(vm,v.x,v.y,v.z,v.h or 0,true,false);SetEntityAsMissionEntity(npcVehicle,true,true);SetVehicleOnGroundProperly(npcVehicle);SetVehicleEngineHealth(npcVehicle,a.engineHealth or 280);SetVehicleBodyHealth(npcVehicle,a.bodyHealth or 650);SetVehicleEngineOn(npcVehicle,false,true,true);SetVehicleUndriveable(npcVehicle,true);SetVehicleDirtLevel(npcVehicle,13.0)
 SetModelAsNoLongerNeeded(pm);SetModelAsNoLongerNeeded(vm);return true
end


local mechDlgCam=nil
local function mechSetWorldUi(show)
    TriggerEvent('cookie_hud:client:hudVisible',show)
    DisplayRadar(show)
    if not show then SetCurrentPedWeapon(PlayerPedId(),`WEAPON_UNARMED`,true) end
end
local function mechStartCam(id)
    if mechDlgCam then return end
    local target=nil
    if id then
        local ok,ped=pcall(function() return exports.cookie_admin:getNpcPed(id) end)
        target=(ok and ped) or nil
    end
    if not(target and DoesEntityExist(target))then return end
    local me=PlayerPedId()
    local t=GetPedBoneCoords(target,31086,0.0,0.0,0.0)
    local h=math.rad(GetEntityHeading(target))
    local fx,fy=-math.sin(h),math.cos(h)
    local c=vec3(t.x+fx*1.32-fy*.28,t.y+fy*1.32+fx*.28,t.z+.05)
    TaskTurnPedToFaceEntity(me,target,800)
    mechDlgCam=CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',c.x,c.y,c.z,0,0,0,39.0,false,0)
    PointCamAtCoord(mechDlgCam,t.x,t.y,t.z)
    SetCamActive(mechDlgCam,true)
    RenderScriptCams(true,true,550,true,true)
end
local function mechStopCam()
    if not mechDlgCam then return end
    RenderScriptCams(false,true,450,true,true)
    DestroyCam(mechDlgCam,true)
    mechDlgCam=nil
end

RegisterNetEvent('cookie_mechanic:client:openDialog',function(d)
    npcId=tonumber(d and d.npcId)
    if not npcId then return end
    dialog=true
    mechSetWorldUi(false)
    mechStartCam(npcId)
    SetNuiFocus(true,true)
    SendNUIMessage({action='open',npc=(d and d.label)or'정비소 반장 강민철'})
    TriggerServerEvent('cookie_mechanic:server:requestState',npcId)
end)
RegisterNetEvent('cookie_mechanic:client:state',function(d)state=d or{};SendNUIMessage({action='state',data=state})end)
RegisterNetEvent('cookie_mechanic:client:offer',function(d)offer=d;SendNUIMessage({action='offer',data=d})end)
RegisterNetEvent('cookie_mechanic:client:offerExpired',function()offer=nil;SendNUIMessage({action='offerExpired'})end)
RegisterNetEvent('cookie_mechanic:client:offerClosed',function()offer=nil;SendNUIMessage({action='offerClosed'})end)
RegisterNetEvent('cookie_mechanic:client:startNpcTask',function(d)offer=nil;task=d;if spawnNpcTask(d)then route(d.vehicle,d.label or'고장 차량')end;SendNUIMessage({action='task',data=d})end)

RegisterNetEvent('cookie_mechanic:client:playerOffer',function(d)if task then return end;playerOffer=d;SendNUIMessage({action='playerOffer',data=d})end)
RegisterNetEvent('cookie_mechanic:client:closePlayerOffer',function(d)if playerOffer and d and playerOffer.id==d.id then playerOffer=nil;SendNUIMessage({action='playerOfferClose'})end end)
RegisterNetEvent('cookie_mechanic:client:startPlayerTask',function(d)playerOffer=nil;task=d;route(d.coord,'플레이어 정비 요청');SendNUIMessage({action='playerTask',data=d})end)

RegisterNetEvent('cookie_mechanic:client:completed',function(d)
 if d and d.netId then local veh=NetToVeh(d.netId);if veh and veh~=0 then SetVehicleFixed(veh);SetVehicleDeformationFixed(veh);SetVehicleEngineHealth(veh,1000.0);SetVehicleBodyHealth(veh,1000.0)end end
 if npcVehicle and DoesEntityExist(npcVehicle)then SetVehicleFixed(npcVehicle);SetVehicleEngineHealth(npcVehicle,1000.0);SetVehicleBodyHealth(npcVehicle,1000.0);SetVehicleUndriveable(npcVehicle,false)end
 task=nil;clearBlip();SendNUIMessage({action='completed',data=d});if npcCustomer or npcVehicle then CreateThread(function()Wait(5000);delNpcStuff()end)end
end)
RegisterNetEvent('cookie_mechanic:client:customerComplete',function(d)local veh=d and d.netId and NetToVeh(d.netId);if veh and veh~=0 then SetVehicleFixed(veh);SetVehicleDeformationFixed(veh);SetVehicleEngineHealth(veh,1000.0);SetVehicleBodyHealth(veh,1000.0)end end)
RegisterNetEvent('cookie_mechanic:client:clearAll',function()offer=nil;playerOffer=nil;task=nil;clearBlip();delNpcStuff();SendNUIMessage({action='clearAll'})end)
RegisterNetEvent('cookie_mechanic:client:adminData',function(d)SendNUIMessage({action='npcMechanic',data=d})end)

RegisterNUICallback('close',function(_,cb)cb({ok=true});dialog=false;SetNuiFocus(false,false);SendNUIMessage({action='close'});mechStopCam();mechSetWorldUi(true)end)
RegisterNUICallback('hire',function(_,cb)cb({ok=true});TriggerServerEvent('cookie_mechanic:server:hire',npcId)end)
RegisterNUICallback('quit',function(_,cb)cb({ok=true});TriggerServerEvent('cookie_mechanic:server:quit',npcId)end)
RegisterNUICallback('duty',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_mechanic:server:duty',d and d.on==true,npcId)end)

local function accept()if offer then TriggerServerEvent('cookie_mechanic:server:acceptNpc')elseif playerOffer then TriggerServerEvent('cookie_mechanic:server:acceptPlayer',playerOffer.id)end end
local function decline()if offer then TriggerServerEvent('cookie_mechanic:server:declineNpc')elseif playerOffer then TriggerServerEvent('cookie_mechanic:server:declinePlayer',playerOffer.id)end end
RegisterCommand('mechanicaccept',accept,false);RegisterCommand('mechanicdecline',decline,false)
RegisterKeyMapping('mechanicaccept','정비 콜 수락','keyboard','ADD');RegisterKeyMapping('mechanicdecline','정비 콜 거절','keyboard','SUBTRACT')
CreateThread(function()while true do if (offer or playerOffer)and not dialog then if IsControlJustPressed(0,15)or IsControlJustPressed(0,241)then accept();Wait(250)elseif IsControlJustPressed(0,14)or IsControlJustPressed(0,242)then decline();Wait(250)end;Wait(0)else Wait(200)end end end)

-- 시민용 실제 정비 요청
RegisterCommand('정비요청',function()
 local ped=PlayerPedId();local veh=GetVehiclePedIsIn(ped,false)
 if veh==0 then veh=GetClosestVehicle(GetEntityCoords(ped),7.0,0,70)end
 if veh==0 then return TriggerEvent('cookie_admin:client:notify','정비할 차량 근처에서 요청하세요.',true)end
 local p=GetEntityCoords(veh);TriggerServerEvent('cookie_mechanic:server:playerRequest',{netId=VehToNet(veh),coord={x=p.x,y=p.y,z=p.z},label='시민 차량 긴급 정비'})
end,false)
RegisterCommand('mechaniccall',function()ExecuteCommand('정비요청')end,false)

CreateThread(function()
 local shown=false
 while true do
  local w=500
  if task then
   local veh
   if task.type=='npc' then veh=npcVehicle else veh=task.netId and NetToVeh(task.netId)end
   if veh and veh~=0 and DoesEntityExist(veh)then
    local p=GetEntityCoords(PlayerPedId());local v=GetEntityCoords(veh);local dist=#(p-v)
    if dist<30 then w=0;DrawMarker(0,v.x,v.y,v.z+1.4,0,0,0,0,0,0,.35,.35,.35,255,184,0,170,false,true,2,false)
     if dist<=M.InteractRadius then
      if not shown then lib.showTextUI('[E] 차량 정비 시작',{position='left-center'});shown=true end
      if IsControlJustPressed(0,38)then
       if IsPedInAnyVehicle(PlayerPedId(),false)then TriggerEvent('cookie_admin:client:notify','차량에서 내려 정비하세요.',true)
       else
        local hasKit=lib.callback.await('cookie_mechanic:server:hasRepairKit',false)
        if not hasKit then
         TriggerEvent('cookie_admin:client:notify','수리키트가 필요합니다. 정비 상점에서 먼저 구매하세요.',true)
        else
         if shown then lib.hideTextUI();shown=false end
         TaskStartScenarioInPlace(PlayerPedId(),'WORLD_HUMAN_VEHICLE_MECHANIC',0,true)
         local ok=lib.progressCircle({duration=(tonumber(task.repairSeconds)or M.DefaultRepairSeconds)*1000,position='bottom',label='차량 정비중 · 수리키트 1개 사용',canCancel=true,disable={move=true,car=true,combat=true}})
         ClearPedTasksImmediately(PlayerPedId())
         if ok then TriggerServerEvent('cookie_mechanic:server:finish')end
        end
       end
       Wait(400)
      end
     elseif shown then lib.hideTextUI();shown=false end
    end
   end
  elseif shown then lib.hideTextUI();shown=false end
  Wait(w)
 end
end)



-- COOKIE: 정비공 본인 차량 수리 (고객 의뢰와 별개)
local selfRepairBusy = false
local function trySelfRepair(vehicle)
 if selfRepairBusy then return end
 local ped = PlayerPedId()
 if IsPedInAnyVehicle(ped, false) then
  return TriggerEvent('cookie_admin:client:notify', '차량에서 내려 수리하세요.', true)
 end
 if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
  return TriggerEvent('cookie_admin:client:notify', '수리할 차량이 가까이 없습니다.', true)
 end
 if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 4.5 then return end
 local netId = NetworkGetNetworkIdFromEntity(vehicle)
 if not netId or netId == 0 then
  return TriggerEvent('cookie_admin:client:notify', '네트워크 차량만 수리할 수 있습니다.', true)
 end
 selfRepairBusy = true
 local permitted = lib.callback.await('cookie_mechanic:server:selfRepairCheck', false, netId)
 if not permitted then selfRepairBusy = false; return end
 TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_VEHICLE_MECHANIC', 0, true)
 local done = lib.progressCircle({
  duration = (tonumber(Config.Mechanic.DefaultRepairSeconds) or 12) * 1000,
  position = 'bottom', label = '내 차량 수리 중 · 수리키트 1개',
  canCancel = true, disable = { move = true, car = true, combat = true }
 })
 ClearPedTasks(ped)
 if done then TriggerServerEvent('cookie_mechanic:server:selfRepairFinish', netId) end
 selfRepairBusy = false
end
RegisterCommand('자차수리', function()
 local ped = PlayerPedId()
 local coords = GetEntityCoords(ped)
 local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 70)
 trySelfRepair(vehicle)
end, false)
RegisterCommand('selfrepair', function() ExecuteCommand('자차수리') end, false)

RegisterNetEvent('cookie_mechanic:client:selfRepairDone', function(netId)
 local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
 if vehicle == 0 or not DoesEntityExist(vehicle) then return end
 SetVehicleFixed(vehicle)
 SetVehicleDeformationFixed(vehicle)
 SetVehicleEngineHealth(vehicle, 1000.0)
 SetVehicleBodyHealth(vehicle, 1000.0)
 SetVehiclePetrolTankHealth(vehicle, 1000.0)
 SetVehicleUndriveable(vehicle, false)
end)

CreateThread(function()
 while GetResourceState('ox_target') ~= 'started' do Wait(1000) end
 exports.ox_target:addGlobalVehicle({
  {
   name = 'cookie_mechanic_self_repair',
   icon = 'fa-solid fa-wrench',
   label = '내 차량 수리 (수리공)',
   distance = 3.0,
   canInteract = function(entity)
    local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
    local job = ok and data and data.job
    return job and job.name == Config.Mechanic.Job and not IsPedInAnyVehicle(PlayerPedId(), false)
   end,
   onSelect = function(data) trySelfRepair(data.entity) end
  }
 })
end)
