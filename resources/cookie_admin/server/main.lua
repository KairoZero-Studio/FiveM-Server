print('^2[COOKIE ADMIN]^7 build 20260827-2124 loaded')
print('^2[cookie_admin] LABOR+DELIVERY V2 server loaded^7')
local function getLicense(src)

local function cookieAdminLog(category, title, description, fields, options)
    if GetResourceState('cookie_logs') ~= 'started' then return end
    pcall(function()
        exports.cookie_logs:Log(category, title, description, fields or {}, options or {})
    end)
end


    local license = GetPlayerIdentifierByType(src, 'license2')
    if not license then
        license = GetPlayerIdentifierByType(src, 'license')
    end
    return license
end

CreateThread(function()
    MySQL.update.await("UPDATE cookie_admin_feature SET label = '소환하기' WHERE feature_key = 'goto'", {})

    -- 2026-08-25 관리자 플레이어/차량 관리 정리
    -- 기존 DB에 남아있는 '부상 치료'는 F3에서 완전히 제거하고, 차량 관리 명칭을 간단히 통일한다.
    pcall(function()
        MySQL.update.await("DELETE FROM cookie_admin_feature WHERE feature_key = 'cure_wound'", {})
        MySQL.update.await([[
            UPDATE cookie_admin_feature
            SET label = CASE feature_key
                WHEN 'veh_spawn' THEN '스폰'
                WHEN 'veh_del'   THEN '삭제'
                WHEN 'veh_fix'   THEN '수리'
                WHEN 'veh_give'  THEN '차량 지급'
                ELSE label
            END
            WHERE feature_key IN ('veh_spawn','veh_del','veh_fix','veh_give')
        ]], {})
    end)

    MySQL.query.await([[
        INSERT INTO cookie_admin_feature
          (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
        VALUES
          ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'melt', '녹임', 1, 0, 1, 12)
        ON DUPLICATE KEY UPDATE label = VALUES(label)
    ]], {})

    -- LV1 뉴비가이드: 이동/소환/위치 확인/끌고가기만 허용. 기존 LV1 기능은 LV2로 승격.
    MySQL.update.await("UPDATE cookie_admin_feature SET min_level=2 WHERE min_level=1 AND feature_key NOT IN ('tp','goto','location_check','drag')", {})
    MySQL.query.await([[
        INSERT INTO cookie_admin_feature
          (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
        VALUES
          ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'location_check', '위치 확인', 1, 0, 1, 3),
          ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'drag', '끌고가기', 1, 0, 1, 4)
        ON DUPLICATE KEY UPDATE label=VALUES(label), min_level=VALUES(min_level), sort_order=VALUES(sort_order)
    ]], {})
    MySQL.update.await("UPDATE cookie_admin_feature SET min_level=1 WHERE feature_key IN ('tp','goto','location_check','drag')", {})

end)


-- ============================================================
-- COOKIE ITEM CONFISCATION V14.2.8
-- 지급 관리 > 아이템 압수 (LV3+)
-- ============================================================
CreateThread(function()
    MySQL.query.await([[
        INSERT INTO cookie_admin_category (category_key, label, tab_min_level, sort_order)
        VALUES ('grant', '지급 관리', 3, 3)
        ON DUPLICATE KEY UPDATE label=VALUES(label), tab_min_level=VALUES(tab_min_level), sort_order=VALUES(sort_order)
    ]], {})
    MySQL.query.await([[
        INSERT INTO cookie_admin_feature
          (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
        VALUES
          ((SELECT id FROM cookie_admin_category WHERE category_key='grant' LIMIT 1),
           'confiscate_item', '아이템 압수', 3, 1, 1, 4)
        ON DUPLICATE KEY UPDATE
          category_id=VALUES(category_id), label=VALUES(label), min_level=VALUES(min_level),
          danger_level=VALUES(danger_level), requires_target=VALUES(requires_target), sort_order=VALUES(sort_order)
    ]], {})
end)

CreateThread(function()
    MySQL.query.await("ALTER TABLE `cookie_admin` ADD COLUMN IF NOT EXISTS `admin_team` VARCHAR(32) NULL AFTER `admin_level`", {})
    MySQL.query.await("ALTER TABLE `cookie_admin_category` ADD COLUMN IF NOT EXISTS `team_key` VARCHAR(32) NOT NULL DEFAULT 'general' AFTER `tab_min_level`", {})

end)

CreateThread(function()
    MySQL.query.await([[
        INSERT INTO cookie_admin_feature
          (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
        VALUES
          ((SELECT id FROM cookie_admin_category WHERE category_key='onboarding'),
           'admin_alias', '관리자 별명 변경', 4, 0, 1, 20)
        ON DUPLICATE KEY UPDATE label = VALUES(label), min_level = VALUES(min_level)
    ]], {})

end)

CreateThread(function()
    MySQL.query.await([[
        INSERT INTO cookie_admin_feature
          (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
        VALUES
          ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'jobless', '무직처리', 1, 0, 1, 14)
        ON DUPLICATE KEY UPDATE label = VALUES(label)
    ]], {})

    -- 접속 중인 플레이어 > 플레이어 관리 > 운전면허
    MySQL.query.await([[
        INSERT INTO cookie_admin_feature
          (category_id, feature_key, label, min_level, danger_level, requires_target, sort_order)
        VALUES
          ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'license_suspend', '운전면허 정지', 1, 0, 1, 15),
          ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'license_restore', '운전면허 정지 해제', 1, 0, 1, 16)
        ON DUPLICATE KEY UPDATE
          category_id=VALUES(category_id),
          label=VALUES(label),
          min_level=VALUES(min_level),
          sort_order=VALUES(sort_order)
    ]], {})

end)

