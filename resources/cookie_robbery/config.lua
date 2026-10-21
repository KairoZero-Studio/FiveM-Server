Config = {}

-- 첫 버전은 편의점 강도. DB 구조는 추후 ATM/보석상/은행 타입 확장 가능.
Config.DefaultType = 'convenience'

-- 강도 시작 키
Config.InteractControl = 38 -- E

-- 시작자는 반드시 총기류를 들고 있어야 함.
Config.RequireFirearm = true

-- 시작 순간 이 거리 안에서 '무기를 들고 있는 비치안 유저'를 공범으로 자동 편입.
Config.DefaultCrewRadius = 12.0

-- 강도팀이 현장을 완전히 벗어난 상태가 이 시간 이상 이어지면 실패.
Config.LeaveGraceSeconds = 10

-- 경찰 결과 입력 비콘 상호작용 허용 거리.
Config.PoliceResultDistance = 3.5

-- 신고 블립
Config.DispatchBlipSeconds = 180
Config.DispatchBlipSprite = 161
Config.DispatchBlipColor = 5 -- yellow
Config.DispatchBlipScale = 1.05

-- 치안 팩션 타입
Config.LawFactionTypes = {
    police = true,
    security = true,
}

-- 장소마다 관리자에서 '필수 출근 팩션 + 최소 인원'을 직접 지정한다.
-- 아무 팩션 조건도 등록하지 않은 기존 장소만 아래 fallback을 사용.
-- 0 = 제한 없음 / 1 = 경찰·보안국 합산 최소 1명
Config.FallbackLawOnDuty = 1

-- 등록된 모든 RP 장소의 교전 반경을 평소에도 빨간 선으로 표시.
Config.AlwaysShowConfiguredBoundaries = true
Config.ConfiguredBoundaryAlpha = 115

Config.Debug = false


-- 빈집 강도: 근접무기만 허용.
-- 아래 그룹은 GTA weapon group hash 기준으로 판정한다.
Config.EmptyHouse = {
    breakInSeconds = 7,

    -- 빈집 강도는 총기류를 들고 시작할 수 없음.
    requireMelee = true,
    blockFirearms = true,

    -- 서버/클라이언트에서 GetWeapontypeGroup 판정에 의존하지 않고
    -- 허용된 근접무기 해시를 직접 비교한다.
    allowedMeleeWeapons = {
        'WEAPON_KNIFE',
        'WEAPON_NIGHTSTICK',
        'WEAPON_HAMMER',
        'WEAPON_BAT',
        'WEAPON_GOLFCLUB',
        'WEAPON_CROWBAR',
        'WEAPON_BOTTLE',
        'WEAPON_DAGGER',
        'WEAPON_HATCHET',
        'WEAPON_KNUCKLE',
        'WEAPON_MACHETE',
        'WEAPON_FLASHLIGHT',
        'WEAPON_SWITCHBLADE',
        'WEAPON_WRENCH',
        'WEAPON_BATTLEAXE',
        'WEAPON_POOLCUE',
        'WEAPON_STONE_HATCHET',
        'WEAPON_CANDYCANE',
    }
}

-- 편의점 전멸전 빨간 경계선 표시 설정.
Config.ConvenienceBoundary = {
    enabled = true,
    segments = 72,        -- 원을 구성하는 선 조각 수
    heightOffset = 0.08,  -- 바닥에서 살짝 띄움
    alpha = 220,
    drawDistance = 180.0, -- 이 거리 안 유저에게만 렌더
}


-- 은행 강도(대형 RP)
Config.Bank = {
    -- 은행은 총기 사용 전제로 시작.
    requireFirearm = true,

    -- 전리품 비콘 기본 회수 시간(비콘별 설정이 없을 때).
    defaultLootSeconds = 10,

    -- 최종 전멸전 범위도 빨간 경계선을 표시.
    showBoundary = true,

    -- 은행 전리품은 최종 승리 전까지 서버 세션에 임시 보관(escrow)한다.
    -- 경찰 승리 시 지급되지 않고 사라지므로 중간 거래/도주 악용을 막는다.
    escrowUntilVictory = true,
}

-- COOKIE RP V1.6 범위 시각화
Config.BoundaryVisual = {
    style = 'wall',        -- wall / line
    wallHeight = 0.22,     -- 땅에 붙는 낮은 경계 띠
    groundOffset = 0.015,  -- 지면과 겹쳐 깜빡이는 현상 방지
    idleAlpha = 62,        -- 평소
    activeAlpha = 125,     -- RP 진행 중
    lineAlpha = 245,
    showVertices = true,
}
