Config = {}

Config.InteractMaxSpeed = 3.0
Config.ApplyCheckMs = 1200
Config.SessionSeconds = 600

-- 아주 작은 손상도 있으면 먼저 전체 수리를 해야 튜닝 가능.
Config.RepairHealthThreshold = 999.0
Config.FullRepairPrice = 300000

Config.MaxEngineLevel = 5
Config.MaxSpeedLevel = 5
Config.MaxBrakeLevel = 5
Config.MaxDurabilityLevel = 5
Config.MaxSuspensionLevel = 5
Config.MaxTransmissionLevel = 5

Config.SpeedMultipliers = {
    [0] = 1.00,
    [1] = 1.03,
    [2] = 1.06,
    [3] = 1.10,
    [4] = 1.14,
    [5] = 1.19,
}

-- =========================================================
-- 차량별 COOKIE 성능 프로필
-- speedLevel : 튜닝샵 '속도 강화' 0~5단계
-- engineLevel: 튜닝샵 '엔진 강화' 0~5단계
-- 등록되지 않은 차량은 기존 SpeedMultipliers 방식 그대로 사용.
-- =========================================================
Config.VehiclePerformanceProfiles = {
    -- =====================================================
    -- 뉴비 차량
    -- 일반차 상급보다 살짝 좋은 체감.
    -- 최고속도는 한정차 영역을 침범하지 않도록 230km/h 제한.
    -- =====================================================
    noobles = {
        label = 'noobles',
        class = 'newbie',

        speeds = {
            [0] = 205.0,
            [1] = 210.0,
            [2] = 215.0,
            [3] = 220.0,
            [4] = 225.0,
            [5] = 230.0,
        },

        driveForce = {
            [0] = 0.330,
            [1] = 0.345,
            [2] = 0.360,
            [3] = 0.376,
            [4] = 0.392,
            [5] = 0.410,
        },

        driveInertia = {
            [0] = 1.050,
            [1] = 1.075,
            [2] = 1.100,
            [3] = 1.125,
            [4] = 1.150,
            [5] = 1.180,
        },

        clutchUp = {
            [0] = 2.40,
            [1] = 2.55,
            [2] = 2.70,
            [3] = 2.85,
            [4] = 3.05,
            [5] = 3.25,
        },

        clutchDown = {
            [0] = 2.20,
            [1] = 2.35,
            [2] = 2.50,
            [3] = 2.65,
            [4] = 2.85,
            [5] = 3.05,
        },

        -- 순정부터 적용되는 주행 성능.
        baseHandling = {
            fDriveBiasFront = 0.350,
            fBrakeForce = 1.050,
            fBrakeBiasFront = 0.550,
            fHandBrakeForce = 0.700,

            fSteeringLock = 38.000,
            fTractionCurveMax = 2.780,
            fTractionCurveMin = 2.600,
            fTractionCurveLateral = 22.500,
            fTractionSpringDeltaMax = 0.130,
            fLowSpeedTractionLossMult = 0.780,
            fTractionBiasFront = 0.495,
            fTractionLossMult = 0.900,

            fSuspensionForce = 2.450,
            fSuspensionCompDamp = 1.500,
            fSuspensionReboundDamp = 2.250,
            fSuspensionUpperLimit = 0.080,
            fSuspensionLowerLimit = -0.110,
            fSuspensionBiasFront = 0.510,

            fAntiRollBarForce = 1.000,
            fAntiRollBarBiasFront = 0.530,
            fRollCentreHeightFront = 0.130,
            fRollCentreHeightRear = 0.140,

            fCollisionDamageMult = 0.880,
            fDeformationDamageMult = 0.800,
            fEngineDamageMult = 0.900,
        },
    },

    -- =====================================================
    -- 한정 차량: 이클립스
    -- 속도 단계는 기존 180~280 유지.
    -- 가속/브레이크/접지/고속 코너링을 대폭 상향.
    -- =====================================================
    eclipse = {
        label = '이클립스',
        class = 'limited',

        speeds = {
            [0] = 180.0,
            [1] = 200.0,
            [2] = 220.0,
            [3] = 240.0,
            [4] = 260.0,
            [5] = 280.0,
        },

        driveForce = {
            [0] = 0.390,
            [1] = 0.415,
            [2] = 0.442,
            [3] = 0.470,
            [4] = 0.500,
            [5] = 0.535,
        },

        driveInertia = {
            [0] = 1.120,
            [1] = 1.160,
            [2] = 1.200,
            [3] = 1.240,
            [4] = 1.280,
            [5] = 1.320,
        },

        clutchUp = {
            [0] = 3.10,
            [1] = 3.35,
            [2] = 3.60,
            [3] = 3.85,
            [4] = 4.15,
            [5] = 4.45,
        },

        clutchDown = {
            [0] = 2.90,
            [1] = 3.10,
            [2] = 3.30,
            [3] = 3.50,
            [4] = 3.75,
            [5] = 4.00,
        },

        baseHandling = {
            fDriveBiasFront = 0.450,
            fBrakeForce = 1.220,
            fBrakeBiasFront = 0.550,
            fHandBrakeForce = 0.780,

            fSteeringLock = 40.000,
            fTractionCurveMax = 3.180,
            fTractionCurveMin = 2.980,
            fTractionCurveLateral = 23.000,
            fTractionSpringDeltaMax = 0.120,
            fLowSpeedTractionLossMult = 0.660,
            fTractionBiasFront = 0.495,
            fTractionLossMult = 0.820,

            fSuspensionForce = 2.800,
            fSuspensionCompDamp = 1.750,
            fSuspensionReboundDamp = 2.600,
            fSuspensionUpperLimit = 0.070,
            fSuspensionLowerLimit = -0.100,
            fSuspensionBiasFront = 0.510,

            fAntiRollBarForce = 1.220,
            fAntiRollBarBiasFront = 0.540,
            fRollCentreHeightFront = 0.145,
            fRollCentreHeightRear = 0.155,

            fCollisionDamageMult = 0.780,
            fDeformationDamageMult = 0.650,
            fEngineDamageMult = 0.800,
        },
    },

    -- =====================================================
    -- 한정 차량: 크라운
    -- 이클립스와 동일한 강화 성능.
    -- =====================================================
    crown = {
        label = '크라운',
        class = 'limited',

        speeds = {
            [0] = 180.0,
            [1] = 200.0,
            [2] = 220.0,
            [3] = 240.0,
            [4] = 260.0,
            [5] = 280.0,
        },

        driveForce = {
            [0] = 0.390,
            [1] = 0.415,
            [2] = 0.442,
            [3] = 0.470,
            [4] = 0.500,
            [5] = 0.535,
        },

        driveInertia = {
            [0] = 1.120,
            [1] = 1.160,
            [2] = 1.200,
            [3] = 1.240,
            [4] = 1.280,
            [5] = 1.320,
        },

        clutchUp = {
            [0] = 3.10,
            [1] = 3.35,
            [2] = 3.60,
            [3] = 3.85,
            [4] = 4.15,
            [5] = 4.45,
        },

        clutchDown = {
            [0] = 2.90,
            [1] = 3.10,
            [2] = 3.30,
            [3] = 3.50,
            [4] = 3.75,
            [5] = 4.00,
        },

        baseHandling = {
            fDriveBiasFront = 0.450,
            fBrakeForce = 1.220,
            fBrakeBiasFront = 0.550,
            fHandBrakeForce = 0.780,

            fSteeringLock = 40.000,
            fTractionCurveMax = 3.180,
            fTractionCurveMin = 2.980,
            fTractionCurveLateral = 23.000,
            fTractionSpringDeltaMax = 0.120,
            fLowSpeedTractionLossMult = 0.660,
            fTractionBiasFront = 0.495,
            fTractionLossMult = 0.820,

            fSuspensionForce = 2.800,
            fSuspensionCompDamp = 1.750,
            fSuspensionReboundDamp = 2.600,
            fSuspensionUpperLimit = 0.070,
            fSuspensionLowerLimit = -0.100,
            fSuspensionBiasFront = 0.510,

            fAntiRollBarForce = 1.220,
            fAntiRollBarBiasFront = 0.540,
            fRollCentreHeightFront = 0.145,
            fRollCentreHeightRear = 0.155,

            fCollisionDamageMult = 0.780,
            fDeformationDamageMult = 0.650,
            fEngineDamageMult = 0.800,
        },
    },
    -- =====================================================
    -- 일반 차량: 스태포드
    -- 클래식 대형 고급 세단 / 묵직하고 안정적인 후륜구동
    -- =====================================================
    stafford = {
        label = '스태포드',
        class = 'normal',

        speeds = {
            [0] = 185.0,
            [1] = 190.0,
            [2] = 195.0,
            [3] = 200.0,
            [4] = 205.0,
            [5] = 210.0,
        },

        driveForce = {
            [0] = 0.285,
            [1] = 0.298,
            [2] = 0.312,
            [3] = 0.326,
            [4] = 0.340,
            [5] = 0.355,
        },

        driveInertia = {
            [0] = 0.980,
            [1] = 1.000,
            [2] = 1.020,
            [3] = 1.045,
            [4] = 1.070,
            [5] = 1.100,
        },

        clutchUp = {
            [0] = 2.10,
            [1] = 2.25,
            [2] = 2.40,
            [3] = 2.55,
            [4] = 2.70,
            [5] = 2.90,
        },

        clutchDown = {
            [0] = 1.95,
            [1] = 2.10,
            [2] = 2.25,
            [3] = 2.40,
            [4] = 2.55,
            [5] = 2.75,
        },

        baseHandling = {
            fDriveBiasFront = 0.000,

            fBrakeForce = 0.980,
            fBrakeBiasFront = 0.570,
            fHandBrakeForce = 0.650,

            fSteeringLock = 35.000,

            fTractionCurveMax = 2.580,
            fTractionCurveMin = 2.400,
            fTractionCurveLateral = 22.000,
            fTractionSpringDeltaMax = 0.140,
            fLowSpeedTractionLossMult = 0.850,
            fTractionBiasFront = 0.490,
            fTractionLossMult = 0.950,

            fSuspensionForce = 2.250,
            fSuspensionCompDamp = 1.350,
            fSuspensionReboundDamp = 2.000,
            fSuspensionUpperLimit = 0.100,
            fSuspensionLowerLimit = -0.125,
            fSuspensionBiasFront = 0.520,

            fAntiRollBarForce = 0.880,
            fAntiRollBarBiasFront = 0.540,
            fRollCentreHeightFront = 0.120,
            fRollCentreHeightRear = 0.130,

            fCollisionDamageMult = 0.850,
            fDeformationDamageMult = 0.780,
            fEngineDamageMult = 0.900,
        },
    },

    -- =====================================================
    -- 일반 차량: 스트레치
    -- 대형 리무진 / 긴 휠베이스 / 안정형 후륜구동
    -- =====================================================
    stretch = {
        label = '스트레치',
        class = 'normal',

        speeds = {
            [0] = 175.0,
            [1] = 180.0,
            [2] = 185.0,
            [3] = 190.0,
            [4] = 195.0,
            [5] = 200.0,
        },

        driveForce = {
            [0] = 0.265,
            [1] = 0.278,
            [2] = 0.291,
            [3] = 0.305,
            [4] = 0.319,
            [5] = 0.335,
        },

        driveInertia = {
            [0] = 0.940,
            [1] = 0.960,
            [2] = 0.980,
            [3] = 1.000,
            [4] = 1.025,
            [5] = 1.050,
        },

        clutchUp = {
            [0] = 1.95,
            [1] = 2.10,
            [2] = 2.25,
            [3] = 2.40,
            [4] = 2.55,
            [5] = 2.75,
        },

        clutchDown = {
            [0] = 1.80,
            [1] = 1.95,
            [2] = 2.10,
            [3] = 2.25,
            [4] = 2.40,
            [5] = 2.60,
        },

        baseHandling = {
            fDriveBiasFront = 0.000,

            fBrakeForce = 0.960,
            fBrakeBiasFront = 0.585,
            fHandBrakeForce = 0.600,

            fSteeringLock = 32.500,

            fTractionCurveMax = 2.500,
            fTractionCurveMin = 2.320,
            fTractionCurveLateral = 21.500,
            fTractionSpringDeltaMax = 0.145,
            fLowSpeedTractionLossMult = 0.900,
            fTractionBiasFront = 0.490,
            fTractionLossMult = 0.980,

            fSuspensionForce = 2.150,
            fSuspensionCompDamp = 1.250,
            fSuspensionReboundDamp = 1.900,
            fSuspensionUpperLimit = 0.105,
            fSuspensionLowerLimit = -0.130,
            fSuspensionBiasFront = 0.530,

            fAntiRollBarForce = 0.820,
            fAntiRollBarBiasFront = 0.550,
            fRollCentreHeightFront = 0.115,
            fRollCentreHeightRear = 0.125,

            fCollisionDamageMult = 0.820,
            fDeformationDamageMult = 0.760,
            fEngineDamageMult = 0.900,
        },
    },

    -- =====================================================
    -- 일반 차량: 아스보
    -- 소형 해치백 / 전륜구동 / 경쾌한 초반 가속
    -- =====================================================
    asbo = {
        label = '아스보',
        class = 'normal',

        speeds = {
            [0] = 180.0,
            [1] = 185.0,
            [2] = 190.0,
            [3] = 195.0,
            [4] = 200.0,
            [5] = 205.0,
        },

        driveForce = {
            [0] = 0.295,
            [1] = 0.308,
            [2] = 0.322,
            [3] = 0.337,
            [4] = 0.352,
            [5] = 0.368,
        },

        driveInertia = {
            [0] = 1.020,
            [1] = 1.040,
            [2] = 1.060,
            [3] = 1.080,
            [4] = 1.105,
            [5] = 1.130,
        },

        clutchUp = {
            [0] = 2.25,
            [1] = 2.40,
            [2] = 2.55,
            [3] = 2.70,
            [4] = 2.85,
            [5] = 3.05,
        },

        clutchDown = {
            [0] = 2.05,
            [1] = 2.20,
            [2] = 2.35,
            [3] = 2.50,
            [4] = 2.65,
            [5] = 2.85,
        },

        baseHandling = {
            fDriveBiasFront = 1.000,

            fBrakeForce = 1.020,
            fBrakeBiasFront = 0.600,
            fHandBrakeForce = 0.680,

            fSteeringLock = 40.000,

            fTractionCurveMax = 2.620,
            fTractionCurveMin = 2.440,
            fTractionCurveLateral = 22.500,
            fTractionSpringDeltaMax = 0.135,
            fLowSpeedTractionLossMult = 0.760,
            fTractionBiasFront = 0.505,
            fTractionLossMult = 0.920,

            fSuspensionForce = 2.400,
            fSuspensionCompDamp = 1.450,
            fSuspensionReboundDamp = 2.150,
            fSuspensionUpperLimit = 0.085,
            fSuspensionLowerLimit = -0.110,
            fSuspensionBiasFront = 0.540,

            fAntiRollBarForce = 1.000,
            fAntiRollBarBiasFront = 0.560,
            fRollCentreHeightFront = 0.125,
            fRollCentreHeightRear = 0.135,

            fCollisionDamageMult = 0.950,
            fDeformationDamageMult = 0.900,
            fEngineDamageMult = 0.950,
        },
    },

    -- =====================================================
    -- 일반 차량: 칸조
    -- 소형 스포츠 해치백 / 전륜구동 / 민첩한 튜닝카
    -- =====================================================
    kanjo = {
        label = '칸조',
        class = 'normal',

        speeds = {
            [0] = 185.0,
            [1] = 190.0,
            [2] = 195.0,
            [3] = 200.0,
            [4] = 210.0,
            [5] = 220.0,
        },

        driveForce = {
            [0] = 0.320,
            [1] = 0.337,
            [2] = 0.355,
            [3] = 0.374,
            [4] = 0.394,
            [5] = 0.415,
        },

        driveInertia = {
            [0] = 1.060,
            [1] = 1.085,
            [2] = 1.110,
            [3] = 1.135,
            [4] = 1.165,
            [5] = 1.195,
        },

        clutchUp = {
            [0] = 2.50,
            [1] = 2.65,
            [2] = 2.80,
            [3] = 2.95,
            [4] = 3.15,
            [5] = 3.35,
        },

        clutchDown = {
            [0] = 2.30,
            [1] = 2.45,
            [2] = 2.60,
            [3] = 2.75,
            [4] = 2.95,
            [5] = 3.15,
        },

        baseHandling = {
            fDriveBiasFront = 1.000,

            fBrakeForce = 1.080,
            fBrakeBiasFront = 0.600,
            fHandBrakeForce = 0.720,

            fSteeringLock = 41.000,

            fTractionCurveMax = 2.780,
            fTractionCurveMin = 2.580,
            fTractionCurveLateral = 22.800,
            fTractionSpringDeltaMax = 0.130,
            fLowSpeedTractionLossMult = 0.720,
            fTractionBiasFront = 0.503,
            fTractionLossMult = 0.880,

            fSuspensionForce = 2.550,
            fSuspensionCompDamp = 1.600,
            fSuspensionReboundDamp = 2.350,
            fSuspensionUpperLimit = 0.075,
            fSuspensionLowerLimit = -0.100,
            fSuspensionBiasFront = 0.540,

            fAntiRollBarForce = 1.100,
            fAntiRollBarBiasFront = 0.560,
            fRollCentreHeightFront = 0.135,
            fRollCentreHeightRear = 0.145,

            fCollisionDamageMult = 0.920,
            fDeformationDamageMult = 0.850,
            fEngineDamageMult = 0.920,
        },
    },


    -- 일반 차량: 브리오소 R/A
    brioso = {
        label = '브리오소 R/A',
        class = 'normal',
        speeds = {
            [0] = 180.0, [1] = 183.0, [2] = 186.0,
            [3] = 189.0, [4] = 192.0, [5] = 195.0,
        },
        driveForce = {
            [0] = 0.275, [1] = 0.286, [2] = 0.297,
            [3] = 0.309, [4] = 0.321, [5] = 0.334,
        },
        driveInertia = {
            [0] = 1.000, [1] = 1.018, [2] = 1.036,
            [3] = 1.054, [4] = 1.075, [5] = 1.095,
        },
        clutchUp = {
            [0] = 2.10, [1] = 2.22, [2] = 2.34,
            [3] = 2.46, [4] = 2.60, [5] = 2.75,
        },
        clutchDown = {
            [0] = 1.95, [1] = 2.07, [2] = 2.19,
            [3] = 2.31, [4] = 2.45, [5] = 2.60,
        },
        baseHandling = {
            fDriveBiasFront = 1.000,
            fBrakeForce = 0.950,
            fBrakeBiasFront = 0.610,
            fHandBrakeForce = 0.650,
            fSteeringLock = 41.500,
            fTractionCurveMax = 2.450,
            fTractionCurveMin = 2.280,
            fTractionCurveLateral = 22.200,
            fTractionSpringDeltaMax = 0.140,
            fLowSpeedTractionLossMult = 0.820,
            fTractionBiasFront = 0.507,
            fTractionLossMult = 0.960,
            fSuspensionForce = 2.300,
            fSuspensionCompDamp = 1.350,
            fSuspensionReboundDamp = 2.000,
            fSuspensionUpperLimit = 0.090,
            fSuspensionLowerLimit = -0.115,
            fSuspensionBiasFront = 0.550,
            fAntiRollBarForce = 0.920,
            fAntiRollBarBiasFront = 0.570,
            fRollCentreHeightFront = 0.120,
            fRollCentreHeightRear = 0.130,
            fCollisionDamageMult = 1.000,
            fDeformationDamageMult = 0.950,
            fEngineDamageMult = 1.000,
        },
    },


    -- =====================================================
    -- 한정 차량: 벤토
    -- 벤츠계 고급 스포츠 세단 / 40:60 AWD
    -- =====================================================
    vento = {
        label = '벤토',
        class = 'limited',

        speeds = {
            [0] = 200.0,
            [1] = 220.0,
            [2] = 240.0,
            [3] = 255.0,
            [4] = 275.0,
            [5] = 295.0,
        },

        driveForce = {
            [0] = 0.380,
            [1] = 0.405,
            [2] = 0.432,
            [3] = 0.460,
            [4] = 0.490,
            [5] = 0.525,
        },

        driveInertia = {
            [0] = 1.100,
            [1] = 1.135,
            [2] = 1.170,
            [3] = 1.205,
            [4] = 1.245,
            [5] = 1.290,
        },

        clutchUp = {
            [0] = 3.00,
            [1] = 3.25,
            [2] = 3.50,
            [3] = 3.75,
            [4] = 4.00,
            [5] = 4.30,
        },

        clutchDown = {
            [0] = 2.80,
            [1] = 3.00,
            [2] = 3.20,
            [3] = 3.40,
            [4] = 3.65,
            [5] = 3.90,
        },

        baseHandling = {
            fDriveBiasFront = 0.400,

            fBrakeForce = 1.180,
            fBrakeBiasFront = 0.555,
            fHandBrakeForce = 0.750,

            fSteeringLock = 39.000,

            fTractionCurveMax = 3.050,
            fTractionCurveMin = 2.850,
            fTractionCurveLateral = 22.900,
            fTractionSpringDeltaMax = 0.120,
            fLowSpeedTractionLossMult = 0.680,
            fTractionBiasFront = 0.497,
            fTractionLossMult = 0.840,

            fSuspensionForce = 2.700,
            fSuspensionCompDamp = 1.650,
            fSuspensionReboundDamp = 2.450,
            fSuspensionUpperLimit = 0.075,
            fSuspensionLowerLimit = -0.105,
            fSuspensionBiasFront = 0.515,

            fAntiRollBarForce = 1.150,
            fAntiRollBarBiasFront = 0.535,
            fRollCentreHeightFront = 0.140,
            fRollCentreHeightRear = 0.150,

            fCollisionDamageMult = 0.800,
            fDeformationDamageMult = 0.680,
            fEngineDamageMult = 0.820,
        },
    },

    -- =====================================================
    -- 일반 차량: 브리오소 헨토
    -- Brioso 300 기반 / 클래식 소형차 / RWD
    -- =====================================================
    brioso2 = {
        label = '브리오소 헨토',
        class = 'normal',

        speeds = {
            [0] = 185.0,
            [1] = 189.0,
            [2] = 193.0,
            [3] = 197.0,
            [4] = 201.0,
            [5] = 205.0,
        },

        driveForce = {
            [0] = 0.285,
            [1] = 0.298,
            [2] = 0.311,
            [3] = 0.325,
            [4] = 0.339,
            [5] = 0.354,
        },

        driveInertia = {
            [0] = 1.020,
            [1] = 1.040,
            [2] = 1.060,
            [3] = 1.080,
            [4] = 1.102,
            [5] = 1.125,
        },

        clutchUp = {
            [0] = 2.15,
            [1] = 2.28,
            [2] = 2.41,
            [3] = 2.54,
            [4] = 2.68,
            [5] = 2.83,
        },

        clutchDown = {
            [0] = 2.00,
            [1] = 2.12,
            [2] = 2.24,
            [3] = 2.36,
            [4] = 2.49,
            [5] = 2.63,
        },

        baseHandling = {
            fDriveBiasFront = 0.000,

            fBrakeForce = 0.980,
            fBrakeBiasFront = 0.590,
            fHandBrakeForce = 0.700,

            fSteeringLock = 40.500,

            fTractionCurveMax = 2.520,
            fTractionCurveMin = 2.340,
            fTractionCurveLateral = 22.300,
            fTractionSpringDeltaMax = 0.135,
            fLowSpeedTractionLossMult = 0.780,
            fTractionBiasFront = 0.492,
            fTractionLossMult = 0.920,

            fSuspensionForce = 2.350,
            fSuspensionCompDamp = 1.400,
            fSuspensionReboundDamp = 2.050,
            fSuspensionUpperLimit = 0.095,
            fSuspensionLowerLimit = -0.115,
            fSuspensionBiasFront = 0.505,

            fAntiRollBarForce = 0.950,
            fAntiRollBarBiasFront = 0.510,
            fRollCentreHeightFront = 0.120,
            fRollCentreHeightRear = 0.125,

            fCollisionDamageMult = 1.000,
            fDeformationDamageMult = 0.920,
            fEngineDamageMult = 0.980,
        },
    },

    -- =====================================================
    -- 일반 차량 1티어: 플래그십
    -- 일반차 최상급 / AWD 35:65 / 8단
    -- =====================================================
    plagship = {
        label = '플래그십',
        class = 'normal',

        speeds = {
            [0] = 200.0,
            [1] = 204.0,
            [2] = 208.0,
            [3] = 212.0,
            [4] = 216.0,
            [5] = 220.0,
        },

        driveForce = {
            [0] = 0.345,
            [1] = 0.360,
            [2] = 0.376,
            [3] = 0.393,
            [4] = 0.411,
            [5] = 0.430,
        },

        driveInertia = {
            [0] = 1.075,
            [1] = 1.095,
            [2] = 1.115,
            [3] = 1.138,
            [4] = 1.162,
            [5] = 1.188,
        },

        clutchUp = {
            [0] = 2.70,
            [1] = 2.85,
            [2] = 3.00,
            [3] = 3.15,
            [4] = 3.32,
            [5] = 3.50,
        },

        clutchDown = {
            [0] = 2.50,
            [1] = 2.65,
            [2] = 2.80,
            [3] = 2.95,
            [4] = 3.10,
            [5] = 3.28,
        },

        baseHandling = {
            fDriveBiasFront = 0.350,
            fBrakeForce = 1.120,
            fBrakeBiasFront = 0.560,
            fHandBrakeForce = 0.740,
            fSteeringLock = 38.500,

            fTractionCurveMax = 2.950,
            fTractionCurveMin = 2.750,
            fTractionCurveLateral = 22.800,
            fTractionSpringDeltaMax = 0.120,
            fLowSpeedTractionLossMult = 0.700,
            fTractionBiasFront = 0.497,
            fTractionLossMult = 0.850,

            fSuspensionForce = 2.650,
            fSuspensionCompDamp = 1.580,
            fSuspensionReboundDamp = 2.350,
            fSuspensionUpperLimit = 0.080,
            fSuspensionLowerLimit = -0.105,
            fSuspensionBiasFront = 0.515,

            fAntiRollBarForce = 1.100,
            fAntiRollBarBiasFront = 0.530,
            fRollCentreHeightFront = 0.140,
            fRollCentreHeightRear = 0.150,

            fCollisionDamageMult = 0.850,
            fDeformationDamageMult = 0.740,
            fEngineDamageMult = 0.850,
        },
    },
}


