RegisterNetEvent("ghostguard:flag", function(type, details)
    local src = source

    if isAdmin(src) then return end

    pushAlert(src, type, details)
    autoBanPlayer(src, type, details)
end)