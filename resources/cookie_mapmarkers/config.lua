Config = {}
Config.AdminCommand = 'mapmarker'
Config.AdminMinLevel = 1
Config.MaxMarkers = 300
Config.DefaultSprite = 1
Config.DefaultColour = 0
Config.DefaultScale = 0.80
Config.YtdResource = 'cookie_mapblips'

-- These presets match cookie_mapblips/stream/minimap.ytd.
-- colour=0 is intentional because each custom sprite already contains its own colour.
Config.CustomImagePresets = {
    main_square   = { label = '메인광장',   sprite = 602, colour = 0, scale = 0.80, texture = 'ng_2 / 602' },
    main_garage   = { label = '메인차고',   sprite = 603, colour = 0, scale = 0.80, texture = 'ng_2 / 603' },
    security      = { label = '보안국',     sprite = 604, colour = 0, scale = 0.80, texture = 'ng_2 / 604' },
    police        = { label = '경찰서',     sprite = 605, colour = 0, scale = 0.80, texture = 'ng_2 / 605' },
    garage_area   = { label = '차고지',     sprite = 606, colour = 0, scale = 0.80, texture = 'ng_2 / 606' },
    city_hall     = { label = '시청',       sprite = 607, colour = 0, scale = 0.80, texture = 'ng_2 / 607' },

    delivery      = { label = '배달기사',   sprite = 618, colour = 0, scale = 0.80, texture = 'ng_2 / 618' },
    repair_worker = { label = '수리공',     sprite = 619, colour = 0, scale = 0.80, texture = 'ng_2 / 619' },
    convenience   = { label = '편의점',     sprite = 620, colour = 0, scale = 0.80, texture = 'ng_2 / 620' },
    bank          = { label = '은행',       sprite = 621, colour = 0, scale = 0.80, texture = 'ng_2 / 621' },
    repair_shop   = { label = '정비소',     sprite = 622, colour = 0, scale = 0.80, texture = 'ng_2 / 622' },
    taxi          = { label = '택시기사',   sprite = 623, colour = 0, scale = 0.80, texture = 'ng_2 / 623' },

    atm           = { label = 'ATM',        sprite = 636, colour = 0, scale = 0.80, texture = 'ng_2 / 636' },
    clothing      = { label = '옷장/옷가게',sprite = 637, colour = 0, scale = 0.80, texture = 'ng_2 / 637' },
    trucker       = { label = '트럭기사',   sprite = 638, colour = 0, scale = 0.80, texture = 'ng_2 / 638' },
    construction  = { label = '건설인부',   sprite = 639, colour = 0, scale = 0.80, texture = 'ng_2 / 639' },
}
