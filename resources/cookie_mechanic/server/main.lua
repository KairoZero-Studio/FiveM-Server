print('^2[cookie_mechanic] V2 server loaded^7')
local M=Config.Mechanic
local pending,active={},{}
local playerCalls={}
local callSeq=0
local managerNpc={}

local function P(s)return exports.qbx_core:GetPlayer(s)end
local function J(s)local p=P(s)return p and p.PlayerData and p.PlayerData.job end
local function hired(s)local j=J(s)return j and j.name==M.Job end
local function duty(s)local j=J(s)return j and j.name==M.Job and j.onduty==true end
local function nt(s,m,e)TriggerClientEvent('cookie_admin:client:notify',s,m,e==true)end
local function lvl(s)local ok,v=pcall(function()return exports.cookie_admin:getCivilLevel(s, M.Job or M.Skill)end)return ok and tonumber(v)or 1 end
local function mult(s)local l=math.max(1,math.min(5,lvl(s)));return M.PayMult[l]or 1.0,l end
local function skill(s)local ok,v=pcall(function()return exports.cookie_skill:get(s,M.Skill)end)return ok and v or{}end
local function refresh(s)TriggerEvent('cookie_admin:server:nameTagDirty',s);TriggerEvent('cookie_admin:server:jobDisplayDirty',s)end
local function pricing()local ok,v=pcall(function()return exports.cookie_mechanic:pricing()end);return ok and v or{}end
local function tasks(n)local ok,v=pcall(function()return exports.cookie_mechanic:tasksForNpc(n)end);return ok and v or{}end
local function near(s,c,r)local ped=GetPlayerPed(s);if ped==0 then return false end;return #(GetEntityCoords(ped)-vec3(c.x,c.y,c.z))<=r end
local function itemCount(s,name)local ok,v=pcall(function()return exports.ox_inventory:GetItemCount(s,name)end);return ok and tonumber(v)or 0 end
local function removeItem(s,name,count)local ok,v=pcall(function()return exports.ox_inventory:RemoveItem(s,name,count or 1)end);return ok and v==true end
local function addItem(s,name,count,metadata)local ok,v=pcall(function()return exports.ox_inventory:AddItem(s,name,count or 1,metadata)end);return ok and v==true end

local function phoneEmit(s,d)
 if not s or not GetPlayerName(s) then return end
 TriggerClientEvent('cookie_phone:client:mechanicStatus',s,d or{})
end

CreateThread(function()Wait(800);pcall(function()exports.qbx_core:CreateJob(M.Job,M.JobDef,true)end)end)

local function state(s,n)
 local mm,ll=mult(s);local h;pcall(function()h=exports.cookie_core:getHeadInfo(s)end)
 TriggerClientEvent('cookie_mechanic:client:state',s,{npcId=tonumber(n),hired=hired(s),onDuty=duty(s),pending=pending[s]~=nil,active=active[s]~=nil,level=ll,payMult=mm,skill=skill(s),nick=h and h.nick or nil,gobun=h and h.gobun or nil})
end
RegisterNetEvent('cookie_mechanic:server:requestState',function(n)managerNpc[source]=tonumber(n);state(source,n)end)
RegisterNetEvent('cookie_mechanic:server:hire',function(n)
 local s=source
 local p=P(s)
 if not p then return end
 if hired(s) then return nt(s,'이미 정비공입니다.',true) end

 local curJob=p.PlayerData and p.PlayerData.job
 if curJob and curJob.name and curJob.name~='unemployed' and curJob.name~=M.Job then
  return nt(s,('현재 %s 직업을 보유 중입니다. 기존 직업을 그만둔 뒤 취업하세요.'):format(curJob.label or curJob.name),true)
 end

 local ok=p.Functions.SetJob(M.Job,0)
 if ok==false then return nt(s,'정비공 취업 처리에 실패했습니다.',true) end
 refresh(s)
 nt(s,'정비공으로 취업했습니다.')
 state(s,n)
end)

