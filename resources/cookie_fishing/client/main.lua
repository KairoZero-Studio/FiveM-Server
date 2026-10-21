local fishingBusy=false
local managerOpen=false
local fishingGameOpen=false
local fishingGameToken=nil
local equippedRodItem=nil
local equippedRodLabel=nil
local fishingRodObj=nil
local continuousFishing=false
local fishingCancelRequested=false
local fishPromptState=nil
local nextRodInventoryCheck=0
local fishingLockedHeading=nil

local ROD_INFO={
    fishingrod={label='초급 낚싯대'},
    fishingrod_mid={label='중급 낚싯대'},
    fishingrod_pro={label='고급 낚싯대'},
}

local FISH_KEYS={
    w={control=32,label='W'},
    a={control=34,label='A'},
    s={control=33,label='S'},
    d={control=35,label='D'},
    q={control=44,label='Q'},
    e={control=38,label='E'},
}

local function notify(msg,err)
    if lib and lib.notify then
        lib.notify({title='낚시',description=msg,type=err and 'error' or 'inform'})
    end
end

local function loadModel(model)
    local hash=type(model)=='number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local untilAt=GetGameTimer()+3500
    while not HasModelLoaded(hash) and GetGameTimer()<untilAt do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadAnim(dict)
    RequestAnimDict(dict)
    local untilAt=GetGameTimer()+2500
    while not HasAnimDictLoaded(dict) and GetGameTimer()<untilAt do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function removeFishingRodObject()
    if fishingRodObj and DoesEntityExist(fishingRodObj) then
        DeleteEntity(fishingRodObj)
    end
    fishingRodObj=nil
end

local function attachFishingRodObject()
    if fishingRodObj and DoesEntityExist(fishingRodObj) then return true end
    local ped=PlayerPedId()
    if ped==0 then return false end
    local hash=loadModel('prop_fishing_rod_01')
    if not hash then
        notify('낚싯대 오브젝트를 불러오지 못했습니다.',true)
        return false
    end
    local obj=CreateObject(hash,0.0,0.0,0.0,true,true,false)
    if not obj or obj==0 then
        SetModelAsNoLongerNeeded(hash)
        return false
    end
    SetEntityCollision(obj,false,false)
    SetEntityAsMissionEntity(obj,true,true)
    AttachEntityToEntity(obj,ped,GetPedBoneIndex(ped,60309),0.0,0.0,0.0,0.0,0.0,0.0,true,true,false,true,1,true)
    fishingRodObj=obj
    SetModelAsNoLongerNeeded(hash)
    return true
end

local function playFishingHoldAnim()
    local ped=PlayerPedId()
    if ped==0 or IsPedInAnyVehicle(ped,false) then return end
    local dict='amb@world_human_stand_fishing@idle_a'
    if loadAnim(dict) then
        TaskPlayAnim(ped,dict,'idle_c',3.0,3.0,-1,49,0.0,false,false,false)
    end
end

local function clearFishingAnim()
    local ped=PlayerPedId()
    if ped~=0 then
        StopAnimTask(ped,'amb@world_human_stand_fishing@idle_a','idle_c',1.0)
    end
end

local function currentFishingZone()
    local ok,z=pcall(function() return exports.cookie_safezone:getFishingZone() end)
    if ok and type(z)=='table' then return z end
    return nil
end

local function localItemCount(item)
    if not item or item=='' then return 0 end
    local ok,n=pcall(function() return exports.ox_inventory:Search('count',item) end)
    return ok and (tonumber(n) or 0) or 0
end


local function lockFishingPed()
    local ped=PlayerPedId()
    if ped==0 or not DoesEntityExist(ped) then return end
    if fishingLockedHeading==nil then
        fishingLockedHeading=GetEntityHeading(ped)
    end
    FreezeEntityPosition(ped,true)
    SetEntityHeading(ped,fishingLockedHeading)
end

local function unlockFishingPed()
    local ped=PlayerPedId()
    if ped~=0 and DoesEntityExist(ped) then
        FreezeEntityPosition(ped,false)
    end
    fishingLockedHeading=nil
end

