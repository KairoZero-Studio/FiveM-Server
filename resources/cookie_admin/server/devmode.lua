local DEV_SETTING_ID = 1
local devModeEnabled = false
local devModeMessage = '현재 개발 중인 서버입니다. 허가된 관리자/테스터만 접속할 수 있습니다.'
local devModeReady = false

-- cookie_admin 본체(server/main.lua)와 동일한 식별자 우선순위를 사용한다.
-- 기존 코드는 license: 를 먼저 반환했지만 관리자 DB는 license2: 를 우선 저장/조회해서,
-- 실제 LV5 관리자도 개발모드에서 권한 없음으로 판정되는 문제가 있었다.
local function devLicense(src)
    local license2 = GetPlayerIdentifierByType(src, 'license2')
    if license2 and license2 ~= '' then return license2 end

    local license = GetPlayerIdentifierByType(src, 'license')
    if license and license ~= '' then return license end

    -- 일부 환경에서 GetPlayerIdentifierByType 결과가 비어 있을 때를 위한 안전한 폴백.
    local fallback = nil
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:sub(1,9) == 'license2:' then return id end
        if not fallback and id:sub(1,8) == 'license:' then fallback = id end
    end
    return fallback
end

local function validLicense(lic)
    return type(lic) == 'string' and lic:match('^license2?:[%x]+$') ~= nil
end

local function trim(v)
    if type(v) ~= 'string' then return '' end
    return (v:gsub('^%s+',''):gsub('%s+$',''))
end

local function maskedLicense(lic)
    lic=tostring(lic or '')
    local pfx,body=lic:match('^(license2?:)(.+)$')
    if not pfx then return lic end
    if #body <= 12 then return pfx..body end
    return pfx..body:sub(1,6)..'••••••'..body:sub(-6)
end

local function devNotify(src,msg,err)
    TriggerClientEvent('cookie_admin:client:notify',src,tostring(msg or ''),err and true or false)
end

local function hasManagePermission(src)
    local lic=devLicense(src)
    if not lic then return false end
    local row=MySQL.single.await([[
        SELECT admin_level,is_active,pw_hash
        FROM cookie_admin
        WHERE license=?
        LIMIT 1
    ]],{lic})
    if not row then return false end
    local active=(row.is_active==1 or row.is_active==true)
    local level=tonumber(row.admin_level) or 0
    return active and level>=5 and row.pw_hash~=nil
end

local function adminAutoAllowed(lic)
    if not lic then return false end
    local row=MySQL.single.await([[
        SELECT admin_level,is_active
        FROM cookie_admin
        WHERE license=?
        LIMIT 1
    ]],{lic})
    if not row then return false end
    return (row.is_active==1 or row.is_active==true) and (tonumber(row.admin_level) or 0)>=1
end

local function whitelistRow(lic)
    if not lic then return nil end
    return MySQL.single.await([[
        SELECT license,label,note,added_by,added_at,last_seen_name,last_join_at
        FROM cookie_devmode_whitelist
        WHERE license=?
        LIMIT 1
    ]],{lic})
end

