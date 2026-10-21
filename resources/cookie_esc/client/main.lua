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



local isOpen = false
local previewCam = nil

local stagePed = nil
local stageActive = false

local function destroyStage()
    stageActive = false

    if previewCam then
        RenderScriptCams(false, false, 0, true, true)
        SetCamActive(previewCam, false)
        DestroyCam(previewCam, true)
        previewCam = nil
    end

    if stagePed and DoesEntityExist(stagePed) then
        DeleteEntity(stagePed)
    end
    stagePed = nil

    SetArtificialLightsState(false)

    local t = GlobalState.currentTime
    if t and t.hour then
        NetworkOverrideClockTime(math.floor(t.hour), math.floor(t.minute or 0), 0)
    else
        NetworkClearClockTimeOverride()
    end

    NetworkOverrideClockMillisecondsPerGameMinute(
        GlobalState.freezeTime and 99999999 or (GlobalState.timeScale or 2000))
end

local function setupCam()
    if not Config.PreviewCam then return end

    local ped = PlayerPedId()
    local s = Config.StagePed

    stagePed = ClonePed(ped, false, false, true)
    if not stagePed or stagePed == 0 then

        return
    end

    SetEntityCoords(stagePed, s.x, s.y, s.z, false, false, false, false)
    SetEntityHeading(stagePed, s.w)
    SetEntityInvincible(stagePed, true)
    SetBlockingOfNonTemporaryEvents(stagePed, true)
    SetEntityCollision(stagePed, false, false)

    local posed = false
    for i = 1, #(Config.StagePoses or {}) do
        local p = Config.StagePoses[i]
        RequestAnimDict(p.dict)

        local waited = 0
        while not HasAnimDictLoaded(p.dict) and waited < 1500 do
            Wait(20)
            waited = waited + 20
        end

        if HasAnimDictLoaded(p.dict) then

            TaskPlayAnim(stagePed, p.dict, p.clip, 8.0, 8.0, -1, 1, 0.0, false, false, false)
            posed = true

            break
        else

        end
    end

    if not posed and Config.StageScenario then
        TaskStartScenarioInPlace(stagePed, Config.StageScenario, 0, true)

    elseif not posed then

        ClearPedTasksImmediately(stagePed)

    end
    Wait(80)

    SetEntityCoords(stagePed, s.x, s.y, s.z, false, false, false, false)
    SetEntityHeading(stagePed, s.w)
    FreezeEntityPosition(stagePed, true)

    local h = math.rad(s.w)
    local fx, fy = -math.sin(h), math.cos(h)

    local camX = s.x + fx * Config.Cam.forward
    local camY = s.y + fy * Config.Cam.forward
    local camZ = s.z + Config.Cam.up

    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camX, camY, camZ, 0.0, 0.0, 0.0, Config.Cam.fov, false, 0)
    PointCamAtCoord(previewCam, s.x, s.y, s.z + Config.Cam.aim)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, false, 0, true, true)

    stageActive = true
    NetworkOverrideClockTime(0, 0, 0)
    SetArtificialLightsState(true)

    CreateThread(function()
        local L = Config.StageLight
        local lz = s.z + L.up
        while stageActive do
            NetworkOverrideClockTime(0, 0, 0)
            SetUseHiDof()
            DrawLightWithRange(s.x + fx * L.forward, s.y + fy * L.forward, lz,
                255, 244, 214, L.range, L.front)
            DrawLightWithRange(s.x - fx * L.forward, s.y - fy * L.forward, lz,
                255, 244, 214, L.range, L.back)
            Wait(0)
        end
    end)
end

local function destroyCam()
    destroyStage()
end

local function openPanel()
    if isOpen then return end
    local ok, owner = cookieUiFocus(true)
    if ok == false then
        TriggerEvent('cookie_admin:client:notify', ('다른 UI(%s)가 열려 있습니다. 먼저 닫아주세요.'):format(tostring(owner or 'unknown')), true)
        return
    end
    isOpen = true

    SendNUIMessage({
        action = 'open',
        config = {
            brand      = Config.Brand,
            brandEn    = Config.BrandEn,
            tabs       = Config.Tabs,
            shortcuts  = Config.Shortcuts,
            suggest    = Config.Suggest,
            notice     = Config.Notice,
            news       = Config.News,
            discord    = Config.DiscordInvite,
            discordUrl = Config.DiscordUrl,
            homepage   = Config.Homepage,
            statusMax  = Config.StatusMax,
            statusOn   = Config.StatusEnabled,
        },
    })

    setupCam()

    TriggerEvent('cookie_chat:escMode', true)

    TriggerEvent('cookie_hud:client:hudVisible', false)

    CreateThread(function()
        while isOpen do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            EnableControlAction(0, 1, true)
            EnableControlAction(0, 2, true)
            Wait(0)
        end
    end)

    CreateThread(function()
        local p = lib.callback.await('cookie_esc:payload', false)
        if not isOpen then return end
        if p and p.ok then
            SendNUIMessage({ action = 'fill', data = p })
        else
            SendNUIMessage({ action = 'fillFail' })

        end
    end)

end

