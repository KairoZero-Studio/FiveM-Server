쿠키서버 - 크라운 최종 수정본

이 파일은 사용자가 직접 업로드한 Crown.zip의 최신 모델 파일을 그대로 사용했습니다.

[실제 포함된 최신 모델]
stream/crown.yft
stream/crown_hi.yft
stream/crown.ytd

모델 파일은 수정/교체하지 않았습니다.

[이전 문제]
기존 Crown.zip은 파일명은 crown.* 였지만:
- Config.Model = 'sentinel'
- AddTextEntry('SENTINEL', ...)
- vehicles.meta 없음
상태였기 때문에 독립 차량 crown으로 로딩될 수 없는 구조였습니다.

[수정 후]
모델명/스폰명: crown
텍스처명: crown
handlingId: CROWN
인게임명: 크라운

[설치]
resources/
└─ [cookie_vehicles]/
   └─ [cookie_car_limited]/
      └─ Crown/
         ├─ fxmanifest.lua
         ├─ client.lua
         ├─ data/
         │  ├─ vehicles.meta
         │  ├─ handling.meta
         │  └─ carvariations.meta
         └─ stream/
            ├─ crown.yft
            ├─ crown_hi.yft
            └─ crown.ytd

[콘솔]
refresh
ensure Crown

이미 실행중:
restart Crown

[테스트]
/car crown

[차량관리/Qbox]
qbx_core/shared/vehicles.lua 에:

crown = {
    name = '크라운',
    brand = '',
    model = 'crown',
    price = 0,
    category = 'limited',
    type = 'automobile',
    hash = `crown`,
},

추가.

[성능]
이클립스와 동일한 베이스 핸들링.
쿠키 튜닝샵 프로필도 crown 기준으로:
0 = 180
1 = 200
2 = 220
3 = 240
4 = 260
5 = 280 km/h

[중요]
만약 /car crown 시에도 차량이 순간 나타났다 사라지거나 아예 투명하다면,
Blender/Sollumz에서 최상위 Fragment가 아직 sentinel 이름으로 export된 경우일 수 있습니다.
그 경우 파일명만 crown으로 바꾼 것이 아니라,
Fragment 이름까지 crown으로 바꿔 crown.yft/crown_hi.yft를 다시 export해야 합니다.
