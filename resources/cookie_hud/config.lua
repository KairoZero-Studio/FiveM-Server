Config = {}
Config.Debug = false

Config.BrandColor = '#FFB800'

function CookieHudLog(...)
    if not Config.Debug then return end
    local args = { ... }
    local msg = '^3[cookie_hud]^7'
    for _, v in ipairs(args) do
        msg = msg .. '\t' .. tostring(v)
    end

end
