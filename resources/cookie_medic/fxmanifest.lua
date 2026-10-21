fx_version 'cerulean'
game 'gta5'

description '쿠키서버 다운 화면 + 자가재생동기 소생 단축 시스템'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}
client_script 'client.lua'
server_script 'server.lua'

ui_page 'nui/index.html'
files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

dependency 'qbx_medical'
dependency 'ox_inventory'

dependency 'cookie_core'
