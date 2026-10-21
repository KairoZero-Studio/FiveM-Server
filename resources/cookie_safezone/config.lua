

Config = {}

Config.Debug = false
Config.DebugZones = false

Config.AlphaInterval = 250
Config.AlphaValue = 150

Config.EnterSound = { name = 'CHECKPOINT_PERFECT', set = 'HUD_MINI_GAME_SOUNDSET' }
Config.ExitSound  = { name = 'CHECKPOINT_MISSED',  set = 'HUD_MINI_GAME_SOUNDSET' }

Config.boundary = {
    enabled = true,

    color = { r = 255, g = 200, b = 0 },
    alpha = 90,
    wallHeight = 1.2,
    wallBands = 6,
    fadePower = 1.6,
    groundOffset = 0.02,

    renderDistance = 18.0,
    fadeDistance = 25.0,

    segmentLength = 2.5,
    maxSegments = 240,
    snapToGround = true,

    minVisualRadius = 2.6,

    -- 상호작용 비콘은 실제 판정 반경과 별개로 조금 작게 표시한다.
    -- 예: 관리자에서 반경 1.0m -> 화면 표시 반경 0.72m
    beaconVisualScale = 0.72,
    beaconMinVisualRadius = 0.45,

    exactVisualTypes = {
        duty = true,
        armory = true,

        duty_lspd = true,
        armory_lspd = true,
    },

    minSegments = 12,

    maxSnapDelta = 3.0,
}

Config.garageInteractRadius = 2.4

Config.corona = {
    markerType = 25,
    scale = 1.7,
    zOffset = 0.05,
    renderDistance = 30.0,
}

function CookieSafezoneLog(...)
    if Config.Debug then

    end
end


-- 시민직업 도구 상점 기본 구성
-- 기업/팩션 상점은 추후 별도 시스템으로 제작한다.
-- jobshop 비콘은 공용이며, 이용자의 현재 시민직업에 맞는 상품만 노출된다.
-- 실제 상품/가격은 DB(cookie_jobshop_item)에 저장되며 F3 관리자 메뉴에서 수정한다.
Config.JobShop = {
    payType = 'cash',
    maxQuantity = 20,

    jobs = {
        taxi     = { label = '택시기사' },
        trucker  = { label = '트럭커' },
        labor    = { label = '건설 인부' },
        delivery = { label = '배달기사' },
        mechanic = { label = '정비공' },
    },

    -- DB가 처음 만들어질 때만 들어가는 기본 상품.
    -- 이후 가격/판매여부는 F3 → 비콘 관리 → 직업 도구 상점 관리에서 변경한다.
    initialItems = {
        { job = 'mechanic', item = 'repairkit', label = '수리키트', price = 25000, sortOrder = 10 },
    },
}
