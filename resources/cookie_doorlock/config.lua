Config = {}

-- 관리자용 /dooradmin 최소 COOKIE 관리자 레벨.
-- cookie_admin이 실행 중이면 '관리자 근무중' 상태도 함께 확인합니다.
Config.AdminMinLevel = 3

-- cookie_admin이 없을 때 사용할 ACE 권한.
-- add_ace group.admin cookie.doorlock.admin allow
Config.AdminAce = 'cookie.doorlock.admin'

-- 관리자 근무중인 사람은 모든 문을 잠금/해제할 수 있습니다.
Config.AdminBypass = true

-- 문 생성 시 카메라로 선택 가능한 최대 거리.
Config.CaptureDistance = 8.0

-- 커스텀 YMAP/MLO에서 레이캐스트가 정적 맵 충돌만 반환할 때
-- 충돌점 주변의 CObject를 추가 탐색하는 반경.
Config.CaptureFallbackRadius = 2.25

-- 카메라 중앙 광선 주변 오브젝트 탐색 폭.
Config.CaptureRayRadius = 0.85

-- 근처 문 관리 목록 거리.
Config.AdminListDistance = 25.0

-- 일반 상호작용 거리 기본값.
Config.DefaultInteractDistance = 2.0

-- 문 잠금/해제 상호작용 연출.
-- E를 누르면 아래 시간 동안 진행 UI와 애니메이션이 재생된 뒤 실제 상태가 변경됩니다.
Config.ActionDuration = 3000
Config.ActionProgressPosition = 'bottom'
Config.ActionAnimDict = 'anim@mp_player_intmenu@key_fob@'
Config.ActionAnimClip = 'fob_click'
Config.ActionAnimFlag = 49

-- 문 엔티티를 직접 고정하는 보조 처리.
-- 일반 회전문뿐 아니라 자동문/슬라이딩문/차고문 잠금에도 사용합니다.
Config.FreezeEntityFallback = true

-- 자동문/차고문 강화 잠금 설정.
-- 자동문은 열리며 원래 좌표에서 이동할 수 있으므로 넓은 범위에서 같은 모델을 다시 찾고,
-- 잠긴 동안 등록 당시 좌표/회전으로 계속 복원하여 자동 개방을 막습니다.
Config.AutoDoorSearchRadius = 8.0
Config.AutoDoorEnforceDistance = 45.0
Config.AutoDoorEnforceInterval = 75
Config.AutoDoorPositionTolerance = 0.025

-- 열린 자동문/차고문을 잠글 때 바로 고정하지 않고 먼저 닫히게 하는 시간(ms).
Config.AutoDoorCloseBeforeLockMs = 650


-- 잠긴 문 위에 표시되는 월드 잠금 배지.
Config.LockIndicatorEnabled = true
Config.LockIndicatorDistance = 3.0
Config.LockIndicatorHeight = 0.5

Config.Text = {
    locked = '잠김',
    unlocked = '열림',
}
