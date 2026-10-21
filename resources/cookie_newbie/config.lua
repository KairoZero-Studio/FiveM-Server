Config = {}

-- 맵이 확정되기 전 테스트용. 나중에 false로 바꾸고 비콘/NPC에서
-- TriggerEvent('cookie_newbie:client:open') 호출하면 됩니다.
Config.EnableTestCommand = false
Config.TestCommand = 'newbiehall'

Config.Title = '뉴비 시청'
Config.EducationTitle = '쿠키서버 기본 교육'
Config.VerifyTitle = '디스코드 뉴비 인증'
Config.RequireDiscordVerify = true
Config.RewardKitItem = 'newbie_reward_kit'
Config.RewardKitLabel = '뉴비 보상 키트'

Config.GuidePages = {
    {
        title = '1. 쿠키서버 생활 시작',
        body = '고정번호와 별명은 서버에서 나를 구분하는 기본 정보입니다. 다른 사람을 존중하며 RP 흐름을 방해하지 않도록 플레이해주세요.'
    },
    {
        title = '2. 도움 받기',
        body = '모르는 기능이 있으면 관리자/뉴비도우미에게 문의하고, 서버 내 안내 UI와 가이드를 먼저 확인해주세요.'
    },
    {
        title = '3. 다음 절차',
        body = '가이드를 확인한 뒤 시청의 뉴비 인증 비콘에서 인증을 완료하면 정상 플레이 권한이 열립니다. 실제 뉴비가이드는 진행 위치를 안내하는 역할입니다.'
    },
}

Config.EducationPages = {
    {
        title = '도로 기본',
        body = '도로에서는 서버 교통 규칙을 지키고, 사고가 나면 상황을 무시하고 이탈하지 않습니다.'
    },
    {
        title = 'RP 기본',
        body = '상대방과의 상황을 존중하고, 시스템 허점을 악용하거나 고의로 진행을 방해하지 않습니다.'
    },
    {
        title = '문제 발생 시',
        body = '버그나 분쟁이 발생하면 증거를 남기고 관리자에게 문의합니다. 직접 보복하거나 악용하지 않습니다.'
    },
}
