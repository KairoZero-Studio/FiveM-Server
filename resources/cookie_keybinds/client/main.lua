-- COOKIE keybind compatibility helper
-- 키 가이드의 실제 UI/권한/DB 관리는 cookie_admin KEY GUIDE V3에서 담당합니다.

-- 구형 P 직접 지도 바인딩 무효화 유지.
RegisterCommand('cookie_direct_map', function()
    -- intentionally disabled
end, false)

exports('openMap', function()
    -- intentionally disabled
end)

print('[cookie_keybinds] V3.0 compatibility helper loaded')
