fx_version 'cerulean'
game 'gta5'

name 'cookie_mining'
description 'COOKIE SERVER - Mining V1.4 (3-tier pickaxes, rhythm, admin zones, purity, collection)'
author 'Cookie'
version '13.8.2'


ui_page 'nui/manager.html'

files {
    'nui/manager.html',
    'nui/manager.css',
    'nui/manager.js'
}

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
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'qbx_core',
    'cookie_admin',
    'cookie_safezone'
}

dependency 'cookie_core'
