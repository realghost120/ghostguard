-- =========================================
-- GhostGuard Magic Bullet Detection
-- =========================================

AddEventHandler("gameEventTriggered", function(event, data)

    if event ~= "CEventNetworkEntityDamage" then return end

    local victim = data[1]
    local attacker = data[2]
    local isFatal = data[4]

    if not victim or not attacker then return end
    if not IsPedAPlayer(victim) then return end
    if not isFatal then return end

    local victimPlayer = NetworkGetPlayerIndexFromPed(victim)
    if victimPlayer ~= PlayerId() then return end

    local attackerPlayer = NetworkGetPlayerIndexFromPed(attacker)
    if not attackerPlayer or attackerPlayer == -1 then return end

    local attackerPed = GetPlayerPed(attackerPlayer)
    if not attackerPed or attackerPed == 0 then return end

    local hasLos =
        HasEntityClearLosToEntity(attackerPed, victim, 17) or
        HasEntityClearLosToEntityInFront(attackerPed, victim)

    if not hasLos then
        TriggerServerEvent(
            "ghostguard:alert",
            "Magic Bullet",
            "No line of sight kill"
        )
    end
end)