-- 2026-08-25 관리자 킥/밴 연동
-- 밴은 cookie_admin 자체 DB에 저장하며, cookie_admin 리소스만 교체해도 동작하도록 테이블을 자동 생성한다.
CreateThread(function()
    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_admin_ban` (
              `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
              `identifier`    VARCHAR(80)  NOT NULL,
              `target_gobun`  INT          NULL,
              `target_cid`    VARCHAR(64)  NULL,
              `target_name`   VARCHAR(80)  NULL,
              `reason`        VARCHAR(300) NOT NULL,
              `admin_name`    VARCHAR(60)  NULL,
              `admin_license` VARCHAR(80)  NULL,
              `expires_at`    DATETIME     NULL,
              `revoked_at`    DATETIME     NULL,
              `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (`id`),
              KEY `idx_ban_identifier` (`identifier`),
              KEY `idx_ban_active` (`identifier`,`revoked_at`,`expires_at`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_admin_punishment_log` (
              `id`             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
              `action`         VARCHAR(16)  NOT NULL,
              `admin_name`     VARCHAR(60)  NULL,
              `admin_license`  VARCHAR(80)  NULL,
              `admin_level`    INT          NULL,
              `target_server`  INT          NULL,
              `target_gobun`   INT          NULL,
              `target_cid`     VARCHAR(64)  NULL,
              `target_name`    VARCHAR(80)  NULL,
              `target_license` VARCHAR(80)  NULL,
              `reason`         VARCHAR(300) NULL,
              `minutes`        INT          NULL,
              `created_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (`id`),
              KEY `idx_punish_action` (`action`),
              KEY `idx_punish_target` (`target_gobun`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})
    end)
end)

local function trimText(value, maxLen)
    local text = type(value) == 'string' and value:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if maxLen and #text > maxLen then text = text:sub(1, maxLen) end
    return text
end

local function targetPunishInfo(target)
    local info = {
        serverId = target,
        license = getLicense(target),
        gobun = nil,
        citizenid = nil,
        name = GetPlayerName(target) or ('#' .. tostring(target)),
    }

    local player = exports.qbx_core:GetPlayer(target)
    if player and player.PlayerData then
        info.citizenid = player.PlayerData.citizenid
    end

    local okHead, head = pcall(function() return exports.cookie_core:getHeadInfo(target) end)
    if okHead and type(head) == 'table' then
        info.gobun = tonumber(head.gobun)
        if type(head.nick) == 'string' and head.nick ~= '' then info.name = head.nick end
    else
        local okNick, nick = pcall(function() return exports.cookie_core:getNickname(target) end)
        if okNick and type(nick) == 'string' and nick ~= '' then info.name = nick end
    end

    return info
end

local function punishmentExpiryText(minutes)
    minutes = math.floor(tonumber(minutes) or 0)
    if minutes <= 0 then return '영구' end
    if minutes % 1440 == 0 then
        return ('%d일'):format(math.floor(minutes / 1440))
    end
    if minutes % 60 == 0 then
        return ('%d시간'):format(math.floor(minutes / 60))
    end
    return ('%d분'):format(minutes)
end

-- 접속 단계에서 활성 밴을 검사한다.
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    local src = source
    local identifier = getLicense(src)
    if not identifier then return end

    deferrals.defer()
    Wait(0)

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT id, reason, admin_name, expires_at
            FROM cookie_admin_ban
            WHERE identifier = ?
              AND revoked_at IS NULL
              AND (expires_at IS NULL OR expires_at > NOW())
            ORDER BY id DESC
            LIMIT 1
        ]], { identifier })
    end)

    if not ok then
        deferrals.done()
        return
    end

    if row then
        local untilText = row.expires_at and tostring(row.expires_at) or '영구'
        deferrals.done(([[쿠키서버 이용이 제한되어 있습니다.
사유: %s
해제: %s
처리 관리자: %s]]):format(
            tostring(row.reason or '사유 없음'),
            untilText,
            tostring(row.admin_name or '관리자')
        ))
        return
    end

    deferrals.done()
end)

local getState

-- 관리자 역할/출근/대상 보호 규칙 (2026-09-25)
local function adminRowBySource(src)
    local lic = getLicense(src)
    if not lic then return nil end
    return MySQL.single.await(
        'SELECT id, admin_name, admin_level, admin_team, is_dev, total_minute, duty_minute, license FROM cookie_admin WHERE license = ? AND is_active = 1',
        { lic }
    )
end

function CookieCanUseAdminPower(src, admin)
    admin = admin or adminRowBySource(src)
    if not admin then return false, '관리자 권한이 없습니다' end
    local lv = tonumber(admin.admin_level) or 0
    if lv <= 3 and getState(src) ~= 'duty' then
        return false, 'LV1~LV3은 관리자 출근 중에만 권한을 사용할 수 있습니다'
    end
    return true
end

function CookieCanTargetAdmin(actorSrc, targetSrc)
    actorSrc, targetSrc = tonumber(actorSrc), tonumber(targetSrc)
    if not actorSrc or not targetSrc then return true end
    local actor = adminRowBySource(actorSrc)
    local target = adminRowBySource(targetSrc)
    if not actor or not target then return true end
    if (tonumber(target.admin_level) or 0) > (tonumber(actor.admin_level) or 0) then
        return false, ('자신보다 높은 LV%d 관리자는 대상으로 지정할 수 없습니다'):format(tonumber(target.admin_level) or 0)
    end
    return true
end

local function fetchAdmin(license)
    return MySQL.single.await(
        'SELECT id, admin_name, admin_level, admin_team, is_dev, total_minute, duty_minute, license FROM cookie_admin WHERE license = ? AND is_active = 1',
        { license }
    )
end

local function getEffectiveLevel(license)
    if not license then return 0, 0, false end
    local row = MySQL.single.await(
        'SELECT admin_level, (pw_hash IS NOT NULL) AS has_pw FROM cookie_admin WHERE license = ? AND is_active = 1',
        { license }
    )
    if not row then return 0, 0, false end
    local qualified = row.admin_level

    local hasPw = (row.has_pw == 1 or row.has_pw == true)
    local effective = qualified
    if qualified >= 5 and not hasPw then
        effective = 4
    end

    return effective, qualified, hasPw
end

local function fetchAdminLevelMap()
    local map = {}
    local rows = MySQL.query.await('SELECT license, admin_level FROM cookie_admin WHERE is_active = 1', {})
    if rows then
        for _, r in ipairs(rows) do map[r.license] = r.admin_level end
    end
    return map
end

local function buildPlayerList()
    local list = {}
    local levelMap = fetchAdminLevelMap()
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = exports.qbx_core:GetPlayer(src)

        local account = GetPlayerName(src) or ('#' .. tostring(src))
        local realname = nil
        if player and player.PlayerData and player.PlayerData.charinfo then
            local ci = player.PlayerData.charinfo
            local full = (ci.firstname or '') .. ' ' .. (ci.lastname or '')
            full = (full:gsub('^%s+', ''):gsub('%s+$', ''))
            if full ~= '' then realname = full end
        end

        local nickname
        local okNick, res = pcall(function() return exports.cookie_core:getNickname(src) end)
        if okNick then nickname = res end
        local onboarded = nickname ~= nil and nickname ~= ''
        list[#list + 1] = {
            serverId = src,
            name = (onboarded and nickname) or realname or account,
            nickname = onboarded and nickname or nil,
            realname = realname,
            onboarded = onboarded,
            citizenid = player and player.PlayerData and player.PlayerData.citizenid or nil,

            adminLevel = (function()
                local lic = getLicense(src)
                return (lic and levelMap[lic]) or 0
            end)(),

            driverLicense = (function()
                if GetResourceState('cookie_license')~='started' then return nil end
                local ok,row=pcall(function()
                    return exports.cookie_license:GetBySource(src)
                end)
                return ok and row or nil
            end)(),
        }
    end
    return list
end

local function getCharName(src)
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.charinfo then
        local ci = player.PlayerData.charinfo
        return ('%s %s'):format(ci.firstname or '', ci.lastname or '')
    end
    return GetPlayerName(src) or '대상'
end

local function fetchFeatures(adminLevel, adminTeam)
    local categories = MySQL.query.await(
        'SELECT id, category_key, label, sort_order, team_key FROM cookie_admin_category WHERE tab_min_level <= ? ORDER BY sort_order',
        { adminLevel }
    )
    local features = MySQL.query.await(
        'SELECT category_id, feature_key, label, min_level, danger_level, requires_target, sort_order FROM cookie_admin_feature WHERE min_level <= ? ORDER BY sort_order',
        { adminLevel }
    )

    local result = {}
    for _, cat in ipairs(categories or {}) do
        local teamKey = cat.team_key or 'general'
        local teamOk = (teamKey == 'general') or (adminLevel >= 4) or (adminLevel >= 2 and adminTeam ~= nil and adminTeam == teamKey)
        if teamOk then
            local catFeatures = {}
            for _, f in ipairs(features or {}) do
                if f.category_id == cat.id then
                    catFeatures[#catFeatures + 1] = {
                        key = f.feature_key,
                        label = f.label,
                        dangerLevel = f.danger_level,
                        requiresTarget = f.requires_target == 1,
                    }
                end
            end
            if #catFeatures > 0 then
                result[#result + 1] = {
                    key = cat.category_key,
                    label = cat.label,
                    features = catFeatures,
                }
            end
        end
    end
    return result
end

local function canAccessTeam(adminLevel, adminTeam, teamKey)
    if not teamKey or teamKey == 'general' then return true end
    if adminLevel >= 4 then return true end
    return adminLevel >= 2 and adminTeam ~= nil and adminTeam == teamKey
end

function CookieAdminTeamAuth(src, teamKey)
    local license = getLicense(src)
    if not license then return nil end
    local admin = fetchAdmin(license)
    if not admin then return nil end
    if not canAccessTeam(admin.admin_level, admin.admin_team, teamKey) then return nil end
    return admin
end

local function normalizeTeam(level, team)
    if level ~= 2 and level ~= 3 then return nil end
    if type(team) ~= 'string' or team == '' then return nil end
    for _, t in ipairs(Config.AdminTeams or {}) do
        if t.key == team then return team end
    end
    return nil
end

local function teamLabelOf(team)
    if not team then return nil end
    for _, t in ipairs(Config.AdminTeams or {}) do
        if t.key == team then return t.label end
    end
    return team
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await(
            "ALTER TABLE cookie_skin MODIFY COLUMN skin_type VARCHAR(16) NOT NULL DEFAULT 'rp'")
    end)
    if not ok then

        return
    end

    local moved = MySQL.update.await(
        "UPDATE cookie_skin SET skin_type = 'admin' WHERE skin_type = 'public'"
    ) or 0
    if moved > 0 then

    end
end)

local function fetchSkins(adminId)

    local rp = MySQL.query.await([[
        SELECT skin_key, label, model_name, emoji, image
        FROM cookie_skin WHERE skin_type = 'rp'
        ORDER BY sort_order
    ]]) or {}

    local admin, private = {}, {}

    if adminId and adminId > 0 then

        admin = MySQL.query.await([[
            SELECT skin_key, label, model_name, emoji, image
            FROM cookie_skin WHERE skin_type = 'admin'
            ORDER BY sort_order
        ]]) or {}

        private = MySQL.query.await([[
            SELECT s.skin_key, s.label, s.model_name, s.emoji, s.image
            FROM cookie_admin_skin a
            JOIN cookie_skin s ON a.skin_id = s.id
            WHERE a.admin_id = ?
            ORDER BY s.sort_order
        ]], { adminId }) or {}
    end

    return { rp = rp, admin = admin, private = private }
end

local adminState = {}

getState = function(src)
    return adminState[src] or 'rp'
end

local function setState(src, state)
    adminState[src] = state

    if CookieRefreshNameTag then pcall(CookieRefreshNameTag, src) end
end

exports('getState', function(src)
    return getState(src)
end)

function CookieGetAdminState(src)
    return getState(src)
end

local function buildUserPane(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    local pd = player.PlayerData
    local ci = pd.charinfo or {}
    local money = pd.money or {}
    local license = getLicense(src)

    local u = license and MySQL.single.await(
        'SELECT gobun, nickname FROM cookie_user WHERE license = ?', { license }) or nil

    local rpMin, jobMin = 0, 0
    if license then
        local ok, t = pcall(function()
            return MySQL.single.await(
                'SELECT rp_minute, job_minute FROM cookie_user WHERE license = ?', { license })
        end)
        if ok and t then
            rpMin = t.rp_minute or 0
            jobMin = t.job_minute or 0
        end
    end

    return {
        nickname = (u and u.nickname ~= '' and u.nickname) or nil,
        gobun = u and u.gobun or nil,
        cash = money.cash or 0,
        bank = money.bank or 0,
        rpMinute = rpMin,
        jobMinute = jobMin,

        jobDisplay = (function()
            if not CookieJobDisplay then return nil end
            local ok, txt = pcall(CookieJobDisplay, src)
            return ok and txt or nil
        end)(),
    }
end


-- ============================================================
-- 시민직 중앙 레벨 시스템 V2
-- 경험치는 기존 cookie_skill에 그대로 누적되지만,
-- 실제 해금 레벨은 cookie_job_level_progress에서 관리한다.
-- 다음 레벨은 요구 경험치 + 승급 아이템 조건을 만족한 뒤
-- F3 > 내정보 > 직업 레벨에서 직접 승급해야 열린다.
-- ============================================================
local JOB_LEVEL_DEFAULT_MAX = 5
local JOB_LEVEL_DEFAULT_REQ = {
    -- 현재 ox_inventory 기준에는 job_level_ticket이 없으므로 기본 승급은 EXP만 사용한다.
    -- 관리자가 F3에서 실제 존재하는 ox_inventory 아이템을 지정하면 추가 조건으로 사용할 수 있다.
    [2] = { exp = 50,  item = '', count = 0 },
    [3] = { exp = 150, item = '', count = 0 },
    [4] = { exp = 300, item = '', count = 0 },
    [5] = { exp = 500, item = '', count = 0 },
}

local function civilJobKeys()
    local rows = {}
    for key, def in pairs(Config.CivilJobs or {}) do
        rows[#rows + 1] = {
            key = key,
            label = def.label or key,
            emoji = def.emoji or '💼',
            skill = def.skill or key,
        }
    end
    table.sort(rows, function(a,b)
        return tostring(a.label) < tostring(b.label)
    end)
    return rows
end

local function f3ActivityLevelKeys()
    local rows = {}
    for key, def in pairs(Config.F3JobLevelActivities or {}) do
        rows[#rows + 1] = {
            key = key,
            label = def.label or key,
            emoji = def.emoji or '⭐',
            skill = def.skill or key,
            statLabel = def.statLabel or '완료',
        }
    end
    table.sort(rows, function(a,b)
        return tostring(a.label) < tostring(b.label)
    end)
    return rows
end

local function playerCitizenIdForJobLevel(src)
    local p = exports.qbx_core:GetPlayer(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function activityTotalJob(src, key)
    local cid = playerCitizenIdForJobLevel(src)
    if not cid then return 0 end

    if key == 'fishing' then
        local row = MySQL.single.await(
            'SELECT COALESCE(SUM(caught_count),0) AS total FROM cookie_fishing_collection WHERE citizenid=?',
            { cid }
        )
        return math.max(0, tonumber(row and row.total) or 0)
    elseif key == 'mining' then
        local row = MySQL.single.await(
            'SELECT COALESCE(SUM(mined_count),0) AS total FROM cookie_mining_collection WHERE citizenid=?',
            { cid }
        )
        return math.max(0, tonumber(row and row.total) or 0)
    end

    return 0
end

local function ensureJobLevelTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_job_level_config (
            job_key VARCHAR(64) NOT NULL PRIMARY KEY,
            max_level INT NOT NULL DEFAULT 5,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_job_level_requirement (
            job_key VARCHAR(64) NOT NULL,
            target_level INT NOT NULL,
            required_exp BIGINT NOT NULL DEFAULT 0,
            item_name VARCHAR(80) NOT NULL DEFAULT '',
            item_count INT NOT NULL DEFAULT 0,
            PRIMARY KEY(job_key,target_level)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_job_level_progress (
            citizenid VARCHAR(64) NOT NULL,
            job_key VARCHAR(64) NOT NULL,
            unlocked_level INT NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid,job_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, j in ipairs(civilJobKeys()) do
        MySQL.insert.await(
            'INSERT IGNORE INTO cookie_job_level_config(job_key,max_level) VALUES(?,?)',
            { j.key, JOB_LEVEL_DEFAULT_MAX }
        )
        for lv = 2, JOB_LEVEL_DEFAULT_MAX do
            local req = JOB_LEVEL_DEFAULT_REQ[lv] or {
                exp = (lv - 1) * 100,
                item = '',
                count = 0
            }
            MySQL.insert.await([[
                INSERT IGNORE INTO cookie_job_level_requirement
                    (job_key,target_level,required_exp,item_name,item_count)
                VALUES(?,?,?,?,?)
            ]], { j.key, lv, req.exp, req.item, req.count })
        end
    end

    -- V11 이전에 자동 생성된 존재하지 않는 기본 승급권 조건을 안전하게 정리한다.
    -- 실제 ox_inventory에 job_level_ticket이 추가되어 있다면 기존 설정은 유지한다.
    local hasLegacyTicket = false
    pcall(function()
        hasLegacyTicket = exports.ox_inventory:Items('job_level_ticket') ~= nil
    end)
    if not hasLegacyTicket then
        MySQL.update.await([[
            UPDATE cookie_job_level_requirement
            SET item_name='', item_count=0
            WHERE item_name='job_level_ticket'
        ]])
    end
end

CreateThread(function()
    Wait(1200)
    local ok, err = pcall(ensureJobLevelTables)
    if not ok then
        print(('^1[cookie_admin] job level table init failed: %s^7'):format(tostring(err)))
    end
end)

local function jobConfig(jobKey)
    local row = MySQL.single.await(
        'SELECT max_level FROM cookie_job_level_config WHERE job_key=?',
        { jobKey }
    )
    return {
        maxLevel = math.max(1, tonumber(row and row.max_level) or JOB_LEVEL_DEFAULT_MAX)
    }
end

local function jobRequirement(jobKey, targetLevel)
    if not targetLevel then return nil end
    local row = MySQL.single.await([[
        SELECT required_exp,item_name,item_count
        FROM cookie_job_level_requirement
        WHERE job_key=? AND target_level=?
    ]], { jobKey, targetLevel })
    if not row then return nil end
    return {
        targetLevel = targetLevel,
        requiredExp = math.max(0, tonumber(row.required_exp) or 0),
        itemName = tostring(row.item_name or ''),
        itemCount = math.max(0, tonumber(row.item_count) or 0),
    }
end

local function skillExp(src, skillKey)
    local row = {}
    pcall(function() row = exports.cookie_skill:get(src, skillKey) or {} end)
    return tonumber(row.exp or row.total or 0) or 0, row
end

local function centralJobLevel(src, jobKey)
    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData then return 1 end
    local cid = p.PlayerData.citizenid
    if not cid then return 1 end

    local cfg = jobConfig(jobKey)
    MySQL.insert.await(
        'INSERT IGNORE INTO cookie_job_level_progress(citizenid,job_key,unlocked_level) VALUES(?,?,1)',
        { cid, jobKey }
    )
    local row = MySQL.single.await(
        'SELECT unlocked_level FROM cookie_job_level_progress WHERE citizenid=? AND job_key=?',
        { cid, jobKey }
    )
    return math.max(1, math.min(cfg.maxLevel, tonumber(row and row.unlocked_level) or 1))
end

-- 다른 시민직 리소스가 사용할 중앙 레벨 export.
exports('getCivilLevel', function(src, jobOrSkill)
    local key = tostring(jobOrSkill or '')
    if (Config.CivilJobs or {})[key] then
        return centralJobLevel(src, key)
    end
    for jobKey, def in pairs(Config.CivilJobs or {}) do
        if def.skill == key then return centralJobLevel(src, jobKey) end
    end
    return 1
end)

local function buildJobLevelAdminConfig()
    local jobs = {}
    for _, j in ipairs(civilJobKeys()) do
        local cfg = jobConfig(j.key)
        local requirements = {}
        for lv = 2, cfg.maxLevel do
            local req = jobRequirement(j.key, lv) or {
                targetLevel = lv, requiredExp = 0, itemName = '', itemCount = 0
            }
            requirements[#requirements + 1] = req
        end
        jobs[#jobs + 1] = {
            key = j.key,
            label = j.label,
            emoji = j.emoji,
            skill = j.skill,
            maxLevel = cfg.maxLevel,
            requirements = requirements,
        }
    end
    return { jobs = jobs }
end

local function buildJobLevels(src)
    local out = {}

    -- 실제 시민직: 기존 중앙 승급 시스템 그대로 사용.
    -- Config.CivilJobs에 새 시민직을 추가하면 F3 목록에도 자동으로 나타납니다.
    for _, j in ipairs(civilJobKeys()) do
        local exp, row = skillExp(src, j.skill)
        local level = centralJobLevel(src, j.key)
        local cfg = jobConfig(j.key)
        local req = level < cfg.maxLevel and jobRequirement(j.key, level + 1) or nil

        out[#out + 1] = {
            key = j.key,
            label = j.label,
            emoji = j.emoji,
            skill = j.skill,
            level = level,
            maxLevel = cfg.maxLevel,
            exp = exp,
            autoLevel = false,

            -- 기존 UI 호환용
            levelExp = 0,
            nextExp = req and req.requiredExp or 0,

            requiredExp = req and req.requiredExp or 0,
            requiredItem = req and req.itemName or '',
            requiredItemCount = req and req.itemCount or 0,
            canLevel = req and exp >= req.requiredExp or false,

            totalJob = tonumber(row.total_job or row.deliveries or 0) or 0,
            totalPay = tonumber(row.total_pay or 0) or 0,
            statLabel = '완료',
        }
    end

    -- 낚시/광질: 고용 직업이 아니라 실제 활동 숙련도(cookie_skill)를 그대로 표시.
    for _, j in ipairs(f3ActivityLevelKeys()) do
        local exp, row = skillExp(src, j.skill)
        local totalJob = activityTotalJob(src, j.key)

        -- V13.4 이전 광질 기록도 잃지 않도록 기존 채굴 횟수만큼 최초 1회 EXP를 보정.
        -- 이후에는 cookie_mining이 성공 채굴마다 1 EXP씩 직접 누적합니다.
        if j.key == 'mining' and totalJob > exp then
            pcall(function()
                exports.cookie_skill:addExp(src, j.skill, math.floor(totalJob - exp))
            end)
            exp, row = skillExp(src, j.skill)
        end

        local level = math.max(1, tonumber(row.level) or 1)
        local maxLevel = math.max(1, tonumber(row.maxLevel) or 5)
        local nextExp = tonumber(row.nextExp) or 0
        local levelExp = tonumber(row.levelExp) or 0

        out[#out + 1] = {
            key = j.key,
            label = j.label,
            emoji = j.emoji,
            skill = j.skill,
            level = level,
            maxLevel = maxLevel,
            exp = exp,
            autoLevel = true,
            levelExp = levelExp,
            nextExp = nextExp,
            requiredExp = nextExp,
            requiredItem = '',
            requiredItemCount = 0,
            canLevel = false,
            totalJob = totalJob,
            totalPay = 0,
            statLabel = j.statLabel,
        }
    end

    return out
end

local function buildJobPane(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    local job = player.PlayerData.job
    if not job then return nil end
    local grade = job.grade or {}

    local pane = {
        name = job.label or job.name or '무직',
        jobKey = job.name,
        grade = grade.name or '-',
        gradeLevel = grade.level or 0,
        onDuty = (job.onduty == true),
        salary = job.payment or grade.payment or 0,
    }

    local def = CookieCivilJobOf(src)
    if def then
        pane.isCivil    = true
        pane.employ     = '위촉직'
        pane.skillLabel = def.label
        pane.skillLevel = CookieCivilLevel(src, def.skill)
    end

    return pane
end

local function attachShell(payload, src, isAdmin)
    local tabs = {}
    if isAdmin then
        payload.isAdmin = true
        tabs[#tabs + 1] = { key = 'admin', label = '관리자' }
    end
    payload.user = buildUserPane(src)
    tabs[#tabs + 1] = { key = 'user', label = '내정보' }

    if not payload.skins then
        local ok, s = pcall(fetchSkins, 0)
        payload.skins = (ok and s) or { public = {}, private = {} }
    end

    if CookieBuildFactionPane then
        local ok, fpane = pcall(CookieBuildFactionPane, src)
        if ok and fpane then
            payload.faction = fpane
        elseif not ok then

        end
    end

    payload.job = buildJobPane(src)
    payload.jobLevels = buildJobLevels(src)
    payload.personalStorage = CookieBuildPersonalStorage and CookieBuildPersonalStorage(src) or {
        vehicle={}, cosmetic={}, chair={}, skin={}, summary={vehicle=0,cosmetic=0,chair=0,skin=0}
    }
    payload.tabs = tabs
    return payload
end

local function buildShellBase(src)
    return attachShell({}, src, false)
end

RegisterNetEvent('cookie_admin:server:requestOpen', function()
    local src = source
    local license = getLicense(src)

    if not license then

        return
    end

    local admin = fetchAdmin(license)
    if not admin then

        TriggerClientEvent('cookie_admin:client:openPanel', src, buildShellBase(src))
        return
    end

    local effectiveLevel, _, hasPw = getEffectiveLevel(license)

    local features = fetchFeatures(admin.admin_level, admin.admin_team)

    if admin.admin_level >= Config.WeaponGiveMinLevel then
        local wcats = {}
        for _, cat in ipairs(Config.Weapons) do
            wcats[#wcats + 1] = { key = 'wcat:' .. cat.key, label = cat.label, dangerLevel = 1, requiresTarget = true }
        end
        features[#features + 1] = { key = 'weapon_mgmt', label = '무기 관리', features = wcats }
    end

    local payload = {
        me = {
            name = admin.admin_name,
            level = admin.admin_level,
            effectiveLevel = effectiveLevel,
            team = admin.admin_team,

            totalMinute = admin.total_minute,
            dutyMinute = admin.duty_minute,
            state = getState(src),
            hasPw = hasPw,
            isDev = (admin.is_dev == true or admin.is_dev == 1),

        },
        players = buildPlayerList(),
        features = features,
        adminTeams = Config.AdminTeams,
        skins = fetchSkins(admin.id),
        weapons = (admin.admin_level >= Config.WeaponGiveMinLevel) and Config.Weapons or nil,

        vehicleCatalog = CookieBuildVehCatalog(),
        vehicleBrandOrder = CookieVehOrder,
        vehicleMajorOrder = CookieMajorOrder,
        vehiclePerms = {
            spawn = admin.admin_level >= Config.VehicleSpawnMinLevel,
            exhibit = admin.admin_level >= Config.VehicleExhibitMinLevel,
        },

        factionPerms = {
            manage = canAccessTeam(admin.admin_level, admin.admin_team, 'faction'),
        },
        factionTypes = Config.FactionTypes,

        logPerms = { view = admin.admin_level >= 4 },

        npcPerms = { edit = admin.admin_level >= (Config.NpcEditMinLevel or 3) },
        systemPerms = { manage = effectiveLevel >= 5 },

        factions = (function()
            if not canAccessTeam(admin.admin_level, admin.admin_team, 'faction') then return nil end
            local ok, rows = pcall(function()
                return MySQL.query.await(
                    'SELECT id, name, garage_key FROM cookie_faction WHERE is_active = 1 ORDER BY id', {})
            end)
            rows = (ok and rows) or {}
            for _, fr in ipairs(rows) do
                local okS, sh = pcall(function()
                    return MySQL.query.await(
                        'SELECT id, model, label, price, min_grade, active FROM cookie_faction_shop WHERE faction_id = ?',
                        { fr.id })
                end)
                fr.shop = (okS and sh) or {}
            end
            return rows
        end)(),
    }

    attachShell(payload, src, true)

    TriggerClientEvent('cookie_admin:client:openPanel', src, payload)
end)


RegisterNetEvent('cookie_admin:server:jobLevelUp', function(jobKey)
    local src = source
    jobKey = tostring(jobKey or '')
    local def = (Config.CivilJobs or {})[jobKey]
    if not def then return end

    local p = exports.qbx_core:GetPlayer(src)
    if not p or not p.PlayerData or not p.PlayerData.citizenid then return end
    local cid = p.PlayerData.citizenid

    local current = centralJobLevel(src, jobKey)
    local cfg = jobConfig(jobKey)
    if current >= cfg.maxLevel then
        return TriggerClientEvent('cookie_admin:client:notify',src,'이미 최대 레벨입니다.',true)
    end

    local target = current + 1
    local req = jobRequirement(jobKey, target)
    if not req then
        return TriggerClientEvent('cookie_admin:client:notify',src,'승급 조건이 설정되지 않았습니다.',true)
    end

    local exp = skillExp(src, def.skill)
    if exp < req.requiredExp then
        return TriggerClientEvent('cookie_admin:client:notify',src,
            ('경험치가 부족합니다. %s / %s'):format(exp,req.requiredExp),true)
    end

    if req.itemName ~= '' and req.itemCount > 0 then
        local okCount, count = pcall(function()
            return exports.ox_inventory:Search(src,'count',req.itemName)
        end)
        count = okCount and tonumber(count) or 0
        if count < req.itemCount then
            return TriggerClientEvent('cookie_admin:client:notify',src,
                ('승급 아이템이 부족합니다. %s x%d 필요'):format(req.itemName,req.itemCount),true)
        end

        local removed = false
        pcall(function()
            removed = exports.ox_inventory:RemoveItem(src,req.itemName,req.itemCount) == true
        end)
        if not removed then
            return TriggerClientEvent('cookie_admin:client:notify',src,'승급 아이템을 사용하지 못했습니다.',true)
        end
    end

    MySQL.update.await([[
        UPDATE cookie_job_level_progress
        SET unlocked_level=?,updated_at=CURRENT_TIMESTAMP
        WHERE citizenid=? AND job_key=?
    ]], { target,cid,jobKey })

    TriggerClientEvent('cookie_admin:client:notify',src,
        ('%s LV%d 승급 완료!'):format(def.label or jobKey,target),false)
    TriggerClientEvent('cookie_admin:client:jobLevelsRefresh',src,buildJobLevels(src))
end)

RegisterNetEvent('cookie_admin:server:requestJobLevelSystem', function()
    local src = source
    local license = getLicense(src)
    if not license then return end
    local admin = fetchAdmin(license)
    if not admin then return end
    local effective = select(1,getEffectiveLevel(license))
    if (tonumber(effective) or 0) < 5 then return end
    TriggerClientEvent('cookie_admin:client:jobLevelSystemData',src,buildJobLevelAdminConfig())
end)

RegisterNetEvent('cookie_admin:server:saveJobLevelSystem', function(data)
    local src = source
    local license = getLicense(src)
    if not license or type(data) ~= 'table' or type(data.jobs) ~= 'table' then return end
    local admin = fetchAdmin(license)
    if not admin then return end
    local effective = select(1,getEffectiveLevel(license))
    if (tonumber(effective) or 0) < 5 then return end

    local known = Config.CivilJobs or {}
    for _, j in ipairs(data.jobs) do
        local key = tostring(j.key or '')
        if known[key] then
            local maxLv = math.max(1,math.min(50,math.floor(tonumber(j.maxLevel) or 5)))
            MySQL.insert.await([[
                INSERT INTO cookie_job_level_config(job_key,max_level) VALUES(?,?)
                ON DUPLICATE KEY UPDATE max_level=VALUES(max_level)
            ]], {key,maxLv})

            for lv=2,maxLv do
                local rr = nil
                if type(j.requirements)=='table' then
                    for _, r in ipairs(j.requirements) do
                        if tonumber(r.targetLevel)==lv then rr=r break end
                    end
                end
                rr = rr or {}
                local exp = math.max(0,math.floor(tonumber(rr.requiredExp) or ((lv-1)*100)))
                local item = tostring(rr.itemName or ''):lower():sub(1,80)
                local cnt = math.max(0,math.min(999,math.floor(tonumber(rr.itemCount) or 0)))

                -- 승급 아이템은 ox_inventory에 실제 등록된 ID만 저장한다.
                if item ~= '' and cnt > 0 then
                    local okItem, itemDef = pcall(function()
                        return exports.ox_inventory:Items(item)
                    end)
                    if not okItem or not itemDef then
                        return TriggerClientEvent('cookie_admin:client:notify',src,
                            ('존재하지 않는 ox_inventory 아이템입니다: %s'):format(item),true)
                    end
                else
                    item, cnt = '', 0
                end

                MySQL.insert.await([[
                    INSERT INTO cookie_job_level_requirement(job_key,target_level,required_exp,item_name,item_count)
                    VALUES(?,?,?,?,?)
                    ON DUPLICATE KEY UPDATE
                      required_exp=VALUES(required_exp),
                      item_name=VALUES(item_name),
                      item_count=VALUES(item_count)
                ]], {key,lv,exp,item,cnt})
            end

            MySQL.update.await(
                'DELETE FROM cookie_job_level_requirement WHERE job_key=? AND target_level>?',
                {key,maxLv}
            )
            MySQL.update.await(
                'UPDATE cookie_job_level_progress SET unlocked_level=? WHERE job_key=? AND unlocked_level>?',
                {maxLv,key,maxLv}
            )
        end
    end

    TriggerClientEvent('cookie_admin:client:notify',src,'직업 레벨 설정을 저장했습니다.',false)
    TriggerClientEvent('cookie_admin:client:jobLevelSystemData',src,buildJobLevelAdminConfig())
end)

local function checkFeaturePermission(adminLevel, featureKey)
    local row = MySQL.single.await(
        'SELECT min_level, danger_level, requires_target FROM cookie_admin_feature WHERE feature_key = ?',
        { featureKey }
    )
    if not row then return nil, '존재하지 않는 기능' end
    if adminLevel < row.min_level then return nil, '권한 부족' end
    return row, nil
end

RegisterNetEvent('cookie_admin:server:punishPlayer', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local action = tostring(data.action or ''):lower()
    if action ~= 'kick' and action ~= 'ban' then return end

    local target = tonumber(data.targetServerId)
    local reason = trimText(data.reason, 300)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상이 접속 중이 아닙니다', true)
        return
    end
    if target == src then
        TriggerClientEvent('cookie_admin:client:notify', src, '자기 자신에게는 사용할 수 없습니다', true)
        return
    end
    local canTarget, targetErr = CookieCanTargetAdmin(src, target)
    if not canTarget then
        TriggerClientEvent('cookie_admin:client:notify', src, targetErr, true)
        return
    end
    if #reason < 2 then
        TriggerClientEvent('cookie_admin:client:notify', src, '사유를 2자 이상 입력하세요', true)
        return
    end

    local license = getLicense(src)
    local admin = license and fetchAdmin(license) or nil
    if not admin then return end
    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then
        TriggerClientEvent('cookie_admin:client:notify', src, powerErr, true)
        return
    end

    local feature, err = checkFeaturePermission(tonumber(admin.admin_level) or 0, action)
    if not feature then
        TriggerClientEvent('cookie_admin:client:notify', src, err or '권한이 없습니다', true)
        return
    end

    local t = targetPunishInfo(target)
    if not t.license then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상의 라이선스를 확인할 수 없습니다', true)
        return
    end

    if action == 'kick' then
        pcall(function()
            MySQL.insert.await([[
                INSERT INTO cookie_admin_punishment_log
                  (action, admin_name, admin_license, admin_level, target_server, target_gobun,
                   target_cid, target_name, target_license, reason, minutes)
                VALUES ('kick', ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ]], {
                admin.admin_name, license, admin.admin_level, target, t.gobun,
                t.citizenid, t.name, t.license, reason
            })
        end)

        TriggerClientEvent('cookie_admin:client:notify', src,
            ('%s님을 킥했습니다. 사유: %s'):format(t.name, reason), false)

        cookieAdminLog('kick','관리자 킥',reason,{
            {name='처리 관리자',value=tostring(admin.admin_name or '-'),inline=true},
        },{actorSrc=src,targetSrc=target,actorLabel='관리자',targetLabel='대상',eventKey='kick'})

        -- 대상에게 실제 퇴장 전에 사유를 먼저 보여줍니다.
        TriggerClientEvent('cookie_admin:client:notify', target,
            ('관리자에 의해 킥됩니다. 사유: %s'):format(reason), true)

        local expectedLicense = t.license
        SetTimeout(1200, function()
            if GetPlayerName(target) and getLicense(target) == expectedLicense then
                TriggerEvent('cookie_chat:server:markDrop', target, 'kick', reason)
                DropPlayer(target, ('관리자에 의해 서버에서 추방되었습니다.\n사유: %s\n처리 관리자: %s'):format(
                    reason, tostring(admin.admin_name or '관리자')))
            end
        end)
        return
    end

    local minutes = math.floor(tonumber(data.minutes) or 0)
    local allowed = {
        [0] = true,       -- 영구
        [1440] = true,    -- 1일
        [4320] = true,    -- 3일
        [10080] = true,   -- 7일
        [43200] = true,   -- 30일
    }
    if not allowed[minutes] then minutes = 0 end

    local expiresAt = nil
    if minutes > 0 then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + (minutes * 60))
    end

    local banId = MySQL.insert.await([[
        INSERT INTO cookie_admin_ban
          (identifier, target_gobun, target_cid, target_name, reason,
           admin_name, admin_license, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        t.license, t.gobun, t.citizenid, t.name, reason,
        admin.admin_name, license, expiresAt
    })

    if not banId then
        TriggerClientEvent('cookie_admin:client:notify', src, '밴 저장에 실패했습니다', true)
        return
    end

    pcall(function()
        MySQL.insert.await([[
            INSERT INTO cookie_admin_punishment_log
              (action, admin_name, admin_license, admin_level, target_server, target_gobun,
               target_cid, target_name, target_license, reason, minutes)
            VALUES ('ban', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            admin.admin_name, license, admin.admin_level, target, t.gobun,
            t.citizenid, t.name, t.license, reason, minutes
        })
    end)

    local durationText = punishmentExpiryText(minutes)
    TriggerClientEvent('cookie_admin:client:notify', src,
        ('%s님을 %s 밴했습니다. 사유: %s'):format(t.name, durationText, reason), false)

    local releaseText = expiresAt or '영구'

    cookieAdminLog('ban','관리자 밴',reason,{
        {name='처리 관리자',value=tostring(admin.admin_name or '-'),inline=true},
        {name='기간',value=durationText,inline=true},
        {name='해제',value=releaseText,inline=true},
    },{actorSrc=src,targetSrc=target,actorLabel='관리자',targetLabel='대상',eventKey='ban'})

    -- 밴 사유/기간을 대상 화면에 먼저 표시한 뒤 연결을 종료합니다.
    TriggerClientEvent('cookie_admin:client:notify', target,
        ('관리자에 의해 밴됩니다. 사유: %s · 기간: %s'):format(reason, durationText), true)

    local expectedLicense = t.license
    SetTimeout(1500, function()
        if GetPlayerName(target) and getLicense(target) == expectedLicense then
            TriggerEvent('cookie_chat:server:markDrop', target, 'ban', reason)
            DropPlayer(target, ('쿠키서버 이용이 제한되었습니다.\n사유: %s\n기간: %s\n해제: %s\n처리 관리자: %s'):format(
                reason, durationText, releaseText, tostring(admin.admin_name or '관리자')))
        end
    end)
end)

-- ============================================================
-- V14.3.0 서버 리붓 (LV5)
--  · F3 버튼 -> 60초 카운트다운
--  · 카운트 종료 후 전체 플레이어에게 리붓 안내 -> 전원 퇴장
--  · 퇴장 메시지는 cookie_chat에서 '리붓 후 다시 접속해주세요'로 고정 표기
--  · 마지막에 FXServer quit. txAdmin이 서버 프로세스를 관리 중이면 재기동됩니다.
-- ============================================================
local cookieRebootRunning = false
local cookieRebootEndsAt = 0
local cookieRebootReviveCooldown = {}

RegisterNetEvent('cookie_admin:server:rebootEmergencyRevive', function()
    local src = source
    if not cookieRebootRunning or not src or src <= 0 then return end

    local now = GetGameTimer()
    local last = cookieRebootReviveCooldown[src] or 0
    if now - last < 2000 then return end
    cookieRebootReviveCooldown[src] = now

    local ok = pcall(function()
        exports.qbx_medical:Revive(src)
        exports.qbx_medical:Heal(src)
    end)
    if ok then
        TriggerClientEvent('cookie_admin:client:restoreHp', src, src)
    end
end)

AddEventHandler('playerDropped', function()
    cookieRebootReviveCooldown[source] = nil
end)

local function cookieRebootBroadcast(message)
    message = trimText(message, 300)
    if message == '' then return end
    if GetResourceState('chat') == 'started' then
        exports.chat:addMessage(-1, {
            templateId = 'cookie_system',
            args = { message }
        })
    else
        TriggerClientEvent('chat:addMessage', -1, { args = { '[COOKIE]', message } })
    end
end

RegisterNetEvent('cookie_admin:server:startReboot', function()
    local src = source
    local license = getLicense(src)
    local admin = license and fetchAdmin(license) or nil
    if not admin then return end

    local effectiveLevel = select(1, getEffectiveLevel(license))
    if effectiveLevel < 5 then
        TriggerClientEvent('cookie_admin:client:notify', src, 'LV5 관리자만 서버 리붓을 사용할 수 있습니다.', true)
        return
    end

    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then
        TriggerClientEvent('cookie_admin:client:notify', src, powerErr or '현재 사용할 수 없습니다.', true)
        return
    end

    if cookieRebootRunning then
        local remain = math.max(0, cookieRebootEndsAt - os.time())
        TriggerClientEvent('cookie_admin:client:notify', src,
            ('이미 서버 리붓이 진행 중입니다. 약 %d초 남았습니다.'):format(remain), true)
        TriggerClientEvent('cookie_admin:client:rebootCountdown', src, remain)
        return
    end

    cookieRebootRunning = true
    cookieRebootEndsAt = os.time() + 60

    TriggerClientEvent('cookie_admin:client:notify', src, '서버 리붓 60초 카운트다운을 시작했습니다.', false)
    cookieRebootBroadcast(('서버가 60초 후 리붓됩니다. 잠시 후 다시 접속해주세요. (관리자: %s)'):format(
        tostring(admin.admin_name or '관리자')))

    pcall(function()
        cookieAdminLog('reboot', '서버 리붓', '60초 카운트다운 시작', {
            { name = '처리 관리자', value = tostring(admin.admin_name or '-'), inline = true },
        }, { actorSrc = src, actorLabel = '관리자', eventKey = 'reboot' })
    end)

    CreateThread(function()
        local notices = { [30] = true, [10] = true, [5] = true }
        for remaining = 60, 1, -1 do
            TriggerClientEvent('cookie_admin:client:rebootCountdown', -1, remaining)
            if notices[remaining] then
                cookieRebootBroadcast(('서버 리붓까지 %d초 남았습니다.'):format(remaining))
            end
            Wait(1000)
        end

        TriggerClientEvent('cookie_admin:client:rebootCountdown', -1, 0)
        cookieRebootBroadcast('서버 리붓 카운트가 종료되었습니다. 지금 리붓을 진행합니다.')
        Wait(500)

        local players = GetPlayers()
        -- 먼저 모두 리붓 퇴장으로 표시해 두어 playerDropped 분류가 흔들리지 않게 합니다.
        for _, pid in ipairs(players) do
            local target = tonumber(pid)
            if target then
                TriggerEvent('cookie_chat:server:markDrop', target, 'reboot', '리붓 후 다시 접속해주세요')
            end
        end

        for _, pid in ipairs(players) do
            local target = tonumber(pid)
            if target and GetPlayerName(target) then
                DropPlayer(target, 'COOKIE SERVER REBOOT\n리붓 후 다시 접속해주세요.')
            end
        end

        Wait(1500)
        ExecuteCommand('quit')
    end)
end)

RegisterNetEvent('cookie_admin:server:runFeature', function(featureKey, targetServerId)
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    if not admin then

        return
    end

    local feature, err = checkFeaturePermission(admin.admin_level, featureKey)
    if not feature then

        return
    end

    if feature.requires_target == 1 then
        local target = tonumber(targetServerId)
        if not target or not GetPlayerName(target) then

            return
        end
    end

    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then
        TriggerClientEvent('cookie_admin:client:notify', src, powerErr, true)
        return
    end

    local targetName = (function()
        local ok, nick = pcall(function()
            return exports.cookie_core:getNickname(tonumber(targetServerId))
        end)
        if ok and type(nick) == 'string' and nick ~= '' then return nick end
        return GetPlayerName(tonumber(targetServerId)) or '대상'
    end)()
    local target = tonumber(targetServerId)
    if target then
        local canTarget, targetErr = CookieCanTargetAdmin(src, target)
        if not canTarget then
            TriggerClientEvent('cookie_admin:client:notify', src, targetErr, true)
            return
        end
    end

    if featureKey == 'hp_restore' then

        -- 체력 회복은 사망/다운 상태를 건드리지 않는다.
        TriggerClientEvent('cookie_admin:client:restoreHp', target, target)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님의 체력을 회복했습니다')

    elseif featureKey == 'revive' then

        -- 관리자 부활은 cookie_medic의 일반 부활 대기시간과 무관하게 즉시 실행한다.
        local okRevive = pcall(function()
            exports.qbx_medical:Revive(target)
            exports.qbx_medical:Heal(target)
        end)
        if not okRevive then
            TriggerClientEvent('cookie_admin:client:notify', src, '부활 처리에 실패했습니다', true)
            return
        end
        TriggerClientEvent('cookie_admin:client:restoreHp', target, target)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님을 즉시 부활시켰습니다')
        TriggerClientEvent('cookie_admin:client:notify', target, '관리자에 의해 즉시 부활했습니다')

    elseif featureKey == 'cuff' then
        if GetResourceState('cookie_police') ~= 'started' then
            return TriggerClientEvent('cookie_admin:client:notify', src, '경찰 수갑 시스템이 실행 중이 아닙니다', true)
        end

        local current = false
        local okState, value = pcall(function() return exports.cookie_police:IsCuffed(target) end)
        if okState then current = value == true end

        local okSet, result = pcall(function()
            return exports.cookie_police:ForceSetCuffed(target, not current)
        end)
        if not okSet or result == false then
            return TriggerClientEvent('cookie_admin:client:notify', src, '수갑 상태 변경에 실패했습니다', true)
        end

        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. (current and '님의 수갑을 해제했습니다' or '님에게 수갑을 채웠습니다'))
        TriggerClientEvent('cookie_admin:client:notify', target, current and '관리자에 의해 수갑이 해제되었습니다' or '관리자에 의해 수갑이 채워졌습니다', not current)

    elseif featureKey == 'cure_food' then
        local targetPlayer = exports.qbx_core:GetPlayer(target)
        if not targetPlayer then
            TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다', true)
            return
        end
        targetPlayer.Functions.SetMetaData('hunger', 100)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님의 배고픔을 회복했습니다')

    elseif featureKey == 'cure_water' then
        local targetPlayer = exports.qbx_core:GetPlayer(target)
        if not targetPlayer then
            TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다', true)
            return
        end
        targetPlayer.Functions.SetMetaData('thirst', 100)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님의 수분을 회복했습니다')

    elseif featureKey == 'tp' then

        local targetPed = GetPlayerPed(target)
        local coords = GetEntityCoords(targetPed)
        local heading = GetEntityHeading(targetPed)
        TriggerClientEvent('cookie_admin:client:teleportTo', src, coords, heading)
        local adminNick = getCharName(src)
        local targetNick = getCharName(target)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님에게 이동했습니다')

    elseif featureKey == 'goto' then

        local adminPed = GetPlayerPed(src)
        local adminCoords = GetEntityCoords(adminPed)
        local adminHeading = GetEntityHeading(adminPed)
        TriggerClientEvent('cookie_admin:client:bringTo', target, adminCoords, adminHeading)
        local adminNick = getCharName(src)
        local targetNick = getCharName(target)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님을 소환했습니다')

    elseif featureKey == 'location_check' then
        local ped = GetPlayerPed(target)
        if not ped or ped == 0 then
            return TriggerClientEvent('cookie_admin:client:notify', src, '대상 위치를 확인할 수 없습니다', true)
        end
        local c = GetEntityCoords(ped)
        TriggerClientEvent('cookie_admin:client:showTargetLocation', src, targetName, c.x, c.y, c.z)

    elseif featureKey == 'drag' then
        TriggerClientEvent('cookie_admin:client:toggleAdminDrag', target, src)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님의 끌고가기 상태를 전환했습니다')

    elseif featureKey == 'melt' then

        TriggerClientEvent('cookie_admin:client:melt', target)
        local adminNick = getCharName(src)
        local targetNick = getCharName(target)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님의 상태를 초기화했습니다 (녹임)')

    elseif featureKey == 'send_onboarding' then

        local targetLicense = getLicense(target)
        if not targetLicense then
            TriggerClientEvent('cookie_admin:client:notify', src, '대상 license 확인 실패', true)
            return
        end
        local ok = exports.cookie_core:resetOnboarding(targetLicense)
        if not ok then
            TriggerClientEvent('cookie_admin:client:notify', src, '온보딩 초기화 실패', true)
            return
        end
        local adminNick = getCharName(src)
        local targetNick = getCharName(target)

        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님을 온보딩으로 보냈습니다')
        DropPlayer(target, '관리자에 의해 온보딩이 재설정되었습니다. 재접속해주세요.')
    elseif featureKey == 'jobless' then

        local targetPlayer = exports.qbx_core:GetPlayer(target)
        if not targetPlayer then
            TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다', true)
            return
        end
        local jobName = targetPlayer.PlayerData.job and targetPlayer.PlayerData.job.name
        local civil = jobName and Config.CivilJobs and Config.CivilJobs[jobName]
        if not civil then
            TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님은 시민직이 아닙니다 (팩션/무직은 대상 아님)', true)
            return
        end
        if civil.quitEvent then
            pcall(function() TriggerEvent(civil.quitEvent, target, '관리자 무직처리') end)
        end
        pcall(function() targetPlayer.Functions.SetJob('unemployed', 0) end)

        TriggerEvent('cookie_admin:server:nameTagDirty', target)
        TriggerEvent('cookie_admin:server:jobDisplayDirty', target)
        local adminNick = getCharName(src)
        local targetNick = getCharName(target)
        TriggerClientEvent('cookie_admin:client:notify', src, targetName .. '님을 무직 처리했습니다 (' .. (civil.label or jobName) .. ')')
        TriggerClientEvent('cookie_admin:client:notify', target, '관리자에 의해 무직 처리되었습니다', true)

    else

        TriggerClientEvent('cookie_admin:client:notify', src, '미구현 기능입니다', true)
    end
end)


-- ============================================================
-- COOKIE ITEM CONFISCATION V14.2.8
-- 대상 인벤토리 조회 / 슬롯 단위 압수 / 전체 압수
-- ============================================================
local function confiscateAccess(src, target)
    local license = getLicense(src)
    if not license then return nil, nil, '관리자 식별에 실패했습니다' end
    local admin = fetchAdmin(license)
    if not admin then return nil, nil, '관리자 권한이 없습니다' end

    local feature, err = checkFeaturePermission(admin.admin_level, 'confiscate_item')
    if not feature then return nil, nil, err or '권한이 부족합니다' end

    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then return nil, nil, powerErr or '현재 관리자 기능을 사용할 수 없습니다' end

    target = tonumber(target)
    if not target or not GetPlayerName(target) then
        return nil, nil, '대상이 접속 중이 아닙니다'
    end
    if target == src then
        return nil, nil, '자기 자신의 아이템은 압수할 수 없습니다'
    end

    local canTarget, targetErr = CookieCanTargetAdmin(src, target)
    if not canTarget then return nil, nil, targetErr or '해당 대상을 관리할 수 없습니다' end

    if GetResourceState('ox_inventory') ~= 'started' then
        return nil, nil, 'ox_inventory가 실행 중이 아닙니다'
    end
    return admin, target, nil
end

local function buildConfiscateInventory(target)
    local ok, list = pcall(function()
        return exports.ox_inventory:GetInventoryItems(target)
    end)
    if not ok or type(list) ~= 'table' then return nil end

    local rows = {}
    for slot, it in pairs(list) do
        if type(it) == 'table' and it.name and (tonumber(it.count) or 0) > 0 then
            rows[#rows + 1] = {
                slot = tonumber(it.slot) or tonumber(slot) or 0,
                name = tostring(it.name),
                label = tostring(it.label or it.name),
                count = math.floor(tonumber(it.count) or 0),
            }
        end
    end
    table.sort(rows, function(a, b)
        local al, bl = (a.label or ''):lower(), (b.label or ''):lower()
        if al == bl then return (a.slot or 0) < (b.slot or 0) end
        return al < bl
    end)
    return rows
end

local function sendConfiscateInventory(src, target, message, isError)
    local rows = buildConfiscateInventory(target)
    if not rows then
        TriggerClientEvent('cookie_admin:client:targetInventory', src, {
            ok = false, targetServerId = target, items = {},
            message = message or '대상 인벤토리를 불러오지 못했습니다', isError = true,
        })
        return
    end
    local nick = GetPlayerName(target) or ('#' .. tostring(target))
    local okNick, cookieNick = pcall(function() return exports.cookie_core:getNickname(target) end)
    if okNick and type(cookieNick) == 'string' and cookieNick ~= '' then nick = cookieNick end
    TriggerClientEvent('cookie_admin:client:targetInventory', src, {
        ok = true, targetServerId = target, targetName = nick, items = rows,
        message = message, isError = isError == true,
    })
end

RegisterNetEvent('cookie_admin:server:requestTargetInventory', function(targetServerId)
    local src = source
    local _, target, err = confiscateAccess(src, targetServerId)
    if not target then
        TriggerClientEvent('cookie_admin:client:targetInventory', src, { ok=false, items={}, message=err, isError=true })
        return
    end
    sendConfiscateInventory(src, target)
end)

RegisterNetEvent('cookie_admin:server:confiscateItem', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local admin, target, err = confiscateAccess(src, data.targetServerId)
    if not target then
        TriggerClientEvent('cookie_admin:client:notify', src, err or '압수할 수 없습니다', true)
        return
    end

    local slot = math.floor(tonumber(data.slot) or 0)
    local qty = math.floor(tonumber(data.count) or 0)
    if slot < 1 or qty < 1 then
        TriggerClientEvent('cookie_admin:client:notify', src, '압수 수량 또는 슬롯이 올바르지 않습니다', true)
        return sendConfiscateInventory(src, target)
    end

    local okSlot, item = pcall(function()
        return exports.ox_inventory:GetSlot(target, slot)
    end)
    if not okSlot or type(item) ~= 'table' or not item.name then
        TriggerClientEvent('cookie_admin:client:notify', src, '해당 슬롯의 아이템이 이미 변경되었습니다', true)
        return sendConfiscateInventory(src, target)
    end

    local available = math.floor(tonumber(item.count) or 0)
    if available < 1 then return sendConfiscateInventory(src, target) end
    qty = math.min(qty, available)

    local removed = false
    local okRemove, result = pcall(function()
        return exports.ox_inventory:RemoveItem(target, item.name, qty, item.metadata, slot)
    end)
    removed = okRemove and result == true
    if not removed then
        TriggerClientEvent('cookie_admin:client:notify', src, '아이템 압수에 실패했습니다', true)
        return sendConfiscateInventory(src, target)
    end

    local label = tostring(item.label or item.name)
    local adminName = tostring(admin.admin_name or GetPlayerName(src) or '관리자')
    local targetName = GetPlayerName(target) or ('#' .. target)
    local okNick, nick = pcall(function() return exports.cookie_core:getNickname(target) end)
    if okNick and type(nick) == 'string' and nick ~= '' then targetName = nick end

    TriggerClientEvent('cookie_admin:client:notify', src, ('%s님의 %s ×%d을 압수했습니다'):format(targetName, label, qty), false)
    TriggerClientEvent('cookie_admin:client:notify', target, ('관리자에 의해 %s ×%d이 압수되었습니다'):format(label, qty), true)
    cookieAdminLog('admin','아이템 압수',('%s ×%d'):format(label, qty),{
        {name='관리자',value=adminName,inline=true},
        {name='대상',value=targetName,inline=true},
        {name='아이템 코드',value=tostring(item.name),inline=true},
        {name='수량',value=tostring(qty),inline=true},
        {name='슬롯',value=tostring(slot),inline=true},
    },{actorSrc=src,targetSrc=target,actorLabel='관리자',targetLabel='대상',eventKey='item_confiscate'})

    sendConfiscateInventory(src, target, ('%s ×%d 압수 완료'):format(label, qty), false)
end)

RegisterNetEvent('cookie_admin:server:confiscateAllItems', function(targetServerId)
    local src = source
    local admin, target, err = confiscateAccess(src, targetServerId)
    if not target then
        TriggerClientEvent('cookie_admin:client:notify', src, err or '압수할 수 없습니다', true)
        return
    end

    local rows = buildConfiscateInventory(target)
    if not rows then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상 인벤토리를 불러오지 못했습니다', true)
        return
    end
    if #rows == 0 then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상 인벤토리가 비어 있습니다', true)
        return sendConfiscateInventory(src, target)
    end

    local removedStacks, removedCount = 0, 0
    -- 뒤쪽 슬롯부터 처리해 슬롯 이동 영향을 최소화한다.
    table.sort(rows, function(a,b) return (a.slot or 0) > (b.slot or 0) end)
    for _, row in ipairs(rows) do
        local okSlot, item = pcall(function() return exports.ox_inventory:GetSlot(target, row.slot) end)
        if okSlot and type(item) == 'table' and item.name and (tonumber(item.count) or 0) > 0 then
            local count = math.floor(tonumber(item.count) or 0)
            local okRemove, result = pcall(function()
                return exports.ox_inventory:RemoveItem(target, item.name, count, item.metadata, row.slot)
            end)
            if okRemove and result == true then
                removedStacks = removedStacks + 1
                removedCount = removedCount + count
            end
        end
    end

    local targetName = GetPlayerName(target) or ('#' .. target)
    local okNick, nick = pcall(function() return exports.cookie_core:getNickname(target) end)
    if okNick and type(nick) == 'string' and nick ~= '' then targetName = nick end
    local adminName = tostring(admin.admin_name or GetPlayerName(src) or '관리자')

    if removedStacks < 1 then
        TriggerClientEvent('cookie_admin:client:notify', src, '압수 가능한 아이템이 없거나 제거에 실패했습니다', true)
        return sendConfiscateInventory(src, target)
    end

    TriggerClientEvent('cookie_admin:client:notify', src, ('%s님의 인벤토리를 전체 압수했습니다 (%d칸 / %d개)'):format(targetName, removedStacks, removedCount), false)
    TriggerClientEvent('cookie_admin:client:notify', target, '관리자에 의해 인벤토리 아이템이 전체 압수되었습니다', true)
    cookieAdminLog('admin','아이템 전체 압수',('총 %d칸 / %d개'):format(removedStacks, removedCount),{
        {name='관리자',value=adminName,inline=true},
        {name='대상',value=targetName,inline=true},
        {name='압수 슬롯',value=tostring(removedStacks),inline=true},
        {name='총 수량',value=tostring(removedCount),inline=true},
    },{actorSrc=src,targetSrc=target,actorLabel='관리자',targetLabel='대상',eventKey='item_confiscate_all'})

    sendConfiscateInventory(src, target, ('전체 압수 완료 · %d개'):format(removedCount), false)
end)

RegisterNetEvent('cookie_admin:server:giveMoney', function()
    local src = source
    -- 2026-08-26: 관리자 지급은 모두 F3 우편함을 통해 수령하도록 통일.
    TriggerClientEvent('cookie_admin:client:notify', src, '돈 지급은 지급 관리 > 우편 발송을 이용해주세요', true)
end)

local function findWeaponInCatalog(weaponName)
    for _, cat in ipairs(Config.Weapons) do
        for _, it in ipairs(cat.items) do
            if it.name == weaponName then return it, cat end
        end
    end
    return nil, nil
end

RegisterNetEvent('cookie_admin:server:giveWeapon', function(targetServerId, weaponName, amount, mode)
    local src = source
    local license = getLicense(src)
    if not license then return end
    local admin = fetchAdmin(license)
    if not admin then  return end

    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then
        TriggerClientEvent('cookie_admin:client:notify', src, powerErr, true)
        return
    end

    if admin.admin_level < Config.WeaponGiveMinLevel then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return
    end

    local item, cat = findWeaponInCatalog(tostring(weaponName))
    if not item then

        TriggerClientEvent('cookie_admin:client:notify', src, '등록되지 않은 무기입니다', true)
        return
    end

    local target = tonumber(targetServerId)
    if not target then return end
    local targetPlayer = exports.qbx_core:GetPlayer(target)
    if not targetPlayer then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다', true)
        return
    end

    local n = math.floor(tonumber(amount) or 0)
    mode = tostring(mode or 'weapon')
    local ok, msg

    if mode == 'ammo' then

        if cat.type ~= 'gun' or not item.ammo then
            TriggerClientEvent('cookie_admin:client:notify', src, '이 무기는 별도 탄약이 없습니다', true); return
        end
        if n < 1 or n > 9999 then
            TriggerClientEvent('cookie_admin:client:notify', src, '탄약 수는 1~9999 사이여야 합니다', true); return
        end
        ok = exports.ox_inventory:AddItem(target, item.ammo, n) and true or false
        msg = item.label .. ' 탄약 ' .. n .. '발 지급 완료'
    else

        if cat.type == 'throwable' then
            if n < 1 or n > 9999 then
                TriggerClientEvent('cookie_admin:client:notify', src, '개수는 1~9999 사이여야 합니다', true); return
            end
            ok = exports.ox_inventory:AddItem(target, item.name, n) and true or false
            msg = item.label .. ' ' .. n .. '개 지급 완료'
        else
            ok = exports.ox_inventory:AddItem(target, item.name, 1) and true or false
            msg = item.label .. ' 지급 완료 (무기만 · 탄약 별도)'
            n = 0
        end
    end

    if not ok then
        TriggerClientEvent('cookie_admin:client:notify', src, '지급 실패 (인벤 공간/무게 확인)', true)

        return
    end

    TriggerClientEvent('cookie_admin:client:notify', src, msg, false)

end)

RegisterNetEvent('cookie_admin:server:startDuty', function()
    local src = source
    local license = getLicense(src)
    if not license then return end
    local admin = fetchAdmin(license)
    if not admin then return end

    setState(src, 'duty')
    TriggerClientEvent('cookie_admin:client:stateChanged', src, 'duty')
    TriggerClientEvent('cookie_admin:client:notify', src, '관리 업무를 시작했습니다')
end)

RegisterNetEvent('cookie_admin:server:endDuty', function()
    local src = source
    setState(src, 'rp')
    TriggerClientEvent('cookie_admin:client:stateChanged', src, 'rp')
    TriggerClientEvent('cookie_admin:client:notify', src, '관리 업무를 종료했습니다', false, 'neutral')
end)

RegisterNetEvent('cookie_admin:server:toggleRp', function()
    local src = source
    local current = getState(src)
    if current == 'duty' then
        setState(src, 'rp')
        TriggerClientEvent('cookie_admin:client:stateChanged', src, 'rp')
        TriggerClientEvent('cookie_admin:client:notify', src, 'RP 모드로 전환했습니다')
    elseif current == 'rp' then
        setState(src, 'duty')
        TriggerClientEvent('cookie_admin:client:stateChanged', src, 'duty')
        TriggerClientEvent('cookie_admin:client:notify', src, '관리 모드로 복귀했습니다')
    end
end)

local function isValidPw(pw)
    return type(pw) == 'string' and pw:match('^%d%d%d%d%d%d$') ~= nil
end

local function makeSalt()
    return lib.string.random(string.rep('.', 32))
end

RegisterNetEvent('cookie_admin:server:setAdminPw', function(newPw)
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    if not admin then

        return
    end

    if admin.admin_level < 5 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return
    end

    if not isValidPw(newPw) then

        TriggerClientEvent('cookie_admin:client:notify', src, '비밀번호는 6자리 숫자여야 합니다', true)
        return
    end

    local cur = MySQL.single.await('SELECT pw_hash FROM cookie_admin WHERE license = ?', { license })
    if cur and cur.pw_hash ~= nil then

        TriggerClientEvent('cookie_admin:client:notify', src, '이미 비밀번호가 설정되어 있습니다', true)
        return
    end

    local newSalt = makeSalt()
    MySQL.update.await(
        'UPDATE cookie_admin SET pw_hash = SHA2(CONCAT(?, ?), 256), pw_salt = ? WHERE license = ?',
        { newPw, newSalt, newSalt, license }
    )

    TriggerClientEvent('cookie_admin:client:notify', src, '비밀번호를 설정했습니다', false)
end)

RegisterNetEvent('cookie_admin:server:resetAdminPw', function(targetServerId)
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    if not admin then

        return
    end

    if not (admin.is_dev == true or admin.is_dev == 1) then

        TriggerClientEvent('cookie_admin:client:notify', src, '개발자 권한이 필요합니다', true)
        return
    end

    local target = tonumber(targetServerId)
    if not target then return end
    local targetLicense = getLicense(target)
    if not targetLicense then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다', true)
        return
    end

    local targetAdmin = fetchAdmin(targetLicense)
    if not targetAdmin then

        TriggerClientEvent('cookie_admin:client:notify', src, '대상이 관리자가 아닙니다', true)
        return
    end

    MySQL.update.await(
        'UPDATE cookie_admin SET pw_hash = NULL, pw_salt = NULL WHERE license = ?',
        { targetLicense }
    )

    TriggerClientEvent('cookie_admin:client:notify', src, targetAdmin.admin_name .. '님의 비밀번호를 초기화했습니다', false)
end)

exports('getEffectiveLevel', function(src)
    local license = getLicense(src)
    if not license then return 0 end
    return (getEffectiveLevel(license))
end)

exports('isAdminDuty', function(src, minLevel)
    local license = getLicense(src)
    if not license then return false end
    local row = fetchAdmin(license)
    if not row then return false end
    local level = tonumber(row.admin_level) or 0
    return getState(src) == 'duty' and level >= math.max(1, math.floor(tonumber(minLevel) or 1))
end)

exports('getAdminName', function(src)
    local license = getLicense(src)
    if not license then return nil end
    local admin = fetchAdmin(license)
    return admin and admin.admin_name or nil
end)

exports('hasAdminPw', function(src)
    local license = getLicense(src)
    if not license then return false end
    local row = MySQL.single.await('SELECT pw_hash FROM cookie_admin WHERE license = ?', { license })
    return row ~= nil and row.pw_hash ~= nil
end)

exports('verifyAdminPw', function(src, pw)
    local license = getLicense(src)
    if not license then return false end
    if type(pw) ~= 'string' then return false end
    local res = MySQL.single.await(
        'SELECT (pw_hash IS NOT NULL AND pw_hash = SHA2(CONCAT(?, pw_salt), 256)) AS ok FROM cookie_admin WHERE license = ?',
        { pw, license }
    )
    return res ~= nil and res.ok == 1
end)

local function isValidLicense(lic)
    return type(lic) == 'string' and lic:match('^license2?:%x+$') ~= nil
end

local function buildGrantList()
    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local license = getLicense(src)
        if license then
            local u = MySQL.single.await('SELECT gobun, nickname FROM cookie_user WHERE license = ?', { license })
            list[#list + 1] = {
                serverId = src,
                gobun = u and u.gobun or nil,
                nickname = (u and u.nickname and u.nickname ~= '') and u.nickname or getCharName(src),
                license = license,
            }
        end
    end
    return list
end

local grantPwAttempts = {}
local GRANT_MAX_ATTEMPTS = 5
local GRANT_BLOCK_SEC = 60

RegisterNetEvent('cookie_admin:server:requestGrantList', function()
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    local effectiveLevel = getEffectiveLevel(license)
    if not admin or effectiveLevel < 5 then

        return
    end
    local list = buildGrantList()

    TriggerClientEvent('cookie_admin:client:grantList', src, list)
end)

RegisterNetEvent('cookie_admin:server:grantAdmin', function(targetLicense, alias, pw, grantLevel, grantTeam)
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    if not admin then

        return
    end

    local effectiveLevel = getEffectiveLevel(license)

    if admin.admin_level < 5 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return
    end

    local now = os.time()
    local att = grantPwAttempts[license]
    if att and att.blockedUntil and att.blockedUntil > now then
        local remain = att.blockedUntil - now

        TriggerClientEvent('cookie_admin:client:notify', src, ('비밀번호 시도 초과 %d초 후 다시 시도하세요'):format(remain), true)
        return
    end

    if type(pw) ~= 'string' then return end
    local pwRow = MySQL.single.await(
        'SELECT (pw_hash IS NOT NULL AND pw_hash = SHA2(CONCAT(?, pw_salt), 256)) AS ok, pw_hash FROM cookie_admin WHERE license = ?',
        { pw, license }
    )
    local hasPw = pwRow ~= nil and pwRow.pw_hash ~= nil
    if not hasPw then

        TriggerClientEvent('cookie_admin:client:notify', src, '먼저 비밀번호를 설정하세요', true)
        return
    end

    local pwOk = (pwRow.ok == 1 or pwRow.ok == true)

    if not pwOk then
        att = grantPwAttempts[license] or { count = 0 }
        att.count = att.count + 1
        if att.count >= GRANT_MAX_ATTEMPTS then
            att.blockedUntil = now + GRANT_BLOCK_SEC
            att.count = 0

            TriggerClientEvent('cookie_admin:client:notify', src, ('비밀번호 %d회 실패 %d초간 차단됩니다'):format(GRANT_MAX_ATTEMPTS, GRANT_BLOCK_SEC), true)
        else
            TriggerClientEvent('cookie_admin:client:notify', src, ('비밀번호가 일치하지 않습니다 (%d/%d)'):format(att.count, GRANT_MAX_ATTEMPTS), true)
        end
        grantPwAttempts[license] = att
        return
    end

    grantPwAttempts[license] = nil

    if not isValidLicense(targetLicense) then

        TriggerClientEvent('cookie_admin:client:notify', src, 'license 형식이 올바르지 않습니다', true)
        return
    end

    local targetUser = MySQL.single.await('SELECT id, gobun, nickname FROM cookie_user WHERE license = ?', { targetLicense })
    if not targetUser then

        TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다 (미가입 유저)', true)
        return
    end

    local existing = MySQL.single.await('SELECT id FROM cookie_admin WHERE license = ?', { targetLicense })

    if existing then
        TriggerClientEvent('cookie_admin:client:notify', src, '이미 관리자로 등록된 대상입니다', true)
        return
    end

    local cleanAlias = nil
    if type(alias) == 'string' then
        local trimmed = alias:gsub('^%s+', ''):gsub('%s+$', '')
        if #trimmed > 0 then cleanAlias = trimmed:sub(1, 64) end
    end

    local adminName = targetUser.nickname
    if not adminName or adminName == '' then adminName = cleanAlias end
    if not adminName or adminName == '' then adminName = ('고번%s'):format(targetUser.gobun) end

    local level = math.floor(tonumber(grantLevel) or 0)
    if level < 1 or level > 5 then level = 1 end

    local team = normalizeTeam(level, grantTeam)

    MySQL.insert.await(
        'INSERT INTO cookie_admin (license, admin_alias, user_id, admin_name, admin_level, admin_team, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { targetLicense, cleanAlias, targetUser.id, adminName, level, team, license }
    )

    local levelName = Config.LevelName[level] or ('LV' .. level)
    local teamLabel = teamLabelOf(team)
    local teamSuffix = teamLabel and (' · ' .. teamLabel) or ''

    TriggerClientEvent('cookie_admin:client:notify', src, ('%s님에게 관리자 권한(LV%d %s%s)을 부여했습니다'):format(adminName, level, levelName, teamSuffix), false)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local license = getLicense(src)
    if license then grantPwAttempts[license] = nil end
end)

RegisterNetEvent('cookie_admin:server:setAdminAlias', function(targetServerId, newName)
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    if not admin or admin.admin_level < 4 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다 (LV4 이상)', true)
        return
    end

    local tsrc = math.floor(tonumber(targetServerId) or 0)
    local tlicense = tsrc > 0 and getLicense(tsrc) or nil
    if not tlicense then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다 (접속 종료?)', true)
        return
    end

    local target = fetchAdmin(tlicense)
    if not target then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상이 관리자가 아닙니다', true)
        return
    end

    local nm = type(newName) == 'string' and newName:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #nm < 2 then
        TriggerClientEvent('cookie_admin:client:notify', src, '별명은 2자 이상이어야 합니다', true)
        return
    end
    nm = nm:sub(1, 60)

    MySQL.update.await(
        'UPDATE cookie_admin SET admin_name = ?, updated_by = ? WHERE license = ?',
        { nm, license, tlicense })

    TriggerClientEvent('cookie_admin:client:notify', src,
        ('%s → "%s" 로 관리자 별명을 변경했습니다'):format(target.admin_name or '-', nm), false)

    if tsrc ~= src then
        TriggerClientEvent('cookie_admin:client:notify', tsrc, ('관리자 별명이 "%s"(으)로 변경되었습니다'):format(nm), false)
    end
    TriggerClientEvent('cookie_admin:client:forceClosePanel', tsrc)
    if tsrc ~= src then TriggerClientEvent('cookie_admin:client:forceClosePanel', src) end
end)

local function fetchTargetLevel(license)
    local row = MySQL.single.await(
        'SELECT admin_level, is_active, (pw_hash IS NOT NULL) AS has_pw FROM cookie_admin WHERE license = ?',
        { license }
    )
    if not row then return 0, false, false end
    local active = (row.is_active == 1 or row.is_active == true)
    local hasPw = (row.has_pw == 1 or row.has_pw == true)
    return active and row.admin_level or 0, true, hasPw
end

local function countActiveLv5()
    local row = MySQL.single.await(
        'SELECT COUNT(*) AS n FROM cookie_admin WHERE is_active = 1 AND admin_level >= 5', {}
    )
    return (row and tonumber(row.n)) or 0
end

RegisterNetEvent('cookie_admin:server:changeAdminLevel', function(targetServerId, newLevel)
    local src = source
    local license = getLicense(src)
    if not license then return end

    local admin = fetchAdmin(license)
    if not admin then

        return
    end

    local effectiveLevel = getEffectiveLevel(license)
    if effectiveLevel < 5 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return
    end

    local targetSrc = tonumber(targetServerId)
    local targetLicense = targetSrc and getLicense(targetSrc)
    if not targetLicense then
        TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다 (접속 종료?)', true)
        return
    end

    local level = math.floor(tonumber(newLevel) or -1)
    if level < 0 or level > 5 then

        return
    end

    local oldLevel, rowExists, targetHasPw = fetchTargetLevel(targetLicense)

    if level == oldLevel then
        TriggerClientEvent('cookie_admin:client:notify', src, '이미 해당 레벨입니다', true)
        return
    end

    if targetLicense == license and level < oldLevel then

        TriggerClientEvent('cookie_admin:client:notify', src, '자기 자신은 강등할 수 없습니다', true)
        return
    end

    if oldLevel >= 5 and level < 5 and countActiveLv5() <= 1 then

        TriggerClientEvent('cookie_admin:client:notify', src, '마지막 LV5는 강등할 수 없습니다', true)
        return
    end

    local targetUser = MySQL.single.await('SELECT id, gobun, nickname FROM cookie_user WHERE license = ?', { targetLicense })
    local targetName = (targetUser and targetUser.nickname and targetUser.nickname ~= '') and targetUser.nickname
        or getCharName(targetSrc)

    if not rowExists then
        if level == 0 then
            TriggerClientEvent('cookie_admin:client:notify', src, '이미 관리자가 아닙니다', true)
            return
        end
        if not targetUser then
            TriggerClientEvent('cookie_admin:client:notify', src, '대상을 찾을 수 없습니다 (미가입 유저)', true)
            return
        end

        MySQL.insert.await(
            'INSERT INTO cookie_admin (license, user_id, admin_name, admin_level, created_by) VALUES (?, ?, ?, ?, ?)',
            { targetLicense, targetUser.id, targetName, level, license }
        )
    elseif level == 0 then
        MySQL.update.await(
            'UPDATE cookie_admin SET is_active = 0, updated_by = ? WHERE license = ?',
            { license, targetLicense }
        )
    else

        MySQL.update.await(
            'UPDATE cookie_admin SET admin_level = ?, is_active = 1, updated_by = ? WHERE license = ?',
            { level, license, targetLicense }
        )
    end

    local levelName = (level == 0) and '관리자 아님' or (Config.LevelName[level] or ('LV' .. level))
    TriggerClientEvent('cookie_admin:client:notify', src,
        ('%s님의 레벨을 LV%d → LV%d (%s)로 변경했습니다'):format(targetName, oldLevel, level, levelName), false)

    if level >= 5 and not targetHasPw then
        TriggerClientEvent('cookie_admin:client:notify', src,
            'LV5 자격만 부여됨 대상이 비밀번호를 설정해야 발효됩니다', true)
    end

    if targetSrc ~= src then
        TriggerClientEvent('cookie_admin:client:notify', targetSrc,
            ('관리자 레벨이 LV%d(%s)(으)로 변경되었습니다'):format(level, levelName), false)
        TriggerClientEvent('cookie_admin:client:forceClosePanel', targetSrc)
    end
end)

local function authorizeToggle(src, toggleKey)
    local license = getLicense(src)
    if not license then return false end
    local effectiveLevel = getEffectiveLevel(license)
    if effectiveLevel < 1 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return false
    end

    return true
end

RegisterNetEvent('cookie_admin:server:toggleNoclip', function()
    local src = source
    if not authorizeToggle(src, 'noclip') then return end
    TriggerClientEvent('cookie_admin:client:applyNoclip', src)
end)

RegisterNetEvent('cookie_admin:server:toggleSuperJump', function()
    local src = source
    if not authorizeToggle(src, 'superjump') then return end
    TriggerClientEvent('cookie_admin:client:applySuperJump', src)
end)

RegisterNetEvent('cookie_admin:server:toggleStamina', function()
    local src = source
    if not authorizeToggle(src, 'stamina') then return end
    TriggerClientEvent('cookie_admin:client:applyStamina', src)
end)

RegisterNetEvent('cookie_admin:server:toggleSprint', function()
    local src = source
    if not authorizeToggle(src, 'sprint') then return end
    TriggerClientEvent('cookie_admin:client:applySprint', src)
end)

local VALID_POS_SHAPE = { circle = true, box = true }

RegisterNetEvent('cookie_admin:server:extractPos', function(shape)
    local src = source
    local license = getLicense(src)
    if not license then return end
    local effectiveLevel = getEffectiveLevel(license)
    if effectiveLevel < 5 then

        TriggerClientEvent('cookie_admin:client:notify', src, '권한이 부족합니다', true)
        return
    end
    if type(shape) ~= 'string' or not VALID_POS_SHAPE[shape] then shape = 'circle' end

    TriggerClientEvent('cookie_admin:client:applyExtractPos', src, shape)
end)

CreateThread(function()
    while true do
        Wait(5000)
        for src, state in pairs(adminState) do
            if state == 'duty' then
                local player = exports.qbx_core:GetPlayer(src)
                if player then
                    player.Functions.SetMetaData('hunger', 100)
                    player.Functions.SetMetaData('thirst', 100)
                end
            end
        end
    end
end)

local accrueTimers = {}

local function startAccrue(src, license)
    if accrueTimers[src] then return end
    accrueTimers[src] = true
    CreateThread(function()
        while accrueTimers[src] do
            Wait(Config.TimeAccrueInterval)
            if not accrueTimers[src] then break end
            MySQL.update.await(
                'UPDATE cookie_admin SET total_minute = total_minute + 1, last_seen_at = NOW() WHERE license = ?',
                { license }
            )

            if getState(src) == 'duty' then
                MySQL.update.await(
                    'UPDATE cookie_admin SET duty_minute = duty_minute + 1 WHERE license = ?',
                    { license }
                )

            end
        end
    end)
end

AddEventHandler('playerJoining', function()
    local src = source
    local license = getLicense(src)
    if not license then return end
    local admin = fetchAdmin(license)
    if admin then
        startAccrue(src, license)

    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    accrueTimers[src] = nil
    adminState[src] = nil
end)

CookieVehBrand = {}
CookieVehOrder = {}
CookieMajorMap = {}
CookieMajorOrder = {}
CookieTestVeh = {}
CookiePreviewVeh = {}

local function cookieVehNotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local function cookieVehLog(admin, action, model, targetName, detail)
end

function CookieBuildVehCatalog()
    local out = {}
    local vehs = exports.qbx_core:GetVehiclesByName()
    if not vehs then return out end

    -- 관리자 '차량 지급'에서 일반/한정 차고 분류를 미리 보여주기 위한 등록 정보.
    local generalSet, limitedSet = {}, {}
    pcall(function()
        for _, r in ipairs(MySQL.query.await(
            'SELECT model, display_name FROM cookie_dealership_vehicles WHERE active = 1', {}) or {}) do
            local key = tostring(r.model or ''):lower():gsub('%s', '')
            if key ~= '' then generalSet[key] = r.display_name or key end
        end
        for _, r in ipairs(MySQL.query.await(
            'SELECT model, label FROM cookie_limited_vehicles WHERE active = 1', {}) or {}) do
            local key = tostring(r.model or ''):lower():gsub('%s', '')
            if key ~= '' then limitedSet[key] = r.label or key end
        end
    end)

    for spawn, v in pairs(vehs) do
        local model = v.model or spawn
        local modelKey = tostring(model or ''):lower():gsub('%s', '')
        -- Qbox 카테고리는 소문자/공백 제거 후 사용한다.
        local cat = tostring(v.category or 'sports'):lower():gsub('%s+', '')
        local garageType, garageLabel = nil, nil
        -- 둘 다 등록된 예외 상황에서는 실제 cookie_garage 분류와 동일하게 한정을 우선한다.
        if limitedSet[modelKey] then
            garageType, garageLabel = 'limited', limitedSet[modelKey]
        elseif generalSet[modelKey] then
            garageType, garageLabel = 'general', generalSet[modelKey]
        end

        -- 쿠키서버 차고 등록 분류를 관리자 차량 대분류에도 우선 적용한다.
        -- Qbox category가 sedans/sports 등으로 남아 있어도 일반/한정 차량이 확실히 보이게 한다.
        local major = CookieMajorMap[cat] or '기타'
        if garageType == 'limited' then
            major = '한정차량'
        elseif garageType == 'general' then
            major = '일반차량'
        end

        out[#out + 1] = {
            model = modelKey,
            name = v.name or modelKey,
            brand = CookieVehBrand[modelKey] or '기타',
            category = cat,
            major = major,
            price = v.price or 0,
            isNew = (Config.NewVehicles and Config.NewVehicles[modelKey]) and true or false,
            job = (CookieVehJob or {})[modelKey] or nil,
            garageType = garageType,
            garageLabel = garageLabel,
        }
    end
    return out
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_dealership_vehicles` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `model` VARCHAR(60) NOT NULL,
          `brand` VARCHAR(40) NOT NULL DEFAULT '기타',
          `display_name` VARCHAR(80) NOT NULL,
          `price` BIGINT NOT NULL DEFAULT 0,
          `category` VARCHAR(30) DEFAULT NULL,
          `spec` VARCHAR(120) DEFAULT NULL,
          `image` LONGTEXT DEFAULT NULL,
          `sort_order` INT NOT NULL DEFAULT 0,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `added_by` VARCHAR(60) DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          UNIQUE KEY `uniq_model` (`model`),
          KEY `idx_brand_active` (`brand`, `active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})
    pcall(function()
        MySQL.query.await('ALTER TABLE cookie_dealership_vehicles ADD COLUMN IF NOT EXISTS image LONGTEXT NULL AFTER spec')
    end)

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_vehicle_image` (
          `model` VARCHAR(60) NOT NULL PRIMARY KEY,
          `image` MEDIUMTEXT NOT NULL,
          `updated_by` VARCHAR(60) NULL,
          `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_limited_vehicles` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `model` VARCHAR(60) NOT NULL,
          `label` VARCHAR(80) NOT NULL,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `added_by` VARCHAR(60) DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          UNIQUE KEY `uniq_model` (`model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_admin_vehicle_log` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `admin_name` VARCHAR(60) DEFAULT NULL,
          `admin_license` VARCHAR(80) DEFAULT NULL,
          `action` VARCHAR(24) NOT NULL,
          `model` VARCHAR(60) DEFAULT NULL,
          `target_name` VARCHAR(60) DEFAULT NULL,
          `detail` VARCHAR(120) DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          KEY `idx_admin` (`admin_license`),
          KEY `idx_action` (`action`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]], {})

    local raw = LoadResourceFile('cookie_admin', 'data/brand_map.json')
    if raw then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            CookieVehBrand = data.model2brand or {}
            CookieVehOrder = data.brandOrder or {}
        else

        end
    else

    end

    local rawM = LoadResourceFile('cookie_admin', 'data/major_category.json')
    if rawM then
        local okM, dataM = pcall(json.decode, rawM)
        if okM and type(dataM) == 'table' then
            CookieMajorMap = dataM.cat2major or {}
            CookieMajorOrder = dataM.order or {}
        else

        end
    else

    end

    CookieVehJob = {}
    CookieJobOrder = {}
    local rawJ = LoadResourceFile('cookie_admin', 'data/job_map.json')
    if rawJ then
        local okJ, dataJ = pcall(json.decode, rawJ)
        if okJ and type(dataJ) == 'table' then
            CookieVehJob = dataJ.model2job or {}
            CookieJobOrder = dataJ.jobOrder or {}
        else

        end
    else

    end

    local cnt = 0; for _ in pairs(CookieVehBrand) do cnt = cnt + 1 end
    local jcnt = 0; for _ in pairs(CookieVehJob) do jcnt = jcnt + 1 end

end)

local function cookieVehAuth(src, minLevel)
    local license = getLicense(src)
    if not license then return nil end
    local admin = fetchAdmin(license)
    if not admin then return nil end
    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then cookieVehNotify(src, powerErr, true); return nil end
    if admin.admin_level < minLevel then
        cookieVehNotify(src, '권한이 부족합니다', true); return nil
    end
    return admin
end

RegisterNetEvent('cookie_admin:server:spawnVehicle', function(model, targetServerId)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleSpawnMinLevel)
    if not admin then return end

    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then cookieVehNotify(src, '차량 모델이 비어있습니다', true); return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then

        cookieVehNotify(src, '등록되지 않은 차량입니다', true); return
    end

    local dest, targetName, isTarget = src, nil, false
    if targetServerId then
        local t = tonumber(targetServerId)
        if not t then cookieVehNotify(src, '잘못된 대상입니다', true); return end
        local tp = exports.qbx_core:GetPlayer(t)
        if not tp then cookieVehNotify(src, '대상을 찾을 수 없습니다', true); return end
        dest, isTarget = t, true
        targetName = (tp.PlayerData and tp.PlayerData.name) or GetPlayerName(t) or ('#' .. t)
    end

    local ped = GetPlayerPed(dest)
    if not ped or ped == 0 then cookieVehNotify(src, '대상 캐릭터가 없습니다', true); return end

    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({
            model = model,
            spawnSource = ped,
            warp = not isTarget,
            bucket = GetPlayerRoutingBucket(dest),
        })
    end)
    if not ok or not veh then

        cookieVehNotify(src, '스폰 실패 (모델 확인)', true); return
    end

    pcall(function() exports.qbx_vehiclekeys:GiveKeys(dest, veh) end)

    if isTarget then
        local owner = exports.qbx_core:GetPlayer(dest)
        local ownerCid = owner and owner.PlayerData and owner.PlayerData.citizenid
        if ownerCid then
            pcall(function()
                Entity(veh).state:set('cookieAdminTempOwner', ownerCid, true)
                Entity(veh).state:set('cookieAdminTempOwnerSid', dest, true)
            end)
        end
        cookieVehNotify(src, (vinfo.name or model) .. ' → ' .. targetName .. ' 임시 스폰 완료', false)
        cookieVehNotify(dest, '관리자가 임시 차량을 스폰했습니다: ' .. (vinfo.name or model), false)
    else
        cookieVehNotify(src, (vinfo.name or model) .. ' 스폰 완료', false)
    end

end)


