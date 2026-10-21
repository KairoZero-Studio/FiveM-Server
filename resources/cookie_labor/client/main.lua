
local L = Config.Labor

local dialogOpen = false
local currentNpc = nil
local state = nil
local task = nil
local carrying = false
local boxObj = nil
local pileObjs = {}
local routeBlip = nil
local textShown = nil

local CARRY_DICT = 'anim@heists@box_carry@'

local function notify(msg, err)
    TriggerEvent('cookie_admin:client:notify', msg, err and true or false)
end

local function setText(msg)
    if textShown == msg then return end
    textShown = msg
    if msg then
        lib.showTextUI(msg, { position='left-center' })
    else
        lib.hideTextUI()
    end
end

local function clearRoute()
    if routeBlip then RemoveBlip(routeBlip); routeBlip = nil end
end

local function setRoute(c, name)
    clearRoute()
    if not c then return end
    routeBlip = AddBlipForCoord(c.x+0.0, c.y+0.0, c.z+0.0)
    SetBlipSprite(routeBlip, 1)
    SetBlipColour(routeBlip, 5)
    SetBlipScale(routeBlip, 0.8)
    SetBlipRoute(routeBlip, true)
    SetBlipRouteColour(routeBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(name or '건설 작업')
    EndTextCommandSetBlipName(routeBlip)
end

local function drawMarkerAt(c)
    DrawMarker(1, c.x+0.0, c.y+0.0, c.z-1.0,
        0.0,0.0,0.0, 0.0,0.0,0.0,
        2.2,2.2,1.0, 255,184,0,95,
        false,false,0,false,nil,nil,false)
end

local function cleanupPile()
    for _, o in ipairs(pileObjs) do
        if DoesEntityExist(o) then DeleteObject(o) end
    end
    pileObjs = {}
end

local function spawnPile()
    cleanupPile()
    if not task or not L.Pile or L.Pile.enabled == false then return end

    local m = joaat(L.Pile.prop or L.FallbackBoxProp)
    RequestModel(m)
    local timeout = GetGameTimer()+5000
    while not HasModelLoaded(m) and GetGameTimer()<timeout do Wait(20) end
    if not HasModelLoaded(m) then return end

    local c = task.source
    local count = math.max(3, math.min(7, tonumber(L.Pile.count) or 5))
    local spacing = tonumber(L.Pile.spacing) or 0.48

    for i=1,count do
        local row = math.floor((i-1)/3)
        local col = (i-1)%3
        local x = c.x + (col-1)*spacing
        local y = c.y + row*spacing*0.7
        local z = c.z + row*0.42
        local o = CreateObjectNoOffset(m, x,y,z, false,false,false)
        if o and o ~= 0 then
            PlaceObjectOnGroundProperly(o)
            FreezeEntityPosition(o, true)
            SetEntityCollision(o, false, false)
            pileObjs[#pileObjs+1] = o
        end
    end
    SetModelAsNoLongerNeeded(m)
end

local function startCarry()
    if carrying then return end

    local ped = PlayerPedId()
    local model = joaat(L.BoxProp or L.FallbackBoxProp)
    if not IsModelValid(model) then model = joaat(L.FallbackBoxProp) end

    RequestAnimDict(CARRY_DICT)
    RequestModel(model)
    local timeout = GetGameTimer()+5000
    while (not HasAnimDictLoaded(CARRY_DICT) or not HasModelLoaded(model)) and GetGameTimer()<timeout do Wait(20) end

    if not HasModelLoaded(model) then
        notify('상자 모델을 불러오지 못했습니다.', true)
        return
    end

    carrying = true
    TaskPlayAnim(ped, CARRY_DICT, 'idle', 3.0,3.0,-1,49,0.0,false,false,false)

    local p = GetEntityCoords(ped)
    boxObj = CreateObject(model, p.x,p.y,p.z+0.2, false,false,false)
    SetEntityCollision(boxObj, false, false)
    AttachEntityToEntity(boxObj, ped, GetPedBoneIndex(ped,28422),
        0.05,0.08,0.26, -145.0,290.0,0.0,
        true,true,false,true,1,true)

    setRoute(task.dest, '상자 운반 목적지')
end

local function stopCarry()
    if carrying then ClearPedTasks(PlayerPedId()) end
    carrying = false
    if boxObj and DoesEntityExist(boxObj) then
        DetachEntity(boxObj,true,true)
        DeleteEntity(boxObj)
    end
    boxObj = nil
end

local function hideGuide()
    SendNUIMessage({ action='guideHide' })
end

local function updateGuide(line)
    if not task then return end
    SendNUIMessage({
        action='guide',
        label=task.label,
        delivered=task.delivered or 0,
        total=task.total or 0,
        reward=task.reward or 0,
        line=line or '',
    })
end

local function cancelTaskLocal()
    task = nil
    stopCarry()
    cleanupPile()
    clearRoute()
    setText(nil)
    hideGuide()
end


local laborDlgCam = nil

local function laborSetWorldUi(show)
    TriggerEvent('cookie_hud:client:hudVisible', show)
    DisplayRadar(show)
    if not show then
        SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true)
    end
end

local function laborStartCam(npcId)
    if laborDlgCam then return end
    local target=nil
    if npcId then
        local ok,ped=pcall(function() return exports.cookie_admin:getNpcPed(npcId) end)
        target=(ok and ped) or nil
    end
    if not (target and DoesEntityExist(target)) then return end

    local me=PlayerPedId()
    local t=GetPedBoneCoords(target,31086,0.0,0.0,0.0)
    local h=math.rad(GetEntityHeading(target))
    local fx,fy=-math.sin(h),math.cos(h)
    local c=vec3(t.x+fx*1.32-fy*.28,t.y+fy*1.32+fx*.28,t.z+.05)

    TaskTurnPedToFaceEntity(me,target,800)
    laborDlgCam=CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',c.x,c.y,c.z,0.0,0.0,0.0,39.0,false,0)
    PointCamAtCoord(laborDlgCam,t.x,t.y,t.z)
    SetCamActive(laborDlgCam,true)
    RenderScriptCams(true,true,550,true,true)
end

local function laborStopCam()
    if not laborDlgCam then return end
    RenderScriptCams(false,true,450,true,true)
    DestroyCam(laborDlgCam,true)
    laborDlgCam=nil
end

RegisterNetEvent('cookie_labor:client:openDialog', function(data)
    currentNpc = tonumber(data and data.npcId)
    if not currentNpc then return end
    dialogOpen = true
    laborSetWorldUi(false)
    laborStartCam(currentNpc)
    SetNuiFocus(true,true)
    SendNUIMessage({ action='openLoading', npc=(data and data.label) or '건설 반장 권설현' })
    TriggerServerEvent('cookie_labor:server:requestState', currentNpc)
end)

RegisterNetEvent('cookie_labor:client:state', function(d)
    state = d or {}
    if dialogOpen then
        SendNUIMessage({ action='state', data=state })
    end
end)

RegisterNetEvent('cookie_labor:client:line', function(msg)
    SendNUIMessage({ action='toastLine', text=msg })
end)

RegisterNetEvent('cookie_labor:client:task', function(d)
    task = d
    task.delivered = tonumber(task.delivered) or 0
    stopCarry()
    spawnPile()
    setRoute(task.source, '상자 더미')
    updateGuide('상자 더미로 이동하세요')
end)

RegisterNetEvent('cookie_labor:client:cancelTask', cancelTaskLocal)

RegisterNetEvent('cookie_labor:client:pickupApproved', function()
    if not task or carrying then return end
    startCarry()
    updateGuide('상자를 목적지까지 옮기세요')
end)

RegisterNetEvent('cookie_labor:client:delivered', function(d)
    if not task then return end
    task.delivered = tonumber(d and d.delivered) or task.delivered
    stopCarry()
    setRoute(task.source, '상자 더미')
    updateGuide(('다음 상자를 가져오세요 · %d/%d'):format(task.delivered, task.total))
end)

RegisterNetEvent('cookie_labor:client:completed', function(d)
    local pay = tonumber(d and d.pay) or 0
    stopCarry()
    cleanupPile()
    clearRoute()
    setText(nil)
    hideGuide()

    SendNUIMessage({ action='complete', pay=pay })
    task = nil
end)

RegisterNUICallback('close', function(_,cb)
    cb({ok=true})
    dialogOpen=false
    SetNuiFocus(false,false)
    SendNUIMessage({action='close'})
    laborStopCam()
    laborSetWorldUi(true)
    laborStopCam()
    laborSetWorldUi(true)
end)

RegisterNUICallback('hire', function(_,cb)
    cb({ok=true})
    TriggerServerEvent('cookie_labor:server:hire', currentNpc)
end)

RegisterNUICallback('quit', function(_,cb)
    cb({ok=true})
    TriggerServerEvent('cookie_labor:server:quit', currentNpc)
end)

RegisterNUICallback('duty', function(data,cb)
    cb({ok=true})
    TriggerServerEvent('cookie_labor:server:duty', data and data.on == true, currentNpc)
end)

RegisterNUICallback('task', function(_,cb)
    cb({ok=true})
    TriggerServerEvent('cookie_labor:server:requestTask', currentNpc)
end)

CreateThread(function()
    while true do
        local wait = 600
        local hint = nil

        if task then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local src = vec3(task.source.x+0.0,task.source.y+0.0,task.source.z+0.0)
            local dst = vec3(task.dest.x+0.0,task.dest.y+0.0,task.dest.z+0.0)
            local ds = #(pos-src)
            local dd = #(pos-dst)

            if ds < 35.0 then drawMarkerAt(task.source); wait=0 end
            if dd < 35.0 then drawMarkerAt(task.dest); wait=0 end

            if not carrying and task.delivered < task.total and ds <= (L.InteractRadius or 2.2) then
                wait=0
                hint='[E] 상자 들기'
                if IsControlJustPressed(0,38) then
                    TriggerServerEvent('cookie_labor:server:pickup')
                    Wait(300)
                end
            elseif carrying and dd <= (L.InteractRadius or 2.2) then
                wait=0
                hint='[E] 상자 내려놓기'
                if IsControlJustPressed(0,38) then
                    stopCarry()
                    TriggerServerEvent('cookie_labor:server:deliver')
                    Wait(300)
                end
            elseif carrying then
                wait=0
                hint='상자를 지정된 위치까지 운반하세요'
            end
        end

        setText(hint)
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopCarry()
    cleanupPile()
    clearRoute()
    setText(nil)
    SetNuiFocus(false,false)
end)
