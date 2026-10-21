

local T = Config.Taxi
local open = false
local npcLabel = '택시 관리인'

local function cards()
    local list = {}
    for _, v in ipairs(T.Vehicles or {}) do
        list[#list + 1] = {
            key = v.key, label = v.label, level = v.level,
            model = v.model,
            repairFee = v.repairFee, lossFee = v.lossFee,
        }
    end
    return list
end

local function setWorldUi(show)
    TriggerEvent('cookie_hud:client:hudVisible', show)
    DisplayRadar(show)

    if not show then

        SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true)
    end
end

local dlgCam = nil

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

    npcLabel = (payload and payload.label) or '택시 관리인'

    setWorldUi(false)
    startCam(payload and payload.npcId)
    TriggerEvent('cookie_taxi:client:dialogState', true)

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        npc = npcLabel,
        lines = T.Lines,
        vehicles = cards(),
    })

    TriggerServerEvent('cookie_taxi:server:requestState')
end

local function closeDialog()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopCam()
    setWorldUi(true)
    TriggerEvent('cookie_taxi:client:dialogState', false)
end

CreateThread(function()
    while true do
        if open then
            DisableAllControlActions(0)
            EnableControlAction(0, 200, true)
            Wait(0)
        else
            Wait(300)
        end
    end
end)

RegisterNetEvent('cookie_taxi:client:openDialog', function(p)
    openDialog(p)
end)

-- cookie_admin에서 직접 호출할 수 있는 안전한 클라이언트 export.
exports('OpenNpcDialog', function(payload)
    openDialog(payload)
end)

RegisterNetEvent('cookie_taxi:client:state', function(s)
    if type(s) ~= 'table' then return end
    SendNUIMessage({ action = 'state', state = s })
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeDialog()
end)

RegisterNUICallback('hire', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:hire')
end)

RegisterNUICallback('quit', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:quit')
end)

RegisterNUICallback('duty', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:duty', (data and data.on) == true)
end)

RegisterNUICallback('assign', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:assign', data and data.key)
    closeDialog()
end)

RegisterNUICallback('returnVeh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:returnVeh')
end)

RegisterNUICallback('payDebt', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:payDebt')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    RenderScriptCams(false, false, 0, true, true)
    if dlgCam then DestroyCam(dlgCam, true) end

    SetNuiFocus(false, false)
    TriggerEvent('cookie_hud:client:hudVisible', true)
    DisplayRadar(true)
end)