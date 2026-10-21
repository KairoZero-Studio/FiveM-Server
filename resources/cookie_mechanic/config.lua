Config = Config or {}
Config.Mechanic = {}
local M=Config.Mechanic

M.Job='mechanic'
M.Skill='mechanic'
M.JobDef={label='정비공',defaultDuty=false,offDutyPay=false,grades={[0]={name='정비공',payment=0}}}

M.CallMinDelay=15
M.CallMaxDelay=40
M.CallExpire=45
M.InteractRadius=3.2
M.ExpPerRepair=4
M.PayMult={1.00,1.05,1.10,1.16,1.23}

M.DefaultVehicle='blista'
M.DefaultPed='a_m_m_business_01'
M.DefaultRepairSeconds=12
M.DefaultEngineHealth=280.0
M.DefaultBodyHealth=650.0
M.DefaultNpcReward=70000

-- 플레이어 정비 기본 요금: 택시와 같은 단계식 거리 요금
M.PlayerPricing={
    BaseFare=10000,      -- 출장 기본요금
    FreeDist=1000.0,     -- 최초 무료 거리
    StepDist=500.0,      -- 이후 요금 거리 단위
    StepFare=3000,       -- 거리 단위당 추가
    RepairFee=30000,     -- 실제 정비 기본료
    MaxFare=250000,
}

M.Blip={sprite=446,colour=5,scale=.82}
