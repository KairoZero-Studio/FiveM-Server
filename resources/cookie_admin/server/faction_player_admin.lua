local function fpNotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr == true)
end

-- 과거 버전에서 접속 플레이어 관리창에 만들었던 "팩션 관리" 탭을 제거한다.
-- 팩션 관련 관리자 기능은 이제 F3 > 서버 팩션 관리에서만 처리한다.
CreateThread(function()
    Wait(1800)
    local catId = MySQL.scalar.await(
        "SELECT id FROM cookie_admin_category WHERE category_key = 'faction_player' LIMIT 1"
    )
    if catId then
        MySQL.query.await('DELETE FROM cookie_admin_feature WHERE category_id = ?', { catId })
        MySQL.query.await('DELETE FROM cookie_admin_category WHERE id = ?', { catId })
    end
    MySQL.query.await("DELETE FROM cookie_admin_feature WHERE feature_key IN ('faction_warn','faction_remove')", {})
end)

-- 구버전 NUI가 남아 있어도 개인 팩션 경고/팩션직 제거는 실행하지 않는다.
RegisterNetEvent('cookie_admin:server:factionPlayerAction', function()
    fpNotify(source, '팩션 관련 조치는 F3 > 서버 팩션 관리에서 이용해주세요', true)
end)
