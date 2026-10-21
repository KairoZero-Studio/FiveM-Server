fx_version 'cerulean'
game 'gta5'

name 'cookie_taxi'
description '쿠키서버 택시 (시민직 1호, 숙련도 기준점)'
author 'Cookie'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/dialog.lua',
    'client/hail.lua',
    'client/blip.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/hail.lua',
    'server/job.lua',
    'server/main.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

dependency 'oxmysql'
dependency 'cookie_skill'

server_script 'server/admin_pay.lua'

dependency 'cookie_admin'

dependency 'cookie_core'
