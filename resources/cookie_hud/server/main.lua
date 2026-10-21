print('^2[COOKIE HUD]^7 build 20260828-CAMERA-HUDOFF loaded')


local WD = { '일', '월', '화', '수', '목', '금', '토' }

local function buildClock()
    local t = os.date('!*t', os.time() + 9 * 3600)

    local ampm = t.hour < 12 and '오전' or '오후'
    local h12 = t.hour % 12
    if h12 == 0 then h12 = 12 end
    return ('%d년%02d월%02d일 (%s) %s %d:%02d'):format(t.year, t.month, t.day, WD[t.wday], ampm, h12, t.min)
end

local function pushInfo(target)
    TriggerClientEvent('cookie_hud:setClock', target, { text = buildClock(), players = #GetPlayers() })
end

CreateThread(function()
    while true do
        pushInfo(-1)
        Wait(60000)
    end
end)

RegisterNetEvent('cookie_hud:server:requestHud', function()
    pushInfo(-1)
end)

AddEventHandler('playerDropped', function()
    CreateThread(function() Wait(50); pushInfo(-1) end)
end)

