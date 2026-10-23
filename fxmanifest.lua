fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aeth_txadmin'
author 'AETHRALETH'
description 'txAdmin Discord webhooks, ban role sync and configurable admin role mirror'
version '1.4.0'

server_scripts {
    'config.lua',
    'server/logger.lua',
    'server/ban_sync.lua',
    'server/relay_settings.lua'
}
