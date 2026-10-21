-- COOKIE QUEST CLIENT V2.0.0

RegisterNUICallback('requestQuests', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestQuests')
end)

RegisterNUICallback('claimQuest', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:claimQuest', data and data.questId)
end)

RegisterNUICallback('requestQuestAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestQuestAdmin')
end)

RegisterNUICallback('saveQuestAdmin', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveQuestAdmin', data or {})
end)

RegisterNetEvent('cookie_admin:client:questData', function(data, message, isError)
    SendNUIMessage({ action='questData', data=data or {}, message=message, isError=isError==true })
end)

RegisterNetEvent('cookie_admin:client:questAdminData', function(data)
    SendNUIMessage({ action='questAdminData', data=data or {} })
end)

RegisterNetEvent('cookie_admin:client:questAdminSaved', function(ok, message)
    SendNUIMessage({ action='questAdminSaved', ok=ok==true, message=message or '' })
end)

print('^2[cookie_admin]^7 QUEST CLIENT ADMIN V2.0.0 ready')
