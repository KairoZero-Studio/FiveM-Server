Config = {}

-- =========================================================
-- COOKIE SERVER custom map blips
-- =========================================================

Config.CustomSprites = {
    -- 1번째 줄
    MAIN_SQUARE   = 621, -- 메인광장
    MAIN_GARAGE   = 622, -- 메인차고
    SECURITY      = 623, -- 보안국
    POLICE        = 624, -- 경찰서
    GARAGE_AREA   = 625, -- 차고지
    CITY_HALL     = 626, -- 시청

    -- 2번째 줄
    DELIVERY      = 638, -- 배달기사
    REPAIR_WORKER = 639, -- 수리공
    CONVENIENCE   = 640, -- 편의점
    REPAIR_SHOP   = 641, -- 정비소
    BANK          = 642, -- 은행
    TAXI          = 643, -- 택시기사

    -- 3번째 줄
    ATM           = 656, -- ATM
    CLOTHING      = 657, -- 옷장
    CONSTRUCTION  = 661, -- 건설인부
    TRUCKER       = 667, -- 트럭기사
}

-- =========================================================
-- 기본 설정
-- =========================================================

Config.Defaults = {
    colour = 0,
    scale = 0.80,
    shortRange = false,
    display = 4,
    route = false,
    routeColour = 0,
}

-- =========================================================
-- 단일 맵포인트
-- =========================================================

Config.Blips = {
    {
        id = 'main_garage',
        label = '메인 차고',
        coords = vec3(255.23, -788.39, 31.45),

        sprite = Config.CustomSprites.MAIN_GARAGE,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'main_square',
        label = '메인 광장',
        coords = vec3(190.00, -932.09, 30.69),

        sprite = Config.CustomSprites.MAIN_SQUARE,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'city_hall',
        label = '시청',
        coords = vec3(-2237.32, 249.76, 176.35),

        sprite = Config.CustomSprites.CITY_HALL,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'delivery',
        label = '배달부',
        coords = vec3(-50.84, -1763.95, 29.09),

        sprite = Config.CustomSprites.DELIVERY,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'repair_shop',
        label = '정비소',
        coords = vec3(-350.7, -136.5, 39.0),

        sprite = Config.CustomSprites.REPAIR_SHOP,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'police',
        label = '경찰청',
        coords = vec3(-339.42, -253.27, 32.71),

        sprite = Config.CustomSprites.POLICE,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'construction',
        label = '건설 인부',
        coords = vec3(125.27, -396.01, 41.25),

        sprite = Config.CustomSprites.CONSTRUCTION,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'taxi',
        label = '택시 기사',
        coords = vec3(599.51, 89.73, 92.81),

        sprite = Config.CustomSprites.TAXI,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'trucker',
        label = '트럭 기사',
        coords = vec3(915.28, -3235.59, 5.90),

        sprite = Config.CustomSprites.TRUCKER,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'bank',
        label = '은행',
        coords = vec3(255.206, 225.303, 101.876),

        sprite = Config.CustomSprites.BANK,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },

    {
        id = 'SECURITY',
        label = '보안국',
        coords = vec3(302.41, 6632.19, 33.40),

        sprite = Config.CustomSprites.SECURITY,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,
    },
}

-- =========================================================
-- 그룹 맵포인트
--
-- 134~254 = 이름 없는 커스텀 카테고리
--
-- 그래서 오른쪽 범례에서
--
-- 차고지: 남부 차고지
--
-- 이런 식이 아니라
--
-- 남부 차고지 < 1/4 >
--
-- 식으로 나오게 함.
-- =========================================================

Config.BlipGroups = {

    -- =====================================================
    -- 차고지
    -- =====================================================

    GARAGES = {
        label = '차고지',

        -- 이름 없는 그룹
        category = 134,

        sprite = Config.CustomSprites.GARAGE_AREA,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,

        locations = {
            {
                id = 'garage_1',
                label = '은하 동네 옆 차고지',
                coords = vec3(-821.64, -1197.28, 6.84),
            },

            {
                id = 'garage_2',
                label = '대형 주차장 차고지',
                coords = vec3(-322.69, -697.32, 33.00),
            },

            {
                id = 'garage_3',
                label = '남부 차고지',
                coords = vec3(-459.97, -619.48, 31.17),
            },

            {
                id = 'garage_4',
                label = '남부 해안가 차고지',
                coords = vec3(-2000.95, -493.94, 11.38),
            },
        }
    },

    -- =====================================================
    -- 편의점
    -- =====================================================

    CONVENIENCE = {
        label = '편의점',

        -- 이름 없는 그룹
        category = 135,

        sprite = Config.CustomSprites.CONVENIENCE,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,

        locations = {
            {
                id = 'convenience_1',
                label = '북부 편의점 동 고속도로점',
                coords = vec3(2678.49, 3284.28, 55.24),
            },

            {
                id = 'convenience_2',
                label = '북부 편의점 남북도로점',
                coords = vec3(1164.901, 2711.500, 38.158),
            },

            {
                id = 'convenience_3',
                label = '남부 편의점 은하 동네점',
                coords = vec3(-1221.474, -908.906, 12.326),
            },

            {
                id = 'convenience_4',
                label = '남부 편의점 은행 위점',
                coords = vec3(378.280, 332.354, 103.566),
            },
        }
    },

    -- =====================================================
    -- ATM
    -- =====================================================

    ATMS = {
        label = 'ATM',

        -- 이름 없는 그룹
        category = 136,

        sprite = Config.CustomSprites.ATM,
        colour = 0,
        scale = 1.25,
        shortRange = true,
        display = 4,
        route = false,
        routeColour = 0,

        locations = {
            {
                id = 'atm_1',
                label = '북부 ATM 남북도로점',
                coords = vec3(1177.208, 2711.960, 38.098),
            },

            {
                id = 'atm_2',
                label = '남부 ATM 메인 광장점',
                coords = vec3(145.982, -1044.933, 29.378),
            },
        }
    },
}