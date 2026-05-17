-- server/update.lua

local CURRENT_VERSION = "2.0.0"
local VERSION_URL = "https://panel.ghostguardac.se/version"


CreateThread(function()
    Wait(3000)

    PerformHttpRequest(VERSION_URL, function(code, res)

        if code ~= 200 or not res or res == "" then
    return -- silent fail
end


        local ok, data = pcall(json.decode, res)
        if not ok or type(data) ~= "table" or not data.version then
            print("^1[GhostGuard]^0 Invalid version response.")
            return
        end

        local latest = tostring(data.version)
        local current = tostring(CURRENT_VERSION)

        if latest ~= current then
            print("^3[GhostGuard]^0 👻 Update Available!")
            print("^3Installed:^0 v" .. current)
            print("^2Latest:^0 v" .. latest)

            if data.download then
                print("^5Download:^0 " .. tostring(data.download))
            end

            if data.notes then
                print("^6Changelog:^0 " .. tostring(data.notes))
            end

        else
            print("^2═══════════════════════════════════════^0")
            print("^2[GhostGuard]^0 👻 Version ^3v" .. current .. "^0")
            print("^2Status:^0 ^2Up to Date ✔^0")
            print("^2═══════════════════════════════════════^0")
        end

    end, "GET")

end)
