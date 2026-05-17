-- server/detections.lua
-- Tar emot detections och skickar dem vidare till main.lua via ghostguard:alert
-- Inga bans här. Inga dubbevents. All strafflogik i main.lua.

local function s(x)
    if x == nil then return "-" end
    return tostring(x)
end

local function flag(src, aType, details)
    -- Skicka med src korrekt
    TriggerEvent("ghostguard:alert", src, s(aType), s(details))
end

-- Generic flag från client
RegisterNetEvent("ghostguard:flag", function(aType, details)
    local src = source
    flag(src, aType, details)
end)

-- Kompat: om gamla client fortfarande triggar gg:flag
RegisterNetEvent("gg:flag", function(reason)
    local src = source
    flag(src, "Flag", reason)
end)

-- Specifika detections
RegisterNetEvent("ghostguard:explosionDetected", function(details)
    local src = source
    flag(src, "Explosion", details)
end)

RegisterNetEvent("ghostguard:speedhackDetected", function(speed)
    local src = source
    flag(src, "Speedhack", "Speed: " .. s(speed))
end)

RegisterNetEvent("ghostguard:vehicleSpawned", function(model)
    local src = source
    flag(src, "Vehicle spawned", "Model: " .. s(model))
end)

RegisterNetEvent("ghostguard:godmodeDetected", function()
    local src = source
    flag(src, "Godmode", "Player had godmode")
end)

RegisterNetEvent("ghostguard:noclipDetected", function(distance)
    local src = source
    flag(src, "Noclip", "Moved " .. s(math.floor(tonumber(distance) or 0)) .. "m unnaturally")
end)
