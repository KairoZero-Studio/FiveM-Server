Config = {}

Config.AllowedFactionTypes = { police = true, security = true }
Config.RequireDuty = true
Config.TargetDistance = 2.8
Config.PullOverDistance = 48.0
Config.PMRadarRefreshMs = 100
Config.MirandaRadius = 12.0
Config.BackupBlipSeconds = 35

Config.Keys = {
    lights = 'NUMPAD7',
    siren = 'NUMPAD8',
    pm = 'NUMPAD9',
    pullOver = 'Y',
    cuff = 'G',
    miranda = 'PAGEUP',
    escort = 'H',
    backup = 'F1',
}

Config.MirandaText =
    '당신은 묵비권을 행사할 수 있으며, 진술은 법정에서 불리하게 사용될 수 있습니다. ' ..
    '변호인의 조력을 받을 권리가 있으며, 이를 이해하셨습니까?'

Config.Detention = {
    teleport = true,
    jail = { x = 1690.63, y = 2591.91, z = 45.56, h = 178.0 },
    release = { x = 1847.12, y = 2586.05, z = 45.67, h = 269.0 },
    maxMinutes = 720,
}

-- 수배/도주는 모두 '시간제 추격전'이다.
Config.Chase = {
    -- V3: 추격 시간은 고정. F5에서 임의 시간 입력을 받지 않는다.
    wantedMinutes = 30,
    escapeMinutes = 20,
    appearanceMinutes = 10,
    pmAutoCount = 4,       -- P.M 정차 요청 3회 초과 = 4번째에 자동 도주
    -- 같은 대상에 대한 정차 요청은 시간으로 초기화하지 않는다.
}

-- 영장은 개인이 아니라 팩션/조직 대상으로 발부한다.
-- 기본값: 사설팩션(private), 범죄팩션(crime)
-- 필요 시 civil/security 등 타입을 true로 추가하면 F5 목록에 노출된다.
Config.WarrantTargetTypes = {
    private = true,
    crime = true,
}

Config.MDT = {
    maxSearchResults = 30,
    recentRows = 50,
    maxFine = 50000000,
    maxWarrantMinutes = 43200,
}


-- COOKIE 경찰청/보안국 공식 죄목표.
-- fine 단위는 실제 원화 값, jail/license 단위는 분.
-- 여러 죄목 선택 시 면허정지는 합산하되 최종 60분을 넘지 않습니다.
Config.PenaltyBailPerMinute = 100000
Config.PenaltyLicenseMaxMinutes = 60

