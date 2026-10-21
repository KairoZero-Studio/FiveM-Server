Config = {}

-- F3에서 변경 가능. DB 설정이 없을 때만 사용하는 최초 기본값입니다.
Config.Default = {
    enabled = true,
    title = 'COOKIE 월간 쿠지',
    seasonMonth = os.date('%Y-%m'),
    ticketItem = 'cookie_kuji_ticket',

    -- 메인광장 임시 기본 위치. F3에서 좌표를 직접 변경할 수 있습니다.
    beacon = vector3(190.00, -932.09, 30.69),
    beaconColor = { r = 255, g = 190, b = 45, a = 155 },

    interactDistance = 2.0,
    renderDistance = 60.0,
    -- V1.1: 바닥에 붙는 납작한 원형 비콘
    markerDiameter = 1.60,
    markerHeight = 0.80,
}

Config.DrawCooldownMs = 1200

-- 최초 DB 생성 시 들어가는 예시 경품입니다.
-- F3 > 관리자 > 시스템 관리 > 월간 쿠지에서 전부 변경할 수 있습니다.
Config.DefaultPrizes = {
    { grade = 'A', label = '한정 차량 예시', rewardType = 'vehicle', rewardKey = 'replace_me', amount = 1, stock = 1, image = '', sortOrder = 10 },
    { grade = 'B', label = '한정 치장 예시', rewardType = 'cosmetic', rewardKey = 'replace_me', amount = 1, stock = 3, image = '', sortOrder = 20 },
    { grade = 'C', label = '쿠지 티켓 보너스', rewardType = 'item', rewardKey = 'cookie_kuji_ticket', amount = 1, stock = 5, image = '', sortOrder = 30 },
}
