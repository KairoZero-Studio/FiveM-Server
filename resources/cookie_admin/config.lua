Config = {}

Config.Debug = false

Config.LevelName = {
    [1] = '뉴비가이드',
    [2] = '스태프',
    [3] = 'ADMIN',
    [4] = 'SENIORADMIN',
    [5] = 'HEADADMIN',
}

Config.AdminTeams = {
    { key = 'faction', label = '팩션팀' },

}

Config.FactionTypes = {
    { key = 'police',      label = '경찰국',   gov = true },
    { key = 'security',    label = '보안국',   gov = true },
    { key = 'corrections', label = '교정국',   gov = true },
    { key = 'fire',        label = '소방국',   gov = true },
    { key = 'private',     label = '사설팩션', gov = false },
    { key = 'tow',         label = '렉카',     gov = false },
    { key = 'crime',       label = '범죄팩션', gov = false },
    { key = 'civil',       label = '시민직',   gov = false },
}

Config.FactionRankPreset = {
    police = {
        { grade = 0, name = '순경', officer = false, leader = false, salary = 50 },
        { grade = 1, name = '경장', officer = false, leader = false, salary = 60 },
        { grade = 2, name = '경사', officer = false, leader = false, salary = 70 },
        { grade = 3, name = '경위', officer = true,  leader = false, salary = 90 },
        { grade = 4, name = '경감', officer = true,  leader = false, salary = 110 },
        { grade = 5, name = '서장', officer = true,  leader = true,  salary = 150 },
    },
    default = {
        { grade = 0, name = '수습', officer = false, leader = false, salary = 30 },
        { grade = 1, name = '정규', officer = false, leader = false, salary = 50 },
        { grade = 2, name = '간부', officer = true,  leader = false, salary = 80 },
        { grade = 3, name = '리더', officer = true,  leader = true,  salary = 120 },
    },
}

Config.FactionDepartments = {
    police      = { '순찰부', '교통부', '수사부', '교육부', '인사부', '감찰부', '특공대' },
    security    = { '경비부', '호송부', '교육부', '감찰부' },
    corrections = { '보안과', '교정과', '분류과' },
    fire        = { '진압부', '구급부', '예방부' },
    tow         = { '견인팀', '압류팀' },
    default     = { '운영부', '관리부' },
}

Config.TimeAccrueInterval = 60000

function CookieLog(...)
    if Config.Debug then

    end
end

Config.VehicleSpawnMinLevel = 3

Config.VehicleExhibitMinLevel = 3

Config.VehiclePreviewPad = vector4(-1336.0, -3044.0, 13.94, 329.0)

Config.TestDriveTrack = vector4(-1191.0, -2823.0, 13.9, 152.0)

Config.NewVehicles = { fmss = true, gr1 = true, countyp = true }

Config.LspdLineup = {
    'gr1', 'fmss', 'polaventa', 'countyp', 'crusader', 'vetir',
    'poldominator10', 'poldorado', 'polfaction2', 'fbi', 'fbi2',
    'polgauntlet', 'polgreenwood', 'polimpaler5', 'polimpaler6',
    'police', 'police2', 'police3', 'police4', 'policeb', 'policet',
    'riot', 'pbus', 'riot2', 'pstarex', 'pstarex2',
}

Config.ArmoryChargeBudget = false
Config.ArmoryMaxQty = 20

Config.ArmorValue = 1000
Config.ArmorLabel = '근무 케블라'

Config.ArmoryImageAlias = {
    ['WEAPON_TACTICALRIFLE'] = 'WEAPON_MILITARYRIFLE',
}

Config.ArmoryLineup = {
    'WEAPON_APPISTOL',
    'WEAPON_STUNGUN',
    'WEAPON_SMG_MK2',
    'WEAPON_ASSAULTRIFLE_MK2',
    'WEAPON_CARBINERIFLE_MK2',
    'WEAPON_TACTICALRIFLE',
    'WEAPON_PUMPSHOTGUN_MK2',
    'WEAPON_ASSAULTSHOTGUN',
    'WEAPON_SNIPERRIFLE',
}

