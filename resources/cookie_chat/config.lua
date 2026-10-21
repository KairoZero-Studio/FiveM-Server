Config = {}

Config.debug = false

-- 채팅 메시지 영역은 접속 직후부터 상시 표시.
Config.alwaysVisible = true

-- 일반 채팅 머리표시: 시민직 직업명은 숨기고 팩션만 표시합니다.
-- 팩션 색상은 F3 > 팩션 관리에 저장된 색상을 실시간으로 사용합니다.
Config.showCivilJobTag = false
Config.showFactionTag = true

Config.proximityDist = 20.0
Config.rpDist = 20.0

Config.adminAce = 'cookie.chat.admin'

Config.adCooldown = 180

-- 팩션 채팅 허용 범위.
-- 경찰/보안국은 faction_type으로, 약국/렉카는 팩션 key/name/jobName 키워드로 인식합니다.
Config.factionChatAllowedTypes = {
    police = true,
    security = true,
}

Config.factionChatKeywords = {
    'pharmacy', 'drugstore', 'clinic', 'yakguk', '약국',
    'tow', 'wrecker', 'recovery', '렉카', '견인',
}


Config.joinDefault = '^2%s joined the server'
Config.quitDefault = '^1%s left the server (%s)'

Config.filterEnabled = true

Config.filterAdminExempt = false
Config.linkAdminExempt = true

Config.bannedWords = {

    '시발', '씨발', '씨빨', '시빨', '싀발', '씨바', '시바알', '싸발', '쓰발', '쒸발', '십알',
    '시팔', '씨팔', '시펄', '씨펄', '쉬발', '슈발', '시부랄', '시부럴', '씨부랄', '씨불',
    '시발럼', '씨발럼', '시발놈', '씨발놈', '시발년', '씨발년', '개시발', '개씨발',
    'ㅅㅂ', 'ㅆㅂ', 'ㅅ1ㅂ', 'ㅅㅃ',

    '병신', '븅신', '빙신', '병싄', '병신아', '개병신', '븅딱',
    'ㅂㅅ', 'ㅄ',

    '새끼', '새키', '색끼', '색기', '섹기', '쉐끼', '쉑', '쌔끼', '씹새', '씨새',
    '개새', '개색', '개세끼', '개쉑', '개쌔', '놈새',
    'ㅅㄲ', 'ㄱㅅㄲ',

    '지랄', '찌랄', '지럴', '개지랄',
    'ㅈㄹ',

    '좆', '좃', '좇', '조까', '족까', '좆같', '좃같', '좆밥', '좃밥',
    'ㅈㄴ', '존나', '졸라', '열라', '개존나',

    '씹', '십새', '십년', '씹년', '씹창', '씹덕', '십덕',

    '미친놈', '미친년', '미친새', '또라이', '똘아이', '돌아이',
    'ㅁㅊ', 'ㅁㅊㄴ',

    '애미', '에미', '애비', '에비', '느금', '늬미', '니애미', '니미', '엄창',
    'ㄴㄱㅁ',

    '꺼져', '닥쳐', '뒤져', '디져', '주겨', '죽어라',
    'ㄲㅈ', 'ㄷㅊ',
    '등신', '멍청이', '머저리', '호구새',
    '창녀', '걸레년', '보지', '자지', '섹스', '섹기',
    '장애인새', '앰창', '앰생',

    'fuck', 'fuk', 'fck', 'shit', 'bitch', 'asshole', 'bastard',
    'motherfuck', 'dick', 'pussy', 'cunt', 'wtf', 'stfu',
}

Config.blockLinks = true
Config.linkPatterns = {
    'https?://',
    'www%.',
    'discord%.gg',
    '%.com', '%.net', '%.kr', '%.io', '%.gg',
}

Config.spamEnabled = true
Config.spamWindow = 30
Config.spamMaxMessages = 5
Config.spamSameRepeat = 5
Config.spamMuteSeconds = 30

Config.muteDefaultMinutes = 10

Config.channelColor = {
    proximity = '#cfe3f0',
    faction   = '#6ee7a8',
    ad        = '#ffd166',
    admin     = '#ff4d4f',
    rp        = '#c9a7ff',
    whisper   = '#79c6ff',
}

function ckLog(tag, msg)
    if not Config.debug then return end

end
