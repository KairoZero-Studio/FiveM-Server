fx_version 'cerulean'
game 'gta5'
name 'cookie_fishing'
description 'COOKIE SERVER - full fishing session movement lock V1.7.8'
author 'Cookie'
version '1.7.5'

ui_page 'nui/manager.html'
files { 'nui/manager.html','nui/manager.css','nui/manager.js' }
shared_scripts { '@ox_lib/init.lua','config.lua' }
client_scripts { 'client/main.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua','server/main.lua' }
dependencies {
    'cookie_core', 'ox_lib','oxmysql','ox_inventory','qbx_core','cookie_admin','cookie_safezone' }