-- ─────────────────────────────────────────────────────────────
-- 접속 중인 플레이어 > 차량 관리
-- 스폰: 차고 DB에는 넣지 않고 대상 명의(키 + 상태 태그)로 월드에 임시 생성
-- 삭제/수리: 대상의 DB 차량 번호판 + 관리자 임시 차량을 월드 전체에서 찾음
-- 지급: cookie_personal_v2 차고 DB에 영구 소유권 등록
-- ─────────────────────────────────────────────────────────────
local TARGET_VEH_FEATURE = {
    spawn = 'veh_spawn',
    delete = 'veh_del',
    repair = 'veh_fix',
    give = 'veh_give',
}
local COOKIE_PERSONAL_GARAGE = 'cookie_personal_v2'

local function cookieNormalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', '')
end

local function cookieTargetVehicleAuth(src, action, targetServerId)
    local featureKey = TARGET_VEH_FEATURE[action]
    if not featureKey then return nil, nil, nil, '잘못된 차량 관리 동작입니다' end

    local license = getLicense(src)
    if not license then return nil, nil, nil, '관리자 식별 정보를 찾을 수 없습니다' end
    local admin = fetchAdmin(license)
    if not admin then return nil, nil, nil, '관리자 권한이 없습니다' end

    local feature = checkFeaturePermission(admin.admin_level, featureKey)
    if not feature then return nil, nil, nil, '해당 차량 관리 권한이 없습니다' end
    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then return nil, nil, nil, powerErr end

    local target = tonumber(targetServerId)
    local canTarget, targetErr = CookieCanTargetAdmin(src, target)
    if not canTarget then return nil, nil, nil, targetErr end
    if not target or not GetPlayerName(target) then return nil, nil, nil, '대상을 찾을 수 없습니다' end
    local tp = exports.qbx_core:GetPlayer(target)
    if not tp or not tp.PlayerData or not tp.PlayerData.citizenid then
        return nil, nil, nil, '대상 시민 정보를 찾을 수 없습니다'
    end

    return admin, target, tp, nil
