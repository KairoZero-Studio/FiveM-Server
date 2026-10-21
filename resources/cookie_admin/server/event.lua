-- COOKIE OPEN EVENT V1
-- 오픈 이벤트 1: 시민직별 누적 근무시간 1위 (각 직업 독립 집계)
-- 오픈 이벤트 2: 이벤트 기간 RP 접속시간 1위
-- 실제 보상 자동 지급은 이벤트 종료일/차량 모델 확정 후 연결한다.

local eventReady = false
local eventReqAt = {}

local function eventLog(msg)
    print(('^3[COOKIE EVENT]^7 %s'):format(tostring(msg)))
end

local JOB_EVENT_ORDER = { 'taxi', 'trucker', 'delivery', 'labor', 'mechanic' }

local PLAYTIME_EVENT_DEF = {
    id = 'open_playtime',
    metric = 'rp',
    title = '도시의 개척자',
    description = '오픈 이벤트 기간 동안 쿠키서버에 가장 오래 접속해 RP 시간을 기록한 시민이 우승합니다.',
    badge = '접속시간 1위',
    rewards = {
        { kind = '칭호', text = '「초대 접속왕」' },
    },
}

local ACTIVITY_EVENT_DEFS = {
    fishing = {
        id='open_fishing_king', metric='activity', activityKey='fishing', activityLabel='낚시',
        title='오픈 낚시왕', description='오픈 이벤트 기간 동안 실제 낚시를 가장 오래 진행한 시민이 우승합니다.', badge='낚시시간 1위',
        rewards={{kind='칭호',text='「초대 낚시왕」'}},
    },
    mining = {
        id='open_mining_king', metric='activity', activityKey='mining', activityLabel='광질',
        title='오픈 광부왕', description='오픈 이벤트 기간 동안 실제 광질을 가장 오래 진행한 시민이 우승합니다.', badge='광질시간 1위',
        rewards={{kind='칭호',text='「초대 광부왕」'}},
    },
}

local MINERAL_META = {
    coal={'석탄','common'},iron={'철광석','common'},copper={'구리광석','common'},tin={'주석광석','common'},lead={'납광석','common'},zinc={'아연광석','common'},
    nickel={'니켈광석','uncommon'},bauxite={'보크사이트','uncommon'},quartz={'석영','uncommon'},silver={'은광석','rare'},obsidian={'흑요석','rare'},garnet={'가넷','rare'},amethyst={'자수정','rare'},topaz={'토파즈','rare'},opal={'오팔','rare'},
    gold={'금광석','epic'},emerald={'에메랄드','epic'},sapphire={'사파이어','epic'},ruby={'루비','epic'},diamond={'다이아몬드','legendary'},
}
local MINERAL_RARITY_RANK={common=1,uncommon=2,rare=3,epic=4,legendary=5}
local MINERAL_RARITY_LABEL={common='일반',uncommon='고급',rare='희귀',epic='영웅',legendary='전설'}

local function jobEventLabel(jobKey)
    local cfg = Config.CivilJobs and Config.CivilJobs[jobKey]
    return cfg and tostring(cfg.label or jobKey) or tostring(jobKey)
end

local function jobEventTitle(jobKey)
    local label = jobEventLabel(jobKey)
    local special = {
        taxi = '오픈 택시왕',
        trucker = '오픈 트럭왕',
        delivery = '오픈 배달왕',
        labor = '오픈 건설왕',
        mechanic = '오픈 정비왕',
    }
    return special[jobKey] or ('오픈 '..label..' 1위')
end

local function jobEventTitleReward(jobKey)
    local special = {
        taxi = '「초대 택시왕」',
        trucker = '「초대 트럭왕」',
        delivery = '「초대 배달왕」',
        labor = '「초대 건설왕」',
        mechanic = '「초대 정비왕」',
    }
    return special[jobKey] or ('「초대 '..jobEventLabel(jobKey)..'」')
end

