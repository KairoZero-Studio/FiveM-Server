fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_faction_recovery'
author 'COOKIE SERVER'
description 'Faction field phone + tow F5 recovery hotfix'
version '1.0.0'

shared_script '@ox_lib/init.lua'
client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'ox_lib',
    'qbx_core',
    'cookie_admin'
}
