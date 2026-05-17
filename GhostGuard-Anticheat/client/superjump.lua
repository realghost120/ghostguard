CreateThread(function()
    local jumpFlags = 0
    local normalJumpHeight = 1.8 -- vanlig jump är ~1.2-1.5

    while true do
        Wait(500)

        local ped = PlayerPedId()
        if not ped or ped == 0 then goto continue end

        if IsPedInAnyVehicle(ped, false) then
            goto continue
        end

        if IsPedSwimming(ped) then
            goto continue
        end

        if IsPedJumping(ped) then
            local startZ = GetEntityCoords(ped).z
            local maxZ = startZ

            -- kolla hopp i 0.7 sek
            for i = 1, 14 do
                Wait(50)
                local z = GetEntityCoords(ped).z
                if z > maxZ then
                    maxZ = z
                end
            end

            local jumpHeight = maxZ - startZ

            if jumpHeight > normalJumpHeight then
                jumpFlags = jumpFlags + 1

                if jumpFlags >= 2 then
                    jumpFlags = 0
                    TriggerServerEvent(
                        "ghostguard:alert",
                        "Super Jump",
                        "Height: " .. math.floor(jumpHeight * 100) / 100
                    )
                end
            else
                if jumpFlags > 0 then
                    jumpFlags = jumpFlags - 1
                end
            end
        end

        ::continue::
    end
end)