-- COOKIE ALL VEHICLE TUNING V3: models not explicitly profiled use sensible class caps.
-- Base game / unnamed vehicles remain tunable with the generic multiplier.
Config.TuneVehicleTier = {
    odin = 'five',
    noobles = 'newbie',
    eclipse = 'limited',
    crown = 'limited',
    crossout = 'limited',
    vesper = 'limited',
    vento = 'normal',
    asbo = 'normal',
    brioso = 'normal',
    brioso2 = 'normal',
    kanjo = 'normal',
    stafford = 'normal',
    stretch = 'normal',
 }
Config.TuneTierTopSpeed = { normal = 220.0, newbie = 230.0, limited = 340.0, war = 400.0, five = 480.0 }
-- An entry is a physical upper bound in km/h; existing individual profiles retain their own speed curves.
Config.GenericTuneDriveForceGain = 0.18 -- max 18% stronger acceleration than stock at engine 5
Config.GenericTuneBrakeGain = 0.20 -- max 20% stronger braking at brake 5
Config.GenericTuneTractionGain = 0.08 -- max 8% tire grip improvement at max suspension

Config.DurabilityReduction = {
    [0] = 0.00,
    [1] = 0.10,
    [2] = 0.20,
    [3] = 0.32,
    [4] = 0.45,
    [5] = 0.60,
}

