Config = {}

Config.Debug = false

-- 기본 FiveM chat 리소스의 일반 채팅을 가로채 칭호를 붙입니다.
-- 이미 별도 커스텀 채팅을 사용하며 메시지가 두 번 보이면 false로 바꾸세요.
Config.InterceptDefaultChat = false

-- 머리 위 칭호
Config.OverheadDistance = 35.0
Config.OverheadRefreshMs = 250
Config.ShowSelfOverhead = false

-- 킬피드
Config.KillfeedDuration = 7000
Config.KillfeedMaxItems = 6

-- 관리자 판정
-- 1) ACE: cookie.identity.admin
-- 2) cookie_admin이 GetAdminLevel export를 제공하면 아래 레벨 이상
Config.AdminAce = 'cookie.identity.admin'
Config.CookieAdminMinLevel = 3

-- 커맨드
Config.UserCommand = 'titles'
Config.AdminCommand = 'cookieidentity'

-- 처음 실행 시 자동으로 만들어지는 기본 카탈로그입니다.
Config.DefaultCatalog = {
    { code = 'chat_admin', type = 'chat_title', label = '관리자', color = '#ff5b5b', style = {} },
    { code = 'chat_staff', type = 'chat_title', label = '스태프', color = '#62a8ff', style = {} },
    { code = 'chat_vip', type = 'chat_title', label = 'VIP', color = '#ffd55b', style = {} },

    { code = 'head_admin', type = 'overhead_title', label = 'ADMIN', color = '#ff5b5b', style = {} },
    { code = 'head_staff', type = 'overhead_title', label = 'STAFF', color = '#62a8ff', style = {} },
    { code = 'head_vip', type = 'overhead_title', label = 'VIP', color = '#ffd55b', style = {} },

    { code = 'feed_default', type = 'killfeed_skin', label = '기본 킬피드', color = '#ffffff', style = { theme = 'default' } },
    { code = 'feed_gold', type = 'killfeed_skin', label = '골드 킬피드', color = '#ffd166', style = { theme = 'gold' } },
    { code = 'feed_pink', type = 'killfeed_skin', label = '핑크 킬피드', color = '#ff8fd8', style = { theme = 'pink' } },
    { code = 'feed_ice', type = 'killfeed_skin', label = '아이스 킬피드', color = '#8de7ff', style = { theme = 'ice' } },
}
