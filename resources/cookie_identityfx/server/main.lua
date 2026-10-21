local activeCache = {}
local dbReady = false

local validTypes = {
    chat_title = true,
    overhead_title = true,
    killfeed_skin = true
}

local function dbg(...)
    if Config.Debug then
        print('[cookie_identityfx]', ...)
    end
end

local function getPlayer(src)
    if not src or src <= 0 then return nil end
    return exports.qbx_core:GetPlayer(src)
end

local function getCitizenId(src)
    local player = getPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function getDisplayName(src)
    local p = Player(src)
    if p and p.state then
        local n = p.state.cookie_name or p.state.cookieName or p.state.nickname or p.state.displayName
        if type(n) == 'string' and n ~= '' then return n end
    end

    local player = getPlayer(src)
    if player and player.PlayerData then
        local pd = player.PlayerData
        if pd.charinfo then
            local first = pd.charinfo.firstname
            local last = pd.charinfo.lastname
            if type(first) == 'string' and first ~= '' and first ~= 'Unknown' then
                local full = first
                if type(last) == 'string' and last ~= '' then full = full .. ' ' .. last end
                return full
            end
        end
    end

    return GetPlayerName(src) or ('ID %s'):format(src)
end

local function isAdmin(src)
    if src == 0 then return true end

    if Config.AdminAce and IsPlayerAceAllowed(src, Config.AdminAce) then
        return true
    end

    -- 보통 관리자 ACE가 command 전체를 허용하는 서버와의 호환
    if IsPlayerAceAllowed(src, 'command') then
        return true
    end

    if GetResourceState('cookie_admin') == 'started' then
        local ok, level = pcall(function()
            return exports.cookie_admin:GetAdminLevel(src)
        end)
        if ok and tonumber(level) and tonumber(level) >= (Config.CookieAdminMinLevel or 3) then
            return true
        end
    end

    return false
end

local function sanitizeCode(v)
    v = tostring(v or ''):lower()
    v = v:gsub('%s+', '_')
    v = v:gsub('[^%w_%-]', '')
    return v:sub(1, 64)
end

local function sanitizeColor(v)
    v = tostring(v or '#ffffff')
    if not v:match('^#%x%x%x%x%x%x$') then
        return '#ffffff'
    end
    return v
end

