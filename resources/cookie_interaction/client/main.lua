local interactionOpen,inviteOpen,tradeOpen,licenseCardOpen=false,false,false,false
local currentTarget,currentTradeId=nil,nil
local currentTargetTest=false
local testNpc=0
local testTrade=nil

local function notify(msg,err) TriggerEvent('cookie_admin:client:notify',tostring(msg or ''),err==true) end
local function focus(on) SetNuiFocus(on,on) end
local function rotToDir(r)local z,x=math.rad(r.z),math.rad(r.x);local c=math.abs(math.cos(x));return vec3(-math.sin(z)*c,math.cos(z)*c,math.sin(x))end
local function closeInteraction()interactionOpen=false;currentTarget=nil;currentTargetTest=false;SendNUIMessage({action='interactionClose'});if not inviteOpen and not tradeOpen and not licenseCardOpen then focus(false) end end
local function closeInvite()inviteOpen=false;SendNUIMessage({action='tradeInviteClose'});if not interactionOpen and not tradeOpen and not licenseCardOpen then focus(false) end end
local function closeTrade()tradeOpen=false;currentTradeId=nil;testTrade=nil;SendNUIMessage({action='tradeClose'});if not interactionOpen and not inviteOpen and not licenseCardOpen then focus(false) end end

local function loadModel(model)
    local hash=joaat(model);RequestModel(hash);local deadline=GetGameTimer()+5000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

RegisterNetEvent('cookie_interaction:client:deleteTestNpc',function()
    if testNpc~=0 and DoesEntityExist(testNpc) then DeletePed(testNpc) end
    testNpc=0;notify('상호작용 테스트 시민을 삭제했습니다.',false)
end)

RegisterNetEvent('cookie_interaction:client:spawnTestNpc',function()
    if testNpc~=0 and DoesEntityExist(testNpc) then DeletePed(testNpc) end
    local hash=loadModel('a_m_y_business_01');if not hash then return notify('테스트 NPC 모델을 불러오지 못했습니다.',true) end
    local me=PlayerPedId();local pos=GetOffsetFromEntityInWorldCoords(me,0.0,1.8,0.0)
    testNpc=CreatePed(4,hash,pos.x,pos.y,pos.z,GetEntityHeading(me)+180.0,false,false);SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(testNpc,true,true);SetEntityInvincible(testNpc,true);FreezeEntityPosition(testNpc,true);SetBlockingOfNonTemporaryEvents(testNpc,true);SetPedCanRagdoll(testNpc,false)
    TaskStartScenarioInPlace(testNpc,'WORLD_HUMAN_STAND_MOBILE',0,true)
    notify('테스트 시민을 앞에 소환했습니다. NPC를 바라보고 CAPSLOCK을 눌러보세요.',false)
end)

local function lookedAtTarget(maxDistance)
    local cam=GetGameplayCamCoord();local dir=rotToDir(GetGameplayCamRot(2));local dest=cam+dir*maxDistance
    local ray=StartShapeTestRay(cam.x,cam.y,cam.z,dest.x,dest.y,dest.z,-1,PlayerPedId(),7)
    local _,hit,_,_,entity=GetShapeTestResult(ray)
    if hit==1 and entity~=0 and IsEntityAPed(entity) then
        if testNpc~=0 and entity==testNpc then return {test=true,source=-999} end
        if IsPedAPlayer(entity) then local idx=NetworkGetPlayerIndexFromPed(entity);if idx and idx~=-1 and idx~=PlayerId() then return {test=false,source=GetPlayerServerId(idx)} end end
    end
    local me=GetEntityCoords(PlayerPedId());local best,bestDot=nil,0.94
    if testNpc~=0 and DoesEntityExist(testNpc) then
        local d=GetEntityCoords(testNpc)-me;local dist=#d;if dist>0.01 and dist<=maxDistance then local nd=d/dist;local dot=dir.x*nd.x+dir.y*nd.y+dir.z*nd.z;if dot>bestDot then bestDot=dot;best={test=true,source=-999} end end
    end
    for _,pid in ipairs(GetActivePlayers()) do if pid~=PlayerId() then local ped=GetPlayerPed(pid);if ped~=0 and DoesEntityExist(ped) then local d=GetEntityCoords(ped)-me;local dist=#d;if dist>0.01 and dist<=maxDistance then local nd=d/dist;local dot=dir.x*nd.x+dir.y*nd.y+dir.z*nd.z;if dot>bestDot then bestDot=dot;best={test=false,source=GetPlayerServerId(pid)} end end end end end
    return best
