

fx_version 'adamant'
games { 'rdr3', 'gta5' }

author 'Cookie Dev (fork of cfx chat)'
description 'KZS 독자 채팅 Phase 1 - 서버 로직 보존 + NUI 교체(DOM 직접 조립)'
version '1.0.1'

ui_page 'nui/index.html'

client_script 'cl_chat.lua'
server_script 'sv_chat.lua'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
}

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
nui_callback_strict_mode 'true'
