🍪 COOKIE SERVER 간편 차고 V1.0.1
================================

※ 기존 cookie_garage 리소스의 코드를 직접 검사해 전체 기능을 이전한 버전이 아닙니다.
※ 메인 차고 1곳에 먼저 적용하는 독립형 대체 차고입니다.

지원:
 - 본인 소유 차량을 목록으로 표시
 - 차량 선택 즉시 생성 및 운전석 탑승
 - qbx_vehiclekeys 열쇠 지급
 - 서버 월드의 동일 번호판 차량 중복 생성 차단
 - state=0 이라도 차량이 실제로 없으면 재출고
 - 내 차량 입고 및 기존 차량 튜닝 데이터 저장
 - DB 소유 기록 삭제 및 전체 상태 초기화 없음

설치:
1. 서버 종료, DB 및 resources/[cookie]/cookie_garage 백업
2. 이 ZIP의 cookie_garage_simple 폴더를 resources/cookie_garage_simple 에 넣기
   (resources/[cookie] 안에 넣지 마세요. 시작 순서 충돌 방지)
3. server.cfg의 ensure [cookie] 다음 줄에 추가:
   stop cookie_garage
   ensure cookie_garage_simple
4. qbx_core, ox_lib, oxmysql, qbx_vehiclekeys, qbx_vehicles가 시작됐는지 확인
5. 서버 전체 재시작
6. 메인 차고 (255.23, -788.39, 31.45)에서 E로 열기

설정:
 - cookie_garage_simple/config.lua -> Config.Garages.main
 - coords 는 키를 누르는 지점
 - spawns 는 실제 빈 주차 칸으로 수정해야 하는 임시 좌표
 - 다른 차고도 Config.Garages에 추가 가능
 - Config.ShowAllOwned=true: 일반차, 한정차, Odin, noobles 등 전체 소유 차량 표시

중요:
 - 기존 차고 폴더는 삭제하지 말고 실행만 중지
 - 기존 팩션 전용 차고 / 별도 한정차 UI는 V1의 적용 범위 밖
 - 다른 리소스가 기존 cookie_garage export를 사용한다면 중지 시 해당 기능은 작동하지 않을 수 있음
 - DB state=2 압류 차량은 출고 불가
 - 실패하면 콘솔의 [cookie_garage_simple] 로그를 확인
 - 실제 FiveM 인게임 테스트 전의 1차 버전

롤백:
 server.cfg의 두 줄을 제거하고 서버 전체 재시작.
 이전 차량을 DB에 임의 일괄 변경하지 마세요.
