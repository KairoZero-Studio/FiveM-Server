local ready=false

local function clean(v,maxLen)
    local s=tostring(v or ''):gsub('[%z\1-\31]',' '):gsub('^%s+',''):gsub('%s+$','')
    if maxLen and #s>maxLen then s=s:sub(1,maxLen) end
    return s
end

local function truthy(v)
    return v==true or tonumber(v)==1
end

local function ensureTables()
    if ready then return true end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_crime_record (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(64) NOT NULL,
            gobun INT NULL,
            nickname VARCHAR(80) NULL,
            offense_count INT UNSIGNED NOT NULL DEFAULT 1,
            crime_score INT UNSIGNED NOT NULL DEFAULT 0,
            fine_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            jail_minutes INT UNSIGNED NOT NULL DEFAULT 0,
            license_minutes INT UNSIGNED NOT NULL DEFAULT 0,
            charges_json LONGTEXT NOT NULL,
            source_type VARCHAR(32) NOT NULL DEFAULT 'police_penalty',
            source_label VARCHAR(120) NULL,
            agency_type VARCHAR(32) NULL,
            agency_name VARCHAR(80) NULL,
            officer_citizenid VARCHAR(64) NULL,
            officer_name VARCHAR(80) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(id),
            KEY idx_cookie_crime_citizen(citizenid,created_at),
            KEY idx_cookie_crime_score(crime_score),
            KEY idx_cookie_crime_created(created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_crime_user_stats (
            citizenid VARCHAR(64) NOT NULL,
            gobun INT NULL,
            nickname VARCHAR(80) NULL,
            record_count INT UNSIGNED NOT NULL DEFAULT 0,
            offense_count INT UNSIGNED NOT NULL DEFAULT 0,
            crime_score BIGINT UNSIGNED NOT NULL DEFAULT 0,
            total_fine BIGINT UNSIGNED NOT NULL DEFAULT 0,
            total_jail_minutes BIGINT UNSIGNED NOT NULL DEFAULT 0,
            total_license_minutes BIGINT UNSIGNED NOT NULL DEFAULT 0,
            robbery_losses INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid),
            KEY idx_cookie_crime_stats_score(crime_score),
            KEY idx_cookie_crime_stats_offense(offense_count)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- 오픈 이벤트 범죄왕 전용 집계.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_crime_stats (
            citizenid VARCHAR(64) NOT NULL,
            gobun INT NULL,
            nickname VARCHAR(80) NULL,
            score BIGINT UNSIGNED NOT NULL DEFAULT 0,
            offense_count INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid),
            KEY idx_cookie_open_crime_score(score)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    ready=true
    return true
end

local function identity(cid)
    cid=clean(cid,64)
    if cid=='' then return nil end

    local row=MySQL.single.await([[
        SELECT p.citizenid,cu.gobun,cu.nickname
        FROM players p
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license,':',-1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE p.citizenid=?
        LIMIT 1
    ]],{cid})

    return {
        citizenid=cid,
        gobun=row and tonumber(row.gobun) or nil,
        nickname=row and clean(row.nickname,80) or '-'
    }
end

local function eventEnabled()
    local exists=MySQL.single.await([[SHOW TABLES LIKE 'cookie_open_event_state']])
    if not exists then return false end
    local row=MySQL.single.await('SELECT enabled FROM cookie_open_event_state WHERE id=1 LIMIT 1')
    return row and truthy(row.enabled) or false
end

local function normalizeCharges(charges)
    local out={}
    local totalScore=0

    if type(charges)~='table' then charges={} end
    for _,x in ipairs(charges) do
        if type(x)=='table' then
            local label=clean(x.label,100)
            if label~='' then
                local score=math.max(0,math.floor(tonumber(x.score) or 0))
                out[#out+1]={
                    id=clean(x.id,64),
                    category=clean(x.category,64),
                    label=label,
                    score=score
                }
                totalScore=totalScore+score
            end
        end
    end

    return out,totalScore
end

local function addRecord(data)
    ensureTables()
    data=type(data)=='table' and data or {}

    local cid=clean(data.citizenid,64)
    if cid=='' then return false,'시민 식별자가 없습니다.' end

    local who=identity(cid)
    local charges,scoreFromCharges=normalizeCharges(data.charges)
    if #charges<1 then return false,'전과 죄목이 없습니다.' end

    local score=math.max(0,math.floor(tonumber(data.crimeScore) or scoreFromCharges))
    local fine=math.max(0,math.floor(tonumber(data.fine) or 0))
    local jail=math.max(0,math.floor(tonumber(data.jailMinutes) or 0))
    local licenseMinutes=math.max(0,math.floor(tonumber(data.licenseMinutes) or 0))
    local sourceType=clean(data.sourceType,32)
    if sourceType=='' then sourceType='police_penalty' end

    local gobun=tonumber(data.gobun) or (who and who.gobun) or nil
    local nickname=clean(data.nickname,80)
    if nickname=='' then nickname=who and who.nickname or '-' end

    local recordId=MySQL.insert.await([[
        INSERT INTO cookie_crime_record
          (citizenid,gobun,nickname,offense_count,crime_score,
           fine_amount,jail_minutes,license_minutes,charges_json,
           source_type,source_label,agency_type,agency_name,
           officer_citizenid,officer_name)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    ]],{
        cid,gobun,nickname,#charges,score,
        fine,jail,licenseMinutes,json.encode(charges),
        sourceType,clean(data.sourceLabel,120),
        clean(data.agencyType,32),clean(data.agencyName,80),
        clean(data.officerCitizenId,64),clean(data.officerName,80)
    })

    local robberyLoss=sourceType=='robbery_loss' and 1 or 0
    MySQL.query.await([[
        INSERT INTO cookie_crime_user_stats
          (citizenid,gobun,nickname,record_count,offense_count,crime_score,
           total_fine,total_jail_minutes,total_license_minutes,robbery_losses)
        VALUES (?,?,?,1,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
          gobun=VALUES(gobun),
          nickname=VALUES(nickname),
          record_count=record_count+1,
          offense_count=offense_count+VALUES(offense_count),
          crime_score=crime_score+VALUES(crime_score),
          total_fine=total_fine+VALUES(total_fine),
          total_jail_minutes=total_jail_minutes+VALUES(total_jail_minutes),
          total_license_minutes=total_license_minutes+VALUES(total_license_minutes),
          robbery_losses=robbery_losses+VALUES(robbery_losses)
    ]],{
        cid,gobun,nickname,#charges,score,
        fine,jail,licenseMinutes,robberyLoss
    })

    if eventEnabled() and score>0 then
        MySQL.query.await([[
            INSERT INTO cookie_open_event_crime_stats
              (citizenid,gobun,nickname,score,offense_count)
            VALUES (?,?,?,?,?)
            ON DUPLICATE KEY UPDATE
              gobun=VALUES(gobun),
              nickname=VALUES(nickname),
              score=score+VALUES(score),
              offense_count=offense_count+VALUES(offense_count)
        ]],{cid,gobun,nickname,score,#charges})
    end

    return true,{
        id=tonumber(recordId),
        citizenid=cid,
        gobun=gobun,
        nickname=nickname,
        offenseCount=#charges,
        crimeScore=score
    }
end

local function summary(cid,limit)
    ensureTables()
    cid=clean(cid,64)
    if cid=='' then return nil end
    limit=math.max(1,math.min(100,math.floor(tonumber(limit) or Config.RecentRecordLimit or 30)))

    local s=MySQL.single.await([[
        SELECT citizenid,gobun,nickname,record_count,offense_count,crime_score,
               total_fine,total_jail_minutes,total_license_minutes,robbery_losses
        FROM cookie_crime_user_stats
        WHERE citizenid=?
        LIMIT 1
    ]],{cid}) or {}

    local rows=MySQL.query.await(([[
        SELECT id,offense_count,crime_score,fine_amount,jail_minutes,license_minutes,
               charges_json,source_type,source_label,agency_type,agency_name,
               officer_name,DATE_FORMAT(created_at,'%%Y-%%m-%%d %%H:%%i') AS created_at
        FROM cookie_crime_record
        WHERE citizenid=?
        ORDER BY id DESC
        LIMIT %d
    ]]):format(limit),{cid}) or {}

    local records={}
    for _,r in ipairs(rows) do
        local charges={}
        if type(r.charges_json)=='string' and r.charges_json~='' then
            local ok,decoded=pcall(json.decode,r.charges_json)
            if ok and type(decoded)=='table' then charges=decoded end
        end
        records[#records+1]={
            id=tonumber(r.id),
            offenseCount=tonumber(r.offense_count) or 0,
            crimeScore=tonumber(r.crime_score) or 0,
            fine=tonumber(r.fine_amount) or 0,
            jailMinutes=tonumber(r.jail_minutes) or 0,
            licenseMinutes=tonumber(r.license_minutes) or 0,
            charges=charges,
            sourceType=r.source_type,
            sourceLabel=r.source_label,
            agencyType=r.agency_type,
            agencyName=r.agency_name,
            officerName=r.officer_name,
            createdAt=r.created_at
        }
    end

    return {
        citizenid=cid,
        gobun=tonumber(s.gobun),
        nickname=s.nickname,
        recordCount=tonumber(s.record_count) or 0,
        offenseCount=tonumber(s.offense_count) or 0,
        crimeScore=tonumber(s.crime_score) or 0,
        totalFine=tonumber(s.total_fine) or 0,
        totalJailMinutes=tonumber(s.total_jail_minutes) or 0,
        totalLicenseMinutes=tonumber(s.total_license_minutes) or 0,
        robberyLosses=tonumber(s.robbery_losses) or 0,
        records=records
    }
end

exports('AddRecord',addRecord)
exports('GetSummaryByCitizenId',summary)

exports('GetRobberyLossDefinition',function(kind)
    local x=Config.RobberyLossScores[tostring(kind or '')]
    if not x then return nil end
    return {label=x.label,score=tonumber(x.score) or 0}
end)

CreateThread(function()
    Wait(500)
    ensureTables()
    print('^2[cookie_crime]^7 criminal record + crime score ready')
end)
