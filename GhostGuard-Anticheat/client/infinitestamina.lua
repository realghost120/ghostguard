CreateThread(function()
    local staminaFlags = 0
    local consecutiveChecks = 0
    local sprintStart = 0
    local SPRINT_THRESHOLD = 15000 -- 15 sekunder

    while true do
        Wait(2000)

        local ped = PlayerPedId()
        if not ped or ped == 0 then goto continue end

        -- ignorera fordon & vatten
        if IsPedInAnyVehicle(ped, false) or IsPedSwimming(ped) then
            sprintStart = 0
            consecutiveChecks = 0
            goto continue
        end

        if IsPedSprinting(ped) then
            if sprintStart == 0 then
                sprintStart = GetGameTimer()
            end

            local sprintDuration = GetGameTimer() - sprintStart
            local stamina = GetPlayerSprintStaminaRemaining(PlayerId())

            if sprintDuration > SPRINT_THRESHOLD and stamina > 70 then
                consecutiveChecks = consecutiveChecks + 1

                if consecutiveChecks >= 2 then
                    staminaFlags = staminaFlags + 1

                    if staminaFlags >= 2 then
                        TriggerServerEvent("ghostguard:alert", "Infinite Stamina", "Sprint abuse")
                        staminaFlags = 0
                        consecutiveChecks = 0
                        sprintStart = 0
                    end
                end
            else
                consecutiveChecks = 0
            end
        else
            sprintStart = 0
            consecutiveChecks = 0

            if staminaFlags > 0 then
                staminaFlags = staminaFlags - 1
            end
        end

        ::continue::
    end
end)
