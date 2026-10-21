

RegisterNetEvent('cookie_hud:client:notice', function(data)
    if type(data) ~= 'table' then return end

    local text = tostring(data.text or '')
    if text == '' then return end

    local seconds = tonumber(data.seconds) or 0

    SendNUIMessage({
        action = 'notice',
        text = text,
        seconds = seconds,
        hold = tonumber(data.hold) or 6,
    })
end)
