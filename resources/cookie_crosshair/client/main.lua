

local UNARMED = joaat('WEAPON_UNARMED')
local cfg = nil
local shown = false
local editorOpen = false

RegisterNetEvent('cookie_crosshair:client:apply', function(c)
    if type(c) ~= 'table' then return end
    cfg = c
    SendNUIMessage({ action = 'apply', cfg = c })
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('cookie_crosshair:server:request')
end)
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('cookie_crosshair:server:request')
end)

local function isArmed()
    local w = GetSelectedPedWeapon(PlayerPedId())
    return w ~= UNARMED and w ~= 0 and w ~= `WEAPON_UNARMED`
end

local function isFirstPerson()
    local ped = PlayerPedId()

    -- GTA/FiveM 카메라 모드 4 = 1인칭.
    -- 차량 안에서도 1인칭이면 같은 방식으로 처리합니다.
    if IsPedInAnyVehicle(ped, false) then
        return GetFollowVehicleCamViewMode() == 4
    end

    return GetFollowPedCamViewMode() == 4
end

CreateThread(function()
    while true do
        local wait = 350
        if not editorOpen and cfg ~= nil then
            local armed = isArmed()
            local firstPerson = isFirstPerson()

            local want
            if cfg.adsOnly == false then
                want = true
            else
                -- V13.9.7:
                -- 3인칭은 기존처럼 조준할 때만 표시.
                -- 1인칭은 무기를 들고 있으면 조준하지 않아도 상시 표시.
                want = armed and (firstPerson or IsPlayerFreeAiming(PlayerId()))
            end

            if armed or cfg.adsOnly == false then wait = 0 end

            if cfg.base == false and armed then
                HideHudComponentThisFrame(14)
            end

            if want ~= shown then
                shown = want
                SendNUIMessage({ action = 'overlay', show = want })
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('cookie_crosshair:client:openEditor', function()
    if editorOpen then return end
    editorOpen = true

    if shown then shown = false; SendNUIMessage({ action = 'overlay', show = false }) end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action  = 'openEditor',
        cfg     = cfg or Config.Crosshair.Default,
        presets = Config.Crosshair.Presets,
    })
end)

RegisterNUICallback('save', function(data, cb)
    cb({ ok = true })

    editorOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeEditor' })
    TriggerServerEvent('cookie_crosshair:server:save', data)
end)

RegisterNUICallback('closeEditor', function(_, cb)
    cb({ ok = true })
    editorOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeEditor' })

    if cfg then SendNUIMessage({ action = 'apply', cfg = cfg }) end
end)

RegisterCommand('크로스헤어', function()
    TriggerEvent('cookie_crosshair:client:openEditor')
end, false)

RegisterCommand('조준점', function()
    TriggerEvent('cookie_crosshair:client:openEditor')
end, false)
RegisterCommand('crosshair', function()
    TriggerEvent('cookie_crosshair:client:openEditor')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)

print('^2[cookie_crosshair]^7 FIRST PERSON ALWAYS V13.9.7 ready')
