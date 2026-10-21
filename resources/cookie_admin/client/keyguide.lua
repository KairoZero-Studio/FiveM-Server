print('[cookie_admin] KEY GUIDE V3.0 client loaded')

-- COOKIE KEY GUIDE V3

RegisterNUICallback('requestKeyGuide', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestKeyGuide')
end)

RegisterNUICallback('requestKeyGuideAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestKeyGuideAdmin')
end)

RegisterNUICallback('saveKeyGuideAdmin', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveKeyGuideAdmin', data or {})
end)

RegisterNetEvent('cookie_admin:client:keyGuideData', function(data)
    SendNUIMessage({
        action = 'keyGuideData',
        data = data or { categories = {} }
    })
end)

RegisterNetEvent('cookie_admin:client:keyGuideAdminData', function(data)
    SendNUIMessage({
        action = 'keyGuideAdminData',
        data = data or { categories = {}, factions = {} }
    })
end)

RegisterNetEvent('cookie_admin:client:keyGuideAdminSaved', function(ok, message)
    SendNUIMessage({
        action = 'keyGuideAdminSaved',
        ok = ok == true,
        message = message or ''
    })
end)
