fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_garage'
description 'COOKIE Garage V5.0.0 - standalone DB garage, no qbx_garages/qbx_vehicles dependency'
author 'COOKIE SERVER'
version '5.0.0'

shared_script '@ox_lib/init.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

client_script 'client.lua'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'cookie_core'
}
