---Job names must be lower case (top level table key)
---@type table<string, Job>
return {
    ['delivery'] = {
        label = '배달기사',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '배달기사', payment = 0 },
        },
    },
    ['tow'] = {
        label = '견인',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [1] = { name = '정규', payment = 0 },
            [2] = { name = '간부', payment = 0 },
            [3] = { name = '회장', payment = 0 },
            [0] = { name = '수습', payment = 0 },
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
    ['lawyer'] = {
        label = '법률사무소',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Associate', payment = 50 },
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
    ['vineyard'] = {
        label = '농장',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Picker', payment = 50 },
        },
    },
    ['police'] = {
        label = '쿠키 경찰국',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [1] = { name = '경장', payment = 30000 },
            [2] = { name = '경사', payment = 40000 },
            [3] = { name = '경위', payment = 60000 },
            [4] = { name = '경감', payment = 80000 },
            [5] = { name = '서장', payment = 100000 },
            [0] = { name = '순경', payment = 20000 },
        },
    },
    ['security2'] = {
        label = '보안국',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [1] = { name = '정규', payment = 50 },
            [2] = { name = '간부', payment = 80 },
            [3] = { name = '리더', payment = 120 },
            [0] = { name = '수습', payment = 30 },
        },
    },
    ['mechanic'] = {
        label = '정비공',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '정비공', payment = 0 },
        },
    },
    ['unemployed'] = {
        label = '시민',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [0] = { name = 'Freelancer', payment = 0 },
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
    ['private2'] = {
        label = '멍텅구리',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [3] = { name = '리더', payment = 0 },
            [1] = { name = '정규', payment = 0 },
            [2] = { name = '간부', payment = 0 },
            [0] = { name = '수습', payment = 0 },
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
    ['civil'] = {
        label = '관리자들',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [3] = { name = '리더', payment = 120 },
            [1] = { name = '정규', payment = 50 },
            [2] = { name = '간부', payment = 80 },
            [0] = { name = '수습', payment = 30 },
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
    ['taxi'] = {
        label = '택시기사',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '택시기사', payment = 0 },
        },
    },
    ['crime2'] = {
        label = '적월',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [1] = { name = '정규', payment = 0 },
            [2] = { name = '간부', payment = 0 },
            [3] = { name = '만월', payment = 0 },
            [0] = { name = '수습', payment = 0 },
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
    ['trucker'] = {
        label = '트럭커',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            [0] = { name = '트럭커', payment = 0 },
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
    ['security'] = {
        label = '보안국',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [3] = { name = '리더', payment = 120 },
            [1] = { name = '정규', payment = 50 },
            [2] = { name = '간부', payment = 80 },
            [0] = { name = '수습', payment = 30 },
        },
    },
    ['private'] = {
        label = '스태프',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [3] = { name = 'ㄷ', payment = 0 },
        },
    },
    ['crime'] = {
        label = '적월',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            [3] = { name = '만월', payment = 0 },
            [1] = { name = '정규', payment = 0 },
            [2] = { name = '간부', payment = 0 },
            [0] = { name = '수습', payment = 0 },
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
}