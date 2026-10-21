Config = Config or {}

-- 20분간 실제 플레이 활동이 없으면 잠수존으로 자동 이동합니다.
Config.IdleMinutes = 20

-- 메인광장의 잠수존 이동 비콘.
Config.MainPortal = vec4(196.80, -934.20, 30.69, 144.0)

-- 잠수존은 별도 라우팅 버킷에서 운용됩니다.
-- 좌표를 바꾸고 싶으면 아래 두 좌표만 바꾸면 됩니다.
Config.AfkSpawn = vec4(-1604.90, -1049.40, 13.02, 320.0)
Config.AfkReturnPortal = vec3(-1601.35, -1046.55, 13.02)
Config.AfkZoneRadius = 42.0
Config.RoutingBucket = 7777

Config.PortalDrawDistance = 28.0
Config.PortalInteractDistance = 2.1
Config.NeedsKeepIntervalMs = 2000
Config.ActivityMoveDistance = 0.55
Config.ActivityHeadingDegrees = 4.0
