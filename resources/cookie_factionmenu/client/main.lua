local menuOpen = false
local lastProfile = nil

local function notify(message, isError)
    if lib and lib.notify then
        lib.notify({
            title = 'COOKIE 업무 단말기',
            description = tostring(message or ''),
            type = isError and 'error' or 'inform'
        })
        return
    end
    TriggerEvent('chat:addMessage', { args = { 'COOKIE', tostring(message or '') } })
end

local function closeScullyMenu()
    if GetResourceState('scully_emotemenu') ~= 'started' then return end
    pcall(function() exports.scully_emotemenu:closeMenu() end)
    TriggerEvent('scully_emotemenu:closeMenu')
end

local function categoriesFor(profile)
    local faction = profile and profile.faction or nil
    local t = faction and tostring(faction.type or '') or ''
    if t == 'police' or t == 'security' then
        return Config.PoliceCategories or {}
    end
    if t == 'tow' then
        return Config.TowCategories or {}
    end
    if t == 'crime' then
        return Config.CrimeCategories or Config.GenericIntranetCategories or {}
    end
    if Config.IsDaisoFaction and Config.IsDaisoFaction(faction) then
        return Config.DaisoCategories or {}
    end
    if Config.IsPharmacyFaction and Config.IsPharmacyFaction(faction) then
        return Config.PharmacyCategories or {}
    end
    local generic = Config.GenericIntranetCategories or {}
    -- The same F5 interface is reused, only categories and headings change.
    return generic
end

local function setMenu(open)
    menuOpen = open == true
    SetNuiFocus(menuOpen, menuOpen)
    SetNuiFocusKeepInput(false)

    if not menuOpen then
        SendNUIMessage({ action = 'close' })
        return
    end

    closeScullyMenu()
    SendNUIMessage({
        action = 'open',
        profile = lastProfile,
        categories = categoriesFor(lastProfile),
    })

    CreateThread(function()
        for _, delay in ipairs({ 50, 150, 300 }) do
            Wait(delay)
            if menuOpen then closeScullyMenu() end
        end
    end)
end

local function toggleMenu()
    if menuOpen then
        setMenu(false)
        return
    end

    if IsPauseMenuActive() then return end
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.cookieCameraMode == true then
        return notify('카메라 사용 중에는 업무 단말기를 열 수 없습니다.', true)
    end

    local profile = lib.callback.await('cookie_factionmenu:getProfile', false)
    if not profile or not profile.allowed then
        return notify((profile and profile.reason) or '업무 단말기를 사용할 수 없습니다.', true)
    end

    lastProfile = profile
    setMenu(true)
end

RegisterCommand('cookie_factionmenu', toggleMenu, false)
RegisterKeyMapping('cookie_factionmenu', 'COOKIE 팩션 업무 단말기', 'keyboard', 'F5')

local function openAction(actionId)
    if IsPauseMenuActive() then return false end
    local p = lib.callback.await('cookie_factionmenu:getProfile', false)
    if not p or not p.allowed then
        notify((p and p.reason) or '업무 단말기를 사용할 수 없습니다.', true)
        return false
    end
    lastProfile = p
    setMenu(true)
    if actionId and tostring(actionId) ~= '' then
        CreateThread(function()
            Wait(90)
            if menuOpen then SendNUIMessage({action='focusAction', id=tostring(actionId)}) end
        end)
    end
    return true
end

exports('openAction', openAction)
exports('open', function() return openAction(nil) end)
exports('close', function() if menuOpen then setMenu(false) end end)

RegisterNUICallback('close', function(_, cb)
    setMenu(false)
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    local profile = lib.callback.await('cookie_factionmenu:getProfile', false)
    if profile and profile.allowed then
        lastProfile = profile
        SendNUIMessage({ action = 'profile', profile = profile })
    end
    cb({ ok = true })
end)


local F5_SAFE_ACTIONS = {
    -- 수배/도주/출석요구는 cookie_police:mdtAction 단일 라우터만 사용한다.
    -- SAFE 라우터와 MDT 라우터가 섞여 응답이 비는 문제를 방지한다.
    roster=true,
    warrant_targets=true,
    warrant_board=true,
    warrant_add=true,
    penalty_calculator=true,
    dispatch=true,
    cases=true,
    audit=true,
    intranet_home=true,
    intranet_ledger=true,
    intranet_performance=true,
    intranet_leave_board=true,
    intranet_settlement_board=true,
    budget_lookup=true,
}

local F5_SAFE_RESULT_ACTIONS = {
    -- 수배/도주 참여·종료 역시 cookie_police:mdtResultAction 단일 라우터 사용.
    warrant_close=true,
    dispatch_join=true,
    dispatch_close=true,
    case_close=true,
    leave_approve=true,
    leave_reject=true,
    penalty_apply=true,
}

local function awaitF5Callback(name,...)
    local args={...}
    local ok,result=pcall(function()
        return lib.callback.await(name,false,table.unpack(args))
    end)
    if not ok then
        local err=tostring(result)
        print(('[cookie_factionmenu] callback error %s: %s'):format(tostring(name),err))
        return nil,err
    end
    return result,nil
end

RegisterNUICallback('runAction', function(data, cb)
    local id = type(data) == 'table' and tostring(data.id or '') or ''
    local payload = type(data) == 'table' and (data.payload or {}) or {}
    if id == '' then return cb({ ok = false, message = '잘못된 기능입니다.' }) end

    local callbackName = id:sub(1,3) == 'ci_' and 'cookie_factionmenu:intranetAction' or (F5_SAFE_ACTIONS[id]
        and 'cookie_police:f5SafeAction'
        or 'cookie_police:mdtAction')

    local result,callbackErr = awaitF5Callback(callbackName, id, payload)

    -- SAFE 라우터가 준비되지 않은 짧은 시작 구간에는 기존 MDT 콜백으로 1회 재시도.
    if not result and callbackName == 'cookie_police:f5SafeAction' then
        result,callbackErr = awaitF5Callback('cookie_police:mdtAction', id, payload)
    end

    cb(result or {
        ok = false,
        message = callbackErr and ('업무 처리 오류: '..callbackErr) or '업무 서버 응답이 없습니다. cookie_police 상태를 확인해주세요.'
    })
end)

RegisterNUICallback('resultAction', function(data, cb)
    local action = type(data) == 'table' and tostring(data.action or '') or ''
    local payload = type(data) == 'table' and (data.payload or {}) or {}
    if action == '' then return cb({ ok = false, message = '잘못된 요청입니다.' }) end

    local callbackName = action:sub(1,3) == 'ci_' and 'cookie_factionmenu:intranetResult' or (F5_SAFE_RESULT_ACTIONS[action]
        and 'cookie_police:f5SafeResultAction'
        or 'cookie_police:mdtResultAction')

    local result,callbackErr = awaitF5Callback(callbackName, action, payload)

    if not result and callbackName == 'cookie_police:f5SafeResultAction' then
        result,callbackErr = awaitF5Callback('cookie_police:mdtResultAction', action, payload)
    end

    cb(result or {
        ok = false,
        message = callbackErr and ('업무 처리 오류: '..callbackErr) or '업무 결과 서버 응답이 없습니다. cookie_police 상태를 확인해주세요.'
    })
end)

RegisterNetEvent('cookie_factionmenu:client:notify', function(message, isError)
    notify(message, isError)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if menuOpen then SetNuiFocus(false, false) end
end)
