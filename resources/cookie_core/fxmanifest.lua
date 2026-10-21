fx_version 'cerulean'
game 'gta5'

name 'cookie_core'
description 'COOKIE core - onboarding + UI focus + event security foundation'
author 'Cookie'
version '0.7.0'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua',
    'server/sv_verify.lua',
    'server/sv_security.lua'
}

client_script 'client/ui_focus.lua'

dependency 'oxmysql'


dependency 'qbx_core'
