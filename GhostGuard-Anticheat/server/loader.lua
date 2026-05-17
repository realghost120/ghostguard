-- GhostGuard server-side loader
-- This is the ONLY server script that loads from disk. Everything else
-- is fetched from the GhostGuard backend at runtime so customers always
-- run the latest code and licenses can be enforced server-side.

local backendUrl = (Config and Config.BackendURL) or "https://panel.ghostguardac.se"

local function getHWID()
    local h = GetConvar("sv_licenseKey", "")
    if h == "" then h = GetConvar("sv_hostname", "unknown") end
    return h
end

local function hardStop(reason)
    print("^1═══════════════════════════════════════^0")
    print("^1[GhostGuard] " .. reason .. "^0")
    print("^1Visit https://ghostguardac.se/pricing for licenses^0")
    print("^1═══════════════════════════════════════^0")
    Wait(1500)
    StopResource(GetCurrentResourceName())
end

local function bootstrap()
    if not Config or not Config.LicenseKey or Config.LicenseKey == "" then
        hardStop("Missing LicenseKey in config.lua")
        return
    end

    PerformHttpRequest(backendUrl .. "/api/resource/bundle", function(code, response)
        if code ~= 200 or not response then
            hardStop("Cannot reach license server (HTTP " .. tostring(code) .. ")")
            return
        end

        local ok, data = pcall(json.decode, response)
        if not ok or type(data) ~= "table" then
            hardStop("Invalid response from license server")
            return
        end

        if not data.success then
            local reason = data.reason or "UNKNOWN"
            hardStop("License denied: " .. reason)
            return
        end

        if not data.code or data.code == "" then
            hardStop("Empty bundle received")
            return
        end

        print("^2[GhostGuard] Loaded v" .. (data.version or "?") .. " from server.^0")

        local chunk, loadErr = load(data.code, "@ghostguard-remote", "t", _ENV)
        if not chunk then
            hardStop("Bundle compile error: " .. tostring(loadErr))
            return
        end

        local execOk, execErr = pcall(chunk)
        if not execOk then
            hardStop("Bundle execution failed: " .. tostring(execErr))
            return
        end
    end, "POST", json.encode({
        license_key = Config.LicenseKey,
        hwid = getHWID(),
    }), { ["Content-Type"] = "application/json" })
end

CreateThread(function()
    Wait(500)
    bootstrap()
end)
