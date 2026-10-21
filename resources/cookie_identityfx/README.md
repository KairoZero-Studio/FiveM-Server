# COOKIE Identity FX v1.0.0

TURN 서버의 채팅 칭호 / 머리 위 칭호 / 킬피드 아이디어를 쿠키서버 QBOX 구조로 다시 만든 독립 리소스입니다.

## 포함 기능

- QBOX / oxmysql 전용
- 채팅 칭호
- 머리 위 칭호
- 킬피드
  - 킬러 / 피해자
  - 무기 이름
  - 헤드샷
  - 거리
  - 스킨 테마
- 유저가 보유한 칭호/스킨을 직접 장착
- 관리자 인게임 관리창
  - 칭호/킬피드 스킨 생성
  - 온라인 유저에게 지급/회수
- DB 테이블 자동 생성
- 기존 TURN vRP Proxy/Tunnel 의존성 없음
- Discord Webhook 없음

## 설치

1. cookie_identityfx 폴더 전체를 쿠키서버 resources/[cookie]/ 안에 넣습니다.
2. [cookie] 그룹을 통째로 ensure 하고 있지 않다면 server.cfg에 아래 한 줄을 추가합니다.

ensure cookie_identityfx

3. 서버를 시작하면 DB 테이블이 자동 생성됩니다. install.sql을 직접 실행할 필요는 없습니다.

## 명령어

/titles
- 본인 보유 채팅칭호 / 머리칭호 / 킬피드 스킨 장착

/cookieidentity
- 관리자 관리창

cookiegrantcosmetic [서버ID] [code]
- 서버 콘솔 또는 관리자용 직접 지급 명령

## 관리자 권한

다음 순서로 판정합니다.

1. ACE cookie.identity.admin
2. 일반 admin 계열에서 흔히 쓰는 command ACE
3. cookie_admin 리소스가 GetAdminLevel export를 제공하는 경우 LV3 이상

ACE를 직접 추가하고 싶으면 예:

add_ace group.admin cookie.identity.admin allow

## F3 연결

현재 버전은 기존 cookie_admin 파일을 강제로 수정하지 않도록 독립적으로 만들어졌습니다.
그래서 바로 사용 가능한 관리창은 /cookieidentity 입니다.

나중에 F3 버튼에 연결할 때 버튼 콜백에서 클라이언트 이벤트 한 줄만 호출하면 됩니다.

TriggerEvent('cookie_identityfx:client:openAdmin')

또는 client export:

exports.cookie_identityfx:OpenAdmin()

## 채팅이 두 번 보일 경우

config.lua:

Config.InterceptDefaultChat = false

로 변경하세요. 이는 이미 다른 커스텀 채팅 리소스가 chatMessage를 자체 처리하고 있을 때만 필요합니다.

## TURN 원본과 달라진 점

- vRP user_id 제거 → QBOX citizenid 사용
- Tunnel / Proxy 제거
- vRP 권한 제거
- 칭호를 단일 값이 아닌 "보유 → 선택 장착" 방식으로 변경
- 관리자 인게임 생성/지급/회수 추가
- 킬피드 스킨을 DB 보유형으로 변경
- 머리 칭호와 채팅 칭호를 독립적으로 장착
- 경제/아이템 지급 기능 없음: 표시 시스템만 담당
