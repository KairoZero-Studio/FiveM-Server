fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_license'
author 'Cookie'
description 'COOKIE driver license - newbie townhall manual issue + suspension logs'
version '1.3.0'

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
