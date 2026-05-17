CreateThread(function()
    while true do
        Wait(2000)

        local ped = PlayerPedId()

        for _, weapon in ipairs(Config.BlacklistedWeapons) do
            if HasPedGotWeapon(ped, GetHashKey(weapon), false) then
                TriggerServerEvent("ghostguard:alert", "Blacklisted weapon", weapon)
                -- eller: TriggerServerEvent("gg:flag", "Blacklisted weapon: "..weapon)
            end
        end
    end
end)
