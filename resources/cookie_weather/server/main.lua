

local API_KEY = GetConvar('cookie:owmKey', '')
local URL = 'https://api.openweathermap.org/data/2.5/weather?q=%s&appid=%s&units=metric&lang=kr'

local desired = nil
local lastPayload = nil

local function applyWeather(gtaType)
    local cur = GlobalState.weather
    if cur and cur.weather == gtaType then return end
    GlobalState.weather = {
        weather = gtaType,
        time = 9000000,
        hasSnow = Config.SnowTypes[gtaType] or nil,
    }

end

local function pushWeatherHud(target)
    if lastPayload then
        TriggerClientEvent('cookie_hud:setWeather', target, lastPayload)
    end
end

local function poll()
    local url = URL:format(Config.City, API_KEY)
    PerformHttpRequest(url, function(status, body)

        if status ~= 200 or not body or body == '' then

            return
        end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' or not data.weather or not data.weather[1] then

            return
        end

        local main   = data.weather[1].main
        local descKr = data.weather[1].description or main
        local temp   = (data.main and data.main.temp) and math.floor(data.main.temp + 0.5) or nil
        local gta    = Config.WeatherMap[main] or Config.DefaultWeather
        local icon   = Config.IconMap[main] or ''

        desired = gta
        lastPayload = { desc = descKr, temp = temp, icon = icon }
        applyWeather(gta)
        pushWeatherHud(-1)

    end, 'GET', '', { ['Content-Type'] = 'application/json' })
end

RegisterNetEvent('cookie_hud:server:requestHud', function()
    pushWeatherHud(source)
end)

if API_KEY == '' then

    return
end

CreateThread(function()
    while true do
        poll()
        Wait(Config.PollIntervalMs)
    end
end)

CreateThread(function()
    while true do
        Wait(Config.ReassertIntervalMs)
        if desired then applyWeather(desired) end
    end
end)

