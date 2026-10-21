local function clean(value, maxLen)
    local s=tostring(value or ''):gsub('[%z\1-\31]',' '):gsub('^%s+',''):gsub('%s+$','')
    if maxLen and #s>maxLen then s=s:sub(1,maxLen) end
    return s
end

local function getLicense(src)
    return GetPlayerIdentifierByType(src,'license2')
        or GetPlayerIdentifierByType(src,'license')
end

local function sourceByCitizenid(cid)
    cid=tostring(cid or '')
    if cid=='' then return nil end

    for _,raw in ipairs(GetPlayers()) do
        local src=tonumber(raw)
        local p=src and exports.qbx_core:GetPlayer(src) or nil
        local pd=p and p.PlayerData or nil
        if pd and tostring(pd.citizenid or '')==cid then
            return src
        end
    end
    return nil
end

local function playerMetaFromSource(src)
    local p=exports.qbx_core:GetPlayer(src)
    local pd=p and p.PlayerData or nil
    local citizenid=pd and tostring(pd.citizenid or '') or ''

    local gobun,name
    pcall(function() gobun=exports.cookie_core:getGobun(src) end)
    pcall(function() name=exports.cookie_core:getNickname(src) end)
    if not name or name=='' then name=GetPlayerName(src) or '-' end

    return {
        citizenid=citizenid,
        gobun=tonumber(gobun),
        name=clean(name,80),
    }
end

local function webhookUrl(category)
    category=tostring(category or 'license'):lower()

    local map={
        license='cookie_log_license',
        police_license='cookie_log_police_license',
        security_license='cookie_log_security_license',
    }

    local direct=''
    if type(Config.DiscordWebhooks)=='table' then
        direct=clean(Config.DiscordWebhooks[category],700)
    end
    if direct~='' then return direct end

    local convar=map[category] or map.license
    return clean(GetConvar(convar,''),700)
end

local function discordLog(category, title, description, fields)
    local url=webhookUrl(category)
    if url=='' then return end

    local payload={
        username=Config.DiscordBotName or 'COOKIE 면허 로그',
        avatar_url=(clean(Config.DiscordAvatarURL,700)~='' and Config.DiscordAvatarURL or nil),
        allowed_mentions={parse={}},
        embeds={{
            title=clean(title,256),
            description=clean(description,4096)~='' and clean(description,4096) or nil,
            color=0xD7A34F,
            fields=fields or {},
            timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ'),
            footer={text='COOKIE SERVER · DRIVER LICENSE'}
        }}
    }

    PerformHttpRequest(url,function(status)
        status=tonumber(status) or 0
        if status<200 or status>=300 then
            print(('[cookie_license] Discord HTTP ERROR %s'):format(status))
        end
    end,'POST',json.encode(payload),{['Content-Type']='application/json'})
end

local function formatNo(id)
    local digits=math.max(4,tonumber(Config.NumberDigits) or 6)
    return tostring(Config.NumberPrefix or 'CKD-') .. string.format('%0'..digits..'d',tonumber(id) or 0)
end

local function selectByUserLicense(userLicense)
    return MySQL.single.await([[
        SELECT id,user_license,citizenid,gobun,holder_name,license_no,
               UNIX_TIMESTAMP(issued_at) AS issued_at_ts,
               UNIX_TIMESTAMP(suspended_until) AS suspended_until_ts,
               suspend_reason,suspended_by_type,suspended_by_name,suspended_by_faction,
               UNIX_TIMESTAMP(suspended_at) AS suspended_at_ts
        FROM cookie_driver_license
        WHERE user_license=?
        LIMIT 1
    ]],{userLicense})
end

local function decorate(row)
    if not row then return nil end

    local untilTs=tonumber(row.suspended_until_ts)
    local suspended=untilTs and untilTs>os.time() or false

    return {
        id=tonumber(row.id),
        licenseNo=tostring(row.license_no or ''),
        citizenid=tostring(row.citizenid or ''),
        gobun=tonumber(row.gobun),
        name=tostring(row.holder_name or ''),
        issuedAt=tonumber(row.issued_at_ts),
        suspended=suspended,
        status=suspended and 'suspended' or 'valid',
        statusLabel=suspended and '정지' or '정상',
        suspendedUntil=untilTs,
        remainingSeconds=suspended and math.max(0,untilTs-os.time()) or 0,
        reason=suspended and tostring(row.suspend_reason or '') or '',
        suspendedByType=suspended and tostring(row.suspended_by_type or '') or '',
        suspendedByName=suspended and tostring(row.suspended_by_name or '') or '',
        suspendedByFaction=suspended and tostring(row.suspended_by_faction or '') or '',
    }