Config.PaymentOrder = { 'bank', 'cash' }

-- 서버에서 최종 재계산.
Config.Prices = {
    primaryColor = 150000,
    secondaryColor = 120000,
    specialPaint = 450000,
    wheelColor = 80000,
    windowTint = 120000,
    interiorColor = 150000,

    enginePerLevel = 600000,
    speedPerLevel = 850000,
    durabilityPerLevel = 750000,
    brakePerLevel = 450000,
    suspensionPerLevel = 300000,
    transmissionPerLevel = 500000,
    turbo = 1200000,

    bulletproofTyres = 900000,
    horn = 80000,
    xenon = 250000,
    engineAudio = 700000,

    extrasEach = 50000,
    plateStyle = 100000,
    neon = 350000,
    wheelModel = 350000,
    tyreSmokeColor = 100000,

    frontBumper = 200000,
    rearBumper = 200000,
    roof = 200000,
    exhaust = 200000,
}

-- 일반 RGB와 별도로 고르는 COOKIE 특수 페인트.
-- 원하는 색은 자유롭게 계속 추가 가능.
Config.SpecialPaints = {
    { key='none', label='사용 안 함' },

    { key='carbon_black', label='카본 블랙', rgb={12,12,15} },
    { key='obsidian', label='옵시디언', rgb={21,18,26} },
    { key='graphite', label='그래파이트', rgb={45,49,55} },
    { key='gunmetal', label='건메탈', rgb={67,72,79} },
    { key='titanium', label='티타늄 실버', rgb={133,139,145} },
    { key='frozen_silver', label='프로즌 실버', rgb={188,192,197} },
    { key='pearl_white', label='펄 화이트', rgb={242,242,245} },
    { key='ivory', label='아이보리', rgb={238,230,208} },

    { key='candy_red', label='캔디 레드', rgb={205,0,26} },
    { key='crimson', label='크림슨', rgb={142,7,31} },
    { key='wine_red', label='와인 레드', rgb={82,16,33} },
    { key='lava_red', label='라바 레드', rgb={237,42,26} },
    { key='rose', label='로즈', rgb={220,72,112} },
    { key='hot_pink', label='핫 핑크', rgb={255,37,142} },
    { key='rose_gold', label='로즈 골드', rgb={183,110,121} },

    { key='tangerine', label='탠저린', rgb={244,100,21} },
    { key='sunset_orange', label='선셋 오렌지', rgb={227,73,25} },
    { key='champagne', label='샴페인', rgb={205,181,131} },
    { key='gold', label='골드', rgb={205,164,52} },
    { key='lemon', label='레몬 옐로우', rgb={243,226,35} },

    { key='lime', label='라임', rgb={99,205,35} },
    { key='emerald', label='에메랄드', rgb={16,145,93} },
    { key='forest', label='포레스트', rgb={24,75,47} },
    { key='mint', label='민트', rgb={92,220,184} },

    { key='ice_blue', label='아이스 블루', rgb={116,210,255} },
    { key='sky_blue', label='스카이 블루', rgb={65,170,234} },
    { key='electric_blue', label='일렉트릭 블루', rgb={21,105,255} },
    { key='royal_blue', label='로열 블루', rgb={31,54,168} },
    { key='navy', label='네이비', rgb={16,28,74} },
    { key='turquoise', label='터콰이즈', rgb={31,191,193} },
    { key='teal', label='틸', rgb={14,108,117} },

    { key='midnight_purple', label='미드나잇 퍼플', rgb={54,26,84} },
    { key='violet', label='바이올렛', rgb={111,43,178} },
    { key='lavender', label='라벤더', rgb={174,141,212} },

    { key='bronze', label='브론즈', rgb={145,97,49} },
    { key='copper', label='코퍼', rgb={184,92,56} },
    { key='mocha', label='모카', rgb={91,66,54} },
}

