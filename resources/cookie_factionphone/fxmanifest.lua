fx_version 'cerulean'
game 'gta5'
name 'cookie_factionphone'
description 'COOKIE faction field tablet HUD - police/security/crime/tow'
author 'COOKIE SERVER'
version '2.0.0'
ui_page 'nui/index.html'
shared_script '@ox_lib/init.lua'
files {'nui/index.html','nui/style.css','nui/app.js'}
client_script 'client.lua'
server_scripts {'@oxmysql/lib/MySQL.lua','server.lua'}
dependencies {'ox_lib','oxmysql','qbx_core','cookie_admin','cookie_factionmenu'}
