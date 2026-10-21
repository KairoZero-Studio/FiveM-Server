fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'cookie_mapmarkers'
author 'Cookie'
description 'COOKIE native map markers + custom YTD image slots'
version '1.2.0'
ui_page 'nui/index.html'
files {'nui/index.html','nui/style.css','nui/app.js'}
shared_scripts {'@ox_lib/init.lua','config.lua'}
client_scripts {'client/main.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server/main.lua'}
dependencies {'ox_lib','oxmysql','cookie_admin','cookie_mapblips'}

dependency 'cookie_core'
