RegisterNetEvent('cookie_trucker:client:adminPay',function(d)
    SendNUIMessage({action='adminTruckPay',data=d or {}})
end)



local T = Config.Trucker
local open = false
local dlgCam = nil
local curNpcId = nil
local curNpcLabel = '트럭 배차관리인'

local function setWorldUi(show)
    TriggerEvent('cookie_hud:client:hudVisible', show)
    TriggerEvent('cookie_chat:forceHide', not show)
    DisplayRadar(show)
    if not show then
        SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true)
    end
end

local function startCam(npcId)
    if dlgCam then return end
    local me = PlayerPedId()
    local target = nil
    if npcId then
        local ok, ped = pcall(function() return exports.cookie_admin:getNpcPed(npcId) end)
        target = (ok and ped) or nil
    end
    if not (target and DoesEntityExist(target)) then return end

    local tPos = GetPedBoneCoords(target, 31086, 0.0, 0.0, 0.0)
    local h = math.rad(GetEntityHeading(target))
    local fx, fy = -math.sin(h), math.cos(h)
    local camPos = vec3(
        tPos.x + fx * 1.35 - fy * 0.35,
        tPos.y + fy * 1.35 + fx * 0.35,
        tPos.z + 0.06
    )
    TaskTurnPedToFaceEntity(me, target, 800)
    dlgCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, 40.0, false, 0)
    PointCamAtCoord(dlgCam, tPos.x, tPos.y, tPos.z)
    SetCamActive(dlgCam, true)
    RenderScriptCams(true, true, 600, true, true)
end

local function stopCam()
    if not dlgCam then return end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(dlgCam, true)
    dlgCam = nil
end

local function openDialog(payload)
    if open then return end
    open = true
    curNpcId = payload and payload.npcId or nil
    curNpcLabel = (payload and payload.label) or '트럭 배차관리인'
    setWorldUi(false)
    startCam(payload and payload.npcId)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', npc = (payload and payload.label) or '트럭 배차관리인', lines = T.Lines })
    TriggerServerEvent('cookie_trucker:server:requestState', curNpcId)
end

local function closeDialog()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopCam()
    setWorldUi(true)
end

CreateThread(function()
    while true do
        if open then
            DisableAllControlActions(0)
            EnableControlAction(0, 200, true)
            DisplayRadar(false)
            HideHudComponentThisFrame(7)
            HideHudComponentThisFrame(9)
            Wait(0)
        else
            Wait(300)
        end
    end
end)

RegisterNetEvent('cookie_trucker:client:openDialog', function(payload) openDialog(payload) end)

RegisterNetEvent('cookie_trucker:client:state', function(st)
    SendNUIMessage({ action = 'state', state = st })
end)
RegisterNetEvent('cookie_trucker:client:jobs', function(jobs)
    SendNUIMessage({ action = 'jobs', jobs = jobs })
end)
RegisterNetEvent('cookie_trucker:client:line', function(txt)
    SendNUIMessage({ action = 'line', text = txt })
end)

local job = nil
local jobBoarded = false
local curTruck = nil
local myLevel = 1
local carrying = false
local boxObj = nil
local firstLoadShown = false
local jobBlip = nil

local function clearRoute()
    if jobBlip then RemoveBlip(jobBlip); jobBlip = nil end
end
local function setRoute(c)
    clearRoute()
    if not c then return end
    jobBlip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    SetBlipSprite(jobBlip, 1)
    SetBlipColour(jobBlip, 5)
    SetBlipScale(jobBlip, 0.9)
    SetBlipAsShortRange(jobBlip, false)
    SetBlipRoute(jobBlip, true)
    SetBlipRouteColour(jobBlip, 5)
end
local function cineOne(text, gold, npc)
    SendNUIMessage({ action = 'cine', seq = { { text = text, gold = gold, npc = npc } } })
end
local function guideUpd(line)
    if not job then return end
    SendNUIMessage({ action = 'guide', level = myLevel, cap = job.cap, loaded = job.loaded, line = line })
end
local function trunkPos()
    if not (curTruck and DoesEntityExist(curTruck)) then return nil end
    return GetOffsetFromEntityInWorldCoords(curTruck, 0.0, (T.TrunkOffset or -4.6), 0.5)
