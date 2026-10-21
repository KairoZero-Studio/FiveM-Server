local function panelOpen()
    return type(CookieAdminPanelIsOpen) == 'function' and CookieAdminPanelIsOpen()
end

local function sendToast(message, isWarn)
    SendNUIMessage({ action = 'toast', message = message, isWarn = isWarn == true })
end

local function sendDoorList()
    if GetResourceState('cookie_doorlock') ~= 'started' then
        SendNUIMessage({ action = 'doorAdminData', rows = {}, unavailable = true })
        return
    end

    local data = lib.callback.await('cookie_doorlock:server:getAdminDoors', false)
    if data == nil then
        SendNUIMessage({ action = 'doorAdminData', rows = {}, permissions = {}, denied = true })
        return
    end
    -- 구버전 doorlock 응답(배열)도 호환합니다.
    if data.rows ~= nil then
        SendNUIMessage({ action = 'doorAdminData', rows = data.rows or {}, permissions = data.permissions or {} })
    else
        SendNUIMessage({ action = 'doorAdminData', rows = data or {}, permissions = {} })
    end
end

RegisterNUICallback('doorAdminRequest', function(_, cb)
    cb({ ok = true })
    CreateThread(sendDoorList)
end)

RegisterNUICallback('doorAdminCapture', function(data, cb)
    local mode = data and data.mode == 'double' and 'double' or 'single'
    if GetResourceState('cookie_doorlock') ~= 'started' then
        cb({ ok = false, error = 'resource' })
        return sendToast('cookie_doorlock 리소스가 실행 중이 아닙니다.', true)
    end

    local allowed = lib.callback.await('cookie_doorlock:server:isAdmin', false)
    if not allowed then
        cb({ ok = false, error = 'permission' })
        return sendToast('문 관리 권한이 없습니다. 관리자 근무 상태를 확인해주세요.', true)
    end

    cb({ ok = true })
    CreateThread(function()
        SendNUIMessage({ action = 'doorCaptureFocus', active = true })
        CookieAdminSetNuiFocus(false, false)
        Wait(150)

        local ok, leaves = pcall(function()
            return exports.cookie_doorlock:CaptureLeaves(mode)
        end)

        if panelOpen() then
            CookieAdminSetNuiFocus(true, false)
            SendNUIMessage({ action = 'doorCaptureFocus', active = false })

            if ok and type(leaves) == 'table' and #leaves > 0 then
                SendNUIMessage({ action = 'doorCaptureResult', mode = mode, leaves = leaves })
            elseif not ok then
                sendToast('문 선택 기능을 실행하지 못했습니다.', true)
            else
                sendToast('문 등록을 취소했습니다.', false)
            end
        end
    end)
end)


RegisterNUICallback('doorAdminMergeCapture', function(_, cb)
    if GetResourceState('cookie_doorlock') ~= 'started' then
        cb({ ok = false, error = 'resource' })
        return sendToast('cookie_doorlock 리소스가 실행 중이 아닙니다.', true)
    end

    local allowed = lib.callback.await('cookie_doorlock:server:isAdmin', false)
    if not allowed then
        cb({ ok = false, error = 'permission' })
        return sendToast('문 관리 권한이 없습니다. 관리자 근무 상태를 확인해주세요.', true)
    end

    cb({ ok = true })
    CreateThread(function()
        SendNUIMessage({ action = 'doorCaptureFocus', active = true })
        CookieAdminSetNuiFocus(false, false)
        Wait(150)

        local ok, leaves = pcall(function()
            return exports.cookie_doorlock:CaptureLeaves('double')
        end)

        if panelOpen() then
            CookieAdminSetNuiFocus(true, false)
            SendNUIMessage({ action = 'doorCaptureFocus', active = false })
        end

        if ok and type(leaves) == 'table' and #leaves == 2 then
            TriggerServerEvent('cookie_doorlock:server:adminMergeByLeaves', leaves)
        elseif not ok then
            sendToast('양문 묶기 선택 기능을 실행하지 못했습니다.', true)
        else
            sendToast('양문 묶기를 취소했습니다.', false)
        end
    end)
end)

RegisterNUICallback('doorAdminCreate', function(data, cb)
    cb({ ok = true })
    if GetResourceState('cookie_doorlock') ~= 'started' then
        return sendToast('cookie_doorlock 리소스가 실행 중이 아닙니다.', true)
    end
    TriggerServerEvent('cookie_doorlock:server:adminCreate', data or {})
end)

RegisterNUICallback('doorAdminUpdate', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or not tonumber(data.id) then return end
    TriggerServerEvent('cookie_doorlock:server:adminUpdate', tonumber(data.id), data)
end)

RegisterNUICallback('doorAdminSetState', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or not tonumber(data.id) then return end
    TriggerServerEvent('cookie_doorlock:server:adminSetState', tonumber(data.id), data.locked == true)
end)

RegisterNUICallback('doorAdminDelete', function(data, cb)
    cb({ ok = true })
    if type(data) ~= 'table' or not tonumber(data.id) then return end
    TriggerServerEvent('cookie_doorlock:server:adminDelete', tonumber(data.id))
end)

RegisterNetEvent('cookie_doorlock:client:adminRefresh', function()
    if not panelOpen() then return end
    CreateThread(function()
        Wait(100)
        sendDoorList()
    end)
end)
