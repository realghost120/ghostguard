local admins = {}
local GhostGuardActive = false

local logs   = {}
local alerts = {}

local frozenPlayers = {} -- [playerId] = true/false

local CONFIG = {
    adminFile = "admins.json",
    maxLogs = 300,
    maxAlerts = 150,

    -- LOG SETTINGS
    logChat = false,
    logEntityCreates = true,
    logExplosions = true,

    -- SPAM DETECTION (entityCreating)
    vehicleCreateWindowMs = 8000,
    vehicleCreateMax = 18,       -- höjd från 10 för färre false positives
    vehicleGraceMs = 60000,      -- ignorera vehicle spam första 60s efter join

    -- ✅ AUTOBAN SETTINGS
    autoBan = true,

    -- anti abuse: max alerts per typ per 10 sek
    alertRateWindowMs = 10000,
    alertRateMax = 8,

    -- per typ: strikes + duration + reason
    punish = {
        ["Vehicle spawn spam"] = { strikes = 2, duration = "P", reason = "Vehicle spawn spam" },
        ["Explosion"]          = { strikes = 1, duration = "P", reason = "Explosion event" },

        ["Flag"]               = { strikes = 1, duration = "P", reason = "GhostGuard Flag" },
        ["Speedhack"] = { strikes = 1, duration = "P", reason = "Speedhack" },
        ["Godmode"]            = { strikes = 1, duration = "P", reason = "Godmode" },
        ["Noclip"]             = { strikes = 1, duration = "P", reason = "Noclip" },
        ["Super Jump"] = { strikes = 1, duration = "P", reason = "Super Jump" },
        ["Resource Stop"] = { strikes = 1, duration = "P", reason = "Resource Stop" },
        ["Resource Restart"] = { strikes = 1, duration = "P", reason = "Resource Restart" },
        ["Magic Bullet"] = { strikes = 1, duration = "P", reason = "Magic Bullet" },
        ["Infinite Stamina"] = { strikes = 1, duration = "P", reason = "Infinite Stamina" },

        ["Vehicle spawned"]    = { strikes = 3, duration = "P", reason = "Suspicious vehicle spawning" },
        -- ["Blacklisted weapon"] = { strikes = 1, duration = "7d", reason = "Blacklisted weapon" },
    },
}






-- ========= TIME HELPERS =========
local function nowISO() return os.date("!%Y-%m-%dT%H:%M:%SZ") end
local function nowPretty() return os.date("%Y-%m-%d %H:%M:%S") end

-- ========= JOIN TRACKING (grace) =========
local joinTime = {} -- [src]=GetGameTimer()

local function inGrace(src)
    local t = joinTime[src]
    if not t then return true end
    return (GetGameTimer() - t) < CONFIG.vehicleGraceMs
end

-- ========= JSON HELPERS =========
local function loadJson(file)
    local raw = LoadResourceFile(GetCurrentResourceName(), file)
    if raw and raw ~= "" then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    return {}
end


-- ========= LOADERS =========
local function loadAdmins()
    admins = loadJson(CONFIG.adminFile)
    local count = 0
    if type(admins) == "table" then
        for _ in pairs(admins) do count = count + 1 end
    end
    print(("^2GhostGuard: Admins loaded (%s)^0"):format(count))
end



