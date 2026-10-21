

local KEEP = {
    [8] = true,
}

local MAX_SPRITE = 900

local mine = {}

exports('keepBlip', function(blip)
    if blip and blip ~= 0 then mine[blip] = true end
end)

RegisterNetEvent('cookie_hud:client:keepBlip', function(blip)
    if blip and blip ~= 0 then mine[blip] = true end
end)

local function stripBlips()
    local removed = 0

    for sprite = 1, MAX_SPRITE do
        if not KEEP[sprite] then
            local blip = GetFirstBlipInfoId(sprite)
            local guard = 0

            while DoesBlipExist(blip) and guard < 500 do
                guard = guard + 1

                if mine[blip] or IsMissionCreatorBlip(blip) then

                    blip = GetNextBlipInfoId(sprite)
                else
                    RemoveBlip(blip)
                    removed = removed + 1
                    blip = GetFirstBlipInfoId(sprite)
                end
            end
        end
    end

    return removed
end

CreateThread(function()
    Wait(2000)

    local first = stripBlips()

    local wasPause = false

    while true do
        Wait(1000)
        stripBlips()

        local pause = IsPauseMenuActive()
        if pause and not wasPause then
            stripBlips()
            Wait(0)
            stripBlips()
        end
        wasPause = pause
    end
end)

RegisterCommand('blipcount', function()
    local n = 0
    for sprite = 1, MAX_SPRITE do
        local blip = GetFirstBlipInfoId(sprite)
        while DoesBlipExist(blip) do
            n = n + 1
            blip = GetNextBlipInfoId(sprite)
        end
    end

end, false)