end

local function cookieWorldVehiclesForCitizen(citizenid)
    local plateSet = {}
    local rows = MySQL.query.await('SELECT plate FROM player_vehicles WHERE citizenid = ?', { citizenid }) or {}
    for _, r in ipairs(rows) do
        local p = cookieNormalizePlate(r.plate)
        if p ~= '' then plateSet[p] = true end
    end

    local found = {}
    local okAll, vehicles = pcall(GetAllVehicles)
    if not okAll or type(vehicles) ~= 'table' then return found end

    for _, veh in ipairs(vehicles) do
        if veh and veh ~= 0 and DoesEntityExist(veh) then
            local plate = cookieNormalizePlate(GetVehicleNumberPlateText(veh))
            local tempOwner = nil
            pcall(function() tempOwner = Entity(veh).state.cookieAdminTempOwner end)
            local persistent = plate ~= '' and plateSet[plate] == true
            local temporary = tempOwner ~= nil and tostring(tempOwner) == tostring(citizenid)
            if persistent or temporary then
                found[#found + 1] = {
                    entity = veh,
                    plate = plate,
                    persistent = persistent,
                    temporary = temporary,
                }
            end
        end
    end
    return found
end

-- 관리자 차량 수리 보완: 소유권 DB에 없는 월드 차량도 대상 시민이
-- 실제 탑승 중이거나 바로 옆에 있는 경우 수리 대상으로 찾는다.
-- 주의: 이 함수는 수리 전용이며 차량 삭제/소유권 변경에는 절대 사용하지 않는다.
local function cookieRepairVehicleNearTarget(target, maxDistance)
    local ped = GetPlayerPed(target)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil, nil end

    local current = GetVehiclePedIsIn(ped, false)
    if current and current ~= 0 and DoesEntityExist(current) then
        return current, '탑승 중'
    end

    local targetCoords = GetEntityCoords(ped)
    if not targetCoords then return nil, nil end
    local targetBucket = GetPlayerRoutingBucket(target)
    local ok, vehicles = pcall(GetAllVehicles)
    if not ok or type(vehicles) ~= 'table' then return nil, nil end

    local closest, distance = nil, maxDistance or 8.0
    for _, veh in ipairs(vehicles) do
        if veh and veh ~= 0 and DoesEntityExist(veh) and GetEntityRoutingBucket(veh) == targetBucket then
            local coords = GetEntityCoords(veh)
            if coords then
                local d = #(targetCoords - coords)
                if d < distance then
                    closest, distance = veh, d
                end
            end
        end
    end
    if closest then return closest, '근처 차량' end
    return nil, nil
