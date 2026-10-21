local activeChases = {}
local chaseViewByCitizenid = {}
local pmStopCounts = {}
local chaseCreateLocks = {}

local CHASE_END_PRESETS = {
    ['RP중 디컨'] = true,
    ['도주자 측 패배'] = true,
    ['경찰/보안국 측 전멸'] = true,
    ['상황 종료'] = true,
    ['오등록'] = true,
}

local function cookiePoliceLog(category, title, description, fields, options)
    if GetResourceState('cookie_logs') ~= 'started' then return end
    pcall(function()
        exports.cookie_logs:Log(category, title, description, fields or {}, options or {})
    end)
end



local function notify(src, message, isError)
    TriggerClientEvent('cookie_admin:client:notify', src, message, isError == true)
end


local function factionMember(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok, member = pcall(function() return exports.cookie_admin:getFactionMember(src) end)
    return ok and member or nil
end

local function hasAccess(src)
    local m = factionMember(src)
    if not m then return false, nil end
    local t = tostring(m.type or ''):lower()
    if not Config.AllowedFactionTypes[t] then return false, m end
    if Config.RequireDuty and m.duty ~= true then return false, m end
    return true, m
end

local function guard(src, officerOnly)
    local ok, m = hasAccess(src)
    if not ok then
        return nil, { ok=false, message='경찰청/보안국 출근 상태에서만 사용할 수 있습니다.' }
    end
    if officerOnly and not (m.isOfficer or m.isLeader) then
        return nil, { ok=false, message='간부 이상만 사용할 수 있습니다.' }
    end
    return m
end

local function playerData(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p, p and p.PlayerData or nil
end

local function cleanText(v, maxLen)
    local s = tostring(v or ''):gsub('[%z\1-\31]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function fineFactionLabel(member)
    local name = cleanText(member and member.name or '', 80)
    if name ~= '' then return name end
    local factionType = tostring(member and member.type or ''):lower()
    if factionType == 'security' then return '보안국' end
    return '경찰청'
end

local function sendFineReceipt(target, member, actor, receiptNo, reason, amount, paid, paymentMethod)
    if not target or not GetPlayerName(target) then return end
    TriggerClientEvent('cookie_police:client:fineReceipt', target, {
        receiptNo = tostring(receiptNo or '-'),
        faction = fineFactionLabel(member),
        officer = cleanText(actor and actor.name or '-', 80),
        reason = cleanText(reason, 300),
        amount = math.max(0, math.floor(tonumber(amount) or 0)),
        paid = paid == true,
        paymentMethod = tostring(paymentMethod or (paid == true and '납부 완료' or '미납')),
        issuedAt = os.date('%Y-%m-%d %H:%M:%S')
    })
end

local function cleanPlate(v)
    return cleanText(v, 16):upper():gsub('%s+', '')
end

local function clampInt(v, mn, mx, default)
    local n = math.floor(tonumber(v) or tonumber(default) or 0)
    if mn and n < mn then n = mn end
    if mx and n > mx then n = mx end
    return n
end

local function decodeJson(v)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return {} end
    local ok, t = pcall(json.decode, v)
    return ok and type(t) == 'table' and t or {}
end

local function displayCitizen(row)
    if not row then return '-' end
    if row.nickname and row.nickname ~= '' then return row.nickname end
    local ci = decodeJson(row.charinfo)
    local n = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or '-'
end

local function citizenLabel(row)
    if not row then return '- / -' end
    return ('%s / %s'):format(tostring(row.gobun or '-'), displayCitizen(row))
end

local function sourceByCitizenid(cid)
    cid = tostring(cid or '')
    if cid == '' then return nil end
    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        local _, pd = playerData(src)
        if pd and tostring(pd.citizenid or '') == cid then return src end
    end
    return nil
end

local function officerInfo(src, member)
    local _, pd = playerData(src)
    local ci = pd and pd.charinfo or {}
    local nick, gobun = nil, nil
    pcall(function() nick = exports.cookie_core:getNickname(src) end)
    pcall(function() gobun = exports.cookie_core:getGobun(src) end)

    local name = nick
    if not name or name == '' then
        name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    end
    if name == '' then name = GetPlayerName(src) or ('#' .. tostring(src)) end

    return {
        citizenid = pd and pd.citizenid or '',
        name = name,
        gobun = gobun,
        label = ('%s / %s'):format(tostring(gobun or '-'), name),
        factionId = tonumber(member and member.id) or 0,
    }
end

-- 사용자 입력은 오직 '고번 / 이름'만 허용한다.
local function queryCitizenMatches(q)
    q = cleanText(q, 80)
    if q == '' then return {} end
    local like = '%' .. q .. '%'
    local limit = clampInt(Config.MDT and Config.MDT.maxSearchResults, 1, 100, 30)

    return MySQL.query.await([[
        SELECT p.citizenid, p.charinfo, p.metadata, p.license,
               cu.gobun, cu.nickname, cu.jumin, cu.age, cu.phone, cu.gender
        FROM players p
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE CAST(cu.gobun AS CHAR) = ?
           OR cu.nickname LIKE ?
        ORDER BY
          (CAST(cu.gobun AS CHAR) = ?) DESC,
          (cu.nickname = ?) DESC,
          cu.gobun ASC
        LIMIT ?
    ]], { q, like, q, q, limit }) or {}
end

local function resolveCitizen(input)
    local q = cleanText(input, 80)
    if q == '' then return nil, '고번 또는 이름을 입력하세요.' end

    local rows = queryCitizenMatches(q)
    if #rows < 1 then
        return nil, '일치하는 시민을 찾지 못했습니다. 고번 또는 이름을 확인하세요.'
    end

    if #rows > 1 then
        for _, r in ipairs(rows) do
            if tostring(r.gobun or '') == q then
                return r, nil, sourceByCitizenid(r.citizenid)
            end
        end

        local exactName = {}
        for _, r in ipairs(rows) do
            if tostring(r.nickname or '') == q then exactName[#exactName+1] = r end
        end
        if #exactName == 1 then
            local r = exactName[1]
            return r, nil, sourceByCitizenid(r.citizenid)
        end

        return nil, '같은 이름/유사 이름이 여러 명입니다. 고번으로 입력하세요.', nil, rows
    end

    return rows[1], nil, sourceByCitizenid(rows[1].citizenid)
end

local function citizenRowByCitizenid(cid)
    cid = cleanText(cid, 50)
    if cid == '' then return nil end
    return MySQL.single.await([[
        SELECT p.citizenid, p.charinfo, p.metadata, p.license,
               cu.gobun, cu.nickname, cu.jumin, cu.age, cu.phone, cu.gender
        FROM players p
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE p.citizenid=?
        LIMIT 1
    ]], { cid })
end

local function activeChaseForCitizen(cid)
    cid = cleanText(cid, 50)
    if cid == '' then return nil end
    return MySQL.single.await([[
        SELECT id,kind,officer_citizenid,officer_name
        FROM cookie_police_wanted
        WHERE citizenid=? AND active=1 AND expires_at>NOW()
        ORDER BY id DESC LIMIT 1
    ]], { cid })
end

local function targetNearby(src, target, distance)
    if not target or not GetPlayerName(target) then return false end
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if a == 0 or b == 0 then return false end
    return #(GetEntityCoords(a) - GetEntityCoords(b)) <= (distance or 4.0)
end

local function isCuffed(target)
    local bag = Player(target) and Player(target).state
    if bag and bag.cookieCuffed == true then return true end
    local ok, result = pcall(function() return exports.cookie_police:IsCuffed(target) end)
    return ok and result == true
end

local function audit(member, actor, action, targetCid, detail)
    MySQL.insert.await([[
        INSERT INTO cookie_police_audit
          (faction_id, actor_citizenid, actor_name, action, target_citizenid, detail)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        member.id, actor.citizenid, actor.name, action,
        targetCid, cleanText(detail, 500)
    })
end

local function licensesFromMetadata(metadata)
    local md = decodeJson(metadata)
    local licences = md.licences or md.licenses or md.license or {}
    local out = {}
    local labels = {
        driver='운전면허',
        weapon='총기면허',
        business='사업면허',
        boat='선박면허',
        pilot='항공면허'
    }

    if type(licences) == 'table' then
        for k, v in pairs(licences) do
            if v == true or v == 1 or v == 'true' then
                out[#out+1] = labels[k] or tostring(k)
            end
        end
    end

    table.sort(out)
    return out
end


local function otherLicensesFromMetadata(metadata)
    local all=licensesFromMetadata(metadata)
    local out={}
    for _,label in ipairs(all) do
        if tostring(label)~='운전면허' then out[#out+1]=label end
    end
    return out
end

local function cookieDriverLicense(cid)
    if GetResourceState('cookie_license')~='started' then return nil end
    local ok,row=pcall(function()
        return exports.cookie_license:GetByCitizenId(cid)
    end)
    return ok and row or nil
end

local function identityProfile(cid)
    local rows = MySQL.query.await([[
        SELECT p.citizenid, p.charinfo, p.metadata, p.license,
               cu.gobun, cu.nickname, cu.jumin, cu.age, cu.phone, cu.gender
        FROM players p
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE p.citizenid = ? LIMIT 1
    ]], { cid }) or {}

    local r = rows[1]
    if not r then return nil end

    local wanted = MySQL.query.await([[
        SELECT id, kind, reason, created_at, expires_at
        FROM cookie_police_wanted
        WHERE citizenid=? AND active=1 AND expires_at > NOW()
        ORDER BY id DESC LIMIT 8
    ]], { cid }) or {}

    local fines = MySQL.query.await([[
        SELECT amount, reason, paid, created_at
        FROM cookie_police_fine
        WHERE target_citizenid=?
        ORDER BY id DESC LIMIT 6
    ]], { cid }) or {}

    local detentions = MySQL.query.await([[
        SELECT charge, fine_amount, jail_seconds, created_at
        FROM cookie_faction_detention
        WHERE target_citizenid=?
        ORDER BY id DESC LIMIT 6
    ]], { cid }) or {}

    local activeDet = MySQL.single.await([[
        SELECT id, charge, UNIX_TIMESTAMP(release_at) AS release_ts
        FROM cookie_police_detention_active
        WHERE citizenid=? AND active=1 AND release_at > NOW()
        ORDER BY id DESC LIMIT 1
    ]], { cid })

    local wantedOut = {}
    for _, x in ipairs(wanted) do
        wantedOut[#wantedOut+1] = {
            left = ((x.kind == 'escape') and '도주 추격전' or '수배 추격전') .. ' · ' .. tostring(x.reason or ''),
            right = tostring(x.expires_at or '')
        }
    end

    local fineOut, detOut = {}, {}
    for _, x in ipairs(fines) do
        fineOut[#fineOut+1] = {
            left=tostring(x.reason or '-'),
            right=('%s원 · %s'):format(
                tostring(x.amount or 0),
                (x.paid==1 or x.paid==true) and '납부' or '미납'
            )
        }
    end
    for _, x in ipairs(detentions) do
        detOut[#detOut+1] = {
            left=tostring(x.charge or '-'),
            right=('%s분'):format(math.floor((tonumber(x.jail_seconds) or 0)/60))
        }
    end

    return {
        citizenid = r.citizenid, -- NUI 내부 상세 버튼 식별용. 화면에는 표시하지 않음.
        gobun = r.gobun,
        name = displayCitizen(r),
        label = citizenLabel(r),
        phone = r.phone,
        jumin = r.jumin,
        age = r.age,
        gender = r.gender,
        licences = otherLicensesFromMetadata(r.metadata),
        driverLicense = cookieDriverLicense(r.citizenid),
        wantedCount = #wanted,
        detained = activeDet ~= nil,
        wanted = wantedOut,
        fines = fineOut,
        detentions = detOut,
    }
end

local function success(title, message)
    return { ok=true, kind='success', title=title, message=message }
end

local function tableResult(title, columns, rows, rowActions)
    return {
        ok=true,
        kind='table',
        title=title,
        columns=columns,
        rows=rows or {},
        rowActions=rowActions or {}
    }
end

-- -------------------------------------------------------------------
-- DB / migration
-- evidence 및 vehicle_bolo는 V2.1부터 더 이상 사용하지 않는다.
-- 과거 DB 테이블은 데이터 보호를 위해 DROP하지 않는다.
-- -------------------------------------------------------------------
local function createTables()
    local statements = {
[[CREATE TABLE IF NOT EXISTS cookie_police_wanted (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 kind VARCHAR(16) NOT NULL DEFAULT 'wanted',
 reason VARCHAR(500) NOT NULL,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 expires_at DATETIME NOT NULL,
 cleared_at DATETIME NULL,
 cleared_by VARCHAR(80) NULL,
 clear_reason VARCHAR(160) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_active (faction_id,active),
 INDEX idx_cid (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_wanted_unit (
 wanted_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 officer_name VARCHAR(80) NULL,
 joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(wanted_id,citizenid),
 INDEX idx_wanted(wanted_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_warrant (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NULL,
 target_name VARCHAR(80) NULL,
 target_faction_id INT NULL,
 target_faction_key VARCHAR(40) NULL,
 target_faction_name VARCHAR(80) NULL,
 target_faction_type VARCHAR(20) NULL,
 warrant_type VARCHAR(16) NOT NULL DEFAULT 'search',
 reason VARCHAR(500) NOT NULL,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 expires_at DATETIME NULL,
 closed_at DATETIME NULL,
 closed_by VARCHAR(80) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_active (faction_id,active),
 INDEX idx_target_faction (target_faction_id,active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_case (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 case_no VARCHAR(30) NOT NULL UNIQUE,
 title VARCHAR(120) NOT NULL,
 suspect_citizenid VARCHAR(50) NULL,
 suspect_name VARCHAR(80) NULL,
 summary TEXT NOT NULL,
 result TEXT NULL,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 status VARCHAR(16) NOT NULL DEFAULT 'open',
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 INDEX idx_faction (faction_id,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_fine (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 target_citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 amount INT NOT NULL DEFAULT 0,
 reason VARCHAR(300) NOT NULL,
 paid TINYINT(1) NOT NULL DEFAULT 0,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_target (target_citizenid),
 INDEX idx_faction (faction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_dispatch (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NULL,
 title VARCHAR(100) NOT NULL,
 detail VARCHAR(500) NULL,
 priority INT NOT NULL DEFAULT 1,
 x DOUBLE NULL,
 y DOUBLE NULL,
 z DOUBLE NULL,
 created_by VARCHAR(80) NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 closed_by VARCHAR(80) NULL,
 closed_at DATETIME NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_active (faction_id,active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_dispatch_unit (
 dispatch_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 officer_name VARCHAR(80) NULL,
 joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(dispatch_id,citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_detention_active (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 charge VARCHAR(200) NOT NULL,
 release_at DATETIME NOT NULL,
 active TINYINT(1) NOT NULL DEFAULT 1,
 officer_citizenid VARCHAR(50) NULL,
 officer_name VARCHAR(80) NULL,
 released_by VARCHAR(80) NULL,
 released_at DATETIME NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_cid(citizenid,active),
 INDEX idx_release(active,release_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_appearance_request (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 faction_name VARCHAR(100) NULL,
 target_citizenid VARCHAR(50) NOT NULL,
 target_name VARCHAR(80) NULL,
 reason VARCHAR(500) NOT NULL,
 officer_citizenid VARCHAR(50) NOT NULL,
 officer_name VARCHAR(80) NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'pending',
 requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 responded_at DATETIME NULL,
 deadline_at DATETIME NULL,
 completed_at DATETIME NULL,
 INDEX idx_appearance_target(target_citizenid,status),
 INDEX idx_appearance_officer(officer_citizenid,status),
 INDEX idx_appearance_status(status,deadline_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

[[CREATE TABLE IF NOT EXISTS cookie_police_audit (
 id INT AUTO_INCREMENT PRIMARY KEY,
 faction_id INT NOT NULL,
 actor_citizenid VARCHAR(50) NULL,
 actor_name VARCHAR(80) NULL,
 action VARCHAR(40) NOT NULL,
 target_citizenid VARCHAR(50) NULL,
 detail VARCHAR(500) NULL,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 INDEX idx_faction(faction_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    }

    for _, sql in ipairs(statements) do
        local ok, err = pcall(function() MySQL.query.await(sql) end)
        if not ok then
            print(('^1[cookie_police MDT]^7 migration failed: %s'):format(tostring(err)))
        end
    end

    -- 기존 테이블이 이미 존재하면 CREATE TABLE IF NOT EXISTS만으로는 새 컬럼이 생기지 않는다.
    -- V3 수배/도주/출석요구가 사용하는 컬럼을 전부 보강한다.
    local alters = {
        "ALTER TABLE cookie_police_warrant MODIFY COLUMN citizenid VARCHAR(50) NULL",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_id INT NULL AFTER target_name",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_key VARCHAR(40) NULL AFTER target_faction_id",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_name VARCHAR(80) NULL AFTER target_faction_key",
        "ALTER TABLE cookie_police_warrant ADD COLUMN IF NOT EXISTS target_faction_type VARCHAR(20) NULL AFTER target_faction_name",

        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS target_name VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS kind VARCHAR(16) NOT NULL DEFAULT 'wanted'",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS reason VARCHAR(500) NOT NULL DEFAULT '기존 추격'",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS officer_citizenid VARCHAR(50) NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS officer_name VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS active TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS expires_at DATETIME NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS cleared_at DATETIME NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS cleared_by VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS clear_reason VARCHAR(160) NULL",
        "ALTER TABLE cookie_police_wanted ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP",

        "ALTER TABLE cookie_police_wanted_unit ADD COLUMN IF NOT EXISTS officer_name VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_wanted_unit ADD COLUMN IF NOT EXISTS joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP",

        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS faction_id INT NOT NULL DEFAULT 0",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS faction_name VARCHAR(100) NULL",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS target_name VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS reason VARCHAR(500) NOT NULL DEFAULT '출석 요구'",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS officer_citizenid VARCHAR(50) NOT NULL DEFAULT ''",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS officer_name VARCHAR(80) NULL",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'pending'",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS responded_at DATETIME NULL",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS deadline_at DATETIME NULL",
        "ALTER TABLE cookie_police_appearance_request ADD COLUMN IF NOT EXISTS completed_at DATETIME NULL",
    }
    for _, sql in ipairs(alters) do
        local okAlter, alterErr = pcall(function() MySQL.query.await(sql) end)
        if not okAlter then
            print(('^1[cookie_police MDT]^7 alter failed: %s | %s'):format(tostring(sql), tostring(alterErr)))
        end
    end

    pcall(function()
        MySQL.update.await("UPDATE cookie_police_wanted SET kind='wanted' WHERE kind IS NULL OR kind NOT IN ('wanted','escape')")
        MySQL.update.await("UPDATE cookie_police_wanted SET expires_at=DATE_ADD(NOW(), INTERVAL 30 MINUTE) WHERE active=1 AND expires_at IS NULL")
    end)
end

-- -------------------------------------------------------------------
-- Chase cache / HUD
-- -------------------------------------------------------------------
local function hideChase(chase)
    if not chase then return end

    local targetSrc = sourceByCitizenid(chase.citizenid)
    if targetSrc then
        TriggerClientEvent('cookie_police:client:chaseHud', targetSrc, {
            visible=false,
            chaseId=chase.id
        })
    end

    for cid in pairs(chase.participants or {}) do
        local src = sourceByCitizenid(cid)
        if src then
            TriggerClientEvent('cookie_police:client:chaseHud', src, {
                visible=false,
                chaseId=chase.id
            })
        end
    end
end

local function refreshChase(id, keepSelections)
    id = tonumber(id)
    if not id then return nil end

    local row = MySQL.single.await([[
        SELECT w.id,w.faction_id,w.citizenid,w.target_name,w.kind,w.reason,
               w.officer_citizenid,w.officer_name,UNIX_TIMESTAMP(w.expires_at) AS expires_ts,
               cu.gobun,cu.nickname
        FROM cookie_police_wanted w
        LEFT JOIN players p ON p.citizenid=w.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE w.id=? AND w.active=1 AND w.expires_at > NOW()
        LIMIT 1
    ]], { id })

    if not row then
        activeChases[id] = nil
        return nil
    end

    local units = MySQL.query.await([[
        SELECT citizenid,officer_name
        FROM cookie_police_wanted_unit
        WHERE wanted_id=?
        ORDER BY joined_at ASC
    ]], { id }) or {}

    local participants = {}
    for _, u in ipairs(units) do
        participants[tostring(u.citizenid)] = tostring(u.officer_name or '-')
        if not keepSelections and not chaseViewByCitizenid[tostring(u.citizenid)] then
            chaseViewByCitizenid[tostring(u.citizenid)] = id
        end
    end

    local chase = {
        id=id,
        factionId=tonumber(row.faction_id) or 0,
        citizenid=tostring(row.citizenid or ''),
        gobun=row.gobun,
        targetName=row.nickname or row.target_name or '-',
        targetLabel=('%s / %s'):format(tostring(row.gobun or '-'), tostring(row.nickname or row.target_name or '-')),
        kind=(row.kind == 'escape') and 'escape' or 'wanted',
        reason=tostring(row.reason or ''),
        officerCitizenid=tostring(row.officer_citizenid or ''),
        officerName=tostring(row.officer_name or '-'),
        expiresAt=tonumber(row.expires_ts) or 0,
        participants=participants
    }

    activeChases[id] = chase
    return chase
end

local function loadActiveChases()
    activeChases = {}
    chaseViewByCitizenid = {}

    local rows = MySQL.query.await([[
        SELECT id FROM cookie_police_wanted
        WHERE active=1 AND expires_at > NOW()
        ORDER BY id DESC
    ]]) or {}

    for _, row in ipairs(rows) do
        refreshChase(row.id, false)
    end
end

local function pushChase(src, chase, role)
    if not src or not chase then return end
    local remain = math.max(0, (tonumber(chase.expiresAt) or 0) - os.time())

    TriggerClientEvent('cookie_police:client:chaseHud', src, {
        visible=true,
        chaseId=chase.id,
        kind=chase.kind,
        role=role,
        target=chase.targetLabel,
        reason=chase.reason,
        seconds=remain
    })
end


local function chaseMinutes(kind)
    if kind == 'escape' then return tonumber(Config.Chase and Config.Chase.escapeMinutes) or 20 end
    return tonumber(Config.Chase and Config.Chase.wantedMinutes) or 30
end

local function notifyChaseParticipants(chase, message, isError)
    if not chase then return end
    local sent = {}
    local targetSrc = sourceByCitizenid(chase.citizenid)
    if targetSrc then
        sent[targetSrc] = true
        notify(targetSrc, message, isError == true)
    end
    for cid in pairs(chase.participants or {}) do
        local src = sourceByCitizenid(cid)
        if src and not sent[src] then
            sent[src] = true
            notify(src, message, isError == true)
        end
    end
end

AddEventHandler('cookie_police:internal:safeChaseJoin',function(id,cid,src)
    id=tonumber(id)
    if not id then return end
    if cid and cid~='' then chaseViewByCitizenid[tostring(cid)]=id end
    local chase=refreshChase(id,true)
    if chase and src and GetPlayerName(tonumber(src)) then pushChase(tonumber(src),chase,'officer') end
end)

AddEventHandler('cookie_police:internal:safeChaseClear',function(id,reason)
    id=tonumber(id)
    if not id then return end
    local chase=activeChases[id] or refreshChase(id,true)
    if chase then
        hideChase(chase)
        notifyChaseParticipants(chase,(chase.kind=='escape' and '도주' or '수배')..' 상황이 종료되었습니다. 사유: '..tostring(reason or '상황 종료'),false)
    end
    activeChases[id]=nil
end)

local function createChase(member, actor, row, target, kind, reason, sourceTag)
    if not member or not actor or not row or not row.citizenid then
        return false, '추격전 등록 정보가 올바르지 않습니다.'
    end

    local cid = tostring(row.citizenid)
    if chaseCreateLocks[cid] then
        return false, '해당 시민의 도주/수배 등록이 이미 처리 중입니다.'
    end
    chaseCreateLocks[cid] = true

    local callOk, resultOk, resultValue, resultMinutes = xpcall(function()
        kind = kind == 'escape' and 'escape' or 'wanted'
        reason = cleanText(reason, 500)
        if reason == '' then return false, '추격 사유를 입력하세요.' end

        local existing = activeChaseForCitizen(cid)
        if existing then
            return false, '해당 시민은 이미 진행 중인 도주/수배 상태입니다.'
        end

        local minutes = chaseMinutes(kind)
        local expires = os.date('%Y-%m-%d %H:%M:%S', os.time() + minutes * 60)
        local id = MySQL.insert.await([[
            INSERT INTO cookie_police_wanted
              (faction_id,citizenid,target_name,kind,reason,
               officer_citizenid,officer_name,expires_at)
            VALUES (?,?,?,?,?,?,?,?)
        ]], {
            member.id,cid,displayCitizen(row),kind,reason,
            actor.citizenid,actor.name,expires
        })

        if not id then return false, '추격전 등록에 실패했습니다.' end

        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_police_wanted_unit
              (wanted_id,citizenid,officer_name)
            VALUES (?,?,?)
        ]], { id,actor.citizenid,actor.name })

        chaseViewByCitizenid[actor.citizenid] = tonumber(id)
        local chase = refreshChase(id,true)

        audit(member,actor,kind..'_add',cid,
            ('%s · %d분 · %s · %s'):format(citizenLabel(row),minutes,reason,tostring(sourceTag or 'manual')))

        if target and GetPlayerName(target) then
            notify(target,('%s 등록 · 제한시간 %d분 · 끝까지 버티면 자동 해제됩니다.'):format(kind=='escape' and '도주' or '수배',minutes),false)
            if chase then pushChase(target,chase,'target') end
        end
        if actor.citizenid and chase then
            local officerSrc = sourceByCitizenid(actor.citizenid)
            if officerSrc then pushChase(officerSrc,chase,'officer') end
        end

        cookiePoliceLog(
            kind=='escape' and 'escape' or 'wanted',
            kind=='escape' and '도주 등록' or '수배 등록',
            reason,{
                {name='대상',value=citizenLabel(row),inline=true},
                {name='유효시간',value=tostring(minutes)..'분',inline=true},
                {name='등록방식',value=tostring(sourceTag or 'manual'),inline=true},
            },{
                actorSrc=sourceByCitizenid(actor.citizenid),targetSrc=target,
                actorLabel='등록자',targetLabel='대상',eventKey=kind
            }
        )

        return true,chase,minutes
    end, debug.traceback)

    chaseCreateLocks[cid] = nil

    if not callOk then
        print(('^1[cookie_police MDT]^7 createChase crash (%s): %s'):format(cid,tostring(resultOk)))
        return false, '도주/수배 등록 중 서버 오류가 발생했습니다. 서버 콘솔의 [cookie_police MDT] 로그를 확인하세요.'
    end

    return resultOk, resultValue, resultMinutes
end

local function appearanceHud(row, visible)
    if not row then return end
    local targetSrc = sourceByCitizenid(row.target_citizenid)
    local officerSrc = sourceByCitizenid(row.officer_citizenid)
    if visible == false then
        if targetSrc then TriggerClientEvent('cookie_police:client:appearanceHud',targetSrc,{visible=false,id=row.id}) end
        if officerSrc then TriggerClientEvent('cookie_police:client:appearanceHud',officerSrc,{visible=false,id=row.id}) end
        return
    end
    local deadline = tonumber(row.deadline_ts) or 0
    local remain = math.max(0,deadline-os.time())
    if targetSrc then
        TriggerClientEvent('cookie_police:client:appearanceHud',targetSrc,{visible=true,id=row.id,role='target',target=row.target_name or '-',seconds=remain})
    end
    if officerSrc then
        TriggerClientEvent('cookie_police:client:appearanceHud',officerSrc,{visible=true,id=row.id,role='requester',target=row.target_name or '-',seconds=remain})
    end
end

local function appearanceRow(id)
    return MySQL.single.await([[
        SELECT a.*,UNIX_TIMESTAMP(a.deadline_at) AS deadline_ts
        FROM cookie_police_appearance_request a
        WHERE a.id=? LIMIT 1
    ]],{tonumber(id)})
end

CreateThread(function()
    Wait(500)
    local okInit, initErr = xpcall(function()
        createTables()
        loadActiveChases()
    end, debug.traceback)

    if not okInit then
        print(('^1[cookie_police MDT]^7 V3.0.2 startup failed: %s'):format(tostring(initErr)))
        return
    end

    print('^2[cookie_police]^7 MDT V3.0.2 pursuit/wanted/appearance system ready')
end)

CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        local expiredIds = {}

        for id,chase in pairs(activeChases) do
            if chase.expiresAt <= now then
                expiredIds[#expiredIds+1] = id
            else
                local targetSrc = sourceByCitizenid(chase.citizenid)
                if targetSrc then pushChase(targetSrc,chase,'target') end
                for cid in pairs(chase.participants) do
                    if tonumber(chaseViewByCitizenid[cid]) == tonumber(id) then
                        local src = sourceByCitizenid(cid)
                        if src then pushChase(src,chase,'officer') end
                    end
                end
            end
        end

        for _,id in ipairs(expiredIds) do
            local chase = activeChases[id]
            hideChase(chase)
            MySQL.update.await([[
                UPDATE cookie_police_wanted
                SET active=0,cleared_at=NOW(),cleared_by='TIMEOUT',clear_reason='시간 만료'
                WHERE id=? AND active=1
            ]],{id})
            if chase then
                local label=chase.kind=='escape' and '도주' or '수배'
                local targetSrc=sourceByCitizenid(chase.citizenid)
                if targetSrc then notify(targetSrc,label..' 제한시간을 모두 버텼습니다. 자유 상태로 전환되었습니다.',false) end
                for cid in pairs(chase.participants or {}) do
                    local officerSrc=sourceByCitizenid(cid)
                    if officerSrc then notify(officerSrc,chase.targetLabel..'님의 '..label..' 제한시간이 만료되었습니다.',false) end
                end
            end
            activeChases[id]=nil
        end

        local overdue = MySQL.query.await([[
            SELECT a.*,UNIX_TIMESTAMP(a.deadline_at) AS deadline_ts
            FROM cookie_police_appearance_request a
            WHERE a.status='accepted' AND a.deadline_at IS NOT NULL AND a.deadline_at<=NOW()
            LIMIT 50
        ]]) or {}
        for _,row in ipairs(overdue) do
            MySQL.update.await([[
                UPDATE cookie_police_appearance_request
                SET status='overdue' WHERE id=? AND status='accepted'
            ]],{row.id})
            appearanceHud(row,false)
            local officerSrc=sourceByCitizenid(row.officer_citizenid)
            if officerSrc then
                notify(officerSrc,(row.target_name or '대상')..'님의 출석 대기 10분이 종료되었습니다. F5에서 수배를 수동 등록할 수 있습니다.',false)
            end
        end
    end
end)

-- -------------------------------------------------------------------
-- Boards / lookups
-- -------------------------------------------------------------------
local function citizenSearchResult(q)
    local rows = queryCitizenMatches(q)
    local out = {}

    for _, r in ipairs(rows) do
        out[#out+1] = {
            citizenid = r.citizenid, -- 상세 버튼 내부 식별용
            gobun = r.gobun,
            name = displayCitizen(r),
            identity = citizenLabel(r),
        }
    end

    return tableResult('신원 조회 결과', {
        {key='identity',label='고번 / 이름'},
    }, out, {
        {action='identity_open',label='상세',tone='blue'}
    })
end

local function licenseLookup(q)
    local row, why, _, matches = resolveCitizen(q)
    if not row then
        if matches then return citizenSearchResult(q) end
        return {ok=false,message=why}
    end

    local dl=cookieDriverLicense(row.citizenid)
    local other=otherLicensesFromMetadata(row.metadata)

    local status='미발급'
    local no='-'
    local untilText='-'
    local reason='-'

    if dl then
        no=dl.licenseNo or '-'
        status=dl.suspended and '정지' or '정상'
        reason=dl.suspended and (dl.reason or '-') or '-'
        if dl.suspended and dl.suspendedUntil then
            untilText=os.date('%Y-%m-%d %H:%M:%S',tonumber(dl.suspendedUntil))
        end
    end

    return tableResult('면허 조회 결과', {
        {key='identity',label='고번 / 이름'},
        {key='driverNo',label='운전면허번호'},
        {key='driverStatus',label='상태'},
        {key='suspendedUntil',label='정지 종료'},
        {key='reason',label='정지 사유'},
        {key='other',label='기타 면허/자격'},
    }, {{
        identity=citizenLabel(row),
        driverNo=no,
        driverStatus=status,
        suspendedUntil=untilText,
        reason=reason,
        other=#other>0 and table.concat(other,', ') or '-'
    }})
end

local function rosterResult(member)
    local rows = MySQL.query.await([[
        SELECT m.citizenid, m.grade, m.duty, r.rank_name, cu.gobun, cu.nickname
        FROM cookie_faction_member m
        LEFT JOIN cookie_faction_rank r
          ON r.faction_id=m.faction_id AND r.grade=m.grade
        LEFT JOIN players p ON p.citizenid=m.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE m.faction_id=? AND m.status='active'
        ORDER BY m.duty DESC, m.grade DESC, cu.gobun ASC
    ]], { member.id }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        out[#out+1] = {
            identity=('%s / %s'):format(tostring(r.gobun or '-'), tostring(r.nickname or '-')),
            rank=r.rank_name or ('G'..tostring(r.grade or 0)),
            duty=(r.duty==1 or r.duty==true) and '근무중' or '퇴근'
        }
    end

    return tableResult('근무자 현황', {
        {key='identity',label='고번 / 이름'},
        {key='rank',label='계급'},
        {key='duty',label='상태'}
    }, out)
end

local function wantedBoard(member, actor)
    local rows = MySQL.query.await([[
        SELECT w.id,w.citizenid,w.target_name,w.kind,w.reason,w.officer_citizenid,w.officer_name,
               w.expires_at,UNIX_TIMESTAMP(w.expires_at) AS expires_ts,
               cu.gobun,cu.nickname,
               (SELECT COUNT(*) FROM cookie_police_wanted_unit u WHERE u.wanted_id=w.id) AS units,
               (SELECT COUNT(*) FROM cookie_police_wanted_unit u WHERE u.wanted_id=w.id AND u.citizenid=?) AS joined,
               (SELECT GROUP_CONCAT(u.officer_name ORDER BY u.joined_at SEPARATOR ', ')
                  FROM cookie_police_wanted_unit u WHERE u.wanted_id=w.id) AS unit_names
        FROM cookie_police_wanted w
        LEFT JOIN players p ON p.citizenid=w.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE w.active=1 AND w.expires_at>NOW()
        ORDER BY w.id DESC
        LIMIT ?
    ]], { actor.citizenid,Config.MDT.recentRows or 50 }) or {}

    local out={}
    local now=os.time()
    for _,r in ipairs(rows) do
        local kind=r.kind=='escape' and '도주' or '수배'
        local remain=math.max(0,(tonumber(r.expires_ts) or now)-now)
        out[#out+1]={
            id=r.id,citizenid=r.citizenid,kind=kind,
            target=('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or r.target_name or '-')),
            reason=r.reason,officer=r.officer_name or '-',
            remaining=('%02d:%02d'):format(math.floor(remain/60),remain%60),
            participants=('%s명 · %s'):format(tonumber(r.units) or 0,tostring(r.unit_names or '-')),
            joinLabel=(kind=='도주') and '도주 참여' or '수배 참여',
            canJoin=(tonumber(r.joined) or 0)==0,
            canClear=tostring(r.officer_citizenid or '')==tostring(actor.citizenid or '')
        }
    end

    return tableResult('수배/도주 현황',{
        {key='kind',label='구분'},
        {key='target',label='고번 / 이름'},
        {key='reason',label='사유'},
        {key='officer',label='등록자'},
        {key='remaining',label='남은 시간'},
        {key='participants',label='참여 인원'},
    },out,{
        {action='wanted_join',label='참여',labelKey='joinLabel',tone='blue',showKey='canJoin'},
        {action='wanted_clear',label='종료',tone='green',showKey='canClear'}
    })
end

local function appearanceBoard(member, actor)
    local rows=MySQL.query.await([[
        SELECT a.*,UNIX_TIMESTAMP(a.deadline_at) AS deadline_ts,
               cu.gobun,cu.nickname
        FROM cookie_police_appearance_request a
        LEFT JOIN players p ON p.citizenid=a.target_citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE a.status IN ('pending','accepted','overdue')
        ORDER BY a.id DESC LIMIT ?
    ]],{Config.MDT.recentRows or 50}) or {}

    local out={}
    local now=os.time()
    local labels={pending='응답 대기',accepted='출석 대기',overdue='10분 초과'}
    for _,r in ipairs(rows) do
        local manage=tostring(r.officer_citizenid or '')==tostring(actor.citizenid or '')
        local remain='-'
        if r.status=='accepted' and r.deadline_ts then
            local sec=math.max(0,tonumber(r.deadline_ts)-now)
            remain=('%02d:%02d'):format(math.floor(sec/60),sec%60)
        elseif r.status=='overdue' then
            remain='시간 초과'
        end
        out[#out+1]={
            id=r.id,
            target=('%s / %s'):format(tostring(r.gobun or '-'),tostring(r.nickname or r.target_name or '-')),
            reason=r.reason,
            officer=r.officer_name or '-',
            statusLabel=labels[r.status] or r.status,
            remaining=remain,
            canComplete=manage and (r.status=='accepted' or r.status=='overdue'),
            canWanted=manage and r.status=='overdue',
            canCancel=manage and (r.status=='pending' or r.status=='accepted' or r.status=='overdue')
        }
    end

    return tableResult('출석 요구 현황',{
        {key='target',label='고번 / 이름'},
        {key='reason',label='사유'},
        {key='officer',label='요구자'},
        {key='statusLabel',label='상태'},
        {key='remaining',label='남은 시간'},
    },out,{
        {action='appearance_complete',label='출석 완료',tone='green',showKey='canComplete'},
        {action='appearance_wanted',label='수배 등록',tone='red',showKey='canWanted'},
        {action='appearance_cancel',label='요구 취소',tone='blue',showKey='canCancel'}
    })
end

local function warrantTargetOptions(member)
    local rows = MySQL.query.await([[
        SELECT id,faction_key,faction_type,name
        FROM cookie_faction
        WHERE is_active=1
        ORDER BY faction_type,name
    ]]) or {}

    local options = {}
    local labels = {
        private='사설팩션',
        crime='범죄조직',
        civil='시민직',
        police='경찰',
        security='보안',
        corrections='교정',
        fire='소방'
    }

    for _, f in ipairs(rows) do
        local t = tostring(f.faction_type or '')
        if Config.WarrantTargetTypes[t] and tonumber(f.id) ~= tonumber(member.id) then
            options[#options+1] = {
                value=tostring(f.id),
                label=('[%s] %s'):format(labels[t] or t, tostring(f.name or f.faction_key))
            }
        end
    end

    return {
        ok=true,
        kind='options',
        title='영장 대상 팩션/조직',
        options=options
    }
end

local function warrantBoard(member)
    local rows = MySQL.query.await([[
        SELECT id,target_faction_id,target_faction_name,target_faction_type,
               warrant_type,reason,officer_name,expires_at
        FROM cookie_police_warrant
        WHERE faction_id=?
          AND target_faction_id IS NOT NULL
          AND active=1
          AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY id DESC
        LIMIT ?
    ]], { member.id, Config.MDT.recentRows or 50 }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        out[#out+1] = {
            id=r.id,
            targetFactionId=r.target_faction_id,
            type=(r.warrant_type=='raid' and '작전 영장' or '수색 영장'),
            target=r.target_faction_name or '-',
            reason=r.reason,
            officer=r.officer_name,
            expires=r.expires_at or '무기한'
        }
    end

    return tableResult('팩션/조직 영장 현황', {
        {key='type',label='종류'},
        {key='target',label='대상 팩션/조직'},
        {key='reason',label='사유'},
        {key='officer',label='발부자'},
        {key='expires',label='만료'}
    }, out, {
        {action='warrant_close',label='종료',tone='green'}
    })
end

local function dispatchBoard(member)
    local rows = MySQL.query.await([[
        SELECT d.id,d.title,d.detail,d.priority,d.created_by,d.created_at,
               (SELECT COUNT(*) FROM cookie_police_dispatch_unit u WHERE u.dispatch_id=d.id) AS units
        FROM cookie_police_dispatch d
        WHERE d.active=1 AND (d.faction_id IS NULL OR d.faction_id=?)
        ORDER BY d.priority DESC,d.id DESC
        LIMIT ?
    ]], { member.id, Config.MDT.recentRows or 50 }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        out[#out+1] = {
            id=r.id,
            priority=('P'..tostring(r.priority or 1)),
            title=r.title,
            detail=r.detail,
            units=r.units,
            created_by=r.created_by,
            created_at=r.created_at
        }
    end

    return tableResult('신고/출동 현황', {
        {key='priority',label='우선'},
        {key='title',label='신고'},
        {key='detail',label='내용'},
        {key='units',label='출동'},
        {key='created_at',label='접수'}
    }, out, {
        {action='dispatch_join',label='출동 참가',tone='blue'},
        {action='dispatch_close',label='종결',tone='green'}
    })
end

local function casesBoard(member)
    local rows = MySQL.query.await([[
        SELECT c.id,c.case_no,c.title,c.suspect_name,c.officer_name,c.status,c.created_at,
               cu.gobun
        FROM cookie_police_case c
        LEFT JOIN players p ON p.citizenid=c.suspect_citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE c.faction_id=?
        ORDER BY c.id DESC
        LIMIT ?
    ]], { member.id, Config.MDT.recentRows or 50 }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        out[#out+1] = {
            id=r.id,
            case_no=r.case_no,
            title=r.title,
            suspect=(r.suspect_name and r.suspect_name ~= '') and
                (('%s / %s'):format(tostring(r.gobun or '-'), tostring(r.suspect_name))) or '-',
            officer_name=r.officer_name,
            status=r.status,
            created_at=r.created_at
        }
    end

    return tableResult('사건 목록', {
        {key='case_no',label='사건번호'},
        {key='title',label='사건명'},
        {key='suspect',label='피의자'},
        {key='officer_name',label='작성자'},
        {key='status',label='상태'},
        {key='created_at',label='작성일'}
    }, out, {
        {action='case_close',label='종결',tone='green'}
    })
end

local function auditBoard(member)
    local rows = MySQL.query.await([[
        SELECT actor_name,action,detail,created_at
        FROM cookie_police_audit
        WHERE faction_id=?
        ORDER BY id DESC
        LIMIT ?
    ]], { member.id, Config.MDT.recentRows or 50 }) or {}

    return tableResult('업무 로그', {
        {key='actor_name',label='처리자'},
        {key='action',label='업무'},
        {key='detail',label='내용'},
        {key='created_at',label='시간'}
    }, rows)
end

local function budgetBoard(member)
    if not (member.isOfficer or member.isLeader) then
        return {ok=false,message='간부 이상만 조회할 수 있습니다.'}
    end

    local f = MySQL.single.await('SELECT budget FROM cookie_faction WHERE id=?', { member.id }) or {}
    local rows = MySQL.query.await([[
        SELECT delta,balance_after,category,reason,created_at
        FROM cookie_faction_budget_log
        WHERE faction_id=?
        ORDER BY id DESC LIMIT 30
    ]], { member.id }) or {}

    return {
        ok=true,
        kind='summary',
        title='팩션 공금',
        metrics={
            {label='현재 공금',value=tonumber(f.budget) or 0},
            {label='최근 내역',value=#rows}
        },
        columns={
            {key='delta',label='변동'},
            {key='balance_after',label='잔액'},
            {key='category',label='구분'},
            {key='reason',label='사유'},
            {key='created_at',label='시간'}
        },
        rows=rows
    }
end

local function vehicleLookup(q)
    q = cleanText(q, 60)
    if q == '' then return {ok=false,message='번호판 또는 소유자 고번/이름을 입력하세요.'} end

    local nameLike = '%' .. q .. '%'
    local plateLike = '%' .. cleanPlate(q) .. '%'

    local rows = MySQL.query.await([[
        SELECT pv.id,pv.citizenid,pv.plate,cu.gobun,cu.nickname
        FROM player_vehicles pv
        LEFT JOIN players p ON p.citizenid=pv.citizenid
        LEFT JOIN cookie_user cu
          ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
           = SUBSTRING_INDEX(p.license, ':', -1) COLLATE utf8mb4_unicode_ci
        WHERE REPLACE(UPPER(pv.plate),' ','') LIKE ?
           OR cu.nickname LIKE ?
           OR CAST(cu.gobun AS CHAR)=?
        ORDER BY pv.id DESC
        LIMIT ?
    ]], { plateLike, nameLike, q, Config.MDT.maxSearchResults or 30 }) or {}

    local out = {}
    for _, r in ipairs(rows) do
        out[#out+1] = {
            plate=r.plate,
            owner=('%s / %s'):format(tostring(r.gobun or '-'), tostring(r.nickname or '-'))
        }
    end

    return tableResult('차량 조회 결과', {
        {key='plate',label='번호판'},
        {key='owner',label='소유자'}
    }, out)
end

-- -------------------------------------------------------------------
-- Main MDT actions
-- -------------------------------------------------------------------
lib.callback.register('cookie_police:mdtAction', function(source, action, payload)
    local src = source
    payload = type(payload)=='table' and payload or {}
    action = tostring(action or '')

    local officerOnly =
        action == 'warrant_add'
        or action == 'budget_lookup'
        or action == 'budget_deposit'
        or action == 'intranet_ledger_add'
        or action == 'intranet_settlement_board'
        or action == 'intranet_settlement_pay'

    local member, err = guard(src, officerOnly)
    if not member then return err end

    local actor = officerInfo(src, member)

    if CookieIntranetAction then
        local extra = CookieIntranetAction(src, action, payload, member, actor)
        if extra ~= nil then return extra end
    end

    if action == 'identity_lookup' then
        return citizenSearchResult(payload.query)

    elseif action == 'license_lookup' then
        return licenseLookup(payload.query)

    elseif action == 'vehicle_lookup' then
        return vehicleLookup(payload.query)

    elseif action == 'roster' then
        return rosterResult(member)

    elseif action == 'wanted_board' then
        return wantedBoard(member,actor)

    elseif action == 'appearance_board' then
        return appearanceBoard(member,actor)

    elseif action == 'warrant_targets' then
        return warrantTargetOptions(member)

    elseif action == 'warrant_board' then
        return warrantBoard(member)

    elseif action == 'dispatch' then
        return dispatchBoard(member)

    elseif action == 'cases' then
        return casesBoard(member)

    elseif action == 'audit' then
        return auditBoard(member)

    elseif action == 'budget_lookup' then
        return budgetBoard(member)
    end

    -- 운전면허 정지/해제는 경찰청/보안국 근무자가 사용 가능.
    if action=='license_suspend' or action=='license_restore' then
        local memberType=tostring(member.type or ''):lower()
        if memberType~='police' and memberType~='security' then
            return {ok=false,message='운전면허 정지/해제는 경찰청/보안국만 사용할 수 있습니다.'}
        end
        if GetResourceState('cookie_license')~='started' then
            return {ok=false,message='운전면허 시스템이 실행 중이 아닙니다.'}
        end

        local row,why=resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end

        local actorPayload={
            source=src,
            type=memberType,
            name=actor.name,
            faction=member.name or (memberType=='security' and '보안국' or '경찰청')
        }

        if action=='license_suspend' then
            local minutes=clampInt(payload.minutes,1,60,0)
            if minutes<1 then return {ok=false,message='면허 정지시간을 분 단위로 입력하세요.'} end

            local reason=cleanText(payload.reason,300)
            if #reason<2 then return {ok=false,message='죄목/정지 사유를 입력하세요.'} end

            local ok,result=exports.cookie_license:SuspendByCitizenId(
                row.citizenid,minutes,reason,actorPayload
            )
            if not ok then return {ok=false,message=result or '면허 정지에 실패했습니다.'} end

            audit(member,actor,'license_suspend',row.citizenid,
                ('%s · %d분 · %s'):format(citizenLabel(row),minutes,reason))

            return success(
                '운전면허 정지 완료',
                ('%s · %d분'):format(citizenLabel(row),minutes)
            )
        end

        local reason=cleanText(payload.reason,300)
        if #reason<2 then return {ok=false,message='정지 해제 사유를 입력하세요.'} end

        local ok,result,message=exports.cookie_license:RestoreByCitizenId(
            row.citizenid,reason,actorPayload
        )
        if not ok then return {ok=false,message=result or '면허 정지 해제에 실패했습니다.'} end

        audit(member,actor,'license_restore',row.citizenid,
            citizenLabel(row)..' · '..reason)

        return success(
            '운전면허 정지 해제',
            message or (citizenLabel(row)..' 운전면허를 정상 상태로 변경했습니다.')
        )
    end

    -- 출석 요구: 사유 포함 요구서 -> 수락 시 10분, 거절 시 자동 수배.
    if action == 'appearance_add' then
        local row,why,target=resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end
        if activeChaseForCitizen(row.citizenid) then
            return {ok=false,message='이미 도주/수배 상태인 대상에게는 출석 요구를 보낼 수 없습니다.'}
        end

        local existing=MySQL.single.await([[
            SELECT id FROM cookie_police_appearance_request
            WHERE target_citizenid=? AND status IN ('pending','accepted','overdue')
            ORDER BY id DESC LIMIT 1
        ]],{row.citizenid})
        if existing then return {ok=false,message='해당 시민에게 이미 진행 중인 출석 요구가 있습니다.'} end

        local reason=cleanText(payload.reason,500)
        if #reason<2 then return {ok=false,message='출석 요구 사유를 입력하세요.'} end

        local id=MySQL.insert.await([[
            INSERT INTO cookie_police_appearance_request
              (faction_id,faction_name,target_citizenid,target_name,reason,
               officer_citizenid,officer_name,status)
            VALUES (?,?,?,?,?,?,?,'pending')
        ]],{
            member.id,tostring(member.name or member.type or '경찰/보안국'),
            row.citizenid,displayCitizen(row),reason,actor.citizenid,actor.name
        })
        if not id then return {ok=false,message='출석 요구 저장에 실패했습니다.'} end

        audit(member,actor,'appearance_add',row.citizenid,citizenLabel(row)..' · '..reason)
        if target then
            TriggerClientEvent('cookie_police:client:appearanceRequest',target,{
                id=id,targetName=displayCitizen(row),faction=tostring(member.name or '경찰/보안국'),reason=reason
            })
            notify(target,('%s님, %s로 출석 바랍니다. 수락 또는 거절을 선택해주세요.'):format(displayCitizen(row),reason),false)
        end
        return success('출석 요구 발송',target and (citizenLabel(row)..'에게 출석 요구서를 보냈습니다.') or (citizenLabel(row)..' 출석 요구를 저장했습니다. 대상이 접속하면 요구서가 표시됩니다.'))
    end

    -- 도주/수배는 고정 시간제이며 동시에 존재할 수 없다.
    if action == 'wanted_add' or action == 'escape_add' then
        local row,why,target=resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end
        local reason=cleanText(payload.reason,500)
        if reason=='' then return {ok=false,message='추격 사유를 입력하세요.'} end
        local kind=action=='escape_add' and 'escape' or 'wanted'
        local ok,chaseOrWhy,minutes=createChase(member,actor,row,target,kind,reason,'manual')
        if not ok then return {ok=false,message=chaseOrWhy} end
        return success(kind=='escape' and '도주 등록' or '수배 등록',('%s · %d분'):format(citizenLabel(row),minutes))

    elseif action == 'warrant_add' then
        local targetFactionId = tonumber(payload.targetFactionId)
        if not targetFactionId then return {ok=false,message='대상 팩션/조직을 선택하세요.'} end

        local faction = MySQL.single.await([[
            SELECT id,faction_key,faction_type,name
            FROM cookie_faction
            WHERE id=? AND is_active=1
            LIMIT 1
        ]], { targetFactionId })

        if not faction then return {ok=false,message='대상 팩션/조직을 찾지 못했습니다.'} end
        if tonumber(faction.id) == tonumber(member.id) then
            return {ok=false,message='자기 팩션을 영장 대상으로 지정할 수 없습니다.'}
        end
        if not Config.WarrantTargetTypes[tostring(faction.faction_type or '')] then
            return {ok=false,message='현재 설정상 영장 대상이 될 수 없는 팩션 유형입니다.'}
        end

        local wt = payload.warrantType == 'raid' and 'raid' or 'search'
        local reason = cleanText(payload.reason, 500)
        if reason == '' then return {ok=false,message='영장 발부 사유를 입력하세요.'} end

        local minutes = clampInt(
            payload.minutes, 0,
            Config.MDT.maxWarrantMinutes or 43200,
            0
        )
        local expires = minutes > 0
            and os.date('%Y-%m-%d %H:%M:%S', os.time()+minutes*60)
            or nil

        MySQL.insert.await([[
            INSERT INTO cookie_police_warrant
              (faction_id,citizenid,target_name,
               target_faction_id,target_faction_key,target_faction_name,target_faction_type,
               warrant_type,reason,officer_citizenid,officer_name,expires_at)
            VALUES (?,NULL,NULL,?,?,?,?,?,?,?,?,?)
        ]], {
            member.id,
            faction.id,faction.faction_key,faction.name,faction.faction_type,
            wt,reason,actor.citizenid,actor.name,expires
        })

        audit(
            member,actor,'warrant_add',nil,
            ('%s · %s · %s'):format(
                tostring(faction.name),
                wt == 'raid' and '작전 영장' or '수색 영장',
                reason
            )
        )

        cookiePoliceLog('warrant','영장 발부',reason,{
            {name='대상 팩션/조직',value=tostring(faction.name or '-'),inline=true},
            {name='종류',value=wt=='raid' and '작전 영장' or '수색 영장',inline=true},
            {name='유효시간',value=minutes>0 and (tostring(minutes)..'분') or '무기한',inline=true},
        },{actorSrc=src,actorLabel='발부자',eventKey='warrant'})

        return success(
            '팩션/조직 영장 발부 완료',
            ('%s · %s'):format(
                faction.name,
                wt == 'raid' and '작전 영장' or '수색 영장'
            )
        )

    elseif action == 'fine' then
        local row, why, target = resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end
        if not target then return {ok=false,message='벌금 대상이 현재 접속 중이 아닙니다.'} end
        if not targetNearby(src,target,Config.TargetDistance+2.0) then
            return {ok=false,message='대상이 너무 멉니다.'}
        end

        local amount = clampInt(payload.amount,1,Config.MDT.maxFine or 50000000,0)
        local reason = cleanText(payload.reason,300)
        if amount < 1 or reason == '' then
            return {ok=false,message='벌금액과 사유를 입력하세요.'}
        end

        local tp = exports.qbx_core:GetPlayer(target)
        local paid = false
        local paymentMethod = '미납'
        if tp and tp.Functions.RemoveMoney('bank',amount,'경찰 벌금: '..reason) == true then
            paid = true
            paymentMethod = '은행'
        elseif tp and tp.Functions.RemoveMoney('cash',amount,'경찰 벌금: '..reason) == true then
            paid = true
            paymentMethod = '현금'
        end

        local fineId = MySQL.insert.await([[
            INSERT INTO cookie_police_fine
              (faction_id,target_citizenid,target_name,amount,reason,paid,
               officer_citizenid,officer_name)
            VALUES (?,?,?,?,?,?,?,?)
        ]], {
            member.id,row.citizenid,displayCitizen(row),amount,reason,
            paid and 1 or 0,actor.citizenid,actor.name
        })

        if paid then
            pcall(function()
                exports.cookie_admin:addFactionIncome(
                    member.id,amount,'fine_income',reason,actor.citizenid
                )
            end)
        end

        audit(
            member,actor,'fine',row.citizenid,
            ('%s · %d원 · %s'):format(citizenLabel(row),amount,reason)
        )

        notify(
            target,
            ('벌금 %s원이 부과되었습니다. 사유: %s%s'):format(
                amount,reason,paid and '' or ' (잔액 부족으로 미납)'
            ),
            not paid
        )

        sendFineReceipt(
            target, member, actor,
            fineId and ('F-%06d'):format(tonumber(fineId) or 0) or ('F-%d'):format(os.time()),
            reason, amount, paid, paymentMethod
        )

        cookiePoliceLog('fine','벌금 부과',reason,{
            {name='벌금',value=tostring(amount)..'원',inline=true},
            {name='납부',value=paid and '납부 완료' or '미납',inline=true},
            {name='집행 팩션',value=tostring(member.name or '-'),inline=true},
        },{
            actorSrc=src,targetSrc=target,
            actorLabel='부과자',targetLabel='대상',
            eventKey='fine'
        })

        return success(
            '벌금 처리 완료',
            ('%s · %s원 · %s'):format(
                citizenLabel(row),amount,paid and '납부 완료' or '미납 기록'
            )
        )

    elseif action == 'search_items' then
        local row, why, target = resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end
        if not target or not targetNearby(src,target,Config.TargetDistance+1.5) then
            return {ok=false,message='대상이 접속 중이 아니거나 너무 멉니다.'}
        end
        if not isCuffed(target) then
            return {ok=false,message='수갑이 채워진 대상만 소지품 검사할 수 있습니다.'}
        end

        TriggerClientEvent('cookie_police:client:openTargetInventory',src,target)
        audit(member,actor,'inventory_search',row.citizenid,citizenLabel(row)..' 소지품 검사')
        return success('소지품 검사', citizenLabel(row)..' 인벤토리를 열었습니다.')

    elseif action == 'seize_items' then
        local row, why, target = resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end
        if not target or not targetNearby(src,target,Config.TargetDistance+1.5) then
            return {ok=false,message='대상이 접속 중이 아니거나 너무 멉니다.'}
        end
        if not isCuffed(target) then
            return {ok=false,message='수갑이 채워진 대상만 압수할 수 있습니다.'}
        end
        if GetResourceState('ox_inventory') ~= 'started' then
            return {ok=false,message='ox_inventory가 실행 중이 아닙니다.'}
        end

        local item = cleanText(payload.item,100):lower()
        local count = clampInt(payload.count,1,1000,1)
        local reason = cleanText(payload.reason,300)

        if item=='' or reason=='' then
            return {ok=false,message='아이템과 압수 사유를 입력하세요.'}
        end

        local okR, removed = pcall(function()
            return exports.ox_inventory:RemoveItem(target,item,count)
        end)
        if not okR or removed ~= true then
            return {ok=false,message='대상에게 해당 아이템/수량이 없거나 압수하지 못했습니다.'}
        end

        local okA, added = pcall(function()
            return exports.ox_inventory:AddItem(src,item,count)
        end)

        if not okA or added ~= true then
            pcall(function() exports.ox_inventory:AddItem(target,item,count) end)
            return {ok=false,message='경찰 인벤토리 공간이 부족하여 압수를 취소했습니다.'}
        end

        audit(
            member,actor,'seize',row.citizenid,
            ('%s · %s x%d · %s'):format(citizenLabel(row),item,count,reason)
        )

        cookiePoliceLog('seize','아이템 압수',reason,{
            {name='아이템',value=('%s x%d'):format(item,count),inline=true},
            {name='집행 팩션',value=tostring(member.name or '-'),inline=true},
        },{
            actorSrc=src,targetSrc=target,
            actorLabel='압수자',targetLabel='대상',
            eventKey='seize'
        })

        return success('압수 완료', ('%s x%d를 압수했습니다.'):format(item,count))

    elseif action == 'detain' then
        local row, why, target = resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end
        if not target or not targetNearby(src,target,Config.TargetDistance+2.0) then
            return {ok=false,message='대상이 접속 중이 아니거나 너무 멉니다.'}
        end
        if not isCuffed(target) then
            return {ok=false,message='수갑이 채워진 대상만 구금할 수 있습니다.'}
        end

        local charge = cleanText(payload.charge,200)
        local minutes = clampInt(payload.minutes,1,Config.Detention.maxMinutes or 720,1)
        local fine = clampInt(payload.fine,0,Config.MDT.maxFine or 50000000,0)
        local note = cleanText(payload.note,500)
        if charge=='' then return {ok=false,message='죄목을 입력하세요.'} end

        local paidFine=0
        local detentionPaymentMethod='미납'
        local tp=exports.qbx_core:GetPlayer(target)
        if fine>0 and tp then
            if tp.Functions.RemoveMoney('bank',fine,'구금 벌금: '..charge) == true then
                paidFine=fine
                detentionPaymentMethod='은행'
            elseif tp.Functions.RemoveMoney('cash',fine,'구금 벌금: '..charge) == true then
                paidFine=fine
                detentionPaymentMethod='현금'
            end
        end

        pcall(function()
            exports.cookie_admin:recordDetention(
                member.id,actor.citizenid,row.citizenid,displayCitizen(row),
                charge,paidFine,minutes*60,note
            )
        end)

        MySQL.update.await([[
            UPDATE cookie_police_detention_active
            SET active=0,released_at=NOW(),released_by='REPLACED'
            WHERE citizenid=? AND active=1
        ]], {row.citizenid})

        local detentionId = MySQL.insert.await([[
            INSERT INTO cookie_police_detention_active
              (faction_id,citizenid,target_name,charge,release_at,
               officer_citizenid,officer_name)
            VALUES (?,?,?,?,DATE_ADD(NOW(),INTERVAL ? SECOND),?,?)
        ]], {
            member.id,row.citizenid,displayCitizen(row),charge,
            minutes*60,actor.citizenid,actor.name
        })

        audit(
            member,actor,'detain',row.citizenid,
            ('%s · %s · %d분 · 벌금 %d'):format(
                citizenLabel(row),charge,minutes,paidFine
            )
        )

        pcall(function() exports.cookie_police:ForceSetCuffed(target, false) end)
        TriggerClientEvent('cookie_police:client:setDetained',target,minutes*60,charge,true)
        notify(target, ('%s 사유로 %d분 구금되었습니다.'):format(charge,minutes), false)

        if fine > 0 then
            sendFineReceipt(
                target, member, actor,
                detentionId and ('D-%06d'):format(tonumber(detentionId) or 0) or ('D-%d'):format(os.time()),
                charge, fine, paidFine == fine, detentionPaymentMethod
            )
        end

        local detentionLogKey =
            tostring(member.type or ''):lower()=='security'
            and 'security_detention'
            or 'police_detention'

        cookiePoliceLog(
            detentionLogKey,
            tostring(member.type or ''):lower()=='security' and '보안국 구금' or '경찰청 구금',
            charge,{
                {name='구금시간',value=tostring(minutes)..'분',inline=true},
                {name='벌금',value=tostring(fine)..'원',inline=true},
                {name='실납부',value=tostring(paidFine)..'원',inline=true},
                {name='메모',value=note~='' and note or '-',inline=false},
            },{
                actorSrc=src,targetSrc=target,
                actorLabel='집행자',targetLabel='구금 대상',
                eventKey='detention'
            }
        )

        return success(
            '구금 집행 완료',
            ('%s · %d분%s'):format(
                citizenLabel(row),minutes,
                (fine>0 and paidFine==0) and ' · 벌금 미납' or ''
            )
        )

    elseif action == 'release' then
        local row, why, target = resolveCitizen(payload.target)
        if not row then return {ok=false,message=why} end

        local affected=MySQL.update.await([[
            UPDATE cookie_police_detention_active
            SET active=0,released_at=NOW(),released_by=?
            WHERE citizenid=? AND active=1
        ]], {actor.name,row.citizenid})

        if not affected or affected<1 then
            return {ok=false,message='현재 구금 중인 시민이 아닙니다.'}
        end

        if target then
            TriggerClientEvent(
                'cookie_police:client:setDetained',
                target,0,cleanText(payload.reason,200),false
            )
        end

        audit(
            member,actor,'release',row.citizenid,
            citizenLabel(row)..' · '..cleanText(payload.reason,200)
        )

        return success('석방 처리 완료', citizenLabel(row)..' 시민을 석방했습니다.')

    elseif action == 'case_report' then
        local title=cleanText(payload.title,120)
        local summary=cleanText(payload.summary,5000)
        local result=cleanText(payload.result,3000)

        if title=='' or summary=='' then
            return {ok=false,message='사건명과 사건 경위를 입력하세요.'}
        end

        local suspectCid,suspectName=nil,nil
        if cleanText(payload.suspect,80)~='' then
            local r, why = resolveCitizen(payload.suspect)
            if not r then return {ok=false,message='피의자: '..tostring(why)} end
            suspectCid=r.citizenid
            suspectName=displayCitizen(r)
        end

        local caseNo=('CK-%s-%04d'):format(os.date('%y%m%d'),math.random(0,9999))
        while MySQL.single.await(
            'SELECT id FROM cookie_police_case WHERE case_no=? LIMIT 1',
            {caseNo}
        ) do
            caseNo=('CK-%s-%04d'):format(os.date('%y%m%d'),math.random(0,9999))
        end

        MySQL.insert.await([[
            INSERT INTO cookie_police_case
              (faction_id,case_no,title,suspect_citizenid,suspect_name,
               summary,result,officer_citizenid,officer_name)
            VALUES (?,?,?,?,?,?,?,?,?)
        ]], {
            member.id,caseNo,title,suspectCid,suspectName,
            summary,result,actor.citizenid,actor.name
        })

        audit(member,actor,'case_create',suspectCid,caseNo..' '..title)
        return success('사건 보고서 저장', caseNo..' · '..title)

    elseif action == 'budget_deposit' then
        local amount=clampInt(payload.amount,1,100000000,0)
        local reason=cleanText(payload.reason,120)
        local p=exports.qbx_core:GetPlayer(src)

        if not p or amount<1 then
            return {ok=false,message='입금액을 확인하세요.'}
        end
        if p.Functions.RemoveMoney('bank',amount,'팩션 공금 입금') ~= true then
            return {ok=false,message='은행 잔액이 부족합니다.'}
        end

        local affected=MySQL.update.await(
            'UPDATE cookie_faction SET budget=budget+? WHERE id=?',
            {amount,member.id}
        )

        if not affected or affected<1 then
            p.Functions.AddMoney('bank',amount,'팩션 공금 입금 실패 환불')
            return {ok=false,message='공금 입금 처리에 실패했습니다.'}
        end

        local f=MySQL.single.await(
            'SELECT budget FROM cookie_faction WHERE id=?',
            {member.id}
        ) or {}

        MySQL.insert.await([[
            INSERT INTO cookie_faction_budget_log
              (faction_id,delta,balance_after,category,reason,actor_citizenid)
            VALUES (?,?,?,?,?,?)
        ]], {
            member.id,amount,tonumber(f.budget) or 0,'deposit',
            reason~='' and reason or 'F5 공금 입금',actor.citizenid
        })

        audit(member,actor,'budget_deposit',nil,tostring(amount))

        local accountLogKey =
            tostring(member.type or ''):lower()=='security'
            and 'security_account'
            or 'police_account'

        cookiePoliceLog(
            accountLogKey,
            tostring(member.type or ''):lower()=='security' and '보안국 공동계좌' or '경찰청 공동계좌',
            reason,{
                {name='구분',value='입금',inline=true},
                {name='금액',value=tostring(amount)..'원',inline=true},
                {name='잔액',value=tostring(tonumber(f.budget) or 0)..'원',inline=true},
            },{
                actorSrc=src,actorLabel='처리자',eventKey='account_deposit'
            }
        )

        return success('공금 입금 완료', ('%d원을 입금했습니다.'):format(amount))
    end

    return {ok=false,message='아직 연결되지 않은 업무입니다.'}
end)

-- -------------------------------------------------------------------
-- P.M 자동 도주 / 출석 요구 응답
-- -------------------------------------------------------------------
AddEventHandler('cookie_police:internal:pullOverRecorded',function(officerSrc,targetSrc)
    officerSrc=tonumber(officerSrc); targetSrc=tonumber(targetSrc)
    if not officerSrc or not targetSrc or not GetPlayerName(officerSrc) or not GetPlayerName(targetSrc) then return end
    local ok,member=hasAccess(officerSrc)
    if not ok or not member then return end
    local _,targetPd=playerData(targetSrc)
    if not targetPd or not targetPd.citizenid then return end
    if activeChaseForCitizen(targetPd.citizenid) then return end

    -- 같은 대상에 대한 정차 요청을 경찰/보안국 전체에서 합산한다.
    -- 시간 경과로 초기화하지 않으며 4번째 실제 Y 정차 요청에서 자동 도주 등록.
    local key=tostring(targetPd.citizenid)
    local need=tonumber(Config.Chase and Config.Chase.pmAutoCount) or 4
    local count=(tonumber(pmStopCounts[key]) or 0)+1
    pmStopCounts[key]=count

    local targetRow=citizenRowByCitizenid(targetPd.citizenid)
    notify(officerSrc,('P.M 정차 요청 %d/%d · %s'):format(count,need,targetRow and citizenLabel(targetRow) or GetPlayerName(targetSrc)),count>=need-1)
    if count<need then return end

    pmStopCounts[key]=nil
    if not targetRow then return notify(officerSrc,'도주 자동 등록 대상 정보를 찾지 못했습니다.',true) end
    local actor=officerInfo(officerSrc,member)
    local okCreate,why,minutes=createChase(member,actor,targetRow,targetSrc,'escape','P.M 정차 요구 4회 불응','PM AUTO')
    if not okCreate then return notify(officerSrc,why,true) end
    notify(officerSrc,('P.M 정차 요구 3회 초과로 자동 도주 등록되었습니다. %d분'):format(minutes),false)
end)

RegisterNetEvent('cookie_police:server:appearanceRespond',function(id,accepted)
    local src=source
    local _,pd=playerData(src)
    if not pd or not pd.citizenid then return end
    local row=appearanceRow(id)
    if not row or row.status~='pending' or tostring(row.target_citizenid)~=tostring(pd.citizenid) then return end

    local officerSrc=sourceByCitizenid(row.officer_citizenid)

    -- 출석 요구 대기 중 대상이 이미 도주/수배 상태가 되었다면 출석 절차를 자동 종료한다.
    if activeChaseForCitizen(row.target_citizenid) then
        MySQL.update.await([[
            UPDATE cookie_police_appearance_request
            SET status='cancelled',responded_at=NOW(),completed_at=NOW()
            WHERE id=? AND status='pending'
        ]],{row.id})
        TriggerClientEvent('cookie_police:client:appearanceHud',src,{show=false})
        notify(src,'이미 도주 또는 수배 상태여서 출석 요구가 종료되었습니다.',true)
        if officerSrc then notify(officerSrc,(row.target_name or '대상')..'님이 이미 도주/수배 상태여서 출석 요구가 자동 종료되었습니다.',true) end
        return
    end

    if accepted==true then
        local minutes=tonumber(Config.Chase and Config.Chase.appearanceMinutes) or 10
        local deadline=os.date('%Y-%m-%d %H:%M:%S',os.time()+minutes*60)
        MySQL.update.await([[
            UPDATE cookie_police_appearance_request
            SET status='accepted',responded_at=NOW(),deadline_at=?
            WHERE id=? AND status='pending'
        ]],{deadline,row.id})
        row=appearanceRow(row.id)
        appearanceHud(row,true)
        notify(src,('출석 요구를 수락했습니다. %d분 이내 출석해주세요.'):format(minutes),false)
        if officerSrc then notify(officerSrc,(row.target_name or '대상')..'님이 출석 요구를 수락했습니다. 10분 대기가 시작됩니다.',false) end
        return
    end

    MySQL.update.await([[
        UPDATE cookie_police_appearance_request
        SET status='rejected',responded_at=NOW(),completed_at=NOW()
        WHERE id=? AND status='pending'
    ]],{row.id})
    notify(src,'출석 요구를 거절했습니다. 즉시 수배 등록 절차가 진행됩니다.',true)

    local targetRow=citizenRowByCitizenid(row.target_citizenid)
    local member={id=tonumber(row.faction_id) or 0,name=row.faction_name or '경찰/보안국',type='police'}
    local actor={citizenid=row.officer_citizenid,name=row.officer_name or '담당자',gobun=nil,label=row.officer_name or '담당자',factionId=tonumber(row.faction_id) or 0}
    local okCreate,why=createChase(member,actor,targetRow,src,'wanted','출석 요구 거절 · '..tostring(row.reason or ''),'APPEARANCE REJECT AUTO')
    if okCreate then
        MySQL.update.await("UPDATE cookie_police_appearance_request SET status='wanted' WHERE id=?",{row.id})
        if officerSrc then notify(officerSrc,(row.target_name or '대상')..'님이 출석 요구를 거절하여 수배 30분이 자동 등록되었습니다.',false) end
    elseif officerSrc then
        notify(officerSrc,'출석 요구 거절 처리 중 수배 자동 등록 실패: '..tostring(why),true)
    end
end)

RegisterNetEvent('cookie_police:server:requestAppearanceState',function()
    local src=source
    local _,pd=playerData(src)
    if not pd or not pd.citizenid then return end
    local cid=tostring(pd.citizenid)

    local accepted=MySQL.single.await([[
        SELECT a.*,UNIX_TIMESTAMP(a.deadline_at) AS deadline_ts
        FROM cookie_police_appearance_request a
        WHERE a.status='accepted' AND a.deadline_at>NOW()
          AND (a.target_citizenid=? OR a.officer_citizenid=?)
        ORDER BY a.id DESC LIMIT 1
    ]],{cid,cid})
    if accepted then appearanceHud(accepted,true) end

    local pending=MySQL.single.await([[
        SELECT * FROM cookie_police_appearance_request
        WHERE target_citizenid=? AND status='pending'
        ORDER BY id DESC LIMIT 1
    ]],{cid})
    if pending then
        TriggerClientEvent('cookie_police:client:appearanceRequest',src,{
            id=pending.id,targetName=pending.target_name,faction=pending.faction_name or '경찰/보안국',reason=pending.reason
        })
    end
end)

-- -------------------------------------------------------------------
-- Row actions
-- -------------------------------------------------------------------
lib.callback.register('cookie_police:mdtResultAction', function(source, action, payload)
    local src=source
    payload=type(payload)=='table' and payload or {}
    action=tostring(action or '')

    local officerOnly = action == 'warrant_close'
    local member, err = guard(src, officerOnly)
    if not member then return err end
    local actor=officerInfo(src,member)

    if CookieIntranetResultAction then
        local extra = CookieIntranetResultAction(src, action, payload, member, actor)
        if extra ~= nil then return extra end
    end

    if action=='identity_open' then
        local cid=cleanText(payload.citizenid,50)
        local p=identityProfile(cid)
        if not p then return {ok=false,message='시민 정보를 찾지 못했습니다.'} end
        return {
            ok=true,kind='profile',title='시민 상세 조회',
            profile=p,message='신원 상세 정보를 불러왔습니다.'
        }

    elseif action=='wanted_join' then
        local id=clampInt(payload.id,1,999999999,0)
        local row=MySQL.single.await([[
            SELECT id,kind,citizenid FROM cookie_police_wanted
            WHERE id=? AND active=1 AND expires_at>NOW() LIMIT 1
        ]],{id})
        if not row then return {ok=false,message='진행 중인 추격전을 찾지 못했습니다.'} end

        local joined=MySQL.scalar.await('SELECT COUNT(*) FROM cookie_police_wanted_unit WHERE wanted_id=? AND citizenid=?',{id,actor.citizenid}) or 0
        if tonumber(joined)>0 then return {ok=false,message='이미 이 추격전에 참여 중입니다.'} end

        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_police_wanted_unit(wanted_id,citizenid,officer_name)
            VALUES (?,?,?)
        ]],{id,actor.citizenid,actor.name})
        chaseViewByCitizenid[actor.citizenid]=id
        local chase=refreshChase(id,true)
        if chase then pushChase(src,chase,'officer') end
        audit(member,actor,'chase_join',row.citizenid,('#%d %s 참여'):format(id,row.kind=='escape' and '도주' or '수배'))
        return success(row.kind=='escape' and '도주 참여' or '수배 참여','추적에 참여했습니다. 상단에 남은 시간이 표시됩니다.')

    elseif action=='wanted_clear' then
        local id=clampInt(payload.id,1,999999999,0)
        local row=MySQL.single.await([[
            SELECT citizenid,kind,officer_citizenid,officer_name
            FROM cookie_police_wanted WHERE id=? AND active=1 LIMIT 1
        ]],{id})
        if not row then return {ok=false,message='활성 도주/수배를 찾지 못했습니다.'} end
        if tostring(row.officer_citizenid or '')~=tostring(actor.citizenid or '') then
            return {ok=false,message='최초 등록자만 이 도주/수배를 종료할 수 있습니다.'}
        end

        local endReason=cleanText(payload.endReason,160)
        if endReason=='' then return {ok=false,message='종료 사유를 선택하세요.'} end
        if not CHASE_END_PRESETS[endReason] and #endReason<2 then return {ok=false,message='종료 사유를 입력하세요.'} end

        local chase=activeChases[id] or refreshChase(id,true)
        hideChase(chase)
        MySQL.update.await([[
            UPDATE cookie_police_wanted
            SET active=0,cleared_at=NOW(),cleared_by=?,clear_reason=?
            WHERE id=? AND active=1
        ]],{actor.name,endReason,id})
        activeChases[id]=nil

        if chase then
            local label=row.kind=='escape' and '도주' or '수배'
            notifyChaseParticipants(chase,label..' 상황이 종료되었습니다. 사유: '..endReason,false)
        end
        audit(member,actor,'chase_end',row.citizenid,('#%d · %s'):format(id,endReason))
        return success('추격전 종료',(row.kind=='escape' and '도주' or '수배')..' 상황을 종료했습니다. · '..endReason)

    elseif action=='appearance_complete' or action=='appearance_cancel' or action=='appearance_wanted' then
        local id=clampInt(payload.id,1,999999999,0)
        local row=appearanceRow(id)
        if not row or not ({pending=true,accepted=true,overdue=true})[tostring(row.status)] then
            return {ok=false,message='진행 중인 출석 요구를 찾지 못했습니다.'}
        end
        if tostring(row.officer_citizenid or '')~=tostring(actor.citizenid or '') then
            return {ok=false,message='출석 요구를 보낸 담당자만 처리할 수 있습니다.'}
        end

        if action=='appearance_complete' then
            if row.status~='accepted' and row.status~='overdue' then return {ok=false,message='수락된 출석 요구만 완료할 수 있습니다.'} end
            MySQL.update.await("UPDATE cookie_police_appearance_request SET status='completed',completed_at=NOW() WHERE id=?",{id})
            appearanceHud(row,false)
            local targetSrc=sourceByCitizenid(row.target_citizenid)
            if targetSrc then notify(targetSrc,'출석 완료 처리되었습니다.',false) end
            audit(member,actor,'appearance_complete',row.target_citizenid,'#'..id)
            return success('출석 완료','출석 요구를 완료 처리했습니다.')
        elseif action=='appearance_cancel' then
            MySQL.update.await("UPDATE cookie_police_appearance_request SET status='cancelled',completed_at=NOW() WHERE id=?",{id})
            appearanceHud(row,false)
            local targetSrc=sourceByCitizenid(row.target_citizenid)
            if targetSrc then notify(targetSrc,'출석 요구가 취소되었습니다.',false) end
            audit(member,actor,'appearance_cancel',row.target_citizenid,'#'..id)
            return success('출석 요구 취소','출석 요구를 취소했습니다.')
        end

        if row.status~='overdue' then return {ok=false,message='출석 수락 후 10분이 지난 경우에만 수배를 수동 등록할 수 있습니다.'} end
        local targetRow=citizenRowByCitizenid(row.target_citizenid)
        if not targetRow then return {ok=false,message='대상 시민 정보를 찾지 못했습니다.'} end
        local targetSrc=sourceByCitizenid(row.target_citizenid)
        local okCreate,why,minutes=createChase(member,actor,targetRow,targetSrc,'wanted','출석 요구 미이행 · '..tostring(row.reason or ''),'APPEARANCE OVERDUE MANUAL')
        if not okCreate then return {ok=false,message=why} end
        MySQL.update.await("UPDATE cookie_police_appearance_request SET status='wanted',completed_at=NOW() WHERE id=?",{id})
        appearanceHud(row,false)
        return success('수배 등록',('출석 미이행으로 수배 %d분을 등록했습니다.'):format(minutes))

    elseif action=='warrant_close' then
        local id=clampInt(payload.id,1,999999999,0)
        local row=MySQL.single.await([[
            SELECT target_faction_name
            FROM cookie_police_warrant
            WHERE id=? AND faction_id=? AND active=1
        ]], {id,member.id})

        if not row then return {ok=false,message='활성 팩션/조직 영장을 찾지 못했습니다.'} end

        MySQL.update.await([[
            UPDATE cookie_police_warrant
            SET active=0,closed_at=NOW(),closed_by=?
            WHERE id=? AND faction_id=?
        ]], {actor.name,id,member.id})

        audit(
            member,actor,'warrant_close',nil,
            ('#%d · %s'):format(id,tostring(row.target_faction_name or '-'))
        )

        return success('영장 종료','팩션/조직 영장을 종료했습니다.')

    elseif action=='dispatch_join' then
        local id=clampInt(payload.id,1,999999999,0)
        local d=MySQL.single.await([[
            SELECT id FROM cookie_police_dispatch
            WHERE id=? AND active=1 AND (faction_id IS NULL OR faction_id=?)
        ]], {id,member.id})

        if not d then return {ok=false,message='활성 신고를 찾지 못했습니다.'} end

        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_police_dispatch_unit
              (dispatch_id,citizenid,officer_name)
            VALUES (?,?,?)
        ]], {id,actor.citizenid,actor.name})

        audit(member,actor,'dispatch_join',nil,'#'..id)
        return success('출동 참가','신고 #'..id..' 출동 인원으로 등록했습니다.')

    elseif action=='dispatch_close' then
        local id=clampInt(payload.id,1,999999999,0)
        local affected=MySQL.update.await([[
            UPDATE cookie_police_dispatch
            SET active=0,closed_by=?,closed_at=NOW()
            WHERE id=? AND active=1 AND (faction_id IS NULL OR faction_id=?)
        ]], {actor.name,id,member.id})

        if not affected or affected<1 then
            return {ok=false,message='활성 신고를 찾지 못했습니다.'}
        end

        audit(member,actor,'dispatch_close',nil,'#'..id)

        cookiePoliceLog('report_close','신고 종결','',{
            {name='신고',value='#'..tostring(id),inline=true},
            {name='처리 팩션',value=tostring(member.name or '-'),inline=true},
        },{actorSrc=src,actorLabel='종결자',eventKey='report_close'})

        return success('신고 종결','신고 #'..id..'을 종결했습니다.')

    elseif action=='case_close' then
        local id=clampInt(payload.id,1,999999999,0)
        local affected=MySQL.update.await([[
            UPDATE cookie_police_case
            SET status='closed'
            WHERE id=? AND faction_id=? AND status<>'closed'
        ]], {id,member.id})

        if not affected or affected<1 then
            return {ok=false,message='종결할 사건을 찾지 못했습니다.'}
        end

        audit(member,actor,'case_close',nil,'#'..id)
        return success('사건 종결','사건 #'..id..'을 종결했습니다.')
    end

    return {ok=false,message='지원하지 않는 처리입니다.'}
end)

-- F1 지원요청 -> MDT 신고/출동에도 기록
RegisterNetEvent('cookie_police:server:backup', function()
    local src=source
    local ok,member=hasAccess(src)
    if not ok then return end

    local actor=officerInfo(src,member)
    local ped=GetPlayerPed(src)
    if ped==0 then return end
    local c=GetEntityCoords(ped)

    local id=MySQL.insert.await([[
        INSERT INTO cookie_police_dispatch
          (faction_id,title,detail,priority,x,y,z,created_by)
        VALUES (?,?,?,?,?,?,?,?)
    ]], {
        member.id,'경찰 지원 요청',
        actor.label..' 경찰관의 현장 지원 요청',
        2,c.x,c.y,c.z,actor.name
    })

    if id then
        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_police_dispatch_unit
              (dispatch_id,citizenid,officer_name)
            VALUES (?,?,?)
        ]], {id,actor.citizenid,actor.name})
    end
end)

-- -------------------------------------------------------------------
-- Detention restore
-- -------------------------------------------------------------------
local function restoreDetention(src)
    local _,pd=playerData(src)
    if not pd or not pd.citizenid then return end

    local row=MySQL.single.await([[
        SELECT charge,
               GREATEST(0,UNIX_TIMESTAMP(release_at)-UNIX_TIMESTAMP()) AS remain
        FROM cookie_police_detention_active
        WHERE citizenid=? AND active=1 AND release_at>NOW()
        ORDER BY id DESC LIMIT 1
    ]], {pd.citizenid})

    if row and tonumber(row.remain)>0 then
        TriggerClientEvent(
            'cookie_police:client:setDetained',
            src,tonumber(row.remain),row.charge,true
        )
    end
end

RegisterNetEvent('cookie_police:server:requestDetentionState', function()
    restoreDetention(source)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src=source
    CreateThread(function()
        Wait(1800)
        restoreDetention(src)
    end)
end)

CreateThread(function()
    while true do
        Wait(5000)

        local expired=MySQL.query.await([[
            SELECT id,citizenid
            FROM cookie_police_detention_active
            WHERE active=1 AND release_at<=NOW()
            LIMIT 100
        ]]) or {}

        for _,r in ipairs(expired) do
            MySQL.update.await([[
                UPDATE cookie_police_detention_active
                SET active=0,released_at=NOW(),released_by='TIME'
                WHERE id=? AND active=1
            ]], {r.id})

            local src=sourceByCitizenid(r.citizenid)
            if src then
                TriggerClientEvent(
                    'cookie_police:client:setDetained',
                    src,0,'형기 종료',false
                )
                notify(src,'구금 시간이 종료되어 석방되었습니다.',false)
            end
        end
    end
end)

exports('CreateDispatch', function(data)
    data=type(data)=='table' and data or {}
    local factionId=tonumber(data.factionId)
    local title=cleanText(data.title or '신고 접수',100)
    local detail=cleanText(data.detail,500)
    local priority=clampInt(data.priority,1,3,1)
    local c=data.coords or {}

    return MySQL.insert.await([[
        INSERT INTO cookie_police_dispatch
          (faction_id,title,detail,priority,x,y,z,created_by)
        VALUES (?,?,?,?,?,?,?,?)
    ]], {
        factionId,title,detail,priority,
        tonumber(c.x),tonumber(c.y),tonumber(c.z),
        cleanText(data.createdBy or 'SYSTEM',80)
    })
end)
