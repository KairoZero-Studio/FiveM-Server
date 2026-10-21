local locations = {}
local crafting = false
local currentOpen = nil
local textVisible = false

local function notify(msg, kind)
    lib.notify({
        title = '조직 제조',
        description = tostring(msg or ''),
        type = kind or 'inform'
    })
end

local function setFocus(on)
    SetNuiFocus(on == true, on == true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    if on and SetCursorLocation then SetCursorLocation(0.5, 0.5) end
end

local function hideText()
    if textVisible then
        lib.hideTextUI()
        textVisible = false
    end
end

RegisterNetEvent('cookie_drugcraft:client:locations', function(rows)
    locations = rows or {}
end)

RegisterNetEvent('cookie_drugcraft:client:open', function(payload)
    currentOpen = payload
    setFocus(true)
    SendNUIMessage({ action = 'openCraft', payload = payload })
end)

RegisterNetEvent('cookie_drugcraft:client:denied', function(message)
    notify(message or '이용할 수 없습니다.', 'error')
end)

RegisterNetEvent('cookie_drugcraft:client:started', function(payload)
    crafting = true
    currentOpen = nil
    setFocus(false)
    SendNUIMessage({ action = 'craftStarted', payload = payload })
    notify(payload.boosted and '미니게임 성공 · 빠른 제조를 시작합니다.' or '자동 제조를 시작합니다.', 'success')
end)

RegisterNetEvent('cookie_drugcraft:client:cycle', function(payload)
    SendNUIMessage({ action = 'craftCycle', payload = payload })
end)

RegisterNetEvent('cookie_drugcraft:client:finished', function(payload)
    crafting = false
    SendNUIMessage({ action = 'craftFinished', payload = payload })
    notify(('제조 완료 · %s %s개'):format(payload.label or '완제품', payload.produced or 0), 'success')
end)

RegisterNetEvent('cookie_drugcraft:client:canceled', function(payload)
    crafting = false
    SendNUIMessage({ action = 'craftCanceled', payload = payload })
    notify(('제조 취소 · 남은 원재료 %s개 반환'):format(payload.refunded or 0), 'warning')
end)

RegisterNetEvent('cookie_drugcraft:client:refundClaimed', function(amount)
    amount = tonumber(amount) or 0
    if amount > 0 then
        notify(('이전 제조 예약에서 남은 원재료 %d개를 돌려받았습니다.'):format(amount), 'success')
    end
end)

RegisterNetEvent('cookie_drugcraft:client:adminOpen', function(payload)
    setFocus(true)
    SendNUIMessage({ action = 'openAdmin', payload = payload })
end)

RegisterNetEvent('cookie_drugcraft:client:adminRefresh', function(payload)
    SendNUIMessage({ action = 'adminRefresh', payload = payload })
end)

RegisterNUICallback('close', function(_, cb)
    setFocus(false)
    currentOpen = nil
    cb({ ok = true })
end)

RegisterNUICallback('startAuto', function(data, cb)
    if not currentOpen then cb({ ok = false }) return end
    TriggerServerEvent('cookie_drugcraft:server:start', {
        token = currentOpen.token,
        locationId = currentOpen.locationId,
        recipe = data and data.recipe,
        rawAmount = data and data.rawAmount,
        boosted = false
    })
    cb({ ok = true })
end)

RegisterNUICallback('minigameResult', function(data, cb)
    if not currentOpen then cb({ ok = false }) return end
    TriggerServerEvent('cookie_drugcraft:server:start', {
        token = currentOpen.token,
        locationId = currentOpen.locationId,
        recipe = data and data.recipe,
        rawAmount = data and data.rawAmount,
        boosted = data and data.success == true
    })
    cb({ ok = true })
end)

RegisterNUICallback('adminAddLocation', function(data, cb)
    TriggerServerEvent('cookie_drugcraft:server:adminAddLocation', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminUpdateLocation', function(data, cb)
    TriggerServerEvent('cookie_drugcraft:server:adminUpdateLocation', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminDeleteLocation', function(data, cb)
    TriggerServerEvent('cookie_drugcraft:server:adminDeleteLocation', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('adminUpdateRecipe', function(data, cb)
    TriggerServerEvent('cookie_drugcraft:server:adminUpdateRecipe', data or {})
    cb({ ok = true })
end)

RegisterCommand('drugcraftadmin', function()
    TriggerServerEvent('cookie_drugcraft:server:adminRequest')
end, false)

CreateThread(function()
    Wait(2500)
    TriggerServerEvent('cookie_drugcraft:server:requestLocations')
    TriggerServerEvent('cookie_drugcraft:server:claimRefund')
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        if ped ~= 0 and not IsEntityDead(ped) and not crafting then
            local pos = GetEntityCoords(ped)
            local nearest, nearestDist = nil, 99999.0
            for _, loc in ipairs(locations) do
                if loc.enabled == 1 or loc.enabled == true then
                    local dist = #(pos - vector3(loc.x + 0.0, loc.y + 0.0, loc.z + 0.0))
                    if dist < nearestDist then nearest, nearestDist = loc, dist end
                    if dist <= (Config.MarkerDistance or 30.0) then
                        sleep = 0
                        local m = Config.Marker
                        DrawMarker(m.type or 1, loc.x + 0.0, loc.y + 0.0, loc.z - 0.92,
                            0.0,0.0,0.0,0.0,0.0,0.0,
                            m.scale.x,m.scale.y,m.scale.z,
                            m.color.r,m.color.g,m.color.b,m.color.a,
                            false,false,2,false,nil,nil,false)
                    end
                end
            end
            if nearest and nearestDist <= (Config.InteractDistance or 2.2) then
                sleep = 0
                if not textVisible then
                    lib.showTextUI(('[E] %s'):format(nearest.label or '조직 제조'))
                    textVisible = true
                end
                if IsControlJustPressed(0, 38) then
                    hideText()
                    TriggerServerEvent('cookie_drugcraft:server:open', nearest.id)
                    Wait(500)
                end
            else
                hideText()
            end
        else
            hideText()
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    local debounce = false
    while true do
        if crafting then
            Wait(0)
            if not debounce and IsControlJustPressed(0, 177) then
                debounce = true
                TriggerServerEvent('cookie_drugcraft:server:cancel')
                SetTimeout(800, function() debounce = false end)
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    hideText()
    setFocus(false)
end)