-- ========= IDENTIFIERS =========
local function getIdentifiers(src)
    local ids = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        ids[#ids+1] = GetPlayerIdentifier(src, i)
    end
    return ids
end

local function bestIdentifier(src)
    local ids = getIdentifiers(src)
    for _, id in ipairs(ids) do
        if id:find("steam:") == 1 then return id end
    end
    for _, id in ipairs(ids) do
        if id:find("license:") == 1 then return id end
    end
    return ids[1] or "-"

end

local function isAdmin(src)
    local ids = getIdentifiers(src)
    if type(admins) ~= "table" then return false end

    for _, id in ipairs(ids) do
        if id:sub(1,8) == "discord:" then
            if admins[id] == true then
                return true
            end
        end
    end

    return false
end




-- ========= LIVE PUSH HELPERS =========
local function pushToAdmins(evName, payload)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and isAdmin(src) then
            TriggerClientEvent(evName, src, payload)
        end
    end
end

-- ========= LOG + ALERT =========
local function pushLog(title, meta, line)
    local item = {
        time = nowPretty(),
        title = title or "Log",
        meta = meta or "",
        line = ("[%s] %s"):format(nowPretty(), line or title or "Log")
    }
    table.insert(logs, 1, item)
    if #logs > CONFIG.maxLogs then logs[#logs] = nil end
    pushToAdmins("ghostguard:pushLog", item)
end

local function sendLogToBackend(title, meta, line)
    if not Config or not Config.BackendURL then return end
    PerformHttpRequest(Config.BackendURL .. "/api/server/log", function(code, _)
        -- debug valfritt
    end, "POST", json.encode({
        license_key = Config.LicenseKey,
        type = "log",
        title = title,
        meta = meta,
        message = line
    }), { ["Content-Type"] = "application/json" })
end

local function pushAlert(src, aType, details)
    local name = GetPlayerName(src) or ("ID "..tostring(src))
    local ident = bestIdentifier(src) or "-"

    local item = {
        time = nowPretty(),
        id = src,
        name = name,
        identifier = ident,
        type = aType or "Unknown",
        details = details or "-"
    }

    table.insert(alerts, 1, item)
    if #alerts > CONFIG.maxAlerts then alerts[#alerts] = nil end
    pushToAdmins("ghostguard:pushAlert", item)
end

-- =========================
-- GhostGuard FiveM Log Engine (Backend logs)
-- =========================
local GG_LOG = {
    enabled = true,
    sendToBackend = true,
    rateMs = 800,
    includeIP = false,
}

local _ggLast = {}

local function ggCanLog(key, ms)
    local now = GetGameTimer()
    ms = ms or GG_LOG.rateMs
    if _ggLast[key] and (now - _ggLast[key]) < ms then return false end
    _ggLast[key] = now
    return true
end

local function ggIdMap(src)
    local out = {}
    for _, v in ipairs(getIdentifiers(src)) do
        if v:sub(1,8) == "license:" then out.license = v
        elseif v:sub(1,6) == "steam:" then out.steam = v
        elseif v:sub(1,8) == "discord:" then out.discord = v
        elseif v:sub(1,6) == "fivem:" then out.fivem = v
        elseif v:sub(1,4) == "xbl:" then out.xbl = v
        elseif v:sub(1,5) == "live:" then out.live = v
        end
    end
    return out
end

local function ggMeta(src)
    return {
        server_id = src,
        name = GetPlayerName(src) or ("ID "..tostring(src)),
        best_id = bestIdentifier(src) or "-",
        identifiers = ggIdMap(src),
    }
end

local function ggSend(level, type_, title, message, meta)
    if not GG_LOG.enabled then return end
    if not GG_LOG.sendToBackend then return end
    if not Config or not Config.BackendURL then return end
    if not Config.LicenseKey then return end

    -- rate-limit per type+player (om meta har server_id)
    local key = ("%s:%s"):format(type_ or "type", meta and meta.server_id or "0")
    if not ggCanLog(key, GG_LOG.rateMs) then return end

    PerformHttpRequest(
        Config.BackendURL .. "/api/server/log",
        function(code, _)
            -- debug valfritt
        end,
        "POST",
        json.encode({
            license_key = Config.LicenseKey,
            level = level,
            type = type_,
            title = title,
            message = message,
            meta = meta
        }),
        { ["Content-Type"] = "application/json" }
    )
end

-- ========= BAN SYSTEM =========
local function parseBanDuration(input)
    if not input or input == "" then return nil, "Missing duration" end
    local s = tostring(input):lower():gsub("%s+", "")

    if s == "p" or s == "perm" or s == "permanent" then
        return 0, nil -- 0 = permanent
    end

    local num, unit = s:match("^(%d+)([mhd])$")
    if not num or not unit then
        return nil, "Invalid duration. Use 30m, 2h, 5d or P."
    end

    num = tonumber(num)
    if num <= 0 then return nil, "Invalid duration number" end
    if unit == "m" then return num * 60, nil end
    if unit == "h" then return num * 60 * 60, nil end
    if unit == "d" then return num * 24 * 60 * 60, nil end
    return nil, "Invalid duration unit"
end

local function addBan(target, reason, durationStr, byName)
    local ids = getIdentifiers(target)
    local seconds, err = parseBanDuration(durationStr)
    if err then return false, err end

    local banId    = ("GG-%d-%d"):format(os.time(), math.random(1000, 9999))
    local nowUnix  = os.time()
    local expiresAt = nil

    if seconds ~= 0 then
        expiresAt = os.date("!%Y-%m-%dT%H:%M:%SZ", nowUnix + seconds)
    end

    local entry = {
        ban_id      = banId,
        name        = GetPlayerName(target) or ("ID "..tostring(target)),
        reason      = reason or "No reason",
        created_at  = nowISO(),
        expires_at  = expiresAt,
        by          = byName or "GhostGuard",
        identifiers = ids,
    }

    if Config and Config.BackendURL and Config.LicenseKey then
        PerformHttpRequest(
            Config.BackendURL .. "/api/server/ban",
            function(code)
                if code ~= 200 then
                    print(("^1[GhostGuard] Ban backend error: %d^0"):format(code))
                end
            end,
            "POST",
            json.encode({
                license_key = Config.LicenseKey,
                ban_id      = entry.ban_id,
                player      = target,
                player_name = entry.name,
                identifiers = entry.identifiers,
                reason      = reason,
                duration    = durationStr,
                banned_by   = byName or "GhostGuard(Auto)",
                created_at  = entry.created_at,
                expires_at  = entry.expires_at,
            }),
            { ["Content-Type"] = "application/json" }
        )
    end

    return true, entry
end

local function removeBan(ban_id)
    if not Config or not Config.BackendURL or not Config.LicenseKey then
        return false
    end
    PerformHttpRequest(
        Config.BackendURL .. "/api/server/unban",
        function(code)
            print(("[GhostGuard] Unban backend: %d"):format(code))
        end,
        "POST",
        json.encode({
            license_key = Config.LicenseKey,
            ban_id      = tostring(ban_id),
        }),
        { ["Content-Type"] = "application/json" }
    )
    return true
end


-- ========= INIT =========
CreateThread(function()
    math.randomseed(os.time())
    loadAdmins()
    pushLog("System", "Boot", "GhostGuard server started")
end)

RegisterCommand("gac_reloadadmins", function()
    loadAdmins()
    pushLog("Admin", "Reload", "Admins reloaded")
end, true)

-- ========= LICENSE CHECK =========
local function getServerHWID()
    local hwid = GetConvar("sv_licenseKey", "")
    if hwid == "" then
        hwid = GetConvar("sv_hostname", "unknown") .. ":" .. GetConvar("sv_endpointPrivacy", "0")
    end
    return hwid
end

local function checkLicenseOnce(cb)
    local url = Config.BackendURL .. "/api/license/verify"

    PerformHttpRequest(url, function(code, response)
        if code ~= 200 or not response then
            cb(false, "offline")
            return
        end

        local ok, data = pcall(json.decode, response)
        if not ok or type(data) ~= "table" then
            cb(false, "invalid_response")
            return
        end

        if data.valid == true and data.payload and data.signature then
            cb(true, "approved", data)
        else
            cb(false, data.reason or "denied")
        end
    end,
    "POST",
    json.encode({
        license_key = Config.LicenseKey,
        hwid = getServerHWID(),
    }),
    { ["Content-Type"] = "application/json" })
end

local failedVerifications = 0
local MAX_FAILED_BEFORE_SHUTDOWN = 3

local function shutdownAnticheat(reason)
    GhostGuardActive = false
    print("^1═══════════════════════════════════════^0")
    print("^1[GhostGuard] ANTICHEAT DISABLED^0")
    print("^1Reason: " .. reason .. "^0")
    print("^1Köp en ny licens på https://ghostguardac.se/pricing^0")
    print("^1═══════════════════════════════════════^0")
    pushLog("License", "SHUTDOWN", "Anticheat disabled: " .. reason)
    Wait(2000)
    StopResource(GetCurrentResourceName())
end

CreateThread(function()
    checkLicenseOnce(function(ok, state)
        if not ok then
            shutdownAnticheat("License " .. state)
            return
        end

        GhostGuardActive = true
        print("^2[GhostGuard] License approved (HWID bound). Anticheat active.^0")
        pushLog("License", "OK", "License approved")
    end)

    while true do
        Wait(60 * 1000)
        checkLicenseOnce(function(ok, state)
            if not ok then
                if state == "offline" or state == "invalid_response" then
                    failedVerifications = failedVerifications + 1
                    print("^3[GhostGuard] License verification failed ("..failedVerifications.."/"..MAX_FAILED_BEFORE_SHUTDOWN.."): "..state.."^0")
                    if failedVerifications >= MAX_FAILED_BEFORE_SHUTDOWN then
                        shutdownAnticheat("Could not verify license (network issue or DNS hijack)")
                    end
                    return
                end
                shutdownAnticheat("License " .. state)
            else
                failedVerifications = 0
            end
        end)
    end
end)

-- ========= BAN CHECK ON CONNECT (via Supabase) =========
AddEventHandler("playerConnecting", function(name, setKickReason, deferrals)
    local src = source
    joinTime[src] = GetGameTimer()

    deferrals.defer()
    deferrals.update("Kontrollerar ban-status...")

    local ids = getIdentifiers(src)

    if not Config or not Config.BackendURL or not Config.LicenseKey then
        deferrals.done()
        return
    end

    PerformHttpRequest(
        Config.BackendURL .. "/api/server/ban/check",
        function(code, response)
            local data = json.decode(response or "{}")

            if data and data.banned and data.ban then
                local b   = data.ban
                local exp = b.expires_at and ("\nGår ut: " .. b.expires_at) or "\nGår ut: PERMANENT"
                deferrals.done(
                    ("Du är bannad från servern.\nBan ID: %s\nReason: %s\nBy: %s%s"):format(
                        b.ban_id    or "N/A",
                        b.reason    or "No reason",
                        b.banned_by or "GhostGuard",
                        exp
                    )
                )
            else
                deferrals.done()
                pushLog("Player", "Join", ("JOIN %s (%s)"):format(name or "unknown", bestIdentifier(src)))
                local m = ggMeta(src)
                ggSend("info", "player_join", "Player Joined",
                    ("[%d] %s joined"):format(src, m.name), m)
            end
        end,
        "POST",
        json.encode({
            license_key = Config.LicenseKey,
            identifiers = ids,
        }),
        { ["Content-Type"] = "application/json" }
    )
end)

AddEventHandler("playerDropped", function(reason)
    local src = source
    frozenPlayers[src] = nil
    joinTime[src] = nil

    pushLog("Player", "Leave", ("LEAVE %s (%s) | %s"):format(GetPlayerName(src) or "unknown", bestIdentifier(src), tostring(reason or "-")))

    local m = ggMeta(src)
    m.reason = tostring(reason or "-")
    ggSend("info", "player_leave", "Player Left",
        ("[%d] %s left (%s)"):format(src, m.name, m.reason), m)
end)

-- ========= OPTIONAL: CHAT LOGGING =========
AddEventHandler("chatMessage", function(src, name, msg)
    if not CONFIG.logChat then return end
    pushLog("Chat", bestIdentifier(src), ("%s: %s"):format(name or "unknown", tostring(msg)))
end)

-- ========= AUTOBAN CORE =========
local strikes = {}     -- strikes[src][type] = count
local rateBuckets = {} -- rateBuckets[src][type] = {t0=ms,count=n}

local function addStrike(src, aType)
    strikes[src] = strikes[src] or {}
    strikes[src][aType] = (strikes[src][aType] or 0) + 1
    return strikes[src][aType]
end

local function rateHit(src, aType)
    local nowMs = GetGameTimer()
    rateBuckets[src] = rateBuckets[src] or {}
    local b = rateBuckets[src][aType]

    if not b then
        rateBuckets[src][aType] = { t0 = nowMs, count = 1 }
        return false
    end

    if (nowMs - b.t0) > CONFIG.alertRateWindowMs then
        b.t0 = nowMs
        b.count = 1
        return false
    end

    b.count = b.count + 1
    return (b.count > CONFIG.alertRateMax)
end

local function autoBanPlayer(src, aType, details)
    if not GhostGuardActive then return end
    if not CONFIG.autoBan then return end
    if not src or src == 0 then return end
    if isAdmin(src) then return end

    if rateHit(src, aType) then
        pushLog("Alert", bestIdentifier(src) or "-", ("RATE-LIMITED alert %s (%s) type=%s"):format(GetPlayerName(src) or "Unknown", src, aType))
        return
    end

    local rule = CONFIG.punish[aType]
    if not rule then return end

    local count = addStrike(src, aType)
    if count < (rule.strikes or 1) then
        pushLog("Strike", bestIdentifier(src) or "-", ("STRIKE %s (%s) %s (%d/%d)"):format(GetPlayerName(src) or "Unknown", src, aType, count, rule.strikes or 1))
        return
    end

    local reason = ("%s | %s"):format(rule.reason or aType, tostring(details or "-"))
    local ok, res = addBan(src, reason, rule.duration or "P", "GhostGuard(Auto)")
    if not ok then
        pushLog("AutoBan", bestIdentifier(src) or "-", ("FAILED autoban %s (%s): %s"):format(GetPlayerName(src) or "Unknown", src, tostring(res)))
        return
    end

    local b = res
    pushLog("AutoBan", bestIdentifier(src) or "-", ("AUTOBAN %s (%s) | %s | %s"):format(GetPlayerName(src) or "Unknown", src, b.reason, (b.expires_at or "PERM")))

    if Config and Config.BackendURL and Config.LicenseKey then
        local m = ggMeta(src)
        local idList = {}
        if m.identifiers then
            for _, v in pairs(m.identifiers) do
                idList[#idList+1] = v
            end
        end
        PerformHttpRequest(
            Config.BackendURL .. "/api/server/detection",
            function() end,
            "POST",
            json.encode({
                license_key    = Config.LicenseKey,
                player_name    = m.name,
                player_id      = tostring(src),
                identifiers    = idList,
                detection_type = aType,
                details        = tostring(details or "-"),
                action_taken   = "ban",
                ban_id         = b.ban_id,
            }),
            { ["Content-Type"] = "application/json" }
        )
    end

    DropPlayer(src, ("Du är bannad från servern.\nBan ID: %s\nReason: %s\nBy: %s\nGår ut: %s"):format(
        b.ban_id, b.reason, b.by, (b.expires_at or "PERMANENT")
    ))
end

-- ========= EXPLOSION LOGGING (+ optional autoban + backend) =========
AddEventHandler("explosionEvent", function(sender, ev)
    if not CONFIG.logExplosions then return end
    if not sender or sender == 0 then return end

    local name = GetPlayerName(sender) or ("ID "..tostring(sender))
    local ident = bestIdentifier(sender)
    local exType = ev and ev.explosionType or "?"
    local pos = ev and ev.pos or nil

    local posStr = "-"
    if pos then
        posStr = ("%.1f %.1f %.1f"):format(pos.x or 0.0, pos.y or 0.0, pos.z or 0.0)
    end

    pushLog("Explosion", ident, ("EXPLOSION by %s | type=%s pos=%s"):format(name, tostring(exType), posStr))
    pushAlert(sender, "Explosion", ("type=%s pos=%s"):format(tostring(exType), posStr))

    local m = ggMeta(sender)
    m.explosion = ev
    m.pos = posStr
    ggSend("alert", "explosion", "Explosion Event",
        ("[%d] %s explosionType=%s pos=%s"):format(sender, m.name, tostring(exType), posStr), m)

    autoBanPlayer(sender, "Explosion", ("type=%s pos=%s"):format(tostring(exType), posStr))
end)

-- ========= ENTITY CREATE LOGGING (safer) =========
local createBuckets = {}  -- [owner] = {t0=ms, count=int}
local recentEntities = {} -- [owner] = { [entity]=true }

local function bucketReset(owner, nowMs)
    createBuckets[owner] = { t0 = nowMs, count = 0 }
    recentEntities[owner] = {}
end

local function bucketAdd(owner, entity)
    local nowMs = GetGameTimer()
    local b = createBuckets[owner]
    if not b then
        bucketReset(owner, nowMs)
        b = createBuckets[owner]
    end

    if (nowMs - b.t0) > CONFIG.vehicleCreateWindowMs then
        bucketReset(owner, nowMs)
        b = createBuckets[owner]
    end

    recentEntities[owner] = recentEntities[owner] or {}
    if recentEntities[owner][entity] then
        return b.count, (b.count >= CONFIG.vehicleCreateMax)
    end
    recentEntities[owner][entity] = true

    b.count = b.count + 1
    return b.count, (b.count >= CONFIG.vehicleCreateMax)
end

AddEventHandler("entityCreating", function(entity)
    if not CONFIG.logEntityCreates then return end
    if not DoesEntityExist(entity) then return end

    local owner = NetworkGetEntityOwner(entity)
    if not owner or owner == 0 then return end
    if isAdmin(owner) then return end

    local entType = GetEntityType(entity)
    if entType ~= 2 then return end

    -- ✅ grace: ignorera vid join
    if inGrace(owner) then return end

    local count, hit = bucketAdd(owner, entity)
    if hit then
        local name = GetPlayerName(owner) or ("ID "..tostring(owner))
        local ident = bestIdentifier(owner)

        pushLog("VehicleSpam", ident, ("POSSIBLE VEHICLE SPAM by %s | %d vehicles in window"):format(name, count))
        pushAlert(owner, "Vehicle spawn spam", ("%d vehicles in %dms"):format(count, CONFIG.vehicleCreateWindowMs))

        local m = ggMeta(owner)
        m.vehicleSpam = { count = count, windowMs = CONFIG.vehicleCreateWindowMs }
        ggSend("warn", "vehicle_spam", "Vehicle Spawn Spam",
            ("[%d] %s spawned %d vehicles in %dms"):format(owner, m.name, count, CONFIG.vehicleCreateWindowMs), m)

        autoBanPlayer(owner, "Vehicle spawn spam", ("%d vehicles in %dms"):format(count, CONFIG.vehicleCreateWindowMs))
    end
end)


-- ========= PANEL =========
RegisterCommand("gac", function(source)
    if source == 0 then return end
    if not GhostGuardActive then return end
    if not isAdmin(source) then return end

    TriggerClientEvent("ghostguard:openPanel", source)
    TriggerClientEvent("ghostguard:sendLogs", source, logs)
    TriggerClientEvent("ghostguard:sendAlerts", source, alerts)

    if Config and Config.BackendURL and Config.LicenseKey then
        PerformHttpRequest(
            Config.BackendURL .. "/api/server/bans/" .. Config.LicenseKey,
            function(code, response)
                local data = json.decode(response or "{}")
                if data and data.bans then
                    TriggerClientEvent("ghostguard:sendBans", source, data.bans)
                end
            end,
            "GET"
        )
    end
end)




-- /gac_addid [serverId]  (ex: /gac_addid 12)
RegisterCommand("gac_addid", function(src, args)
    -- endast console (src=0) eller en redan-admin får lägga till admins
    if src ~= 0 and not isAdmin(src) then
        TriggerClientEvent("chat:addMessage", src, { args = {"GhostGuard", "Du har inte access."} })
        return
    end

    local target = tonumber(args[1] or "")
    if not target then
        if src ~= 0 then
            TriggerClientEvent("chat:addMessage", src, { args = {"GhostGuard", "Usage: /gac_addid [serverId]"} })
        else
            print("Usage: gac_addid [serverId]")
        end
        return
    end

    local ok, err = addAdminFromPlayerId(target)
    if not ok then
        if src ~= 0 then
            TriggerClientEvent("chat:addMessage", src, { args = {"GhostGuard", "Failed: "..tostring(err)} })
        else
            print("Failed:", err)
        end
        return
    end

    loadAdmins() -- reload så det gäller direkt
    local msg = ("✅ Added admin: %s (%s)"):format(GetPlayerName(target) or "Unknown", target)

    if src ~= 0 then
        TriggerClientEvent("chat:addMessage", src, { args = {"GhostGuard", msg} })
    else
        print(msg)
    end
end, false)



-- ========= UI REQUESTS =========
RegisterNetEvent("ghostguard:getPlayers", function()
    local src = source
    if not isAdmin(src) then return end

    local list = {}
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        list[#list+1] = {
            id = id,
            name = GetPlayerName(id) or ("Player "..pid),
            ping = GetPlayerPing(id) or 0,
            identifier = bestIdentifier(id) or "-"
        }
    end
    TriggerClientEvent("ghostguard:sendPlayers", src, list)
end)

RegisterNetEvent("ghostguard:getBans", function()
    local src = source
    if not isAdmin(src) then return end
    if Config and Config.BackendURL and Config.LicenseKey then
        PerformHttpRequest(
            Config.BackendURL .. "/api/server/bans/" .. Config.LicenseKey,
            function(code, response)
                local data = json.decode(response or "{}")
                if data and data.bans then
                    TriggerClientEvent("ghostguard:sendBans", src, data.bans)
                end
            end,
            "GET"
        )
    end
end)

RegisterNetEvent("ghostguard:getLogs", function()
    local src = source
    if not isAdmin(src) then return end
    TriggerClientEvent("ghostguard:sendLogs", src, logs)
end)

RegisterNetEvent("ghostguard:getAlerts", function()
    local src = source
    if not isAdmin(src) then return end
    TriggerClientEvent("ghostguard:sendAlerts", src, alerts)
end)

-- ========= ACTIONS =========
RegisterNetEvent("ghostguard:kickPlayer", function(target, reason)
    local src = source
    if not isAdmin(src) then return end

    local t = tonumber(target)
    if not t or not GetPlayerName(t) then return end

    local r = tostring(reason or "No reason")
    pushLog("Kick", ("admin:%d"):format(src), ("KICK %s (%s) | %s"):format(GetPlayerName(t), t, r))
    DropPlayer(t, "Kicked: "..r)
end)

RegisterNetEvent("ghostguard:banPlayer", function(target, reason, timeStr)
    local src = source
    if not isAdmin(src) then return end

    local t = tonumber(target)
    if not t or not GetPlayerName(t) then return end

    local adminName = GetPlayerName(src) or ("Admin "..tostring(src))
    local ok, resOrErr = addBan(t, tostring(reason or "No reason"), "P", adminName)
    if not ok then
        TriggerClientEvent("chat:addMessage", src, { args={"GhostGuard", resOrErr} })
        return
    end

    local b = resOrErr
    pushLog("Ban", ("admin:%d"):format(src), ("BAN %s (%s) | %s | %s"):format(GetPlayerName(t), t, b.reason, (b.expires_at or "PERM")))
    DropPlayer(t, ("Du är bannad från servern.\nBan ID: %s\nReason: %s\nBy: %s\nGår ut: %s"):format(
        b.ban_id, b.reason, b.by, (b.expires_at or "PERMANENT")
    ))
end)

RegisterNetEvent("ghostguard:unban", function(ban_id)
    local src = source
    if not isAdmin(src) then return end

    local ok = removeBan(tostring(ban_id))
    if ok then
        pushLog("Unban", ("admin:%d"):format(src), ("UNBAN %s"):format(tostring(ban_id)))
    end
end)

RegisterNetEvent("ghostguard:teleportToPlayer", function(target)
    local src = source
    if not isAdmin(src) then return end

    local t = tonumber(target)
    if not t then return end

    local ped = GetPlayerPed(t)
    if not ped then return end

    local coords = GetEntityCoords(ped)
    TriggerClientEvent("ghostguard:teleportAdmin", src, { x=coords.x, y=coords.y, z=coords.z + 0.5 })
end)

RegisterNetEvent("ghostguard:freezePlayer", function(target)
    local src = source
    if not isAdmin(src) then return end

    local t = tonumber(target)
    if not t or not GetPlayerName(t) then return end

    frozenPlayers[t] = not frozenPlayers[t]
    local toggle = frozenPlayers[t]

    TriggerClientEvent("ghostguard:freezeMe", t, toggle)

    if toggle then
        pushLog("Freeze", ("admin:%d"):format(src), ("FREEZE %s (%s)"):format(GetPlayerName(t) or "Unknown", t))
    else
        pushLog("Freeze", ("admin:%d"):format(src), ("UNFREEZE %s (%s)"):format(GetPlayerName(t) or "Unknown", t))
    end
end)

RegisterNetEvent("ghostguard:sendDM", function(target, msg)
    local src = source
    if not isAdmin(src) then return end

    local t = tonumber(target)
    if not t or not GetPlayerName(t) then return end

    local adminName = GetPlayerName(src) or "Admin"
    local text = ("GhostGuard DM från %s: %s"):format(adminName, tostring(msg))
    TriggerClientEvent("ghostguard:notify", t, text)

    pushLog("DM", ("admin:%d"):format(src), ("DM -> %s (%s): %s"):format(GetPlayerName(t), t, tostring(msg)))
end)

RegisterNetEvent("ghostguard:customNotify", function(target, style, title, message, duration)
    local src = source
    if not isAdmin(src) then return end

    local t = tonumber(target)
    if not t or not GetPlayerName(t) then return end

    TriggerClientEvent("ghostguard:customNotify", t,
        tostring(style or "info"),
        tostring(title or "GhostGuard"),
        tostring(message or ""),
        tonumber(duration or 5000)
    )

    pushLog("Notify", ("admin:%d"):format(src),
        ("NOTIFY -> %s (%s) [%s] %s: %s"):format(
            GetPlayerName(t), t, tostring(style or "info"),
            tostring(title or "GhostGuard"),
            tostring(message or "")
        )
    )
end)


-- ========= ALERT INTAKE =========
RegisterNetEvent("ghostguard:alert", function(aType, details)
print("SERVER GOT ALERT:", aType, details)
    
local src = source
    aType = tostring(aType or "Unknown")
    details = tostring(details or "-")

    pushAlert(src, aType, details)
    pushLog("Alert", bestIdentifier(src) or "-", ("ALERT %s (%s): %s | %s"):format(GetPlayerName(src) or "Unknown", src, aType, details))

    autoBanPlayer(src, aType, details)
end)

-- ========= HEARTBEAT =========
CreateThread(function()
    while true do
        Wait(5000)

        local players = {}

        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)

            players[#players+1] = {
                id = src,
                name = GetPlayerName(src),
                ping = GetPlayerPing(src)
            }
        end

        if Config and Config.BackendURL and Config.LicenseKey then
            PerformHttpRequest(
                Config.BackendURL .. "/api/server/heartbeat",
                function(code, body)
                    -- inget print här längre
                end,
                "POST",
                json.encode({
                    license_key = Config.LicenseKey,
                    version = "2.0.0",
                    players = players
                }),
                { ["Content-Type"] = "application/json" }
            )
        end
    end
end)

-- ========= DASHBOARD ACTIONS =========
local function doKick(target, reason)
    DropPlayer(target, "Kicked: " .. tostring(reason or "No reason"))
end

local function doBan(target, reason, duration)
    local adminName = "Dashboard"
    local ok, resOrErr = addBan(target, tostring(reason or "No reason"), tostring(duration or "P"), adminName)
    if ok then
        local b = resOrErr
        DropPlayer(target, ("Du är bannad.\nBan ID: %s\nReason: %s\nBy: %s\nGår ut: %s"):format(
            b.ban_id, b.reason, b.by, (b.expires_at or "PERMANENT")
        ))
    else
        print("^1[GhostGuard] Dashboard ban failed:^0", resOrErr)
    end
end

local function doDM(target, msg)
    local text = ("~b~GhostGuard DM~s~\nFrån: ~b~Dashboard~s~\n\n%s"):format(tostring(msg or ""))
    TriggerClientEvent("ghostguard:notify", target, text)
end

local function doFreeze(target)
    frozenPlayers[target] = not frozenPlayers[target]
    TriggerClientEvent("ghostguard:freezeMe", target, frozenPlayers[target])
end




-- ========= DASHBOARD ACTION POLL =========
CreateThread(function()
    while true do
        Wait(3000)

        PerformHttpRequest(
            Config.BackendURL .. "/api/server/actions/" .. Config.LicenseKey,
            function(status, response)
                if status == 200 and response then
                    local data = json.decode(response)

                    if data and data.actions then
                        for _, action in ipairs(data.actions) do

                            if action.type == "kick" then
                                local id = tonumber(action.payload.player)
                                if id then
                                    DropPlayer(id, action.payload.reason or "Kicked by GhostGuard")
                                end
                            end

                            if action.type == "ban" then
                                local id = tonumber(action.payload.player)
                                if id and GetPlayerName(id) then
                                    local reason   = tostring(action.payload.reason   or "No reason")
                                    local ok, b    = addBan(id, reason, "P", "Dashboard")
                                    if ok then
                                        DropPlayer(id, ("Du är bannad från servern.\nBan ID: %s\nReason: %s\nBy: %s\nGår ut: %s"):format(
                                            b.ban_id, b.reason, b.by, (b.expires_at or "PERMANENT")
                                        ))
                                    end
                                end
                            end

                            if action.type == "dm" then
                                local id = tonumber(action.payload.player)
                                if id then
                                    TriggerClientEvent("chat:addMessage", id, {
                                        args = { "^3GhostGuard", action.payload.message or "" }
                                    })
                                end
                            end

                        end
                    end
                end
            end,
            "GET"
        )
    end
end)







-- Detection settings läses från config.lua, inte från databasen


-- =========================================
-- GhostGuard Anti Stop Server Protection
-- =========================================

local lastHeartbeats = {}

RegisterNetEvent("ghostguard:heartbeat", function()
    local src = source
    lastHeartbeats[src] = os.time()
end)

CreateThread(function()
    while true do
        Wait(10000)

        for _, player in ipairs(GetPlayers()) do
            local src = tonumber(player)

            if not lastHeartbeats[src] then
                autoBanPlayer(src, "Resource Tamper", "No heartbeat")
            else
                if os.time() - lastHeartbeats[src] > 10 then
                    autoBanPlayer(src, "Resource Tamper", "Heartbeat timeout")
                end
            end
        end
    end
end)
