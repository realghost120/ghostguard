fx_version 'cerulean'
game 'gta5'

author 'Ghost'
description 'GhostGuard Anticheat'
version '2.0.0'

lua54 'yes'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/**/*.lua'
}

-- Endast loadern körs lokalt. All övrig server-logik hämtas från backend
-- vid uppstart så kunder alltid kör senaste versionen automatiskt.
server_scripts {
    'server/loader.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'license.cfg'
}
