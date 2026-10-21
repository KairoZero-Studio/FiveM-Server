
local RANK_CATEGORIES = {
    playtime = { label='플레이시간', icon='⏱️', description='ESC 플레이시간 순위만 현재 시점부터 다시 집계합니다.' },
    jobs = { label='직업 근무시간', icon='💼', description='각 직업별 ESC 근무시간 순위를 현재 누적값부터 다시 시작합니다.' },
    crime = { label='범죄 · 전과', icon='⚖️', description='전과와 범죄점수 원본은 유지하고 ESC 증가분만 다시 집계합니다.' },
    fishing = { label='낚시 최고 무게', icon='🎣', description='도감·개인 최고기록은 유지하고 ESC 낚시 순위 시즌만 초기화합니다.' },
    mining = { label='광물 최고 순도', icon='💎', description='개인 최고순도 기록은 유지하고 ESC 광물 순위 시즌만 초기화합니다.' },
}
local RANK_ORDER = {'playtime','jobs','crime','fishing','mining'}
local rankingAdminReady=false
local rankingAdminInitError=nil

local function rankAdminNotify(src,msg,isErr)
    TriggerClientEvent('cookie_admin:client:notify',src,msg,isErr==true)
end

local function rankAdminAuth(src)
    local admin=CookieAdminTeamAuth and CookieAdminTeamAuth(src,'general') or nil
    if not admin or (tonumber(admin.admin_level) or 0)<5 then return nil end
    return admin
end

local function adminName(admin)
    return tostring((admin and (admin.admin_name or admin.alias or admin.name)) or '관리자')
end

