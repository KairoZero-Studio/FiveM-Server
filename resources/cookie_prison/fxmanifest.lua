fx_version 'cerulean'
game 'gta5'

name 'cookie_prison'
description 'COOKIE prison labor + release ticket'
author 'Cookie'
version '1.1.0'

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
    'ox_inventory',
    'qbx_core',
    'cookie_police'
}
