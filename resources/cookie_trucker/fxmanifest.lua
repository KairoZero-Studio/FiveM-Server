fx_version 'cerulean'
game 'gta5'

name 'cookie_trucker'
description '트럭커 시민직 — 배송 작업 (택시 축 미러링)'
author 'cookie'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/admin.lua',
    'server/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

dependency 'oxmysql'
dependency 'cookie_skill'

dependency 'cookie_admin'

dependency 'cookie_core'