end

local function ensureByLicense(userLicense,citizenid,gobun,name)
    userLicense=clean(userLicense,100)
    citizenid=clean(citizenid,64)
    name=clean(name,80)
    gobun=tonumber(gobun)

    if userLicense=='' then return nil,false end

    MySQL.insert.await([[
        INSERT IGNORE INTO cookie_driver_license
          (user_license,citizenid,gobun,holder_name)
        VALUES (?,?,?,?)
    ]],{
        userLicense,
        citizenid~='' and citizenid or nil,
        gobun,
        name~='' and name or nil
    })

    local row=selectByUserLicense(userLicense)
    if not row then return nil,false end

    local changed=false
    if not row.license_no or tostring(row.license_no)=='' then
        local no=formatNo(row.id)
        MySQL.update.await(
            'UPDATE cookie_driver_license SET license_no=? WHERE id=? AND (license_no IS NULL OR license_no="")',
            {no,row.id}
        )
        row=selectByUserLicense(userLicense)
        changed=true
    end

    if citizenid~='' or gobun or name~='' then
        MySQL.update.await([[
            UPDATE cookie_driver_license
            SET citizenid=COALESCE(NULLIF(?,''),citizenid),
                gobun=COALESCE(?,gobun),
                holder_name=COALESCE(NULLIF(?,''),holder_name)
            WHERE id=?
        ]],{citizenid,gobun,name,row.id})
        row=selectByUserLicense(userLicense)
    end

    return decorate(row),changed
end

local function ensureForSource(src,notifyNew)
    src=tonumber(src)
    if not src or not GetPlayerName(src) then return nil,false end

    local userLicense=getLicense(src)
    if not userLicense then return nil,false end

    local user=MySQL.single.await(
        'SELECT gobun,nickname FROM cookie_user WHERE license=? LIMIT 1',
        {userLicense}
    )

    -- license2/license prefix가 달라진 기존 데이터도 대응.
    if not user then
        user=MySQL.single.await([[
            SELECT license,gobun,nickname
            FROM cookie_user
            WHERE SUBSTRING_INDEX(license,':',-1)=SUBSTRING_INDEX(?,':',-1)
            LIMIT 1
        ]],{userLicense})
        if user and user.license then userLicense=user.license end
    end

    if not user then return nil,false end

    local meta=playerMetaFromSource(src)
    local row,created=ensureByLicense(
        userLicense,
        meta.citizenid,
        user.gobun or meta.gobun,
        user.nickname or meta.name
    )

    if row and created and notifyNew then
        TriggerClientEvent('ox_lib:notify',src,{
            title='운전면허 발급',
            description=('운전면허가 발급되었습니다. 면허번호: %s'):format(row.licenseNo),
            type='success'
        })
    end

    return row,created
end

local function ensureByCitizenid(cid)
    cid=clean(cid,64)
    if cid=='' then return nil end

    local row=MySQL.single.await([[
        SELECT p.citizenid,p.license,
               cu.license AS cookie_license,cu.gobun,cu.nickname
        FROM players p
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE p.citizenid=?
        LIMIT 1
    ]],{cid})

    if not row then return nil end

    local userLicense=row.cookie_license or row.license
    return select(1,ensureByLicense(
        userLicense,
        row.citizenid,
        row.gobun,
        row.nickname
    ))
end

