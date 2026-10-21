Config = {}

-- GTA V Sentinel XS
Config.Model = 'sentinel'
Config.DisplayName = '센티널 XS'

sentinel = {
    name = '센티널 XS',
    brand = '',
    model = 'sentinel',
    -- ...
}

-- =========================================================
-- 일반차용 기본 핸들링
-- 속도/가속 단계는 cookie_tuningshop에서 관리하므로
-- 여기서는 DriveForce/MaxFlatVel을 건드리지 않습니다.
-- =========================================================
Config.Handling = {
    -- 차체 무게감 / 충돌 안정성
    fMass = 1700.000000,

    -- 구동
    fDriveBiasFront = 0.000000, -- 0.0 = 후륜, 1.0 = 전륜, 0.5 = AWD

    -- 브레이크
    fBrakeForce = 0.780000,
    fBrakeBiasFront = 0.540000,
    fHandBrakeForce = 0.600000,

    -- 조향
    fSteeringLock = 35.500000,

    -- 접지
    fTractionCurveMax = 2.220000,
    fTractionCurveMin = 2.020000,
    fTractionCurveLateral = 22.300000,
    fTractionSpringDeltaMax = 0.150000,
    fLowSpeedTractionLossMult = 1.050000,
    fTractionBiasFront = 0.490000,
    fTractionLossMult = 1.000000,

    -- 서스펜션
    fSuspensionForce = 2.280000,
    fSuspensionCompDamp = 1.420000,
    fSuspensionReboundDamp = 2.160000,
    fSuspensionUpperLimit = 0.080000,
    fSuspensionLowerLimit = -0.110000,
    fSuspensionRaise = 0.000000,
    fSuspensionBiasFront = 0.510000,

    -- 차체 롤 억제
    fAntiRollBarForce = 1.020000,
    fAntiRollBarBiasFront = 0.550000,
    fRollCentreHeightFront = 0.115000,
    fRollCentreHeightRear = 0.125000,
}

-- true로 켜면 아래 기본 가속값도 이 리소스가 강제로 적용합니다.
-- 현재 COOKIE 튜닝샵이 엔진 0~5단계 가속을 담당하므로 기본 false 권장.
Config.OverrideAcceleration = false

Config.Acceleration = {
    fInitialDriveForce = 0.245000,
    fDriveInertia = 0.920000,
    fClutchChangeRateScaleUpShift = 1.800000,
    fClutchChangeRateScaleDownShift = 1.700000,
}

Config.Debug = false