end

local curTextUi = nil
local function textUi(msg)
    if msg == curTextUi then return end
    curTextUi = msg
    if msg then pcall(function() exports.ox_lib:showTextUI(msg, { position = 'left-center' }) end)
    else pcall(function() exports.ox_lib:hideTextUI() end) end
end
local function drawZone(c)
    DrawMarker(1, c.x + 0.0, c.y + 0.0, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        2.4, 2.4, 1.3, 255, 184, 0, 110, false, false, 0, false, nil, nil, false)
end

local CARRY_DICT = 'anim@heists@box_carry@'
local BOX_MODEL = nil

CreateThread(function()
    local m = GetHashKey(Config.Trucker.BoxProp or 'prop_cardbox_01a')
    if not IsModelValid(m) then m = GetHashKey('prop_cardbox_01a') end
    RequestModel(m)
    local t = GetGameTimer() + 15000
    while not HasModelLoaded(m) and GetGameTimer() < t do Wait(100) end
    if HasModelLoaded(m) then BOX_MODEL = m;
    else  end
end)

local function startCarry()
    if carrying then return end
    local ped = PlayerPedId()
    carrying = true

    RequestAnimDict(CARRY_DICT)
    local a = GetGameTimer() + 2000
    while not HasAnimDictLoaded(CARRY_DICT) and GetGameTimer() < a do Wait(10) end
    TaskPlayAnim(ped, CARRY_DICT, 'idle', 3.0, 3.0, -1, 49, 0.0, false, false, false)

    local model = BOX_MODEL
    if not model then
        model = GetHashKey(T.BoxProp or 'prop_cardbox_01a')
        if not IsModelValid(model) then model = GetHashKey('prop_cardbox_01a') end
        RequestModel(model)
        local b = GetGameTimer() + 5000
        while not HasModelLoaded(model) and GetGameTimer() < b do Wait(20) end
        if HasModelLoaded(model) then BOX_MODEL = model end
    end
    if not model or not HasModelLoaded(model) then

        return
    end
    local co = GetEntityCoords(ped)
    boxObj = CreateObject(model, co.x, co.y, co.z + 0.2, false, false, false)
    if not boxObj or boxObj == 0 or not DoesEntityExist(boxObj) then
         boxObj = nil; return
    end
    SetEntityCollision(boxObj, false, false)
    AttachEntityToEntity(boxObj, ped, GetPedBoneIndex(ped, 28422),
        0.05, 0.08, 0.26, -145.0, 290.0, 0.0, true, true, false, true, 1, true)
end
local function stopCarry()
    local ped = PlayerPedId()
    if carrying then ClearPedTasks(ped) end
    if boxObj and DoesEntityExist(boxObj) then DetachEntity(boxObj, true, true); DeleteEntity(boxObj) end
    boxObj = nil
    carrying = false
end
local function endJobLocal()
    clearRoute(); stopCarry()
    job = nil; jobBoarded = false; curTruck = nil; firstLoadShown = false
    SendNUIMessage({ action = 'guideHide' })
end
local function startGoStock()
    if not job then return end
    job.stage = 'go_stock'
    setRoute(job.stock)
    SendNUIMessage({ action = 'guide', level = myLevel, cap = job.cap, loaded = 0, line = '재고지로 이동하시오.' })
end

