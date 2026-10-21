local function yn(v) return v and 'true' or 'false' end

local function status(label)
    local ped = PlayerPedId()
    local exists = ped ~= 0 and DoesEntityExist(ped)
    local pos = exists and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    local cam = -1
    if type(GetRenderingCam) == 'function' then
        local ok, current = pcall(GetRenderingCam)
        if ok then cam = current end
    end

    print('[cookie_screen_diag] '..tostring(label))
    print(('[cookie_screen_diag] fadedOut=%s fadedIn=%s fadingOut=%s fadingIn=%s'):format(
        yn(IsScreenFadedOut()), yn(IsScreenFadedIn()), yn(IsScreenFadingOut()), yn(IsScreenFadingIn())
    ))
    print(('[cookie_screen_diag] renderingCam=%s ped=%s exists=%s pos=%.2f %.2f %.2f'):format(
        tostring(cam), tostring(ped), yn(exists), pos.x, pos.y, pos.z
    ))
    print(('[cookie_screen_diag] sessionStarted=%s cookie_select=%s cookie_loading=%s loadscreen=%s'):format(
        yn(NetworkIsSessionStarted()), GetResourceState('cookie_select'),
        GetResourceState('cookie_loading'), GetResourceState('loadscreen')
    ))
end

RegisterCommand('cookie_screen_status', function()
    status('STATUS')
end, false)

RegisterCommand('cookie_screen_recover', function()
    status('BEFORE MANUAL RECOVERY')
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    DoScreenFadeIn(600)
    CreateThread(function()
        Wait(950)
        status('AFTER MANUAL RECOVERY')
    end)
end, false)

CreateThread(function()
    Wait(5000)
    print('[cookie_screen_diag] v1.0.1 ready: F8 cookie_screen_status / cookie_screen_recover')
end)