end

local function testProfile()return{source=-999,gobun=9999,name='테스트 시민',label='9999 / 테스트 시민',faction=nil,test=true,canRequestLicense=true}end
local function myProfile()
    local g=LocalPlayer.state and LocalPlayer.state.cookieGobun or nil
    return {
        source=GetPlayerServerId(PlayerId()),
        gobun=g,
        name=GetPlayerName(PlayerId()) or '나',
        label=(g and tostring(g) or '-')..' / '..(GetPlayerName(PlayerId()) or '나'),
        faction=nil
    }
end
local function pushTestState()
    if not testTrade then return end
    SendNUIMessage({action='tradeState',data={tradeId=-999,me=testTrade.me,other=testTrade.other,myOffer=testTrade.myOffer,theirOffer=testTrade.theirOffer,myReady=testTrade.ready,theirReady=true,myConfirmed=testTrade.confirmed,theirConfirmed=true,bothReady=testTrade.ready,expiresAt=os.time()+9999,testMode=true}})
end
local function openTestTrade()
    local r=lib.callback.await('cookie_interaction:getMyTradeData',false)

    local me=myProfile()
    local a={money={cash=0,bank=0},items={},vehicles={},titles={},assets={},assetKinds={}}

    if type(r)=='table' and r.ok==true then
        if type(r.profile)=='table' then me=r.profile end
        if type(r.assets)=='table' then a=r.assets end
    else
        notify('내 거래 자산을 불러오지 못했습니다. 서버 콘솔의 TRADE ASSETS 로그를 확인해주세요.',true)
    end

    testTrade={
        me=me,
        other=testProfile(),
        assets=a,
        myOffer={},
        theirOffer={
            {key='test:cash',type='money',label='테스트 현금 1,000,000원'},
            {key='test:weapon',type='item',weapon=true,label='테스트 권총 · SERIAL TEST-001'}
        },
        ready=false,
        confirmed=false
    }

    tradeOpen=true
    currentTradeId=-999
    focus(true)

    SendNUIMessage({
        action='tradeOpen',
        data={
            tradeId=-999,
            state={
                tradeId=-999,
                me=testTrade.me,
                other=testTrade.other,
                myOffer={},
                theirOffer=testTrade.theirOffer,
                myReady=false,
                theirReady=true,
                myConfirmed=false,
                theirConfirmed=true,
                bothReady=false,
                testMode=true
            },
            assets=a
        }
    })
end
local function findAsset(data)
    if not testTrade then return nil end;local t=tostring(data.type or '');local id=tonumber(data.id)
    if t=='item' then for _,x in ipairs(testTrade.assets.items or {}) do if tonumber(x.id)==id then local c=math.max(1,math.min(tonumber(data.count) or 1,tonumber(x.count) or 1));return{key='item:'..id,type='item',weapon=x.weapon,label=(x.label or x.name)..' x'..c}end end
    elseif t=='vehicle' then for _,x in ipairs(testTrade.assets.vehicles or {}) do if tonumber(x.id)==id then return{key='vehicle:'..id,type='vehicle',label=(x.label or x.model)..' · '..(x.plate or '-')}end end
    elseif t=='title' then for _,x in ipairs(testTrade.assets.titles or {}) do if tonumber(x.id)==id then return{key='title:'..id,type='title',label=(x.kind=='chat' and '채팅칭호 · ' or '머리위칭호 · ')..(x.label or '-')}end end
    elseif t=='asset' then for _,x in ipairs(testTrade.assets.assets or {}) do if tonumber(x.id)==id then return{key='asset:'..id,type='asset',label=((testTrade.assets.assetKinds or {})[x.kind] or x.kind)..' · '..(x.label or '-')}end end
    elseif t=='money' then local mt=tostring(data.moneyType or 'cash');local amount=math.max(1,math.floor(tonumber(data.amount) or 0));return{key='money:'..mt,type='money',label=(mt=='bank' and '은행 ' or '현금 ')..amount..'원'} end
end

