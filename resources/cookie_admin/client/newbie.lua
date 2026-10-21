-- COOKIE F3 NEWBIE KIT SYSTEM V1

RegisterNUICallback('requestNewbieKitSystem', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestNewbieKitSystem')
end)

RegisterNUICallback('saveNewbieKitSystem', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveNewbieKitSystem', data or {})
end)

RegisterNetEvent('cookie_admin:client:newbieKitSystemData', function(data, message, isError)
    SendNUIMessage({
        action = 'newbieKitSystemData',
        data = data or {},
        message = message,
        isError = isError == true,
    })
end)

RegisterNetEvent('cookie_admin:client:newbieKitSystemSaved', function(ok, message)
    SendNUIMessage({
        action = 'newbieKitSystemSaved',
        ok = ok == true,
        message = message or '',
    })
end)
