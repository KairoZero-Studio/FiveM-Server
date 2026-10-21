fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_esc'
description 'COOKIE ESC + driver license + criminal rankings + crime event'
author 'Cookie'
version '0.3.3'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/app.js',
    'nui/style.css'
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