Config.AmmoLabels = {
    ['ammo-9']       = '9mm 탄약',
    ['ammo-45']      = '.45 탄약',
    ['ammo-50']      = '.50 탄약',
    ['ammo-22']      = '.22 탄약',
    ['ammo-38']      = '.38 탄약',
    ['ammo-44']      = '.44 탄약',
    ['ammo-rifle']   = '소총 탄약',
    ['ammo-rifle2']  = '소총 탄약 II',
    ['ammo-shotgun'] = '샷건 탄약',
    ['ammo-sniper']  = '저격 탄약',
    ['ammo-heavy']   = '중화기 탄약',
    ['ammo-mg']      = '기관총 탄약',
    ['ammo-laser']   = '레이저 탄약',
}

Config.WeaponParts = {
    { key = 'muzzle', label = '총구', items = {
        { name = 'at_suppressor_light', label = '소음기' },
        { name = 'at_suppressor_heavy', label = '전술 소음기' },
        { name = 'at_compensator',      label = '컴펜세이터' },
        { name = 'at_muzzle_flat',      label = '머즐 브레이크 플랫' },
        { name = 'at_muzzle_tactical',  label = '머즐 브레이크 전술' },
        { name = 'at_muzzle_heavy',     label = '머즐 브레이크 헤비' },
        { name = 'at_muzzle_precision', label = '머즐 브레이크 정밀' },
    }},
    { key = 'scope', label = '조준경', items = {
        { name = 'at_scope_small',    label = '소형 스코프' },
        { name = 'at_scope_medium',   label = '중형 스코프' },
        { name = 'at_scope_large',    label = '대형 스코프' },
        { name = 'at_scope_advanced', label = '고급 스코프' },
        { name = 'at_scope_holo',     label = '홀로 사이트' },
        { name = 'at_scope_nv',       label = '야간 투시경' },
        { name = 'at_scope_thermal',  label = '열화상 조준경' },
    }},
    { key = 'clip', label = '탄창', items = {
        { name = 'at_clip_extended_pistol',  label = '권총 확장 탄창' },
        { name = 'at_clip_extended_smg',     label = 'SMG 확장 탄창' },
        { name = 'at_clip_extended_rifle',   label = '소총 확장 탄창' },
        { name = 'at_clip_extended_shotgun', label = '샷건 확장 탄창' },
        { name = 'at_clip_extended_sniper',  label = '저격 확장 탄창' },
        { name = 'at_clip_drum_smg',         label = 'SMG 드럼 탄창' },
        { name = 'at_clip_drum_rifle',       label = '소총 드럼 탄창' },
        { name = 'at_clip_drum_shotgun',     label = '샷건 드럼 탄창' },
    }},
    { key = 'etc', label = '기타', items = {
        { name = 'at_flashlight', label = '플래시라이트' },
        { name = 'at_grip',       label = '그립' },
        { name = 'at_barrel',     label = '헤비 배럴' },
    }},
}

Config.DutyIdleMinutes = 30

Config.NameTagOrgOnDutyOnly = true

Config.FactionDefaultEmoji = {
    police      = '👮',
    security    = '🛡️',
    corrections = '⛓️',
    fire        = '🚒',
    private     = '💼',
    crime       = '💀',
    civil       = '🍀',
}

Config.NpcEditMinLevel = 3

