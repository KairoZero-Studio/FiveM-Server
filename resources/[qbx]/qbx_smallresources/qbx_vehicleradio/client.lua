local config = lib.loadJson('qbx_vehicleradio.config')
local radioEnabled = not config.disableRadioByDefault

-- COOKIE: remove vehicle-radio toggle command and F9 key mapping.
-- Leave automatic in-vehicle radio state management intact.

lib.onCache('vehicle', function(currentVehicle)
    if currentVehicle and currentVehicle ~= 0 then
        SetUserRadioControlEnabled(radioEnabled)
        if not radioEnabled then
            SetVehRadioStation(currentVehicle, "OFF")
        end
    else
        SetUserRadioControlEnabled(true)
    end
end)