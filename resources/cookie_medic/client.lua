

local DEATH_BAG = 'qbx_medical:deathState'
local ALIVE = 1

local isDown = false

local function setDownUI(on)
    SendNUIMessage({ action = on and 'show' or 'hide' })
    SetNuiFocus(on, on)
end

AddStateBagChangeHandler(DEATH_BAG, ('player:%s'):format(cache.serverId), function(_, _, value)
    local down = value ~= nil and value ~= ALIVE
    if down == isDown then return end
    isDown = down
    setDownUI(down)

end)

CreateThread(function()
    local v = LocalPlayer.state[DEATH_BAG]
    isDown = v ~= nil and v ~= ALIVE
    if isDown then setDownUI(true) end
end)

CreateThread(function()
    while true do
        if isDown then
            HideHudComponentThisFrame(1)
            HideHudComponentThisFrame(2)
            HideHudComponentThisFrame(3)
            HideHudComponentThisFrame(4)
            HideHudComponentThisFrame(6)
            HideHudComponentThisFrame(7)
            HideHudComponentThisFrame(9)
            HideHudComponentThisFrame(19)
            HideHudComponentThisFrame(20)

            ClearAllHelpMessages()

            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterNUICallback('declare', function(data, cb)
    cb({ ok = true })
    if not isDown then return end

    local kind = data and data.kind

    if kind ~= 'wipe' and kind ~= 'stop' and kind ~= 'death' and kind ~= 'revive' then return end

    TriggerServerEvent('cookie_medic:server:declare', kind)
end)

RegisterNetEvent('cookie_medic:client:status', function(text)
    SendNUIMessage({ action = 'status', text = text or '' })
end)

RegisterNetEvent('cookie_medic:client:reviveCount', function(sec)
    SendNUIMessage({ action = 'reviveCount', sec = sec })
end)

RegisterNetEvent('cookie_medic:client:reviveMode', function(boosted, sec)
    SendNUIMessage({
        action = 'reviveMode',
        boosted = boosted == true,
        sec = tonumber(sec) or 0,
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'hide' })
    SetNuiFocus(false, false)
end)
