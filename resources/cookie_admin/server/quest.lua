-- COOKIE DAILY / WEEKLY QUEST V2.0.0
-- 퀘스트 정의와 보상을 F3 관리자 > 퀘스트 시스템에서 편집할 수 있습니다.
-- 지원 지표: playtime_min / civil_job_min / fishing_sec / mining_sec

local questReady = false
local questClaimLocks = {}

local DEFAULT_QUESTS = {
    { id='daily_play_30', period='daily', metric='playtime_min', title='도시 적응', description='오늘 쿠키서버에서 30분 동안 활동하세요.', target=30, unit='minute', rewardType='bank', rewardAmount=20000, sort=10 },
    { id='daily_job_30', period='daily', metric='civil_job_min', title='오늘도 일손', description='시민직으로 30분 동안 근무하세요.', target=30, unit='minute', rewardType='bank', rewardAmount=25000, sort=20 },
    { id='daily_fishing_10', period='daily', metric='fishing_sec', title='낚시 한 판', description='오늘 실제 낚시 활동을 10분 진행하세요.', target=600, unit='second', rewardType='bank', rewardAmount=15000, sort=30 },
    { id='daily_mining_10', period='daily', metric='mining_sec', title='광산 한 바퀴', description='오늘 실제 광질 활동을 10분 진행하세요.', target=600, unit='second', rewardType='bank', rewardAmount=15000, sort=40 },
    { id='weekly_play_300', period='weekly', metric='playtime_min', title='도시의 일주일', description='이번 주 쿠키서버에서 5시간 동안 활동하세요.', target=300, unit='minute', rewardType='bank', rewardAmount=100000, sort=10 },
    { id='weekly_job_240', period='weekly', metric='civil_job_min', title='성실 근무', description='이번 주 시민직으로 4시간 동안 근무하세요.', target=240, unit='minute', rewardType='bank', rewardAmount=120000, sort=20 },
    { id='weekly_fishing_60', period='weekly', metric='fishing_sec', title='주간 낚시꾼', description='이번 주 실제 낚시 활동을 1시간 진행하세요.', target=3600, unit='second', rewardType='bank', rewardAmount=60000, sort=30 },
    { id='weekly_mining_60', period='weekly', metric='mining_sec', title='주간 광부', description='이번 주 실제 광질 활동을 1시간 진행하세요.', target=3600, unit='second', rewardType='bank', rewardAmount=60000, sort=40 },
}

local METRICS = {
    playtime_min = { label='접속시간', unit='minute' },
    civil_job_min = { label='시민직 근무시간', unit='minute' },
    fishing_sec = { label='낚시 활동시간', unit='second' },
    mining_sec = { label='광질 활동시간', unit='second' },
}

local function player(src)
    return exports.qbx_core:GetPlayer(src)
end