Config.NpcPeds = {
    { key = 'office', label = '사무직', items = {
        { model = 'a_m_y_business_01',  label = '정장 남성 1' },
        { model = 'a_m_m_business_01',  label = '정장 남성 2' },
        { model = 'a_f_y_business_01',  label = '정장 여성 1' },
        { model = 'a_f_y_business_02',  label = '정장 여성 2' },
        { model = 'a_m_y_business_03',  label = '캐주얼 정장' },
        { model = 's_m_m_highsec_01',   label = '경비원' },
    }},
    { key = 'gov', label = '공직', items = {
        { model = 's_m_y_cop_01',       label = '경찰관' },
        { model = 's_f_y_cop_01',       label = '여경' },
        { model = 's_m_y_sheriff_01',   label = '보안관' },
        { model = 's_m_y_swat_01',      label = '특공대' },
        { model = 's_m_y_fireman_01',   label = '소방관' },
        { model = 's_m_m_paramedic_01', label = '구급대원' },
        { model = 's_m_m_prisguard_01', label = '교도관' },
    }},
    { key = 'work', label = '현장직', items = {
        { model = 's_m_y_construct_01', label = '건설 노동자' },
        { model = 's_m_m_gardener_01',  label = '정원사' },
        { model = 's_m_y_garbage_01',   label = '환경미화원' },
        { model = 's_m_m_trucker_01',   label = '트럭 기사' },
        { model = 's_m_m_dockwork_01',  label = '항만 노동자' },
        { model = 's_m_y_airworker',    label = '공항 직원' },
        { model = 's_m_m_autoshop_01',  label = '정비공' },
    }},
    { key = 'shop', label = '판매/서비스', items = {
        { model = 'mp_m_shopkeep_01',   label = '상점 점원' },
        { model = 's_m_y_dealer_01',    label = '중개인' },
        { model = 's_f_y_bartender_01', label = '바텐더' },
        { model = 's_m_m_lathandy_01',  label = '차량 판매원' },
        { model = 's_m_y_valet_01',     label = '발렛' },
        { model = 's_f_m_shop_high',    label = '고급 매장 직원' },
    }},
    { key = 'civ', label = '시민', items = {
        { model = 'a_m_y_hipster_01',   label = '힙스터 남성' },
        { model = 'a_f_y_hipster_01',   label = '힙스터 여성' },
        { model = 'a_m_m_eastsa_01',    label = '동양계 남성' },
        { model = 'a_f_m_eastsa_01',    label = '동양계 여성' },
        { model = 'a_m_y_skater_01',    label = '스케이터' },
        { model = 'a_m_y_stwhi_01',     label = '평상복 남성' },
        { model = 'a_f_y_genhot_01',    label = '평상복 여성' },
    }},
    { key = 'crime', label = '범죄', items = {
        { model = 'g_m_y_lost_01',      label = '바이커' },
        { model = 'g_m_y_ballasout_01', label = '발라스' },
        { model = 'g_m_y_famca_01',     label = '패밀리즈' },
        { model = 'g_m_m_chigoon_01',   label = '조직원' },
        { model = 'a_m_m_hillbilly_01', label = '시골 건달' },
    }},
}

Config.NpcScenarios = {
    { key = '',                              label = '없음 (차렷)' },
    { key = 'WORLD_HUMAN_CLIPBOARD',         label = '서류 확인' },
    { key = 'WORLD_HUMAN_STAND_IMPATIENT',   label = '초조하게 대기' },
    { key = 'WORLD_HUMAN_GUARD_STAND',       label = '경비 자세' },
    { key = 'WORLD_HUMAN_COP_IDLES',         label = '경찰 대기' },
    { key = 'WORLD_HUMAN_STAND_MOBILE',      label = '통화 중' },
    { key = 'WORLD_HUMAN_SMOKING',           label = '흡연' },
    { key = 'WORLD_HUMAN_AA_COFFEE',         label = '커피' },
    { key = 'WORLD_HUMAN_LEANING',           label = '기대서기' },
    { key = 'WORLD_HUMAN_HAMMERING',         label = '망치질' },
    { key = 'WORLD_HUMAN_WELDING',           label = '용접' },
    { key = 'PROP_HUMAN_PARKING_METER',      label = '기계 조작' },
}

Config.NpcComponents = {
    { id = 1,  label = '마스크' },
    { id = 3,  label = '상의(팔)' },
    { id = 4,  label = '하의' },
    { id = 5,  label = '가방' },
    { id = 6,  label = '신발' },
    { id = 7,  label = '액세서리' },
    { id = 8,  label = '이너' },
    { id = 11, label = '상의' },
    { id = 0,  label = '모자', prop = true },
    { id = 1,  label = '안경', prop = true },
}

Config.CivilJobs = {
    taxi = {
        label   = '택시기사',
        emoji   = '🚕',
        tagName = '택시기사',
        skill   = 'taxi',
        quitEvent = 'cookie_taxi:server:forceQuit',
    },

    trucker = {
        label   = '트럭커',
        emoji   = '🚚',
        tagName = '트럭커',
        skill   = 'trucker',
        quitEvent = 'cookie_trucker:server:forceQuit',
    },

    labor = {
        label   = '건설 인부',
        emoji   = '👷',
        tagName = '건설 인부',
        skill   = 'labor',
        quitEvent = 'cookie_labor:server:forceQuit',
    },
    delivery = {
        label   = '배달기사',
        emoji   = '🛵',
        tagName = '배달기사',
        skill   = 'delivery',
        quitEvent = 'cookie_delivery:server:forceQuit',
    },
    mechanic = {
        label   = '정비공',
        emoji   = '🔧',
        tagName = '정비공',
        skill   = 'mechanic',
        quitEvent = 'cookie_mechanic:server:forceQuit',
    },
}