local function getByCitizenid(cid)
    cid=clean(cid,64)
    if cid=='' then return nil end

    local row=MySQL.single.await([[
        SELECT dl.id,dl.user_license,dl.citizenid,dl.gobun,dl.holder_name,dl.license_no,
               UNIX_TIMESTAMP(dl.issued_at) AS issued_at_ts,
               UNIX_TIMESTAMP(dl.suspended_until) AS suspended_until_ts,
               dl.suspend_reason,dl.suspended_by_type,dl.suspended_by_name,dl.suspended_by_faction,
               UNIX_TIMESTAMP(dl.suspended_at) AS suspended_at_ts
        FROM players p
        JOIN cookie_driver_license dl
          ON SUBSTRING_INDEX(dl.user_license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE p.citizenid=?
        LIMIT 1
    ]],{cid})

    if not row then return nil end
    return decorate(row)
end

local function insertHistory(row,action,minutes,reason,actor)
    MySQL.insert.await([[
        INSERT INTO cookie_driver_license_history
          (license_id,license_no,target_citizenid,target_gobun,target_name,
           action,minutes,reason,actor_source,actor_type,actor_name,actor_faction)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
    ]],{
        row.id,row.licenseNo,row.citizenid,row.gobun,row.name,
        action,minutes,clean(reason,300),
        actor and tonumber(actor.source) or nil,
        actor and clean(actor.type,32) or nil,
        actor and clean(actor.name,80) or nil,
        actor and clean(actor.faction,80) or nil
    })
end

local function logAction(title,row,reason,minutes,actor,untilTs)
    local actorText='SYSTEM'
    if actor then
        actorText=('%s%s'):format(
            clean(actor.name,80)~='' and clean(actor.name,80) or ('SID '..tostring(actor.source or '-')),
            clean(actor.faction,80)~='' and (' · '..clean(actor.faction,80)) or ''
        )
    end

    local targetText=('%s / %s'):format(
        tostring(row.gobun or '-'),
        tostring(row.name or '-')
    )

    local fields={
        {name='대상',value=targetText,inline=true},
        {name='운전면허번호',value='`'..clean(row.licenseNo,80)..'`',inline=true},
        {name='처리자',value=actorText,inline=false},
    }

    if minutes and tonumber(minutes) and tonumber(minutes)>0 then
        fields[#fields+1]={name='정지시간',value=tostring(math.floor(tonumber(minutes)))..'분',inline=true}
    end
    if untilTs then
        fields[#fields+1]={name='정지 종료',value=os.date('%Y-%m-%d %H:%M:%S',untilTs),inline=true}
    end
    if clean(reason,300)~='' then
        fields[#fields+1]={name='사유 / 죄목',value=clean(reason,300),inline=false}
    end

    local category='license'
    if actor and tostring(actor.type or '')=='police' then
        category='police_license'
    elseif actor and tostring(actor.type or '')=='security' then
        category='security_license'
    end

    discordLog(category,title,'',fields)
end

local function suspendCitizen(cid,minutes,reason,actor)
    minutes=math.floor(tonumber(minutes) or 0)
    if minutes<(Config.MinSuspendMinutes or 1) or minutes>(Config.MaxSuspendMinutes or 60) then
        return false,('정지시간은 %d~%d분으로 입력해주세요.'):format(
            Config.MinSuspendMinutes or 1,
            Config.MaxSuspendMinutes or 60
        )
    end

    reason=clean(reason,300)
    if #reason<2 then return false,'정지 사유/죄목을 2자 이상 입력해주세요.' end

    local row=getByCitizenid(cid)
    if not row then return false,'대상의 운전면허 정보를 찾을 수 없습니다.' end

    local untilTs=os.time()+(minutes*60)

    -- 더 긴 정지가 이미 남아 있으면 짧은 새 처리가 기존 정지를 단축하지 않는다.
    if row.suspended and tonumber(row.suspendedUntil) and tonumber(row.suspendedUntil)>untilTs then
        untilTs=tonumber(row.suspendedUntil)
    end

    MySQL.update.await([[
        UPDATE cookie_driver_license
        SET suspended_until=FROM_UNIXTIME(?),
            suspend_reason=?,
            suspended_by_type=?,
            suspended_by_name=?,
            suspended_by_faction=?,
            suspended_at=NOW(),
            restored_at=NULL
        WHERE id=?
    ]],{
        untilTs,
        reason,
        actor and clean(actor.type,32) or 'system',
        actor and clean(actor.name,80) or 'SYSTEM',
        actor and clean(actor.faction,80) or '',
        row.id
    })

    row=getByCitizenid(cid) or row
    insertHistory(row,'suspend',minutes,reason,actor)
    logAction('운전면허 정지',row,reason,minutes,actor,untilTs)

    local target=sourceByCitizenid(cid)
    if target then
        TriggerClientEvent('ox_lib:notify',target,{
            title='운전면허 정지',
            description=('%d분간 운전면허가 정지되었습니다. 사유: %s'):format(minutes,reason),
            type='error'
        })
    end

    return true,row
end

local function restoreCitizen(cid,reason,actor,automatic)
    reason=clean(reason,300)
    if not automatic and #reason<2 then
        return false,'정지 해제 사유를 2자 이상 입력해주세요.'
    end

    local row=getByCitizenid(cid)
    if not row then return false,'대상의 운전면허 정보를 찾을 수 없습니다.' end

    -- 이미 정상이어도 성공 처리하되 중복 로그는 남기지 않는다.
    if not row.suspended then
        return true,row,'이미 정상 상태입니다.'
    end

    MySQL.update.await([[
        UPDATE cookie_driver_license
        SET suspended_until=NULL,
            suspend_reason=NULL,
            suspended_by_type=NULL,
            suspended_by_name=NULL,
            suspended_by_faction=NULL,
            restored_at=NOW()
        WHERE id=?
    ]],{row.id})

    local action=automatic and 'auto_restore' or 'restore'
    local logReason=automatic and '정지시간 만료' or reason

    row=getByCitizenid(cid) or row
    insertHistory(row,action,nil,logReason,actor)

    if not automatic or Config.LogAutomaticRestore then
        logAction(
            automatic and '운전면허 정지 자동 해제' or '운전면허 정지 해제',
            row,logReason,nil,actor,nil
        )
    end

    local target=sourceByCitizenid(cid)
    if target then
        TriggerClientEvent('ox_lib:notify',target,{
            title='운전면허',
            description=automatic and '운전면허 정지시간이 만료되어 정상 복구되었습니다.'
                or '운전면허 정지가 해제되었습니다.',
            type='success'
        })
    end

    return true,row
end

local function getExistingForSource(src)
    src=tonumber(src)
    if not src then return nil end

    local userLicense=getLicense(src)
    if not userLicense then return nil end

    local row=selectByUserLicense(userLicense)
    if not row then
        local u=MySQL.single.await([[
            SELECT license
            FROM cookie_user
            WHERE SUBSTRING_INDEX(license,':',-1)=SUBSTRING_INDEX(?,':',-1)
            LIMIT 1
        ]],{userLicense})
        if u and u.license then row=selectByUserLicense(u.license) end
    end
    return decorate(row)
end

-- 명시적인 발급용. 뉴비 시청 단계에서만 이 export를 사용한다.
exports('IssueForSource',function(src)
    return ensureForSource(src,true)
end)

-- 하위 호환용: 이름은 유지하되 새 코드에서는 IssueForSource 사용 권장.
exports('EnsureForSource',function(src)
    return ensureForSource(src,false)
end)

-- 조회는 더 이상 자동 발급하지 않는다.
exports('GetBySource',function(src)
    return getExistingForSource(src)
end)

exports('GetByCitizenId',function(cid)
    return getByCitizenid(cid)
end)

exports('SuspendByCitizenId',function(cid,minutes,reason,actor)
    return suspendCitizen(cid,minutes,reason,type(actor)=='table' and actor or nil)
end)

exports('RestoreByCitizenId',function(cid,reason,actor)
    return restoreCitizen(cid,reason,type(actor)=='table' and actor or nil,false)
end)

-- V1.3: 접속만으로 운전면허를 자동 발급하지 않는다.
-- 뉴비 시청의 '운전면허 발급' 단계를 통과해야 생성된다.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded',function()
    -- intentionally no-op
end)

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_driver_license (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            user_license VARCHAR(100) NOT NULL,
            citizenid VARCHAR(64) NULL,
            gobun INT NULL,
            holder_name VARCHAR(80) NULL,
            license_no VARCHAR(40) NULL,
            issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            suspended_until DATETIME NULL,
            suspend_reason VARCHAR(300) NULL,
            suspended_by_type VARCHAR(32) NULL,
            suspended_by_name VARCHAR(80) NULL,
            suspended_by_faction VARCHAR(80) NULL,
            suspended_at DATETIME NULL,
            restored_at DATETIME NULL,
            PRIMARY KEY(id),
            UNIQUE KEY uq_driver_user_license(user_license),
            UNIQUE KEY uq_driver_license_no(license_no),
            KEY idx_driver_citizenid(citizenid),
            KEY idx_driver_gobun(gobun),
            KEY idx_driver_suspended(suspended_until)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_driver_license_history (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            license_id BIGINT UNSIGNED NOT NULL,
            license_no VARCHAR(40) NOT NULL,
            target_citizenid VARCHAR(64) NULL,
            target_gobun INT NULL,
            target_name VARCHAR(80) NULL,
            action VARCHAR(24) NOT NULL,
            minutes INT NULL,
            reason VARCHAR(300) NULL,
            actor_source INT NULL,
            actor_type VARCHAR(32) NULL,
            actor_name VARCHAR(80) NULL,
            actor_faction VARCHAR(80) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(id),
            KEY idx_driver_history_license(license_id,created_at),
            KEY idx_driver_history_target(target_citizenid,created_at),
            KEY idx_driver_history_action(action,created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    if Config.BackfillExistingCitizens then
        local rows=MySQL.query.await([[
            SELECT cu.license,cu.gobun,cu.nickname,p.citizenid
            FROM cookie_user cu
            LEFT JOIN players p
              ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
               = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
            WHERE cu.nickname IS NOT NULL AND cu.nickname<>''
              AND cu.consent_at IS NOT NULL
            ORDER BY cu.gobun ASC
        ]]) or {}

        local count=0
        for _,r in ipairs(rows) do
            local row,created=ensureByLicense(
                r.license,
                r.citizenid,
                r.gobun,
                r.nickname
            )
            if row and created then count=count+1 end
        end

        print(('^2[cookie_license]^7 driver license ready · backfill issued %d'):format(count))
    else
        print('^2[cookie_license]^7 driver license ready')
    end
end)

CreateThread(function()
    while true do
        Wait(math.max(10,tonumber(Config.ExpirySweepSeconds) or 60)*1000)

        local rows=MySQL.query.await([[
            SELECT dl.citizenid
            FROM cookie_driver_license dl
            WHERE dl.suspended_until IS NOT NULL
              AND dl.suspended_until<=NOW()
        ]]) or {}

        for _,r in ipairs(rows) do
            if r.citizenid and tostring(r.citizenid)~='' then
                restoreCitizen(r.citizenid,'정지시간 만료',nil,true)
            else
                -- citizenid가 없는 초기 레코드도 DB 상태는 정상화.
                MySQL.update.await([[
                    UPDATE cookie_driver_license
                    SET suspended_until=NULL,
                        suspend_reason=NULL,
                        suspended_by_type=NULL,
                        suspended_by_name=NULL,
                        suspended_by_faction=NULL,
                        restored_at=NOW()
                    WHERE citizenid IS NULL AND suspended_until IS NOT NULL AND suspended_until<=NOW()
                ]])
            end
        end
    end
end)

RegisterCommand('cookielicenselogtest',function(src,args)
    if src~=0 then return end

    local category=tostring(args and args[1] or 'license'):lower()
    local allowed={
        license=true,
        police_license=true,
        security_license=true,
    }

    if not allowed[category] then
        print('[cookie_license] 사용법: cookielicenselogtest license|police_license|security_license')
        return
    end

    local url=webhookUrl(category)
    if url=='' then
        local names={
            license='cookie_log_license',
            police_license='cookie_log_police_license',
            security_license='cookie_log_security_license',
        }
        print(('[cookie_license] %s WEBHOOK EMPTY · %s 설정 필요'):format(
            category,names[category]
        ))
        return
    end

    discordLog(category,'COOKIE 면허 로그 테스트','웹훅 연결 테스트입니다.',{
        {name='카테고리',value=category,inline=true},
        {name='상태',value='정상',inline=true}
    })
    print(('[cookie_license] %s 면허 로그 테스트 전송 요청 완료'):format(category))
end,true)
