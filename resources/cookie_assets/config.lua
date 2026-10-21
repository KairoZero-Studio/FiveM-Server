Config = {}

-- furniture reward_key formats:
--   chair:prop_chair_01a  -> 설치 + 앉기 가능
--   decor:prop_table_03   -> 설치만 가능
--   prop_chair_01a        -> 하위호환: chair 로 처리
Config.Furniture = {
    RecoverEverySeconds = 60,
    RecoverHunger = 5,
    RecoverThirst = 5,
    InteractDistance = 1.65,
    PickupDistance = 2.25,
    MaxPlaceDistance = 4.0,
    RotateStep = 5.0,
    MoveStep = 0.12,
}

-- cosmetic reward_key format:
--   prop:<slot>:<drawable>:<texture>
-- examples:
--   prop:0:12:0   모자
--   prop:1:5:0    안경
-- GTA ped prop slots만 사용해서 기존 의상 component를 건드리지 않습니다.
Config.Cosmetic = {
    MaxPropSlot = 7,
}
