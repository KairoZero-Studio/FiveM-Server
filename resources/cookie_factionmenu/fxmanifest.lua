fx_version '4.3.0'
game 'gta5'
lua54 'yes'

name 'cookie_factionmenu'
author 'Cookie'
description 'COOKIE F5 pharmacy + Daiso + tow + organization workflows'
version '4.2.0'

ui_page 'nui/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

client_script 'client/main.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/intranet.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'cookie_admin',
    'cookie_core',
    'cookie_police'
}
