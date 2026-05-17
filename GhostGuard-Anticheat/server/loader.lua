-- GhostGuard server-side loader
-- The ONLY server-script that runs from disk. All anticheat logic is
-- fetched from the backend (encrypted) at runtime so it cannot be
-- modified, dumped or stolen from the customer server.

local backendUrl = (Config and Config.BackendURL) or "https://panel.ghostguardac.se"

local function getLicense()
    local raw = LoadResourceFile(GetCurrentResourceName(), "license.cfg") or ""
    raw = raw:gsub("^%s*(.-)%s*$", "%1")
    raw = raw:gsub("\r", ""):gsub("\n", "")
    return raw
end

local function getHWID()
    local h = GetConvar("sv_licenseKey", "")
    if h == "" then h = GetConvar("sv_hostname", "unknown") end
    return h
end

local function hardStop(reason)
    print("^1═══════════════════════════════════════^0")
    print("^1[GhostGuard] " .. reason .. "^0")
    print("^1Buy or renew: https://ghostguardac.se/pricing^0")
    print("^1═══════════════════════════════════════^0")
    Wait(1500)
    StopResource(GetCurrentResourceName())
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(input)
    input = input:gsub("[^" .. B64 .. "=]", "")
    local bits = {}
    for i = 1, #input do
        local c = input:sub(i, i)
        if c == "=" then break end
        local v = B64:find(c, 1, true)
        if v then
            v = v - 1
            for j = 6, 1, -1 do bits[#bits + 1] = (v >> (j - 1)) & 1 end
        end
    end
    local bytes = {}
    for i = 1, #bits - 7, 8 do
        local b = 0
        for j = 0, 7 do b = b | (bits[i + j] << (7 - j)) end
        bytes[#bytes + 1] = b
    end
    return string.char(table.unpack(bytes))
end

local function deriveKey(license, hwid)
    local s = license .. ":" .. hwid .. ":ghostguard"
    local out = {}
    for i = 1, #s do
        out[i] = (s:byte(i) * 31 + i * 7) % 256
    end
    return out
end

local function decrypt(b64payload, key)
    local data = b64decode(b64payload)
    local out = {}
    local klen = #key
    for i = 1, #data do
        out[i] = string.char(data:byte(i) ~ key[((i - 1) % klen) + 1])
    end
    return table.concat(out)
end

local function bootstrap()
    local license = getLicense()
    if license == "" then
        hardStop("Missing license. Open license.cfg in resource folder and paste your key.")
        return
    end

    local hwid = getHWID()

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
            hardStop("License denied: " .. (data.reason or "UNKNOWN"))
            return
        end

        if not data.payload or data.payload == "" then
            hardStop("Empty payload from license server")
            return
        end

        local decryptOk, plain = pcall(function()
            return decrypt(data.payload, deriveKey(license, hwid))
        end)
        if not decryptOk or not plain or plain == "" then
            hardStop("Bundle decryption failed")
            return
        end

        local chunk, loadErr = load(plain, "@ghostguard-remote", "t", _ENV)
        if not chunk then
            hardStop("Bundle compile error: " .. tostring(loadErr))
            return
        end

        local execOk, execErr = pcall(chunk)
        if not execOk then
            hardStop("Bundle execution failed: " .. tostring(execErr))
            return
        end

        print("^2[GhostGuard] v" .. (data.version or "?") .. " loaded successfully^0")
    end, "POST", json.encode({
        license_key = license,
        hwid = hwid,
    }), { ["Content-Type"] = "application/json" })
end

CreateThread(function()
    Wait(500)
    bootstrap()
end)
