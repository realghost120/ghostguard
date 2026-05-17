local function safeTostring(x)
    if x == nil then return "-" end
    return tostring(x)
end


RegisterNetEvent("gg:flag")
AddEventHandler("gg:flag", function(reason)
    local src = source
    local r = safeTostring(reason)

    -- Skicka in i main.lua:s alert/autoban-system om det finns
    if GetResourceState(GetCurrentResourceName()) == "started" then
        -- main.lua har ghostguard:alert, som i sin tur kan autobanna
        TriggerEvent("ghostguard:alert", "Flag", r)
        return
    end

    -- Fallback (bör aldrig behövas)
    DropPlayer(src, "GhostGuard: " .. r)
end)

