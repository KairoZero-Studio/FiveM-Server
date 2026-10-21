fx_version 'cerulean'
game 'gta5'

name 'cookie_doorlock'
description 'COOKIE SERVER persistent door lock system'
author 'Cookie'
version '1.5.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core'
}
