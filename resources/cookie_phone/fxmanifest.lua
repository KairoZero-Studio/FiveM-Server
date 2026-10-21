fx_version 'cerulean'
game 'gta5'

name 'cookie_phone'
description 'COOKIE phone + pro camera + gallery + emergency dispatch + AFK integration'
author 'Cookie'
version '3.4.0'

ui_page 'nui/index.html'

shared_script '@ox_lib/init.lua'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/app.js',
    'nui/wallpapers.js',
    'nui/ringtone.wav',
    'nui/ringback.wav',
    'nui/wallpapers/black.webp',
    'nui/wallpapers/white.webp',
    'nui/wallpapers/starry_night.webp',
    'nui/wallpapers/caramel_gloss.webp',
    'nui/wallpapers/pink_glass_flower.webp',
    'nui/wallpapers/cookie_bakery.webp',
    'nui/wallpapers/mint_glass.webp',
    'nui/wallpapers/lavender_aurora.webp',
}

client_script 'client/main.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'cookie_taxi',
    'cookie_mechanic',
    'ox_lib',
    'qbx_core',
    'pma-voice',
    'screencapture',
    'oxmysql'
}

dependency 'cookie_core'
