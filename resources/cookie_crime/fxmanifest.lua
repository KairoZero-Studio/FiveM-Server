fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_crime'
author 'Cookie'
description 'COOKIE criminal record, crime score and ranking V1'
version '1.0.0'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql',
    'qbx_core',
    'cookie_core'
}
