fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'COOKIE SERVER'
description 'Prevents negative cash/bank/crypto balances and repairs existing negatives'
version '1.0.0'

server_script '@oxmysql/lib/MySQL.lua'
server_script 'server/main.lua'

dependencies {
    'qbx_core',
    'oxmysql'
}
