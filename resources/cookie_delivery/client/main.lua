print('^2[cookie_delivery] V11 client loaded^7')
local D=Config.Delivery;local npc,state,current,bag,blip=nil,{},nil,nil,nil
local dlgCam=nil
local function setWorldUi(show) TriggerEvent('cookie_hud:client:hudVisible',show);DisplayRadar(show);if not show then SetCurrentPedWeapon(PlayerPedId(),`WEAPON_UNARMED`,true) end end
local function startCam(npcId) if dlgCam then return end;local target=nil;if npcId then local ok,ped=pcall(function()return exports.cookie_admin:getNpcPed(npcId)end);target=(ok and ped)or nil end;if not(target and DoesEntityExist(target))then return end;local me=PlayerPedId();local t=GetPedBoneCoords(target,31086,0.0,0.0,0.0);local h=math.rad(GetEntityHeading(target));local fx,fy=-math.sin(h),math.cos(h);local c=vec3(t.x+fx*1.35-fy*.35,t.y+fy*1.35+fx*.35,t.z+.06);TaskTurnPedToFaceEntity(me,target,800);dlgCam=CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',c.x,c.y,c.z,0,0,0,40.0,false,0);PointCamAtCoord(dlgCam,t.x,t.y,t.z);SetCamActive(dlgCam,true);RenderScriptCams(true,true,600,true,true) end
local function stopCam() if not dlgCam then return end;RenderScriptCams(false,true,500,true,true);DestroyCam(dlgCam,true);dlgCam=nil end

local function route(x,y,z,n)if blip then RemoveBlip(blip)end;blip=AddBlipForCoord(x,y,z);SetBlipRoute(blip,true);BeginTextCommandSetBlipName('STRING');AddTextComponentString(n);EndTextCommandSetBlipName(blip)end
local function carry()local ped=PlayerPedId();local dict='anim@heists@box_carry@';RequestAnimDict(dict);local m=joaat(D.BagProp);RequestModel(m);while not HasAnimDictLoaded(dict)or not HasModelLoaded(m)do Wait(20)end;TaskPlayAnim(ped,dict,'idle',4.0,-4.0,-1,49,0,false,false,false);local p=GetEntityCoords(ped);bag=CreateObject(m,p.x,p.y,p.z,true,true,false);AttachEntityToEntity(bag,ped,GetPedBoneIndex(ped,28422),.02,-.12,-.18,0,0,0,true,true,false,true,1,true)end
local function clear()ClearPedTasks(PlayerPedId());if bag and DoesEntityExist(bag)then DeleteEntity(bag)end;bag=nil;if blip then RemoveBlip(blip);blip=nil end end

-- 배달 콜은 마우스 포커스를 사용하지 않음.
-- NPC 대화창의 NUI 포커스는 기존대로 유지한다.

RegisterNetEvent('cookie_delivery:client:openDialog',function(d) npc=tonumber(d and d.npcId);SetNuiFocus(true,true);setWorldUi(false);startCam(npc);SendNUIMessage({action='open',npc=(d and d.label) or '배달 관리인'});TriggerServerEvent('cookie_delivery:server:requestState',npc) end)
RegisterNetEvent('cookie_delivery:client:state',function(d)state=d;SendNUIMessage({action='state',data=d})end)
RegisterNetEvent('cookie_delivery:client:call',function(d)current=d;SendNUIMessage({action='call',data=d})end)
RegisterNetEvent('cookie_delivery:client:accepted',function(d)
    current=d;route(d.restaurant.pickup_x,d.restaurant.pickup_y,d.restaurant.pickup_z,'음식 픽업');SendNUIMessage({action='accepted'})end)
