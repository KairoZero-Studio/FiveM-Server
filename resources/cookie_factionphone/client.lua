local open=false
local busy=false
local profile=nil
local tabletObject=nil
local tabletDict='amb@code_human_in_bus_passenger_idles@female@tablet@base'
local tabletAnim='base'
local tabletModel='prop_cs_tablet'

local function notify(msg,err)
 if lib and lib.notify then lib.notify({title='COOKIE 현장 단말기',description=tostring(msg or ''),type=err and 'error' or 'inform'})
 else TriggerEvent('chat:addMessage',{args={'COOKIE',tostring(msg or '')}}) end
end

local function uiFocus(state)
 local res=GetCurrentResourceName()
 if state then
  if GetResourceState('cookie_core')=='started' then
   local ok,owner=exports.cookie_core:Acquire(res,false)
   if ok~=true then return false,owner end
  end
  SetNuiFocus(true,true);SetNuiFocusKeepInput(false)
  if SetCursorLocation then SetCursorLocation(0.5,0.5) end
  return true
 end
 SetNuiFocus(false,false);SetNuiFocusKeepInput(false)
 if GetResourceState('cookie_core')=='started' then pcall(function() exports.cookie_core:Release(res) end) end
 return true
end

local function requestAnim(dict)
 RequestAnimDict(dict);local untilAt=GetGameTimer()+3000
 while not HasAnimDictLoaded(dict) and GetGameTimer()<untilAt do Wait(10) end
 return HasAnimDictLoaded(dict)
end

local function requestModel(model)
 local hash=GetHashKey(model);RequestModel(hash);local untilAt=GetGameTimer()+3000
 while not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(10) end
 return HasModelLoaded(hash),hash
end

local function stopTablet()
 local ped=PlayerPedId()
 if DoesEntityExist(tabletObject) then DeleteEntity(tabletObject) end
 tabletObject=nil;StopAnimTask(ped,tabletDict,tabletAnim,2.0);ClearPedSecondaryTask(ped)
end

local function startTablet()
 stopTablet()
 local ped=PlayerPedId()
 if IsPedInAnyVehicle(ped,false) or IsEntityDead(ped) then return end
 if not requestAnim(tabletDict) then return end
 local ok,hash=requestModel(tabletModel);if not ok then return end
 TaskPlayAnim(ped,tabletDict,tabletAnim,3.0,3.0,-1,49,0.0,false,false,false)
 local c=GetEntityCoords(ped)
 tabletObject=CreateObject(hash,c.x,c.y,c.z+0.2,true,true,false)
 if DoesEntityExist(tabletObject) then
  AttachEntityToEntity(tabletObject,ped,GetPedBoneIndex(ped,28422),0.0,-0.03,0.0,20.0,-90.0,0.0,true,true,false,true,1,true)
 end
 SetModelAsNoLongerNeeded(hash)
end

local function getClosestPlayer(maxDist)
 local myPos=GetEntityCoords(PlayerPedId());local closest,dist=nil,maxDist or 3.2
 for _,player in ipairs(GetActivePlayers()) do
  if player~=PlayerId() then
   local ped=GetPlayerPed(player)
   if DoesEntityExist(ped) then local d=#(GetEntityCoords(ped)-myPos);if d<dist then closest,dist=player,d end end
  end
 end
 return closest and GetPlayerServerId(closest) or nil
end

local function getClosestVehicle(maxDist)
 local p=GetEntityCoords(PlayerPedId());local veh=GetClosestVehicle(p.x,p.y,p.z,maxDist or 6.0,0,71)
 if veh==0 or not DoesEntityExist(veh) then return nil end
 return veh
end

local function closeTablet()
 if not open then return end
 open=false;SendNUIMessage({action='close'});uiFocus(false);stopTablet()
end

local function openTablet()
 if open or busy or IsPauseMenuActive() or IsEntityDead(PlayerPedId()) then return end
 busy=true
 local p=lib.callback.await('cookie_factionphone:getProfile',false)
 if not p or not p.allowed then busy=false;return notify((p and p.reason) or '팩션 현장 단말기를 사용할 수 없습니다.',true) end
 local ok,owner=uiFocus(true)
 if ok==false then busy=false;return notify(('다른 UI(%s)가 열려 있습니다.'):format(tostring(owner or 'unknown')),true) end
 profile=p;open=true;startTablet();SendNUIMessage({action='open',profile=profile});busy=false
end

local function toggleTablet() if busy then return end;if open then closeTablet() else openTablet() end end
RegisterCommand('cookie_faction_tablet',toggleTablet,false)
RegisterKeyMapping('cookie_faction_tablet','COOKIE 팩션 현장 단말기','keyboard','I')

