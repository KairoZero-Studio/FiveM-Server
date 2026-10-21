

local blips = {}

local function removeBlip(netId)
    local b = blips[netId]
    if b and DoesBlipExist(b) then RemoveBlip(b) end
    blips[netId] = nil
end

local function clearAll()
    for netId in pairs(blips) do removeBlip(netId) end
end

RegisterNetEvent('cookie_taxi:client:taxiBlips', function(list)
    local seen = {}

    for _, netId in ipairs(list or {}) do
        seen[netId] = true

        if not blips[netId] then

            if NetworkDoesNetworkIdExist(netId) then
                local veh = NetToVeh(netId)
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                    local b = AddBlipForEntity(veh)
                    SetBlipSprite(b, 198)
                    SetBlipColour(b, 5)
                    SetBlipScale(b, 0.8)
                    SetBlipAsShortRange(b, false)
                    ShowHeadingIndicatorOnBlip(b, true)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentSubstringPlayerName('택시 (빈차)')
                    EndTextCommandSetBlipName(b)
                    blips[netId] = b
                end
            end
        end
    end

    for netId in pairs(blips) do
        if not seen[netId] then removeBlip(netId) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAll() end
end)
