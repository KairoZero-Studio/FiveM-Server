fx_version 'cerulean'
game 'gta5'

name 'cookie_skill'
description '쿠키서버 시민직 숙련도 (공용 기반)'
author 'Cookie'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependency 'oxmysql'


dependency 'qbx_core'