local function decodeStyle(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, data = pcall(json.decode, raw)
    return ok and type(data) == 'table' and data or {}
end

local function ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_cosmetic_catalog (
            id INT NOT NULL AUTO_INCREMENT,
            code VARCHAR(64) NOT NULL,
            type VARCHAR(32) NOT NULL,
            label VARCHAR(96) NOT NULL,
            color VARCHAR(16) NOT NULL DEFAULT '#ffffff',
            style_json LONGTEXT NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_cookie_cosmetic_code (code),
            KEY idx_cookie_cosmetic_type (type)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_cosmetic_ownership (
            citizenid VARCHAR(64) NOT NULL,
            code VARCHAR(64) NOT NULL,
            active TINYINT(1) NOT NULL DEFAULT 0,
            granted_by VARCHAR(64) NULL,
            granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (citizenid, code),
            KEY idx_cookie_cosmetic_owner_active (citizenid, active),
            CONSTRAINT fk_cookie_cosmetic_catalog
                FOREIGN KEY (code) REFERENCES cookie_cosmetic_catalog(code)
                ON UPDATE CASCADE ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    for _, item in ipairs(Config.DefaultCatalog or {}) do
        if validTypes[item.type] then
            MySQL.insert.await([[
                INSERT IGNORE INTO cookie_cosmetic_catalog (code, type, label, color, style_json, enabled)
                VALUES (?, ?, ?, ?, ?, 1)
            ]], {
                sanitizeCode(item.code),
                item.type,
                tostring(item.label or item.code),
                sanitizeColor(item.color),
                json.encode(item.style or {})
            })
        end
    end

    dbReady = true
    print('[cookie_identityfx] DB ready')
end

local function waitDb()
    while not dbReady do Wait(50) end
end

local function refreshCache(citizenid)
    if not citizenid then return {} end
    waitDb()

    local rows = MySQL.query.await([[
        SELECT c.code, c.type, c.label, c.color, c.style_json
        FROM cookie_cosmetic_ownership o
        INNER JOIN cookie_cosmetic_catalog c ON c.code = o.code
        WHERE o.citizenid = ? AND o.active = 1 AND c.enabled = 1
    ]], { citizenid }) or {}

    local data = {}
    for _, row in ipairs(rows) do
        data[row.type] = {
            code = row.code,
            type = row.type,
            label = row.label,
            color = row.color,
            style = decodeStyle(row.style_json)
        }
    end

    activeCache[citizenid] = data
    return data
end

local function getActiveForSource(src)
    local cid = getCitizenId(src)
    if not cid then return {} end
    if not activeCache[cid] then
        return refreshCache(cid)
    end
    return activeCache[cid]
end

local function getOwned(citizenid)
    waitDb()
    local rows = MySQL.query.await([[
        SELECT c.code, c.type, c.label, c.color, c.style_json, o.active
        FROM cookie_cosmetic_ownership o
        INNER JOIN cookie_cosmetic_catalog c ON c.code = o.code
        WHERE o.citizenid = ? AND c.enabled = 1
        ORDER BY c.type, c.id
    ]], { citizenid }) or {}

    for _, row in ipairs(rows) do
        row.style = decodeStyle(row.style_json)
        row.style_json = nil
        row.active = tonumber(row.active) == 1
    end
    return rows
end

local function getCatalog()
    waitDb()
    local rows = MySQL.query.await([[
        SELECT code, type, label, color, style_json, enabled
        FROM cookie_cosmetic_catalog
        WHERE enabled = 1
        ORDER BY type, id
    ]]) or {}

    for _, row in ipairs(rows) do
        row.style = decodeStyle(row.style_json)
        row.style_json = nil
        row.enabled = tonumber(row.enabled) == 1
    end
    return rows
end

local function broadcastOverheads()
    local payload = {}
    local players = exports.qbx_core:GetQBPlayers()

    for src, _ in pairs(players or {}) do
        src = tonumber(src)
        if src then
            local active = getActiveForSource(src)
            local title = active.overhead_title
            if title then
                payload[tostring(src)] = {
                    label = title.label,
                    color = title.color
                }
            end
        end
    end

    TriggerClientEvent('cookie_identityfx:client:syncOverheads', -1, payload)
end

local function sendSelfData(src, openMode)
    local cid = getCitizenId(src)
    if not cid then return end

    local active = refreshCache(cid)
    local owned = getOwned(cid)

    TriggerClientEvent('cookie_identityfx:client:selfData', src, {
        owned = owned,
        active = active,
        displayName = getDisplayName(src),
        admin = isAdmin(src),
        openMode = openMode
    })
end

local function adminPayload()
    local players = {}
    for src, player in pairs(exports.qbx_core:GetQBPlayers() or {}) do
        src = tonumber(src)
        if src and player and player.PlayerData then
            players[#players + 1] = {
                source = src,
                citizenid = player.PlayerData.citizenid,
                name = getDisplayName(src)
            }
        end
    end

    table.sort(players, function(a, b) return a.source < b.source end)

    return {
        players = players,
        catalog = getCatalog()
    }
end

CreateThread(ensureSchema)

AddEventHandler('playerDropped', function()
    local src = source
    local cid = getCitizenId(src)
    if cid then activeCache[cid] = nil end
    SetTimeout(300, broadcastOverheads)
end)

RegisterNetEvent('cookie_identityfx:server:requestSync', function(openMode)
    local src = source
    sendSelfData(src, openMode)
    broadcastOverheads()
end)

RegisterNetEvent('cookie_identityfx:server:requestAdminData', function()
    local src = source
    if not isAdmin(src) then return end
    TriggerClientEvent('cookie_identityfx:client:adminData', src, adminPayload())
end)

RegisterNetEvent('cookie_identityfx:server:setActive', function(kind, code)
    local src = source
    local cid = getCitizenId(src)
    if not cid or not validTypes[kind] then return end
    waitDb()

    MySQL.update.await([[
        UPDATE cookie_cosmetic_ownership o
        INNER JOIN cookie_cosmetic_catalog c ON c.code = o.code
        SET o.active = 0
        WHERE o.citizenid = ? AND c.type = ?
    ]], { cid, kind })

    code = sanitizeCode(code)
    if code ~= '' then
        local owned = MySQL.single.await([[
            SELECT o.code
            FROM cookie_cosmetic_ownership o
            INNER JOIN cookie_cosmetic_catalog c ON c.code = o.code
            WHERE o.citizenid = ? AND o.code = ? AND c.type = ? AND c.enabled = 1
            LIMIT 1
        ]], { cid, code, kind })

        if owned then
            MySQL.update.await('UPDATE cookie_cosmetic_ownership SET active = 1 WHERE citizenid = ? AND code = ?', {
                cid, code
            })
        end
    end

    refreshCache(cid)
    sendSelfData(src, 'user')
    broadcastOverheads()
end)

RegisterNetEvent('cookie_identityfx:server:adminCreate', function(data)
    local src = source
    if not isAdmin(src) or type(data) ~= 'table' then return end

    local kind = tostring(data.type or '')
    local code = sanitizeCode(data.code)
    local label = tostring(data.label or ''):sub(1, 96)
    local color = sanitizeColor(data.color)
    local theme = tostring(data.theme or 'default'):sub(1, 32)

    if not validTypes[kind] or code == '' or label == '' then return end

    local style = {}
    if kind == 'killfeed_skin' then style.theme = theme end

    MySQL.query.await([[
        INSERT INTO cookie_cosmetic_catalog (code, type, label, color, style_json, enabled)
        VALUES (?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            type = VALUES(type),
            label = VALUES(label),
            color = VALUES(color),
            style_json = VALUES(style_json),
            enabled = 1
    ]], { code, kind, label, color, json.encode(style) })

    TriggerClientEvent('cookie_identityfx:client:adminData', src, adminPayload())
end)

RegisterNetEvent('cookie_identityfx:server:adminGrant', function(target, code)
    local src = source
    if not isAdmin(src) then return end

    target = tonumber(target)
    code = sanitizeCode(code)
    if not target or code == '' then return end

    local targetCid = getCitizenId(target)
    if not targetCid then return end

    local item = MySQL.single.await('SELECT code FROM cookie_cosmetic_catalog WHERE code = ? AND enabled = 1 LIMIT 1', { code })
    if not item then return end

    MySQL.query.await([[
        INSERT INTO cookie_cosmetic_ownership (citizenid, code, active, granted_by)
        VALUES (?, ?, 0, ?)
        ON DUPLICATE KEY UPDATE granted_by = VALUES(granted_by)
    ]], { targetCid, code, getCitizenId(src) or ('src:' .. tostring(src)) })

    refreshCache(targetCid)
    sendSelfData(target, 'user')
    TriggerClientEvent('cookie_identityfx:client:adminData', src, adminPayload())
end)

RegisterNetEvent('cookie_identityfx:server:adminRevoke', function(target, code)
    local src = source
    if not isAdmin(src) then return end

    target = tonumber(target)
    code = sanitizeCode(code)
    if not target or code == '' then return end

    local targetCid = getCitizenId(target)
    if not targetCid then return end

    MySQL.update.await('DELETE FROM cookie_cosmetic_ownership WHERE citizenid = ? AND code = ?', {
        targetCid, code
    })

    refreshCache(targetCid)
    sendSelfData(target, 'user')
    TriggerClientEvent('cookie_identityfx:client:adminData', src, adminPayload())
    broadcastOverheads()
end)

-- COOKIE / TURN weapon-icon lookup. Uses only files shipped with cookie_hud.
-- Weapon hashes can arrive as unsigned integers on some clients.
local cookieWeaponIcons = {
    [-2084633992] = 'weapon_carbinerifle',
    [-2067956739] = 'weapon_crowbar',
    [-2066285827] = 'weapon_bullpuprifle_mk2',
    [-2009644972] = 'weapon_snspistol_mk2',
    [-1951375401] = 'weapon_flashlight',
    [-1853920116] = 'weapon_navyrevolver',
    [-1834847097] = 'weapon_dagger',
    [-1813897027] = 'weapon_grenade',
    [-1810795771] = 'weapon_poolcue',
    [-1786099057] = 'weapon_bat',
    [-1768145561] = 'weapon_specialcarbine_mk2',
    [-1746263880] = 'weapon_doubleaction',
    [-1716589765] = 'weapon_pistol50',
    [-1716189206] = 'weapon_knife',
    [-1660422300] = 'weapon_mg',
    [-1658906650] = 'weapon_militaryrifle',
    [-1654528753] = 'weapon_bullpupshotgun',
    [-1652067232] = 'weapon_autoshotgun',
    [-1600701090] = 'weapon_bzgas',
    [-1569615261] = 'weapon_unarmed',
    [-1568386805] = 'weapon_grenadelauncher',
    [-1553120962] = 'car',
    [-1466123874] = 'weapon_musket',
    [-1420407917] = 'weapon_proxmine',
    [-1357824103] = 'weapon_advancedrifle',
    [-1355376991] = 'weapon_raypistol',
    [-1312131151] = 'weapon_rpg',
    [-1238556825] = 'weapon_rayminigun',
    [-1169823560] = 'weapon_pipebomb',
    [-1168940174] = 'weapon_hazardcan',
    [-1121678507] = 'weapon_minismg',
    [-1076751822] = 'weapon_snspistol',
    [-1075685676] = 'weapon_pistol_mk2',
    [-1074790547] = 'weapon_assaultrifle',
    [-1063057011] = 'weapon_specialcarbine',
    [-1045183535] = 'weapon_revolver',
    [-952879014] = 'weapon_marksmanrifle',
    [-879347409] = 'weapon_revolver_mk2',
    [-853065399] = 'weapon_battleaxe',
    [-842959696] = 'fall',
    [-771403250] = 'weapon_heavypistol',
    [-656458692] = 'weapon_knuckle',
    [-619010992] = 'weapon_machinepistol',
    [-608341376] = 'weapon_combatmg_mk2',
    [-598887786] = 'weapon_marksmanpistol',
    [-581044007] = 'weapon_machete',
    [-544306709] = 'weapon_molotov',
    [-538741184] = 'weapon_switchblade',
    [-494615257] = 'weapon_assaultshotgun',
    [-275439685] = 'weapon_dbshotgun',
    [-270015777] = 'weapon_assaultsmg',
    [-102973651] = 'weapon_hatchet',
    [-102323637] = 'weapon_bottle',
    [-86904375] = 'weapon_carbinerifle_mk2',
    [-72657034] = 'fall',
    [-38085395] = 'weapon_unarmed',
    [-37975472] = 'weapon_smokegrenade',
    [94989220] = 'weapon_combatshotgun',
    [100416529] = 'weapon_sniperrifle',
    [101631238] = 'weapon_fireextinguisher',
    [125959754] = 'weapon_compactlauncher',
    [126349499] = 'weapon_snowball',
    [133987706] = 'car',
    [137902532] = 'weapon_vintagepistol',
    [171789620] = 'weapon_combatpdw',
    [177293209] = 'weapon_heavysniper_mk2',
    [205991906] = 'weapon_heavysniper',
    [317205821] = 'weapon_autoshotgun',
    [324215364] = 'weapon_microsmg',
    [338557568] = 'weapon_wrench',
    [419712736] = 'weapon_wrench',
    [453432689] = 'weapon_pistol',
    [487013001] = 'weapon_pumpshotgun',
    [539292904] = 'weapon_grenade',
    [584646201] = 'weapon_appistol',
    [600439132] = 'weapon_ball',
    [615608432] = 'weapon_molotov',
    [727643628] = 'weapon_ceramicpistol',
    [736523883] = 'weapon_smg',
    [741814745] = 'weapon_stickybomb',
    [883325847] = 'weapon_petrolcan',
    [911657153] = 'weapon_stungun',
    [940833800] = 'weapon_stone_hatchet',
    [961495388] = 'weapon_assaultrifle_mk2',
    [984333226] = 'weapon_heavyshotgun',
    [1119849093] = 'weapon_minigun',
    [1141786504] = 'weapon_golfclub',
    [1198256469] = 'weapon_raycarbine',
    [1198879012] = 'weapon_flaregun',
    [1233104067] = 'weapon_flare',
    [1305664598] = 'weapon_grenadelauncher_smoke',
    [1317494643] = 'weapon_hammer',
    [1432025498] = 'weapon_pumpshotgun_mk2',
    [1470379660] = 'weapon_gadgetpistol',
    [1593441988] = 'weapon_combatpistol',
    [1627465347] = 'weapon_gusenberg',
    [1649403952] = 'weapon_compactrifle',
    [1672152130] = 'weapon_hominglauncher',
    [1737195953] = 'weapon_nightstick',
    [1785463520] = 'weapon_marksmanrifle_mk2',
    [1834241177] = 'weapon_railgun',
    [2017895192] = 'weapon_sawnoffshotgun',
    [2024373456] = 'weapon_smg_mk2',
    [2132975508] = 'weapon_bullpuprifle',
    [2138347493] = 'weapon_firework',
    [2144741730] = 'weapon_combatmg',
}

local function cookieResolveWeaponIcon(value)
    local hash = tonumber(value)
    if not hash then return 'weapon_unarmed' end
    if hash > 2147483647 then hash = hash - 4294967296 end
    return cookieWeaponIcons[hash] or 'weapon_unarmed'
end

RegisterNetEvent('cookie_identityfx:server:death', function(killerSid, weaponLabel, headshot, distance, weaponHash)
    local victimSid = source
    killerSid = tonumber(killerSid) or 0

    local victimName = getDisplayName(victimSid)
    local killerName = 'WORLD'
    local skin = { code = 'feed_default', label = '기본', color = '#ffffff', style = { theme = 'default' } }

    if killerSid > 0 and GetPlayerName(killerSid) then
        killerName = getDisplayName(killerSid)
        local active = getActiveForSource(killerSid)
        if active.killfeed_skin then skin = active.killfeed_skin end
    end

    local payload = {
        killer = killerName,
        victim = victimName,
        weapon = tostring(weaponLabel or 'UNKNOWN'):sub(1, 48),
        weaponIcon = cookieResolveWeaponIcon(weaponHash),
        headshot = headshot == true,
        distance = math.floor(math.max(0, math.min(9999, tonumber(distance) or 0)) + 0.5),
        theme = (skin.style and skin.style.theme) or 'default',
        accent = skin.color or '#ffffff',
        duration = Config.KillfeedDuration or 7000
    }

    TriggerClientEvent('cookie_identityfx:client:killfeed', -1, payload)
end)

if Config.InterceptDefaultChat then
    AddEventHandler('chatMessage', function(src, name, message)
        if not src or src <= 0 then return end
        message = tostring(message or '')
        if message == '' or message:sub(1, 1) == '/' then return end

        CancelEvent()

        local active = getActiveForSource(src)
        local title = active.chat_title
        local args

        if title then
            args = {
                ('[%s]'):format(title.label),
                getDisplayName(src),
                message
            }
        else
            args = {
                '',
                getDisplayName(src),
                message
            }
        end

        TriggerClientEvent('chat:addMessage', -1, {
            color = {255, 255, 255},
            multiline = true,
            template = '<div style="padding:2px 0"><span style="color:{0};font-weight:800">{1}</span> <span style="font-weight:700">{2}</span>: <span>{3}</span></div>',
            args = {
                title and title.color or '#ffffff',
                args[1],
                args[2],
                args[3]
            }
        })
    end)
end

RegisterCommand(Config.UserCommand or 'titles', function(src)
    if src <= 0 then return end
    sendSelfData(src, 'user')
end, false)

RegisterCommand(Config.AdminCommand or 'cookieidentity', function(src)
    if src <= 0 then
        print('[cookie_identityfx] In-game command only.')
        return
    end
    if not isAdmin(src) then
        TriggerClientEvent('chat:addMessage', src, { args = { '^1COOKIE', '권한이 없습니다.' } })
        return
    end
    sendSelfData(src, 'admin')
    TriggerClientEvent('cookie_identityfx:client:adminData', src, adminPayload())
end, false)

RegisterCommand('cookiegrantcosmetic', function(src, args)
    if src ~= 0 and not isAdmin(src) then return end

    local target = tonumber(args[1])
    local code = sanitizeCode(args[2])
    if not target or code == '' then
        print('usage: cookiegrantcosmetic [serverId] [code]')
        return
    end

    local cid = getCitizenId(target)
    if not cid then
        print('[cookie_identityfx] target not online')
        return
    end

    local exists = MySQL.single.await('SELECT code FROM cookie_cosmetic_catalog WHERE code = ? AND enabled = 1', { code })
    if not exists then
        print('[cookie_identityfx] unknown code: ' .. code)
        return
    end

    MySQL.query.await([[
        INSERT INTO cookie_cosmetic_ownership (citizenid, code, active, granted_by)
        VALUES (?, ?, 0, ?)
        ON DUPLICATE KEY UPDATE granted_by = VALUES(granted_by)
    ]], { cid, code, src == 0 and 'console' or (getCitizenId(src) or tostring(src)) })

    refreshCache(cid)
    sendSelfData(target, 'user')
    print(('[cookie_identityfx] granted %s to %s'):format(code, cid))
end, false)

exports('GetChatTitle', function(src)
    src = tonumber(src)
    if not src then return nil end
    local active = getActiveForSource(src)
    local title = active and active.chat_title or nil
    if not title then return nil end
    return {
        text = tostring(title.label or ''),
        color = tostring(title.color or '#FFE08A'),
        bg = '#251B0B',
    }
end)

exports('IsIdentityAdmin', isAdmin)