RegisterNetEvent('cookie_delivery:client:picked',function(d)current=d;carry();route(d.dropoff.x,d.dropoff.y,d.dropoff.z,'배달 목적지');SendNUIMessage({action='picked'})end)
RegisterNetEvent('cookie_delivery:client:completed',function(d)current=nil;clear();SendNUIMessage({action='completed',data=d})end)
RegisterNetEvent('cookie_delivery:client:callExpired',function()
    current=nil
    SendNUIMessage({action='callExpired'})
end)
RegisterNetEvent('cookie_delivery:client:clearCall',function()
    current=nil
    SendNUIMessage({action='clearCall'})
end)
RegisterNetEvent('cookie_delivery:client:clearAll',function()current=nil;clear();SendNUIMessage({action='clearAll'})end)
RegisterNetEvent('cookie_delivery:client:adminData',function(d)SendNUIMessage({action='npcDelivery',data=d})end)
RegisterNUICallback('close',function(_,cb)cb({ok=true});SetNuiFocus(false,false);SendNUIMessage({action='close'});stopCam();setWorldUi(true)end);RegisterNUICallback('hire',function(_,cb)cb({ok=true});TriggerServerEvent('cookie_delivery:server:hire',npc)end);RegisterNUICallback('quit',function(_,cb)cb({ok=true});TriggerServerEvent('cookie_delivery:server:quit',npc)end);RegisterNUICallback('duty',function(d,cb)cb({ok=true});TriggerServerEvent('cookie_delivery:server:duty',d.on==true,npc)end);RegisterNUICallback('accept',function(_,cb)
    cb({ok=true})
    TriggerServerEvent('cookie_delivery:server:acceptCall')
end)


-- 배달 콜 키 조작
-- 마우스 휠: 일반 게임 조작용 14/15 + NUI cursor scroll 241/242 둘 다 감지
local function hasPendingDeliveryOffer()
    return current and current.restaurant and current.dropoff and current.picked == nil
end

local function acceptDeliveryOffer()
    if not hasPendingDeliveryOffer() then return end
    TriggerServerEvent('cookie_delivery:server:acceptCall')
end

local function declineDeliveryOffer()
    if not hasPendingDeliveryOffer() then return end
    TriggerServerEvent('cookie_delivery:server:declineCall')
end

RegisterCommand('deliveryaccept', acceptDeliveryOffer, false)
RegisterCommand('deliverydecline', declineDeliveryOffer, false)

RegisterKeyMapping('deliveryaccept',  '배달 콜 수락', 'keyboard', 'ADD')
RegisterKeyMapping('deliverydecline', '배달 콜 거절', 'keyboard', 'SUBTRACT')

CreateThread(function()
    while true do
        if hasPendingDeliveryOffer() then
            -- 휠 위: INPUT_WEAPON_WHEEL_PREV(15) / CURSOR_SCROLL_UP(241)
            if IsControlJustPressed(0, 15) or IsControlJustPressed(0, 241) then
                acceptDeliveryOffer()
                Wait(250)
            -- 휠 아래: INPUT_WEAPON_WHEEL_NEXT(14) / CURSOR_SCROLL_DOWN(242)
            elseif IsControlJustPressed(0, 14) or IsControlJustPressed(0, 242) then
                declineDeliveryOffer()
                Wait(250)
            end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

CreateThread(function()while true do local w=700;if current then local p=GetEntityCoords(PlayerPedId());local c;if not current.picked then local r=current.restaurant;c=vec3(r.pickup_x,r.pickup_y,r.pickup_z)else local d=current.dropoff;c=vec3(d.x,d.y,d.z)end;local dist=#(p-c);if dist<25 then w=0;DrawMarker(1,c.x,c.y,c.z-1,0,0,0,0,0,0,1.6,1.6,.8,255,184,0,110,false,false,0,false);if dist<2.5 then lib.showTextUI(current.picked and '[E] 음식 전달' or '[E] 음식 픽업',{position='left-center'});if IsControlJustPressed(0,38)then if current.picked then TriggerServerEvent('cookie_delivery:server:deliver')else TriggerServerEvent('cookie_delivery:server:pickup')end;Wait(500)end else lib.hideTextUI()end end else lib.hideTextUI()end;Wait(w)end end)

AddEventHandler('onResourceStop',function(res) if res~=GetCurrentResourceName() then return end;stopCam();SetNuiFocus(false,false);setWorldUi(true) end)


