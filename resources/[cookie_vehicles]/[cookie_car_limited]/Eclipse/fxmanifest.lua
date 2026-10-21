fx_version 'cerulean'
game 'gta5'

author 'COOKIE SERVER'
description 'Eclipse limited vehicle - 280km/h performance patch'
version '1.0.0'

files {
    'data/handling.meta',
    'data/carvariations.meta',
    'data/vehicles.meta'
}

data_file 'HANDLING_FILE' 'data/handling.meta'
data_file 'VEHICLE_VARIATION_FILE' 'data/carvariations.meta'
data_file 'VEHICLE_METADATA_FILE' 'data/vehicles.meta'

client_script 'client.lua'
