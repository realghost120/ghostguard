-- =========================================
-- GhostGuard Anti Resource Protection
-- =========================================

local RESOURCE_NAME = GetCurrentResourceName()
local lastHeartbeat = GetGameTimer()

-- ===============================
-- 🔒 Auto-protect this resource
-- ===============================
local function sendAlert(type, resource)
    TriggerServerEvent("ghostguard:alert", type, resource or RESOURCE_NAME)
end

-- ===============================
-- 🚨 Stop detection
-- ===============================
AddEventHandler("onClientResourceStop", function(resourceName)

    -- Om GhostGuard stoppas
    if resourceName == RESOURCE_NAME then
        sendAlert("Resource Stop", RESOURCE_NAME)
        return
    end
end)

-- ===============================
-- 🚨 Restart detection
-- ===============================
AddEventHandler("onClientResourceStart", function(resourceName)

    if resourceName == RESOURCE_NAME then
        sendAlert("Resource Restart", RESOURCE_NAME)
        return
    end
end)

-- ===============================
-- 💀 Anti manual stop check loop
-- ===============================
CreateThread(function()
    while true do
        Wait(5000)

        if GetResourceState(RESOURCE_NAME) ~= "started" then
            sendAlert("Resource Tamper", RESOURCE_NAME)
        end
    end
end)

-- ===============================
-- ❤️ Heartbeat to server
-- ===============================
CreateThread(function()
    while true do
        Wait(3000)
        TriggerServerEvent("ghostguard:heartbeat")
    end
end)