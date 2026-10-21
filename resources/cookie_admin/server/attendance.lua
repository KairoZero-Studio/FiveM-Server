-- COOKIE ATTENDANCE V2.0.0
-- 일일 출석: KST 기준 하루 누적 접속시간 보상 (관리자 지정 분 단위 마일스톤)
-- 월간 출석: 기존 28단계, 하루 1회 순차 지급

local MAX_MONTHLY_DAYS = 28
local claimLocks = {}

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

local function cleanText(v, maxLen)
    local s = tostring(v or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > (maxLen or 80) then s = s:sub(1, maxLen or 80) end
    return s
end

local function kstUnix()
    return os.time() + (9 * 60 * 60)
end

local function todayKey()
    return os.date('!%Y-%m-%d', kstUnix())
end

local function monthKey()
    return os.date('!%Y-%m', kstUnix())
end

local function monthlyCycleKey(resetSerial)
    local base = monthKey()
    local serial = math.max(0, math.floor(tonumber(resetSerial) or 0))
    if serial <= 0 then return base end
    return ('%s-R%d'):format(base, serial)
end

local function monthlyCycleLabel()
    local t = os.date('!*t', kstUnix())
    return ('%d년 %d월'):format(tonumber(t.year), tonumber(t.month))
end

local function dailyCycleLabel()
    return todayKey():gsub('-', '.')
end

local function effectiveAdmin(src)
    local license = getLicense(src)
    if not license then return nil end

    local row = MySQL.single.await([[
        SELECT admin_name, admin_level, (pw_hash IS NOT NULL) AS has_pw
        FROM cookie_admin
        WHERE license = ? AND is_active = 1
        LIMIT 1
    ]], { license })

    if not row then return nil end
    local qualified = tonumber(row.admin_level) or 0
    local hasPw = row.has_pw == 1 or row.has_pw == true
    local effective = qualified
    if qualified >= 5 and not hasPw then effective = 4 end
    if effective < 5 then return nil end
    row.effective_level = effective
    return row
end

local function rewardLabel(row)
    local t = tostring(row.reward_type or row.type or 'none')
    local amount = math.max(0, math.floor(tonumber(row.amount or row.reward_amount) or 0))
    local itemCount = math.max(0, math.floor(tonumber(row.item_count or row.itemCount or row.reward_item_count) or 0))
    local itemName = tostring(row.item_name or row.itemName or row.reward_item or '')
    local custom = cleanText(row.display_label or row.label, 80)
    if custom ~= '' then return custom end
    if t == 'bank' then return ('계좌 %s원'):format(amount) end
    if t == 'cash' then return ('현금 %s원'):format(amount) end
    if t == 'item' then return ('%s x%s'):format(itemName ~= '' and itemName or '아이템', itemCount) end
    return '보상 미설정'
end

local function rewardExists(reward)
    if not reward then return false end
    if reward.type == 'bank' or reward.type == 'cash' then
        return (tonumber(reward.amount) or 0) > 0
    elseif reward.type == 'item' then
        return tostring(reward.itemName or '') ~= '' and (tonumber(reward.itemCount) or 0) > 0
    end
    return false
end

local function giveReward(src, reward, reason)
    if reward.type == 'bank' or reward.type == 'cash' then
        local ok = exports.qbx_core:AddMoney(src, reward.type, reward.amount, reason or 'COOKIE 출석체크')
        return ok ~= false
    elseif reward.type == 'item' then
        if GetResourceState('ox_inventory') ~= 'started' then return false, '인벤토리 시스템이 실행 중이 아닙니다.' end
        local okItem, item = pcall(function() return exports.ox_inventory:Items(reward.itemName) end)
        if not okItem or not item then return false, ('존재하지 않는 아이템: %s'):format(reward.itemName) end
        local okAdd, success, response = pcall(function()
            return exports.ox_inventory:AddItem(src, reward.itemName, reward.itemCount)
        end)
        if not okAdd or success == false then return false, response or '아이템을 받을 공간이 부족합니다.' end
        return true
    end
    return false, '보상이 설정되지 않았습니다.'
end

-- =========================
-- 월간 출석
-- =========================
local function getMonthlyConfig()
    local cfg = MySQL.single.await([[
        SELECT enabled, title, reset_serial
        FROM cookie_attendance_config
        WHERE id = 1 LIMIT 1
    ]]) or { enabled = 1, title = '월간 출석 체크', reset_serial = 0 }

    return {
        enabled = cfg.enabled == 1 or cfg.enabled == true,
        title = cleanText(cfg.title, 40) ~= '' and cleanText(cfg.title, 40) or '월간 출석 체크',
        resetSerial = math.max(0, math.floor(tonumber(cfg.reset_serial) or 0)),
    }
end

local function getMonthlyRewards(adminMode)
    local rows = MySQL.query.await([[
        SELECT day_no, reward_type, amount, item_name, item_count, display_label
        FROM cookie_attendance_reward ORDER BY day_no ASC
    ]]) or {}
    local map = {}
    for _, r in ipairs(rows) do map[tonumber(r.day_no)] = r end

    local out = {}
    for day = 1, MAX_MONTHLY_DAYS do
        local r = map[day] or {}
        local row = {
            day = day,
            type = tostring(r.reward_type or 'none'),
            amount = math.max(0, math.floor(tonumber(r.amount) or 0)),
            itemName = cleanText(r.item_name, 80),
            itemCount = math.max(0, math.floor(tonumber(r.item_count) or 0)),
            label = cleanText(r.display_label, 80),
        }
        if not adminMode and row.label == '' then row.label = rewardLabel(row) end
        out[#out + 1] = row
    end
    return out
end

local function monthlyRewardByDay(day)
    day = tonumber(day)
    if not day or day < 1 or day > MAX_MONTHLY_DAYS then return nil end
    local row = MySQL.single.await([[
        SELECT day_no, reward_type, amount, item_name, item_count, display_label
        FROM cookie_attendance_reward WHERE day_no = ? LIMIT 1
    ]], { day })
    if not row then return nil end
    return {
        day = day,
        type = tostring(row.reward_type or 'none'),
        amount = math.max(0, math.floor(tonumber(row.amount) or 0)),
        itemName = cleanText(row.item_name, 80),
        itemCount = math.max(0, math.floor(tonumber(row.item_count) or 0)),
        label = rewardLabel(row),
    }
end

local function buildMonthlyAttendance(src)
    local cid = citizenId(src)
    local cfg = getMonthlyConfig()
    local rewards = getMonthlyRewards(false)
    local currentCycle = monthlyCycleKey(cfg.resetSerial)

    if not cid then
        return {
            enabled = false, title = cfg.title, cycle = currentCycle, cycleLabel = monthlyCycleLabel(),
            claimedCount = 0, claimedToday = false, nextDay = 1, canClaim = false,
            reason = '시민 정보를 불러올 수 없습니다.', rewards = rewards, claimed = {}, mode = 'monthly'
        }
    end

    local claims = MySQL.query.await([[
        SELECT reward_day, claim_date
        FROM cookie_attendance_claim
        WHERE citizenid = ? AND cycle_key = ?
        ORDER BY reward_day ASC
    ]], { cid, currentCycle }) or {}

    local claimed, claimedToday = {}, false
    for _, row in ipairs(claims) do
        local d = tonumber(row.reward_day)
        if d and d >= 1 and d <= MAX_MONTHLY_DAYS then claimed[tostring(d)] = true end
        if tostring(row.claim_date or ''):sub(1, 10) == todayKey() then claimedToday = true end
    end

    local claimedCount = #claims
    local nextDay = math.min(MAX_MONTHLY_DAYS + 1, claimedCount + 1)
    local nextReward = nextDay <= MAX_MONTHLY_DAYS and rewards[nextDay] or nil
    local canClaim, reason = true, nil

    if not cfg.enabled then
        canClaim, reason = false, '현재 월간 출석체크가 비활성화되어 있습니다.'
    elseif claimedToday then
        canClaim, reason = false, '오늘 월간 출석 보상은 이미 받았습니다.'
    elseif claimedCount >= MAX_MONTHLY_DAYS then
        canClaim, reason = false, '이번 달 28일 출석을 모두 완료했습니다.'
    elseif not nextReward or nextReward.type == 'none' then
        canClaim, reason = false, ('%d일차 보상이 아직 설정되지 않았습니다.'):format(nextDay)
    end

    return {
        mode = 'monthly', enabled = cfg.enabled, title = cfg.title, cycle = currentCycle,
        cycleLabel = monthlyCycleLabel(), today = todayKey(), claimedCount = math.min(claimedCount, MAX_MONTHLY_DAYS),
        claimedToday = claimedToday, nextDay = nextDay <= MAX_MONTHLY_DAYS and nextDay or MAX_MONTHLY_DAYS,
        canClaim = canClaim, reason = reason, rewards = rewards, claimed = claimed,
    }
end

-- =========================
-- 일일 접속시간 출석
-- =========================
local function getDailyConfig()
    local cfg = MySQL.single.await([[
        SELECT enabled, title FROM cookie_attendance_daily_config WHERE id = 1 LIMIT 1
    ]]) or { enabled = 1, title = '일일 출석 체크' }
    return {
        enabled = cfg.enabled == 1 or cfg.enabled == true,
        title = cleanText(cfg.title, 40) ~= '' and cleanText(cfg.title, 40) or '일일 출석 체크',
    }
end

local function getDailyRewards(adminMode)
    local where = adminMode and '' or 'WHERE active = 1'
    local rows = MySQL.query.await(([[
        SELECT id, required_min, reward_type, amount, item_name, item_count, display_label, sort_order, active
        FROM cookie_attendance_daily_reward %s
        ORDER BY required_min ASC, sort_order ASC, id ASC
    ]]):format(where)) or {}

    local out = {}
    for _, r in ipairs(rows) do
        local row = {
            id = tonumber(r.id),
            requiredMinutes = math.max(1, math.floor(tonumber(r.required_min) or 1)),
            type = tostring(r.reward_type or 'none'),
            amount = math.max(0, math.floor(tonumber(r.amount) or 0)),
            itemName = cleanText(r.item_name, 80),
            itemCount = math.max(0, math.floor(tonumber(r.item_count) or 0)),
            label = cleanText(r.display_label, 80),
            sort = math.floor(tonumber(r.sort_order) or 0),
            active = r.active == 1 or r.active == true,
        }
        if not adminMode and row.label == '' then row.label = rewardLabel(row) end
        out[#out + 1] = row
    end
    return out
end

local function buildDailyAttendance(src)
    local cid = citizenId(src)
    local cfg = getDailyConfig()
    local cycle = todayKey()
    local rewards = getDailyRewards(false)
    local minute = 0
    local claimed = {}

    if cid then
        local progress = MySQL.single.await([[
            SELECT minute FROM cookie_attendance_daily_progress WHERE citizenid = ? AND cycle_key = ? LIMIT 1
        ]], { cid, cycle })
        minute = math.max(0, math.floor(tonumber(progress and progress.minute) or 0))

        local claims = MySQL.query.await([[
            SELECT reward_id FROM cookie_attendance_daily_claim WHERE citizenid = ? AND cycle_key = ?
        ]], { cid, cycle }) or {}
        for _, row in ipairs(claims) do claimed[tostring(row.reward_id)] = true end
    end

    local canClaimAny = false
    local nextRequired = nil
    for _, reward in ipairs(rewards) do
        reward.claimed = claimed[tostring(reward.id)] == true
        reward.unlocked = minute >= reward.requiredMinutes
        reward.canClaim = cid ~= nil and cfg.enabled and reward.unlocked and not reward.claimed and rewardExists(reward)
        if reward.canClaim then canClaimAny = true end
        if not reward.claimed and not reward.unlocked and (not nextRequired or reward.requiredMinutes < nextRequired) then
            nextRequired = reward.requiredMinutes
        end
    end

    local reason
    if not cid then reason = '시민 정보를 불러올 수 없습니다.'
    elseif not cfg.enabled then reason = '현재 일일 출석체크가 비활성화되어 있습니다.'
    elseif canClaimAny then reason = '접속시간 조건을 달성한 보상을 받을 수 있습니다.'
    elseif nextRequired then reason = ('다음 보상까지 %d분 남았습니다.'):format(math.max(0, nextRequired - minute))
    else reason = '오늘 받을 수 있는 접속시간 보상을 모두 확인했습니다.' end

    return {
        mode = 'daily', enabled = cfg.enabled, title = cfg.title, cycle = cycle, cycleLabel = dailyCycleLabel(),
        minute = minute, claimed = claimed, rewards = rewards, canClaimAny = canClaimAny,
        nextRequiredMinutes = nextRequired, reason = reason,
    }
end

function CookieAttendanceAccrue(src, minutes)
    src = tonumber(src) or 0
    minutes = math.max(0, math.floor(tonumber(minutes) or 0))
    if src <= 0 or minutes <= 0 then return end
    local cid = citizenId(src)
    if not cid then return end
    MySQL.query.await([[
        INSERT INTO cookie_attendance_daily_progress(citizenid, cycle_key, minute)
        VALUES(?,?,?)
        ON DUPLICATE KEY UPDATE minute = minute + VALUES(minute), updated_at = CURRENT_TIMESTAMP
    ]], { cid, todayKey(), minutes })
end

local function buildAttendancePayload(src)
    return {
        daily = buildDailyAttendance(src),
        monthly = buildMonthlyAttendance(src),
    }
end

local function sendAttendance(src, message, isError)
    TriggerClientEvent('cookie_admin:client:attendanceData', src, buildAttendancePayload(src), message, isError == true)
end

-- =========================
-- DB
-- =========================
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_config (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            title VARCHAR(40) NOT NULL DEFAULT '월간 출석 체크',
            reset_serial INT UNSIGNED NOT NULL DEFAULT 0,
            updated_by VARCHAR(64) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    pcall(function() MySQL.query.await([[ALTER TABLE cookie_attendance_config ADD COLUMN IF NOT EXISTS reset_serial INT UNSIGNED NOT NULL DEFAULT 0]]) end)

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_reset_log (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            admin_name VARCHAR(64) NOT NULL,
            previous_cycle VARCHAR(32) NOT NULL,
            new_cycle VARCHAR(32) NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_reward (
            day_no TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            reward_type VARCHAR(12) NOT NULL DEFAULT 'none',
            amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            item_name VARCHAR(80) NOT NULL DEFAULT '',
            item_count INT UNSIGNED NOT NULL DEFAULT 0,
            display_label VARCHAR(80) NOT NULL DEFAULT '',
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_claim (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            citizenid VARCHAR(64) NOT NULL,
            cycle_key VARCHAR(32) NOT NULL,
            reward_day TINYINT UNSIGNED NOT NULL,
            claim_date DATE NOT NULL,
            reward_type VARCHAR(12) NOT NULL,
            reward_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            reward_item VARCHAR(80) NOT NULL DEFAULT '',
            reward_item_count INT UNSIGNED NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_cookie_attendance_day (citizenid, cycle_key, reward_day),
            UNIQUE KEY uq_cookie_attendance_date (citizenid, claim_date),
            INDEX idx_cookie_attendance_cycle (citizenid, cycle_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    pcall(function() MySQL.query.await([[ALTER TABLE cookie_attendance_claim MODIFY COLUMN cycle_key VARCHAR(32) NOT NULL]]) end)

    MySQL.insert.await([[INSERT IGNORE INTO cookie_attendance_config(id, enabled, title) VALUES(1, 1, '월간 출석 체크')]])
    for day = 1, MAX_MONTHLY_DAYS do
        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_attendance_reward(day_no, reward_type, amount, item_name, item_count, display_label)
            VALUES (?, 'none', 0, '', 0, '')
        ]], { day })
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_daily_config (
            id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            title VARCHAR(40) NOT NULL DEFAULT '일일 출석 체크',
            updated_by VARCHAR(64) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_daily_reward (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            required_min INT UNSIGNED NOT NULL DEFAULT 60,
            reward_type VARCHAR(12) NOT NULL DEFAULT 'none',
            amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            item_name VARCHAR(80) NOT NULL DEFAULT '',
            item_count INT UNSIGNED NOT NULL DEFAULT 0,
            display_label VARCHAR(80) NOT NULL DEFAULT '',
            sort_order INT NOT NULL DEFAULT 0,
            active TINYINT(1) NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_cookie_attendance_daily_required(active, required_min, sort_order)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_daily_progress (
            citizenid VARCHAR(64) NOT NULL,
            cycle_key VARCHAR(10) NOT NULL,
            minute INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid, cycle_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_attendance_daily_claim (
            citizenid VARCHAR(64) NOT NULL,
            cycle_key VARCHAR(10) NOT NULL,
            reward_id INT UNSIGNED NOT NULL,
            reward_type VARCHAR(12) NOT NULL,
            reward_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
            reward_item VARCHAR(80) NOT NULL DEFAULT '',
            reward_item_count INT UNSIGNED NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(citizenid, cycle_key, reward_id),
            INDEX idx_cookie_attendance_daily_cycle(cycle_key, reward_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    local dailyConfigExisted = MySQL.single.await('SELECT id FROM cookie_attendance_daily_config WHERE id=1 LIMIT 1') ~= nil
    MySQL.insert.await([[INSERT IGNORE INTO cookie_attendance_daily_config(id, enabled, title) VALUES(1, 1, '일일 출석 체크')]])
    local dailyCount = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cookie_attendance_daily_reward')) or 0
    if not dailyConfigExisted and dailyCount <= 0 then
        MySQL.insert.await([[INSERT INTO cookie_attendance_daily_reward(required_min,reward_type,sort_order,active) VALUES(60,'none',10,1)]])
        MySQL.insert.await([[INSERT INTO cookie_attendance_daily_reward(required_min,reward_type,sort_order,active) VALUES(180,'none',20,1)]])
    end

    print('^2[cookie_admin]^7 DAILY TIME + MONTHLY ATTENDANCE V2.0.0 ready')
end)

-- =========================
-- 유저 요청 / 수령
-- =========================
RegisterNetEvent('cookie_admin:server:requestAttendance', function()
    sendAttendance(source)
end)

RegisterNetEvent('cookie_admin:server:claimAttendance', function(data)
    local src = source
    local cid = citizenId(src)
    if not cid then return end
    data = type(data) == 'table' and data or {}
    local mode = tostring(data.mode or 'monthly')

    if mode == 'daily' then
        local rewardId = math.floor(tonumber(data.rewardId) or 0)
        if rewardId <= 0 then return sendAttendance(src, '받을 일일 출석 보상을 찾을 수 없습니다.', true) end
        local lockKey = ('%s:daily:%d'):format(cid, rewardId)
        if claimLocks[lockKey] then return end
        claimLocks[lockKey] = true
        local function done(message, isError)
            claimLocks[lockKey] = nil
            sendAttendance(src, message, isError)
        end

        local cfg = getDailyConfig()
        if not cfg.enabled then return done('현재 일일 출석체크가 비활성화되어 있습니다.', true) end
        local cycle = todayKey()
        local rewardRow = MySQL.single.await([[
            SELECT id, required_min, reward_type, amount, item_name, item_count, display_label
            FROM cookie_attendance_daily_reward WHERE id = ? AND active = 1 LIMIT 1
        ]], { rewardId })
        if not rewardRow then return done('일일 출석 보상을 찾을 수 없습니다.', true) end

        local reward = {
            id = rewardId,
            requiredMinutes = math.max(1, math.floor(tonumber(rewardRow.required_min) or 1)),
            type = tostring(rewardRow.reward_type or 'none'),
            amount = math.max(0, math.floor(tonumber(rewardRow.amount) or 0)),
            itemName = cleanText(rewardRow.item_name, 80),
            itemCount = math.max(0, math.floor(tonumber(rewardRow.item_count) or 0)),
            label = rewardLabel(rewardRow),
        }
        if not rewardExists(reward) then return done('이 보상은 아직 설정되지 않았습니다.', true) end

        local minute = tonumber(MySQL.scalar.await([[
            SELECT minute FROM cookie_attendance_daily_progress WHERE citizenid = ? AND cycle_key = ?
        ]], { cid, cycle })) or 0
        if minute < reward.requiredMinutes then
            return done(('접속시간이 부족합니다. 현재 %d분 / 필요 %d분'):format(minute, reward.requiredMinutes), true)
        end

        local exists = MySQL.single.await([[
            SELECT reward_id FROM cookie_attendance_daily_claim WHERE citizenid = ? AND cycle_key = ? AND reward_id = ? LIMIT 1
        ]], { cid, cycle, rewardId })
        if exists then return done('이미 받은 일일 출석 보상입니다.', true) end

        local ok, err = giveReward(src, reward, ('COOKIE 일일 출석 %d분'):format(reward.requiredMinutes))
        if not ok then return done(err or '보상 지급에 실패했습니다.', true) end

        local inserted = MySQL.insert.await([[
            INSERT INTO cookie_attendance_daily_claim
                (citizenid, cycle_key, reward_id, reward_type, reward_amount, reward_item, reward_item_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], { cid, cycle, rewardId, reward.type, reward.amount, reward.itemName, reward.itemCount })
        if not inserted then return done('출석 기록 저장에 실패했습니다. 관리자에게 문의하세요.', true) end
        return done(('%d분 접속 보상 · %s'):format(reward.requiredMinutes, reward.label), false)
    end

    local lockKey = cid .. ':monthly'
    if claimLocks[lockKey] then return end
    claimLocks[lockKey] = true
    local function done(message, isError)
        claimLocks[lockKey] = nil
        sendAttendance(src, message, isError)
    end

    local state = buildMonthlyAttendance(src)
    if not state.canClaim then return done(state.reason or '오늘은 월간 출석 보상을 받을 수 없습니다.', true) end
    local day = tonumber(state.nextDay) or 1
    local reward = monthlyRewardByDay(day)
    if not rewardExists(reward) then return done(('%d일차 보상이 아직 설정되지 않았습니다.'):format(day), true) end

    local duplicate = MySQL.single.await([[
        SELECT id FROM cookie_attendance_claim
        WHERE citizenid = ? AND (claim_date = ? OR (cycle_key = ? AND reward_day = ?)) LIMIT 1
    ]], { cid, todayKey(), state.cycle, day })
    if duplicate then return done('오늘 월간 출석 보상은 이미 받았습니다.', true) end

    local ok, err = giveReward(src, reward, ('COOKIE 월간 출석 %d일차'):format(day))
    if not ok then return done(err or '보상 지급에 실패했습니다.', true) end

    local inserted = MySQL.insert.await([[
        INSERT INTO cookie_attendance_claim
            (citizenid, cycle_key, reward_day, claim_date, reward_type, reward_amount, reward_item, reward_item_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { cid, state.cycle, day, todayKey(), reward.type, reward.amount, reward.itemName, reward.itemCount })
    if not inserted then return done('출석 기록 저장에 실패했습니다. 관리자에게 문의하세요.', true) end
    done(('%d일차 월간 출석 완료 · %s'):format(day, reward.label), false)
end)

-- =========================
-- 관리자
-- =========================
local function attendanceAdminPayload()
    return {
        daily = { config = getDailyConfig(), rewards = getDailyRewards(true) },
        monthly = { config = getMonthlyConfig(), rewards = getMonthlyRewards(true) },
    }
end

RegisterNetEvent('cookie_admin:server:requestAttendanceAdmin', function()
    local src = source
    if not effectiveAdmin(src) then return end
    TriggerClientEvent('cookie_admin:client:attendanceAdminData', src, attendanceAdminPayload())
end)

RegisterNetEvent('cookie_admin:server:saveAttendanceAdmin', function(data)
    local src = source
    local admin = effectiveAdmin(src)
    if not admin or type(data) ~= 'table' then return end
    local adminName = cleanText(admin.admin_name, 64)
    local allowed = { none = true, bank = true, cash = true, item = true }

    -- 구버전 NUI 호환: config/rewards만 오면 월간으로 처리
    local monthly = type(data.monthly) == 'table' and data.monthly or { config = data.config, rewards = data.rewards }
    local daily = type(data.daily) == 'table' and data.daily or {}

    local mcfg = type(monthly.config) == 'table' and monthly.config or {}
    local mtitle = cleanText(mcfg.title, 40); if mtitle == '' then mtitle = '월간 출석 체크' end
    MySQL.update.await([[UPDATE cookie_attendance_config SET enabled=?, title=?, updated_by=? WHERE id=1]], {
        mcfg.enabled == true and 1 or 0, mtitle, adminName
    })

    local monthlyMap = {}
    for _, r in ipairs(type(monthly.rewards) == 'table' and monthly.rewards or {}) do
        local day = math.floor(tonumber(r.day) or 0)
        if day >= 1 and day <= MAX_MONTHLY_DAYS then monthlyMap[day] = r end
    end

    local function normalizeReward(r, context)
        r = type(r) == 'table' and r or {}
        local typ = tostring(r.type or 'none')
        if not allowed[typ] then typ = 'none' end
        local amount = math.max(0, math.min(1000000000, math.floor(tonumber(r.amount) or 0)))
        local itemName = cleanText(r.itemName, 80):lower()
        local itemCount = math.max(0, math.min(999, math.floor(tonumber(r.itemCount) or 0)))
        local label = cleanText(r.label, 80)

        if typ == 'bank' or typ == 'cash' then
            if amount <= 0 then typ = 'none' end
            itemName, itemCount = '', 0
        elseif typ == 'item' then
            amount = 0
            if itemName == '' or itemCount <= 0 then
                typ, itemName, itemCount = 'none', '', 0
            elseif GetResourceState('ox_inventory') == 'started' then
                local okItem, item = pcall(function() return exports.ox_inventory:Items(itemName) end)
                if not okItem or not item then
                    return nil, ('%s 아이템 "%s"을 찾을 수 없습니다.'):format(context, itemName)
                end
            end
        else
            typ, amount, itemName, itemCount = 'none', 0, '', 0
        end
        return { type=typ, amount=amount, itemName=itemName, itemCount=itemCount, label=label }
    end

    for day = 1, MAX_MONTHLY_DAYS do
        local nr, err = normalizeReward(monthlyMap[day], ('월간 %d일차'):format(day))
        if not nr then
            TriggerClientEvent('cookie_admin:client:attendanceAdminSaved', src, false, err)
            return
        end
        MySQL.query.await([[
            INSERT INTO cookie_attendance_reward(day_no,reward_type,amount,item_name,item_count,display_label)
            VALUES(?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE reward_type=VALUES(reward_type),amount=VALUES(amount),item_name=VALUES(item_name),
                item_count=VALUES(item_count),display_label=VALUES(display_label),updated_at=CURRENT_TIMESTAMP
        ]], { day, nr.type, nr.amount, nr.itemName, nr.itemCount, nr.label })
    end

    local dcfg = type(daily.config) == 'table' and daily.config or {}
    local dtitle = cleanText(dcfg.title, 40); if dtitle == '' then dtitle = '일일 출석 체크' end
    MySQL.update.await([[UPDATE cookie_attendance_daily_config SET enabled=?, title=?, updated_by=? WHERE id=1]], {
        dcfg.enabled == true and 1 or 0, dtitle, adminName
    })

    local rows = type(daily.rewards) == 'table' and daily.rewards or {}
    if #rows > 24 then
        TriggerClientEvent('cookie_admin:client:attendanceAdminSaved', src, false, '일일 접속시간 보상은 최대 24개까지 등록할 수 있습니다.')
        return
    end

    local usedMinutes = {}
    local existingDaily = MySQL.query.await('SELECT id FROM cookie_attendance_daily_reward') or {}
    local keepDaily = {}
    MySQL.update.await('UPDATE cookie_attendance_daily_reward SET active=0')
    for i, r in ipairs(rows) do
        local required = math.max(1, math.min(1440, math.floor(tonumber(r.requiredMinutes) or 0)))
        if usedMinutes[required] then
            TriggerClientEvent('cookie_admin:client:attendanceAdminSaved', src, false, ('일일 접속시간 %d분이 중복되어 있습니다.'):format(required))
            return
        end
        usedMinutes[required] = true
        local nr, err = normalizeReward(r, ('일일 %d분'):format(required))
        if not nr then
            TriggerClientEvent('cookie_admin:client:attendanceAdminSaved', src, false, err)
            return
        end
        local active = r.active ~= false and 1 or 0
        local id = math.floor(tonumber(r.id) or 0)
        if id > 0 then
            keepDaily[id] = true
            MySQL.update.await([[
                UPDATE cookie_attendance_daily_reward
                SET required_min=?,reward_type=?,amount=?,item_name=?,item_count=?,display_label=?,sort_order=?,active=?
                WHERE id=?
            ]], { required, nr.type, nr.amount, nr.itemName, nr.itemCount, nr.label, i*10, active, id })
        else
            MySQL.insert.await([[
                INSERT INTO cookie_attendance_daily_reward(required_min,reward_type,amount,item_name,item_count,display_label,sort_order,active)
                VALUES(?,?,?,?,?,?,?,?)
            ]], { required, nr.type, nr.amount, nr.itemName, nr.itemCount, nr.label, i*10, active })
        end
    end

    for _, old in ipairs(existingDaily) do
        local oldId = math.floor(tonumber(old.id) or 0)
        if oldId > 0 and not keepDaily[oldId] then
            MySQL.update.await('DELETE FROM cookie_attendance_daily_reward WHERE id=?', { oldId })
        end
    end

    TriggerClientEvent('cookie_admin:client:attendanceAdminSaved', src, true, '일일/월간 출석체크 설정을 저장했습니다.')
    TriggerClientEvent('cookie_admin:client:attendanceAdminData', src, attendanceAdminPayload())
end)

RegisterNetEvent('cookie_admin:server:resetAttendance', function(data)
    local src = source
    local admin = effectiveAdmin(src)
    if not admin then return end
    data = type(data) == 'table' and data or {}
    local mode = tostring(data.mode or 'monthly')

    if mode == 'daily' then
        local cycle = todayKey()
        MySQL.query.await('DELETE FROM cookie_attendance_daily_progress WHERE cycle_key=?', { cycle })
        MySQL.query.await('DELETE FROM cookie_attendance_daily_claim WHERE cycle_key=?', { cycle })
        claimLocks = {}
        TriggerClientEvent('cookie_admin:client:attendanceResetResult', src, true, '오늘의 전체 일일 접속시간/수령 기록을 초기화했습니다.', 'daily')
        return
    end

    local cfg = getMonthlyConfig()
    local oldCycle = monthlyCycleKey(cfg.resetSerial)
    local nextSerial = cfg.resetSerial + 1
    MySQL.update.await([[UPDATE cookie_attendance_config SET reset_serial=?, updated_by=? WHERE id=1]], {
        nextSerial, cleanText(admin.admin_name, 64)
    })
    local newCycle = monthlyCycleKey(nextSerial)
    MySQL.insert.await([[INSERT INTO cookie_attendance_reset_log(admin_name,previous_cycle,new_cycle) VALUES(?,?,?)]], {
        cleanText(admin.admin_name, 64), oldCycle, newCycle
    })
    claimLocks = {}
    TriggerClientEvent('cookie_admin:client:attendanceResetResult', src, true,
        '전체 유저의 월간 출석 진행도를 1일차부터 다시 시작하도록 초기화했습니다.', 'monthly')
    TriggerClientEvent('cookie_admin:client:attendanceAdminData', src, attendanceAdminPayload())
end)

AddEventHandler('playerDropped', function()
    local cid = citizenId(source)
    if not cid then return end
    for key in pairs(claimLocks) do
        if key:sub(1, #cid) == cid then claimLocks[key] = nil end
    end
end)
