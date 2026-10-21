fx_version 'cerulean'
game 'gta5'

name 'cookie_vehicleui'
author 'COOKIE SERVER'
description 'COOKIE Vehicle V3.0 - one click seat switching'
version '3.0.0'

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js'
}

shared_script 'config.lua'
client_script 'client.lua'

server_script 'server.lua'

dependency 'cookie_core'
