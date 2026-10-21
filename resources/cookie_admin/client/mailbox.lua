RegisterNUICallback('requestGrantItems', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestGrantItems')
    cb({ ok = true })
end)

RegisterNUICallback('sendGrantMail', function(data, cb)
    TriggerServerEvent('cookie_admin:server:sendGrantMail', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('requestMailbox', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestMailbox')
    cb({ ok = true })
end)

RegisterNUICallback('claimMailbox', function(data, cb)
    TriggerServerEvent('cookie_admin:server:claimMailbox', data and data.id)
    cb({ ok = true })
end)

RegisterNUICallback('deleteMailbox', function(data, cb)
    TriggerServerEvent('cookie_admin:server:deleteMailbox', data and data.id)
    cb({ ok = true })
end)

RegisterNetEvent('cookie_admin:client:grantItems', function(items, err)
    SendNUIMessage({ action = 'grantItemCatalog', items = items or {}, error = err })
end)

RegisterNetEvent('cookie_admin:client:mailboxData', function(rows)
    SendNUIMessage({ action = 'mailboxData', rows = rows or {} })
end)

RegisterNetEvent('cookie_admin:client:mailArrived', function(adminName, label)
    SendNUIMessage({
        action = 'toast',
        message = ('관리자 %s님이 우편을 보냈습니다 · %s'):format(tostring(adminName or '관리자'), tostring(label or '보상')),
        isWarn = false,
    })
end)

RegisterNetEvent('cookie_admin:client:grantMailResult', function(ok)
    SendNUIMessage({ action = 'grantMailResult', ok = ok == true })
end)
