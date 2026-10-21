Config = {}

-- =========================================================
-- Discord Developer Portal
-- =========================================================

-- Discord Developer Portal > Applications > General Information > APPLICATION ID
-- 예: '123456789012345678'
Config.ApplicationId = '1543191279976972338'

-- Rich Presence Art Assets에 업로드한 이미지 KEY.
-- 파일명이 아니라 Portal에 표시되는 asset key를 입력.
Config.LargeAsset = 'cookie_logo'
Config.LargeAssetText = '🍪 쿠키서버 | COOKIE SERVER'

-- 선택 사항. 작은 아이콘을 쓰지 않으려면 enabled=false.
Config.SmallAsset = {
    enabled = false,
    key = 'online',
    text = 'COOKIE SERVER 접속 중'
}

-- 버튼은 Discord 정책상 HTTPS URL을 사용.
Config.Buttons = {
    {
        enabled = true,
        label = '🍪 디스코드 접속',
        url = 'https://discord.gg/auQq7pgbKR'
    },
    {
        enabled = false,
        label = '🎮 쿠키서버 접속',
        url = 'https://cfx.re/join/PUT_YOUR_CFX_CODE'
    }
}

-- Discord 상태 갱신 주기.
Config.RefreshMs = 15000

-- 다른 리소스가 Discord Presence를 건드려도 COOKIE SERVER 설정을 다시 적용.
-- Qbox 기본 Rich Presence는 반드시 별도 패치로 disabled 처리하는 것이 권장됨.
Config.ForceReapplyMs = 15000

-- Rich Presence 한 줄.
-- 사용 가능 토큰:
-- {nickname} {activity} {players} {max}
Config.DetailsFormat = '({gobun}) {nickname} | [{players}/{max}]'
Config.StateFormat = '{activity}'

-- 아무 특별 활동이 없을 때 표시.
Config.DefaultActivity = '🍪 쿠키시티 생활 중'

-- 상태 우선순위.
-- 숫자가 높을수록 먼저 표시된다.
Config.ActivityPriority = {
    bank_robbery = 100,
    convenience_robbery = 95,
    emptyhouse_robbery = 90,
    police_duty = 70,
    security_duty = 70,
    faction_duty = 60,
    job = 30,
    default = 0,
}

-- 자동 표시할 팩션 타입 문구.
Config.FactionTypeLabels = {
    police = '🚓 경찰청 · 근무 중',
    security = '🛡️ 보안국 · 근무 중',
}

-- 디버그 출력
Config.Debug = false
