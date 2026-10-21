Config = {}

-- Keybinds
Config.SeatKey = 'M'
Config.SeatbeltKey = 'B'
Config.EngineKey = 'U'
Config.DoorMenuKey = 'J'
Config.LockKey = 'L'

-- 좌석 UI
Config.SeatRefreshMs = 250
Config.MaxSeats = 32

-- 차고 출고 초기 상태
Config.SpawnEngineOn = true
Config.SpawnUnlocked = true

-- 안전벨트
Config.Seatbelt = {
    enabled = true,

    -- 이 속도 이상 주행 중 급감속 시 안전벨트 미착용이면 튕겨나갈 수 있음.
    minSpeedKmh = 65.0,

    -- 직전 속도에서 현재 속도가 이 비율 아래로 급격히 떨어질 때 충돌로 판단.
    decelerationRatio = 0.50,

    -- 너무 작은 감속은 무시.
    minimumSpeedDropKmh = 35.0
}

-- 이미 Qbox 차량키 시스템이 실행 중이면 L 입력에서 COOKIE 잠금 로직은 양보합니다.
-- qbx_vehiclekeys가 없다면 COOKIE의 기본 잠금/해제가 동작합니다.
Config.PreferExternalVehicleKeys = true
Config.ExternalVehicleKeyResources = {
    'qbx_vehiclekeys',
    'qb-vehiclekeys',
}

Config.Debug = false