local function buildJobEventDefs()
    local defs, seen = {}, {}
    for _, jobKey in ipairs(JOB_EVENT_ORDER) do
        if Config.CivilJobs and Config.CivilJobs[jobKey] then
            seen[jobKey] = true
            local label = jobEventLabel(jobKey)
            defs[#defs + 1] = {
                id = 'open_job_'..jobKey,
                metric = 'job',
                jobKey = jobKey,
                title = jobEventTitle(jobKey),
                description = ('오픈 이벤트 기간 동안 %s 근무시간이 가장 긴 시민이 우승합니다. 다른 직업의 근무시간과는 합산하지 않습니다.'):format(label),
                badge = label..' 1위',
                rewards = {
                    { kind = '칭호', text = jobEventTitleReward(jobKey) },
                },
            }
        end
    end

    -- 추후 Config.CivilJobs에 시민직이 추가되면 이벤트에도 자동으로 붙인다.
    local extras = {}
    for jobKey in pairs(Config.CivilJobs or {}) do
        if not seen[jobKey] then extras[#extras + 1] = tostring(jobKey) end
    end
    table.sort(extras)
    for _, jobKey in ipairs(extras) do
        local label = jobEventLabel(jobKey)
        defs[#defs + 1] = {
            id = 'open_job_'..jobKey,
            metric = 'job',
            jobKey = jobKey,
            title = jobEventTitle(jobKey),
            description = ('오픈 이벤트 기간 동안 %s 근무시간이 가장 긴 시민이 우승합니다. 다른 직업의 근무시간과는 합산하지 않습니다.'):format(label),
            badge = label..' 1위',
            rewards = {
                { kind = '칭호', text = jobEventTitleReward(jobKey) },
            },
        }
    end
    return defs
end

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function ensureEventTables()
    if eventReady then return true end

    -- oxmysql await는 직접 yield하도록 둔다. pcall로 감싸면 FiveM 런타임에서
    -- yield across C-call boundary 문제가 생길 수 있다.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_state (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.insert.await('INSERT IGNORE INTO cookie_open_event_state (id, enabled) VALUES (1, 1)')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_open_event_user_stats (
            license VARCHAR(255) NOT NULL PRIMARY KEY,
            rp_minute INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
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
        CREATE TABLE IF NOT EXISTS cookie_open_event_job_stats (
            license VARCHAR(255) NOT NULL,
            job_key VARCHAR(64) NOT NULL,
            job_label VARCHAR(80) NOT NULL DEFAULT '',
            minute INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (license, job_key),
            INDEX idx_cookie_open_job_minute (minute)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    pcall(function()
        MySQL.query.await([[ALTER TABLE cookie_open_event_user_stats
            MODIFY COLUMN license VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL]])
        MySQL.query.await([[ALTER TABLE cookie_open_event_job_stats
            MODIFY COLUMN license VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL]])
    end)

    eventReady = true
    return true
end

CreateThread(function()
    Wait(1000)
    ensureEventTables()
    eventLog('오픈 이벤트 DB 준비 완료')
end)

local function stateRow()
    if not ensureEventTables() then return { enabled = false, started_at = nil } end
    return MySQL.single.await([[
        SELECT enabled, DATE_FORMAT(started_at, '%Y-%m-%d %H:%i') AS started_at
        FROM cookie_open_event_state WHERE id = 1 LIMIT 1
    ]]) or { enabled = 0, started_at = nil }
end

local function canManage(src)
    local license = licenseOf(src)
    if not license then return false end
    local row = MySQL.single.await([[
        SELECT admin_level FROM cookie_admin
        WHERE license = ? AND is_active = 1 LIMIT 1
    ]], { license })
    return row ~= nil and (tonumber(row.admin_level) or 0) >= 5
end

-- playtime.lua가 매분 호출한다.
function CookieOpenEventAccrue(src, license, job, onJobDuty)
    -- 일일 출석 접속시간은 오픈 이벤트 집계 ON/OFF와 무관하게 매분 누적됩니다.
    if CookieAttendanceAccrue then
        CookieAttendanceAccrue(src, 1)
    end

    -- 퀘스트는 오픈 이벤트 집계 ON/OFF와 무관하게 항상 진행됩니다.
    if CookieQuestAccrue then
        CookieQuestAccrue(src, 'playtime_min', 1)
        if onJobDuty and job and job.name then
            local qJobKey = tostring(job.name):sub(1, 64)
            if Config.CivilJobs and Config.CivilJobs[qJobKey] then
                CookieQuestAccrue(src, 'civil_job_min', 1)
            end
        end
    end

    if not eventReady and not ensureEventTables() then return end
    local st = MySQL.single.await('SELECT enabled FROM cookie_open_event_state WHERE id = 1 LIMIT 1')
    if not st or not (st.enabled == 1 or st.enabled == true) then return end
    license = license or licenseOf(src)
    if not license then return end

    MySQL.query.await([[
        INSERT INTO cookie_open_event_user_stats (license, rp_minute)
        VALUES (?, 1)
        ON DUPLICATE KEY UPDATE rp_minute = rp_minute + 1
    ]], { license })

    if onJobDuty and job and job.name then
        local key = tostring(job.name):sub(1, 64)
        local civil = Config.CivilJobs and Config.CivilJobs[key] or nil
        -- 오픈 직업 이벤트는 쿠키 시민직만 집계한다. 경찰/보안/사설/범죄 팩션은 제외.
        if civil then
            local label = tostring(civil.label or job.label or key):sub(1, 80)
            MySQL.query.await([[
                INSERT INTO cookie_open_event_job_stats (license, job_key, job_label, minute)
                VALUES (?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE minute = minute + 1, job_label = VALUES(job_label)
            ]], { license, key, label })
        end
    end
end

local function accrueActivity(playerSrc, activityKey, seconds)
    activityKey=tostring(activityKey or '')
    if activityKey~='fishing' and activityKey~='mining' then return end
    seconds=math.max(0,math.min(300,math.floor(tonumber(seconds) or 0)))
    if seconds<=0 then return end

    -- 낚시/광질 퀘스트도 오픈 이벤트 집계 상태와 무관하게 진행합니다.
    if CookieQuestAccrue then
        CookieQuestAccrue(playerSrc, activityKey..'_sec', seconds)
    end

    if not eventReady and not ensureEventTables() then return end
    local st=MySQL.single.await('SELECT enabled FROM cookie_open_event_state WHERE id=1 LIMIT 1')
    if not st or not (st.enabled==1 or st.enabled==true) then return end
    local license=licenseOf(tonumber(playerSrc) or 0)
    if not license then return end
    MySQL.query.await([[
        INSERT INTO cookie_open_event_activity_stats (license,activity_key,seconds)
        VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE seconds=seconds+VALUES(seconds)
    ]],{license,activityKey,seconds})
end

-- 서버 내부 리소스(cookie_fishing/cookie_mining)에서만 TriggerEvent로 호출한다.
AddEventHandler('cookie_admin:server:openActivityAccrueInternal',function(playerSrc,activityKey,seconds)
    accrueActivity(playerSrc,activityKey,seconds)
end)

local function buildActivityRanking(activityKey,myLicense)
    local rows=MySQL.query.await([[
        SELECT s.license,s.seconds,u.gobun,u.nickname
        FROM cookie_open_event_activity_stats s
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci=s.license COLLATE utf8mb4_general_ci
        WHERE s.activity_key=?
        ORDER BY s.seconds DESC,u.gobun ASC
    ]],{activityKey}) or {}
    local top,mine={}, {rank=nil,seconds=0,activityKey=activityKey}
    for i,r in ipairs(rows) do
        local item={rank=i,gobun=tonumber(r.gobun),nickname=r.nickname,seconds=tonumber(r.seconds) or 0,activityKey=activityKey}
        if i<=10 then top[#top+1]=item end
        if tostring(r.license)==tostring(myLicense) then mine=item end
    end
    return top,mine
end

local function buildMineralPurityRanking(myLicense)
    local rows=MySQL.query.await([[
        SELECT c.citizenid,c.mineral,c.best_purity,p.license,u.gobun,u.nickname
        FROM cookie_mining_collection c
        LEFT JOIN players p ON p.citizenid=c.citizenid
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci=p.license COLLATE utf8mb4_general_ci
        WHERE c.best_purity>0
    ]]) or {}
    local best={}
    for _,r in ipairs(rows) do
        local meta=MINERAL_META[tostring(r.mineral or '')]
        if meta then
            local rarity=meta[2];local cand={license=r.license,gobun=tonumber(r.gobun),nickname=r.nickname,mineral=r.mineral,mineralLabel=meta[1],rarity=rarity,rarityLabel=MINERAL_RARITY_LABEL[rarity] or rarity,rarityRank=MINERAL_RARITY_RANK[rarity] or 0,purity=tonumber(r.best_purity) or 0}
            local key=tostring(r.citizenid)
            local old=best[key]
            if not old or cand.purity>old.purity or (cand.purity==old.purity and cand.rarityRank>old.rarityRank) then best[key]=cand end
        end
    end
    local all={};for _,v in pairs(best) do all[#all+1]=v end
    table.sort(all,function(a,b)
        if a.purity~=b.purity then return a.purity>b.purity end
        if a.rarityRank~=b.rarityRank then return a.rarityRank>b.rarityRank end
        return (tonumber(a.gobun) or 999999999)<(tonumber(b.gobun) or 999999999)
    end)
    local top,mine={}, {rank=nil,purity=0}
    for i,r in ipairs(all) do
        r.rank=i
        if i<=10 then top[#top+1]=r end
        if r.license and tostring(r.license)==tostring(myLicense) then mine=r end
    end
    return top,mine
end

local function userIdentity(license)
    local r = MySQL.single.await('SELECT gobun, nickname FROM cookie_user WHERE license = ? LIMIT 1', { license })
    return r and tonumber(r.gobun) or nil, r and r.nickname or nil
end

local function buildRpRanking(myLicense)
    local rows = MySQL.query.await([[
        SELECT s.license, s.rp_minute AS minute, u.gobun, u.nickname
        FROM cookie_open_event_user_stats s
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci = s.license COLLATE utf8mb4_general_ci
        ORDER BY s.rp_minute DESC, u.gobun ASC
    ]]) or {}

    local top, mine = {}, { rank = nil, minute = 0 }
    for i, r in ipairs(rows) do
        local item = {
            rank = i,
            gobun = tonumber(r.gobun),
            nickname = r.nickname,
            minute = tonumber(r.minute) or 0,
        }
        if i <= 10 then top[#top + 1] = item end
        if tostring(r.license) == tostring(myLicense) then mine = item end
    end
    return top, mine
end

local function buildJobRanking(jobKey, myLicense)
    local rows = MySQL.query.await([[
        SELECT s.license, s.job_key, s.job_label, s.minute, u.gobun, u.nickname
        FROM cookie_open_event_job_stats s
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci = s.license COLLATE utf8mb4_general_ci
        WHERE s.job_key = ?
        ORDER BY s.minute DESC, u.gobun ASC
    ]], { jobKey }) or {}

    local top, mine = {}, { rank = nil, minute = 0, jobKey = jobKey, jobLabel = jobEventLabel(jobKey) }
    for i, r in ipairs(rows) do
        local item = {
            rank = i,
            gobun = tonumber(r.gobun),
            nickname = r.nickname,
            minute = tonumber(r.minute) or 0,
            jobKey = r.job_key or jobKey,
            jobLabel = r.job_label ~= '' and r.job_label or jobEventLabel(jobKey),
        }
        if i <= 10 then top[#top + 1] = item end
        if tostring(r.license) == tostring(myLicense) then mine = item end
    end
    return top, mine
end

local function buildEventPayload(src)
    local license = licenseOf(src)
    local st = stateRow()
    local rpTop, rpMine = buildRpRanking(license)

    local events = {}
    for _, def in ipairs(buildJobEventDefs()) do
        local ranking, mine = buildJobRanking(def.jobKey, license)
        events[#events + 1] = {
            id = def.id,
            metric = def.metric,
            jobKey = def.jobKey,
            title = def.title,
            description = def.description,
            badge = def.badge,
            rewards = def.rewards,
            ranking = ranking,
            my = mine,
        }
    end

    for _,activityKey in ipairs({'fishing','mining'}) do
        local def=ACTIVITY_EVENT_DEFS[activityKey]
        local ranking,mine=buildActivityRanking(activityKey,license)
        events[#events+1]={id=def.id,metric=def.metric,activityKey=activityKey,activityLabel=def.activityLabel,title=def.title,description=def.description,badge=def.badge,rewards=def.rewards,ranking=ranking,my=mine}
    end

    events[#events + 1] = {
        id = PLAYTIME_EVENT_DEF.id,
        metric = PLAYTIME_EVENT_DEF.metric,
        title = PLAYTIME_EVENT_DEF.title,
        description = PLAYTIME_EVENT_DEF.description,
        badge = PLAYTIME_EVENT_DEF.badge,
        rewards = PLAYTIME_EVENT_DEF.rewards,
        ranking = rpTop,
        my = rpMine,
    }

    return {
        enabled = st.enabled == 1 or st.enabled == true,
        startedAt = st.started_at or '-',
        canManage = canManage(src),
        events = events,
    }
end

local function sendEventData(src, message, isError)
    TriggerClientEvent('cookie_admin:client:openEventData', src, buildEventPayload(src), message, isError == true)
end

RegisterNetEvent('cookie_admin:server:requestOpenEvents', function()
    local src = source
    local now = os.time()
    -- 중복 폭주만 방지. 최초 요청은 항상 처리한다.
    if eventReqAt[src] and (now - eventReqAt[src]) < 1 then return end
    eventReqAt[src] = now
    eventLog(('이벤트 데이터 요청 src=%s'):format(src))
    sendEventData(src)
end)

RegisterNetEvent('cookie_admin:server:toggleOpenEvents', function(enabled)
    local src = source
    if not canManage(src) then return sendEventData(src, '이벤트 관리 권한이 없습니다', true) end
    if not ensureEventTables() then return sendEventData(src, '이벤트 DB 준비에 실패했습니다', true) end
    MySQL.update.await('UPDATE cookie_open_event_state SET enabled = ? WHERE id = 1', { enabled == true and 1 or 0 })
    sendEventData(src, enabled == true and '오픈 이벤트 집계를 시작했습니다' or '오픈 이벤트 집계를 일시정지했습니다', false)
end)

RegisterNetEvent('cookie_admin:server:resetOpenEvents', function()
    local src = source
    if not canManage(src) then return sendEventData(src, '이벤트 관리 권한이 없습니다', true) end
    if not ensureEventTables() then return sendEventData(src, '이벤트 DB 준비에 실패했습니다', true) end

    MySQL.query.await('DELETE FROM cookie_open_event_user_stats')
    MySQL.query.await('DELETE FROM cookie_open_event_job_stats')
    MySQL.query.await('DELETE FROM cookie_open_event_activity_stats')
    MySQL.update.await('UPDATE cookie_open_event_state SET enabled = 1, started_at = CURRENT_TIMESTAMP WHERE id = 1')
    sendEventData(src, '오픈 이벤트 기록을 초기화하고 새 집계를 시작했습니다', false)
end)


AddEventHandler('playerDropped', function()
    eventReqAt[source] = nil
end)


-- V1.6.6 ESC bridge ---------------------------------------------------------
-- cookie_esc가 같은 오픈 이벤트 데이터를 그대로 사용하도록 공개 API를 제공한다.
exports('getOpenEventPayload', function(src)
    src = tonumber(src) or 0
    if src <= 0 then return nil end
    return buildEventPayload(src)
end)
exports('GetOpenEventPayload', function(src)
    src = tonumber(src) or 0
    if src <= 0 then return nil end
    return buildEventPayload(src)
end)

local function escMineralPurityRankingV166(limit)
    limit = math.max(1, math.min(50, math.floor(tonumber(limit) or 10)))
    local rows=MySQL.query.await([[
        SELECT c.citizenid,c.mineral,c.best_purity,p.license,u.gobun,u.nickname
        FROM cookie_mining_collection c
        LEFT JOIN players p ON p.citizenid=c.citizenid
        LEFT JOIN cookie_user u ON u.license COLLATE utf8mb4_general_ci=p.license COLLATE utf8mb4_general_ci
        WHERE c.best_purity>0
    ]]) or {}
    local best={}
    for _,r in ipairs(rows) do
        local meta=MINERAL_META[tostring(r.mineral or '')]
        if meta then
            local rarity=meta[2]
            local cand={
                citizenid=r.citizenid,license=r.license,gobun=tonumber(r.gobun),nickname=r.nickname,
                mineral=tostring(r.mineral),mineralLabel=meta[1],
                rarity=rarity,rarityLabel=MINERAL_RARITY_LABEL[rarity] or rarity,
                rarityRank=MINERAL_RARITY_RANK[rarity] or 0,
                purity=tonumber(r.best_purity) or 0,
            }
            local key=tostring(r.citizenid)
            local old=best[key]
            if not old
               or cand.purity>old.purity
               or (cand.purity==old.purity and cand.rarityRank>old.rarityRank) then
                best[key]=cand
            end
        end
    end
    local all={}; for _,v in pairs(best) do all[#all+1]=v end
    table.sort(all,function(a,b)
        if a.purity~=b.purity then return a.purity>b.purity end
        if a.rarityRank~=b.rarityRank then return a.rarityRank>b.rarityRank end
        return (tonumber(a.gobun) or 999999999)<(tonumber(b.gobun) or 999999999)
    end)
    local out={}
    for i=1,math.min(limit,#all) do all[i].rank=i;out[#out+1]=all[i] end
    return out
end

exports('getEscMineralPurityRanking', function(limit)
    return escMineralPurityRankingV166(limit)
end)
exports('GetEscMineralPurityRanking', function(limit)
    return escMineralPurityRankingV166(limit)
end)

if lib and lib.callback and lib.callback.register then
    lib.callback.register('cookie_admin:escMineralPurityRanking', function(_, limit)
        return escMineralPurityRankingV166(limit)
    end)
end

RegisterNetEvent('cookie_admin:server:requestEscMineralPurityRanking',function(limit)
    TriggerClientEvent('cookie_admin:client:escMineralPurityRanking',source,escMineralPurityRankingV166(limit))
end)

print('[cookie_admin] EVENT + ESC RANK BACKEND V1.6.6 ready')

print('^2[COOKIE EVENT]^7 QUEST HOOK V14.0.0 ready')
