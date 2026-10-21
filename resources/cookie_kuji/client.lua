local function cookieUiFocus(on)
    local resourceName = GetCurrentResourceName()

    if on then
        if GetResourceState('cookie_core') == 'started' then
            local ok, owner, previousOwner = exports.cookie_core:Acquire(resourceName, false)
            if ok ~= true then return false, owner, previousOwner end
        end

        -- The resource that owns the NUI page must own the native NUI focus too.
        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
        return true, resourceName, nil
    end

    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    if GetResourceState('cookie_core') == 'started' then
        exports.cookie_core:Release(resourceName)
    end
    return true, nil, nil
end

local opened = false
local state = nil

local function closeUi()
    if not opened then return end
    opened = false
    cookieUiFocus(false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('cookie_kuji:client:bootstrap', function(data)
    state = data or state
end)

RegisterNetEvent('cookie_kuji:client:state', function(data)
    state = data or {}
    if not opened then
        local ok, owner = cookieUiFocus(true)
        if ok == false then
            TriggerEvent('cookie_admin:client:notify', ('다른 UI(%s)가 열려 있습니다. 먼저 닫아주세요.'):format(tostring(owner or 'unknown')), true)
            return
        end
        opened = true
    end
    SendNUIMessage({ action = 'open', data = state })
end)

RegisterNetEvent('cookie_kuji:client:result', function(data)
    if data and data.state then state = data.state end
    SendNUIMessage({ action = 'drawResult', data = data or {} })
end)

RegisterNetEvent('cookie_kuji:client:settingsChanged', function(data)
    state = data or state
    if opened then
        TriggerServerEvent('cookie_kuji:server:requestOpen')
    end
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('draw', function(data, cb)
    local count = tonumber(data and data.count) or 1
    if count ~= 1 and count ~= 5 and count ~= 10 then count = 1 end
    TriggerServerEvent('cookie_kuji:server:draw', count)
    cb('ok')
end)

-- 쿠지 비콘은 cookie_safezone의 F3 비콘 관리가 전담한다.
-- 여기서는 월드 마커를 직접 그리지 않는다.
CreateThread(function()
    Wait(1000)
    TriggerServerEvent('cookie_kuji:server:requestBootstrap')
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        cookieUiFocus(false)
    end
end)
