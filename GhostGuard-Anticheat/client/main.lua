local panelOpen = false

-- ================= OPEN PANEL =================
RegisterNetEvent("ghostguard:openPanel", function()
    if panelOpen then return end
    panelOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage({ action = "open" })

    -- ✅ rätt event enligt server.lua
    TriggerServerEvent("ghostguard:getPlayers")
end)

-- ================= CLOSE FROM UI =================
RegisterNUICallback("close", function(_, cb)
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
    cb("ok")
end)

-- ================= ESC CLOSE =================
CreateThread(function()
    while true do
        Wait(0)
        if panelOpen and IsControlJustPressed(0, 322) then -- ESC
            panelOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = "close" })
        end
    end
end)

-- ================= RECEIVE PLAYER LIST =================
-- ✅ rätt event enligt server.lua
RegisterNetEvent("ghostguard:sendPlayers", function(players)
    SendNUIMessage({
        action = "updatePlayers",
        players = players
    })
end)

-- ================= RECEIVE BANS/LOGS/ALERTS =================
RegisterNetEvent("ghostguard:sendBans", function(bans)
    SendNUIMessage({ action = "updateBans", bans = bans })
end)

RegisterNetEvent("ghostguard:sendLogs", function(logs)
    SendNUIMessage({ action = "updateLogs", logs = logs })
end)

RegisterNetEvent("ghostguard:sendAlerts", function(alerts)
    SendNUIMessage({ action = "updateAlerts", alerts = alerts })
end)

-- live push
RegisterNetEvent("ghostguard:pushLog", function(item)
    SendNUIMessage({ action = "pushLog", item = item })
end)

RegisterNetEvent("ghostguard:pushAlert", function(item)
    SendNUIMessage({ action = "pushAlert", item = item })
end)

-- ================= ACTION CALLBACKS FROM UI =================
RegisterNUICallback("kickPlayer", function(data, cb)
    TriggerServerEvent("ghostguard:kickPlayer", data.id, data.reason)
    cb("ok")
end)

-- ✅ server event togglar själv, behöver inget state
RegisterNUICallback("freezePlayer", function(data, cb)
    TriggerServerEvent("ghostguard:freezePlayer", data.id)
    cb("ok")
end)

RegisterNUICallback("gotoPlayer", function(data, cb)
    TriggerServerEvent("ghostguard:teleportToPlayer", data.id)
    cb("ok")
end)

RegisterNUICallback("banPlayer", function(data, cb)
    TriggerServerEvent("ghostguard:banPlayer", data.id, data.reason, data.time)
    cb("ok")
end)

RegisterNUICallback("unban", function(data, cb)
    TriggerServerEvent("ghostguard:unban", data.ban_id)
    cb("ok")
end)

RegisterNUICallback("getPlayers", function(_, cb)
    TriggerServerEvent("ghostguard:getPlayers")
    cb("ok")
end)

RegisterNUICallback("getBans", function(_, cb)
    TriggerServerEvent("ghostguard:getBans")
    cb("ok")
end)

RegisterNUICallback("getLogs", function(_, cb)
    TriggerServerEvent("ghostguard:getLogs")
    cb("ok")
end)

RegisterNUICallback("getAlerts", function(_, cb)
    TriggerServerEvent("ghostguard:getAlerts")
    cb("ok")
end)

RegisterNetEvent("ghostguard:openPanel", function()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "open"
    })
end)

RegisterNUICallback("close", function(_, cb)
    SetNuiFocus(false, false)
    cb("ok")
end)









-- ================= TELEPORT ADMIN =================
-- ✅ matchar server.lua
RegisterNetEvent("ghostguard:teleportAdmin", function(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false, false)
end)

-- ================= FREEZE ME =================
-- ✅ matchar server.lua
RegisterNetEvent("ghostguard:freezeMe", function(state)
    FreezeEntityPosition(PlayerPedId(), state == true)
end)

-- ================= NOTIFY =================
RegisterNetEvent("ghostguard:notify", function(text)
    -- enkel fallback-notis om du inte har egen notify
    TriggerEvent("chat:addMessage", { args = { "GhostGuard", tostring(text) } })
end)


-- ================= ADVANCED NOCLIP DETECTION =================
CreateThread(function()
    local lastCoords = nil
    local violationCount = 0

    while true do
        Wait(1000)

        local ped = PlayerPedId()

        if not IsPedInAnyVehicle(ped, false) and not IsPedFalling(ped) and not IsPedRagdoll(ped) then
            local coords = GetEntityCoords(ped)
            local speed = GetEntitySpeed(ped)
            local collision = GetEntityCollisionDisabled(ped)

            if lastCoords then
                local distance = #(coords - lastCoords)

                -- 🚨 Suspicious movement
                if collision or distance > 15.0 then
                    violationCount = violationCount + 1
                else
                    violationCount = 0
                end

                -- 🛑 Only trigger after multiple violations
                if violationCount >= 3 then
                    TriggerServerEvent("ghostguard:noclipDetected", {
                        distance = distance,
                        speed = speed
                    })
                    violationCount = 0
                end
            end

            lastCoords = coords
        end
    end
end)

-- ================= GHOSTGUARD SPEED CLIENT =================
CreateThread(function()
    while true do
        Wait(1000)

        local ped = PlayerPedId()

        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            local speed = GetEntitySpeed(vehicle) * 3.6

            if speed > 300 then -- ändra om du vill
                TriggerServerEvent("ghostguard:speedFlag", speed)
            end
        end
    end
end)