RegisterNetEvent('cookie_trucker:client:trucked', function(d)
    CreateThread(function()

        local veh = 0
        local tries = 0
        while tries < 60 do
            veh = d.netId and NetworkGetEntityFromNetworkId(d.netId) or 0
            if veh ~= 0 and DoesEntityExist(veh) then break end
            Wait(50); tries = tries + 1
        end
        if veh == 0 or not DoesEntityExist(veh) then return end

        local me = PlayerPedId()

        SetEntityAlpha(veh, d.alpha or 160, false)

        local npc = curNpcLabel or '트럭 배차관리인'
        SendNUIMessage({ action = 'cine', seq = {
            { text = d.npcCalled  or '트럭을 불렀어. 밖에 세워뒀네.',                       npc = npc },
            { text = d.acceptLine or '배송을 수락했습니다. 트럭에 재고를 채우러 가세요',      gold = true },
            { text = d.warnLine   or '안전운전을 기원하네, 차 다치게 하면 너도 다칠줄 알아!',  npc = npc },
        } })

        local dur = (d.outline or 10) * 1000
        local until_ = GetGameTimer() + dur
        pcall(function()
            SetEntityDrawOutline(veh, true)
            SetEntityDrawOutlineColor(255, 184, 0, 255)
            SetEntityDrawOutlineShader(1)
        end)

        local boarded = false
        while GetGameTimer() < until_ do
            if not DoesEntityExist(veh) then return end
            if IsPedInVehicle(me, veh, false) then boarded = true; break end
            local c = GetEntityCoords(veh)

            DrawMarker(2, c.x, c.y, c.z + 2.7, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                0.6, 0.6, 0.6, 255, 184, 0, 215, true, false, 0, false, nil, nil, false)
            Wait(0)
        end

        pcall(function() SetEntityDrawOutline(veh, false) end)
        if DoesEntityExist(veh) then ResetEntityAlpha(veh) end

        if not boarded then
            local giveUp = GetGameTimer() + 60000
            while GetGameTimer() < giveUp do
                if not DoesEntityExist(veh) then return end
                if IsPedInVehicle(me, veh, false) then boarded = true; break end
                Wait(250)
            end
        end
        if not boarded then return end

        myLevel = d.level or 1
        curTruck = veh
        jobBoarded = true
        if job then
            startGoStock()
        else
            SendNUIMessage({ action = 'guide', level = myLevel, cap = d.cap or 15, loaded = 0,
                             line = d.goLine or '재고지로 이동하시오.' })
        end
    end)
end)

