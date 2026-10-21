
Config = Config or {}
Config.Labor = {}

local L = Config.Labor

L.Debug = false

-- Qbox 직업
L.Job = 'labor'
L.Skill = 'labor'
L.JobDef = {
    label = '건설 인부',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        [0] = { name = '건설 인부', payment = 0 }
    }
}

-- 플레이 설정
L.InteractRadius = 2.2
L.TaskArriveRadius = 20.0
L.BoxProp = 'prop_cs_cardbox_01'
L.FallbackBoxProp = 'prop_cardbox_01a'

-- 상자 더미 장식
L.Pile = {
    enabled = true,
    prop = 'prop_cardbox_01a',
    count = 5,
    spacing = 0.48,
    maxDrawDistance = 80.0,
}

-- 작업 기본값
L.DefaultCount = 5
L.MinCount = 1
L.MaxCount = 30
L.DefaultReward = 25000
L.MinReward = 0
L.MaxReward = 1000000
L.ExpPerBox = 1

-- 레벨 보너스. cookie_skill 설정이 따로 있으면 그 보너스를 우선 사용.
L.PayMult = { 1.00, 1.05, 1.10, 1.17, 1.25 }

L.Lines = {
    hired = '좋아. 오늘부터 건설 인부로 일하면 돼. 출근하면 작업을 바로 배정해줄게.',
    dutyOn = '출근 처리됐어. 오늘 맡을 작업을 확인해.',
    dutyOff = '오늘 일은 여기까지. 수고했어.',
    noTask = '이 작업장에는 아직 등록된 운반 작업이 없어.',
    taskAssigned = '작업이 배정됐습니다. 상자 더미에서 상자를 들고 지정된 위치로 옮기세요.',
    completed = '작업 완료! 수고했습니다.',
}
