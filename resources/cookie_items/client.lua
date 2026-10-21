local energyDrinkUntil = 0
local energyBoostActive = false

local function notify(message, error)
    if GetResourceState('cookie_admin') == 'started' then
        TriggerEvent('cookie_admin:client:notify', message, error == true)
        return
    end

    if lib and lib.notify then
        lib.notify({
            type = error and 'error' or 'success',
            description = message,
        })
    end
end

local function useInventoryItem(data, callback)
    if GetResourceState('ox_inventory') ~= 'started' then
        notify('ox_inventory가 실행 중이 아닙니다.', true)
        return
    end

    exports.ox_inventory:useItem(data, function(used)
        if not used then return end
        callback(used)
    end)
end

exports('armor', function(data)
    useInventoryItem(data, function()
        local ped = PlayerPedId()
        if ped == 0 or IsEntityDead(ped) then return end
        SetPedArmour(ped, 100)
        notify('방탄 게이지가 100%로 충전되었습니다.')
    end)
end)

exports('medikit', function(data)
    useInventoryItem(data, function()
        local ped = PlayerPedId()
        if ped == 0 or IsEntityDead(ped) then return end
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        notify('체력이 100% 회복되었습니다.')
    end)
end)

exports('oxy', function(data)
    useInventoryItem(data, function()
        local ped = PlayerPedId()
        if ped == 0 or IsEntityDead(ped) then return end

        local maxHealth = GetEntityMaxHealth(ped)
        local healAmount = math.max(1, math.floor((maxHealth - 100) * 0.50))
        SetEntityHealth(ped, math.min(maxHealth, GetEntityHealth(ped) + healAmount))
        notify('진통제로 체력을 50% 회복했습니다.')
    end)
end)

local function clearEnergyBoost()
    if energyBoostActive then
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
        energyBoostActive = false
    end
end

CreateThread(function()
    while true do
        if energyDrinkUntil > 0 then
            if GetGameTimer() >= energyDrinkUntil then
                energyDrinkUntil = 0
                clearEnergyBoost()
                notify('에너지 드링크 효과가 종료되었습니다.')
                Wait(750)
            else
                energyBoostActive = true
                SetRunSprintMultiplierForPlayer(PlayerId(), 1.15)
                RestorePlayerStamina(PlayerId(), 1.0)
                Wait(0)
            end
        else
            Wait(750)
        end
    end
end)

exports('energyDrink', function(data)
    useInventoryItem(data, function()
        local ped = PlayerPedId()
        if ped == 0 or IsEntityDead(ped) then return end

        energyDrinkUntil = GetGameTimer() + 10000
        energyBoostActive = true
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.15)
        RestorePlayerStamina(PlayerId(), 1.0)
        notify('10초 동안 이동 속도가 증가합니다.')
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearEnergyBoost()
end)


exports('newbieRewardKit', function(data)
    useInventoryItem(data, function()
        TriggerServerEvent('cookie_items:server:openNewbieRewardKit')
    end)
end)
