local panelOpen = false

local function openPanel()
    if panelOpen then return end
    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "open" })

    -- 🔥 HÄMTA ALLT DIREKT NÄR PANELEN ÖPPNAS
    TriggerServerEvent("ghostguard:getPlayers")
    TriggerServerEvent("ghostguard:getBans")
    TriggerServerEvent("ghostguard:getLogs")
    TriggerServerEvent("ghostguard:getAlerts")
end

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close" })
end

RegisterNetEvent("ghostguard:openPanel", function()
    openPanel()
end)

RegisterNUICallback("close", function(_, cb)
    closePanel()
    cb({ ok = true })
end)

-- ================= REQUESTS FROM UI =================
RegisterNUICallback("requestPlayers", function(_, cb)
    TriggerServerEvent("ghostguard:getPlayers")
    cb({ ok = true })
end)

RegisterNUICallback("requestBans", function(_, cb)
    TriggerServerEvent("ghostguard:getBans")
    cb({ ok = true })
end)

RegisterNUICallback("requestLogs", function(_, cb)
    TriggerServerEvent("ghostguard:getLogs")
    cb({ ok = true })
end)

RegisterNUICallback("requestAlerts", function(_, cb)
    TriggerServerEvent("ghostguard:getAlerts")
    cb({ ok = true })
end)

-- ================= ACTIONS =================
RegisterNUICallback("kickPlayer", function(data, cb)
    TriggerServerEvent("ghostguard:kickPlayer", data.id, data.reason)
    cb({ ok = true })
end)

RegisterNUICallback("banPlayer", function(data, cb)
    TriggerServerEvent("ghostguard:banPlayer", data.id, data.reason, data.time)
    cb({ ok = true })
end)

RegisterNUICallback("unban", function(data, cb)
    TriggerServerEvent("ghostguard:unban", data.ban_id)
    cb({ ok = true })
end)

RegisterNUICallback("teleportTo", function(data, cb)
    TriggerServerEvent("ghostguard:teleportToPlayer", data.id)
    cb({ ok = true })
end)

RegisterNUICallback("freezePlayer", function(data, cb)
    TriggerServerEvent("ghostguard:freezePlayer", data.id)
    cb({ ok = true })
end)

RegisterNUICallback("sendDM", function(data, cb)
    TriggerServerEvent("ghostguard:sendDM", data.id, data.msg)
    cb({ ok = true })
end)

-- ================= SERVER → UI UPDATES =================
RegisterNetEvent("ghostguard:sendPlayers", function(players)
    SendNUIMessage({ action = "updatePlayers", players = players })
end)

RegisterNetEvent("ghostguard:sendBans", function(bans)
    SendNUIMessage({ action = "updateBans", bans = bans })
end)

RegisterNetEvent("ghostguard:sendLogs", function(logs)
    SendNUIMessage({ action = "updateLogs", logs = logs })
end)

RegisterNetEvent("ghostguard:sendAlerts", function(alerts)
    SendNUIMessage({ action = "updateAlerts", alerts = alerts })
end)

-- 🔥 LIVE PUSH
RegisterNetEvent("ghostguard:pushLog", function(log)
    SendNUIMessage({ action = "pushLog", log = log })
end)

RegisterNetEvent("ghostguard:pushAlert", function(alert)
    SendNUIMessage({ action = "pushAlert", alert = alert })
end)

-- ================= ADMIN TELEPORT =================
RegisterNetEvent("ghostguard:teleportAdmin", function(coords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z)
end)

-- ================= FREEZE PLAYER =================
RegisterNetEvent("ghostguard:freezeMe", function(toggle)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, toggle and true or false)
end)

-- ================= DM NOTIFICATION =================
RegisterNetEvent("ghostguard:notify", function(msg)
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, false)
end)

-- ================= ESC CLOSE =================
CreateThread(function()
    while true do
        Wait(0)
        if panelOpen and IsControlJustPressed(0, 322) then
            closePanel()
        end
    end
end)
