Config = {}

Config.Enabled = true
Config.BotName = 'COOKIE LOG'
Config.AvatarURL = ''

-- =========================================================
-- 로그별 Discord Webhook URL 직접 입력
-- 아직 안 만든 항목은 '' 그대로 두면 됩니다.
-- =========================================================
Config.Webhooks = {
    trade = 'https://discord.com/api/webhooks/1544322706932105256/lwzuP4HrXqBvyFgk295aEgSmPH3nSN5ik_ZlwxY6Z_cNiHfKPhFoc47H84P9eswC7RYO',

    seize = '',
    wanted = '',
    escape = '',
    backup = '',
    report_close = '',
    warrant = '',
    fine = '',

    kick = '',
    ban = '',
    admin_call = 'https://discord.com/api/webhooks/1544323417367515177/XbiLaBNpld2pw25tapOm_N-OIAPkIM6iY_g7_yF0rks6K1QIdjBYoAxe1odPkkJxTf-K',
    admin_detention = 'https://discord.com/api/webhooks/1544323050961371216/G9tOJ7vmaCECUWGkHjsBtDcSEXJXEhpehGwCiPrlkBc7XKPfyYwKr-NNpkb0QtK5_R8U',

    police_report = 'https://discord.com/api/webhooks/1544328596020002816/EuvpdzyB4hqODOIJguItmzbJssoobfdSWk-3Nzi2TK2a2GbtYQlqN4oMrAkMQjBhIsq4',
    security_report = '',

    police_detention = '',
    security_detention = '',

    police_account = '',
    security_account = '',
}

-- =========================================================
-- 선택 기능: 여러 로그를 같은 채널로 묶고 싶을 때 사용.
-- URL 직접 입력도 지원하고 server.cfg convar 이름도 지원.
-- 개별 Config.Webhooks가 있으면 그것이 우선.
-- =========================================================
Config.WebhookGroups = {
    trade = 'cookie_log_trade',

    seize = 'cookie_log_police_work',
    wanted = 'cookie_log_police_work',
    escape = 'cookie_log_police_work',
    backup = 'cookie_log_police_work',
    report_close = 'cookie_log_police_work',
    warrant = 'cookie_log_police_work',
    fine = 'cookie_log_police_work',

    kick = 'cookie_log_admin',
    ban = 'cookie_log_admin',
    admin_call = 'cookie_log_admin',
    admin_detention = 'cookie_log_admin',

    police_report = 'cookie_log_police',
    police_detention = 'cookie_log_police',
    police_account = 'cookie_log_police',

    security_report = 'cookie_log_security',
    security_detention = 'cookie_log_security',
    security_account = 'cookie_log_security',
}

Config.Colors = {
    trade = 0x3CCB7F,
    seize = 0x9B59B6,
    wanted = 0xE74C3C,
    escape = 0xD35400,
    backup = 0xF1C40F,
    report_close = 0x95A5A6,
    warrant = 0x8E44AD,
    fine = 0xE67E22,

    kick = 0xFF7675,
    ban = 0xC0392B,
    admin_call = 0xF39C12,
    admin_detention = 0xE84393,

    police_report = 0x3498DB,
    security_report = 0x7F8C8D,

    police_detention = 0x2980B9,
    security_detention = 0x566573,

    police_account = 0x1ABC9C,
    security_account = 0x607D8B,
}

Config.StoreDatabase = true
Config.ConsoleMirror = true
Config.SendIntervalMs = 650
Config.MaxQueue = 1000
Config.IncludeIdentifiers = false
