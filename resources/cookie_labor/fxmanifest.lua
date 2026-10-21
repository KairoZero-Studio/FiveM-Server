
fx_version 'cerulean'
game 'gta5'

name 'cookie_labor'
description 'Cookie Server - 건설 인부 시민직'
author 'Cookie'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/admin.lua',
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
    'cookie_admin',
}

dependency 'cookie_core'