local function sendNpcCall(s,n)
 if not duty(s)or active[s]or pending[s]then return end
 local tok=math.random(100000,999999);pending[s]={token=tok,npcId=n,waiting=true}
 SetTimeout(math.random(M.CallMinDelay,M.CallMaxDelay)*1000,function()
  if not pending[s]or pending[s].token~=tok or not duty(s)then return end
  local list={}
  for _,r in ipairs(tasks(n))do
   if r.customer_x and r.vehicle_x then list[#list+1]=r end
  end
  if #list==0 then pending[s]=nil;return nt(s,'F3 정비공 설정에서 NPC/차량 위치를 등록하세요.',true)end
  local r=list[math.random(#list)]
  pending[s]={token=tok,type='npc',npcId=n,taskId=r.id,label=r.label,pedModel=r.ped_model,vehicleModel=r.vehicle_model,reward=tonumber(r.reward)or M.DefaultNpcReward,repairSeconds=tonumber(r.repair_seconds)or M.DefaultRepairSeconds,engineHealth=tonumber(r.engine_health)or M.DefaultEngineHealth,bodyHealth=tonumber(r.body_health)or M.DefaultBodyHealth,
   customer={x=r.customer_x,y=r.customer_y,z=r.customer_z,h=r.customer_h},vehicle={x=r.vehicle_x,y=r.vehicle_y,z=r.vehicle_z,h=r.vehicle_h},ttl=M.CallExpire}
  TriggerClientEvent('cookie_mechanic:client:offer',s,pending[s])
  SetTimeout(M.CallExpire*1000,function()if pending[s]and pending[s].token==tok and pending[s].type=='npc'then pending[s]=nil;TriggerClientEvent('cookie_mechanic:client:offerExpired',s);if duty(s)then SetTimeout(1500,function()sendNpcCall(s,n)end)end end end)
 end)
end

RegisterNetEvent('cookie_mechanic:server:duty',function(on,n)
 local s=source;local p=P(s);if not p or not hired(s)then return end
 p.Functions.SetJobDuty(on==true);managerNpc[s]=tonumber(n)
 if on then nt(s,'출근했습니다. NPC와 실제 플레이어 정비 요청을 받을 수 있습니다.');sendNpcCall(s,tonumber(n))
 else pending[s]=nil;active[s]=nil;TriggerClientEvent('cookie_mechanic:client:clearAll',s)end
 refresh(s);state(s,n)
end)

RegisterNetEvent('cookie_mechanic:server:phoneInfo',function()
 local s=source
 local pc=pricing()
 local call=playerCalls[s]
 local st='idle'
 if call then st=call.claimedBy and'assigned'or'searching' end
 phoneEmit(s,{state=st,callId=call and call.id or nil,pricing=pc})
end)

RegisterNetEvent('cookie_mechanic:server:cancelPlayerRequest',function()
 local s=source
 local call=playerCalls[s]
 if not call then return phoneEmit(s,{state='idle'})end
 if call.claimedBy then
  return phoneEmit(s,{state='error',message='정비공이 이미 출동 중입니다. 직접 연락해 취소하세요.'})
 end
 playerCalls[s]=nil
 TriggerClientEvent('cookie_mechanic:client:closePlayerOffer',-1,{id=call.id})
 nt(s,'정비 요청을 취소했습니다.',false)
 phoneEmit(s,{state='cancelled'})
end)

-- 실제 플레이어 정비 요청
RegisterNetEvent('cookie_mechanic:server:playerRequest',function(d)
 local customer=source
 if type(d)~='table'or not tonumber(d.netId)or not d.coord then return end
 if playerCalls[customer]then phoneEmit(customer,{state='error',message='이미 정비 요청을 보냈습니다.'});return nt(customer,'이미 정비 요청을 보냈습니다.',true)end
 callSeq=callSeq+1
 local call={id=callSeq,customer=customer,netId=tonumber(d.netId),coord=d.coord,label=d.label or '플레이어 차량 정비',created=os.time()}
 playerCalls[customer]=call
 local sent=0
 for _,sid in ipairs(GetPlayers())do
  local m=tonumber(sid)
  if m and duty(m)and not active[m]and not pending[m]then
   TriggerClientEvent('cookie_mechanic:client:playerOffer',m,{id=call.id,customer=customer,coord=call.coord,label=call.label,ttl=M.CallExpire})
   sent=sent+1
  end
 end
 if sent==0 then playerCalls[customer]=nil;phoneEmit(customer,{state='unavailable',pricing=pricing()});return nt(customer,'현재 출근 중인 정비공이 없습니다.',true)end
 nt(customer,'정비 요청을 보냈습니다.',false)
 phoneEmit(customer,{state='searching',callId=call.id,pricing=pricing(),label=call.label})
 SetTimeout(M.CallExpire*1000,function()
  if playerCalls[customer]and playerCalls[customer].id==call.id and not playerCalls[customer].claimedBy then
   playerCalls[customer]=nil;nt(customer,'정비 요청 시간이 만료되었습니다.',true)
   phoneEmit(customer,{state='expired'})
   TriggerClientEvent('cookie_mechanic:client:closePlayerOffer',-1,{id=call.id})
  end
 end)
end)

RegisterNetEvent('cookie_mechanic:server:acceptPlayer',function(id)
 local s=source;if not duty(s)or active[s]or pending[s]then return end
 local found
 for _,c in pairs(playerCalls)do if c.id==tonumber(id)then found=c break end end
 if not found or found.claimedBy then return end
 found.claimedBy=s
 local ped=GetPlayerPed(s);local mp=GetEntityCoords(ped);local cc=found.coord
 local meters=#(mp-vec3(cc.x,cc.y,cc.z))
 local pc=pricing();local fare=tonumber(pc.base_fare)or 10000;local free=tonumber(pc.free_dist)or 1000;local step=tonumber(pc.step_dist)or 500
 if meters>free and step>0 then fare=fare+math.floor((meters-free)/step)*(tonumber(pc.step_fare)or 3000)end
 fare=fare+(tonumber(pc.repair_fee)or 30000);fare=math.min(fare,tonumber(pc.max_fare)or 250000)
 active[s]={type='player',callId=found.id,customer=found.customer,netId=found.netId,coord=found.coord,meters=meters,price=fare,repairSeconds=M.DefaultRepairSeconds}
 TriggerClientEvent('cookie_mechanic:client:startPlayerTask',s,active[s])
 TriggerClientEvent('cookie_mechanic:client:closePlayerOffer',-1,{id=found.id})
 nt(found.customer,('정비공이 요청을 수락했습니다. 예상 요금 %s원'):format(fare),false)
 phoneEmit(found.customer,{state='assigned',callId=found.id,price=fare,mechanic=s})
 state(s,managerNpc[s])
end)

RegisterNetEvent('cookie_mechanic:server:declinePlayer',function(id)TriggerClientEvent('cookie_mechanic:client:closePlayerOffer',source,{id=tonumber(id)})end)

RegisterNetEvent('cookie_mechanic:server:acceptNpc',function()
 local s=source;local a=pending[s];if not a or a.type~='npc'then return end
 active[s]=a;pending[s]=nil;TriggerClientEvent('cookie_mechanic:client:startNpcTask',s,a);state(s,a.npcId)
end)
RegisterNetEvent('cookie_mechanic:server:declineNpc',function()
 local s=source;local a=pending[s];if not a or a.type~='npc'then return end;local n=a.npcId;pending[s]=nil;TriggerClientEvent('cookie_mechanic:client:offerClosed',s);if duty(s)then SetTimeout(1200,function()sendNpcCall(s,n)end)end
end)

lib.callback.register('cookie_mechanic:server:hasRepairKit',function(src)
 return itemCount(src,'repairkit')>0
end)

RegisterNetEvent('cookie_mechanic:server:finish',function()
 local s=source;local a=active[s];if not a or not duty(s)then return end
 local mm,ll=mult(s);local p=P(s);local repairItem='repairkit'
 if itemCount(s,repairItem)<1 then return nt(s,'수리키트가 필요합니다. 정비 상점에서 먼저 구매하세요.',true)end
 if a.type=='npc'then
   if not near(s,a.vehicle,15)then return end
   if not removeItem(s,repairItem,1)then return nt(s,'수리키트 소모 처리에 실패했습니다.',true)end
   local pay=math.floor((a.reward or 0)*mm);if p then p.Functions.AddMoney('bank',pay,'NPC 현장 정비')end
   pcall(function()exports.cookie_skill:addExp(s,M.Skill,M.ExpPerRepair);exports.cookie_skill:record(s,M.Skill,pay)end)
   local n=a.npcId;active[s]=nil
   TriggerClientEvent('cookie_mechanic:client:completed',s,{type='npc',reward=pay})
   nt(s,'수리키트 1개가 소모되었습니다.',false)
   state(s,n);SetTimeout(1800,function()if duty(s)then sendNpcCall(s,n)end end)
 elseif a.type=='player'then
   local cp=P(a.customer);if not cp then active[s]=nil;return nt(s,'고객이 접속해 있지 않습니다.',true)end
   local price=math.floor(a.price or 0)
   if not(cp.Functions.GetMoney and cp.Functions.GetMoney('bank')>=price)then return nt(s,'고객의 은행 잔액이 부족합니다.',true)end
   if not removeItem(s,repairItem,1)then return nt(s,'수리키트 소모 처리에 실패했습니다.',true)end
   local ok=cp.Functions.RemoveMoney('bank',price,'플레이어 차량 정비')~=false
   if not ok then
    addItem(s,repairItem,1,{source='정비비 결제 실패 환불'})
    return nt(s,'고객의 은행 잔액이 부족합니다.',true)
   end
   local pay=math.floor(price*mm);if p then p.Functions.AddMoney('bank',pay,'플레이어 차량 정비')end
   pcall(function()exports.cookie_skill:addExp(s,M.Skill,M.ExpPerRepair);exports.cookie_skill:record(s,M.Skill,pay)end)
   local customer=a.customer;active[s]=nil;playerCalls[customer]=nil
   TriggerClientEvent('cookie_mechanic:client:completed',s,{type='player',reward=pay,netId=a.netId})
   TriggerClientEvent('cookie_mechanic:client:customerComplete',customer,{price=price,netId=a.netId})
   phoneEmit(customer,{state='completed',price=price})
   nt(s,'수리키트 1개가 소모되었습니다.',false)
   nt(customer,('정비비 %s원이 결제되었습니다.'):format(price),false);state(s,managerNpc[s])
 end
end)

RegisterNetEvent('cookie_mechanic:server:quit',function(n)local s=source;local p=P(s);if p then p.Functions.SetJobDuty(false);p.Functions.SetJob('unemployed',0)end;pending[s]=nil;active[s]=nil;TriggerClientEvent('cookie_mechanic:client:clearAll',s);refresh(s);state(s,n)end)
AddEventHandler('playerDropped',function()
 local s=source
 pending[s]=nil;active[s]=nil;managerNpc[s]=nil
 if playerCalls[s]then
  local id=playerCalls[s].id
  playerCalls[s]=nil
  TriggerClientEvent('cookie_mechanic:client:closePlayerOffer',-1,{id=id})
 end
end)



-- COOKIE: 본인 소유 차량 수리. 소유권/거리/아이템 검사는 서버에서 실행.
local selfRepairPending, selfRepairLocks = {}, {}
local function validateSelfRepair(src, netId)
 if not duty(src) then return false, '정비공으로 출근해야 합니다.' end
 local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
 if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 2 then
  return false, '차량을 찾을 수 없습니다.'
 end
 local ped = GetPlayerPed(src)
 if not ped or ped == 0 or #(GetEntityCoords(ped) - GetEntityCoords(ent)) > 5.0 then
  return false, '차량에 가까이 가서 수리하세요.'
 end
 if GetVehiclePedIsIn(ped, false) ~= 0 then return false, '차량에서 내려 수리하세요.' end
 local player = P(src)
 local citizenid = player and player.PlayerData and player.PlayerData.citizenid
 if not citizenid then return false, '캐릭터 정보를 확인할 수 없습니다.' end
 local plate = (GetVehicleNumberPlateText(ent) or ''):gsub('^%s+', ''):gsub('%s+$', '')
 if plate == '' then return false, '차량 번호판이 없습니다.' end
 local owned = MySQL.scalar.await('SELECT id FROM player_vehicles WHERE citizenid = ? AND TRIM(plate) = ? LIMIT 1', {citizenid, plate})
 if not owned then return false, '본인 소유 차량만 자차 수리할 수 있습니다.' end
 if itemCount(src, 'repairkit') < 1 then return false, '수리키트 1개가 필요합니다.' end
 return true, nil, ent
end

lib.callback.register('cookie_mechanic:server:selfRepairCheck', function(src, netId)
 if selfRepairLocks[src] then return false end
 local ok, reason = validateSelfRepair(src, netId)
 if not ok then nt(src, reason, true); return false end
 selfRepairPending[src] = {netId = tonumber(netId), started = os.time()}
 return true
end)

RegisterNetEvent('cookie_mechanic:server:selfRepairFinish', function(netId)
 local src = source
 if selfRepairLocks[src] then return end
 local pending = selfRepairPending[src]
 selfRepairPending[src] = nil
 if not pending or pending.netId ~= tonumber(netId) then return end
 if os.time() - pending.started < math.max(1, (tonumber(M.DefaultRepairSeconds) or 12) - 2) then return end
 selfRepairLocks[src] = true
 local ok, reason = validateSelfRepair(src, netId)
 if not ok then nt(src, reason, true)
 elseif not removeItem(src, 'repairkit', 1) then nt(src, '수리키트 사용에 실패했습니다.', true)
 else
  TriggerClientEvent('cookie_mechanic:client:selfRepairDone', -1, tonumber(netId))
  nt(src, '내 차량 수리가 완료되었습니다. 수리키트 1개가 소모되었습니다.', false)
 end
 selfRepairLocks[src] = nil
end)

AddEventHandler('playerDropped', function()
 selfRepairPending[source] = nil
 selfRepairLocks[source] = nil
end)
