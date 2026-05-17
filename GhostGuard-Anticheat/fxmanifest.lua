fx_version 'cerulean'
game 'gta5'

author 'Ghost'
description 'GhostGuard Anticheat'
version '3.1.0'

lua54 'yes'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/**/*.lua'
}

server_scripts {
    'server/main.lua',
    'server/detections.lua',
    'server/punish.lua',
    'server/update.lua',
    'server/perms.lua'
}


ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    
}
