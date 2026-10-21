fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_tuningshop'
author 'COOKIE SERVER'
description 'COOKIE indoor tuning shop V2 - repair, paint, performance, lights, wheels, extras'
version '2.0.0'

ui_page 'nui/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core'
}

dependency 'cookie_core'
