local speedActive = false
local lastSpeedAlert = 0

local ALERT_COOLDOWN = 15000 -- 15 sek
local BAN_SPEED = 500.0
local ALERT_SPEED = 220.0

CreateThread(function()
    while true do
        Wait(1000)

        local ped = PlayerPedId()
        local shouldReset = false

        if not ped or ped == 0 then
            shouldReset = true
        elseif not IsPedInAnyVehicle(ped, false) then
            shouldReset = true
        end

        if not shouldReset then
            local vehicle = GetVehiclePedIsIn(ped, false)

            if not vehicle or vehicle == 0 then
                shouldReset = true
            else
                local speed_kmh = GetEntitySpeed(vehicle) * 3.6

                -- 🚨 Direkt ban över 500
                if speed_kmh >= BAN_SPEED then
                    TriggerServerEvent(
                        "ghostguard:alert",
                        "Speedhack",
                        "Extreme vehicle speed: "..math.floor(speed_kmh).." km/h"
                    )
                elseif speed_kmh > ALERT_SPEED then
                    local now = GetGameTimer()

                    if not speedActive and (now - lastSpeedAlert) > ALERT_COOLDOWN then
                        speedActive = true
                        lastSpeedAlert = now

                        TriggerServerEvent(
                            "ghostguard:alert",
                            "Speedhack",
                            "Vehicle speed: "..math.floor(speed_kmh).." km/h"
                        )
                    end
                else
                    shouldReset = true
                end
            end
        end

        if shouldReset then
            speedActive = false
        end
    end
end)