RegisterCommand('cookie_interaction',function()
    if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) or inviteOpen or tradeOpen then return end
    if interactionOpen then return closeInteraction() end
    local target=lookedAtTarget(Config.LookDistance or 4.0);if not target then return notify('앞에 있는 시민을 바라보고 CAPSLOCK을 눌러주세요.',true) end
    if target.test then currentTarget=-999;currentTargetTest=true;interactionOpen=true;focus(true);SendNUIMessage({action='interactionOpen',target=testProfile()});return end
    local r=lib.callback.await('cookie_interaction:getTarget',false,target.source);if not r or r.ok~=true then return notify(r and r.message or '상대방 정보를 불러오지 못했습니다.',true) end
    currentTarget=target.source;currentTargetTest=false;interactionOpen=true;focus(true);SendNUIMessage({action='interactionOpen',target=r.target})
end,false)
RegisterKeyMapping('cookie_interaction','바라보는 시민 상호작용','keyboard',Config.Key or 'CAPITAL')
RegisterNUICallback('interactionClose',function(_,cb)cb({ok=true});closeInteraction()end)
RegisterNUICallback('interactionSelect',function(data,cb)
    cb({ok=true})

    local action=tostring(data and data.action or '')
    local target=tonumber(data and data.target) or currentTarget

    if currentTargetTest or target==-999 then
        closeInteraction()
        if action=='trade' then
            openTestTrade()
        elseif action=='confess' then
            TriggerEvent('cookie_admin:client:coupleInteraction',{
                target=-999,name='테스트 시민',gobun=9999,ringCount=1,testMode=true
            })
        elseif action=='license_request' then
            licenseCardOpen=true
            focus(true)
            SendNUIMessage({
                action='driverLicenseCard',
                data={
                    holder={
                        gobun=9999,
                        name='테스트 시민',
                        label='9999 / 테스트 시민'
                    },
                    licenseNo='CKD-TEST001',
                    statusLabel='정상',
                    suspended=false,
                    suspendedUntil='-',
                    reason='정상 면허 · TEST NPC'
                }
            })
            notify('TEST NPC가 운전면허증을 제시했습니다.',false)
        end
        return
    end

    if not target then return closeInteraction() end
    closeInteraction()

    if action=='trade' then
        TriggerServerEvent('cookie_interaction:server:requestTrade',target)
    elseif action=='confess' then
        TriggerServerEvent('cookie_admin:server:requestCoupleInteraction',target)
    elseif action=='license_request' then
        TriggerServerEvent('cookie_interaction:server:requestDriverLicense',target)
    end
end)

RegisterNetEvent('cookie_interaction:client:driverLicenseRequest',function(data)
    data=type(data)=='table' and data or {}
    local officer=data.officer or {}
    local faction=officer.faction or {}
    local org=tostring(faction.name or '경찰청/보안국')
    local who=tostring(officer.label or '담당자')

    local result=lib.alertDialog({
        header='운전면허증 제시 요청',
        content=('%s 소속 %s 님이 운전면허증 제시를 요청했습니다.\n\n운전면허번호와 현재 면허 상태가 담당자에게 표시됩니다.'):format(org,who),
        centered=true,
        cancel=true,
        labels={
            confirm='운전면허증 제시',
            cancel='거절'
        }
    })

    TriggerServerEvent(
        'cookie_interaction:server:replyDriverLicense',
        tonumber(data.requestId),
        result=='confirm'
    )
end)

RegisterNetEvent('cookie_interaction:client:driverLicenseCard',function(data)
    closeInteraction()
    closeInvite()

    licenseCardOpen=true
    focus(true)
    SendNUIMessage({
        action='driverLicenseCard',
        data=data or {}
    })
end)

RegisterNUICallback('licenseCardClose',function(_,cb)
    cb({ok=true})
    licenseCardOpen=false
    SendNUIMessage({action='driverLicenseCardClose'})
    if not interactionOpen and not inviteOpen and not tradeOpen then
        focus(false)
    end
end)

