

Config = Config or {}

Config.Debug = false

Config.Taxi = {

    Skill      = 'taxi',
    ExpPerRide = 1,

    BaseFare  = 5500,
    FreeDist  = 1000.0,
    StepDist  = 500.0,
    StepFare  = 200,
    IntercityFee = 2000,
    MaxFare   = 200000,
    Salary    = 0,

    TipMin = 0.05,
    TipMax = 0.20,

    MeterTick    = 250,
    MeterMinMove = 0.05,
    MaxTickMove  = 60.0,
    PushEvery    = 4,

    NpcCallMaxPlayers = 50,
    CallInterval      = { min = 90, max = 240 },
    MaxActiveHails    = 3,
    HailTTL           = 600,
    RenderDistance    = 250.0,

    OfferTTL = 20,
    RespawnAfterDecline = { min = 15, max = 40 },

    IdleCallMax = 45,

    DeclinePenalty = false,

    PickupRadius = 4.0,
    DropRadius   = 20.0,
    StopSpeed    = 2.0,
    AutoPickup   = false,

    RoadSnap        = false,
    RoadSnapMax     = 60.0,
    RoadSideOffset  = 3.2,

    RoadSnapMaxDrop = 7.0,

    ClaimTolerance = 40.0,

    OutOfVehLimit = 60,
    JobTimeout    = 900,

    MinTripDistance = 300.0,
    NearMax         = 800.0,
    MidMax          = 2500.0,

    PlatePrefix = 'TAXI',

    SpawnOffset = 5.0,

    GhostSeconds = 5,
    GhostAlpha   = 160,
}

Config.Taxi.Vehicles = {
    { key = 'basic',  label = '기본 택시', model = 'lftaxi',
      level = 1, repairFee = 40000,  lossFee = 120000 },
    { key = 'mid',    label = '중형 택시', model = 'grandgeurtaxi',
      level = 3, repairFee = 90000,  lossFee = 300000 },
    { key = 'luxury', label = '고급 택시', model = 'equustaxi',
      level = 5, repairFee = 180000, lossFee = 600000 },
}

Config.Taxi.Lines = {
    greet        = '무엇을 원하는가?',
    greetHired   = '왔는가. 오늘도 손님이 많을 걸세.',
    greetFaction = '자네는 이미 몸담은 곳이 있지 않은가. 두 집 살림은 안 되네.',

    hired        = '잘 왔네. 오늘부터 자네도 택시기사야.',
    quit         = '언제든 다시 오게.',

    dutyOn       = '나가보게. 무전은 계속 들어올 걸세.',
    dutyOff      = '수고했네. 차는 두고 가게.',

    assignLow    = '당신은 아직 초급 택시기사구만! 지급해줄 차량은 이것뿐일세!',
    assignMid    = '이만하면 손님 태울 만하지. 골라보게.',
    assignHigh   = '자네 정도면 아무 차나 내줘도 되겠어.',
    assignDone   = '기스 내지 말게. 부수면 자네가 무는 거야.',

    needHire     = '일부터 하겠다고 해야 차를 내주지.',
    needDuty     = '출근부터 하게.',
    hasDebt      = '망가뜨린 차값부터 갚게. 그 다음 얘기야.',

    skill        = '경력이 붙을수록 손님이 알아본다네.',
}

