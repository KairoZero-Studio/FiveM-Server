fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'cookie_social'
author 'COOKIE SERVER'
description 'COOKIE right-side motion HUD V2 - favorites/full Scully categories/consent carry'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

dependencies {
    'ox_lib',
    'scully_emotemenu',
    'cookie_core'
}
