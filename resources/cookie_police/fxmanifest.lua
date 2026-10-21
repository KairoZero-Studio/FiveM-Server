fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_police'
description 'COOKIE police/security V3.0.3 + crime restraint access'
author 'Cookie'
version '3.0.3'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

ui_page 'nui/index.html'
files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

client_scripts {
    'client/main.lua',
    'client/mdt.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/f5safe.lua',
    'server/intranet.lua',
    'server/mdt.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'cookie_core',
    'cookie_admin',
    'cookie_license',
    'cookie_crime'
}
