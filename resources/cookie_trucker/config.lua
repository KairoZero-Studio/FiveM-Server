

Config = Config or {}
Config.Trucker = {}

Config.Trucker.Debug = false

Config.Trucker.Job   = 'trucker'
Config.Trucker.Skill = 'trucker'

Config.Trucker.JobDef = {
    label = '트럭커',
    defaultDuty = false,
    offDutyPay = false,
    grades = { [0] = { name = '트럭커', payment = 0 } },
}

Config.Trucker.Truck = { model = 'pounder', label = '파운더' }
Config.Trucker.PlatePrefix = 'TRUCK'
Config.Trucker.SpawnOffset = 6.0
Config.Trucker.GhostSeconds = 5
Config.Trucker.GhostAlpha = 160
Config.Trucker.SpawnOutlineSeconds = 10

Config.Trucker.ArriveRadius   = 15.0
Config.Trucker.ReturnRadius   = 6.0
Config.Trucker.InteractRadius = 2.6
Config.Trucker.TrunkOffset    = -4.6
Config.Trucker.BoxProp        = 'prop_cardbox_01a'

Config.Trucker.Cargo = {
    PerLevel = 15,
    PriceMin = 315,
    PriceMax = 450,
}

Config.Trucker.PerKmReward = 500

Config.Trucker.BasePay = 8000
Config.Trucker.PerKm   = 1500
Config.Trucker.ExpPerDelivery = 1
Config.Trucker.MaxPay  = 300000

Config.Trucker.ClaimCooldown = 300

Config.Trucker.Origin = vec3(1208.5, -3113.9, 5.5)

Config.Trucker.Lines = {
    greet    = '어이, 배송 일 찾아왔나? 배송 업무라면 얼마든지 시켜주지. 근데, 얼빵하게 굴면 해고야. 알겠어?',
    hired    = '좋아, 오늘부터 자네도 트럭커야. 출근하고 배송을 골라.',
    quit     = '수고했어. 트럭은 두고 가고.',
    dutyOn   = '출근했군. 배송 목록을 확인해.',
    dutyOff  = '퇴근이군. 트럭은 회수하겠네.',
    needHire = '먼저 트럭커로 취업해야지.',
    needDuty = '출근부터 하게.',
    called   = '트럭을 불렀어. 밖에 세워뒀네.',
    acceptGo = '배송을 수락했습니다. 트럭에 재고를 채우러 가세요',
    spawnWarn= '안전운전을 기원하네, 차 다치게 하면 너도 다칠줄 알아!',
    goStock  = '재고지로 이동하시오.',

    atStock  = '차량에서 하차하고 재고를 올려 넣으세요!',
    loadingGo= '차량에 물건을 싣고 있습니다. 계속하세요',
    loadDone = '모든 재고가 트렁크에 채워졌습니다.',
    toDeliver= '재고 박스를 이제 배송합니다. 이동하세요',
    atDest   = '차량에서 하차하고 트렁크에 재고를 내리세요',
    allUnload= '운송작업이 모두 완료되었습니다. 운송지역으로 복귀하세요!',
}
