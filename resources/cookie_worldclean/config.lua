Config = {}

-- GTA/FiveM 기본 월드 인구 제거.
Config.RemoveAmbientPeds = true
Config.RemoveAmbientTraffic = true
Config.RemoveParkedVehicles = true
Config.DeleteExistingAmbientEntities = true

-- GTA 기본 치안/수배 제거.
Config.DisableNativePolice = true
Config.DisableWantedLevel = true

-- COOKIE가 자체 UI로 대체하는 GTA 기본 HUD 제거.
Config.HideNativeHud = true
Config.HideNativeHelpText = true

Config.HiddenHudComponents = {
    1,  -- WANTED_STARS
    2,  -- WEAPON_ICON
    3,  -- CASH
    4,  -- MP_CASH
    6,  -- VEHICLE_NAME
    7,  -- AREA_NAME
    8,  -- VEHICLE_CLASS
    9,  -- STREET_NAME
    10, -- HELP_TEXT
    11, -- FLOATING_HELP_TEXT_1
    12, -- FLOATING_HELP_TEXT_2
    13, -- CASH_CHANGE
    14, -- RETICLE
    16, -- RADIO_STATIONS
    17, -- SAVING_GAME
    20, -- WEAPON_WHEEL
}
