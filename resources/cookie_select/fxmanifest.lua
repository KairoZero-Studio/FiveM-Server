fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_select'
description '쿠키서버 간편 온보딩 - 동의/별명/자동 캐릭터 생성'
author 'Cookie'
version '0.2.3'

shared_script '@ox_lib/init.lua'

client_script 'client/cl_main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua'
}

ui_page 'nui/index.html'

files {
    'nui/*',
    'nui/assets/*'
}

dependencies {
    'qbx_core',
    'cookie_core',
    'ox_lib',
    'oxmysql'
}
