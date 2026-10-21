return {
    cityhalls = {
        {
            coords = vec3(-265.0, -963.6, 31.2),
            showBlip = true,
            blip = {
                label = 'City Services',
                shortRange = true,
                sprite = 487,
                display = 4,
                scale = 0.65,
                colour = 0,
            },
            licenses = {
                ['id'] = {
                    item = 'id_card',
                    label = 'ID',
                    cost = 50,
                },
                ['driver'] = {
                    item = 'driver_license',
                    label = 'Driver License',
                    cost = 50,
                },
                ['weapon'] = {
                    item = 'weaponlicense',
                    label = 'Weapon License',
                    cost = 50,
                },
            },
        },
    },

    employment = {
        enabled = true, -- Set to false to disable the employment menu
        -- 표시 라벨만 한글화 — 키(job.name)는 qbx 직업 시스템 키이므로 불변.
        -- cookie_core Config.jobLabels와 동일 단어 사용(머리말/HUD 일치).
        jobs = {
            unemployed = '시민',
            trucker = '운송',
            taxi = '택시',
            tow = '견인',
            reporter = '기자',
            garbage = '환경미화',
            bus = '버스',
        },
    },
}
