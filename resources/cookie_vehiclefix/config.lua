Config = {}

-- =========================================================
-- 하차 잠금 버그
-- =========================================================
Config.ExitUnlockFix = true

-- F로 하차한 직후 다른 키 리소스가 다시 잠그는 경쟁 상태를 막는 시간.
-- 이 시간 동안 방금 운전한 차량을 잠금 해제 상태로 재확정합니다.
Config.ExitUnlockGuardMs = 3500
Config.ExitUnlockTickMs = 125

-- 하차 직전 qbx_vehiclekeys에 키를 다시 보장합니다.
Config.EnsureQbxKeysOnExit = true

-- =========================================================
-- 전체 차량 기본 내구도
-- 값이 낮을수록 데미지를 적게 받습니다.
-- 기존 차량의 수치가 이미 더 튼튼하면 그 값을 그대로 유지합니다.
-- =========================================================
Config.GlobalDurability = {
    enabled = true,
    collision = 0.55,
    deformation = 0.60,
    engine = 0.60,
    weapon = 0.85,
}

-- =========================================================
-- 오딘(5대차) 최상위 내구도
-- 고속 충돌을 수십 번 해도 쉽게 엔진/차체가 망가지지 않는 방향.
-- 폭발 등 GTA 자체 즉사급 상황까지 완전 무적으로 만들지는 않습니다.
-- =========================================================
Config.Odin = {
    enabled = true,

    -- 기본 spawncode 기준. 실제 spawncode가 다르면 여기에 추가하면 됩니다.
    models = {
        'odin',
    },

    -- vehicles.meta displayName이 ODIN 계열인 경우도 자동 감지.
    displayNameContains = {
        'ODIN',
    },

    collision = 0.035,
    deformation = 0.025,
    engine = 0.020,
    weapon = 0.20,

    -- GTA의 추가 차량 강성 플래그.
    strong = true,

    -- 엔진 자연 열화를 꺼서 충돌 누적으로 엔진이 너무 빨리 사망하는 현상 방지.
    disableEngineDegrade = true,

    -- 타이어는 게임성을 위해 기본적으로 터질 수 있게 둠.
    tyresCanBurst = true,
}

Config.Debug = false
