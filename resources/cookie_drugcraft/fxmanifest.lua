fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_drugcraft'
author 'COOKIE SERVER'
version '1.0.0'
description 'COOKIE organization manufacturing + minigames'

ui_page 'nui/index.html'

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

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory',
    'oxmysql',
    'cookie_admin'
}