local function isAllowedLicense(lic)
    if not validLicense(lic) then return false,'invalid' end
    if adminAutoAllowed(lic) then return true,'admin' end
    if whitelistRow(lic) then return true,'whitelist' end
    return false,'blocked'
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_devmode_settings (
            id TINYINT NOT NULL PRIMARY KEY DEFAULT 1,
            enabled TINYINT(1) NOT NULL DEFAULT 0,
            deny_message VARCHAR(255) NOT NULL DEFAULT '현재 개발 중인 서버입니다. 허가된 관리자/테스터만 접속할 수 있습니다.',
            updated_by VARCHAR(80) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        INSERT IGNORE INTO cookie_devmode_settings (id,enabled)
        VALUES (1,0)
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_devmode_whitelist (
            license VARCHAR(96) NOT NULL PRIMARY KEY,
            label VARCHAR(80) NULL,
            note VARCHAR(160) NULL,
            added_by VARCHAR(80) NULL,
            added_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            last_seen_name VARCHAR(100) NULL,
            last_join_at TIMESTAMP NULL DEFAULT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

local function loadSettings()
    local row=MySQL.single.await('SELECT enabled,deny_message FROM cookie_devmode_settings WHERE id=?',{DEV_SETTING_ID})
    devModeEnabled=row and (row.enabled==1 or row.enabled==true) or false
    if row and row.deny_message and tostring(row.deny_message)~='' then
        devModeMessage=tostring(row.deny_message)
    end
end

local function adminName(src)
    local lic=devLicense(src)
    if not lic then return GetPlayerName(src) or '-' end
    local row=MySQL.single.await('SELECT admin_name FROM cookie_admin WHERE license=? LIMIT 1',{lic})
    return (row and row.admin_name and tostring(row.admin_name)) or GetPlayerName(src) or '-'
end

local function userInfoByLicense(lic)
    local row=MySQL.single.await('SELECT gobun,nickname FROM cookie_user WHERE license=? LIMIT 1',{lic})
    return row or {}
end

local function onlineRows()
    local rows={}
    for _,id in ipairs(GetPlayers()) do
        local src=tonumber(id)
        local lic=src and devLicense(src)
        if lic then
            local u=userInfoByLicense(lic)
            local admin=adminAutoAllowed(lic)
            local wl=not admin and whitelistRow(lic) or nil
            rows[#rows+1]={
                serverId=src,
                name=GetPlayerName(src) or ('ID '..tostring(src)),
                nickname=(u.nickname and u.nickname~='') and u.nickname or nil,
                gobun=u.gobun,
                license=lic,
                licenseMasked=maskedLicense(lic),
                allowed=admin or wl~=nil,
                reason=admin and 'admin' or (wl and 'whitelist' or 'none')
            }
        end
    end
    table.sort(rows,function(a,b) return (tonumber(a.serverId) or 0)<(tonumber(b.serverId) or 0) end)
    return rows
end

local function whitelistRows()
    local rows=MySQL.query.await([[
        SELECT license,label,note,added_by,added_at,last_seen_name,last_join_at
        FROM cookie_devmode_whitelist
        ORDER BY added_at DESC
    ]]) or {}
    for _,r in ipairs(rows) do
        r.licenseMasked=maskedLicense(r.license)
    end
    return rows
end

local function buildPayload()
    return {
        enabled=devModeEnabled,
        message=devModeMessage,
        autoAdmin=true,
        online=onlineRows(),
        whitelist=whitelistRows()
    }
end

local function pushPayload(src)
    TriggerClientEvent('cookie_admin:client:devModeData',src,buildPayload())
end

local function kickDisallowedOnline(exceptSrc)
    if not devModeEnabled then return end
    CreateThread(function()
        Wait(250)
        for _,id in ipairs(GetPlayers()) do
            local src=tonumber(id)
            if src and src~=tonumber(exceptSrc) then
                local lic=devLicense(src)
                local ok=false
                local success,result=pcall(function()
                    return isAllowedLicense(lic)
                end)
                ok=success and result==true
                if not ok then
                    DropPlayer(src,devModeMessage)
                end
            end
        end
    end)
end

CreateThread(function()
    Wait(600)
    local ok,err=pcall(function()
        ensureTables()
        loadSettings()
    end)
    devModeReady=ok
    if ok then
        print(('^2[cookie_admin]^7 DEVELOPMENT MODE V1.7.9 ready · %s'):format(devModeEnabled and 'ON' or 'OFF'))
    else
        devModeEnabled=false
        print(('^1[cookie_admin]^7 DEVELOPMENT MODE init failed (fail-open): %s'):format(tostring(err)))
    end
end)

AddEventHandler('playerConnecting',function(playerName,setKickReason,deferrals)
    if not devModeReady or not devModeEnabled then return end

    local src=source
    deferrals.defer()
    Wait(0)
    deferrals.update('COOKIE SERVER · 개발모드 접속 권한을 확인하고 있습니다...')

    local lic=devLicense(src)
    if not lic then
        Wait(0)
        deferrals.done(devModeMessage..'\n\n식별자(license)를 확인할 수 없습니다.')
        CancelEvent()
        return
    end

    local ok,allowed,reason=pcall(function()
        local yes,why=isAllowedLicense(lic)
        return yes,why
    end)

    if not ok then
        print(('^1[cookie_admin][devmode]^7 whitelist check error for %s'):format(tostring(lic)))
        Wait(0)
        deferrals.done('개발모드 접속 권한 확인 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.')
        CancelEvent()
        return
    end

    if not allowed then
        print(('^3[cookie_admin][devmode]^7 blocked %s · %s'):format(tostring(playerName),maskedLicense(lic)))
        Wait(0)
        deferrals.done(devModeMessage)
        CancelEvent()
        return
    end

    if reason=='whitelist' then
        pcall(function()
            MySQL.update.await([[
                UPDATE cookie_devmode_whitelist
                SET last_seen_name=?,last_join_at=NOW()
                WHERE license=?
            ]],{tostring(playerName or ''),lic})
        end)
    end

    Wait(0)
    deferrals.done()
end)

RegisterNetEvent('cookie_admin:server:requestDevMode',function()
    local src=source
    if not hasManagePermission(src) then
        return TriggerClientEvent('cookie_admin:client:devModeError',src,'개발모드 관리는 LV5 관리자 인증이 필요합니다.')
    end
    local ok,data=pcall(buildPayload)
    if not ok then
        print(('^1[cookie_admin][devmode]^7 payload failed: %s'):format(tostring(data)))
        return TriggerClientEvent('cookie_admin:client:devModeError',src,'개발모드 데이터를 불러오지 못했습니다.')
    end
    TriggerClientEvent('cookie_admin:client:devModeData',src,data)
end)

RegisterNetEvent('cookie_admin:server:setDevMode',function(data)
    local src=source
    if not hasManagePermission(src) then
        return TriggerClientEvent('cookie_admin:client:devModeError',src,'개발모드 관리 권한이 없습니다.')
    end

    local enabled=data and data.enabled==true
    local message=trim(data and data.message or devModeMessage)
    if message=='' then message='현재 개발 중인 서버입니다. 허가된 관리자/테스터만 접속할 수 있습니다.' end
    message=message:sub(1,255)

    local lic=devLicense(src)
    local by=adminName(src)

    -- 개발모드를 켠 관리자 자신은 명시 화이트리스트에도 자동 등록.
    if enabled and lic then
        MySQL.query.await([[
            INSERT INTO cookie_devmode_whitelist (license,label,note,added_by,last_seen_name,last_join_at)
            VALUES (?,?,?,?,?,NOW())
            ON DUPLICATE KEY UPDATE
                label=COALESCE(NULLIF(label,''),VALUES(label)),
                last_seen_name=VALUES(last_seen_name),
                last_join_at=NOW()
        ]],{lic,by,'개발모드 활성화 관리자 자동 등록',by,GetPlayerName(src) or by})
    end

    MySQL.update.await([[
        UPDATE cookie_devmode_settings
        SET enabled=?,deny_message=?,updated_by=?
        WHERE id=?
    ]],{enabled and 1 or 0,message,by,DEV_SETTING_ID})

    devModeEnabled=enabled
    devModeMessage=message

    devNotify(src,enabled and '개발모드를 켰습니다. 미허용 접속자는 차단됩니다.' or '개발모드를 껐습니다. 일반 접속을 허용합니다.',false)
    pushPayload(src)

    if enabled then kickDisallowedOnline(src) end

    print(('^3[cookie_admin][devmode]^7 %s by %s'):format(enabled and 'ON' or 'OFF',by))
end)

RegisterNetEvent('cookie_admin:server:addDevWhitelist',function(data)
    local src=source
    if not hasManagePermission(src) then
        return TriggerClientEvent('cookie_admin:client:devModeError',src,'개발모드 관리 권한이 없습니다.')
    end

    local lic=nil
    local label=''
    local note=trim(data and data.note or ''):sub(1,160)
    local targetSrc=tonumber(data and data.serverId)

    if targetSrc and GetPlayerName(targetSrc) then
        lic=devLicense(targetSrc)
        local u=lic and userInfoByLicense(lic) or {}
        label=trim(data and data.label or '')
        if label=='' then label=(u.nickname and u.nickname~='' and u.nickname) or GetPlayerName(targetSrc) or ('ID '..targetSrc) end
    else
        lic=trim(data and data.license or '')
        label=trim(data and data.label or '')
    end

    if not validLicense(lic) then
        return devNotify(src,'올바른 license: 식별자를 입력해주세요.',true)
    end
    if label=='' then label='테스터' end
    label=label:sub(1,80)

    local by=adminName(src)
    MySQL.query.await([[
        INSERT INTO cookie_devmode_whitelist (license,label,note,added_by,last_seen_name,last_join_at)
        VALUES (?,?,?,?,NULL,NULL)
        ON DUPLICATE KEY UPDATE
            label=VALUES(label),
            note=VALUES(note),
            added_by=VALUES(added_by)
    ]],{lic,label,note,by})

    devNotify(src,('%s님을 개발 화이트리스트에 추가했습니다.'):format(label),false)
    pushPayload(src)
end)

RegisterNetEvent('cookie_admin:server:removeDevWhitelist',function(data)
    local src=source
    if not hasManagePermission(src) then
        return TriggerClientEvent('cookie_admin:client:devModeError',src,'개발모드 관리 권한이 없습니다.')
    end

    local lic=trim(data and data.license or '')
    if not validLicense(lic) then return end

    MySQL.update.await('DELETE FROM cookie_devmode_whitelist WHERE license=?',{lic})
    devNotify(src,'개발 화이트리스트에서 제거했습니다.',false)
    pushPayload(src)

    if devModeEnabled and not adminAutoAllowed(lic) then
        for _,id in ipairs(GetPlayers()) do
            local target=tonumber(id)
            if target and devLicense(target)==lic then
                DropPlayer(target,devModeMessage)
                break
            end
        end
    end
end)

RegisterNetEvent('cookie_admin:server:refreshDevWhitelist',function()
    local src=source
    if not hasManagePermission(src) then return end
    pushPayload(src)
end)

exports('isDevelopmentMode',function()
    return devModeEnabled
end)
