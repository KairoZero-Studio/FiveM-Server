Config = Config or {}

Config.Debug = false

-- 시민직의 실제 해금 레벨은 cookie_admin의 중앙 시민직 레벨 시스템이 관리합니다.
-- cookie_skill은 경험치/통계 저장소이며, manualPromotion=true인 시민직은
-- 경험치 조건을 달성해도 자동 승급 알림/보너스 해금이 발생하지 않습니다.
Config.Skills = {}

Config.Skills.taxi = {
    label = '택시기사',
    manualPromotion = true,
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0,   fare = 1.00, tip = 0.05, longW = 0.5, veh = 'basic'  },
        { level = 2, exp = 50,  fare = 1.10, tip = 0.10, longW = 0.8, veh = 'basic'  },
        { level = 3, exp = 150, fare = 1.20, tip = 0.15, longW = 1.0, veh = 'mid'    },
        { level = 4, exp = 300, fare = 1.35, tip = 0.22, longW = 1.3, veh = 'mid'    },
        { level = 5, exp = 500, fare = 1.50, tip = 0.30, longW = 1.6, veh = 'luxury' },
    },
}

Config.Skills.trucker = {
    label = '트럭커',
    manualPromotion = true,
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0,   payMult = 1.00 },
        { level = 2, exp = 50,  payMult = 1.10 },
        { level = 3, exp = 150, payMult = 1.20 },
        { level = 4, exp = 300, payMult = 1.35 },
        { level = 5, exp = 500, payMult = 1.50 },
    },
}

Config.Skills.labor = {
    label = '건설 인부',
    manualPromotion = true,
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0,   payMult = 1.00 },
        { level = 2, exp = 50,  payMult = 1.05 },
        { level = 3, exp = 150, payMult = 1.10 },
        { level = 4, exp = 300, payMult = 1.17 },
        { level = 5, exp = 500, payMult = 1.25 },
    },
}

Config.Skills.delivery = {
    label = '배달기사',
    manualPromotion = true,
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0,   payMult = 1.00 },
        { level = 2, exp = 50,  payMult = 1.05 },
        { level = 3, exp = 150, payMult = 1.10 },
        { level = 4, exp = 300, payMult = 1.15 },
        { level = 5, exp = 500, payMult = 1.20 },
    },
}

Config.Skills.mechanic = {
    label = '정비공',
    manualPromotion = true,
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0,   payMult = 1.00 },
        { level = 2, exp = 50,  payMult = 1.05 },
        { level = 3, exp = 150, payMult = 1.10 },
        { level = 4, exp = 300, payMult = 1.16 },
        { level = 5, exp = 500, payMult = 1.23 },
    },
}

-- 낚시는 시민직 승급권 시스템과 별개의 숙련도이므로 기존 자동 레벨업을 유지합니다.
Config.Skills.fishing = {
    label = '낚시',
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0    },
        { level = 2, exp = 300  },
        { level = 3, exp = 900  },
        { level = 4, exp = 2000 },
        { level = 5, exp = 4000 },
    },
}

-- 광질은 성공적으로 광물 1개를 채굴할 때 1 EXP가 누적됩니다.
-- F3 직업 레벨에서는 이 실제 숙련도를 그대로 표시합니다.
Config.Skills.mining = {
    label = '광질',
    maxLevel = 5,
    levels = {
        { level = 1, exp = 0   },
        { level = 2, exp = 50  },
        { level = 3, exp = 150 },
        { level = 4, exp = 300 },
        { level = 5, exp = 500 },
    },
}