local function closePanel()
    if not isOpen then return end
    isOpen = false

    cookieUiFocus(false)
    SendNUIMessage({ action = 'close' })
    destroyCam()
    TriggerEvent('cookie_chat:escMode', false)
    TriggerEvent('cookie_hud:client:hudVisible', true)

end

exports('isOpen', function() return isOpen end)

AddEventHandler('cookie_esc:client:open', function()
    if LocalPlayer.state.cookiePhoneOpen then return end
    if isOpen then return end
    openPanel()
end)

CreateThread(function()
    while true do
        -- COOKIE phone is open: do not let ESC menu overlap the phone.
        if LocalPlayer.state.cookiePhoneOpen then
            Wait(0)
        elseif IsPauseMenuActive() then
            Wait(100)
        elseif LocalPlayer.state.isLoggedIn then
            -- COOKIE ESC is now ESC-only.
            DisableControlAction(0, 200, true)

            if IsDisabledControlJustPressed(0, 200) then
                if isOpen then
                    closePanel()
                elseif not (Config.BlockWhenDead and IsEntityDead(PlayerPedId())) then
                    openPanel()
                end
            end
            Wait(0)
        else
            Wait(300)
        end
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closePanel()
end)

RegisterNUICallback('news', function(_, cb)
    local r = lib.callback.await('cookie_esc:news', false)
    cb(r or { updates = {}, banners = {} })
end)

RegisterNUICallback('notices', function(_, cb)
    local rows = lib.callback.await('cookie_esc:notices', false)
    cb({ ok = rows ~= nil, list = rows or {} })
end)

RegisterNUICallback('userlist', function(_, cb)
    local data = lib.callback.await('cookie_esc:userlist', false)
    if data then
        cb({ ok = true, list = data.list or {}, summary = data.summary or {} })
    else
        cb({ ok = false, list = {}, summary = {} })
    end
end)

RegisterNUICallback('events', function(_, cb)
    local data = lib.callback.await('cookie_esc:events', false)
    cb(data or { ok = false, events = {} })
end)

-- COOKIE STORE: close ESC before transferring focus to the existing shop HUD
RegisterNUICallback('openCookieStore', function(_, cb)
    cb({ok=true})
    closePanel()
    CreateThread(function()
        Wait(180)
        if GetResourceState('cookie_store') == 'started' then
            TriggerServerEvent('cookie_store:server:open', false)
        else
            lib.notify({title='COOKIE STORE', description='cookie_store 리소스가 시작되지 않았습니다.', type='error'})
        end
    end)
end)

RegisterNUICallback('openEventHub', function(_, cb)
    cb({ ok = true })
    closePanel()
    CreateThread(function()
        Wait(120)
        TriggerEvent('cookie_admin:client:openEventHub', 'event', 'esc')
    end)
end)

RegisterNUICallback('rankings', function(_, cb)
    local data = lib.callback.await('cookie_esc:rankings', false)
    cb(data or { ok = false, categories = {} })
end)

RegisterNUICallback('submitSuggestion', function(data, cb)
    local r = lib.callback.await('cookie_esc:submitSuggestion', false, data or {})
    cb(r or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('setStatus', function(data, cb)
    local r = lib.callback.await('cookie_esc:setStatus', false, (data and data.text) or '')
    cb(r or { ok = false, reason = '서버 응답 없음' })
end)

RegisterNUICallback('openMap', function(_, cb)
    cb({ ok = true })
    closePanel()
    Wait(120)

    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_SP_PAUSE'), false, Config.MapComponent or 44)

end)

RegisterNUICallback('openGtaSettings', function(_, cb)
    cb({ ok = true })
    closePanel()
    Wait(120)
    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_SP_PAUSE'), false, Config.SettingsComponent or 5)

end)

local function leaveServer()
    closePanel()

    TriggerServerEvent('cookie_esc:server:leave')
end

RegisterNUICallback('quitGame', function(_, cb)
    cb({ ok = true })
    leaveServer()
end)

RegisterNUICallback('disconnect', function(_, cb)
    cb({ ok = true })
    leaveServer()
end)

-- COOKIE SAFE CLEANUP:
-- cookie_esc used to move COOKIE chat into ESC layout while the panel is open.
-- If this resource is restarted while the panel is open, the old code could
-- stop before sending escMode=false and leave chat stuck in the middle.
local function restoreCookieUiAfterEsc()
    TriggerEvent('cookie_chat:escMode', false)
    TriggerEvent('cookie_hud:client:hudVisible', true)
    cookieUiFocus(false)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    isOpen = false
    Wait(0)
    restoreCookieUiAfterEsc()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    restoreCookieUiAfterEsc()
end)

RegisterNetEvent('cookie_esc:client:forceRestoreUi', function()
    isOpen = false
    SendNUIMessage({ action = 'close' })
    restoreCookieUiAfterEsc()
end)

RegisterCommand('cookie_ui_reset', function()
    TriggerEvent('cookie_esc:client:forceRestoreUi')
end, false)

print('^2[COOKIE ESC]^7 EVENT+ATTENDANCE HUD NO QUEST V14.1.0 ready')
