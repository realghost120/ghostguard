local godmodeStrikes = 0
local godmodeActive = false
local lastProofTime = 0

local CHECK_INTERVAL = 1000
local REQUIRED_STRIKES = 5
local RESET_TIME = 4000

CreateThread(function()
    while true do
        Wait(CHECK_INTERVAL)

        local ped = PlayerPedId()
        local detected = false

        if ped and ped ~= 0 then

            if not IsEntityDead(ped)
            and not IsPedInAnyVehicle(ped, false)
            and not IsPauseMenuActive()
            and not IsPlayerSwitchInProgress() then

                -- Invincible check
                if GetPlayerInvincible(PlayerId()) or GetPlayerInvincible_2(PlayerId()) then
                    detected = true
                end

                -- Damage proof check
                local bulletProof, fireProof, explosionProof, collisionProof, meleeProof, steamProof, p7, drownProof =
                    GetEntityProofs(ped)

                if fireProof == 1 or explosionProof == 1 or steamProof == 1 or drownProof == 1 then
                    detected = true
                end
            end
        end

        if detected then
            godmodeStrikes = godmodeStrikes + 1
            lastProofTime = GetGameTimer()

            if godmodeStrikes >= REQUIRED_STRIKES and not godmodeActive then
                godmodeActive = true

                TriggerServerEvent(
                    "ghostguard:alert",
                    "Godmode",
                    "Invincibility detected (stable)"
                )
            end
        else
            -- Reset logik
            if (GetGameTimer() - lastProofTime) > RESET_TIME then
                godmodeStrikes = 0
                godmodeActive = false
            end
        end
    end
end)