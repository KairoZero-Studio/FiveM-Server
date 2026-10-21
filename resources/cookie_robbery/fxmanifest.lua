fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_robbery'
author 'Cookie Server'
description 'COOKIE RP robbery V1.7 + defeat criminal record and crime score'
version '1.7.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'qbx_core',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'cookie_admin',
    'cookie_crime'
}