RegisterNetEvent('cookie_factionphone:client:notify',function(msg,err) notify(msg,err) end)
RegisterNetEvent('cookie_factionphone:client:setCrimeCuffed',function(state) TriggerEvent('cookie_police:client:setCuffed',state==true) end)
RegisterNetEvent('cookie_factionphone:client:setCrimeEscorted',function(officerId) TriggerEvent('cookie_police:client:setEscorted',officerId) end)

RegisterNUICallback('close',function(_,cb) closeTablet();cb({ok=true}) end)
RegisterNUICallback('refresh',function(_,cb)
 local p=lib.callback.await('cookie_factionphone:getProfile',false)
 if p and p.allowed then profile=p;SendNUIMessage({action='profile',profile=p});cb({ok=true,profile=p}) else cb({ok=false}) end
end)

RegisterNUICallback('action',function(data,cb)
 local id=tostring((data or {}).id or '')
 if id=='f5' or id=='penalty' or id=='trade' then closeTablet();Wait(120);ExecuteCommand('cookie_factionmenu');return cb({ok=true}) end
 if id=='police_cuff' then closeTablet();Wait(80);ExecuteCommand('+cookie_police_cuff');ExecuteCommand('-cookie_police_cuff');return cb({ok=true})
 elseif id=='police_escort' then closeTablet();Wait(80);ExecuteCommand('+cookie_police_escort');ExecuteCommand('-cookie_police_escort');return cb({ok=true})
 elseif id=='police_miranda' then closeTablet();Wait(80);ExecuteCommand('+cookie_police_miranda');ExecuteCommand('-cookie_police_miranda');return cb({ok=true})
 elseif id=='police_backup' then closeTablet();Wait(80);ExecuteCommand('+cookie_police_backup');ExecuteCommand('-cookie_police_backup');return cb({ok=true})
 elseif id=='crime_cuff' then local target=getClosestPlayer(3.5);if not target then return cb({ok=false,message='가까운 대상이 없습니다.'}) end;TriggerServerEvent('cookie_factionphone:server:crimeCuff',target);return cb({ok=true})
 elseif id=='crime_escort' then local target=getClosestPlayer(4.0);if not target then return cb({ok=false,message='가까운 대상이 없습니다.'}) end;TriggerServerEvent('cookie_factionphone:server:crimeEscort',target);return cb({ok=true})
 elseif id=='account' then local r=lib.callback.await('cookie_factionphone:account',false);return cb(r or {ok=false,message='공동계좌 정보를 불러오지 못했습니다.'})
 elseif id=='tow_list' then local r=lib.callback.await('cookie_factionphone:towList',false);return cb(r or {ok=false,rows={}})
 elseif id=='tow_impound' or id=='tow_scrap' then
  local veh=getClosestVehicle(6.0);if not veh then return cb({ok=false,message='가까운 차량이 없습니다.'}) end
  local event=id=='tow_impound' and 'cookie_factionphone:towImpound' or 'cookie_factionphone:towScrap'
  local r=lib.callback.await(event,false,{plate=GetVehicleNumberPlateText(veh),model=GetEntityModel(veh)})
  if r and r.ok then NetworkRequestControlOfEntity(veh);local u=GetGameTimer()+1500;while not NetworkHasControlOfEntity(veh) and GetGameTimer()<u do Wait(20);NetworkRequestControlOfEntity(veh) end;SetEntityAsMissionEntity(veh,true,true);DeleteVehicle(veh) end
  return cb(r or {ok=false,message='차량 처리 실패'})
 end
 cb({ok=false,message='지원하지 않는 기능입니다.'})
end)

RegisterNUICallback('accountAction',function(data,cb)
 local r=lib.callback.await('cookie_factionphone:accountAction',false,tostring((data or {}).mode or ''),math.floor(tonumber((data or {}).amount) or 0),tostring((data or {}).reason or ''))
 cb(r or {ok=false,message='처리 실패'})
end)
RegisterNUICallback('towRelease',function(data,cb) local r=lib.callback.await('cookie_factionphone:towRelease',false,tonumber((data or {}).id));cb(r or {ok=false,message='해제 실패'}) end)

CreateThread(function()
 while true do
  if open then
   if IsEntityDead(PlayerPedId()) or IsPauseMenuActive() then closeTablet()
   elseif not IsEntityPlayingAnim(PlayerPedId(),tabletDict,tabletAnim,3) and not IsPedInAnyVehicle(PlayerPedId(),false) then TaskPlayAnim(PlayerPedId(),tabletDict,tabletAnim,3.0,3.0,-1,49,0.0,false,false,false) end
   Wait(250)
  else Wait(700) end
 end
end)
AddEventHandler('onResourceStop',function(res) if res~=GetCurrentResourceName() then return end;SetNuiFocus(false,false);stopTablet() end)
print('^2[COOKIE FACTION TABLET]^7 I HUD + tablet prop V2.0.0 ready')
