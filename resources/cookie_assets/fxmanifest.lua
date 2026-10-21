fx_version 'cerulean'
game 'gta5'

name 'cookie_assets'
description 'COOKIE KUJI furniture + cosmetic usable assets'
author 'Cookie'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'oxmysql',
    'qbx_core',
    'cookie_kuji',
    'cookie_admin'
}
