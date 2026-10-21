local overheads = {}
local currentData = nil
local deathLatched = false

local function hexToRgb(hex)
    hex = tostring(hex or '#ffffff'):gsub('#', '')
    if #hex ~= 6 then return 255, 255, 255 end
    return tonumber(hex:sub(1,2), 16) or 255,
           tonumber(hex:sub(3,4), 16) or 255,
           tonumber(hex:sub(5,6), 16) or 255
end

local function drawTitle3D(coords, text, color)
    local cam = GetGameplayCamCoord()
    local dist = #(cam - coords)
    if dist <= 0.01 then dist = 0.01 end

    local scale = math.min(0.34, math.max(0.22, 0.42 / (dist * 0.08)))
    local r, g, b = hexToRgb(color)

    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.0, scale)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextColour(r, g, b, 235)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function weaponLabel(hash)
    if not hash or hash == 0 then return 'UNKNOWN' end
    local key = GetWeaponDisplayNameFromHash(hash)
    if key and key ~= 'NULL' then
        local label = GetLabelText(key)
        if label and label ~= 'NULL' then return label end
        return key
    end
    return tostring(hash)
end

local function openUi(mode)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        mode = mode or 'user',
        data = currentData
    })
end

RegisterNetEvent('cookie_identityfx:client:selfData', function(data)
    currentData = data
    if data and data.openMode then
        openUi(data.openMode)
    else
        SendNUIMessage({ action = 'selfData', data = data })
    end
end)

RegisterNetEvent('cookie_identityfx:client:adminData', function(data)
    SendNUIMessage({ action = 'adminData', data = data })
end)

RegisterNetEvent('cookie_identityfx:client:syncOverheads', function(data)
    overheads = data or {}
end)

-- COOKIE: Display the weapon-icon killfeed inside cookie_hud (under status panel).
-- Keep the original UI as a fallback when cookie_hud is stopped.
RegisterNetEvent('cookie_identityfx:client:killfeed', function(data)
    if GetResourceState('cookie_hud') == 'started' then
        TriggerEvent('cookie_hud:client:killfeed', data)
    else
        SendNUIMessage({ action = 'killfeed', data = data })
    end
end)

RegisterNetEvent('cookie_identityfx:client:openAdmin', function()
    TriggerServerEvent('cookie_identityfx:server:requestSync', 'admin')
    TriggerServerEvent('cookie_identityfx:server:requestAdminData')
end)

exports('OpenAdmin', function()
    TriggerServerEvent('cookie_identityfx:server:requestSync', 'admin')
    TriggerServerEvent('cookie_identityfx:server:requestAdminData')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('equip', function(data, cb)
    TriggerServerEvent('cookie_identityfx:server:setActive', data.type, data.code or '')
    cb({ ok = true })
end)

RegisterNUICallback('refreshAdmin', function(_, cb)
    TriggerServerEvent('cookie_identityfx:server:requestAdminData')
    cb({ ok = true })
end)

RegisterNUICallback('adminCreate', function(data, cb)
    TriggerServerEvent('cookie_identityfx:server:adminCreate', data)
    cb({ ok = true })
end)

RegisterNUICallback('adminGrant', function(data, cb)
    TriggerServerEvent('cookie_identityfx:server:adminGrant', data.target, data.code)
    cb({ ok = true })
end)

RegisterNUICallback('adminRevoke', function(data, cb)
    TriggerServerEvent('cookie_identityfx:server:adminRevoke', data.target, data.code)
    cb({ ok = true })
end)

CreateThread(function()
    Wait(2500)
    TriggerServerEvent('cookie_identityfx:server:requestSync')
end)

CreateThread(function()
    while true do
        local sleep = 750
        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)

        for _, player in ipairs(GetActivePlayers()) do
            if Config.ShowSelfOverhead or player ~= PlayerId() then
                local sid = GetPlayerServerId(player)
                local info = overheads[tostring(sid)]
                if info and info.label then
                    local ped = GetPlayerPed(player)
                    if DoesEntityExist(ped) then
                        local coords = GetEntityCoords(ped)
                        local dist = #(myCoords - coords)
                        if dist <= (Config.OverheadDistance or 35.0) then
                            sleep = 0
                            local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.30)
                            drawTitle3D(head, info.label, info.color)
                        end
                    end
                end
            end
        end

        Wait(sleep == 0 and (Config.OverheadRefreshMs or 250) or sleep)
    end
end)

CreateThread(function()
    while true do
        Wait(120)

        local ped = PlayerPedId()
        local dead = IsEntityDead(ped)

        if dead and not deathLatched then
            deathLatched = true

            local killerEntity = GetPedSourceOfDeath(ped)
            local cause = GetPedCauseOfDeath(ped)
            local killerSid = 0
            local distance = 0.0

            if killerEntity and killerEntity ~= 0 and DoesEntityExist(killerEntity) then
                if IsEntityAPed(killerEntity) and IsPedAPlayer(killerEntity) then
                    local killerPlayer = NetworkGetPlayerIndexFromPed(killerEntity)
                    if killerPlayer and killerPlayer ~= -1 then
                        killerSid = GetPlayerServerId(killerPlayer)
                        distance = #(GetEntityCoords(ped) - GetEntityCoords(killerEntity))
                    end
                end
            end

            local _, bone = GetPedLastDamageBone(ped)
            local headshot = tonumber(bone) == 31086

            TriggerServerEvent(
                'cookie_identityfx:server:death',
                killerSid,
                weaponLabel(cause),
                headshot,
                distance,
                cause  -- Raw weapon hash, for TURN-style weapon icons.
            )
        elseif not dead and deathLatched then
            deathLatched = false
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
