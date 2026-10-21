Config = {}

Config.Debug = false
Config.SkillKey = 'mining'
Config.SkillExpPerSuccess = 1
-- 곡괭이 3단계 체계
-- 기존 mining_pickaxe_basic 아이템 ID는 그대로 유지하여 기존 유저 인벤토리가 깨지지 않습니다.
Config.Pickaxes = {
    basic = {
        item = 'mining_pickaxe_basic',
        label = '보급형 곡괭이',
        durationMultiplier = 1.00,
        defaultPrice = 50000,
    },
    skilled = {
        item = 'mining_pickaxe_skilled',
        label = '숙련자 곡괭이',
        durationMultiplier = 0.80,
        defaultPrice = 150000,
    },
    expert = {
        item = 'mining_pickaxe_expert',
        label = '전문가 곡괭이',
        durationMultiplier = 0.60,
        defaultPrice = 350000,
    },
}
Config.PickaxeOrder = { 'basic', 'skilled', 'expert' }
-- 하위 호환용. 다른 코드가 기존 값을 참조해도 보급형 곡괭이를 가리킵니다.
Config.PickaxeItem = Config.Pickaxes.basic.item

-- 광산 위치/범위와 출현 광물은 F3에서 관리합니다.
Config.InteractDistance = 4.0
Config.MineDurationMs = 20000          -- 리듬게임 실패/미참여 기본 채굴시간
Config.RhythmSuccessDurationMs = 5000 -- 리듬게임 성공 시 채굴시간
Config.RhythmRounds = 4
Config.NodeRespawnMs = 45000
Config.NodeCount = 9
Config.NodePreviewDistance = 80.0
Config.NodeMargin = 1.0
Config.NodeModels = {
    -- V1.5.6: 기존 소형 바위보다 한 단계 큰 중형 바위 위주. giant 계열은 제외.
    'prop_rock_4_c',
    'prop_rock_4_e',
    'prop_rock_5_smash3',
    'prop_rock_4_cl_2',
}

Config.PurityPriceMinMultiplier = 0.50
Config.PurityPriceMaxMultiplier = 2.00
Config.DefaultPickaxePrice = 50000 -- 하위 호환용

Config.Quality = {
    { key = 'normal',  label = '보통',   chance = 60.0, min = 30, max = 59 },
    { key = 'good',    label = '양질',   chance = 28.0, min = 60, max = 79 },
    { key = 'high',    label = '고순도', chance = 10.0, min = 80, max = 94 },
    { key = 'perfect', label = '최상급', chance =  2.0, min = 95, max = 100 },
}

Config.RarityOrder = { 'common', 'uncommon', 'rare', 'epic', 'legendary' }
Config.Rarity = {
    common    = { label = '일반', color = '#9ca3af' },
    uncommon  = { label = '고급', color = '#22c55e' },
    rare      = { label = '희귀', color = '#3b82f6' },
    epic      = { label = '영웅', color = '#a855f7' },
    legendary = { label = '전설', color = '#f59e0b' },
}

-- sell = 광물 관리인 기본 매입 기준가. NPC별 가격이 저장되어 있으면 NPC값이 우선합니다.
Config.Minerals = {
    coal       = { label='석탄',       rarity='common',    weight=16.0, sell=15000 },
    iron       = { label='철광석',     rarity='common',    weight=15.0, sell=20000 },
    copper     = { label='구리광석',   rarity='common',    weight=14.0, sell=18000 },
    tin        = { label='주석광석',   rarity='common',    weight=9.0,  sell=22000 },
    lead       = { label='납광석',     rarity='common',    weight=8.0,  sell=25000 },
    zinc       = { label='아연광석',   rarity='common',    weight=8.0,  sell=25000 },
    nickel     = { label='니켈광석',   rarity='uncommon',  weight=6.0,  sell=35000 },
    bauxite    = { label='보크사이트', rarity='uncommon',  weight=6.0,  sell=35000 },
    quartz     = { label='석영',       rarity='uncommon',  weight=5.0,  sell=45000 },
    silver     = { label='은광석',     rarity='rare',      weight=4.0,  sell=70000 },
    obsidian   = { label='흑요석',     rarity='rare',      weight=3.5,  sell=80000 },
    garnet     = { label='가넷',       rarity='rare',      weight=2.5,  sell=100000 },
    amethyst   = { label='자수정',     rarity='rare',      weight=2.2,  sell=120000 },
    topaz      = { label='토파즈',     rarity='rare',      weight=1.8,  sell=140000 },
    opal       = { label='오팔',       rarity='rare',      weight=1.5,  sell=180000 },
    gold       = { label='금광석',     rarity='epic',      weight=1.2,  sell=250000 },
    emerald    = { label='에메랄드',   rarity='epic',      weight=0.8,  sell=350000 },
    sapphire   = { label='사파이어',   rarity='epic',      weight=0.7,  sell=400000 },
    ruby       = { label='루비',       rarity='epic',      weight=0.6,  sell=450000 },
    diamond    = { label='다이아몬드', rarity='legendary', weight=0.25, sell=800000 },
}
