fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_interaction'
author 'Cookie'
description 'COOKIE interaction V1.3.0 + packed vehicle only secure trade'
version '1.3.0'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts { 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }

dependencies {
    'ox_lib', 'oxmysql', 'ox_inventory', 'qbx_core', 'cookie_core', 'cookie_admin', 'cookie_license'
}