Config.PenaltyCatalog = {
    -- 교통 범죄
    { id='traffic_signal', category='교통 범죄', label='신호위반', desc='교통신호를 위반한 행위', fine=50000, jail=0, license=0, score=1 },
    { id='traffic_centerline', category='교통 범죄', label='중앙선 침범', desc='중앙선을 침범한 행위', fine=50000, jail=0, license=5, score=2 },
    { id='traffic_illegal_parking', category='교통 범죄', label='불법 주정차', desc='도로에 불법 주차를 한 행위', fine=50000, jail=0, license=0, score=1 },
    { id='traffic_noise', category='교통 범죄', label='소음공해', desc='경적 및 차량소음을 반복적으로 일으킨 행위', fine=50000, jail=0, license=0, score=1 },
    { id='traffic_speed', category='교통 범죄', label='과속', desc='국도 140km/h, 고속도로 200km/h 이상으로 주행한 행위', fine=50000, jail=0, license=10, score=2 },
    { id='traffic_sidewalk', category='교통 범죄', label='인도주행', desc='인도에 차량 바퀴가 올라간 상태로 주행한 행위', fine=50000, jail=0, license=5, score=2 },
    { id='traffic_abandon', category='교통 범죄', label='차량 방치', desc='차량을 도로에 방치하고 이탈한 경우', fine=50000, jail=0, license=0, score=1 },
    { id='traffic_stunt', category='교통 범죄', label='스턴트', desc='차량의 바퀴가 2개 이상 뜬 행위', fine=50000, jail=0, license=10, score=3 },
    { id='traffic_wrongway', category='교통 범죄', label='역주행', desc='반대 차선으로 주행한 행위', fine=50000, jail=0, license=15, score=3 },
    { id='traffic_reckless', category='교통 범죄', label='난폭 운전', desc='위 교통 범죄를 2가지 이상 저지른 경우', fine=200000, jail=10, license=20, score=6 },
    { id='traffic_racing', category='교통 범죄', label='폭주', desc='차량의 속도가 300km/h 이상으로 주행한 행위', fine=200000, jail=10, license=30, score=8 },
    { id='traffic_unlicensed', category='교통 범죄', label='무면허 운전', desc='운전면허가 정지된 상태에서 주행한 행위', fine=300000, jail=10, license=60, score=10 },
    { id='traffic_hitrun', category='교통 범죄', label='뺑소니', desc='교통사고 발생 후 필요한 조치 없이 현장을 이탈한 행위', fine=300000, jail=20, license=45, settlement=true, note='합의 가능', score=12 },
    { id='traffic_checkpoint_refusal', category='교통 범죄', label='검문 불응', desc='단속 중 경찰청/보안국의 검문에 불응한 행위', fine=200000, jail=20, license=20, score=8 },
    { id='traffic_stop_refusal', category='교통 범죄', label='정지 명령 불응', desc='정지 요청 2회를 받은 상태에서 계속 차량을 주행한 행위', fine=200000, jail=20, license=30, score=8 },
    { id='traffic_flee', category='교통 범죄', label='도주', desc='차량을 타고 경찰청/보안국에게 도망친 행위', fine=500000, jail=30, license=60, score=15 },
    { id='traffic_retaliation', category='교통 범죄', label='보복 운전', desc='다른 사람의 차량에게 보복을 하며 주행한 행위', fine=300000, jail=15, license=30, settlement=true, note='합의 가능', score=10 },
    { id='traffic_dui', category='교통 범죄', label='음주운전', desc='술 또는 마약을 먹거나 마신 상태에서 운전한 행위', fine=150000, jail=10, license=60, score=12 },

    -- 폭력 범죄
    { id='violent_assault', category='폭력 범죄', label='폭행', desc='타인을 때려 체력을 감소시킨 행위', fine=200000, jail=10, license=0, settlement=true, note='합의 가능', score=8 },
    { id='violent_special_assault', category='폭력 범죄', label='특수 폭행', desc='타인을 무기로 때려 체력을 감소시킨 행위', fine=200000, jail=10, license=0, settlement=true, note='합의 가능', score=12 },
    { id='violent_group_assault', category='폭력 범죄', label='집단 폭행', desc='다수가 타인을 때려 체력을 감소시킨 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능', score=15 },
    { id='violent_confinement', category='폭력 범죄', label='감금', desc='타인의 자유를 제한하거나 가둔 행위', fine=200000, jail=20, license=0, settlement=true, note='합의 가능', score=12 },
    { id='violent_threat', category='폭력 범죄', label='협박', desc='폭행·살인 등의 위협으로 공포심을 유발한 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능', score=10 },
    { id='violent_hostage', category='폭력 범죄', label='인질극', desc='타인을 인질로 삼아 요구사항을 강요한 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능', score=20 },
    { id='violent_kidnap', category='폭력 범죄', label='납치', desc='타인의 동의 없이 강제로 특정 장소로 이동시킨 행위', fine=200000, jail=20, license=0, settlement=true, note='합의 가능', score=18 },
    { id='violent_attempted_murder', category='폭력 범죄', label='살인미수', desc='타인을 살인하려고 시도한 행위', fine=600000, jail=25, license=0, settlement=true, note='합의 가능', score=30 },
    { id='violent_murder', category='폭력 범죄', label='살인', desc='타인을 죽인 행위', fine=1000000, jail=40, license=0, settlement=true, note='합의 가능', score=45 },
    { id='violent_stalking', category='폭력 범죄', label='스토킹', desc='특정인을 지속적으로 따라다니거나 괴롭힌 행위', fine=200000, jail=20, license=0, settlement=true, note='합의 가능', score=8 },
    { id='violent_joint_murder', category='폭력 범죄', label='공동 살인', desc='2인 이상이 계획하여 타인을 죽인 행위', fine=1200000, jail=60, license=0, settlement=true, note='합의 가능', score=55 },
    { id='violent_murder_instigation', category='폭력 범죄', label='살인 교사', desc='살인을 지시하거나 의뢰한 행위', fine=1300000, jail=60, license=0, settlement=true, note='합의 가능', score=50 },
    { id='violent_assault_instigation', category='폭력 범죄', label='폭행 교사', desc='타인에게 폭행을 지시한 행위', fine=300000, jail=15, license=0, settlement=true, note='합의 가능', score=12 },

    -- 재산 범죄
    { id='property_vehicle_theft', category='재산 범죄', label='차량 절도', desc='타인의 차량을 빼앗은 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=12 },
    { id='property_robbery', category='재산 범죄', label='강도', desc='타인을 위협하며 재산을 빼앗은 행위', fine=500000, jail=25, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=15 },
    { id='property_armed_robbery', category='재산 범죄', label='특수 강도', desc='무기를 사용하여 타인을 위협하며 재산을 빼앗은 행위', fine=700000, jail=30, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=22 },
    { id='property_fraud', category='재산 범죄', label='사기', desc='기망행위로 재산상 이득을 취한 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=10 },
    { id='property_extortion', category='재산 범죄', label='공갈', desc='협박을 통해 금품을 요구한 행위', fine=500000, jail=25, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=15 },
    { id='property_damage', category='재산 범죄', label='재물손괴', desc='타인의 차량이나 재산을 파손한 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=8 },
    { id='property_business_obstruction', category='재산 범죄', label='업무방해', desc='타인의 정상적인 업무를 방해한 행위', fine=200000, jail=20, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=6 },
    { id='property_nonpayment', category='재산 범죄', label='무전취식', desc='거래를 하고 금액을 지불하지 않은 행위', fine=500000, jail=30, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=5 },
    { id='property_trespass', category='재산 범죄', label='건조물 침입', desc='정당한 사유 없이 사유지에 침입한 행위', fine=200000, jail=10, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=5 },
    { id='property_privacy_leak', category='재산 범죄', label='개인정보 유출', desc='타인의 개인정보를 무단으로 공개한 행위', fine=500000, jail=30, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=10 },
    { id='property_impersonation', category='재산 범죄', label='사칭', desc='타인의 신분을 사칭하여 활동한 행위', fine=300000, jail=20, license=0, settlement=true, note='합의 가능 · 피해자에게 입힌 손해 전액 복구', score=8 },

    -- 불법 소지품 범죄
    { id='illegal_possession', category='불법 소지품 범죄', label='불법 무기/물건 소지', desc='허가받지 않은 무기/물건을 소지한 행위', fine=100000, jail=5, license=0, score=8 },
    { id='illegal_use', category='불법 소지품 범죄', label='불법 무기 사용', desc='허가받지 않은 무기/물건을 사용한 행위', fine=300000, jail=10, license=0, score=15 },
    { id='illegal_mass_shooting', category='불법 소지품 범죄', label='총기 난사', desc='다수의 사람에게 무차별적으로 총기를 사용한 행위', fine=1000000, jail=40, license=0, note='조직 제외', score=45 },
    { id='illegal_trade', category='불법 소지품 범죄', label='불법 무기/물건 거래', desc='무기/물건을 판매 또는 거래한 행위', fine=500000, jail=20, license=0, score=20 },
    { id='illegal_weapon_hide', category='불법 소지품 범죄', label='총기 은닉', desc='불법 총기를 숨겨놓은 행위', fine=500000, jail=20, license=0, score=15 },

    -- 공무원 범죄
    { id='public_obstruction', category='공무원 범죄', label='공무 집행 방해', desc='공무원의 정당한 업무를 방해한 행위', fine=300000, jail=30, license=0, score=10 },
    { id='public_assault', category='공무원 범죄', label='공무원 폭행', desc='공무원을 폭행한 행위', fine=500000, jail=40, license=0, score=20 },
    { id='public_murder', category='공무원 범죄', label='공무원 살인', desc='공무원을 살해한 행위', fine=1200000, jail=50, license=0, score=50 },
    { id='public_impersonation', category='공무원 범죄', label='공무원 사칭', desc='공무원인 것처럼 사칭한 행위', fine=300000, jail=30, license=0, score=15 },
    { id='public_false_report', category='공무원 범죄', label='허위 신고', desc='고의로 거짓 신고를 접수한 행위', fine=300000, jail=30, license=0, score=8 },
    { id='public_deception', category='공무원 범죄', label='공무원 기만', desc='허위 진술 및 증거 조작으로 공무원을 속인 행위', fine=300000, jail=30, license=0, score=12 },
    { id='public_resist_arrest', category='공무원 범죄', label='체포 저항', desc='체포 과정에서 물리적으로 저항한 행위', fine=300000, jail=20, license=0, score=12 },
    { id='public_perjury', category='공무원 범죄', label='위증', desc='수사 과정에서 허위 진술을 한 행위', fine=300000, jail=20, license=0, score=10 },
    { id='public_confinement', category='공무원 범죄', label='공무원 감금', desc='공무원을 감금한 행위', fine=700000, jail=40, license=0, score=25 },
    { id='public_kidnap', category='공무원 범죄', label='공무원 납치', desc='공무원을 납치한 행위', fine=700000, jail=40, license=0, score=30 },
    { id='public_vehicle_theft', category='공무원 범죄', label='공무원 차량절도', desc='공무원의 차량을 절도한 행위', fine=1000000, jail=50, license=0, score=25 },
    { id='public_vehicle_damage', category='공무원 범죄', label='공무원 차량파손', desc='공무원의 차량을 파손한 행위', fine=300000, jail=30, license=0, score=15 },
}
