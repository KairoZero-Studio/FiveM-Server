---@deprecated REFERENCE ONLY. COOKIE V12 uses ox_inventory/data/items.lua as the single source of truth. Do not load this file as an item registry.
---@type table<string, Item>
return {
    ['armor'] = {
        label = '방탄복',
        weight = 1400,
        stack = true,
        close = true,
        consume = 1,
        description = '사용하면 방탄 게이지를 100%까지 채웁니다.',
        client = {
            image = 'armor.png',
            usetime = 2500,
            cancel = true,
            anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d' },
            disable = { move = true, car = true, combat = true },
            export = 'cookie_items.armor',
        },
    },

    ['medikit'] = {
        label = '구급상자',
        weight = 1000,
        stack = true,
        close = true,
        consume = 1,
        description = '사용하면 체력을 100%까지 회복합니다.',
        client = {
            image = 'medikit.png',
            usetime = 3500,
            cancel = true,
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },
            disable = { move = true, car = true, combat = true },
            export = 'cookie_items.medikit',
        },
    },

    ['oxy'] = {
        label = '진통제',
        weight = 200,
        stack = true,
        close = true,
        consume = 1,
        description = '사용하면 체력을 최대치의 50%만큼 회복합니다.',
        client = {
            image = 'oxy.png',
            usetime = 1800,
            cancel = true,
            anim = { dict = 'mp_suicide', clip = 'pill' },
            disable = { move = true, car = true, combat = true },
            export = 'cookie_items.oxy',
        },
    },

    ['energy_drink'] = {
        label = '에너지 드링크',
        weight = 350,
        stack = true,
        close = true,
        consume = 1,
        description = '마시면 10초 동안 이동 속도가 증가합니다.',
        client = {
            image = 'energy_drink.png',
            usetime = 1800,
            cancel = true,
            anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
            disable = { combat = true },
            export = 'cookie_items.energyDrink',
        },
    },

    ['repairkit'] = {
        label = '수리키트',
        weight = 1200,
        stack = true,
        close = true,
        consume = 0,
        description = '정비기사가 차량을 수리할 때 1개씩 소모되는 전용 도구입니다.',
        client = {
            image = 'rapairkit.png',
        },
    },



    ['skin_packkit'] = {
        label = '스킨 포장키트',
        weight = 700,
        stack = true,
        close = true,
        consume = 0,
        description = '현재 장착 중인 한정 스킨을 해제하고 스킨 보관함으로 되돌립니다.',
        client = {
            image = 'skin_packkit.png',
            usetime = 2000,
            cancel = true,
            anim = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
            disable = { move = true, car = true, combat = true },
            export = 'cookie_admin.skinPackKit',
        },
    },

    ['vehicle_packkit'] = {
        label = '차량 포장키트',
        weight = 1500,
        stack = true,
        close = true,
        consume = 0,
        description = '현재 탑승 중인 본인 소유 개인차량을 포장 상태로 회수합니다. 포장 상태에서만 거래할 수 있습니다.',
        client = {
            image = 'vehicle_packkit.png',
            usetime = 3500,
            cancel = true,
            anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
            disable = { move = true, car = true, combat = true },
            export = 'cookie_admin.vehiclePackKit',
        },
    },


    -- 낚싯대: 퀵슬롯 사용 시 장착/해제만 합니다. 아이템은 소모되지 않습니다.
    ['fishingrod'] = {
        label = '초급 낚싯대', weight = 1500, stack = false, close = true, consume = 0,
        description = '퀵슬롯으로 들고 낚시터에서 E를 눌러 사용합니다.',
        client = { image = 'fishingrod.png', export = 'cookie_fishing.useFishingRod' },
    },
    ['fishingrod_mid'] = {
        label = '중급 낚싯대', weight = 1650, stack = false, close = true, consume = 0,
        description = '퀵슬롯으로 들고 낚시터에서 E를 눌러 사용합니다.',
        client = { image = 'fishingrod_mid.png', export = 'cookie_fishing.useFishingRod' },
    },
    ['fishingrod_pro'] = {
        label = '고급 낚싯대', weight = 1800, stack = false, close = true, consume = 0,
        description = '퀵슬롯으로 들고 낚시터에서 E를 눌러 사용합니다.',
        client = { image = 'fishingrod_pro.png', export = 'cookie_fishing.useFishingRod' },
    },

    -- 곡괭이: 퀵슬롯 사용 시 손에 들고, 바위에서 E로 광질합니다.
    ['mining_pickaxe_basic'] = {
        label = '보급형 곡괭이', weight = 1800, stack = false, close = true, consume = 0,
        description = '퀵슬롯으로 장착한 뒤 바위 가까이에서 E를 누르세요.',
        client = { image = 'mining_pickaxe_basic.png', export = 'cookie_mining.usePickaxe' },
    },
    ['mining_pickaxe_skilled'] = {
        label = '숙련자 곡괭이', weight = 1900, stack = false, close = true, consume = 0,
        description = '퀵슬롯으로 장착한 뒤 바위 가까이에서 E를 누르세요.',
        client = { image = 'mining_pickaxe_skilled.png', export = 'cookie_mining.usePickaxe' },
    },
    ['mining_pickaxe_expert'] = {
        label = '전문가 곡괭이', weight = 2000, stack = false, close = true, consume = 0,
        description = '퀵슬롯으로 장착한 뒤 바위 가까이에서 E를 누르세요.',
        client = { image = 'mining_pickaxe_expert.png', export = 'cookie_mining.usePickaxe' },
    },


    ['newbie_reward_kit'] = {
        label = '뉴비 보상 키트',
        weight = 800,
        stack = true,
        close = true,
        consume = 0,
        description = '뉴비 인증 완료 보상입니다. 사용하면 기본 생존 아이템과 지원금을 지급합니다.',
        client = {
            image = 'newbie_reward_kit.png',
            usetime = 2500,
            cancel = true,
            anim = { dict = 'amb@prop_human_bum_bin@base', clip = 'base' },
            disable = { move = true, car = true, combat = true },
            export = 'cookie_items.newbieRewardKit',
        },
    },

}
