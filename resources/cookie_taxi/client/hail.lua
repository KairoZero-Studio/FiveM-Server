

local blips = {}

local function clearBlips()
    for _, b in ipairs(blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    blips = {}
end

local function mark(x, y, z, sprite, colour, text)
    local b = AddBlipForCoord(x + 0.0, y + 0.0, z + 0.0)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, colour)
    SetBlipScale(b, 0.7)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandSetBlipName(b)
    blips[#blips + 1] = b
end

RegisterNetEvent('cookie_taxi:client:hailList', function(_)
    clearBlips()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearBlips() end
end)
