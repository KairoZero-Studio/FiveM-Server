fx_version 'cerulean'
game 'gta5'

name 'cookie_casino'
description '쿠키서버 카지노 (블랙잭 + 칩 환전) qb-blackjack(MIT)/qb-casino(GPL-3) 로직 기반 QBox 재배선'
author 'Cookie'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
}