Config.WheelColors = {
    { id=0, label='블랙' },
    { id=1, label='그래파이트' },
    { id=4, label='실버' },
    { id=111, label='화이트' },
    { id=27, label='레드' },
    { id=32, label='다크 레드' },
    { id=55, label='그린' },
    { id=64, label='블루' },
    { id=73, label='울트라 블루' },
    { id=88, label='옐로우' },
    { id=135, label='핑크' },
    { id=137, label='핫 핑크' },
    { id=37, label='골드' },
    { id=90, label='브론즈' },
    { id=120, label='크롬' },
}

-- GTA 썬팅 프리셋. %는 UI용 체감 표기.
Config.WindowTints = {
    { id=4, label='순정 / 0%' },
    { id=3, label='연함 / 약 20%' },
    { id=0, label='중간 / 약 35%' },
    { id=2, label='진함 / 약 50%' },
    { id=5, label='리무진 / 약 90%' },
    { id=1, label='완전 검정 / 100%' },
    { id=6, label='그린 틴트' },
}

Config.XenonColors = {
    { id=0, label='화이트' },
    { id=1, label='블루' },
    { id=2, label='일렉트릭 블루' },
    { id=3, label='민트' },
    { id=4, label='라임' },
    { id=5, label='옐로우' },
    { id=6, label='골드' },
    { id=7, label='오렌지' },
    { id=8, label='레드' },
    { id=9, label='핑크' },
    { id=10, label='핫 핑크' },
    { id=11, label='퍼플' },
    { id=12, label='블랙라이트' },
}