-- F3 > 내정보 > 직업 레벨에 함께 표시할 활동형 숙련도.
-- 시민직 고용/퇴사 로직에는 포함하지 않아 기존 직업 시스템에 영향을 주지 않습니다.
Config.F3JobLevelActivities = {
    fishing = {
        label = '낚시',
        emoji = '🎣',
        skill = 'fishing',
        statLabel = '낚은 횟수',
    },
    mining = {
        label = '광질',
        emoji = '⛏️',
        skill = 'mining',
        statLabel = '채굴 횟수',
    },
}

Config.NpcJobKeys = {
    { key = '',      label = '없음 (대화 안 함)',  event = nil },
    { key = 'taxi',  label = '택시 관리인',        event = 'cookie_taxi:client:openDialog',    badge = '택시 일 알아보기' },
    { key = 'trucker', label = '트럭 배차관리인',  event = 'cookie_trucker:client:openDialog', badge = '트럭 일 알아보기' },
    { key = 'labor',   label = '건설 현장 반장',    event = 'cookie_labor:client:openDialog',   badge = '건설 일 알아보기' },
    { key = 'delivery', label = '배달기사 관리인', event = 'cookie_delivery:client:openDialog', badge = '배달 일 알아보기' },
    { key = 'mechanic', label = '정비소 반장', event = 'cookie_mechanic:client:openDialog', badge = '정비 일 알아보기' },
    { key = 'fishing', label = '낚시 관리인', event = 'cookie_fishing:client:openManager', badge = '낚시 관리인과 대화' },
    { key = 'mining', label = '광물 관리인', event = 'cookie_mining:client:openManager', badge = '광물 관리인과 대화' },

}

Config.NpcInteractDistance = 2.2

Config.WeaponGiveMinLevel = 3

