fx_version 'cerulean'
game 'gta5'

name 'cookie_crosshair'
description '쿠키서버 조준점 커스터마이저 (무기 들었을 때만 표시, 계정 저장)'
author 'Cookie'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'nui/index.html'
files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

dependency 'oxmysql'


dependency 'qbx_core'

dependency 'cookie_core'
