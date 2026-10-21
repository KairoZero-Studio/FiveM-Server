-- COOKIE TITLE SYSTEM V3 CLIENT

RegisterNUICallback('requestTitles', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestTitles')
end)

RegisterNUICallback('equipTitle', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:equipTitle', data and data.kind, data and data.id or nil)
end)

RegisterNUICallback('saveTitleDisplaySettings', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveTitleDisplaySettings', data or {})
end)

RegisterNUICallback('requestTitleAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestTitleAdmin')
end)

RegisterNUICallback('saveTitleDefinition', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveTitleDefinition', data or {})
end)

RegisterNUICallback('grantEventTitle', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:grantEventTitle', data and data.id, data and data.gobun)
end)

RegisterNUICallback('revokeEventTitle', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:revokeEventTitle', data and data.id, data and data.gobun)
end)

RegisterNUICallback('deleteTitleDefinition', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:deleteTitleDefinition', data and data.id)
end)

RegisterNetEvent('cookie_admin:client:titleUserData', function(data, message, isError)
    SendNUIMessage({ action='titleUserData', data=data or {}, message=message, isError=isError == true })
end)

RegisterNetEvent('cookie_admin:client:titleAdminData', function(data, message, isError)
    SendNUIMessage({ action='titleAdminData', data=data or {}, message=message, isError=isError == true })
end)
