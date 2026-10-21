

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    local tableCount = 0
    for _ in pairs(Config.Tables or {}) do tableCount = tableCount + 1 end

    local ok, items = pcall(function() return exports.ox_inventory:Items() end)
    if ok and items and items[Config.Chip] then

    else

    end
end)

RegisterCommand('casino_test', function(source)

    if source ~= 0 then
        TriggerClientEvent('chat:addMessage', source, { args = { '^5[cookie_casino]', '자기점검 로그를 서버 콘솔에 출력했습니다.' } })
    end
end, true)
