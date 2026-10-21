fx_version 'cerulean'
game 'gta5'

description 'KZS TAB 무기휠 ox_inventory 아이템 무기를 GTA식 원형 휠로 장착/수납'

shared_script '@ox_lib/init.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'nui/index.html'
files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

dependency 'ox_inventory'

dependency 'cookie_core'