local function suppressFishingMovement()
    local ped=PlayerPedId()
    DisableControlAction(0,30,true) -- move left/right
    DisableControlAction(0,31,true) -- move forward/back
    DisableControlAction(0,32,true) -- W
    DisableControlAction(0,33,true) -- S
    DisableControlAction(0,34,true) -- A
    DisableControlAction(0,35,true) -- D
    DisableControlAction(0,21,true) -- sprint
    DisableControlAction(0,22,true) -- jump
    DisableControlAction(0,23,true) -- enter vehicle
    DisableControlAction(0,24,true) -- attack
    DisableControlAction(0,25,true) -- aim
    DisableControlAction(0,36,true) -- duck
    DisableControlAction(0,37,true) -- weapon wheel
    DisableControlAction(0,44,true) -- Q
    DisableControlAction(0,45,true) -- R/reload
    DisablePlayerFiring(ped,true)

    lockFishingPed()
end

local function setFishPrompt(state,text)
    state=state or 'hidden'
    if fishPromptState==state then return end
    fishPromptState=state
    SendNUIMessage({action='fishPrompt',show=state~='hidden',text=text or ''})
end

local function closeClassicGame(result)
    fishingGameOpen=false
    SendNUIMessage({action='fishGameClose',result=result})
end

local function stopContinuousFishing(reason,refund)
    local wasRunning=continuousFishing or fishingBusy or fishingGameOpen
    continuousFishing=false
    fishingCancelRequested=true
    if fishingGameOpen then closeClassicGame('cancel') end
    local token=fishingGameToken
    fishingGameToken=nil
    fishingBusy=false
    clearFishingAnim()
    unlockFishingPed()
    if token and refund~=false then
        TriggerServerEvent('cookie_fishing:server:cancel',token)
    end
    if reason and wasRunning then notify(reason,false) end
end

local function unequipRod(reason)
    stopContinuousFishing(nil,true)
    equippedRodItem=nil
    equippedRodLabel=nil
    removeFishingRodObject()
    clearFishingAnim()
    unlockFishingPed()
    setFishPrompt('hidden')
    if reason then notify(reason,false) end
end

local function resolveUsedItem(data,slot)
    if type(data)=='string' then return data end
    if type(data)=='table' then
        if type(data.name)=='string' and data.name~='' then return data.name end
        if type(data.item)=='string' and data.item~='' then return data.item end
    end
    if tonumber(slot) then
        local ok,s=pcall(function() return exports.ox_inventory:GetSlot(tonumber(slot)) end)
        if ok and type(s)=='table' and s.name then return tostring(s.name) end
    end
    return nil
end

exports('useFishingRod',function(data,slot)
    local item=resolveUsedItem(data,slot)
    local info=item and ROD_INFO[item]
    if not info then
        notify('낚싯대 아이템 정보를 확인하지 못했습니다.',true)
        return
    end

    if equippedRodItem==item then
        unequipRod(info.label..'를 넣었습니다.')
        return
    end

    if continuousFishing or fishingBusy then
        stopContinuousFishing(nil,true)
        Wait(120)
    end

    equippedRodItem=item
    equippedRodLabel=info.label
    removeFishingRodObject()
    if not attachFishingRodObject() then
        equippedRodItem=nil
        equippedRodLabel=nil
        return
    end
    playFishingHoldAnim()
    notify(('%s를 들었습니다. 낚시터에서 E를 누르면 시작합니다.'):format(info.label),false)
end)