Config.Taxi.Hails = {
    { x = 195.0,   y = -933.0,  z = 30.7,  h = 145.0 },
    { x = 298.0,   y = -584.0,  z = 43.3,  h = 70.0  },
    { x = -589.0,  y = -1050.0, z = 22.3,  h = 0.0   },
    { x = 111.0,   y = -1961.0, z = 20.8,  h = 230.0 },
    { x = 290.0,   y = -1780.0, z = 29.4,  h = 200.0 },
    { x = 826.0,   y = -1290.0, z = 28.2,  h = 90.0  },
    { x = 812.0,   y = -2145.0, z = 29.6,  h = 170.0 },
    { x = -248.0,  y = -2010.0, z = 30.1,  h = 265.0 },
    { x = -1223.0, y = -1490.0, z = 4.4,   h = 125.0 },
    { x = -1850.0, y = -1231.0, z = 13.0,  h = 320.0 },
    { x = -722.0,  y = -159.0,  z = 37.0,  h = 205.0 },
    { x = -300.0,  y = 60.0,    z = 92.0,  h = 340.0 },
    { x = 240.0,   y = 370.0,   z = 105.7, h = 160.0 },
    { x = 297.0,   y = 180.0,   z = 104.4, h = 340.0 },
    { x = 1136.0,  y = -654.0,  z = 56.4,  h = 190.0 },
    { x = -1037.0, y = -2737.0, z = 20.2,  h = 330.0 },
    { x = 925.0,   y = 46.0,    z = 80.9,  h = 240.0 },
    { x = -174.0,  y = 502.0,   z = 137.4, h = 190.0 },
    { x = 1961.0,  y = 3740.0,  z = 32.3,  h = 300.0 },
    { x = -137.0,  y = 6377.0,  z = 31.5,  h = 225.0 },
}

Config.Taxi.Destinations = {
    { label = '레전 스퀘어',      x = 195.0,   y = -933.0,  z = 30.7  },
    { label = '필박스 병원',      x = 298.0,   y = -584.0,  z = 43.3  },
    { label = '리틀 서울',        x = -589.0,  y = -1050.0, z = 22.3  },
    { label = '그로브 스트리트',  x = 111.0,   y = -1961.0, z = 20.8  },
    { label = '스트로베리',       x = 290.0,   y = -1780.0, z = 29.4  },
    { label = '라 메사',          x = 826.0,   y = -1290.0, z = 28.2  },
    { label = '사이프러스 플랫츠',x = 812.0,   y = -2145.0, z = 29.6  },
    { label = '메이즈뱅크 아레나',x = -248.0,  y = -2010.0, z = 30.1  },
    { label = '베스푸치 비치',    x = -1223.0, y = -1490.0, z = 4.4   },
    { label = '델 페로 부두',     x = -1850.0, y = -1231.0, z = 13.0  },
    { label = '록포드 힐스',      x = -722.0,  y = -159.0,  z = 37.0  },
    { label = '버튼',             x = -300.0,  y = 60.0,    z = 92.0  },
    { label = '다운타운 바인우드',x = 240.0,   y = 370.0,   z = 105.7 },
    { label = '미러 파크',        x = 1136.0,  y = -654.0,  z = 56.4  },
    { label = 'LS 국제공항',      x = -1037.0, y = -2737.0, z = 20.2  },
    { label = '카지노',           x = 925.0,   y = 46.0,    z = 80.9  },
    { label = '바인우드 힐스',    x = -174.0,  y = 502.0,   z = 137.4 },
    { label = '샌디 쇼어스',      x = 1961.0,  y = 3740.0,  z = 32.3  },
    { label = '팔레토 베이',      x = -137.0,  y = 6377.0,  z = 31.5  },
    { label = '체육관 부두',      x = -1604.0, y = -1017.0, z = 13.0  },
}

Config.Taxi.HailPeds = {
    'a_m_y_business_01', 'a_f_y_business_02', 'a_m_y_hipster_01', 'a_f_y_hipster_01',
    'a_m_m_eastsa_01',   'a_f_m_eastsa_01',   'a_m_y_skater_01',  'a_m_y_stwhi_01',
    'a_f_y_genhot_01',   'a_m_m_business_01',
}

Config.Taxi.HailLines = {
    ride = { '%s로 갑시다.', '%s까지 부탁해요.', '%s요. 좀 서둘러 주세요.' },
    done = { '고맙습니다.', '수고하셨어요.', '잘 왔네요. 감사합니다.' },
}