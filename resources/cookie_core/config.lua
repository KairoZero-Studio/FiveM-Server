Config = {}

Config.debug = false

Config.gobunStart = 1

Config.jobLabels = {
    unemployed = '시민',
    police     = '경찰',
    bcso       = '보안관',
    sasp       = '주경찰',
    ambulance  = '의료',
    realestate = '부동산',
    taxi       = '택시',
    bus        = '버스',
    cardealer  = '딜러',
    mechanic   = '정비',
    judge      = '판사',
    lawyer     = '변호사',
    reporter   = '기자',
    trucker    = '운송',
    tow        = '견인',
    garbage    = '환경미화',
    vineyard   = '농장',
    hotdog     = '노점',
}

Config.defaultJob = 'unemployed'

-- 채팅에서 정부 팩션을 짧게 표시할 때 사용하는 기본 명칭입니다.
-- 팩션에 tag_name이 설정되어 있으면 그 값이 이 설정보다 우선합니다.
Config.factionChatLabels = {
    police      = '경찰',
    security    = '보안',
    corrections = '교정',
    fire        = '소방',
}
Config.hideDefaultJobChip = true

Config.nicknameMin = 2
Config.nicknameMax = 10

Config.bannedNicknames = { '운영자', '관리자', 'admin', 'gm', '시스템', '쿠키서버' }

Config.introDebug = false

Config.verifyEnabled = true
Config.verifyCodeLength = 6
Config.verifyCodeTTL = 10
Config.verifyMaxAttempts = 5
Config.verifyLockSec = 60

Config.discordInvite = 'discord.gg/Gb25mdAyGY'
Config.discordUrl = 'https://discord.gg/Gb25mdAyGY'
Config.discordChannel = '뉴비-인증'

Config.verifyTokenConvar = 'cookie:verifyToken'

function ckLog(tag, msg)
    if not Config.debug then return end

end
