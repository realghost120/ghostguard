local lastCoords = nil
local strike = 0
local noclipActive = false

CreateThread(function()
    while true do
        Wait(1000)

        local ped = PlayerPedId()
        local shouldReset = false

        if not ped or ped == 0 then
            shouldReset = true
        elseif IsPedInAnyVehicle(ped, false)
        or IsPedFalling(ped)
        or IsPedJumping(ped)
        or IsPedInParachuteFreeFall(ped)
        or IsPedSwimming(ped) then
            shouldReset = true
        end

        if not shouldReset then
            local coords = GetEntityCoords(ped)

            if lastCoords then
                local distance = #(coords - lastCoords)

                local foundGround, groundZ =
                    GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, false)

                if foundGround then
                    local heightAboveGround = coords.z - groundZ

                    if heightAboveGround > 8.0 and distance > 10.0 then
                        strike = strike + 1

                        if strike >= 2 and not noclipActive then
                            noclipActive = true

                            TriggerServerEvent(
                                "ghostguard:alert",
                                "Noclip",
                                "Height: "..math.floor(heightAboveGround)..
                                " Distance: "..math.floor(distance)
                            )
                        end
                    else
                        shouldReset = true
                    end
                end
            end

            lastCoords = coords
        end

        if shouldReset then
            strike = 0
            noclipActive = false
        end
    end
end)