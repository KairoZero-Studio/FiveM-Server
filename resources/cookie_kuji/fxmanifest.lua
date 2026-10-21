fx_version 'cerulean'
game 'gta5'

name 'cookie_kuji'
description 'COOKIE 월간 쿠지 - 유한 재고 뽑기'
author 'Cookie'
version '1.4.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'qbx_core'
}

dependency 'cookie_core'
