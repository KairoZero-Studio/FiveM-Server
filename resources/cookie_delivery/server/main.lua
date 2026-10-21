print('^2[cookie_delivery] V11 server loaded^7')
local D=Config.Delivery;local active,pending={},{}
local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end
local function P(s)return exports.qbx_core:GetPlayer(s)end
local function J(s)local p=P(s)return p and p.PlayerData.job end
local function hired(s)local j=J(s)return j and j.name==D.Job end
local function duty(s)local j=J(s)return j and j.name==D.Job and j.onduty==true end
local function nt(s,m,e)TriggerClientEvent('cookie_admin:client:notify',s,m,e==true)end
CreateThread(function()Wait(800);pcall(function()exports.qbx_core:CreateJob(D.Job,D.JobDef,true)end)end)
local function state(s,n)local sk=nil;pcall(function()sk=exports.cookie_skill:get(s,D.Skill)end);local lv=1;pcall(function()lv=exports.cookie_admin:getCivilLevel(s, D.Job or D.Skill)or 1 end);local mult=(D.PayMult and D.PayMult[math.max(1,math.min(5,tonumber(lv)or 1))])or 1.0;local head=nil;pcall(function()head=exports.cookie_core:getHeadInfo(s)end);TriggerClientEvent('cookie_delivery:client:state',s,{npcId=tonumber(n),hired=hired(s),onDuty=duty(s),active=active[s]~=nil,pending=pending[s]~=nil,level=tonumber(lv)or 1,skill=sk,payMult=mult,nick=head and head.nick or nil,gobun=head and head.gobun or nil})end
RegisterNetEvent('cookie_delivery:server:requestState',function(n)state(source,n)end)
RegisterNetEvent('cookie_delivery:server:hire',function(n)
 local s=source
 local p=P(s)
 if not p then return end
 if hired(s) then return nt(s,'이미 배달기사입니다.',true) end

 local curJob=p.PlayerData and p.PlayerData.job
 if curJob and curJob.name and curJob.name~='unemployed' and curJob.name~=D.Job then
  return nt(s,('현재 %s 직업을 보유 중입니다. 기존 직업을 그만둔 뒤 취업하세요.'):format(curJob.label or curJob.name),true)
 end

 local ok=p.Functions.SetJob(D.Job,0)
 if ok==false then return nt(s,'배달기사 취업 처리에 실패했습니다.',true) end
 nt(s,'배달기사로 취업했습니다.')
 state(s,n)
end)
local function schedule(s,n)
 if not duty(s) or active[s] or pending[s] then return end
 local tok=math.random(100000,999999)
 local waitMs=math.random(D.CallMinDelay,D.CallMaxDelay)*1000
 pending[s]={token=tok,npcId=tonumber(n),waiting=true}

 SetTimeout(waitMs,function()
  if not pending[s] or pending[s].token~=tok or not duty(s) then return end
  local rs=MySQL.query.await('SELECT * FROM cookie_delivery_restaurant WHERE npc_id=? AND is_active=1',{tonumber(n)})or{}
  local ds=MySQL.query.await('SELECT * FROM cookie_delivery_dropoff WHERE npc_id=? AND is_active=1',{tonumber(n)})or{}
  if #rs==0 or #ds==0 then
   pending[s]=nil
   return nt(s,'식당 또는 배달지를 F3에서 등록하세요.',true)
  end

  local r=rs[math.random(#rs)]
  local d=ds[math.random(#ds)]
  local dx,dy,dz=d.x-r.pickup_x,d.y-r.pickup_y,d.z-r.pickup_z
  local km=math.sqrt(dx*dx+dy*dy+dz*dz)/1000
  local ttl=tonumber(D.CallExpire) or 45

  pending[s]={
   token=tok,npcId=tonumber(n),waiting=false,
   restaurant=r,dropoff=d,distanceKm=km,
   estimated=math.floor((tonumber(r.base_pay)or D.DefaultBasePay)+km*(tonumber(r.per_km)or D.DefaultPerKm)),
   ttl=ttl
  }

  TriggerClientEvent('cookie_delivery:client:call',s,pending[s])

  -- 콜 제한시간 만료: 서버가 권위적으로 취소하고 다음 콜 대기
  SetTimeout(ttl*1000,function()
   local a=pending[s]
   if not a or a.token~=tok or a.waiting then return end
   pending[s]=nil
   TriggerClientEvent('cookie_delivery:client:callExpired',s)
   if GetPlayerPing(s)>0 and duty(s) and not active[s] then
    SetTimeout(1200,function()
     if GetPlayerPing(s)>0 and duty(s) and not active[s] and not pending[s] then schedule(s,n) end
    end)
   end
  end)
 end)
end
RegisterNetEvent('cookie_delivery:server:duty',function(on,n)local s=source;local p=P(s);if not p or not hired(s)then return end;p.Functions.SetJobDuty(on==true);if on then nt(s,'출근했습니다. 배달 콜을 기다리세요.');schedule(s,n)else active[s]=nil;pending[s]=nil;TriggerClientEvent('cookie_delivery:client:clearAll',s)end;state(s,n)end)
RegisterNetEvent('cookie_delivery:server:acceptCall',function()
 local s=source
 if not cookieAllowAction(s,'delivery_accept',700,1) then return end
 local a=pending[s]
 if not a or a.waiting or not a.restaurant or not a.dropoff then return end
 active[s]=a
 pending[s]=nil
 active[s].picked=false
 TriggerClientEvent('cookie_delivery:client:accepted',s,active[s])
end)
RegisterNetEvent('cookie_delivery:server:declineCall',function()
 local s=source
 if not cookieAllowAction(s,'delivery_decline',700,1) then return end
 local a=pending[s]
 if not a or a.waiting or not a.restaurant or not a.dropoff then return end
 local n=a.npcId
 pending[s]=nil
 TriggerClientEvent('cookie_delivery:client:clearCall',s)
 if duty(s) then SetTimeout(1200,function() if GetPlayerPing(s)>0 and duty(s) then schedule(s,n) end end) end
end)
RegisterNetEvent('cookie_delivery:server:pickup',function()local s=source;if not cookieAllowAction(s,'delivery_pickup',700,1) then return end;local a=active[s];if not a or a.picked then return end;local p=GetEntityCoords(GetPlayerPed(s));local r=a.restaurant;if #(p-vec3(r.pickup_x,r.pickup_y,r.pickup_z))>4 then return end;a.picked=true;TriggerClientEvent('cookie_delivery:client:picked',s,a)end)
RegisterNetEvent('cookie_delivery:server:deliver',function()
 local s=source
 if not cookieAllowAction(s,'delivery_finish',1200,1) then return end
 local a=active[s];if not a or not a.picked then return end
 local p=GetEntityCoords(GetPlayerPed(s));local d=a.dropoff;if #(p-vec3(d.x,d.y,d.z))>4 then return end
 local pl=P(s);if not pl then return end
 local r=a.restaurant;local lv=1;pcall(function()lv=exports.cookie_admin:getCivilLevel(s, D.Job or D.Skill)or 1 end)
 local mult=(D.PayMult and D.PayMult[math.max(1,math.min(5,tonumber(lv)or 1))])or 1.0
 local pay=math.max(0,math.floor(((tonumber(r.base_pay)or D.DefaultBasePay)+a.distanceKm*(tonumber(r.per_km)or D.DefaultPerKm))*mult))
 local okPay,paid=pcall(function() return pl.Functions.AddMoney('bank',pay,'배달기사') end)
 if not okPay or paid==false then return nt(s,'배달 보수 지급에 실패했습니다. 다시 완료를 눌러주세요.',true) end
 pcall(function()exports.cookie_skill:addExp(s,D.Skill,D.ExpPerDelivery or 3);exports.cookie_skill:record(s,D.Skill,pay)end)
 local n=a.npcId;active[s]=nil;TriggerClientEvent('cookie_delivery:client:completed',s,{reward=pay})
 SetTimeout(1500,function()if GetPlayerPing(s)>0 and duty(s)then schedule(s,n)end end)
end)
RegisterNetEvent('cookie_delivery:server:quit',function(n)local s=source;local p=P(s);if p then p.Functions.SetJobDuty(false);p.Functions.SetJob('unemployed',0)end;active[s]=nil;pending[s]=nil;TriggerClientEvent('cookie_delivery:client:clearAll',s);state(s,n)end)
