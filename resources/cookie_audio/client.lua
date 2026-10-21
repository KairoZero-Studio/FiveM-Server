local blocking = true

local function applyFlags()
    if Config.DisableGameMusic then
        pcall(function() SetAudioFlag('DisableFlightMusic', true) end)
        pcall(function() SetAudioFlag('WantedMusicDisabled', true) end)
        pcall(function() SetAudioFlag('AllowRadioDuringSwitch', false) end)
        pcall(function() SetFrontendRadioActive(false) end)
    end

    if Config.DisableVehicleRadio then
        pcall(function() SetUserRadioControlEnabled(false) end)
        pcall(function() SetMobileRadioEnabledDuringGameplay(false) end)
        pcall(function() SetFrontendRadioActive(false) end)
        pcall(function() SetRadioToStationName('OFF') end)
    end

    for _, emitter in ipairs(Config.StaticEmitters or {}) do
        pcall(function() SetStaticEmitterEnabled(emitter, false) end)
    end

    for _, zone in ipairs(Config.AmbientZones or {}) do
        pcall(function()
            SetAmbientZoneStatePersistent(zone, false, true)
        end)
    end
end

local function disableVehicleRadio()
    if not Config.DisableVehicleRadio then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh and veh ~= 0 then
        pcall(function() SetVehRadioStation(veh, 'OFF') end)
        pcall(function() SetVehicleRadioEnabled(veh, false) end)
    end
end

local function enforce()
    if not blocking then return end

    applyFlags()
    disableVehicleRadio()

    if Config.StopAudioScenes then
        pcall(function() StopAudioScenes() end)
    end
end

CreateThread(function()
    Wait(1000)
    enforce()

    while true do
        if blocking then
            enforce()
        end
        Wait(Config.RefreshInterval or 1500)
    end
end)

CreateThread(function()
    while true do
        if blocking and Config.DisableVehicleRadio then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh and veh ~= 0 then
                pcall(function() SetVehRadioStation(veh, 'OFF') end)
                pcall(function() SetVehicleRadioEnabled(veh, false) end)

                DisableControlAction(0, 81, true)
                DisableControlAction(0, 82, true)
                DisableControlAction(0, 83, true)
                DisableControlAction(0, 84, true)
                DisableControlAction(0, 85, true)

                Wait(0)
            else
                Wait(300)
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    enforce()
    print('^2[cookie_audio] ambient music / map music / vehicle radio disabled.^7')
end)

RegisterCommand('cookieaudioon', function()
    blocking = true
    enforce()
    print('^2[cookie_audio] blocking ON^7')
end, false)

RegisterCommand('cookieaudiooff', function()
    blocking = false
    pcall(function() SetUserRadioControlEnabled(true) end)
    pcall(function() SetMobileRadioEnabledDuringGameplay(true) end)
    pcall(function() SetAudioFlag('DisableFlightMusic', false) end)
    pcall(function() SetAudioFlag('WantedMusicDisabled', false) end)
    print('^3[cookie_audio] blocking OFF^7')
end, false)
