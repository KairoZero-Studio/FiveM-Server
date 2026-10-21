fx_version 'cerulean'
game 'gta5'

name 'cookie_items'
author 'Cookie Server'
description 'COOKIE item effects - medical, armor, energy drink, newbie reward kit'
version '1.4.1'

shared_scripts {
    '@ox_lib/init.lua',
}

client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'oxmysql',
    'qbx_core',
}
