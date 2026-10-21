local MODEL = joaat(Config.Model)

local function applyHandling(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if GetEntityModel(vehicle) ~= MODEL then return end

    for field, value in pairs(Config.Handling) do
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value + 0.0)
    end

    if Config.OverrideAcceleration then
        for field, value in pairs(Config.Acceleration) do
            SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value + 0.0)
        end
    end
end

CreateThread(function()
    AddTextEntry('SENTINEL', Config.DisplayName)

    local lastVeh = 0

    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)

        if veh ~= 0 and GetEntityModel(veh) == MODEL then
            if GetPedInVehicleSeat(veh, -1) == ped then
                applyHandling(veh)

                if Config.Debug and veh ~= lastVeh then
                    print('[COOKIE] Sentinel XS 일반차 핸들링 적용')
                end
            end

            lastVeh = veh
            Wait(1000)
        else
            lastVeh = 0
            Wait(1500)
        end
    end
end)

RegisterCommand('cookie_sentinel_handling', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 or GetEntityModel(veh) ~= MODEL then
        print('[COOKIE] Sentinel XS에 탑승한 상태에서 사용하세요.')
        return
    end

    local brake = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce')
    local steer = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fSteeringLock')
    local tmax = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax')
    local tmin = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin')
    local susp = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fSuspensionForce')
    local force = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce')

    print(('[COOKIE] Sentinel XS | Brake %.3f | Steering %.2f | Traction %.3f/%.3f | Suspension %.3f | DriveForce %.3f')
        :format(brake, steer, tmax, tmin, susp, force))
end, false)
