return {
    stress = {
        enableStress = false, -- If false, it will disable stress for everyone [쿠키 #긴급-4: 스트레스 비활성화 — qbx 업데이트 시 재적용 필요]
    },

    menu = { -- Don't touch
        isOutMapChecked = false, -- isOutMapChecked
        isOutCompassChecked = false, -- isOutMapChecked
        isCompassFollowChecked = true, -- isCompassFollowChecked
        -- [cookie] 우측 지도 로딩 알림 끔 (2026-07-13).
        --   'Square Map Loading...' / 'Loaded!' 영어 토스트가 접속할 때마다 우측에 쌓였다.
        --   로딩 안내는 cookie_hud 의 가운데 로딩 화면이 대신한다.
        isMapNotifChecked = false, -- isMapNotifChecked
        isLowFuelChecked = true, -- isLowFuelChecked
        isCinematicNotifChecked = true, -- isCinematicNotifChecked
        isDynamicHealthChecked = true, -- isDynamicHealthChecked
        isDynamicArmorChecked= true, -- isDynamicArmorChecked
        isDynamicHungerChecked = true, -- isDynamicHungerChecked
        isDynamicThirstChecked = true, -- isDynamicThirstChecked
        isDynamicStressChecked = true, -- isDynamicStressChecked
        isDynamicOxygenChecked = true, -- isDynamicOxygenChecked
        isChangeFPSChecked = true, -- isChangeFPSChecked
        isHideMapChecked = false, -- isHideMapChecked
        isToggleMapBordersChecked = true, -- isToggleMapBordersChecked
        isDynamicEngineChecked = true, -- isDynamicEngineChecked
        isDynamicNitroChecked = true, -- isDynamicNitroChecked
        -- [cookie 2026-07-14] 차량 탑승 시 상단에 뜨던 나침반/거리명/방위 전부 끔.
        --   ★ 우리 UI(접수 대기중 / 운행중)와 정면으로 겹쳤다.
        --     매 프레임 HideHudComponent로 싸우는 대신, 켜는 쪽을 끈다. 그게 근본이다.
        isChangeCompassFPSChecked = false,
        isCompassShowChecked = false,   -- 나침반 띠 (N / NW / NE)
        isShowStreetsChecked = false,   -- 거리명 (샌 바이터스 볼버드)
        isPointerShowChecked = false,   -- 방향 포인터
        isDegreesShowChecked = false,   -- 방위각 (328)
        isCineamticModeChecked = false, -- isCineamticModeChecked
        isToggleMapShapeChecked = 'square', -- isToggleMapShapeChecked
    }
}