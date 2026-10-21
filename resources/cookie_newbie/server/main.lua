local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function bool(v)
    return v == true or tonumber(v) == 1 or tostring(v) == '1'
end

local function ensureRow(license)
    MySQL.insert.await([[INSERT IGNORE INTO cookie_newbie_progress (license) VALUES (?)]], { license })

    return MySQL.single.await([[
        SELECT license, guide_done, identity_done, license_done, education_done,
               verify_done, reward_claimed_at,
               UNIX_TIMESTAMP(completed_at) AS completed_at_ts,
               UNIX_TIMESTAMP(reward_claimed_at) AS reward_claimed_at_ts
        FROM cookie_newbie_progress
        WHERE license = ?
        LIMIT 1
    ]], { license })
end

local function getVerifyInfo()
    if not Config.RequireDiscordVerify then
        return { ok = true, invite = '', channel = '', length = 6 }
    end

    if GetResourceState('cookie_core') ~= 'started' then
        return { ok = false, invite = '', channel = '', length = 6 }
    end

    local ok, info = pcall(function()
        return exports.cookie_core:getVerifyInfo()
    end)

    if ok and type(info) == 'table' then
        return info
    end

    return { ok = false, invite = '', channel = '', length = 6 }
end

local function isVerified(src)
    if not Config.RequireDiscordVerify then return true end
    if GetResourceState('cookie_core') ~= 'started' then return false end

    local ok, verified = pcall(function()
        return exports.cookie_core:isVerified(src)
    end)

    return ok and verified == true
end

local function refreshDerivedState(src, row)
    local license = getLicense(src)
    if not license or not row then return row end

    local identity = exports.cookie_core:getIdentity(src)
    local identityDone = identity and identity.jumin and identity.jumin ~= ''
        and identity.phone and identity.phone ~= ''

    local driver
    if GetResourceState('cookie_license') == 'started' then
        local ok, result = pcall(function()
            return exports.cookie_license:GetBySource(src)
        end)
        if ok then driver = result end
    end
    local licenseDone = driver and driver.licenseNo and driver.licenseNo ~= ''
    local verifyDone = isVerified(src)

    if identityDone and not bool(row.identity_done) then
        MySQL.update.await('UPDATE cookie_newbie_progress SET identity_done=1 WHERE license=?', { license })
        row.identity_done = 1
    end
    if licenseDone and not bool(row.license_done) then
        MySQL.update.await('UPDATE cookie_newbie_progress SET license_done=1 WHERE license=?', { license })
        row.license_done = 1
    end
    if verifyDone and not bool(row.verify_done) then
        MySQL.update.await('UPDATE cookie_newbie_progress SET verify_done=1 WHERE license=?', { license })
        row.verify_done = 1
    elseif (not Config.RequireDiscordVerify) and not bool(row.verify_done) then
        MySQL.update.await('UPDATE cookie_newbie_progress SET verify_done=1 WHERE license=?', { license })
        row.verify_done = 1
    end

    local completed = bool(row.guide_done) and bool(row.identity_done) and bool(row.license_done)
        and bool(row.education_done) and bool(row.verify_done)

    if completed and not row.completed_at_ts then
        MySQL.update.await('UPDATE cookie_newbie_progress SET completed_at=NOW() WHERE license=?', { license })
        row.completed_at_ts = os.time()
    end

    row._identity = identity
    row._driver = driver
    row._verifyInfo = getVerifyInfo()
    return row
end

local function buildState(src)
    local license = getLicense(src)
    if not license then return { ok=false, reason='식별 정보를 확인할 수 없습니다.' } end

    local nick = exports.cookie_core:getNickname(src)
    if not nick or nick == '' then
        return { ok=false, reason='먼저 최초 접속 온보딩을 완료해주세요.' }
    end

    local row = refreshDerivedState(src, ensureRow(license))
    local identity = row._identity or {}
    local driver = row._driver or {}
    local verifyInfo = row._verifyInfo or getVerifyInfo()

    local guideDone = bool(row.guide_done)
    local identityDone = bool(row.identity_done)
    local licenseDone = bool(row.license_done)
    local educationDone = bool(row.education_done)
    local verifyDone = bool(row.verify_done)
    local rewardClaimed = row.reward_claimed_at_ts ~= nil
    local completed = guideDone and identityDone and licenseDone and educationDone and verifyDone

    return {
        ok = true,
        nickname = nick,
        gobun = exports.cookie_core:getGobun(src),
        guideDone = guideDone,
        identityDone = identityDone,
        licenseDone = licenseDone,
        educationDone = educationDone,
        verifyDone = verifyDone,
        verifyRequired = Config.RequireDiscordVerify == true,
        completed = completed,
        rewardClaimed = rewardClaimed,
        rewardItem = Config.RewardKitItem,
        rewardLabel = Config.RewardKitLabel,
        verifyInfo = verifyInfo,
        jumin = identity.jumin,
        phone = identity.phone,
        driverLicense = driver.licenseNo,
        driverStatus = driver.statusLabel,
        completedAt = row.completed_at_ts,
        rewardClaimedAt = row.reward_claimed_at_ts,
    }
