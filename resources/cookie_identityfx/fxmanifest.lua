fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'COOKIE SERVER'
description 'QBOX chat titles, overhead titles and killfeed'
version '1.0.1'

ui_page 'web/index.html'

shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

dependencies {
    'qbx_core',
    'oxmysql'
}
