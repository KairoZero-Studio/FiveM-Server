---Job names must be lower case (top level table key)
---@type table<string, Job>
return {
    ['sasp'] = {
        label = '주 경찰',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'Officer', payment = 75 },
            [2] = { name = 'Sergeant', payment = 100 },
            [3] = { name = 'Lieutenant', payment = 125 },
            [4] = { name = 'Chief', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['bcso'] = {
        label = '보안국',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'Officer', payment = 75 },
            [2] = { name = 'Sergeant', payment = 100 },
            [3] = { name = 'Lieutenant', payment = 125 },
            [4] = { name = 'Chief', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['cardealer'] = {
        label = '차량 딜러',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'Showroom Sales', payment = 75 },
            [2] = { name = 'Business Sales', payment = 100 },
            [3] = { name = 'Finance', payment = 125 },
            [4] = { name = 'Manager', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['garbage'] = {
        label = '환경미화',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Collector', payment = 50 },
        },
    },
    ['bus'] = {
        label = '버스',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Driver', payment = 50 },
        },
    },
    ['taxi'] = {
        label = '택시기사',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '택시기사', payment = 0 },
        },
    },
    ['tow'] = {
        label = '견인',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Driver', payment = 50 },
        },
    },
    ['unemployed'] = {
        label = '시민',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Freelancer', payment = 10 },
        },
    },
    ['lawyer'] = {
        label = '법률사무소',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Associate', payment = 50 },
        },
    },
    ['ambulance'] = {
        label = '응급의료',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'Paramedic', payment = 75 },
            [2] = { name = 'Doctor', payment = 100 },
            [3] = { name = 'Surgeon', payment = 125 },
            [4] = { name = 'Chief', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['hotdog'] = {
        label = '노점',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Sales', payment = 50 },
        },
    },
    ['mechanic'] = {
        label = '정비소',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'Novice', payment = 75 },
            [2] = { name = 'Experienced', payment = 100 },
            [3] = { name = 'Advanced', payment = 125 },
            [4] = { name = 'Manager', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['reporter'] = {
        label = '기자',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Journalist', payment = 50 },
        },
    },
    ['labor'] = {
        label = '건설 인부',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '건설 인부', payment = 0 },
        },
    },
    ['police'] = {
        label = '쿠키 경찰국',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'Officer', payment = 75 },
            [2] = { name = 'Sergeant', payment = 100 },
            [3] = { name = 'Lieutenant', payment = 125 },
            [4] = { name = 'Chief', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['realestate'] = {
        label = '부동산',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Recruit', payment = 50 },
            [1] = { name = 'House Sales', payment = 75 },
            [2] = { name = 'Business Sales', payment = 100 },
            [3] = { name = 'Broker', payment = 125 },
            [4] = { name = 'Manager', payment = 150, isboss = true, bankAuth = true },
        },
    },
    ['trucker'] = {
        label = '트럭커',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '트럭커', payment = 0 },
        },
    },
    ['judge'] = {
        label = '법원',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Judge', payment = 100 },
        },
    },
    ['vineyard'] = {
        label = '농장',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Picker', payment = 50 },
        },
    },
}