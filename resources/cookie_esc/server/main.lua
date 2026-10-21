print('^2[COOKIE ESC]^7 build 20260829-AFK-USERLIST loaded')
local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function truthy(v)
    return v == true or tonumber(v) == 1
end

-- cookie_esc는 cookie_admin의 export 등록 시점에 의존하지 않는다.
-- 팩션 생성 시 선택 가능한 정부 타입과 동일한 키를 사용한다.
local GOV_FACTION_TYPES = {
    police = true, security = true, corrections = true, fire = true,
}

local function isGovernmentFactionType(factionType)
    return GOV_FACTION_TYPES[tostring(factionType or '')] == true
end

CreateThread(function()
    Wait(500)
    MySQL.query.await("ALTER TABLE `cookie_user` ADD COLUMN IF NOT EXISTS `status_msg` VARCHAR(60) NULL", {})
end)

local function fetchUser(license)
    if not license then return nil end
    return MySQL.single.await([[
        SELECT gobun, nickname, status_msg, jumin, age, phone,
               COALESCE(rp_minute, 0) AS rp_minute,
               COALESCE(job_minute, 0) AS job_minute
        FROM cookie_user WHERE license = ? LIMIT 1
    ]], { license })
end

local function fetchFaction(citizenid)
    if not citizenid then return nil end
    return MySQL.single.await([[
        SELECT f.id AS faction_id, f.name AS faction, f.color, f.emoji, f.job_name, f.faction_type,
               m.duty, m.grade AS grade_no, r.rank_name AS grade
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id = m.faction_id AND f.is_active = 1
        LEFT JOIN cookie_faction_rank r ON r.faction_id = m.faction_id AND r.grade = m.grade
        WHERE m.citizenid = ? AND m.status = 'active'
        ORDER BY m.id DESC LIMIT 1
    ]], { citizenid })
end