RegisterNUICallback('close', function(_, cb) cb({ ok = true }); closeDialog() end)
RegisterNUICallback('hire',  function(_, cb) cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:hire') end)
RegisterNUICallback('quit',  function(_, cb) cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:quit') end)
RegisterNUICallback('duty',  function(d, cb) cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:duty', d and d.on == true) end)
RegisterNUICallback('requestJobs', function(_, cb) cb({ ok = true }); TriggerServerEvent('cookie_trucker:server:requestJobs') end)
RegisterNUICallback('accept', function(d, cb)
    cb({ ok = true })
    if d and d.id then TriggerServerEvent('cookie_trucker:server:accept', d.id) end
    closeDialog()
end)

CreateThread(function()
    while true do
        local w = 500
        local want = nil
        if job and job.stage ~= 'board_wait' and job.stage ~= 'done' then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local IR = T.InteractRadius or 2.6
            local AR = T.ArriveRadius or 28.0

            if job.stage == 'go_stock' then
                w = 250
                if #(pos - vec3(job.stock.x, job.stock.y, job.stock.z)) < AR then
                    job.stage = 'loading'; clearRoute()
                    cineOne(job.lines.atStock or '차량에서 하차하고 재고를 올려 넣으세요!', true)
                    guideUpd('재고를 트렁크에 실으세요')
                end

            elseif job.stage == 'loading' then
                w = 0
                drawZone(job.stock)
                local dStock = #(pos - vec3(job.stock.x, job.stock.y, job.stock.z))
                local tp = trunkPos()
                local dTrunk = tp and #(pos - tp) or 999.0
                if not carrying then
                    if dStock < IR then
                        want = '[E] 재고 들기'
                        if IsControlJustPressed(0, 38) then startCarry() end
                    end
                else
                    if dTrunk < (IR + 1.2) then
                        want = '[E] 트렁크에 싣기'
                        if IsControlJustPressed(0, 38) then
                            stopCarry(); TriggerServerEvent('cookie_trucker:server:loadOne')
                        end
                    else
                        want = '트럭 뒤(트렁크)로 이동'
                    end
                end

            elseif job.stage == 'go_deliver' then
                w = 250
                if #(pos - vec3(job.dest.x, job.dest.y, job.dest.z)) < AR then
                    job.stage = 'unloading'; clearRoute()
                    cineOne(job.lines.atDest or '차량에서 하차하고 트렁크에 재고를 내리세요', true)
                    guideUpd('재고를 내리세요')
                end

            elseif job.stage == 'unloading' then
                w = 0
                drawZone(job.dest)
                local dDest = #(pos - vec3(job.dest.x, job.dest.y, job.dest.z))
                local tp = trunkPos()
                local dTrunk = tp and #(pos - tp) or 999.0
                if not carrying then
                    if dTrunk < (IR + 1.2) then
                        want = '[E] 트렁크에서 꺼내기'
                        if IsControlJustPressed(0, 38) then startCarry() end
                    end
                else
                    if dDest < IR then
                        want = '[E] 재고 내리기'
                        if IsControlJustPressed(0, 38) then
                            stopCarry(); TriggerServerEvent('cookie_trucker:server:unloadOne')
                        end
                    else
                        want = '하차 지점으로 이동'
                    end
                end

            elseif job.stage == 'return' then
                w = 0
                drawZone(job.ret)

                if IsPedInAnyVehicle(ped, false)
                   and #(pos - vec3(job.ret.x, job.ret.y, job.ret.z)) < (T.ReturnRadius or 6.0) then
                    job.stage = 'returning'
                    local v = GetVehiclePedIsIn(ped, false)
                    TaskLeaveVehicle(ped, v, 0)
                    CreateThread(function()

                        local until_ = GetGameTimer() + 6000
                        while IsPedInVehicle(PlayerPedId(), v, false) and GetGameTimer() < until_ do Wait(100) end
                        Wait(400)
                        TriggerServerEvent('cookie_trucker:server:finishJob')
                    end)
                end

            elseif job.stage == 'returning' then
                w = 250
            end
        end
        textUi(want)
        Wait(w)
    end
end)

RegisterNetEvent('cookie_trucker:client:jobStart', function(d)
    job = { stock = d.stock, dest = d.dest, ret = d.ret, cap = d.cap, loaded = 0,
            distKm = d.distKm, stage = 'board_wait', lines = d.lines or {} }
    firstLoadShown = false
    if jobBoarded then startGoStock() end
end)

RegisterNetEvent('cookie_trucker:client:cargo', function(d)
    if not job then return end
    job.loaded = d.loaded or job.loaded
    if d.dir == 'load' then
        guideUpd('재고를 트렁크에 실으세요')
        if not firstLoadShown then
            firstLoadShown = true
            cineOne(job.lines.loadingGo or '차량에 물건을 싣고 있습니다. 계속하세요', true)
        end
        if d.full then
            job.stage = 'go_deliver'
            cineOne(job.lines.loadDone or '모든 재고가 트렁크에 채워졌습니다.', true)
            CreateThread(function()
                Wait(2800)
                cineOne(job.lines.toDeliver or '재고 박스를 이제 배송합니다. 이동하세요', true)
                setRoute(job.dest); guideUpd('배송지로 이동하시오.')
            end)
        end
    else
        guideUpd('재고를 내리세요')
        if d.empty then
            job.stage = 'return'
            CreateThread(function()
                Wait(500)
                cineOne(job.lines.allUnload or '운송작업이 모두 완료되었습니다. 운송지역으로 복귀하세요!', true)
                setRoute(job.ret); guideUpd('운송지역으로 복귀하시오.')
            end)
        end
    end
end)

RegisterNetEvent('cookie_trucker:client:jobCancel', function() endJobLocal() end)

RegisterNetEvent('cookie_trucker:client:receipt', function(d)
    endJobLocal()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'receipt', pay = d.pay, from = d.from, to = d.to, date = d.date })
end)

RegisterNUICallback('receiptClose', function(_, cb)
    cb({ ok = true })
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'receiptClose' })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    RenderScriptCams(false, false, 0, true, true)
    if dlgCam then DestroyCam(dlgCam, true) end
    if jobBlip then RemoveBlip(jobBlip) end
    if boxObj and DoesEntityExist(boxObj) then DetachEntity(boxObj, true, true); DeleteEntity(boxObj) end
    SetNuiFocus(false, false)
    TriggerEvent('cookie_hud:client:hudVisible', true)
    TriggerEvent('cookie_chat:forceHide', false)
    DisplayRadar(true)
end)
