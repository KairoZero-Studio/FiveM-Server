fx_version 'cerulean'
game 'gta5'
name 'cookie_store'
version '2.0.0'
description 'COOKIE unified shop - existing cookie_admin mailbox'
shared_scripts {'@ox_lib/init.lua','config.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server/main.lua'}
client_scripts {'client/main.lua'}
ui_page 'html/index.html'
files {'html/index.html','html/app.js','html/style.css'}
dependencies {'oxmysql','ox_lib','qbx_core','cookie_admin','ox_inventory'}