end

local function notify(src, message, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = '뉴비 시청',
        description = message,
        type = kind or 'inform'
    })
end

local function tryGrantReward(src)
    local license = getLicense(src)
    if not license then return false, '식별에 실패했습니다.' end

    local row = refreshDerivedState(src, ensureRow(license))
    local completed = bool(row.guide_done) and bool(row.identity_done) and bool(row.license_done)
        and bool(row.education_done) and bool(row.verify_done)

    if not completed then
        return false, '아직 뉴비 절차가 모두 완료되지 않았습니다.'
    end

    if row.reward_claimed_at_ts then
        return true, '이미 뉴비 보상을 수령했습니다.'
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        return false, 'ox_inventory가 실행 중이 아닙니다.'
    end

    -- DB를 먼저 잠가 동시 요청/중복 클릭으로 중복 지급되는 것을 방지합니다.
    local changed = MySQL.update.await([[
        UPDATE cookie_newbie_progress
        SET reward_claimed_at = NOW()
        WHERE license = ? AND reward_claimed_at IS NULL
    ]], { license })

    if tonumber(changed) ~= 1 then
        return true, '이미 뉴비 보상을 수령했습니다.'
    end

    local ok = exports.ox_inventory:AddItem(src, Config.RewardKitItem, 1, {
        from = 'newbie_verify',
        issuedAt = os.time(),
    })

    if not ok then
        MySQL.update.await('UPDATE cookie_newbie_progress SET reward_claimed_at = NULL WHERE license = ?', { license })
        return false, '인벤토리 공간이 부족하여 보상 지급에 실패했습니다.'
    end

    return true, ('%s 1개를 지급했습니다.'):format(Config.RewardKitLabel)
end

lib.callback.register('cookie_newbie:getState', function(src)
    return buildState(src)
end)

lib.callback.register('cookie_newbie:guideDone', function(src)
    local license = getLicense(src)
    if not license then return { ok=false, reason='식별 실패' } end
    ensureRow(license)
    MySQL.update.await('UPDATE cookie_newbie_progress SET guide_done=1 WHERE license=?', { license })
    local state = buildState(src)
    state.message = '가이드 확인을 완료했습니다.'
    return state
end)

lib.callback.register('cookie_newbie:issueIdentity', function(src)
    local license = getLicense(src)
    if not license then return { ok=false, reason='식별 실패' } end
    local row = ensureRow(license)
    if not bool(row.guide_done) then
        return { ok=false, reason='먼저 가이드를 확인해주세요.', state=buildState(src) }
    end

    local result = exports.cookie_core:issueNewbieIdentity(src)
    if not result or not result.ok then
        return { ok=false, reason=(result and result.reason) or '신분번호 발급에 실패했습니다.', state=buildState(src) }
    end

    MySQL.update.await('UPDATE cookie_newbie_progress SET identity_done=1 WHERE license=?', { license })
    local state = buildState(src)
    state.message = ('주민번호 %s / 전화번호 %s 발급 완료'):format(result.jumin or '-', result.phone or '-')
    return state
end)