end

local function cookieVehicleRegisteredType(model)
    model = tostring(model or ''):lower():gsub('%s', '')
    local limited = MySQL.single.await(
        'SELECT model, label FROM cookie_limited_vehicles WHERE LOWER(model) = ? AND active = 1 LIMIT 1',
        { model })
    if limited then return 'limited', limited.label or model end

    local general = MySQL.single.await(
        'SELECT model, display_name FROM cookie_dealership_vehicles WHERE LOWER(model) = ? AND active = 1 LIMIT 1',
        { model })
    if general then return 'general', general.display_name or model end
    return nil, nil
end

-- COOKIE ADMIN REPAIR V2.1: 허가된 관리자 요청에 대한 대상 클라이언트 근접 수리 결과
-- 기존 차량 소유 DB 및 삭제 로직과 독립. 수리 성공 여부만 안내한다.
local cookieRepairVersion = 'V2.1 (client-nearby fallback)'
local cookieRepairTicket = 0
local cookieRepairRequests = {}

RegisterCommand('cookie_repair_version', function(src)
    if src ~= 0 then return end
    print('[cookie_admin][repair] ' .. cookieRepairVersion .. ' loaded')
end, false)

RegisterNetEvent('cookie_admin:server:repairClientResult', function(ticket, result)
    local src = source
    local key = tonumber(ticket)
    if not key then return end
    local pending = cookieRepairRequests[key]
    if not pending or pending.target ~= src then return end
    cookieRepairRequests[key] = nil
    if GetGameTimer() - pending.startedAt > 15000 then return end

    result = tostring(result or 'unknown')
    local who = pending.targetName or ('#' .. src)
    if result == 'ok' then
        cookieVehNotify(pending.admin, who .. '님 주변 차량 수리를 완료했습니다', false)
    elseif result == 'no_vehicle' then
        if pending.remoteCount > 0 then
            cookieVehNotify(pending.admin, ('%s님 근처 차량은 없지만, 맵상 소유 차량 %d대에 수리 요청을 보냈습니다'):format(who, pending.remoteCount), false)
        else
            cookieVehNotify(pending.admin, who .. '님 근처에 수리할 차량이 없습니다. 대상자가 차량에 타거나 차량 8m 이내에 있어야 합니다.', true)
        end
    elseif result == 'no_control' then
        cookieVehNotify(pending.admin, who .. '님 차량의 네트워크 제어권을 확보하지 못했습니다. 탑승 후 다시 시도하세요.', true)
    else
        cookieVehNotify(pending.admin, who .. '님 차량 수리 응답에 오류가 발생했습니다 (' .. result:sub(1, 24) .. ')', true)
    end
    print(('[cookie_admin][repair] V2.1 admin=%d target=%d result=%s remote=%d'):format(pending.admin, src, result, pending.remoteCount))
end)

