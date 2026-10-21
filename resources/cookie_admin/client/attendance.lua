-- COOKIE ATTENDANCE CLIENT V2.0.0

RegisterNUICallback('requestAttendance', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestAttendance')
end)

RegisterNUICallback('claimAttendance', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:claimAttendance', data or {})
end)

RegisterNUICallback('requestAttendanceAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestAttendanceAdmin')
end)

RegisterNUICallback('saveAttendanceAdmin', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveAttendanceAdmin', data or {})
end)

RegisterNUICallback('resetAttendance', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:resetAttendance', data or {})
end)

RegisterNetEvent('cookie_admin:client:attendanceData', function(data, message, isError)
    SendNUIMessage({ action='attendanceData', data=data or {}, message=message, isError=isError==true })
end)

RegisterNetEvent('cookie_admin:client:attendanceAdminData', function(data)
    SendNUIMessage({ action='attendanceAdminData', data=data or {} })
end)

RegisterNetEvent('cookie_admin:client:attendanceAdminSaved', function(ok, message)
    SendNUIMessage({ action='attendanceAdminSaved', ok=ok==true, message=message or '' })
end)

RegisterNetEvent('cookie_admin:client:attendanceResetResult', function(ok, message, mode)
    SendNUIMessage({ action='attendanceResetResult', ok=ok==true, message=message or '', mode=mode or 'monthly' })
end)
