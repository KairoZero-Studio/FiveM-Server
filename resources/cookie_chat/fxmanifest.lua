fx_version 'cerulean'
game 'gta5'

author 'Cookie Dev'
description 'COOKIE chat V2.6 - channels/titles + always visible message window'
version '2.6.0'



shared_script 'config.lua'


client_scripts {
    'client/cl_titles.lua',
    'client/cl_always_visible.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_moderation.lua',
    'server/sv_chat.lua',
    'server/sv_join.lua',
    'server/sv_transfer.lua'
}


dependency 'qbx_core'
