Config = {}
Config.Debug = false

Config.City = 'Seoul,KR'
Config.PollIntervalMs = 10 * 60 * 1000
Config.ReassertIntervalMs = 30 * 1000

Config.WeatherMap = {
    Clear        = 'EXTRASUNNY',
    Clouds       = 'CLOUDS',
    Rain         = 'RAIN',
    Drizzle      = 'RAIN',
    Thunderstorm = 'THUNDER',
    Snow         = 'SNOW',
    Mist         = 'FOGGY',
    Fog          = 'FOGGY',
    Haze         = 'FOGGY',
    Smoke        = 'FOGGY',
    Dust         = 'FOGGY',
    Sand         = 'FOGGY',
    Ash          = 'FOGGY',
    Squall       = 'THUNDER',
    Tornado      = 'THUNDER',
}
Config.DefaultWeather = 'CLOUDS'

Config.IconMap = {
    Clear = '☀️', Clouds = '☁️', Rain = '🌧️', Drizzle = '🌦️',
    Thunderstorm = '⛈️', Snow = '❄️', Mist = '🌫️', Fog = '🌫️',
    Haze = '🌫️', Smoke = '🌫️', Dust = '🌫️', Sand = '🌫️', Ash = '🌫️',
    Squall = '🌬️', Tornado = '🌪️',
}

Config.SnowTypes = { SNOW = true, BLIZZARD = true, XMAS = true }

function CookieWeatherLog(...)
    if not Config.Debug then return end
    local args = { ... }
    local msg = '^3[cookie_weather]^7'
    for _, v in ipairs(args) do msg = msg .. '\t' .. tostring(v) end

end
