fx_version 'cerulean'
game 'gta5'

name 'cookie_afkzone'
description 'COOKIE SERVER - AFK Zone / 20 minute auto transfer / needs protection'
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
    'ox_lib',
    'qbx_core',
    'qbx_medical'
}

dependency 'cookie_core'
