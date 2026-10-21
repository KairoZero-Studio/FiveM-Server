

local wheelOpen = false

local function closeWheel()
    if not wheelOpen then return end
    wheelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })
end

local function openWheel()
    if wheelOpen then closeWheel() return end

    if LocalPlayer.state.invOpen or LocalPlayer.state.invBusy then return end
    if IsEntityDead(cache.ped) then return end

    local weapons = lib.callback.await('cookie_weaponwheel:getWeapons', false)
    if not weapons then weapons = {} end

    local current = exports.ox_inventory:getCurrentWeapon()
    wheelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'show',
        weapons = weapons,
        currentSlot = current and current.slot or nil,
    })
end

RegisterCommand('cookie_weaponwheel', openWheel, false)
RegisterKeyMapping('cookie_weaponwheel', '무기휠 열기', 'keyboard', 'TAB')

RegisterNUICallback('select', function(data, cb)
    cb(1)
    closeWheel()
    local slot = tonumber(data and data.slot)
    if not slot then return end

    exports.ox_inventory:useSlot(slot)
end)

RegisterNUICallback('close', function(_, cb)
    cb(1)
    closeWheel()
end)

CreateThread(function()
    while true do
        if wheelOpen then
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            Wait(0)
        else
            Wait(200)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if wheelOpen then SetNuiFocus(false, false) end
end)
