fx_version 'cerulean'
game 'gta5'

author 'Cookie Dev'
description 'COOKIE HUD V3.8.3 - add stamina and oxygen below thirst and hunger, keep no-blur soft background'
version '3.8.3'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/vehicle.lua',
    'client/blips.lua',
    'client/notice.lua',
    'client/killfeed.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
    'nui/killfeed.js',
    'nui/killfeed.css',
    'nui/weapons/*.webp',
}


dependency 'qbx_core'