lib.callback.register('cookie_newbie:issueLicense', function(src)
    local license = getLicense(src)
    if not license then return { ok=false, reason='식별 실패' } end
    local row = refreshDerivedState(src, ensureRow(license))
    if not bool(row.guide_done) or not bool(row.identity_done) then
        return { ok=false, reason='먼저 가이드와 주민번호·전화번호 발급을 완료해주세요.', state=buildState(src) }
    end

    if GetResourceState('cookie_license') ~= 'started' then
        return { ok=false, reason='운전면허 시스템이 실행 중이 아닙니다.', state=buildState(src) }
    end

    local licenseData = exports.cookie_license:GetBySource(src)
    if not licenseData then
        licenseData = exports.cookie_license:IssueForSource(src)
    end
    if not licenseData or not licenseData.licenseNo then
        return { ok=false, reason='운전면허 발급에 실패했습니다.', state=buildState(src) }
    end

    MySQL.update.await('UPDATE cookie_newbie_progress SET license_done=1 WHERE license=?', { license })
    local state = buildState(src)
    state.message = ('운전면허 %s 발급 완료'):format(licenseData.licenseNo)
    return state
end)

lib.callback.register('cookie_newbie:educationDone', function(src)
    local license = getLicense(src)
    if not license then return { ok=false, reason='식별 실패' } end
    local row = refreshDerivedState(src, ensureRow(license))
    if not bool(row.license_done) then
        return { ok=false, reason='먼저 운전면허 발급을 완료해주세요.', state=buildState(src) }
    end

    MySQL.update.await('UPDATE cookie_newbie_progress SET education_done=1 WHERE license=?', { license })
    local state = buildState(src)
    state.message = '기본 교육을 완료했습니다. 이제 디스코드 인증을 진행해주세요.'
    return state
end)

lib.callback.register('cookie_newbie:submitVerifyCode', function(src, code)
    if not Config.RequireDiscordVerify then
        local ok, msg = tryGrantReward(src)
        local state = buildState(src)
        state.message = msg or (ok and '보상이 지급되었습니다.' or '인증이 필요하지 않습니다.')
        return state
    end

    local license = getLicense(src)
    if not license then return { ok=false, reason='식별 실패' } end
    local row = refreshDerivedState(src, ensureRow(license))
    if not bool(row.education_done) then
        return { ok=false, reason='먼저 기본 교육을 완료해주세요.', state=buildState(src) }
    end

    local ok, result = pcall(function()
        return exports.cookie_core:redeemCode(src, tostring(code or ''))
    end)

    if not ok or not result or result.ok ~= true then
        return { ok=false, reason=(result and result.reason) or '인증코드 확인에 실패했습니다.', state=buildState(src) }
    end

    MySQL.update.await('UPDATE cookie_newbie_progress SET verify_done=1 WHERE license=?', { license })
    local rewardOk, rewardMsg = tryGrantReward(src)
    local state = buildState(src)
    state.message = rewardOk and ('디스코드 인증이 완료되었습니다. ' .. rewardMsg)
        or ('디스코드 인증은 완료되었지만 보상 지급에 실패했습니다. ' .. (rewardMsg or ''))
    return state
end)

lib.callback.register('cookie_newbie:claimReward', function(src)
    local ok, msg = tryGrantReward(src)
    if not ok then
        return { ok=false, reason=msg, state=buildState(src) }
    end

    local state = buildState(src)
    state.message = msg
    return state
end)

exports('IsComplete', function(src)
    local state = buildState(tonumber(src))
    return state and state.completed == true
end)

exports('GetState', function(src)
    return buildState(tonumber(src))
end)

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_newbie_progress (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            license VARCHAR(255) NOT NULL,
            guide_done TINYINT(1) NOT NULL DEFAULT 0,
            identity_done TINYINT(1) NOT NULL DEFAULT 0,
            license_done TINYINT(1) NOT NULL DEFAULT 0,
            education_done TINYINT(1) NOT NULL DEFAULT 0,
            verify_done TINYINT(1) NOT NULL DEFAULT 0,
            completed_at DATETIME NULL,
            reward_claimed_at DATETIME NULL,
            reward_opened_at DATETIME NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_cookie_newbie_license (license)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    local alters = {
        'ALTER TABLE cookie_newbie_progress ADD COLUMN IF NOT EXISTS verify_done TINYINT(1) NOT NULL DEFAULT 0 AFTER education_done',
        'ALTER TABLE cookie_newbie_progress ADD COLUMN IF NOT EXISTS reward_claimed_at DATETIME NULL AFTER completed_at',
        'ALTER TABLE cookie_newbie_progress ADD COLUMN IF NOT EXISTS reward_opened_at DATETIME NULL AFTER reward_claimed_at',
    }

    for i = 1, #alters do
        pcall(function()
            MySQL.query.await(alters[i])
        end)
    end

    print('^2[cookie_newbie]^7 V1.1.0 verify/reward ready')
end)
