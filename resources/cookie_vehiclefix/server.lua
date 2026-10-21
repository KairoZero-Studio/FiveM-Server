RegisterNetEvent('cookie_vehiclefix:server:ensureExitKeys', function(netId)
    local src = source
    netId = tonumber(netId)
    if not netId then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    -- 악용 방지: 실제로 해당 차량 운전석에 있거나 바로 하차한 운전자만 키 보장.
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local driver = GetPedInVehicleSeat(vehicle, -1)
    local closeEnough = #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= 8.0

    if driver ~= ped and not closeEnough then return end

    if GetResourceState('qbx_vehiclekeys') == 'started' then
        local ok, err = pcall(function()
            exports.qbx_vehiclekeys:GiveKeys(src, vehicle, true)
        end)

        if not ok then
            print(('[cookie_vehiclefix] qbx_vehiclekeys GiveKeys failed src=%s netId=%s err=%s')
                :format(tostring(src), tostring(netId), tostring(err)))
        end
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        local plate = GetVehicleNumberPlateText(vehicle)
        TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate)
    end

    TriggerClientEvent('cookie_vehiclefix:client:unlockVehicle', src, netId)
end)

print('^2[cookie_vehiclefix]^7 server V1.0.0 ready')
