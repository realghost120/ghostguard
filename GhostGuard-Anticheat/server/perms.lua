-- server/perms.lua

GhostGuardPerms = {}

-- 🔒 Lägg in Discord ID här (utan discord:)
GhostGuardPerms.Staff = {
    ["1289995419606192270"] = true, -- Lägg discord id så dina staffs inte blir bannad av anticheat staff 1
    ["DISOCRD-ID"] = true, -- Lägg discord id så dina staffs inte blir bannad av anticheat staff 2
    ["DISOCRD-ID"] = true, -- Lägg discord id så dina staffs inte blir bannad av anticheat staff 3 
    ["DISOCRD-ID"] = true, -- Lägg discord id så dina staffs inte blir bannad av anticheat staff 4 
    ["DISOCRD-ID"] = true, -- Lägg discord id så dina staffs inte blir bannad av anticheat staff 5
    ["DISOCRD-ID"] = true, -- Lägg discord id så dina staffs inte blir bannad av anticheat staff 6

} 

function GhostGuardPerms.IsStaff(src)
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)

        if id and id:sub(1,8) == "discord:" then
            local discordId = id:gsub("discord:", "")

            if GhostGuardPerms.Staff[discordId] then
                return true
            end
        end
    end

    return false
end
