local playerId = PlayerId()

local function disableNativePolice()
    if not Config.DisableNativePolice then return end

    SetCreateRandomCops(false)
    SetCreateRandomCopsNotOnScenarios(false)
    SetCreateRandomCopsOnScenarios(false)
    SetPoliceIgnorePlayer(playerId, true)
    SetDispatchCopsForPlayer(playerId, false)

    for service = 1, 15 do
        EnableDispatchService(service, false)
    end
end

local function isAmbientPopulationEntity(entity)
    if not DoesEntityExist(entity) or IsEntityAMissionEntity(entity) then
        return false
    end

    local populationType = GetEntityPopulationType(entity)
    return populationType >= 1 and populationType <= 5
end

local function deleteAmbientEntities()
    if not Config.DeleteExistingAmbientEntities then return end

    if Config.RemoveAmbientPeds then
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and isAmbientPopulationEntity(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            end
        end
    end

    if Config.RemoveAmbientTraffic or Config.RemoveParkedVehicles then
        for _, vehicle in ipairs(GetGamePool('CVehicle')) do
            if isAmbientPopulationEntity(vehicle) then
                SetEntityAsMissionEntity(vehicle, true, true)
                DeleteEntity(vehicle)
            end
        end
    end
end

CreateThread(function()
    if Config.DisableWantedLevel then
        SetMaxWantedLevel(0)
    end

    disableNativePolice()
    SetGarbageTrucks(false)
    SetRandomBoats(false)
    SetRandomTrains(false)

    print('^2[cookie_worldclean]^7 ambient NPC/traffic/native HUD cleanup loaded')
end)

CreateThread(function()
    while true do
        playerId = PlayerId()

        if Config.RemoveAmbientPeds then
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        end

        if Config.RemoveAmbientTraffic then
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
        end

        if Config.RemoveParkedVehicles then
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
        end

        if Config.DisableWantedLevel and GetPlayerWantedLevel(playerId) ~= 0 then
            SetPlayerWantedLevel(playerId, 0, false)
            SetPlayerWantedLevelNow(playerId, false)
        end

        if Config.HideNativeHud then
            for _, component in ipairs(Config.HiddenHudComponents or {}) do
                HideHudComponentThisFrame(component)
            end
        end

        if Config.HideNativeHelpText then
            HideHudComponentThisFrame(10)
            HideHudComponentThisFrame(11)
            HideHudComponentThisFrame(12)
        end

        Wait(0)
    end
end)

CreateThread(function()
    while true do
        disableNativePolice()

        if Config.DisableWantedLevel then
            SetMaxWantedLevel(0)
        end

        SetGarbageTrucks(false)
        SetRandomBoats(false)
        SetRandomTrains(false)
        deleteAmbientEntities()

        Wait(2500)
    end
end)
