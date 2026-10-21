fx_version 'cerulean'
game 'gta5'

name 'cookie_mechanic'
author 'Cookie Server'
description 'Cookie Server - Mechanic citizen job'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
    'cookie_admin',
}

dependency 'cookie_core'
