fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'cookie_garage_simple'
description 'COOKIE SERVER simple QBOX garage'
version '1.0.1'

shared_scripts {'@ox_lib/init.lua','@qbx_core/modules/lib.lua','config.lua'}
client_scripts {'client/main.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server/main.lua'}
dependencies {'ox_lib','oxmysql','qbx_core','qbx_vehiclekeys'}
