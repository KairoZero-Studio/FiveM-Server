fx_version 'cerulean'
game 'gta5'

name 'cookie_safezone'
description '쿠키서버 안전지대 - 박스/구 존 + 진입 배너 + 반투명/데미지 무효/발사 차단'
author 'Cookie'
version '4.6.1'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'server_convenience.lua',
    'server_jobshop.lua',
    'server_atm.lua',
}

client_script 'client.lua'

dependency 'oxmysql'
dependency 'qbx_core'
dependency 'ox_inventory'
dependency 'illenium-appearance'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
    'nui/logo.png',
}

dependency 'cookie_core'

