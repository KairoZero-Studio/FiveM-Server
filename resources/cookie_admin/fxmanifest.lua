fx_version 'cerulean'
game 'gta5'

name 'cookie_admin'
description '쿠키서버 관리자 패널 + 팩션 NPC HUD + 조직 NPC 기본 판매목록'
author 'Cookie'
version '14.4.1'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/world_cleanup.lua',
    'client/door_admin.lua',
    'client/npc.lua',
    'client/faction_npc.lua',
    'client/attendance.lua',
    'client/couple.lua',
    'client/title.lua',
    'client/keyguide.lua',
    'client/event.lua',
    'client/quest.lua',
    'client/mailbox.lua',
    'client/robbery.lua',
    'client/kuji.lua',
    'client/newbie.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/faction.lua',
    'server/storage.lua',
    'server/limited_inventory.lua',
    'server/ranking_admin.lua',
    'server/devmode.lua',
    'server/main.lua',
    'server/world_cleanup.lua',
    'server/starter_cleanup.lua',
    'server/attendance.lua',
    'server/couple.lua',
    'server/title.lua',
    'server/keyguide.lua',
    'server/faction_admin.lua',
    'server/intranet_catalog.lua',
    'server/faction_npc.lua',
    'server/faction_player_admin.lua',
    'server/duty_armory.lua',
    'server/nametag.lua',
    'server/npc.lua',
    'server/quest.lua',
    'server/event.lua',
    'server/playtime.lua',
    'server/economy.lua',
    'server/chatmod.lua',
    'server/news.lua',
    'server/skin.lua',
    'server/diag.lua',
    'server/mailbox.lua',
    'server/robbery_admin.lua',
    'server/kuji.lua',
    'server/health.lua',
    'server/newbie.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/faction_shop.js',
    'nui/app_labor_delivery_v2.js',
    'nui/robbery_admin.js',
    'nui/door_admin.js',
    'nui/world_cleanup.js',
    'nui/logo.png',
    'nui/img/*.png'
}

dependency 'oxmysql'
dependency 'qbx_medical'

dependency 'cookie_license'
dependency 'cookie_core'