local function normalizeFishingSequence(seq)
    local out={}
    for _,raw in ipairs(type(seq)=='table' and seq or {}) do
        local key=tostring(raw or ''):lower()
        if FISH_KEYS[key] then out[#out+1]=key end
    end
    if #out==0 then out={'w','a','s'} end
    return out
end

local function waitClassicFishingGame(seq,durationMs,gradeLabel,gradeColor)
    fishingGameOpen=true
    local ped=PlayerPedId()
    local index=1
    local duration=math.max(1800,tonumber(durationMs) or 6000)
    local deadline=GetGameTimer()+duration
    local display={}
    for i,key in ipairs(seq) do display[i]={key=key,label=FISH_KEYS[key].label} end

    -- E로 연속 낚시를 시작한 순간의 위치/방향을 유지한다.
    -- 미니게임 한 판이 끝나도 여기서는 절대 잠금을 풀지 않는다.
    lockFishingPed()

    SendNUIMessage({
        action='fishGameOpen',sequence=display,
        duration=duration,
        gradeLabel=gradeLabel or '낚시',gradeColor=gradeColor or '#4dabf7'
    })

    while fishingGameOpen do
        Wait(0)
        suppressFishingMovement()

        -- Q/E는 신화·초월 키 입력용이라 disabled input으로 읽는다.
        DisableControlAction(0,38,true)

        if fishingCancelRequested or not continuousFishing then
            closeClassicGame('cancel')
            return false,'manual_cancel'
        end
        if IsEntityDead(PlayerPedId()) then
            closeClassicGame('cancel')
            return false,'dead'
        end
        if GetGameTimer()>=deadline then
            SendNUIMessage({action='fishGameFail',index=index,reason='time'})
            Wait(330)
            closeClassicGame('fail')
            return false,'timeout'
        end

        local pressed=nil
        for key,def in pairs(FISH_KEYS) do
            if IsDisabledControlJustPressed(0,def.control) or IsControlJustPressed(0,def.control) then
                pressed=key
                break
            end
        end

        if pressed then
            local expected=seq[index]
            if pressed==expected then
                SendNUIMessage({action='fishGameHit',index=index})
                index=index+1
                if index>#seq then
                    SendNUIMessage({action='fishGameSuccess'})
                    Wait(260)
                    closeClassicGame('success')
                    return true,'success'
                end
                SendNUIMessage({action='fishGameCurrent',index=index})
            else
                SendNUIMessage({action='fishGameFail',index=index,reason='wrong',pressed=FISH_KEYS[pressed].label})
                Wait(350)
                closeClassicGame('fail')
                return false,'wrong_key'
            end
        end
    end

    return false,'cancelled'
end

local function requestFishingRound(delayMs)
    CreateThread(function()
        Wait(math.max(0,tonumber(delayMs) or 0))
        if not continuousFishing or fishingBusy or not equippedRodItem then return end
        local zone=currentFishingZone()
        if not zone then
            stopContinuousFishing('낚시 범위를 벗어나 자동 낚시를 중지했습니다.',false)
            return
        end
        if localItemCount(equippedRodItem)<=0 then
            unequipRod('들고 있던 낚싯대가 인벤토리에 없어 장착을 해제했습니다.')
            return
        end
        fishingBusy=true
        fishingCancelRequested=false
        attachFishingRodObject()
        playFishingHoldAnim()
        TriggerServerEvent('cookie_fishing:server:start',equippedRodItem)
    end)
end

RegisterNetEvent('cookie_fishing:client:startRejected',function()
    fishingBusy=false
    fishingGameToken=nil
    fishingCancelRequested=false
    continuousFishing=false
    unlockFishingPed()
    setFishPrompt('hidden')
end)

RegisterNetEvent('cookie_fishing:client:bite',function(data)
    fishingBusy=true
    local min,max=tonumber(data.biteMin) or 3500,tonumber(data.biteMax) or 8000
    if max<min then max=min end
    local token=tostring(data.token or '')
    fishingGameToken=token
    if fishingCancelRequested or not continuousFishing or not equippedRodItem then
        TriggerServerEvent('cookie_fishing:server:cancel',token)
        fishingGameToken=nil
        fishingBusy=false
        return
    end

    notify((data.rodLabel or equippedRodLabel or '낚싯대')..' · 입질을 기다리는 중...',false)
    local biteUntil=GetGameTimer()+math.random(math.floor(min),math.floor(max))
    while GetGameTimer()<biteUntil do
        Wait(50)
        if fishingCancelRequested or not continuousFishing then return end
        if not currentFishingZone() then
            stopContinuousFishing('낚시 범위를 벗어나 자동 낚시를 중지했습니다.',true)
            return
        end
        if IsEntityDead(PlayerPedId()) then
            stopContinuousFishing('낚시를 중지했습니다.',true)
            return
        end
    end

    if fishingCancelRequested or not continuousFishing then return end
    local seq=normalizeFishingSequence(data.seq)
    local ok,reason=waitClassicFishingGame(seq,tonumber(data.gameMs) or 6000,data.gradeLabel,data.gradeColor)

    if fishingCancelRequested or not continuousFishing or reason=='manual_cancel' then return end
    TriggerServerEvent('cookie_fishing:server:finish',ok==true,token,reason)
    fishingGameToken=nil
    fishingBusy=false

    if continuousFishing and equippedRodItem then
        requestFishingRound(ok and 650 or 900)
    end
end)

RegisterNetEvent('cookie_fishing:client:cancelPending',function(reason)
    if fishingGameOpen then closeClassicGame('cancel') end
    fishingBusy=false
    fishingGameToken=nil
    fishingCancelRequested=false
    continuousFishing=false
    clearFishingAnim()
    unlockFishingPed()
    if reason and reason~='' then notify(reason,true) end
end)

RegisterNetEvent('cookie_fishing:client:caught',function(d)
    notify(('%s %.2fkg 획득 · %s'):format(d.label or '물고기',tonumber(d.kg) or 0,d.gradeLabel or ''),false)
end)
RegisterNetEvent('cookie_fishing:client:hof',function(d)
    if d then notify(('낚시왕: %s · %s %.2fkg'):format(d.nickname or '무명',d.label or '-',tonumber(d.kg) or 0),false) end
end)

CreateThread(function()
    while true do
        local wait=400
        if equippedRodItem then
            wait=0
            if IsEntityDead(PlayerPedId()) then
                unequipRod()
                Wait(500)
            else
                if GetGameTimer()>=nextRodInventoryCheck then
                    nextRodInventoryCheck=GetGameTimer()+1000
                    if localItemCount(equippedRodItem)<=0 then
                        unequipRod('낚싯대가 없어 장착을 해제했습니다.')
                    end
                end

                if equippedRodItem then
                    attachFishingRodObject()
                    local zone=currentFishingZone()
                    if continuousFishing then
                        suppressFishingMovement()
                        setFishPrompt('stop','[BACKSPACE] 낚시 중지')
                        if not zone then
                            stopContinuousFishing('낚시 범위를 벗어나 자동 낚시를 중지했습니다.',true)
                        elseif IsControlJustReleased(0,177) or IsDisabledControlJustReleased(0,177) then
                            stopContinuousFishing('낚시를 중지했습니다.',true)
                        end
                    elseif zone and not fishingBusy then
                        setFishPrompt('start','[E] 낚시 시작')
                        if IsControlJustReleased(0,38) or IsDisabledControlJustReleased(0,38) then
                            continuousFishing=true
                            fishingCancelRequested=false
                            fishingLockedHeading=GetEntityHeading(PlayerPedId())
                            lockFishingPed()
                            setFishPrompt('stop','[BACKSPACE] 낚시 중지')
                            requestFishingRound(0)
                        end
                    else
                        setFishPrompt('hidden')
                    end
                end
            end
        else
            setFishPrompt('hidden')
        end
        Wait(wait)
    end
end)

local function openFishingManager(payload)
    local npcId=tonumber(payload and payload.npcId)
    if not npcId then return false end
    print(('[cookie_fishing] open manager requested npc=%s'):format(npcId))
    TriggerServerEvent('cookie_fishing:server:managerMenu',npcId)
    return true
end

RegisterNetEvent('cookie_fishing:client:openManager',function(payload)
    openFishingManager(payload)
end)

exports('OpenManager',function(payload)
    return openFishingManager(payload)
end)
RegisterNetEvent('cookie_fishing:client:managerMenu',function(data)
    if not data then return end
    managerOpen=true;SetNuiFocus(true,true);SendNUIMessage({action='openManager',data=data})
end)
RegisterNUICallback('managerClose',function(_,cb) managerOpen=false;SetNuiFocus(false,false);cb({ok=true}) end)
RegisterNUICallback('managerBuy',function(d,cb) cb({ok=true});if d then TriggerServerEvent('cookie_fishing:server:buy',d.kind,d.npcId) end end)
RegisterNUICallback('managerSellOne',function(d,cb) cb({ok=true});if d then TriggerServerEvent('cookie_fishing:server:sellOne',d.npcId,d.key,d.slot) end end)
RegisterNUICallback('managerSellAll',function(d,cb) cb({ok=true});if d then TriggerServerEvent('cookie_fishing:server:sellAll',d.npcId) end end)


AddEventHandler('onResourceStop',function(r)
    if r~=GetCurrentResourceName() then return end
    if managerOpen then SetNuiFocus(false,false) end
    continuousFishing=false
    fishingBusy=false
    fishingGameOpen=false
    setFishPrompt('hidden')
    SendNUIMessage({action='fishGameClose',result='cancel'})
    removeFishingRodObject()
    clearFishingAnim()
    unlockFishingPed()
end)

print('^2[cookie_fishing]^7 FULL SESSION MOVEMENT LOCK V1.7.8 active')