RegisterNetEvent('cookie_admin:server:targetVehicleAction', function(action, targetServerId, model)
    local src = source
    action = tostring(action or ''):lower()

    local admin, target, tp, authErr = cookieTargetVehicleAuth(src, action, targetServerId)
    if not admin then
        cookieVehNotify(src, authErr or '차량 관리 권한 확인에 실패했습니다', true)
        return
    end

    local citizenid = tp.PlayerData.citizenid
    local targetName = nil
    local okNick, nick = pcall(function() return exports.cookie_core:getNickname(target) end)
    if okNick and type(nick) == 'string' and nick ~= '' then targetName = nick end
    targetName = targetName or tp.PlayerData.name or GetPlayerName(target) or ('#' .. target)

    if action == 'spawn' then
        model = tostring(model or ''):lower():gsub('%s', '')
        if model == '' then return cookieVehNotify(src, '차량을 선택하세요', true) end
        local vinfo = exports.qbx_core:GetVehiclesByName(model)
        if not vinfo then return cookieVehNotify(src, '등록되지 않은 차량 모델입니다', true) end

        local ped = GetPlayerPed(target)
        if not ped or ped == 0 then return cookieVehNotify(src, '대상 캐릭터가 없습니다', true) end
        local okSpawn, netId, veh = pcall(function()
            return qbx.spawnVehicle({
                model = model,
                spawnSource = ped,
                warp = false,
                bucket = GetPlayerRoutingBucket(target),
            })
        end)
        if not okSpawn or not veh then return cookieVehNotify(src, '차량 스폰에 실패했습니다', true) end

        -- DB 소유 차량으로 만들지는 않지만, 세션 동안 대상 명의 차량으로 추적하고 키를 준다.
        pcall(function()
            Entity(veh).state:set('cookieAdminTempOwner', citizenid, true)
            Entity(veh).state:set('cookieAdminTempOwnerSid', target, true)
        end)
        pcall(function() exports.qbx_vehiclekeys:GiveKeys(target, veh) end)

        cookieVehNotify(src, ('%s님 명의로 %s 임시 스폰 완료'):format(targetName, vinfo.name or model), false)
        cookieVehNotify(target, ('관리자가 임시 차량을 스폰했습니다: %s'):format(vinfo.name or model), false)
        return
    end

    if action == 'give' then
        return cookieVehNotify(src, '차량 지급은 지급 관리 > 우편 발송을 이용해주세요', true)
    end

    -- 삭제는 기존처럼 대상이 소유한 차량만 조회한다. 수리는 탑승/근처 차량도 허용한다.
    if action == 'delete' then
        local world = cookieWorldVehiclesForCitizen(citizenid)
        if #world == 0 then
            return cookieVehNotify(src, targetName .. '님의 맵상 소유 차량을 찾을 수 없습니다', true)
        end
        local deleted, restored = 0, {}
        for _, item in ipairs(world) do
            if item.entity and DoesEntityExist(item.entity) then
                if item.persistent and item.plate ~= '' then restored[item.plate] = true end
                local okDel = pcall(DeleteEntity, item.entity)
                if okDel then deleted = deleted + 1 end
            end
        end
        -- 엔티티만 삭제하고 소유권은 지우지 않는다. 영구 차량은 차고 보관 상태로 돌려둔다.
        for plate in pairs(restored) do
            MySQL.update.await([[
                UPDATE player_vehicles SET state = 1
                WHERE citizenid = ? AND UPPER(REPLACE(plate, ' ', '')) = ?
            ]], { citizenid, plate })
        end
        cookieVehNotify(src, ('%s님의 맵상 차량 %d대를 삭제했습니다'):format(targetName, deleted), false)
        cookieVehNotify(target, ('관리자에 의해 맵상 차량 %d대가 정리되었습니다'):format(deleted), false)
        return
    end

    if action == 'repair' then
        -- 서버 GetAllVehicles()에서 차량을 찾지 못해도 실패 처리하지 않는다.
        -- 대상자의 클라이언트는 실제 스트리밍된 탑승/근접 차량을 찾을 수 있다.
        local netIds, seen = {}, {}
        local okWorld, world = pcall(cookieWorldVehiclesForCitizen, citizenid)
        if okWorld and type(world) == 'table' then
            for _, item in ipairs(world) do
                local veh = item.entity
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                    local okNet, netId = pcall(NetworkGetNetworkIdFromEntity, veh)
                    if okNet and type(netId) == 'number' and netId > 0 and not seen[netId] then
                        seen[netId] = true
                        netIds[#netIds + 1] = netId
                    end
                end
            end
        else
            print(('[cookie_admin][repair] owner DB/world scan unavailable target=%s; client repair fallback will run'):format(target))
        end

        -- 소유 차량이 서버 네트워크 목록에 있으면 기존 방식도 유지한다.
        if #netIds > 0 then
            TriggerClientEvent('cookie_admin:client:repairVehicles', -1, netIds)
        end

        cookieRepairTicket = cookieRepairTicket + 1
        local ticket = cookieRepairTicket
        cookieRepairRequests[ticket] = {
            admin = src, target = target, targetName = targetName,
            remoteCount = #netIds, startedAt = GetGameTimer(),
        }
        TriggerClientEvent('cookie_admin:client:repairNearestForAdmin', target, ticket, 8.0)
        cookieVehNotify(src, ('%s님 차량 수리를 확인 중입니다...'):format(targetName), false)
        print(('[cookie_admin][repair] V2.1 request admin=%s target=%s remote=%d ticket=%d'):format(src, target, #netIds, ticket))

        SetTimeout(12000, function()
            local pending = cookieRepairRequests[ticket]
            if not pending then return end
            cookieRepairRequests[ticket] = nil
            if pending.admin and GetPlayerName(pending.admin) then
                cookieVehNotify(pending.admin, '수리 결과 응답이 없습니다. 대상자가 접속 중인지, 최신 client/main.lua가 적용됐는지 확인하세요.', true)
            end
        end)
        return
    end
end)


local function CookieGetCitizenVehicleCatalog()
    local rows = MySQL.query.await([[
        SELECT id, model, display_name, price, category, spec, image, active
        FROM cookie_dealership_vehicles
        WHERE active = 1
        ORDER BY sort_order, id
    ]], {}) or {}

    local imageMap = {}
    local okImg, imgs = pcall(function()
        return MySQL.query.await('SELECT model, image FROM cookie_vehicle_image', {})
    end)
    if okImg and imgs then
        for _, r in ipairs(imgs) do
            imageMap[tostring(r.model):lower()] = r.image
        end
    end

    for _, r in ipairs(rows) do
        r.model = tostring(r.model or ''):lower()
        r.image = imageMap[r.model] or r.image
    end
    return rows
end

exports('GetCitizenVehicleCatalog', CookieGetCitizenVehicleCatalog)

local function cookiePushExhibitList(src)
    -- 핵심 목록은 이미지 테이블과 JOIN하지 않는다.
    -- 이미지 테이블 문제 하나 때문에 전시 목록 전체가 사라지는 현상을 방지.
    local rows = MySQL.query.await([[
        SELECT id, model, brand, display_name, price, category, spec, image,
               sort_order, active, added_by
        FROM cookie_dealership_vehicles
        WHERE active = 1
        ORDER BY sort_order, id
    ]], {}) or {}

    local limited = MySQL.query.await([[
        SELECT id, model, label, active
        FROM cookie_limited_vehicles
        WHERE active = 1
        ORDER BY label, id
    ]], {}) or {}

    local factions = MySQL.query.await([[
        SELECT id, name, faction_key, faction_type, garage_key
        FROM cookie_faction
        WHERE is_active = 1
        ORDER BY id
    ]], {}) or {}

    for _, f in ipairs(factions) do
        f.shop = MySQL.query.await([[
            SELECT id, model, label, price, min_grade, active
            FROM cookie_faction_shop
            WHERE faction_id = ? AND active = 1
            ORDER BY price, id
        ]], { f.id }) or {}
    end

    -- 저장된 차량 이미지는 별도 조회 후 합친다.
    local imageMap = {}
    local okImg, images = pcall(function()
        return MySQL.query.await('SELECT model, image FROM cookie_vehicle_image', {})
    end)
    if okImg and images then
        for _, r in ipairs(images) do
            imageMap[tostring(r.model):lower()] = r.image
        end
    end

    for _, r in ipairs(rows) do
        r.image = imageMap[tostring(r.model):lower()] or r.image
    end
    for _, r in ipairs(limited) do
        r.image = imageMap[tostring(r.model):lower()]
    end
    for _, f in ipairs(factions) do
        for _, r in ipairs(f.shop or {}) do
            r.image = imageMap[tostring(r.model):lower()]
        end
    end

    TriggerClientEvent('cookie_admin:client:exhibitList', src, rows, limited, factions)
end


-- 일반 차고 전용 목록 요청.
-- F3 전시 관리가 정상 동작하는 cookie_admin 서버가 직접 응답하므로
-- cookie_safezone 서버 상태와 무관하게 시민차량 목록을 전달한다.
RegisterNetEvent('cookie_admin:server:requestPublicGarageCatalog', function()
    local src = source

    local rows = MySQL.query.await([[
        SELECT id, model, display_name, price, category, spec, image
        FROM cookie_dealership_vehicles
        WHERE active = 1
        ORDER BY sort_order, id
    ]], {}) or {}

    local imageMap = {}
    local okImg, imgs = pcall(function()
        return MySQL.query.await('SELECT model, image FROM cookie_vehicle_image', {})
    end)
    if okImg and imgs then
        for _, r in ipairs(imgs) do
            imageMap[tostring(r.model or ''):lower()] = r.image
        end
    end

    for _, r in ipairs(rows) do
        local model = tostring(r.model or ''):lower()
        r.model = model
        r.image = imageMap[model] or r.image
    end

    TriggerClientEvent('cookie_safezone:client:generalGarageCatalog', src, rows)
end)

RegisterNetEvent('cookie_admin:server:requestExhibitList', function()
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    cookiePushExhibitList(src)
end)

RegisterNetEvent('cookie_admin:server:exhibitAdd', function(data)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    if type(data) ~= 'table' then return end

    local model = tostring(data.model or ''):gsub('%s', ''):lower()
    if model == '' then cookieVehNotify(src, '차량 모델이 비어있습니다', true); return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then cookieVehNotify(src, '등록되지 않은 차량입니다', true); return end

    local brand = tostring(data.brand or CookieVehBrand[model] or '기타')
    local displayName = tostring(data.displayName or vinfo.name or model)
    local price = math.floor(tonumber(data.price) or vinfo.price or 0)
    if price < 0 then price = 0 end
    local category = tostring(data.category or vinfo.category or '')
    local spec = data.spec and tostring(data.spec) or nil
    local image = data.image and tostring(data.image) or nil
    if image == '' then image = nil end
    -- data URI 또는 http(s) 이미지 주소만 허용
    if image and not image:match('^data:image/') and not image:match('^https?://') then
        image = nil
    end
    local sortOrder = math.floor(tonumber(data.sortOrder) or 0)

    local okSave, saveErr = pcall(function()
        MySQL.query.await([[
            INSERT INTO cookie_dealership_vehicles (model, brand, display_name, price, category, spec, image, sort_order, active, added_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
            ON DUPLICATE KEY UPDATE brand=VALUES(brand), display_name=VALUES(display_name), price=VALUES(price),
                category=VALUES(category), spec=VALUES(spec), image=COALESCE(VALUES(image), image),
                sort_order=VALUES(sort_order), active=1
        ]], { model, brand, displayName, price, category, spec, image, sortOrder, admin.admin_name })
    end)

    if not okSave then
        print(('[cookie_admin] 시민차량 저장 실패 model=%s error=%s'):format(model, tostring(saveErr)))
        cookieVehNotify(src, '시민차량 DB 저장에 실패했습니다. 서버 콘솔을 확인하세요.', true)
        return
    end

    cookieVehNotify(src, displayName .. ' 시민차량 등록 완료', false)
    cookiePushExhibitList(src)
end)

RegisterNetEvent('cookie_admin:server:limitedVehicleSave', function(data)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin or type(data) ~= 'table' then return end

    local model = tostring(data.model or ''):gsub('%s', ''):lower()
    if model == '' or not exports.qbx_core:GetVehiclesByName(model) then
        cookieVehNotify(src, '등록되지 않은 차량입니다', true)
        return
    end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    local label = tostring(data.label or (vinfo and vinfo.name) or model)

    MySQL.query.await([[
        INSERT INTO cookie_limited_vehicles (model, label, active, added_by)
        VALUES (?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE label=VALUES(label), active=1, added_by=VALUES(added_by)
    ]], { model, label, admin.admin_name })

    cookieVehNotify(src, label .. ' 한정 차량 등록 완료', false)
    cookiePushExhibitList(src)
end)

RegisterNetEvent('cookie_admin:server:limitedVehicleDelete', function(id)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    id = tonumber(id)
    if not id then return end
    MySQL.query.await('DELETE FROM cookie_limited_vehicles WHERE id = ?', { id })
    cookieVehNotify(src, '한정 차량에서 제거했습니다', false)
    cookiePushExhibitList(src)
end)

RegisterNetEvent('cookie_admin:server:exhibitRemove', function(data)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    if type(data) ~= 'table' then return end

    local ref
    if data.id then
        ref = MySQL.single.await('SELECT id, model FROM cookie_dealership_vehicles WHERE id = ?', { tonumber(data.id) })
    elseif data.model then
        ref = MySQL.single.await('SELECT id, model FROM cookie_dealership_vehicles WHERE model = ?', { tostring(data.model):lower() })
    end
    if not ref then cookieVehNotify(src, '해당 전시 항목이 없습니다', true); return end

    MySQL.update.await('DELETE FROM cookie_dealership_vehicles WHERE id = ?', { ref.id })

    cookieVehNotify(src, '전시 목록에서 삭제했습니다', false)

    cookiePushExhibitList(src)
end)

local LSPD_GARAGE_NAME = 'cookie_lspd'
local LSPD_FLEET_CID = 'LSPD_FLEET'

local function cookiePushLspdFleet(src)
    local rows = MySQL.query.await(
        'SELECT id, vehicle AS model, plate FROM player_vehicles WHERE garage = ? ORDER BY vehicle, id',
        { LSPD_GARAGE_NAME }
    ) or {}

    for _, r in ipairs(rows) do
        local vinfo = exports.qbx_core:GetVehiclesByName(r.model)
        r.name = vinfo and vinfo.name or r.model
        r.brand = (vinfo and CookieVehBrand[r.model]) or CookieVehBrand[r.model] or '기타'
    end
    TriggerClientEvent('cookie_admin:client:lspdFleet', src, rows)
end

RegisterNetEvent('cookie_admin:server:requestLspdFleet', function()
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    cookiePushLspdFleet(src)
end)

RegisterNetEvent('cookie_admin:server:lspdFleetAdd', function(model)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then cookieVehNotify(src, '차량 모델이 비어있습니다', true); return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then cookieVehNotify(src, '등록되지 않은 차량입니다', true); return end

    local ok, vid = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = LSPD_FLEET_CID,
            garage = LSPD_GARAGE_NAME,
        })
    end)
    if not ok or not vid then

        cookieVehNotify(src, 'LSPD 차고 추가 실패', true); return
    end

    cookieVehNotify(src, ('LSPD 차고에 %s 추가'):format(vinfo.name or model), false)

    cookiePushLspdFleet(src)
end)

RegisterNetEvent('cookie_admin:server:lspdFleetRemove', function(vehicleId)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    local id = tonumber(vehicleId)
    if not id then return end

    local ref = MySQL.single.await('SELECT id, vehicle FROM player_vehicles WHERE id = ? AND garage = ?', { id, LSPD_GARAGE_NAME })
    if not ref then cookieVehNotify(src, '해당 차고 차량이 없습니다', true); return end
    MySQL.query.await('DELETE FROM player_vehicles WHERE id = ? AND garage = ?', { id, LSPD_GARAGE_NAME })

    cookieVehNotify(src, 'LSPD 차고에서 제거했습니다', false)

    cookiePushLspdFleet(src)
end)

RegisterNetEvent('cookie_admin:server:lspdFleetSeed', function()
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleExhibitMinLevel)
    if not admin then return end
    local lineup = Config.LspdLineup or {}

    local existing = {}
    local rows = MySQL.query.await('SELECT vehicle FROM player_vehicles WHERE garage = ?', { LSPD_GARAGE_NAME }) or {}
    for _, r in ipairs(rows) do existing[tostring(r.vehicle):lower()] = true end

    local added, skipped, bad = 0, 0, {}
    for _, m in ipairs(lineup) do
        local model = tostring(m):lower()
        if existing[model] then
            skipped = skipped + 1
        elseif not exports.qbx_core:GetVehiclesByName(model) then
            bad[#bad + 1] = model
        else
            local ok, vid = pcall(function()
                return exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = LSPD_FLEET_CID, garage = LSPD_GARAGE_NAME })
            end)
            if ok and vid then added = added + 1; existing[model] = true else bad[#bad + 1] = model end
        end
    end

    local msg = ('라인업 등록: 추가 %d · 기존 %d'):format(added, skipped)
    if #bad > 0 then msg = msg .. ' · 실패 ' .. #bad .. '(' .. table.concat(bad, ',') .. ')' end
    cookieVehNotify(src, msg, #bad > 0)

    cookiePushLspdFleet(src)
end)

local function cookieDeleteTestVeh(src)
    local veh = CookieTestVeh[src]
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    CookieTestVeh[src] = nil
end

RegisterNetEvent('cookie_admin:server:testSpawnVehicle', function(model)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleSpawnMinLevel)
    if not admin then return end
    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then cookieVehNotify(src, '차량 모델이 비어있습니다', true); return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then cookieVehNotify(src, '등록되지 않은 차량입니다', true); return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local old = CookieTestVeh[src]
    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({ model = model, spawnSource = ped, warp = true, bucket = GetPlayerRoutingBucket(src) })
    end)
    if not ok or not veh then

        cookieVehNotify(src, '스폰 실패 (모델 확인)', true); return
    end
    CookieTestVeh[src] = veh
    if old and DoesEntityExist(old) then DeleteEntity(old) end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)

    cookieVehNotify(src, (vinfo.name or model) .. ' 테스트 스폰', false)