local function ensureRankingAdminTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_playtime_baseline (
            license VARCHAR(255) NOT NULL PRIMARY KEY,
            base_minute INT NOT NULL DEFAULT 0,
            reset_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_crime_baseline (
            citizenid VARCHAR(64) NOT NULL PRIMARY KEY,
            base_offense INT NOT NULL DEFAULT 0,
            base_score INT NOT NULL DEFAULT 0,
            reset_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
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
            gobun VARCHAR(20) NULL,
            nickname VARCHAR(80) NULL,
            species VARCHAR(40) NULL,
            label VARCHAR(80) NULL,
            kg DOUBLE NOT NULL DEFAULT 0,
            caught_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_rank_fishing_kg(kg)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_mining_current (
            citizenid VARCHAR(64) NOT NULL,
            mineral VARCHAR(40) NOT NULL,
            best_purity INT NOT NULL DEFAULT 0,
            mined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid,mineral),
            INDEX idx_rank_mining_purity(best_purity)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_ranking_reset_state (
            category_key VARCHAR(32) NOT NULL PRIMARY KEY,
            reset_at TIMESTAMP NULL,
            reset_by VARCHAR(80) NULL,
            reset_count INT UNSIGNED NOT NULL DEFAULT 0
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    for _,key in ipairs(RANK_ORDER) do
        MySQL.query.await('INSERT IGNORE INTO cookie_ranking_reset_state(category_key) VALUES (?)',{key})
    end
end

local function markReset(key,by)
    MySQL.query.await([[
        INSERT INTO cookie_ranking_reset_state(category_key,reset_at,reset_by,reset_count)
        VALUES (?,NOW(),?,1)
        ON DUPLICATE KEY UPDATE reset_at=NOW(),reset_by=VALUES(reset_by),reset_count=reset_count+1
    ]],{key,by})
end

local function resetPlaytime(by)
    MySQL.query.await([[
        INSERT INTO cookie_ranking_playtime_baseline(license,base_minute,reset_at)
        SELECT license,COALESCE(rp_minute,0),NOW() FROM cookie_user
        ON DUPLICATE KEY UPDATE base_minute=VALUES(base_minute),reset_at=NOW()
    ]])
    markReset('playtime',by)
end

local function resetJobs(by)
    MySQL.query.await([[
        INSERT INTO cookie_ranking_job_baseline(license,job_key,base_minute,reset_at)
        SELECT license,job_key,COALESCE(minute,0),NOW() FROM cookie_job_lifetime_stats
        ON DUPLICATE KEY UPDATE base_minute=VALUES(base_minute),reset_at=NOW()
    ]])
    markReset('jobs',by)
end

local function resetCrime(by)
    MySQL.query.await([[
        INSERT INTO cookie_ranking_crime_baseline(citizenid,base_offense,base_score,reset_at)
        SELECT citizenid,COALESCE(offense_count,0),COALESCE(crime_score,0),NOW() FROM cookie_crime_user_stats
        ON DUPLICATE KEY UPDATE base_offense=VALUES(base_offense),base_score=VALUES(base_score),reset_at=NOW()
    ]])
    markReset('crime',by)
end

local function resetFishing(by)
    MySQL.query.await('DELETE FROM cookie_ranking_fishing_current')
    markReset('fishing',by)
end

local function resetMining(by)
    MySQL.query.await('DELETE FROM cookie_ranking_mining_current')
    markReset('mining',by)
end

local RESETTERS={playtime=resetPlaytime,jobs=resetJobs,crime=resetCrime,fishing=resetFishing,mining=resetMining}

local function rankingAdminPayload()
    local rows=MySQL.query.await([[
        SELECT category_key,DATE_FORMAT(reset_at,'%Y.%m.%d %H:%i:%s') AS reset_at,reset_by,reset_count
        FROM cookie_ranking_reset_state
    ]]) or {}
    local state={}
    for _,r in ipairs(rows) do state[tostring(r.category_key)]=r end
    local out={}
    for _,key in ipairs(RANK_ORDER) do
        local meta=RANK_CATEGORIES[key]
        local st=state[key] or {}
        out[#out+1]={
            key=key,label=meta.label,icon=meta.icon,description=meta.description,
            resetAt=st.reset_at,resetBy=st.reset_by,resetCount=tonumber(st.reset_count) or 0,
        }
    end
    return {categories=out}
end


local function seedSeasonRanksOnce()
    -- 기존 서버 기록이 갑자기 사라지지 않도록 최초 설치 시에만 현재 영구 기록을 시즌 기록으로 복사한다.
    local fstate=MySQL.single.await("SELECT reset_count FROM cookie_ranking_reset_state WHERE category_key='fishing' LIMIT 1")
    local fcount=MySQL.scalar.await('SELECT COUNT(*) FROM cookie_ranking_fishing_current') or 0
    if (tonumber(fstate and fstate.reset_count) or 0)==0 and tonumber(fcount)==0 then
        local rows=MySQL.query.await([[
            SELECT c.citizenid,c.species,c.best_kg,p.license,u.gobun,u.nickname
            FROM cookie_fishing_collection c
            LEFT JOIN players p ON p.citizenid=c.citizenid
            LEFT JOIN cookie_user u ON SUBSTRING_INDEX(u.license,':',-1)=SUBSTRING_INDEX(p.license,':',-1)
            WHERE c.best_kg>0
        ]]) or {}
        local best={}
        for _,r in ipairs(rows) do
            local cid=tostring(r.citizenid or '')
            local kg=tonumber(r.best_kg) or 0
            if cid~='' and (not best[cid] or kg>(tonumber(best[cid].best_kg) or 0)) then best[cid]=r end
        end
        for _,r in pairs(best) do
            MySQL.query.await([[
                INSERT IGNORE INTO cookie_ranking_fishing_current(citizenid,gobun,nickname,species,label,kg,caught_at)
                VALUES (?,?,?,?,?,?,NOW())
            ]],{r.citizenid,r.gobun,r.nickname,r.species,r.species,r.best_kg})
        end
    end

    local mstate=MySQL.single.await("SELECT reset_count FROM cookie_ranking_reset_state WHERE category_key='mining' LIMIT 1")
    local mcount=MySQL.scalar.await('SELECT COUNT(*) FROM cookie_ranking_mining_current') or 0
    if (tonumber(mstate and mstate.reset_count) or 0)==0 and tonumber(mcount)==0 then
        MySQL.query.await([[
            INSERT IGNORE INTO cookie_ranking_mining_current(citizenid,mineral,best_purity,mined_at)
            SELECT citizenid,mineral,best_purity,NOW() FROM cookie_mining_collection WHERE best_purity>0
        ]])
    end
end

CreateThread(function()
    Wait(1200)
    local ok,err=pcall(function()
        ensureRankingAdminTables()
        seedSeasonRanksOnce()
    end)
    rankingAdminReady=ok==true
    rankingAdminInitError=ok and nil or tostring(err)
    if ok then print('^2[cookie_admin]^7 RANKING RESET ADMIN V1.7.5 ready')
    else print(('^1[cookie_admin]^7 ranking reset init failed: %s'):format(tostring(err))) end
end)

RegisterNetEvent('cookie_admin:server:requestRankingAdmin',function()
    local src=source
    if not rankAdminAuth(src) then
        rankAdminNotify(src,'순위표 관리 권한이 없습니다.',true)
        return TriggerClientEvent('cookie_admin:client:rankingAdminError',src,'순위표 관리 권한(LV5 이상)이 없습니다.')
    end
    if not rankingAdminReady then
        local msg=rankingAdminInitError and ('초기화 준비 오류: '..rankingAdminInitError) or '순위표 관리 DB를 준비 중입니다. 잠시 후 다시 시도하세요.'
        return TriggerClientEvent('cookie_admin:client:rankingAdminError',src,msg)
    end
    local ok,data=pcall(rankingAdminPayload)
    if not ok then
        print(('^1[cookie_admin][ranking]^7 request failed: %s'):format(tostring(data)))
        return TriggerClientEvent('cookie_admin:client:rankingAdminError',src,'순위표 관리 데이터를 불러오지 못했습니다.')
    end
    TriggerClientEvent('cookie_admin:client:rankingAdminData',src,data)
end)

RegisterNetEvent('cookie_admin:server:resetRankings',function(data)
    local src=source
    local admin=rankAdminAuth(src)
    if not admin then rankAdminNotify(src,'순위표 관리 권한이 없습니다.',true); return TriggerClientEvent('cookie_admin:client:rankingAdminError',src,'순위표 관리 권한(LV5 이상)이 없습니다.') end
    data=type(data)=='table' and data or {}
    local requested=type(data.categories)=='table' and data.categories or {}
    local selected={}
    for _,v in ipairs(requested) do
        local key=tostring(v or '')
        if RESETTERS[key] then selected[key]=true end
    end
    local count=0
    for _ in pairs(selected) do count=count+1 end
    if count<=0 then return rankAdminNotify(src,'초기화할 순위 항목을 선택하세요.',true) end

    if not rankingAdminReady then return TriggerClientEvent('cookie_admin:client:rankingAdminError',src,'순위표 관리 DB가 아직 준비되지 않았습니다.') end
    local by=adminName(admin)
    for _,key in ipairs(RANK_ORDER) do
        if selected[key] then
            local ok,err=pcall(RESETTERS[key],by)
            if not ok then
                print(('^1[cookie_admin][ranking]^7 reset %s failed: %s'):format(key,tostring(err)))
                local msg=('%s 초기화 중 오류가 발생했습니다.'):format(RANK_CATEGORIES[key].label)
                rankAdminNotify(src,msg,true)
                return TriggerClientEvent('cookie_admin:client:rankingAdminError',src,msg)
            end
        end
    end

    rankAdminNotify(src,('%d개 순위 항목을 초기화했습니다. 원본 기록은 유지됩니다.'):format(count),false)
    TriggerClientEvent('cookie_admin:client:rankingAdminData',src,rankingAdminPayload())
end)
