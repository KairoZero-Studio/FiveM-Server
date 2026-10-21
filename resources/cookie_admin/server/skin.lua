

RegisterNetEvent('cookie_admin:server:applySkin', function(model)
    local src = source
    model = tostring(model or '')
    if model == '' then return end

    local row = MySQL.single.await(
        'SELECT id, skin_type, label FROM cookie_skin WHERE model_name = ? LIMIT 1', { model }
    )
    if not row then

        return
    end

    if row.skin_type == 'rp' then
        TriggerClientEvent('cookie_admin:client:applySkin', src, model)

        return
    end

    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin then

        return
    end

    if CookieGetAdminState(src) ~= 'duty' then

        TriggerClientEvent('cookie_admin:client:toast', src, '관리 시작 후 사용 가능합니다', true)
        return
    end

    if row.skin_type ~= 'admin' then
        local mine = MySQL.single.await(
            'SELECT 1 AS x FROM cookie_admin_skin WHERE admin_id = ? AND skin_id = ? LIMIT 1',
            { admin.id, row.id }
        )
        if not mine then

            return
        end
    end

    TriggerClientEvent('cookie_admin:client:applySkin', src, model)

end)
