쿠키서버 - 이클립스 LOD 수정본

[확인 결과]
- eclipse.yft 내부 pack 이름: eclipse 정상
- eclipse_hi.yft 내부 pack 이름: eclipse_hi 정상
- YFT/YFT_HI 모두 RSC7 리소스로 정상 생성됨
- Blender에서 Fragment 이름을 eclipse로 바꿔 Export한 부분은 정상

[발견한 문제]
기존 vehicles.meta에:
<LODDistances>

라고 되어 있었음.

GTA V / FiveM vehicles.meta 필드명은 대소문자를 구분하며:
<lodDistances>

가 정상임.

이 오류 때문에 차량이 생성 직후 잠깐 보이다가
LOD 갱신 시 Drawable이 사라질 가능성이 높음.

[수정]
- LODDistances -> lodDistances 수정
- LOD 거리값 재작성
- 사용하지 않는 옛 Sentinel용 config.lua 제거
- eclipse / eclipse_hi / eclipse.ytd는 현재 업로드한 최신 파일 그대로 유지
- 최고속도 280km/h / AWD / 한정차 핸들링은 유지

[적용]
현재 서버의 Eclipse 리소스를 이 폴더로 교체한 뒤 서버 콘솔:

refresh
restart Eclipse

처음 인식시키는 경우:
refresh
ensure Eclipse

그 후:
/car eclipse

또는 관리자 차량 미리보기에서 이클립스를 테스트하세요.

[만약 이 수정본에서도 정확히 1초 뒤 사라질 경우]
그때는 eclipse_hi.yft의 Very High LOD 자체 문제일 가능성이 남습니다.
하지만 현재 파일 내부 검사상 eclipse_hi 이름과 리소스 구조는 정상으로 확인되었습니다.
