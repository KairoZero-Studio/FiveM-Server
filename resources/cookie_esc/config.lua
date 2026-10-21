

Config = {}

Config.Debug = false

Config.Brand = '쿠키서버'
Config.BrandEn = 'COOKIE KR'

Config.PreviewCam = true

Config.StagePed = vector4(-1600.0, -3100.0, -190.0, 180.0)

Config.Cam = {
    forward = 2.70,
    up      = 1.50,
    aim     = 1.28,
    fov     = 32.0,
}

Config.StagePoses = {}
Config.StageScenario = nil

Config.StageLight = { forward = 0.9, up = 1.5, range = 2.0, front = 2.2, back = 1.2 }

Config.Tabs = {
    { key = 'play',     label = '플레이',   ready = true  },
    { key = 'map',      label = '지도',     ready = true  },
    { key = 'userlist', label = '유저리스트', ready = true  },
    { key = 'event',    label = '이벤트',   ready = true  },
    { key = 'rank',     label = '순위표',   ready = true  },
    { key = 'shop',     label = '상점',     ready = true, badge = 'NEW' },
}

Config.Shortcuts = {
    { title = '쿠키 상점',   desc = 'Tebex·마일리지·게임머니 상점', ready = true, tab = 'shop' },
    { title = '이벤트 진행중',    desc = '이벤트 참여로 보상을 받아가세요',        ready = true, tab = 'event' },
}

Config.Suggest = {
    title = '건의함',
    desc  = '공개적으로 남기기 어려운 의견을 운영진에게 전달하세요',
    ready = true,
}

Config.Notice = {
    image  = '',
    kicker = '쿠키서버',
    title  = '뉴비 인증 도입',
    sub    = '디스코드 인증 후 입장할 수 있습니다',
}

Config.News = {
    { tag = '패치노트', title = '뉴비 인증 시스템 도입',  date = '07.12', body = '디스코드 인증을 통해서만 서버에 입장할 수 있습니다.', image = '' },
    { tag = '패치노트', title = 'ESC 메뉴 개편',          date = '07.12', body = 'ESC 메뉴가 새로 열립니다.', image = '' },
    { tag = '패치노트', title = '차량 HUD 개편',          date = '07.12', body = '속도계, 연료, 안전벨트 표시가 새로워졌습니다.', image = '' },
}

Config.DiscordInvite = 'discord.gg/DTDMfCvFbn'
Config.DiscordUrl = 'https://discord.gg/DTDMfCvFbn'
Config.Homepage = ''

Config.MapComponent = 44

Config.SettingsComponent = 5

Config.JobEmoji = {
    default    = '',
    unemployed = '',
    police     = '👮',
    bcso       = '🛡️',
    sasp       = '🚨',
    ambulance  = '🚑',
    mechanic   = '🔧',
    taxi       = '🚕',
    trucker    = '🚚',
    judge      = '⚖️',
    lawyer     = '⚖️',
    reporter   = '📰',
    realestate = '🏠',
    cardealer  = '🚗',
}

Config.StatusMax = 20
Config.StatusEnabled = true

Config.BlockWhenDead = true

function EscLog(tag, msg)
    if not Config.Debug then return end

end