RegisterNetEvent('cookie_interaction:client:tradeInvite',function(d)closeInteraction();inviteOpen=true;focus(true);SendNUIMessage({action='tradeInvite',data=d or {}})end)
RegisterNUICallback('tradeInviteReply',function(d,cb)cb({ok=true});local id=tonumber(d and d.requestId);local ok=d and d.accepted==true;closeInvite();if id then TriggerServerEvent('cookie_interaction:server:replyTrade',id,ok)end end)
RegisterNetEvent('cookie_interaction:client:tradeOpen',function(d)closeInteraction();closeInvite();tradeOpen=true;currentTradeId=tonumber(d and d.tradeId);focus(true);SendNUIMessage({action='tradeOpen',data=d or {}})end)
RegisterNetEvent('cookie_interaction:client:tradeState',function(d)if tradeOpen then SendNUIMessage({action='tradeState',data=d or {}})end end)
RegisterNetEvent('cookie_interaction:client:tradeAssets',function(d)if tradeOpen then SendNUIMessage({action='tradeAssets',data=d or {}})end end)
RegisterNetEvent('cookie_interaction:client:tradeClosed',function(d)closeTrade();if d and d.message then notify(d.message,d.isError==true)end end)
RegisterNUICallback('tradeAddOffer',function(d,cb)cb({ok=true});if currentTradeId==-999 and testTrade then local row=findAsset(d or {});if row then local found=false;for i,x in ipairs(testTrade.myOffer)do if x.key==row.key then testTrade.myOffer[i]=row;found=true;break end end;if not found then table.insert(testTrade.myOffer,row)end;testTrade.ready=false;testTrade.confirmed=false;pushTestState()end;return end;if currentTradeId then TriggerServerEvent('cookie_interaction:server:addOffer',currentTradeId,d or {})end end)
RegisterNUICallback('tradeRemoveOffer',function(d,cb)cb({ok=true});if currentTradeId==-999 and testTrade then local key=tostring(d and d.key or '');for i=#testTrade.myOffer,1,-1 do if testTrade.myOffer[i].key==key then table.remove(testTrade.myOffer,i)end end;testTrade.ready=false;testTrade.confirmed=false;pushTestState();return end;if currentTradeId then TriggerServerEvent('cookie_interaction:server:removeOffer',currentTradeId,tostring(d and d.key or ''))end end)
RegisterNUICallback('tradeReady',function(d,cb)cb({ok=true});if currentTradeId==-999 and testTrade then testTrade.ready=d and d.ready==true;testTrade.confirmed=false;pushTestState();return end;if currentTradeId then TriggerServerEvent('cookie_interaction:server:setReady',currentTradeId,d and d.ready==true)end end)
RegisterNUICallback('tradeConfirm',function(_,cb)cb({ok=true});if currentTradeId==-999 and testTrade then if not testTrade.ready then return notify('먼저 거래 준비를 눌러주세요.',true)end;testTrade.confirmed=true;pushTestState();CreateThread(function()Wait(550);notify('테스트 거래 완료! 실제 돈·아이템·소유권은 변경되지 않았습니다.',false);closeTrade()end);return end;if currentTradeId then TriggerServerEvent('cookie_interaction:server:confirm',currentTradeId)end end)
RegisterNUICallback('tradeRefreshAssets',function(_,cb)
    cb({ok=true})

    if currentTradeId==-999 and testTrade then
        local r=lib.callback.await('cookie_interaction:getMyTradeData',false)
        if type(r)=='table' and r.ok==true then
            if type(r.profile)=='table' then
                testTrade.me=r.profile
            end
            if type(r.assets)=='table' then
                testTrade.assets=r.assets
            end
            pushTestState()
            SendNUIMessage({action='tradeAssets',data=testTrade.assets})
        else
            notify('보유목록을 새로고침하지 못했습니다.',true)
        end
        return
    end

    if currentTradeId then
        TriggerServerEvent('cookie_interaction:server:refreshAssets',currentTradeId)
    end
end)
RegisterNUICallback('tradeCancel',function(_,cb)cb({ok=true});if currentTradeId==-999 then closeTrade();return end;if currentTradeId then TriggerServerEvent('cookie_interaction:server:cancel',currentTradeId,'거래를 취소했습니다.')end end)
CreateThread(function()while true do if tradeOpen then DisableControlAction(0,24,true);DisableControlAction(0,25,true);DisableControlAction(0,37,true);Wait(0)else Wait(500)end end end)
AddEventHandler('onClientResourceStop',function(r)if r==GetCurrentResourceName()then focus(false);if testNpc~=0 and DoesEntityExist(testNpc)then DeletePed(testNpc)end end end)
print('^2[cookie_interaction]^7 CAPSLOCK interaction + test NPC ready')