local function getCivilJob(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok, civil = pcall(function()
        return exports.cookie_admin:getCivilJob(src)
    end)
    return ok and civil or nil
end

lib.callback.register('cookie_esc:payload', function(src)
    local player = exports.qbx_core:GetPlayer(src)
    local pd = player and player.PlayerData or nil
    if not pd then return { ok = false } end

    local license = getLicense(src)
    local user = fetchUser(license)
    local ci = pd.charinfo or {}
    local money = pd.money or {}
    local fac = fetchFaction(pd.citizenid)
    if fac and tostring(fac.job_name or '') ~= tostring(pd.job and pd.job.name or '') then fac = nil end
    local civil = fac and nil or getCivilJob(src)

    local driverLicense=nil
    if GetResourceState('cookie_license')=='started' then
        pcall(function()
            driverLicense=exports.cookie_license:GetBySource(src)
        end)
    end

    local jobLabel, orgLabel, gradeLabel, emoji = '시민', '없음', nil, Config.JobEmoji.default
    if fac then
        local gov = isGovernmentFactionType(fac.faction_type)
        local onDuty = truthy(fac.duty)
        orgLabel = fac.faction or '없음'
        gradeLabel = fac.grade or (fac.grade_no and ('G' .. tostring(fac.grade_no))) or nil
        if gov and onDuty then
            jobLabel = fac.faction or '시민'
            emoji = (fac.emoji and fac.emoji ~= '' and fac.emoji) or Config.JobEmoji.default
        elseif not gov then
            -- 사설/범죄 팩션은 소속으로 표시하고 직업 칸은 시민으로 유지한다.
            jobLabel = '시민'
            emoji = Config.JobEmoji.default
        end
    elseif civil then
        jobLabel = civil.label or '시민'
        gradeLabel = civil.level and ('LV%d'):format(tonumber(civil.level) or 1) or nil
        emoji = (civil.emoji and civil.emoji ~= '' and civil.emoji) or Config.JobEmoji.default
    end

    return {
        ok = true,
        gobun = user and user.gobun or nil,
        nick = user and user.nickname or nil,
        status = user and user.status_msg or '',
        rpMin = user and tonumber(user.rp_minute) or 0,
        jobMin = user and tonumber(user.job_minute) or 0,
        phone = (user and user.phone) or ci.phone or nil,
        jumin = user and user.jumin or nil,
        driverLicenseNo = driverLicense and driverLicense.licenseNo or nil,
        driverLicenseStatus = driverLicense and driverLicense.statusLabel or '미발급',
        age = user and tonumber(user.age) or nil,
        job = jobLabel,
        org = orgLabel,
        grade = gradeLabel,
        emoji = emoji,
        cash = tonumber(money.cash) or 0,
        bank = tonumber(money.bank) or 0,
        online = #GetPlayers(),
    }
end)

local function sqlPlaceholders(n)
    local t = {}
    for i = 1, n do t[i] = '?' end
    return table.concat(t, ',')
end

local function sortedSummary(map, fixedFirst)
    local out = {}
    for _, v in pairs(map) do out[#out + 1] = v end
    table.sort(out, function(a, b)
        if fixedFirst and a.key == fixedFirst and b.key ~= fixedFirst then return true end
        if fixedFirst and b.key == fixedFirst and a.key ~= fixedFirst then return false end
        if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
        return tostring(a.label or '') < tostring(b.label or '')
    end)
    return out
end

lib.callback.register('cookie_esc:userlist', function()
    local online, licenses, citizenids = {}, {}, {}
    for _, pid in ipairs(GetPlayers()) do
        local sid = tonumber(pid)
        local player = sid and exports.qbx_core:GetPlayer(sid) or nil
        local pd = player and player.PlayerData or nil
        local license = sid and getLicense(sid) or nil
        if sid and pd and license then
            online[#online + 1] = { sid = sid, pd = pd, license = license, citizenid = pd.citizenid }
            licenses[#licenses + 1] = license
            if pd.citizenid then citizenids[#citizenids + 1] = pd.citizenid end
        end
    end

    local usersByLicense = {}
    if #licenses > 0 then
        local rows = MySQL.query.await(([=[
            SELECT license, gobun, nickname, status_msg FROM cookie_user
            WHERE license IN (%s)
        ]=]):format(sqlPlaceholders(#licenses)), licenses) or {}
        for _, row in ipairs(rows) do usersByLicense[tostring(row.license)] = row end
    end

    -- 활성 팩션 전체를 먼저 만들어 0명이어도 유저리스트에 표시한다.
    local factionCount, factionById = {}, {}
    local factions = MySQL.query.await([[
        SELECT id, name, color, emoji, faction_type, job_name
        FROM cookie_faction WHERE is_active = 1 ORDER BY id
    ]]) or {}
    for _, f in ipairs(factions) do
        local key = tostring(f.id)
        factionById[key] = f
        factionCount[key] = {
            key = key,
            label = f.name or ('팩션 #' .. key),
            emoji = f.emoji or '',
            color = (tostring(f.color or ''):match('^#%x%x%x%x%x%x$') and tostring(f.color):upper()) or '#FFB800',
            count = 0,
            duty = 0,
            gov = isGovernmentFactionType(f.faction_type),
        }
    end

    local memberByCitizen = {}
    if #citizenids > 0 then
        local rows = MySQL.query.await(([=[
            SELECT m.id AS member_id, m.citizenid, m.faction_id, m.duty, m.grade,
                   f.name AS faction, f.color, f.emoji, f.faction_type, f.job_name,
                   r.rank_name AS grade_name
            FROM cookie_faction_member m
            JOIN cookie_faction f ON f.id=m.faction_id AND f.is_active=1
            LEFT JOIN cookie_faction_rank r ON r.faction_id=m.faction_id AND r.grade=m.grade
            WHERE m.status='active' AND m.citizenid IN (%s)
            ORDER BY m.id DESC
        ]=]):format(sqlPlaceholders(#citizenids)), citizenids) or {}
        for _, row in ipairs(rows) do
            local cid = tostring(row.citizenid)
            if not memberByCitizen[cid] then memberByCitizen[cid] = row end
        end
    end

    -- 시민은 인원이 0이어도 항상 고정 노출한다.
    local jobCount = { unemployed = { key = 'unemployed', label = '시민', count = 0, duty = 0 } }
    local out = {}

    for _, info in ipairs(online) do
        local user = usersByLicense[tostring(info.license)]
        local fac = info.citizenid and memberByCitizen[tostring(info.citizenid)] or nil
        if fac and tostring(fac.job_name or '') ~= tostring(info.pd.job and info.pd.job.name or '') then fac = nil end
        local gov = fac and isGovernmentFactionType(fac.faction_type) or false
        local factionOnDuty = fac and truthy(fac.duty) or false
        local civil = fac and nil or getCivilJob(info.sid)
        local afk = Player(info.sid).state.cookieAfk == true

        local jobKey, jobLabel, jobDuty = 'unemployed', '시민', false
        local countInCitizenJob = true
        if fac and gov and factionOnDuty then
            jobLabel = fac.faction or '정부 팩션'
            jobDuty = true
            countInCitizenJob = false -- 출근 중 정부 인원은 팩션 카드에서만 센다.
        elseif fac and not gov then
            jobLabel = '시민'
            countInCitizenJob = false -- 사설/범죄는 팩션 카드에서만 센다.
        elseif civil then
            jobKey = tostring(civil.key or 'unemployed')
            jobLabel = tostring(civil.label or jobKey)
            jobDuty = civil.onDuty == true
        end

        if countInCitizenJob then
            local jc = jobCount[jobKey]
            if not jc then
                jc = { key = jobKey, label = jobLabel, count = 0, duty = 0 }
                jobCount[jobKey] = jc
            end
            jc.count = jc.count + 1
            if jobDuty then jc.duty = jc.duty + 1 end
        end

        local showFaction = false
        if fac then
            if gov then showFaction = factionOnDuty else showFaction = true end
            local fc = factionCount[tostring(fac.faction_id)]
            if fc and showFaction then
                fc.count = fc.count + 1
                if factionOnDuty then fc.duty = fc.duty + 1 end
            end
        end

        if user and user.nickname then
            out[#out + 1] = {
                id = info.sid,
                gobun = user.gobun,
                nick = user.nickname,
                status = user.status_msg or '',
                afk = afk,
                job = jobLabel,
                jobKey = jobKey,
                onduty = jobDuty,
                faction = showFaction and fac.faction or nil,
                factionId = showFaction and tostring(fac.faction_id) or nil,
                factionDuty = showFaction and factionOnDuty or false,
                factionGrade = showFaction and (fac.grade_name or ('G' .. tostring(fac.grade or 0))) or nil,
                factionColor = showFaction and ((tostring(fac.color or ''):match('^#%x%x%x%x%x%x$') and tostring(fac.color):upper()) or '#FFB800') or nil,
            }
        end
    end

    table.sort(out, function(a, b) return (tonumber(a.gobun) or 0) < (tonumber(b.gobun) or 0) end)
    return {
        ok = true,
        list = out,
        summary = {
            total = #out,
            jobs = sortedSummary(jobCount, 'unemployed'),
            factions = sortedSummary(factionCount),
        }
    }
end)

lib.callback.register('cookie_esc:notices', function()
    local rows = MySQL.query.await([[
        SELECT admin_name, reason AS text, DATE_FORMAT(created_at, '%Y.%m.%d %H:%i') AS at
        FROM cookie_admin_chat_action
        WHERE action='notice' AND minutes IS NULL
        ORDER BY id DESC LIMIT 5
    ]]) or {}
    return rows
end)

lib.callback.register('cookie_esc:news', function()
    local rows = MySQL.query.await([[
        SELECT kind, badge, title, body, image, author, DATE_FORMAT(created_at, '%Y.%m.%d') AS date
        FROM cookie_news WHERE active=1 ORDER BY id DESC
    ]]) or {}
    local updates, banners = {}, {}
    for _, r in ipairs(rows) do
        if r.kind == 'banner' then banners[#banners + 1] = r else updates[#updates + 1] = r end
    end
    return { updates = updates, banners = banners }
end)

local EVENT_JOBS = {
    { key='taxi', label='택시기사', title='오픈 택시왕', reward='「초대 택시왕」' },
    { key='trucker', label='트럭커', title='오픈 트럭왕', reward='「초대 트럭왕」' },
    { key='delivery', label='배달기사', title='오픈 배달왕', reward='「초대 배달왕」' },
    { key='labor', label='건설 인부', title='오픈 건설왕', reward='「초대 건설왕」' },
    { key='mechanic', label='정비공', title='오픈 정비왕', reward='「초대 정비왕」' },
}

local JOB_LABELS = {
    taxi='택시기사', trucker='트럭커', delivery='배달기사', labor='건설 인부', mechanic='정비공', unemployed='시민',
}

local tablesReady = false
local function ensureEscDataTables()
    if tablesReady then return end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_job_lifetime_stats (
            license VARCHAR(255) NOT NULL,
            job_key VARCHAR(64) NOT NULL,
            job_label VARCHAR(80) NOT NULL DEFAULT '',
            minute INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (license, job_key), INDEX idx_cookie_job_lifetime_minute (minute)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_fishing_hof (
            id INT PRIMARY KEY DEFAULT 1, citizenid VARCHAR(60) NULL, gobun VARCHAR(20) NULL,
            nickname VARCHAR(60) NULL, species VARCHAR(40) NULL, label VARCHAR(40) NULL,
            kg DOUBLE NOT NULL DEFAULT 0, caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await('INSERT IGNORE INTO cookie_fishing_hof (id, kg) VALUES (1, 0)')
    MySQL.query.await("ALTER TABLE cookie_fishing_hof ADD COLUMN IF NOT EXISTS gobun VARCHAR(20) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_hof ADD COLUMN IF NOT EXISTS nickname VARCHAR(60) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_hof ADD COLUMN IF NOT EXISTS species VARCHAR(40) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_hof ADD COLUMN IF NOT EXISTS label VARCHAR(40) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_hof ADD COLUMN IF NOT EXISTS caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_fishing_rank (
            citizenid VARCHAR(60) NOT NULL PRIMARY KEY, gobun VARCHAR(20) NULL, nickname VARCHAR(60) NULL,
            species VARCHAR(40) NULL, label VARCHAR(40) NULL, kg DOUBLE NOT NULL DEFAULT 0,
            caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_cookie_fishing_rank_kg (kg)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await("ALTER TABLE cookie_fishing_rank ADD COLUMN IF NOT EXISTS gobun VARCHAR(20) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_rank ADD COLUMN IF NOT EXISTS nickname VARCHAR(60) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_rank ADD COLUMN IF NOT EXISTS species VARCHAR(40) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_rank ADD COLUMN IF NOT EXISTS label VARCHAR(40) NULL")
    MySQL.query.await("ALTER TABLE cookie_fishing_rank ADD COLUMN IF NOT EXISTS caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP")
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_state (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY, enabled TINYINT(1) NOT NULL DEFAULT 1,
            started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await('INSERT IGNORE INTO cookie_open_event_state (id, enabled) VALUES (1, 1)')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_user_stats (
            license VARCHAR(255) NOT NULL PRIMARY KEY, rp_minute INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_job_stats (
            license VARCHAR(255) NOT NULL, job_key VARCHAR(64) NOT NULL, job_label VARCHAR(80) NOT NULL DEFAULT '',
            minute INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (license, job_key), INDEX idx_cookie_open_job_minute (minute)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_activity_stats (
            license VARCHAR(255) NOT NULL,
            activity_key VARCHAR(32) NOT NULL,
            seconds BIGINT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (license, activity_key),
            INDEX idx_cookie_open_activity_seconds (activity_key, seconds)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

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

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_playtime_baseline (
            license VARCHAR(255) NOT NULL PRIMARY KEY,
            base_minute BIGINT UNSIGNED NOT NULL DEFAULT 0,
            reset_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_crime_baseline (
            citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
            base_offense BIGINT UNSIGNED NOT NULL DEFAULT 0,
            base_score BIGINT UNSIGNED NOT NULL DEFAULT 0,
            reset_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_job_baseline (
            license VARCHAR(255) NOT NULL,
            job_key VARCHAR(64) NOT NULL,
            base_minute INT NOT NULL DEFAULT 0,
            reset_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(license,job_key),
            INDEX idx_rank_job_base_key(job_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_fishing_current (
            citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
            gobun VARCHAR(20) NULL,nickname VARCHAR(80) NULL,species VARCHAR(40) NULL,label VARCHAR(80) NULL,
            kg DOUBLE NOT NULL DEFAULT 0,caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_rank_fishing_kg(kg)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_mining_current (
            citizenid VARCHAR(64) NOT NULL,mineral VARCHAR(40) NOT NULL,best_purity INT NOT NULL DEFAULT 0,
            mined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid,mineral),INDEX idx_rank_mining_purity(best_purity)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_hidden_job (
            job_key VARCHAR(64) NOT NULL PRIMARY KEY,
            job_label VARCHAR(80) NULL,
            hidden_by VARCHAR(80) NULL,
            hidden_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- MariaDB 12.x는 DEFAULT CHARSET=utf8mb4만 지정하면 uca1400 계열 collation을
    -- 선택할 수 있다. 기존 cookie_user.license와 맞춰 JOIN 오류를 방지한다.
    pcall(function()
        MySQL.query.await([[ALTER TABLE cookie_open_event_user_stats
            MODIFY COLUMN license VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL]])
        MySQL.query.await([[ALTER TABLE cookie_open_event_job_stats
            MODIFY COLUMN license VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL]])
        MySQL.query.await([[ALTER TABLE cookie_job_lifetime_stats
            MODIFY COLUMN license VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL]])
    end)
    tablesReady = true
end

CreateThread(function()
    Wait(1000)
    ensureEscDataTables()
end)

local function rankedRows(rows, myLicense, topN)
    local top, mine = {}, { rank=nil, minute=0 }
    for i, row in ipairs(rows or {}) do
        local item = { rank=i, gobun=tonumber(row.gobun), nickname=row.nickname or '알 수 없음', minute=tonumber(row.minute) or 0 }
        if i <= (topN or 5) then top[#top + 1] = item end
        if myLicense and tostring(row.license) == tostring(myLicense) then mine = item end
    end
    return top, mine
end

local function rankedActivityRowsV168(rows, myLicense, topN)
    local top, mine = {}, { rank=nil, seconds=0 }
    for i,row in ipairs(rows or {}) do
        local item={
            rank=i,
            gobun=tonumber(row.gobun),
            nickname=row.nickname or '알 수 없음',
            seconds=tonumber(row.seconds) or 0,
        }
        if i <= (topN or 10) then top[#top+1]=item end
        if myLicense and tostring(row.license)==tostring(myLicense) then mine=item end
    end
    return top,mine
end

lib.callback.register('cookie_esc:events', function(src)
    ensureEscDataTables()
    local myLicense=getLicense(src)
    local state=MySQL.single.await([[
        SELECT enabled,DATE_FORMAT(started_at,'%Y.%m.%d %H:%i') AS started_at
        FROM cookie_open_event_state WHERE id=1 LIMIT 1
    ]]) or {enabled=1,started_at='-'}

    local allJobRows=MySQL.query.await([[
        SELECT s.license,s.job_key,s.job_label,s.minute,u.gobun,u.nickname
        FROM cookie_open_event_job_stats s
        LEFT JOIN cookie_user u
          ON u.license COLLATE utf8mb4_general_ci=s.license COLLATE utf8mb4_general_ci
        ORDER BY s.job_key ASC,s.minute DESC,u.gobun ASC
    ]]) or {}

    local grouped={}
    for _,row in ipairs(allJobRows) do
        local k=tostring(row.job_key or '')
        grouped[k]=grouped[k] or {}
        grouped[k][#grouped[k]+1]=row
    end

    local events={}
    for _,def in ipairs(EVENT_JOBS) do
        local top,mine=rankedRows(grouped[def.key] or {},myLicense,10)
        events[#events+1]={
            id='open_job_'..def.key,key=def.key,metric='job',
            title=def.title,badge=def.label..' 1위',
            description=('오픈 이벤트 기간 동안 %s 근무시간이 가장 긴 시민이 우승합니다. 다른 직업의 근무시간과는 합산하지 않습니다.'):format(def.label),
            rewards={def.reward},ranking=top,my=mine,
        }
    end

    local activityRows=MySQL.query.await([[
        SELECT s.license,s.activity_key,s.seconds,u.gobun,u.nickname
        FROM cookie_open_event_activity_stats s
        LEFT JOIN cookie_user u
          ON u.license COLLATE utf8mb4_general_ci=s.license COLLATE utf8mb4_general_ci
        WHERE s.activity_key IN ('fishing','mining')
        ORDER BY s.activity_key ASC,s.seconds DESC,u.gobun ASC
    ]]) or {}

    local activityGrouped={fishing={},mining={}}
    for _,row in ipairs(activityRows) do
        local k=tostring(row.activity_key or '')
        if activityGrouped[k] then activityGrouped[k][#activityGrouped[k]+1]=row end
    end

    local fishingTop,fishingMine=rankedActivityRowsV168(activityGrouped.fishing,myLicense,10)
    events[#events+1]={
        id='open_fishing_king',key='fishing',metric='activity',activityKey='fishing',
        title='오픈 낚시왕',badge='낚시시간 1위',
        description='오픈 이벤트 기간 동안 실제 낚시를 가장 오래 진행한 시민이 우승합니다.',
        rewards={'「초대 낚시왕」'},ranking=fishingTop,my=fishingMine,
    }

    local miningTop,miningMine=rankedActivityRowsV168(activityGrouped.mining,myLicense,10)
    events[#events+1]={
        id='open_mining_king',key='mining',metric='activity',activityKey='mining',
        title='오픈 광부왕',badge='광질시간 1위',
        description='오픈 이벤트 기간 동안 실제 광질을 가장 오래 진행한 시민이 우승합니다.',
        rewards={'「초대 광부왕」'},ranking=miningTop,my=miningMine,
    }

    local rpRows=MySQL.query.await([[
        SELECT s.license,s.rp_minute AS minute,u.gobun,u.nickname
        FROM cookie_open_event_user_stats s
        LEFT JOIN cookie_user u
          ON u.license COLLATE utf8mb4_general_ci=s.license COLLATE utf8mb4_general_ci
        ORDER BY s.rp_minute DESC,u.gobun ASC
    ]]) or {}
    local rpTop,rpMine=rankedRows(rpRows,myLicense,10)
    events[#events+1]={
        id='open_playtime',key='playtime',metric='rp',
        title='도시의 개척자',badge='접속시간 1위',
        description='오픈 이벤트 기간 동안 쿠키서버에 가장 오래 접속해 RP 시간을 기록한 시민이 우승합니다.',
        rewards={'「초대 접속왕」'},ranking=rpTop,my=rpMine,
    }

    return {
        ok=true,
        enabled=truthy(state.enabled),
        startedAt=state.started_at or '-',
        events=events
    }
end)

local function appendTopRows(out, rows, valueKey, kind)
    for i,row in ipairs(rows or {}) do
        local item={rank=i,gobun=tonumber(row.gobun),nickname=row.nickname or '알 수 없음',value=tonumber(row[valueKey]) or 0}
        if kind=='fish' then item.fish=row.label or row.species or '물고기'; item.at=row.caught_at or '' end
        out[#out+1]=item
    end
end



local function rankSafeQueryV169(tag, sql, params)
    local ok, result = pcall(function()
        return MySQL.query.await(sql, params or {})
    end)
    if not ok then
        print(('^1[COOKIE ESC][RANK]^7 %s query failed: %s'):format(tostring(tag), tostring(result)))
        return {}
    end
    return result or {}
end

local function rankSafeSingleV169(tag, sql, params)
    local ok, result = pcall(function()
        return MySQL.single.await(sql, params or {})
    end)
    if not ok then
        print(('^1[COOKIE ESC][RANK]^7 %s query failed: %s'):format(tostring(tag), tostring(result)))
        return nil
    end
    return result
end

local ESC_MINERAL_META_V168={
    coal={'석탄','common'},iron={'철광석','common'},copper={'구리광석','common'},
    tin={'주석광석','common'},lead={'납광석','common'},zinc={'아연광석','common'},
    nickel={'니켈광석','uncommon'},bauxite={'보크사이트','uncommon'},quartz={'석영','uncommon'},
    silver={'은광석','rare'},obsidian={'흑요석','rare'},garnet={'가넷','rare'},
    amethyst={'자수정','rare'},topaz={'토파즈','rare'},opal={'오팔','rare'},
    gold={'금광석','epic'},emerald={'에메랄드','epic'},sapphire={'사파이어','epic'},
    ruby={'루비','epic'},diamond={'다이아몬드','legendary'},
}
local ESC_MINERAL_RARITY_RANK_V168={common=1,uncommon=2,rare=3,epic=4,legendary=5}
local ESC_MINERAL_RARITY_LABEL_V168={common='일반',uncommon='고급',rare='희귀',epic='영웅',legendary='전설'}

local function escMineralPurityRowsV168(limit)
    limit=math.max(1,math.min(50,math.floor(tonumber(limit) or 10)))
    local rows=rankSafeQueryV169('mineral_purity',[[
        SELECT c.citizenid,c.mineral,c.best_purity,p.license,u.gobun,u.nickname
        FROM cookie_ranking_mining_current c
        LEFT JOIN players p
          ON p.citizenid COLLATE utf8mb4_unicode_ci =
             c.citizenid COLLATE utf8mb4_unicode_ci
        LEFT JOIN cookie_user u
          ON SUBSTRING_INDEX(u.license,':',-1) COLLATE utf8mb4_unicode_ci =
             SUBSTRING_INDEX(p.license,':',-1) COLLATE utf8mb4_unicode_ci
        WHERE c.best_purity>0
    ]])

    local best={}
    for _,r in ipairs(rows) do
        local meta=ESC_MINERAL_META_V168[tostring(r.mineral or '')]
        if meta then
            local rarity=meta[2]
            local cand={
                citizenid=r.citizenid,license=r.license,
                gobun=tonumber(r.gobun),nickname=r.nickname or '알 수 없음',
                mineral=tostring(r.mineral),mineralLabel=meta[1],
                rarity=rarity,rarityLabel=ESC_MINERAL_RARITY_LABEL_V168[rarity] or rarity,
                rarityRank=ESC_MINERAL_RARITY_RANK_V168[rarity] or 0,
                value=tonumber(r.best_purity) or 0,
            }
            local k=tostring(r.citizenid or '')
            local old=best[k]
            if not old
               or cand.value>old.value
               or (cand.value==old.value and cand.rarityRank>old.rarityRank)
               or (cand.value==old.value and cand.rarityRank==old.rarityRank and cand.mineralLabel<old.mineralLabel) then
                best[k]=cand
            end
        end
    end

    local all={}
    for _,v in pairs(best) do all[#all+1]=v end
    table.sort(all,function(a,b)
        if a.value~=b.value then return a.value>b.value end
        if a.rarityRank~=b.rarityRank then return a.rarityRank>b.rarityRank end
        return (tonumber(a.gobun) or 999999999)<(tonumber(b.gobun) or 999999999)
    end)

    local out={}
    for i=1,math.min(limit,#all) do
        all[i].rank=i
        out[#out+1]=all[i]
    end
    return out
end

lib.callback.register('cookie_esc:rankings', function()
    -- 순위표는 항목 하나의 DB 오류 때문에 전체가 사라지면 안 된다.
    -- 테이블 준비 오류도 기록만 남기고 가능한 항목은 계속 반환한다.
    local okEnsure, ensureErr = pcall(function() ensureEscDataTables() end)
    if not okEnsure then
        print(('^1[COOKIE ESC][RANK]^7 table bootstrap warning: %s'):format(tostring(ensureErr)))
    end

    local categories={}

    -- 1) 낚시 최고 무게
    local fishRows=rankSafeQueryV169('fishing_rank',[[
        SELECT gobun,nickname,label,species,kg,DATE_FORMAT(caught_at,'%Y.%m.%d') AS caught_at
        FROM cookie_ranking_fishing_current WHERE kg>0 ORDER BY kg DESC LIMIT 10
    ]])
    local fish={}; appendTopRows(fish,fishRows,'kg','fish')
    categories[#categories+1]={
        key='fishing',label='낚시 최고 무게',icon='🎣',unit='kg',rows=fish,
        description='각 시민이 낚은 물고기 중 개인 최고 무게를 기준으로 집계합니다.'
    }

    -- 2) 광물 최고 순도
    local mineralPurity=escMineralPurityRowsV168(10)
    categories[#categories+1]={
        key='mineral_purity',label='광물 최고 순도',icon='💎',unit='purity',
        rows=mineralPurity,
        description='각 시민의 최고 순도 광물을 기준으로 집계합니다. 순도가 같으면 광물 등급이 높은 기록이 우선합니다.'
    }

    -- 3) 플레이시간
    local playRows=rankSafeQueryV169('playtime',[[
        SELECT u.gobun,u.nickname,
               GREATEST(COALESCE(u.rp_minute,0)-COALESCE(b.base_minute,0),0) AS minute
        FROM cookie_user u
        LEFT JOIN cookie_ranking_playtime_baseline b
          ON b.license COLLATE utf8mb4_general_ci = u.license COLLATE utf8mb4_general_ci
        WHERE GREATEST(COALESCE(u.rp_minute,0)-COALESCE(b.base_minute,0),0)>0
        ORDER BY minute DESC,u.gobun ASC LIMIT 10
    ]])
    local play={}; appendTopRows(play,playRows,'minute')
    categories[#categories+1]={
        key='playtime',label='플레이시간',icon='⏱',unit='minute',rows=play,
        description='전체 누적 RP 접속시간 기준입니다.'
    }

    -- 4) 직업별 근무시간
    local jobRows=rankSafeQueryV169('job_lifetime',[[
        SELECT s.license,s.job_key,
               CASE WHEN s.job_label='쿠키 경찰국' THEN '경찰청' ELSE s.job_label END AS job_label,
               GREATEST(COALESCE(s.minute,0)-COALESCE(b.base_minute,0),0) AS minute,
               u.gobun,u.nickname
        FROM cookie_job_lifetime_stats s
        LEFT JOIN cookie_user u
          ON u.license COLLATE utf8mb4_general_ci = s.license COLLATE utf8mb4_general_ci
        LEFT JOIN cookie_ranking_job_baseline b
          ON b.license COLLATE utf8mb4_general_ci=s.license COLLATE utf8mb4_general_ci
         AND b.job_key=s.job_key
        LEFT JOIN cookie_ranking_hidden_job h ON h.job_key=s.job_key
        WHERE GREATEST(COALESCE(s.minute,0)-COALESCE(b.base_minute,0),0)>0
          AND h.job_key IS NULL
          AND s.job_label NOT IN ('적월','멍텅구리')
          AND s.job_key NOT IN ('적월','멍텅구리')
        ORDER BY s.job_key ASC,minute DESC,u.gobun ASC
    ]])

    local grouped,labels={},{}
    for _,row in ipairs(jobRows) do
        local key=tostring(row.job_key or '')
        grouped[key]=grouped[key] or {}
        if #grouped[key]<10 then grouped[key][#grouped[key]+1]=row end
        if row.job_label and row.job_label~='' then labels[key]=row.job_label end
    end

    local fixed={'taxi','trucker','delivery','labor','mechanic'}
    local seen={}
    for _,key in ipairs(fixed) do
        seen[key]=true
        local rows={}; appendTopRows(rows,grouped[key] or {},'minute')
        categories[#categories+1]={
            key='job_'..key,label=(JOB_LABELS[key] or labels[key] or key)..' 근무시간',
            icon='★',unit='minute',rows=rows,
            description='해당 직업으로 실제 근무한 누적시간 기준입니다.'
        }
    end

    local extras={}
    for key in pairs(grouped) do
        if not seen[key] and key~='unemployed' then extras[#extras+1]=key end
    end
    table.sort(extras)
    for _,key in ipairs(extras) do
        local rows={}; appendTopRows(rows,grouped[key] or {},'minute')
        categories[#categories+1]={
            key='job_'..key,label=(labels[key] or JOB_LABELS[key] or key)..' 근무시간',
            icon='★',unit='minute',rows=rows,
            description='해당 직업으로 실제 근무한 누적시간 기준입니다.'
        }
    end

    -- 5) 전과 / 범죄점수
    local crimeRows=rankSafeQueryV169('crime',[[
        SELECT s.citizenid,s.gobun,s.nickname,
               GREATEST(s.offense_count-COALESCE(b.base_offense,0),0) AS offense_value,
               GREATEST(s.crime_score-COALESCE(b.base_score,0),0) AS score_value
        FROM cookie_crime_user_stats s
        LEFT JOIN cookie_ranking_crime_baseline b ON b.citizenid=s.citizenid
        WHERE GREATEST(s.offense_count-COALESCE(b.base_offense,0),0)>0
           OR GREATEST(s.crime_score-COALESCE(b.base_score,0),0)>0
        ORDER BY offense_value DESC,score_value DESC,s.gobun ASC
    ]])

    local crimeCount={}
    for _,row in ipairs(crimeRows) do
        if tonumber(row.offense_value)>0 and #crimeCount<10 then
            crimeCount[#crimeCount+1]={
                rank=#crimeCount+1,gobun=tonumber(row.gobun),
                nickname=row.nickname or '알 수 없음',
                value=tonumber(row.offense_value) or 0
            }
        end
    end
    categories[#categories+1]={
        key='crime_count',label='최다 전과',icon='⚖️',unit='count',
        rows=crimeCount,description='순위표 초기화 이후 누적된 전과 죄목 건수를 기준으로 집계합니다.'
    }

    table.sort(crimeRows,function(a,b)
        local av,bv=tonumber(a.score_value) or 0,tonumber(b.score_value) or 0
        if av~=bv then return av>bv end
        local ac,bc=tonumber(a.offense_value) or 0,tonumber(b.offense_value) or 0
        if ac~=bc then return ac>bc end
        return (tonumber(a.gobun) or 999999999)<(tonumber(b.gobun) or 999999999)
    end)

    local crimeScore={}
    for _,row in ipairs(crimeRows) do
        if tonumber(row.score_value)>0 and #crimeScore<10 then
            crimeScore[#crimeScore+1]={
                rank=#crimeScore+1,gobun=tonumber(row.gobun),
                nickname=row.nickname or '알 수 없음',
                value=tonumber(row.score_value) or 0
            }
        end
    end
    categories[#categories+1]={
        key='crime_score',label='범죄점수',icon='🔥',unit='point',
        rows=crimeScore,description='공식 죄목과 강도 RP 패배로 획득한 범죄점수를 기준으로 집계합니다.'
    }

    print(('^2[COOKIE ESC][RANK]^7 response categories=%d'):format(#categories))
    return {
        ok=true,
        categories=categories,
        note='낚시 최고 무게와 광물 최고 순도는 영구 최고 기록입니다. 플레이시간·직업·범죄 순위는 순위표 초기화 기준을 따릅니다.'
    }
end)

RegisterNetEvent('cookie_esc:server:leave', function()
    DropPlayer(source, '서버에서 나갔습니다. 즐거운 하루 되세요!')
end)

lib.callback.register('cookie_esc:setStatus', function(src, text)
    if not Config.StatusEnabled then return {ok=false,reason='상태 메시지 기능이 꺼져 있습니다'} end
    local license=getLicense(src); if not license then return {ok=false,reason='식별 실패'} end
    text=type(text)=='string' and text or ''
    text=text:gsub('^%s+',''):gsub('%s+$','')
    local len=utf8.len(text); if not len then return {ok=false,reason='입력 형식이 올바르지 않습니다'} end
    if len>(Config.StatusMax or 20) then return {ok=false,reason=('%d자 이내로 입력해주세요'):format(Config.StatusMax or 20)} end
    local value=(text=='') and nil or text
    MySQL.update.await('UPDATE cookie_user SET status_msg=? WHERE license=?',{value,license})
    return {ok=true,status=text}
end)

print('^2[COOKIE ESC]^7 EVENT + MINERAL PURITY RANK V1.6.8 active')

print('^2[COOKIE ESC]^7 RANK SEASON RESET V1.7.1 active')


-- ============================================================
-- COOKIE ESC 건의함 V1
-- ============================================================
CreateThread(function()
    Wait(900)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_suggestion (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(64) NULL,
            license VARCHAR(100) NULL,
            gobun INT NULL,
            nickname VARCHAR(80) NULL,
            category VARCHAR(24) NOT NULL DEFAULT 'general',
            title VARCHAR(80) NOT NULL,
            body TEXT NOT NULL,
            status VARCHAR(20) NOT NULL DEFAULT 'new',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(id),
            KEY idx_cookie_suggestion_created(created_at),
            KEY idx_cookie_suggestion_gobun(gobun)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end)

local suggestionCooldown = {}

lib.callback.register('cookie_esc:submitSuggestion', function(src, data)
    data = type(data)=='table' and data or {}
    local now=os.time()
    if (suggestionCooldown[src] or 0)>now then
        return {ok=false,reason='잠시 후 다시 제출해주세요.'}
    end

    local category=tostring(data.category or 'general'):lower()
    if category~='general' and category~='bug' and category~='other' then category='general' end
    local title=tostring(data.title or ''):gsub('^%s+',''):gsub('%s+$',''):sub(1,80)
    local body=tostring(data.body or ''):gsub('^%s+',''):gsub('%s+$',''):sub(1,2000)
    if #title<2 then return {ok=false,reason='제목을 2자 이상 입력해주세요.'} end
    if #body<5 then return {ok=false,reason='내용을 5자 이상 입력해주세요.'} end

    local p=exports.qbx_core:GetPlayer(src)
    local pd=p and p.PlayerData or {}
    local license=getLicense(src)
    local u=fetchUser(license) or {}
    local recent=MySQL.scalar.await([[
        SELECT COUNT(*) FROM cookie_suggestion
        WHERE license=? AND created_at>=DATE_SUB(NOW(),INTERVAL 1 DAY)
    ]],{license}) or 0
    if tonumber(recent)>=10 then return {ok=false,reason='하루 건의 제출 한도(10건)를 초과했습니다.'} end

    local id=MySQL.insert.await([[
        INSERT INTO cookie_suggestion(citizenid,license,gobun,nickname,category,title,body)
        VALUES(?,?,?,?,?,?,?)
    ]],{
        pd.citizenid,license,u.gobun,u.nickname,category,title,body
    })
    if not id then return {ok=false,reason='건의 저장에 실패했습니다.'} end
    suggestionCooldown[src]=now+15
    return {ok=true,id=id}
end)

AddEventHandler('playerDropped',function() suggestionCooldown[source]=nil end)