Config.PlateStyles = {
    { id=0, label='화이트 / 블루 1' },
    { id=1, label='블랙 / 옐로우' },
    { id=2, label='블루 / 옐로우' },
    { id=3, label='화이트 / 블루 2' },
    { id=4, label='화이트 / 블루 3' },
    { id=5, label='노스 양크턴' },
}

Config.WheelTypes = {
    { id=0, label='스포츠' },
    { id=1, label='머슬' },
    { id=2, label='로우라이더' },
    { id=3, label='SUV' },
    { id=4, label='오프로드' },
    { id=5, label='튜너' },
    { id=6, label='바이크' },
    { id=7, label='하이엔드' },
    { id=8, label='베니스 오리지널' },
    { id=9, label='베니스 비스포크' },
    { id=10, label='오픈휠' },
    { id=11, label='스트리트' },
    { id=12, label='트랙' },
}

Config.InteriorColors = {
    { id=0, label='블랙' },
    { id=1, label='그래파이트' },
    { id=3, label='다크 실버' },
    { id=5, label='블루 실버' },
    { id=27, label='레드' },
    { id=31, label='다크 레드' },
    { id=32, label='가넷 레드' },
    { id=37, label='골드' },
    { id=55, label='그린' },
    { id=64, label='블루' },
    { id=73, label='울트라 블루' },
    { id=88, label='옐로우' },
    { id=107, label='크림' },
    { id=111, label='화이트' },
    { id=135, label='핑크' },
    { id=137, label='핫 핑크' },
    { id=145, label='퍼플' },
}

-- ForceVehicleEngineAudio에서 사용할 안전한 기본 GTA 차량 사운드셋.
Config.EngineAudios = {
    { key='stock', label='순정 배기음' },
    { key='ADDER', label='Exotic V12 · Adder' },
    { key='T20', label='Exotic Hybrid · T20' },
    { key='ZENTORNO', label='Exotic V12 · Zentorno' },
    { key='XA21', label='Exotic V8 · XA-21' },
    { key='ITALIGTO', label='GT · Itali GTO' },
    { key='COMET2', label='Sport Flat · Comet' },
    { key='FELTZER2', label='Euro Sport · Feltzer' },
    { key='BANSHEE', label='Sport V8 · Banshee' },
    { key='JESTER', label='JDM Sport · Jester' },
    { key='SULTANRS', label='JDM Turbo · Sultan RS' },
    { key='ELEGY', label='JDM Turbo · Elegy' },
    { key='KURUMA', label='JDM · Kuruma' },
    { key='DOMINATOR', label='Muscle V8 · Dominator' },
    { key='GAUNTLET', label='Muscle V8 · Gauntlet' },
    { key='BUFFALO', label='American V8 · Buffalo' },
    { key='SCHAFTER3', label='Luxury V8 · Schafter' },
}