local function citizenId(src)
    local p = player(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function clean(v, maxLen)
    local s = tostring(v or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > (maxLen or 100) then s = s:sub(1, maxLen or 100) end
    return s
end

local function cleanId(v)
    local s = tostring(v or ''):lower():gsub('[^%w_%-]', '_')
    if #s > 64 then s = s:sub(1,64) end
    return s
end

local function effectiveAdmin(src)
    local license = getLicense(src)
    if not license then return nil end
    local row = MySQL.single.await([[
        SELECT admin_name, admin_level, (pw_hash IS NOT NULL) AS has_pw
        FROM cookie_admin WHERE license=? AND is_active=1 LIMIT 1
    ]], { license })
    if not row then return nil end
    local level = tonumber(row.admin_level) or 0
    local hasPw = row.has_pw == 1 or row.has_pw == true
    if level >= 5 and not hasPw then level = 4 end
    if level < 5 then return nil end
    return row
end

local function kstUnix()
    return os.time() + (9 * 60 * 60)
end

local function dailyCycleKey()
    return os.date('!%Y-%m-%d', kstUnix())
end

local function weeklyCycleKey()
    local now = kstUnix()
    local t = os.date('!*t', now)
    local daysSinceMonday = (tonumber(t.wday or 1) + 5) % 7
    return os.date('!%Y-%m-%d', now - (daysSinceMonday * 86400))
end

local function cycleKey(period)
    if period == 'weekly' then return 'W:' .. weeklyCycleKey() end
    return 'D:' .. dailyCycleKey()
end

local function cycleLabel(period)
    if period == 'weekly' then return ('%s 시작 주간'):format(weeklyCycleKey():gsub('-', '.')) end
    return dailyCycleKey():gsub('-', '.')
end

local function ensureQuestTables()
    if questReady then return true end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_quest_def (
            quest_id VARCHAR(64) NOT NULL PRIMARY KEY,
            period VARCHAR(12) NOT NULL,
            metric_key VARCHAR(40) NOT NULL,
            title VARCHAR(80) NOT NULL,
            description VARCHAR(180) NOT NULL DEFAULT '',
            target_value BIGINT UNSIGNED NOT NULL DEFAULT 1,
            unit VARCHAR(16) NOT NULL DEFAULT 'count',
            reward_type VARCHAR(12) NOT NULL DEFAULT 'bank',
            reward_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            reward_item VARCHAR(80) NULL,
            reward_count INT UNSIGNED NOT NULL DEFAULT 0,
            sort_order INT NOT NULL DEFAULT 0,
            active TINYINT(1) NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_cookie_quest_period(period,active,sort_order),
            INDEX idx_cookie_quest_metric(metric_key,active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_quest_progress (
            citizenid VARCHAR(64) NOT NULL,
            period_key VARCHAR(24) NOT NULL,
            quest_id VARCHAR(64) NOT NULL,
            progress BIGINT UNSIGNED NOT NULL DEFAULT 0,
            claimed_at DATETIME NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid,period_key,quest_id),
            INDEX idx_cookie_quest_progress_cycle(period_key,quest_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_quest_meta (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            initialized TINYINT(1) NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    local seeded = MySQL.single.await('SELECT initialized FROM cookie_quest_meta WHERE id=1 LIMIT 1')
    if not seeded then
        local defCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cookie_quest_def')) or 0
        if defCount <= 0 then
            for _, q in ipairs(DEFAULT_QUESTS) do
                MySQL.insert.await([[
                    INSERT IGNORE INTO cookie_quest_def
                        (quest_id,period,metric_key,title,description,target_value,unit,reward_type,reward_amount,reward_item,reward_count,sort_order,active)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,1)
                ]], { q.id,q.period,q.metric,q.title,q.description,q.target,q.unit,q.rewardType,q.rewardAmount or 0,q.rewardItem,q.rewardCount or 0,q.sort or 0 })
            end
        end
        MySQL.insert.await('INSERT IGNORE INTO cookie_quest_meta(id,initialized) VALUES(1,1)')
    end

    questReady = true
    return true
end

CreateThread(function()
    Wait(1300)
    ensureQuestTables()
    print('^2[cookie_admin]^7 DAILY/WEEKLY QUEST ADMIN V2.0.0 ready')
end)

local function rewardLabel(q)
    local typ = tostring(q.reward_type or '')
    if typ == 'bank' then return ('계좌 %s원'):format(tonumber(q.reward_amount) or 0) end
    if typ == 'cash' then return ('현금 %s원'):format(tonumber(q.reward_amount) or 0) end
    if typ == 'item' then return ('%s x%s'):format(clean(q.reward_item, 80), tonumber(q.reward_count) or 0) end
    return '보상 없음'
end

local function rewardConfigured(q)
    local typ = tostring(q.reward_type or '')
    if typ == 'bank' or typ == 'cash' then return (tonumber(q.reward_amount) or 0) > 0 end
    if typ == 'item' then return clean(q.reward_item,80) ~= '' and (tonumber(q.reward_count) or 0) > 0 end
    return false
end

local function buildPeriod(src, period)
    ensureQuestTables()
    local cid = citizenId(src)
    local pkey = cycleKey(period)
    local defs = MySQL.query.await([[
        SELECT quest_id,period,metric_key,title,description,target_value,unit,
               reward_type,reward_amount,reward_item,reward_count,sort_order
        FROM cookie_quest_def
        WHERE period=? AND active=1
        ORDER BY sort_order ASC, quest_id ASC
    ]], { period }) or {}

    local progressMap = {}
    if cid then
        local rows = MySQL.query.await([[
            SELECT quest_id,progress,claimed_at FROM cookie_quest_progress
            WHERE citizenid=? AND period_key=?
        ]], { cid, pkey }) or {}
        for _, r in ipairs(rows) do progressMap[tostring(r.quest_id)] = r end
    end

    local quests = {}
    for _, q in ipairs(defs) do
        local pr = progressMap[tostring(q.quest_id)] or {}
        local target = math.max(1, math.floor(tonumber(q.target_value) or 1))
        local progress = math.max(0, math.floor(tonumber(pr.progress) or 0))
        local claimed = pr.claimed_at ~= nil
        local complete = progress >= target
        quests[#quests + 1] = {
            id=tostring(q.quest_id), title=clean(q.title,80), description=clean(q.description,180),
            metric=tostring(q.metric_key or ''), unit=tostring(q.unit or 'count'), progress=math.min(progress,target), target=target,
            complete=complete, claimed=claimed, canClaim=complete and not claimed and rewardConfigured(q),
            reward={ type=tostring(q.reward_type or ''), amount=math.max(0,math.floor(tonumber(q.reward_amount) or 0)),
                itemName=clean(q.reward_item,80), itemCount=math.max(0,math.floor(tonumber(q.reward_count) or 0)), label=rewardLabel(q) }
        }
    end

    return {
        period=period, periodKey=pkey, label=cycleLabel(period),
        resetText=period=='weekly' and '매주 월요일 00:00 초기화' or '매일 00:00 초기화', quests=quests
    }
end

local function buildQuestPayload(src)
    return { daily=buildPeriod(src,'daily'), weekly=buildPeriod(src,'weekly') }
end

function CookieQuestAccrue(src, metricKey, amount)
    src = tonumber(src) or 0
    if src <= 0 then return end
    metricKey = tostring(metricKey or '')
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if not METRICS[metricKey] or amount <= 0 then return end
    if not ensureQuestTables() then return end
    local cid = citizenId(src)
    if not cid then return end

    local defs = MySQL.query.await([[
        SELECT quest_id,period,target_value FROM cookie_quest_def WHERE metric_key=? AND active=1
    ]], { metricKey }) or {}
    for _, q in ipairs(defs) do
        local pkey = cycleKey(tostring(q.period or 'daily'))
        local target = math.max(1,math.floor(tonumber(q.target_value) or 1))
        MySQL.query.await([[
            INSERT INTO cookie_quest_progress(citizenid,period_key,quest_id,progress)
            VALUES(?,?,?,?)
            ON DUPLICATE KEY UPDATE progress=LEAST(?, progress + VALUES(progress))
        ]], { cid,pkey,tostring(q.quest_id),amount,target })
    end
end

local function giveQuestReward(src, q)
    local typ = tostring(q.reward_type or '')
    local amount = math.max(0, math.floor(tonumber(q.reward_amount) or 0))
    if (typ == 'bank' or typ == 'cash') and amount > 0 then
        local ok = exports.qbx_core:AddMoney(src, typ, amount, ('COOKIE %s 퀘스트'):format(tostring(q.period or '')))
        return ok ~= false
    end
    if typ == 'item' then
        local name = clean(q.reward_item,80)
        local count = math.max(1,math.floor(tonumber(q.reward_count) or 1))
        if name == '' or GetResourceState('ox_inventory') ~= 'started' then return false end
        local okItem,item = pcall(function() return exports.ox_inventory:Items(name) end)
        if not okItem or not item then return false end
        local ok,success = pcall(function() return exports.ox_inventory:AddItem(src,name,count) end)
        return ok and success ~= false
    end
    return false
end

local function sendQuestData(src, message, isError)
    TriggerClientEvent('cookie_admin:client:questData', src, buildQuestPayload(src), message, isError == true)
end

RegisterNetEvent('cookie_admin:server:requestQuests', function()
    sendQuestData(source)
end)

RegisterNetEvent('cookie_admin:server:claimQuest', function(rawQuestId)
    local src=source
    local cid=citizenId(src)
    local questId=cleanId(rawQuestId)
    if not cid or questId=='' then return end
    local lockKey=cid..':'..questId
    if questClaimLocks[lockKey] then return end
    questClaimLocks[lockKey]=true
    local function done(message,isError)
        questClaimLocks[lockKey]=nil
        sendQuestData(src,message,isError)
    end

    ensureQuestTables()
    local q=MySQL.single.await([[
        SELECT quest_id,period,title,target_value,reward_type,reward_amount,reward_item,reward_count
        FROM cookie_quest_def WHERE quest_id=? AND active=1 LIMIT 1
    ]],{questId})
    if not q then return done('퀘스트 정보를 찾을 수 없습니다.',true) end
    if not rewardConfigured(q) then return done('이 퀘스트의 보상이 아직 설정되지 않았습니다.',true) end

    local pkey=cycleKey(tostring(q.period or 'daily'))
    local target=math.max(1,math.floor(tonumber(q.target_value) or 1))
    local changed=MySQL.update.await([[
        UPDATE cookie_quest_progress SET claimed_at=NOW()
        WHERE citizenid=? AND period_key=? AND quest_id=? AND progress>=? AND claimed_at IS NULL
    ]],{cid,pkey,questId,target})
    if (tonumber(changed) or 0)<1 then return done('아직 완료하지 않았거나 이미 보상을 받은 퀘스트입니다.',true) end

    if not giveQuestReward(src,q) then
        MySQL.update.await([[UPDATE cookie_quest_progress SET claimed_at=NULL WHERE citizenid=? AND period_key=? AND quest_id=?]],{cid,pkey,questId})
        return done('보상 지급에 실패했습니다. 아이템/보상 설정을 확인해주세요.',true)
    end
    done(('%s 퀘스트 보상을 받았습니다.'):format(clean(q.title,80)),false)
end)

-- =========================
-- F3 관리자 퀘스트 편집
-- =========================
local function buildQuestAdminPayload()
    ensureQuestTables()
    local rows=MySQL.query.await([[
        SELECT quest_id,period,metric_key,title,description,target_value,unit,
               reward_type,reward_amount,reward_item,reward_count,sort_order,active
        FROM cookie_quest_def ORDER BY period ASC,sort_order ASC,quest_id ASC
    ]]) or {}
    local quests={}
    for _,q in ipairs(rows) do
        quests[#quests+1]={
            id=tostring(q.quest_id), period=tostring(q.period), metric=tostring(q.metric_key),
            title=clean(q.title,80), description=clean(q.description,180), target=math.max(1,math.floor(tonumber(q.target_value) or 1)),
            unit=tostring(q.unit or 'count'), rewardType=tostring(q.reward_type or 'none'),
            rewardAmount=math.max(0,math.floor(tonumber(q.reward_amount) or 0)), rewardItem=clean(q.reward_item,80),
            rewardCount=math.max(0,math.floor(tonumber(q.reward_count) or 0)), sort=math.floor(tonumber(q.sort_order) or 0),
            active=q.active==1 or q.active==true,
        }
    end
    local metrics={}
    for key,v in pairs(METRICS) do metrics[#metrics+1]={key=key,label=v.label,unit=v.unit} end
    table.sort(metrics,function(a,b) return a.key<b.key end)
    return {quests=quests,metrics=metrics,maxQuests=50}
end

RegisterNetEvent('cookie_admin:server:requestQuestAdmin', function()
    local src=source
    if not effectiveAdmin(src) then return end
    TriggerClientEvent('cookie_admin:client:questAdminData',src,buildQuestAdminPayload())
end)

RegisterNetEvent('cookie_admin:server:saveQuestAdmin', function(data)
    local src=source
    if not effectiveAdmin(src) or type(data)~='table' then return end
    ensureQuestTables()
    local rows=type(data.quests)=='table' and data.quests or {}
    if #rows>50 then
        TriggerClientEvent('cookie_admin:client:questAdminSaved',src,false,'퀘스트는 최대 50개까지 등록할 수 있습니다.')
        return
    end

    local existing=MySQL.query.await('SELECT quest_id FROM cookie_quest_def') or {}
    local keep={}
    local seen={}
    local rewardAllowed={none=true,bank=true,cash=true,item=true}

    for i,r in ipairs(rows) do
        local id=cleanId(r.id)
        if id=='' or id:match('^new_') then id=('custom_%d_%02d'):format(os.time(),i) end
        if seen[id] then
            TriggerClientEvent('cookie_admin:client:questAdminSaved',src,false,('퀘스트 ID가 중복되었습니다: %s'):format(id))
            return
        end
        seen[id]=true; keep[id]=true

        local period=tostring(r.period or 'daily')
        if period~='daily' and period~='weekly' then period='daily' end
        local metric=tostring(r.metric or 'playtime_min')
        local metricDef=METRICS[metric]
        if not metricDef then
            TriggerClientEvent('cookie_admin:client:questAdminSaved',src,false,('지원하지 않는 퀘스트 조건입니다: %s'):format(metric))
            return
        end
        local title=clean(r.title,80); if title=='' then title='새 퀘스트' end
        local description=clean(r.description,180)
        local target=math.max(1,math.min(1000000000,math.floor(tonumber(r.target) or 1)))
        local rewardType=tostring(r.rewardType or 'none'); if not rewardAllowed[rewardType] then rewardType='none' end
        local rewardAmount=math.max(0,math.min(1000000000,math.floor(tonumber(r.rewardAmount) or 0)))
        local rewardItem=clean(r.rewardItem,80):lower()
        local rewardCount=math.max(0,math.min(999,math.floor(tonumber(r.rewardCount) or 0)))
        local active=r.active~=false and 1 or 0
        local sort=math.max(-9999,math.min(9999,math.floor(tonumber(r.sort) or (i*10))))

        if rewardType=='bank' or rewardType=='cash' then
            if rewardAmount<=0 then rewardType='none' end
            rewardItem,rewardCount='',0
        elseif rewardType=='item' then
            rewardAmount=0
            if rewardItem=='' or rewardCount<=0 then
                rewardType,rewardItem,rewardCount='none','',0
            elseif GetResourceState('ox_inventory')=='started' then
                local okItem,item=pcall(function() return exports.ox_inventory:Items(rewardItem) end)
                if not okItem or not item then
                    TriggerClientEvent('cookie_admin:client:questAdminSaved',src,false,('퀘스트 "%s"의 아이템 "%s"을 찾을 수 없습니다.'):format(title,rewardItem))
                    return
                end
            end
        else
            rewardType,rewardAmount,rewardItem,rewardCount='none',0,'',0
        end

        MySQL.query.await([[
            INSERT INTO cookie_quest_def
                (quest_id,period,metric_key,title,description,target_value,unit,reward_type,reward_amount,reward_item,reward_count,sort_order,active)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE period=VALUES(period),metric_key=VALUES(metric_key),title=VALUES(title),description=VALUES(description),
                target_value=VALUES(target_value),unit=VALUES(unit),reward_type=VALUES(reward_type),reward_amount=VALUES(reward_amount),
                reward_item=VALUES(reward_item),reward_count=VALUES(reward_count),sort_order=VALUES(sort_order),active=VALUES(active),updated_at=CURRENT_TIMESTAMP
        ]],{id,period,metric,title,description,target,metricDef.unit,rewardType,rewardAmount,rewardItem,rewardCount,sort,active})
    end

    for _,row in ipairs(existing) do
        local id=tostring(row.quest_id or '')
        if id~='' and not keep[id] then MySQL.update.await('DELETE FROM cookie_quest_def WHERE quest_id=?',{id}) end
    end

    TriggerClientEvent('cookie_admin:client:questAdminSaved',src,true,'퀘스트 내용과 보상 설정을 저장했습니다.')
    TriggerClientEvent('cookie_admin:client:questAdminData',src,buildQuestAdminPayload())
end)

exports('AccrueQuest', function(src,metricKey,amount)
    CookieQuestAccrue(src,metricKey,amount)
end)
