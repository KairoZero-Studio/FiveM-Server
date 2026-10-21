fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'COOKIE SERVER'
description 'COOKIE Discord Logs V2.3 - direct config webhook support'
version '2.3.0'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql',
    'qbx_core',
    'cookie_core'
}
