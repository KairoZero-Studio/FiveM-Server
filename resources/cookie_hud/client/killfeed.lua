-- cookie_hud receives the existing cookie_identityfx killfeed signal locally.
-- No replacement of HUD status, minimap, or identityfx title logic.
RegisterNetEvent('cookie_hud:client:killfeed', function(data)
    if type(data) ~= 'table' then return end
    SendNUIMessage({ action = 'cookieKillfeed', data = data })
end)
