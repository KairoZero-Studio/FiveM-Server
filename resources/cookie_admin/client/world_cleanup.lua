-- COOKIE: F3 world cleanup callback bridge (V2)
-- The UI shows a dedicated Yes/No confirmation before invoking this callback.
RegisterNUICallback('ckCleanupRequest', function(data, cb)
    if type(data) ~= 'table' or (data.mode ~= 'vehicles' and data.mode ~= 'objects') then
        cb({ ok = false, error = '올바르지 않은 삭제 요청입니다.' })
        return
    end
    local expected = data.mode == 'vehicles' and '차량삭제' or '오브젝트삭제'
    if data.confirm ~= expected then
        cb({ ok = false, error = '삭제 확인 값이 올바르지 않습니다.' })
        return
    end
    TriggerServerEvent('cookie_admin:server:cleanupWorldEntities', data.mode, expected)
    cb({ ok = true })
end)

RegisterNetEvent('cookie_admin:client:cleanupResult', function(msg)
    SendNUIMessage({ action = 'ckCleanupResult', message = tostring(msg or '') })
end)