Config.Weapons = {
    { key = 'pistol', label = '권총', type = 'gun', items = {
        { name = 'WEAPON_PISTOL',        label = '권총',            ammo = 'ammo-9' },
        { name = 'WEAPON_PISTOL_MK2',    label = '권총 MK2',        ammo = 'ammo-9' },
        { name = 'WEAPON_COMBATPISTOL',  label = '컴뱃 피스톨',     ammo = 'ammo-9' },
        { name = 'WEAPON_APPISTOL',      label = 'AP 피스톨',       ammo = 'ammo-9' },
        { name = 'WEAPON_CERAMICPISTOL', label = '세라믹 피스톨',   ammo = 'ammo-9' },
        { name = 'WEAPON_VINTAGEPISTOL', label = '빈티지 피스톨',   ammo = 'ammo-9' },
        { name = 'WEAPON_GADGETPISTOL',  label = '페리코 피스톨',   ammo = 'ammo-9' },
        { name = 'WEAPON_PISTOLXM3',     label = 'WM29 권총',       ammo = 'ammo-9' },
        { name = 'WEAPON_HEAVYPISTOL',   label = '헤비 피스톨',     ammo = 'ammo-45' },
        { name = 'WEAPON_SNSPISTOL',     label = 'SNS 권총',        ammo = 'ammo-45' },
        { name = 'WEAPON_SNSPISTOL_MK2', label = 'SNS 권총 MK2',    ammo = 'ammo-45' },
        { name = 'WEAPON_PISTOL50',      label = '권총 .50',        ammo = 'ammo-50' },
        { name = 'WEAPON_MARKSMANPISTOL',label = '마크스맨 피스톨', ammo = 'ammo-22' },
        { name = 'WEAPON_REVOLVER',      label = '리볼버',          ammo = 'ammo-44' },
        { name = 'WEAPON_REVOLVER_MK2',  label = '리볼버 MK2',      ammo = 'ammo-44' },
        { name = 'WEAPON_NAVYREVOLVER',  label = '네이비 리볼버',   ammo = 'ammo-44' },
        { name = 'WEAPON_DOUBLEACTION',  label = '더블액션 리볼버', ammo = 'ammo-38' },
        { name = 'WEAPON_FLAREGUN',      label = '플레어건',        ammo = 'ammo-flare' },
        { name = 'WEAPON_STUNGUN',       label = '테이저' },
    }},
    { key = 'smg', label = '기관단총', type = 'gun', items = {
        { name = 'WEAPON_MICROSMG',      label = '마이크로 SMG',    ammo = 'ammo-45' },
        { name = 'WEAPON_SMG',           label = 'SMG',             ammo = 'ammo-9' },
        { name = 'WEAPON_SMG_MK2',       label = 'SMG MK2',         ammo = 'ammo-9' },
        { name = 'WEAPON_ASSAULTSMG',    label = '어썰트 SMG',      ammo = 'ammo-rifle' },
        { name = 'WEAPON_COMBATPDW',     label = '컴뱃 PDW',        ammo = 'ammo-9' },
        { name = 'WEAPON_MACHINEPISTOL', label = '머신 피스톨',     ammo = 'ammo-9' },
        { name = 'WEAPON_MINISMG',       label = '미니 SMG',        ammo = 'ammo-9' },
        { name = 'WEAPON_TECPISTOL',     label = '택티컬 SMG',      ammo = 'ammo-9' },
        { name = 'WEAPON_GUSENBERG',     label = '구센버그',        ammo = 'ammo-45' },
    }},
    { key = 'rifle', label = '라이플', type = 'gun', items = {
        { name = 'WEAPON_ASSAULTRIFLE',      label = '어썰트 라이플',       ammo = 'ammo-rifle2' },
        { name = 'WEAPON_ASSAULTRIFLE_MK2',  label = '어썰트 라이플 MK2',   ammo = 'ammo-rifle2' },
        { name = 'WEAPON_CARBINERIFLE',      label = '카빈 라이플',         ammo = 'ammo-rifle' },
        { name = 'WEAPON_CARBINERIFLE_MK2',  label = '카빈 라이플 MK2',     ammo = 'ammo-rifle' },
        { name = 'WEAPON_ADVANCEDRIFLE',     label = '어드밴스드 라이플',   ammo = 'ammo-rifle' },
        { name = 'WEAPON_SPECIALCARBINE',    label = '스페셜 카빈',         ammo = 'ammo-rifle' },
        { name = 'WEAPON_SPECIALCARBINE_MK2',label = '스페셜 카빈 MK2',     ammo = 'ammo-rifle' },
        { name = 'WEAPON_BULLPUPRIFLE',      label = '불펍 라이플',         ammo = 'ammo-rifle' },
        { name = 'WEAPON_BULLPUPRIFLE_MK2',  label = '불펍 라이플 MK2',     ammo = 'ammo-rifle' },
        { name = 'WEAPON_COMPACTRIFLE',      label = '컴팩트 라이플',       ammo = 'ammo-rifle2' },
        { name = 'WEAPON_MILITARYRIFLE',     label = '밀리터리 라이플',     ammo = 'ammo-rifle' },
        { name = 'WEAPON_HEAVYRIFLE',        label = '헤비 라이플',         ammo = 'ammo-rifle' },
        { name = 'WEAPON_TACTICALRIFLE',     label = '택티컬 라이플',       ammo = 'ammo-rifle' },
        { name = 'WEAPON_BATTLERIFLE',       label = '배틀 라이플',         ammo = 'ammo-rifle2' },
    }},
    { key = 'shotgun', label = '샷건', type = 'gun', items = {
        { name = 'WEAPON_PUMPSHOTGUN',     label = '펌프 샷건',       ammo = 'ammo-shotgun' },
        { name = 'WEAPON_PUMPSHOTGUN_MK2', label = '펌프 샷건 MK2',   ammo = 'ammo-shotgun' },
        { name = 'WEAPON_SAWNOFFSHOTGUN',  label = '소드오프 샷건',   ammo = 'ammo-shotgun' },
        { name = 'WEAPON_ASSAULTSHOTGUN',  label = '어썰트 샷건',     ammo = 'ammo-shotgun' },
        { name = 'WEAPON_BULLPUPSHOTGUN',  label = '불펍 샷건',       ammo = 'ammo-shotgun' },
        { name = 'WEAPON_HEAVYSHOTGUN',    label = '헤비 샷건',       ammo = 'ammo-shotgun' },
        { name = 'WEAPON_DBSHOTGUN',       label = '더블배럴 샷건',   ammo = 'ammo-shotgun' },
        { name = 'WEAPON_AUTOSHOTGUN',     label = '스위퍼 샷건',     ammo = 'ammo-shotgun' },
        { name = 'WEAPON_COMBATSHOTGUN',   label = '컴뱃 샷건',       ammo = 'ammo-shotgun' },
    }},
    { key = 'sniper', label = '저격총', type = 'gun', items = {
        { name = 'WEAPON_SNIPERRIFLE',       label = '스나이퍼 라이플',     ammo = 'ammo-sniper' },
        { name = 'WEAPON_HEAVYSNIPER',       label = '헤비 스나이퍼',       ammo = 'ammo-heavysniper' },
        { name = 'WEAPON_HEAVYSNIPER_MK2',   label = '헤비 스나이퍼 MK2',   ammo = 'ammo-heavysniper' },
        { name = 'WEAPON_MARKSMANRIFLE',     label = '마크스맨 라이플',     ammo = 'ammo-sniper' },
        { name = 'WEAPON_MARKSMANRIFLE_MK2', label = '마크스맨 라이플 MK2', ammo = 'ammo-sniper' },
        { name = 'WEAPON_PRECISIONRIFLE',    label = '프리시전 라이플',     ammo = 'ammo-sniper' },
    }},
    { key = 'heavy', label = '중화기', type = 'gun', items = {
        { name = 'WEAPON_RPG',             label = 'RPG',             ammo = 'ammo-rocket' },
        { name = 'WEAPON_GRENADELAUNCHER', label = '유탄발사기',      ammo = 'ammo-grenade' },
        { name = 'WEAPON_COMPACTLAUNCHER', label = '컴팩트 유탄발사기', ammo = 'ammo-grenade' },
        { name = 'WEAPON_HOMINGLAUNCHER',  label = '호밍 런처',       ammo = 'ammo-rocket' },
        { name = 'WEAPON_MINIGUN',         label = '미니건',          ammo = 'ammo-rifle2' },
        { name = 'WEAPON_COMBATMG',        label = '컴뱃 MG',         ammo = 'ammo-rifle' },
        { name = 'WEAPON_COMBATMG_MK2',    label = '컴뱃 MG MK2',     ammo = 'ammo-rifle2' },
        { name = 'WEAPON_MG',              label = '머신건',          ammo = 'ammo-rifle2' },
        { name = 'WEAPON_RAILGUN',         label = '레일건',          ammo = 'ammo-railgun' },
    }},
    { key = 'throwable', label = '투척', type = 'throwable', items = {
        { name = 'WEAPON_GRENADE',      label = '수류탄' },
        { name = 'WEAPON_MOLOTOV',      label = '화염병' },
        { name = 'WEAPON_STICKYBOMB',   label = '점착폭탄' },
        { name = 'WEAPON_PIPEBOMB',     label = '파이프폭탄' },
        { name = 'WEAPON_SMOKEGRENADE', label = '연막탄' },
        { name = 'WEAPON_BZGAS',        label = 'BZ 가스' },
        { name = 'WEAPON_TEARGAS',      label = '최루탄' },
        { name = 'WEAPON_PROXMINE',     label = '근접지뢰' },
        { name = 'WEAPON_FLARE',        label = '조명탄' },
        { name = 'WEAPON_SNOWBALL',     label = '눈덩이' },
    }},
    { key = 'melee', label = '둔기/흉기', type = 'melee', items = {
        { name = 'WEAPON_BAT',         label = '야구방망이' },
        { name = 'WEAPON_KNIFE',       label = '나이프' },
        { name = 'WEAPON_MACHETE',     label = '마체테' },
        { name = 'WEAPON_CROWBAR',     label = '쇠지렛대' },
        { name = 'WEAPON_HAMMER',      label = '망치' },
        { name = 'WEAPON_HATCHET',     label = '손도끼' },
        { name = 'WEAPON_GOLFCLUB',    label = '골프채' },
        { name = 'WEAPON_NIGHTSTICK',  label = '경찰봉' },
        { name = 'WEAPON_KNUCKLE',     label = '너클' },
        { name = 'WEAPON_DAGGER',      label = '단검' },
        { name = 'WEAPON_BATTLEAXE',   label = '배틀액스' },
        { name = 'WEAPON_BOTTLE',      label = '병' },
        { name = 'WEAPON_POOLCUE',     label = '당구큐' },
        { name = 'WEAPON_WRENCH',      label = '렌치' },
        { name = 'WEAPON_SWITCHBLADE', label = '스위치블레이드' },
    }},
}
