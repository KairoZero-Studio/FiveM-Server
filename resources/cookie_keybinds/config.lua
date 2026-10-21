Config = {}

-- 관리자 키 가이드 편집 권한.
-- cookie_admin이 실행 중이면 getEffectiveLevel export를 우선 사용합니다.
Config.AdminMinLevel = 4
Config.AllowAceFallback = true
Config.AdminAce = 'cookie.keyguide.manage'

-- 키 가이드를 여는 기본 키.
-- 기존 F3 시민/관리자 UI 버튼에서 export/event로 열 예정이면 false로 꺼도 됩니다.
Config.EnableDefaultKey = true
Config.DefaultKey = 'F10'

-- 경찰/보안국 키 가이드 공개 대상.
-- 실제 Qbox 직업명이 다르면 여기만 바꾸면 됩니다.
Config.PoliceGuideJobs = {
    'police',
    'security',
}

-- 기본 경찰 단축키 항목. DB에 최초 1회 seed되며 이후 관리자 UI 수정값은 보존됩니다.
Config.PoliceGuideItems = {
    { key='lights',   keyLabel='NUM 7',   label='경광등',        description='순찰차 경광등 ON/OFF', sort=10 },
    { key='siren',    keyLabel='NUM 8',   label='사이렌',        description='순찰차 사이렌 ON/OFF', sort=20 },
    { key='pm_mode',  keyLabel='NUM 9',   label='P.M 모드',      description='정차 명령 모드 ON/OFF', sort=30 },
    { key='pullover', keyLabel='Y',       label='차량 정차 요청', description='P.M 모드 중 앞 차량에 정차 요청', sort=40 },
    { key='cuff',     keyLabel='G',       label='수갑',           description='가까운 대상 수갑 사용/해제', sort=50 },
    { key='miranda',  keyLabel='PAGE UP', label='미란다 고지',   description='대상에게 고지하며 주변 사람에게만 표시', sort=60 },
    { key='escort',   keyLabel='H',       label='호송',           description='수갑 상태 대상 호송/해제', sort=70 },
    { key='backup',   keyLabel='F1',      label='지원 요청',      description='근무 중 경찰/보안국에 현재 위치 지원 요청', sort=80 },
}
