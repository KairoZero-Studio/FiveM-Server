fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_newbie'
description 'COOKIE newbie townhall progression - guide/identity/license/education/verify'
author 'Cookie'
version '1.2.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
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
    'qbx_core',
    'cookie_core',
    'cookie_license'
}