end)

RegisterNetEvent('cookie_admin:server:returnTestVehicle', function()
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleSpawnMinLevel)
    if not admin then return end
    if CookieTestVeh[src] then
        cookieDeleteTestVeh(src)
        cookieVehNotify(src, '테스트 차량 반납 완료', false)
    else
        cookieVehNotify(src, '반납할 테스트 차량이 없습니다', true)
    end
end)

AddEventHandler('playerDropped', function()
    cookieDeleteTestVeh(source)
end)

local function cookieSweepPreviewPad()
    local pad = Config.VehiclePreviewPad
    local center = vector3(pad.x + 0.0, pad.y + 0.0, pad.z + 0.0)
    local ok, vehs = pcall(GetAllVehicles)
    if not ok or type(vehs) ~= 'table' then return end
    for i = 1, #vehs do
        local v = vehs[i]
        if v and v ~= 0 and DoesEntityExist(v) and #(GetEntityCoords(v) - center) < 45.0 then
            DeleteEntity(v)
        end
    end
end

RegisterNetEvent('cookie_admin:server:previewSpawnVehicle', function(model)
    local src = source
    local admin = cookieVehAuth(src, Config.VehicleSpawnMinLevel)
    if not admin then return end
    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then cookieVehNotify(src, '등록되지 않은 차량입니다', true); return end
    cookieSweepPreviewPad()
    CookiePreviewVeh[src] = nil
    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({ model = model, spawnSource = Config.VehiclePreviewPad, bucket = GetPlayerRoutingBucket(src) })
    end)
    if not ok or not veh then

        cookieVehNotify(src, '프리뷰 스폰 실패 (모델 확인)', true); return
    end
    CookiePreviewVeh[src] = veh

    TriggerClientEvent('cookie_admin:client:previewVeh', src, netId, vinfo.name)
end)

RegisterNetEvent('cookie_admin:server:facPreviewVehicle', function(model)
    local src = source
    local m = CookieFactionMemberOf and CookieFactionMemberOf(src)
    if not m or not (m.isLeader or m.isOfficer) then

        return
    end

    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then cookieVehNotify(src, '등록되지 않은 차량입니다', true); return end

    cookieSweepPreviewPad()
    CookiePreviewVeh[src] = nil
    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({ model = model, spawnSource = Config.VehiclePreviewPad, bucket = GetPlayerRoutingBucket(src) })
    end)
    if not ok or not veh then

        cookieVehNotify(src, '프리뷰 스폰 실패', true); return
    end
    CookiePreviewVeh[src] = veh
    TriggerClientEvent('cookie_admin:client:previewVeh', src, netId, vinfo.name)
end)

local function cookieDeletePreviewVeh(src)
    local veh = CookiePreviewVeh[src]
    if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
    CookiePreviewVeh[src] = nil
end

RegisterNetEvent('cookie_admin:server:cleanupPreviewVehicle', function()
    cookieDeletePreviewVeh(source)
end)

AddEventHandler('playerDropped', function()
    cookieDeletePreviewVeh(source)
end)

CookieTestDrive = {}
local TESTDRIVE_BUCKET_BASE = 50000

local function cookieEndTestDrive(src)
    local td = CookieTestDrive[src]
    if not td then return end
    if td.veh and DoesEntityExist(td.veh) then DeleteEntity(td.veh) end
    SetPlayerRoutingBucket(src, 0)
    CookieTestDrive[src] = nil
end

RegisterNetEvent('cookie_admin:server:startTestDrive', function(model)
    local src = source
    if not getLicense(src) then return end
    if CookieTestDrive[src] then return end
    model = tostring(model or ''):gsub('%s', ''):lower()
    if model == '' then return end
    local vinfo = exports.qbx_core:GetVehiclesByName(model)
    if not vinfo then TriggerClientEvent('cookie_admin:client:notify', src, '등록되지 않은 차량입니다', true); return end

    local bucket = TESTDRIVE_BUCKET_BASE + src
    SetPlayerRoutingBucket(src, bucket)
    SetRoutingBucketPopulationEnabled(bucket, false)

    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({ model = model, spawnSource = Config.TestDriveTrack, warp = false, bucket = bucket })
    end)
    if not ok or not veh then
        SetPlayerRoutingBucket(src, 0)

        TriggerClientEvent('cookie_admin:client:notify', src, '시승 차량 스폰 실패', true); return
    end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)
    CookieTestDrive[src] = { bucket = bucket, veh = veh }

    TriggerClientEvent('cookie_admin:client:startTestDrive', src, netId, vinfo.name)
end)

RegisterNetEvent('cookie_admin:server:endTestDrive', function()
    cookieEndTestDrive(source)
end)

AddEventHandler('playerDropped', function()
    cookieEndTestDrive(source)
end)


-- 시스템 관리 > 낚시 (LV5)
RegisterNetEvent('cookie_admin:server:requestFishingSystem', function()
    local src = source
    local lv = 0
    pcall(function() lv = tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0 end)
    if lv < 5 then return end

    local ok, data = pcall(function()
        return exports.cookie_fishing:getGradeSettings()
    end)
    if not ok or not data then
        TriggerClientEvent('cookie_admin:client:notify', src, '낚시 시스템 설정을 불러오지 못했습니다', true)
        return
    end
    TriggerClientEvent('cookie_admin:client:fishingSystemData', src, data)
end)

RegisterNetEvent('cookie_admin:server:saveFishingSystem', function(data)
    local src = source
    local lv = 0
    pcall(function() lv = tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0 end)
    if lv < 5 then return end

    local ok, saved, err = pcall(function()
        return exports.cookie_fishing:saveGradeSettings(src, data)
    end)
    if not ok then
        TriggerClientEvent('cookie_admin:client:notify', src, '낚시 설정 저장 중 오류가 발생했습니다', true)
        return
    end
    if not saved then
        TriggerClientEvent('cookie_admin:client:notify', src, err or '저장하지 못했습니다', true)
        return
    end

    TriggerClientEvent('cookie_admin:client:notify', src, '낚시 등급 확률을 저장했습니다', false)
    TriggerClientEvent('cookie_admin:client:fishingSystemData', src, exports.cookie_fishing:getGradeSettings())
end)

print('^2[cookie_admin]^7 admin server ready · V0.7.2')


RegisterNetEvent('cookie_admin:server:adminJail', function(data)
    local src=source
    data=type(data)=='table' and data or {}

    local license=getLicense(src)
    if not license then return end

    local admin=fetchAdmin(license)
    if not admin then return end
    local canPower, powerErr = CookieCanUseAdminPower(src, admin)
    if not canPower then
        return TriggerClientEvent('cookie_admin:client:notify',src,powerErr,true)
    end

    local feature=select(1,checkFeaturePermission(admin.admin_level,'jail'))
    if not feature then
        return TriggerClientEvent('cookie_admin:client:notify',src,'관리자 구금 권한이 없습니다',true)
    end

    local target=tonumber(data.targetServerId)
    local minutes=math.max(1,math.min(1440,math.floor(tonumber(data.minutes) or 10)))
    local reason=tostring(data.reason or ''):gsub('[%c]',' '):gsub('^%s+',''):gsub('%s+$',''):sub(1,200)

    if #reason<2 then
        return TriggerClientEvent('cookie_admin:client:notify',src,'구금 사유를 입력해주세요',true)
    end
    if not target or not GetPlayerName(target) then
        return TriggerClientEvent('cookie_admin:client:notify',src,'대상을 찾을 수 없습니다',true)
    end
    local canTarget,targetErr=CookieCanTargetAdmin(src,target)
    if not canTarget then
        return TriggerClientEvent('cookie_admin:client:notify',src,targetErr,true)
    end
    if GetResourceState('cookie_police')~='started' then
        return TriggerClientEvent('cookie_admin:client:notify',src,'구금 시스템이 실행 중이 아닙니다',true)
    end

    local tp=exports.qbx_core:GetPlayer(target)
    if not tp or not tp.PlayerData then
        return TriggerClientEvent('cookie_admin:client:notify',src,'대상 캐릭터를 찾을 수 없습니다',true)
    end

    local cid=tostring(tp.PlayerData.citizenid or '')
    local targetName=getCharName(target)

    MySQL.update.await(
        "UPDATE cookie_police_detention_active SET active=0,released_at=NOW(),released_by='ADMIN_REPLACED' WHERE citizenid=? AND active=1",
        {cid}
    )

    MySQL.insert.await([[
        INSERT INTO cookie_police_detention_active
          (faction_id,citizenid,target_name,charge,release_at,officer_citizenid,officer_name)
        VALUES
          (0,?,?,?,DATE_ADD(NOW(),INTERVAL ? SECOND),NULL,?)
    ]],{
        cid,targetName,reason,minutes*60,tostring(admin.admin_name or '관리자')
    })

    pcall(function() exports.cookie_police:ForceSetCuffed(target,false) end)
    TriggerClientEvent('cookie_police:client:setDetained',target,minutes*60,reason,true)

    pcall(function()
        local tgobun=nil
        pcall(function() tgobun=exports.cookie_core:getGobun(target) end)

        MySQL.insert.await([[
            INSERT INTO cookie_admin_punishment_log
              (action,admin_name,admin_license,admin_level,target_server,target_gobun,
               target_cid,target_name,target_license,reason,minutes)
            VALUES ('jail',?,?,?,?,?,?,?,?,?,?)
        ]],{
            admin.admin_name,license,admin.admin_level,target,
            tonumber(tgobun),cid,targetName,getLicense(target),reason,minutes
        })
    end)

    cookieAdminLog('admin_detention','관리자 구금',reason,{
        {name='구금시간',value=tostring(minutes)..'분',inline=true},
        {name='처리 관리자',value=tostring(admin.admin_name or '-'),inline=true},
    },{actorSrc=src,targetSrc=target,actorLabel='관리자',targetLabel='구금 대상',eventKey='admin_detention'})

    TriggerClientEvent('cookie_admin:client:notify',src,('%s님을 %d분 구금했습니다.'):format(targetName,minutes),false)
    TriggerClientEvent('cookie_admin:client:notify',target,('관리자에 의해 %d분 구금되었습니다. 사유: %s'):format(minutes,reason),true)
end)


RegisterNetEvent('cookie_admin:server:driverLicenseAction',function(data)
    local src=source
    data=type(data)=='table' and data or {}

    local target=tonumber(data.targetServerId)
    local action=tostring(data.action or ''):lower()
    local reason=trimText(data.reason,300)
    local minutes=math.floor(tonumber(data.minutes) or 0)

    if action~='suspend' and action~='restore' then return end
    if not target or not GetPlayerName(target) then
        return TriggerClientEvent('cookie_admin:client:notify',src,'대상이 접속 중이 아닙니다',true)
    end

    local license=getLicense(src)
    local admin=license and fetchAdmin(license) or nil
    if not admin then return end
    local canPower,powerErr=CookieCanUseAdminPower(src,admin)
    if not canPower then
        return TriggerClientEvent('cookie_admin:client:notify',src,powerErr,true)
    end
    local canTarget,targetErr=CookieCanTargetAdmin(src,target)
    if not canTarget then
        return TriggerClientEvent('cookie_admin:client:notify',src,targetErr,true)
    end

    local featureKey=action=='suspend' and 'license_suspend' or 'license_restore'
    local feature,err=checkFeaturePermission(tonumber(admin.admin_level) or 0,featureKey)
    if not feature then
        return TriggerClientEvent('cookie_admin:client:notify',src,err or '권한이 없습니다',true)
    end

    if GetResourceState('cookie_license')~='started' then
        return TriggerClientEvent('cookie_admin:client:notify',src,'운전면허 시스템이 실행 중이 아닙니다',true)
    end

    local targetPlayer=exports.qbx_core:GetPlayer(target)
    local cid=targetPlayer and targetPlayer.PlayerData and targetPlayer.PlayerData.citizenid
    if not cid then
        return TriggerClientEvent('cookie_admin:client:notify',src,'대상 캐릭터를 찾을 수 없습니다',true)
    end

    local actorPayload={
        source=src,
        type='admin',
        name=tostring(admin.admin_name or GetPlayerName(src) or '관리자'),
        faction='관리자'
    }

    if action=='suspend' then
        if minutes<1 or minutes>525600 then
            return TriggerClientEvent('cookie_admin:client:notify',src,'면허 정지시간은 1~525600분입니다',true)
        end
        if #reason<2 then
            return TriggerClientEvent('cookie_admin:client:notify',src,'정지 사유를 2자 이상 입력하세요',true)
        end

        local ok,result=exports.cookie_license:SuspendByCitizenId(
            cid,minutes,reason,actorPayload
        )
        if not ok then
            return TriggerClientEvent('cookie_admin:client:notify',src,tostring(result or '면허 정지 실패'),true)
        end

        TriggerClientEvent('cookie_admin:client:notify',src,
            ('운전면허를 %d분 정지했습니다.'):format(minutes),false)
        return
    end

    if #reason<2 then
        return TriggerClientEvent('cookie_admin:client:notify',src,'정지 해제 사유를 2자 이상 입력하세요',true)
    end

    local ok,result,message=exports.cookie_license:RestoreByCitizenId(
        cid,reason,actorPayload
    )
    if not ok then
        return TriggerClientEvent('cookie_admin:client:notify',src,tostring(result or '면허 정지 해제 실패'),true)
    end

    TriggerClientEvent('cookie_admin:client:notify',src,
        tostring(message or '운전면허 정지를 해제했습니다.'),false)
end)


-- 좌표 관리 > 낚시/광산 출현 설정 안정화 중계 (V1.5.6)
local function zoneAdminLevel(src)
    local lv=0;pcall(function() lv=tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0 end);return lv
end
RegisterNetEvent('cookie_admin:server:requestFishingZoneSettings',function(zoneId)
    local src=source
    if zoneAdminLevel(src)<5 then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.') end
    if GetResourceState('cookie_fishing')~='started' then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'cookie_fishing 리소스가 실행 중이 아닙니다.') end
    -- 중요: getZoneSettings 내부에서 oxmysql.await를 사용하므로 pcall로 감싸지 않는다.
    local data,err=exports.cookie_fishing:getZoneSettings(src,tonumber(zoneId))
    if not data then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,tostring(err or '어종 설정 데이터 없음')) end
    TriggerClientEvent('cookie_admin:client:fishingZoneSettingsData',src,data)
end)
RegisterNetEvent('cookie_admin:server:saveFishingZoneSettings',function(data)
    local src=source
    if zoneAdminLevel(src)<5 then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.') end
    if GetResourceState('cookie_fishing')~='started' then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'cookie_fishing 리소스가 실행 중이 아닙니다.') end
    local saved,res=exports.cookie_fishing:saveZoneSettings(src,data or {})
    if not saved then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,tostring(res or '어종 설정 저장 실패')) end
    TriggerClientEvent('cookie_admin:client:fishingZoneSettingsData',src,res or {})
    TriggerClientEvent('cookie_admin:client:notify',src,'낚시 포인트 출현 어종 설정을 저장했습니다',false)
end)
RegisterNetEvent('cookie_admin:server:requestMiningZoneSettings',function(zoneId)
    local src=source
    if zoneAdminLevel(src)<5 then return TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.') end
    if GetResourceState('cookie_mining')~='started' then return TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'cookie_mining 리소스가 실행 중이 아닙니다.') end
    local data,err=exports.cookie_mining:getZoneSettings(src,tonumber(zoneId))
    if not data then return TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,tostring(err or '광물 설정 데이터 없음')) end
    TriggerClientEvent('cookie_admin:client:miningZoneSettingsData',src,data)
end)
RegisterNetEvent('cookie_admin:server:saveMiningZoneSettings',function(data)
    local src=source
    if zoneAdminLevel(src)<5 then return TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.') end
    if GetResourceState('cookie_mining')~='started' then return TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,'cookie_mining 리소스가 실행 중이 아닙니다.') end
    local saved,res=exports.cookie_mining:saveZoneSettings(src,data or {})
    if not saved then return TriggerClientEvent('cookie_admin:client:miningZoneSettingsError',src,tostring(res or '광물 설정 저장 실패')) end
    TriggerClientEvent('cookie_admin:client:miningZoneSettingsData',src,res or {})
    TriggerClientEvent('cookie_admin:client:notify',src,'광산 출현 광물 설정을 저장했습니다',false)
end)

-- 시스템 관리 > 광산 (LV5)
RegisterNetEvent('cookie_admin:server:requestMiningSystem', function()
    local src = source
    local lv = 0
    pcall(function() lv = tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0 end)
    if lv < 5 then
        TriggerClientEvent('cookie_admin:client:miningSystemError', src, '시스템 관리 권한(LV5)이 필요합니다')
        return
    end
    if GetResourceState('cookie_mining') ~= 'started' then
        TriggerClientEvent('cookie_admin:client:miningSystemError', src, 'cookie_mining 리소스가 실행 중이 아닙니다')
        return
    end
    local data, err = exports.cookie_mining:getSystemSettings(src)
    if not data then
        TriggerClientEvent('cookie_admin:client:notify', src, '광산 시스템 설정을 불러오지 못했습니다', true)
        TriggerClientEvent('cookie_admin:client:miningSystemError', src, tostring(err or '설정 데이터 없음'))
        return
    end
    TriggerClientEvent('cookie_admin:client:miningSystemData', src, data)
end)

RegisterNetEvent('cookie_admin:server:saveMiningSystem', function(data)
    local src = source
    local lv = 0
    pcall(function() lv = tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0 end)
    if lv < 5 then return TriggerClientEvent('cookie_admin:client:notify', src, '시스템 관리 권한(LV5)이 필요합니다', true) end
    if GetResourceState('cookie_mining') ~= 'started' then return TriggerClientEvent('cookie_admin:client:notify', src, 'cookie_mining 리소스가 실행 중이 아닙니다', true) end
    local saved, result = exports.cookie_mining:saveSystemSettings(src, data or {})
    if not saved then return TriggerClientEvent('cookie_admin:client:notify', src, tostring(result or '저장하지 못했습니다'), true) end
    TriggerClientEvent('cookie_admin:client:miningSystemData', src, result or {})
    TriggerClientEvent('cookie_admin:client:notify', src, '광산 시스템 설정을 저장했습니다', false)
end)

-- ─────────────────────────────────────────────────────────────
-- V1.5.9 HARD FIX: F3 낚시 포인트 어종 설정 DB 직접 처리
-- ─────────────────────────────────────────────────────────────
local F3_FISH_SPECIES_V159 = {
    { key='bungeo', label='붕어', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=1.0, max=3.0, img='fish_bungeo.png', w=1.0 },
    { key='ingeo', label='잉어', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=1.0, max=4.0, img='fish_ingeo.png', w=1.0 },
    { key='michuraji', label='미꾸라지', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.2, max=0.5, img='fish_michuraji.png', w=1.0 },
    { key='megi', label='메기', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=1.5, max=6.0, img='fish_megi.png', w=1.0 },
    { key='bluegill', label='블루길', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.3, max=1.2, img='fish_bluegill.png', w=1.0 },
    { key='bingeo', label='빙어', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.05, max=0.2, img='fish_bingeo.png', w=1.0 },
    { key='bass', label='배스', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=1.0, max=5.0, img='fish_bass.png', w=1.0 },
    { key='bulgasari', label='불가사리', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.2, max=0.8, img='fish_bulgasari.png', w=1.0 },
    { key='haepari', label='해파리', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=1.0, max=5.0, img='fish_haepari.png', w=1.0 },
    { key='jwichi', label='쥐치', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.5, max=2.0, img='fish_jwichi.png', w=1.0 },
    { key='euneo', label='은어', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.2, max=0.8, img='fish_euneo.png', w=1.0 },
    { key='byeongeo', label='병어', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=0.5, max=2.0, img='fish_byeongeo.png', w=1.0 },
    { key='galchi', label='갈치', grade='basic', gradeLabel='기본', gradeColor='#74c69d', min=1.0, max=4.0, img='fish_galchi.png', w=1.0 },
    { key='noraemi', label='노래미', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.5, max=2.5, img='fish_noraemi.png', w=1.0 },
    { key='urak', label='우럭', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=1.0, max=4.0, img='fish_urak.png', w=1.0 },
    { key='gwangeo', label='광어', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=1.5, max=6.0, img='fish_gwangeo.png', w=1.0 },
    { key='jjukkumi', label='쭈꾸미', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.2, max=0.8, img='fish_jjukkumi.png', w=1.0 },
    { key='sungeo', label='숭어', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=1.5, max=5.5, img='fish_sungeo.png', w=1.0 },
    { key='gamseongdom', label='감성돔', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.8, max=3.2, img='fish_gamseongdom.png', w=1.0 },
    { key='domi', label='도미', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=1.0, max=4.0, img='fish_domi.png', w=1.0 },
    { key='hakkkongchi', label='학꽁치', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.2, max=0.7, img='fish_hakkkongchi.png', w=1.0 },
    { key='jeoneo', label='전어', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.2, max=0.8, img='fish_jeoneo.png', w=1.0 },
    { key='samchi', label='삼치', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=2.0, max=8.0, img='fish_samchi.png', w=1.0 },
    { key='yeoneo', label='연어', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=2.0, max=7.0, img='fish_yeoneo.png', w=1.0 },
    { key='gasibok', label='가시복어', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.5, max=2.0, img='fish_gasibok.png', w=1.0 },
    { key='godeungeo', label='고등어', grade='intermediate', gradeLabel='중급', gradeColor='#4dabf7', min=0.5, max=2.5, img='fish_godeungeo.png', w=1.0 },
    { key='chamdom', label='참돔', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=1.5, max=5.5, img='fish_chamdom.png', w=1.0 },
    { key='bangeo', label='방어', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=4.0, max=12.0, img='fish_bangeo.png', w=1.0 },
    { key='nongeo', label='농어', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=2.0, max=7.0, img='fish_nongeo.png', w=1.0 },
    { key='daegu', label='대구', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=3.0, max=9.0, img='fish_daegu.png', w=1.0 },
    { key='minyeo', label='민어', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=2.5, max=7.5, img='fish_minyeo.png', w=1.0 },
    { key='ojingeo', label='오징어', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=0.5, max=2.0, img='fish_ojingeo.png', w=1.0 },
    { key='muneo', label='문어', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=2.0, max=8.0, img='fish_muneo.png', w=1.0 },
    { key='doldom', label='돌돔', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=1.0, max=4.0, img='fish_doldom.png', w=1.0 },
    { key='dageumbari', label='다금바리', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=1.5, max=5.5, img='fish_dageumbari.png', w=1.0 },
    { key='jangeo', label='장어', grade='advanced', gradeLabel='고급', gradeColor='#9b5de5', min=0.5, max=2.0, img='fish_jangeo.png', w=1.0 },
    { key='chamchi', label='참치', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=10.0, max=30.0, img='fish_chamchi.png', w=1.0 },
    { key='cheongsaechi', label='청새치', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=8.0, max=24.0, img='fish_cheongsaechi.png', w=1.0 },
    { key='dotdom', label='돗돔', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=8.0, max=20.0, img='fish_dotdom.png', w=1.0 },
    { key='bukbari', label='붉바리', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=1.0, max=4.0, img='fish_bukbari.png', w=1.0 },
    { key='dalgogi', label='달고기', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=1.0, max=4.0, img='fish_dalgogi.png', w=1.0 },
    { key='hwangsaechi', label='황새치', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=12.0, max=30.0, img='fish_hwangsaechi.png', w=1.0 },
    { key='mansaegi', label='만새기', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=5.0, max=15.0, img='fish_mansaegi.png', w=1.0 },
    { key='sireocaenseu', label='실러캔스', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=2.0, max=6.0, img='fish_sireocaenseu.png', w=1.0 },
    { key='cheolgapsangeo', label='철갑상어', grade='rare', gradeLabel='희귀', gradeColor='#f9c74f', min=10.0, max=30.0, img='fish_cheolgapsangeo.png', w=1.0 },
    { key='gaebokchi', label='개복치', grade='legendary', gradeLabel='전설', gradeColor='#f8961e', min=20.0, max=50.0, img='fish_gaebokchi.png', w=1.0 },
    { key='sangalchi', label='산갈치', grade='legendary', gradeLabel='전설', gradeColor='#f8961e', min=6.0, max=18.0, img='fish_sangalchi.png', w=1.0 },
    { key='mantagaori', label='만타가오리', grade='legendary', gradeLabel='전설', gradeColor='#f8961e', min=25.0, max=60.0, img='fish_mantagaori.png', w=1.0 },
    { key='baeksangaeo', label='백상아리', grade='legendary', gradeLabel='전설', gradeColor='#f8961e', min=35.0, max=80.0, img='fish_baeksangaeo.png', w=1.0 },
    { key='cheongsangaeo', label='청상아리', grade='legendary', gradeLabel='전설', gradeColor='#f8961e', min=25.0, max=60.0, img='fish_cheongsangaeo.png', w=1.0 },
    { key='guisangaeo', label='귀상어', grade='legendary', gradeLabel='전설', gradeColor='#f8961e', min=20.0, max=50.0, img='fish_guisangaeo.png', w=1.0 },
    { key='beomgorae', label='범고래', grade='mythic', gradeLabel='신화', gradeColor='#f94144', min=2000.0, max=5000.0, img='fish_beomgorae.png', w=1.0 },
    { key='daewanggorae', label='대왕고래', grade='mythic', gradeLabel='신화', gradeColor='#f94144', min=8000.0, max=18000.0, img='fish_daewanggorae.png', w=1.0 },
    { key='hyangyugorae', label='향유고래', grade='mythic', gradeLabel='신화', gradeColor='#f94144', min=6000.0, max=14000.0, img='fish_hyangyugorae.png', w=1.0 },
    { key='ilgakgorae', label='일각고래', grade='mythic', gradeLabel='신화', gradeColor='#f94144', min=1000.0, max=3000.0, img='fish_ilgakgorae.png', w=1.0 },
    { key='minkgorae', label='밍크고래', grade='mythic', gradeLabel='신화', gradeColor='#f94144', min=4000.0, max=9000.0, img='fish_minkgorae.png', w=1.0 },
    { key='kraken', label='크라켄', grade='transcendent', gradeLabel='초월', gradeColor='#c77dff', min=5000.0, max=12000.0, img='fish_kraken.png', w=1.0 },
    { key='leviathan', label='레비아탄', grade='transcendent', gradeLabel='초월', gradeColor='#c77dff', min=10000.0, max=25000.0, img='fish_leviathan.png', w=1.0 },
    { key='megalodon', label='메갈로돈', grade='transcendent', gradeLabel='초월', gradeColor='#c77dff', min=7000.0, max=18000.0, img='fish_megalodon.png', w=1.0 },
}
local F3_FISH_GRADE_ORDER_V159 = { 'basic','intermediate','advanced','rare','legendary','mythic','transcendent' }
local F3_FISH_ZONE_GRADE_WEIGHT_V159 = {
    shore={basic=45,intermediate=28,advanced=17,rare=8,legendary=2,mythic=0,transcendent=0},
    boat={basic=24,intermediate=24,advanced=20,rare=16,legendary=9,mythic=6,transcendent=1},
}

local function f3FishAdminOkV159(src)
    local license = getLicense(src)
    if not license then return false end
    local lv = select(1, getEffectiveLevel(license))
    return (tonumber(lv) or 0) >= 5
end

local function f3FishZoneV159(zoneId)
    return MySQL.single.await([[SELECT id,label,fishing_type,fishing_region FROM cookie_zone WHERE id=? AND type='fishing' AND is_active=1 LIMIT 1]], { tonumber(zoneId) })
end

local function f3FishDefaultWeightV159(zone, species)
    local kind = tostring(zone.fishing_type or 'normal') == 'boat' and 'boat' or 'shore'
    local base = tonumber((F3_FISH_ZONE_GRADE_WEIGHT_V159[kind] or {})[species.grade]) or 0
    local count = 0
    for _,v in ipairs(F3_FISH_SPECIES_V159) do if v.grade == species.grade then count=count+1 end end
    if count <= 0 then return math.max(0.01, tonumber(species.w) or 1) end
    local w = base / count
    if w <= 0 then w = math.max(0.01, tonumber(species.w) or 1) end
    return math.floor(w*1000+0.5)/1000
end

local function f3FishPayloadV159(zoneId)
    local zone=f3FishZoneV159(zoneId)
    if not zone then return nil,'낚시 포인트를 찾을 수 없습니다.' end
    local rows=MySQL.query.await('SELECT species,enabled,weight FROM cookie_fishing_zone_fish WHERE zone_id=?',{tonumber(zone.id)}) or {}
    local by={}; for _,r in ipairs(rows) do by[tostring(r.species)]=r end
    local out={}
    for _,f in ipairs(F3_FISH_SPECIES_V159) do
        local r=by[f.key]
        out[#out+1]={key=f.key,label=f.label,grade=f.grade,gradeLabel=f.gradeLabel,gradeColor=f.gradeColor,min=f.min,max=f.max,img=f.img,enabled=(r==nil) and true or (tonumber(r.enabled)==1),weight=(r and tonumber(r.weight)) or f3FishDefaultWeightV159(zone,f),defaultWeight=f3FishDefaultWeightV159(zone,f)}
    end
    local gi={}; for i,g in ipairs(F3_FISH_GRADE_ORDER_V159) do gi[g]=i end
    table.sort(out,function(a,b) local ai,bi=gi[a.grade] or 999,gi[b.grade] or 999;if ai==bi then return tostring(a.label)<tostring(b.label) end;return ai<bi end)
    return {zoneId=tonumber(zone.id),label=zone.label or ('낚시 포인트 #'..tostring(zone.id)),fishingType=zone.fishing_type or 'normal',fishingRegion=zone.fishing_region or ((zone.fishing_type=='boat') and 'offshore' or 'coast'),custom=#rows>0,fish=out,gradeOrder=F3_FISH_GRADE_ORDER_V159}
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cookie_fishing_zone_fish (zone_id INT NOT NULL,species VARCHAR(40) NOT NULL,enabled TINYINT(1) NOT NULL DEFAULT 1,weight DECIMAL(10,3) NOT NULL DEFAULT 1,updated_by VARCHAR(60) NULL,updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,PRIMARY KEY(zone_id,species),INDEX idx_fishing_zone(zone_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    print('[cookie_admin] FISH POINT DB DIRECT V1.5.9 ready')
end)

RegisterNetEvent('cookie_admin:server:requestFishingZoneSettingsV159',function(zoneId)
    local src=source
    print(('[cookie_admin] V159 fish request src=%s zone=%s'):format(src,tostring(zoneId)))
    if not f3FishAdminOkV159(src) then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.') end
    local data,err=f3FishPayloadV159(tonumber(zoneId))
    if not data then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,tostring(err or '어종 설정을 불러오지 못했습니다.')) end
    print(('[cookie_admin] V159 fish response src=%s zone=%s fish=%d'):format(src,tostring(zoneId),#(data.fish or {})))
    TriggerClientEvent('cookie_admin:client:fishingZoneSettingsData',src,data)
end)

RegisterNetEvent('cookie_admin:server:saveFishingZoneSettingsV159',function(data)
    local src=source
    if not f3FishAdminOkV159(src) then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'좌표 관리 권한(LV5)이 필요합니다.') end
    data=data or {}; local zoneId=tonumber(data.zoneId); local zone=f3FishZoneV159(zoneId)
    if not zone then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'낚시 포인트를 찾을 수 없습니다.') end
    if type(data.fish)~='table' or #data.fish==0 then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'저장할 어종 설정이 없습니다.') end
    local valid={}; for _,f in ipairs(F3_FISH_SPECIES_V159) do valid[f.key]=f end
    local incoming={}; local active=0
    for _,r in ipairs(data.fish) do local key=tostring(r.key or ''); if valid[key] then local en=(r.enabled==true or tonumber(r.enabled)==1) and 1 or 0; local wt=math.max(0,math.min(100000,tonumber(r.weight) or 0)); incoming[key]={enabled=en,weight=wt}; if en==1 and wt>0 then active=active+1 end end end
    if active<=0 then return TriggerClientEvent('cookie_admin:client:fishingZoneSettingsError',src,'최소 1종 이상의 물고기를 ON으로 설정하세요.') end
    local by='-'; local lic=getLicense(src); if lic then local row=MySQL.single.await('SELECT alias FROM cookie_admin WHERE license=?',{lic}); if row and row.alias and row.alias~='' then by=row.alias end end
    for _,f in ipairs(F3_FISH_SPECIES_V159) do local r=incoming[f.key] or {enabled=0,weight=f3FishDefaultWeightV159(zone,f)}; MySQL.query.await([[INSERT INTO cookie_fishing_zone_fish(zone_id,species,enabled,weight,updated_by) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE enabled=VALUES(enabled),weight=VALUES(weight),updated_by=VALUES(updated_by)]],{zoneId,f.key,r.enabled,r.weight,by}) end
    local payload=f3FishPayloadV159(zoneId); TriggerClientEvent('cookie_admin:client:fishingZoneSettingsData',src,payload or {}); TriggerClientEvent('cookie_admin:client:notify',src,('낚시 포인트 어종 설정 저장 완료 · 활성 %d종'):format(active),false); print(('[cookie_admin] V159 fish save src=%s zone=%s active=%d'):format(src,zoneId,active))
end)

print('^2[cookie_admin]^7 F3 ALL JOB LEVELS + FISHING/MINING V13.4 ready')

-- ============================================================
-- COOKIE AFK ZONE F3 COORD ADMIN V13.9.1
-- F3 > 관리자 > 좌표 관리에서 현재 관리자 위치를 잠수존 좌표로 저장합니다.
-- ============================================================
local function cookieAfkCoordAdmin(src)
    local license = getLicense(src)
    if not license then return nil end
    local admin = fetchAdmin(license)
    if not admin then return nil end
    local effective = select(1, getEffectiveLevel(license))
    if (tonumber(effective) or 0) < 5 then
        TriggerClientEvent('cookie_admin:client:notify', src, '잠수존 좌표 관리는 LV5 권한이 필요합니다.', true)
        return nil
    end
    return admin
end

local function cookiePushAfkZoneConfig(src)
    if GetResourceState('cookie_afkzone') ~= 'started' then
        TriggerClientEvent('cookie_admin:client:notify', src, 'cookie_afkzone이 실행 중이 아닙니다.', true)
        return
    end

    local ok, cfg = pcall(function()
        return exports.cookie_afkzone:GetAdminConfig()
    end)
    if not ok or type(cfg) ~= 'table' then
        TriggerClientEvent('cookie_admin:client:notify', src, '잠수존 설정을 불러오지 못했습니다.', true)
        return
    end

    TriggerClientEvent('cookie_admin:client:afkZoneConfigData', src, cfg)
end

RegisterNetEvent('cookie_admin:server:requestAfkZoneConfig', function()
    local src = source
    if not cookieAfkCoordAdmin(src) then return end
    cookiePushAfkZoneConfig(src)
end)

RegisterNetEvent('cookie_admin:server:setAfkZoneCoord', function(kind)
    local src = source
    if not cookieAfkCoordAdmin(src) then return end
    if GetResourceState('cookie_afkzone') ~= 'started' then
        return TriggerClientEvent('cookie_admin:client:notify', src, 'cookie_afkzone이 실행 중이 아닙니다.', true)
    end

    kind = tostring(kind or '')
    if kind ~= 'main' and kind ~= 'spawn' and kind ~= 'return' then return end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        return TriggerClientEvent('cookie_admin:client:notify', src, '현재 캐릭터 위치를 읽지 못했습니다.', true)
    end

    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local ok, saved, result = pcall(function()
        return exports.cookie_afkzone:SetAdminCoord(kind, {
            x=pos.x+0.0, y=pos.y+0.0, z=pos.z+0.0, h=heading+0.0,
        })
    end)

    if not ok or saved ~= true then
        return TriggerClientEvent('cookie_admin:client:notify', src,
            type(result) == 'string' and result or '잠수존 좌표 저장에 실패했습니다.', true)
    end

    local labels = {
        main='메인광장 잠수존 입장 비콘',
        spawn='잠수존 입장 스폰',
        ['return']='잠수존 메인광장 복귀 비콘',
    }
    TriggerClientEvent('cookie_admin:client:notify', src,
        (labels[kind] or '잠수존 좌표') .. ' 좌표를 현재 위치로 저장했습니다.', false)

    cookiePushAfkZoneConfig(src)
end)

RegisterNetEvent('cookie_admin:server:saveAfkZoneRadius', function(radius)
    local src = source
    if not cookieAfkCoordAdmin(src) then return end
    if GetResourceState('cookie_afkzone') ~= 'started' then
        return TriggerClientEvent('cookie_admin:client:notify', src, 'cookie_afkzone이 실행 중이 아닙니다.', true)
    end

    radius = tonumber(radius)
    if not radius then
        return TriggerClientEvent('cookie_admin:client:notify', src, '잠수존 반경을 숫자로 입력하세요.', true)
    end
    radius = math.max(5.0, math.min(1000.0, radius))

    local ok, saved, result = pcall(function()
        return exports.cookie_afkzone:SetAdminRadius(radius)
    end)
    if not ok or saved ~= true then
        return TriggerClientEvent('cookie_admin:client:notify', src,
            type(result) == 'string' and result or '잠수존 반경 저장에 실패했습니다.', true)
    end

    TriggerClientEvent('cookie_admin:client:notify', src,
        ('잠수존 반경을 %.1fm로 저장했습니다.'):format(radius), false)
    cookiePushAfkZoneConfig(src)
end)

print('^2[cookie_admin]^7 AFK ZONE COORD ADMIN V13.9.1 ready')

