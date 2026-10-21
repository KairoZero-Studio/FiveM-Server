

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

CreateThread(function()
    local steps = {
        [[CREATE TABLE IF NOT EXISTS `cookie_verify` (
            `code`         VARCHAR(12)  NOT NULL PRIMARY KEY,
            `discord_id`   VARCHAR(50)  NOT NULL,
            `discord_tag`  VARCHAR(64)  DEFAULT NULL,
            `issued_at`    DATETIME     NOT NULL,
            `expires_at`   DATETIME     NOT NULL,
            `used_at`      DATETIME     DEFAULT NULL,
            `used_license` VARCHAR(255) DEFAULT NULL,
            KEY `idx_discord` (`discord_id`),
            KEY `idx_expires` (`expires_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],

        "ALTER TABLE `cookie_user` ADD COLUMN IF NOT EXISTS `verified_at` DATETIME NULL",
        "ALTER TABLE `cookie_user` ADD UNIQUE KEY IF NOT EXISTS `uq_discord` (`discord_id`)",
    }

    local failed = 0
    for i = 1, #steps do

        local ok, err = pcall(function() MySQL.query.await(steps[i], {}) end)
        if not ok then
            failed = failed + 1

        end
    end

    if failed == 0 then

    else

    end
end)

local function randomCode()
    local n = Config.verifyCodeLength or 6
    local buf = {}
    for i = 1, n do buf[i] = tostring(math.random(0, 9)) end
    return table.concat(buf)
end

local function makeUniqueCode()
    for _ = 1, 8 do
        local code = randomCode()
        local dup = MySQL.single.await('SELECT 1 AS x FROM cookie_verify WHERE code = ?', { code })
        if not dup then return code end
    end
    return nil
end

local function userByLicense(license)
    return MySQL.single.await(
        'SELECT gobun, nickname, is_verified FROM cookie_user WHERE license = ?', { license })
end

local function userByDiscord(discordId)
    return MySQL.single.await(
        'SELECT gobun, nickname, is_verified FROM cookie_user WHERE discord_id = ?', { discordId })
end

local function isVerifiedLicense(license)
    local u = userByLicense(license)
    return u ~= nil and (tonumber(u.is_verified) or 0) == 1
end

exports('needsVerify', function(src)
    if not Config.verifyEnabled then return false end
    local license = getLicense(src)
    if not license then return false end
    return not isVerifiedLicense(license)
end)

exports('isVerified', function(src)
    if not Config.verifyEnabled then return true end
    local license = getLicense(src)
    return license ~= nil and isVerifiedLicense(license)
end)

exports('getVerifyInfo', function()
    return {
        ok = true,
        invite = Config.discordInvite or '',
        url = Config.discordUrl or '',
        channel = Config.discordChannel or '',
        length = Config.verifyCodeLength or 6,
    }
end)

local attempts = {}

local function checkLock(src)
    local a = attempts[src]
    if not a then return nil end
    if a.lockedUntil and a.lockedUntil > os.time() then
        return a.lockedUntil - os.time()
    end
    return nil
end

local function bumpAttempt(src)
    local a = attempts[src] or { count = 0 }
    a.count = a.count + 1
    if a.count >= (Config.verifyMaxAttempts or 5) then
        a.count = 0
        a.lockedUntil = os.time() + (Config.verifyLockSec or 60)
    end
    attempts[src] = a
    return a
end

AddEventHandler('playerDropped', function()
    attempts[source] = nil
end)

exports('redeemCode', function(src, code)
    local license = getLicense(src)
    if not license then
        return { ok = false, reason = '식별에 실패했습니다. 재접속해주세요' }
    end

    local existing = userByLicense(license)
    if existing and (tonumber(existing.is_verified) or 0) == 1 then
        return { ok = true, gobun = existing.gobun, already = true }
    end

    local left = checkLock(src)
    if left then
        return { ok = false, reason = ('입력을 너무 많이 틀렸습니다. %d초 후 다시 시도해주세요'):format(left), lock = left }
    end

    code = tostring(code or ''):gsub('%s', '')
    if code == '' then
        return { ok = false, reason = '인증코드를 입력해주세요' }
    end

    local row = MySQL.single.await([[
        SELECT code, discord_id, discord_tag
        FROM cookie_verify
        WHERE code = ? AND used_at IS NULL AND expires_at > NOW()
    ]], { code })

    if not row then
        local a = bumpAttempt(src)

        if a.lockedUntil and a.lockedUntil > os.time() then
            return { ok = false, reason = '입력을 너무 많이 틀렸습니다. 잠시 후 다시 시도해주세요', lock = a.lockedUntil - os.time() }
        end
        local remain = (Config.verifyMaxAttempts or 5) - a.count
        return { ok = false, reason = ('인증코드가 올바르지 않거나 만료되었습니다 (남은 시도 %d회)'):format(remain) }
    end

    local bound = userByDiscord(row.discord_id)
    if bound then

        return { ok = false, reason = ('이 디스코드 계정은 이미 %d번으로 인증되어 있습니다'):format(bound.gobun) }
    end

    local gobun = CookieIssueGobun(license)
    if not gobun then
        return { ok = false, reason = '고정번호 발급에 실패했습니다. 운영진에게 문의해주세요' }
    end

    local ok = pcall(function()
        MySQL.update.await([[
            UPDATE cookie_user
            SET is_verified = 1, discord_id = ?, verified_at = NOW()
            WHERE license = ?
        ]], { row.discord_id, license })
    end)
    if not ok then
        return { ok = false, reason = '이미 사용 중인 디스코드 계정입니다' }
    end

    MySQL.update.await(
        'UPDATE cookie_verify SET used_at = NOW(), used_license = ? WHERE code = ?',
        { license, code })

    attempts[src] = nil

    return { ok = true, gobun = gobun }
end)

local function reply(res, status, tbl)
    res.writeHead(status, { ['Content-Type'] = 'application/json; charset=utf-8' })
    res.send(json.encode(tbl))
end

local function auth(data)
    local token = GetConvar(Config.verifyTokenConvar, '')
    if token == '' then return false, 503, '서버 인증 토큰 미설정' end
    if not data or data.token ~= token then return false, 403, '토큰 불일치' end
    return true
end

local function handleIssue(data, res)
    local did = tostring(data.discord_id or '')
    if did == '' then
        return reply(res, 400, { ok = false, reason = 'discord_id가 필요합니다' })
    end

    local bound = userByDiscord(did)
    if bound and (tonumber(bound.is_verified) or 0) == 1 then
        return reply(res, 200, {
            ok = false, verified = true, gobun = bound.gobun, nickname = bound.nickname,
            reason = '이미 인증이 완료된 계정입니다',
        })
    end

    MySQL.update.await(
        'UPDATE cookie_verify SET expires_at = NOW() WHERE discord_id = ? AND used_at IS NULL',
        { did })

    local code = makeUniqueCode()
    if not code then
        return reply(res, 500, { ok = false, reason = '코드 생성 실패. 잠시 후 다시 시도해주세요' })
    end

    local ttl = Config.verifyCodeTTL or 10
    MySQL.insert.await([[
        INSERT INTO cookie_verify (code, discord_id, discord_tag, issued_at, expires_at)
        VALUES (?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? MINUTE))
    ]], { code, did, tostring(data.discord_tag or ''), ttl })

    return reply(res, 200, { ok = true, code = code, ttl = ttl })
end

local function handleStatus(data, res)
    local did = tostring(data.discord_id or '')
    if did == '' then
        return reply(res, 400, { ok = false, reason = 'discord_id가 필요합니다' })
    end
    local u = userByDiscord(did)
    local verified = u ~= nil and (tonumber(u.is_verified) or 0) == 1
    return reply(res, 200, {
        ok = true,
        verified = verified,
        gobun = u and u.gobun or nil,
        nickname = u and u.nickname or nil,
    })
end

SetHttpHandler(function(req, res)
    local path = (req.path or ''):gsub('^/cookie_core', ''):gsub('%?.*$', '')

    if req.method ~= 'POST' or (path ~= '/issue' and path ~= '/status') then
        res.writeHead(404, { ['Content-Type'] = 'application/json' })
        res.send(json.encode({ ok = false, reason = 'not found' }))
        return
    end

    req.setDataHandler(function(body)

        CreateThread(function()
            local ok, err = pcall(function()
                local data = body and json.decode(body) or nil
                if type(data) ~= 'table' then
                    return reply(res, 400, { ok = false, reason = '요청 형식 오류' })
                end

                local pass, code, reason = auth(data)
                if not pass then

                    return reply(res, code, { ok = false, reason = reason })
                end

                if path == '/issue' then
                    return handleIssue(data, res)
                end
                return handleStatus(data, res)
            end)

            if not ok then

                pcall(function()
                    res.writeHead(500, { ['Content-Type'] = 'application/json' })
                    res.send(json.encode({ ok = false, reason = '서버 오류' }))
                end)
            end
        end)
    end)
end)

CreateThread(function()
    while true do
        Wait(600000)
        MySQL.query.await('DELETE FROM cookie_verify WHERE used_at IS NULL AND expires_at < DATE_SUB(NOW(), INTERVAL 1 DAY)')
    end
end)

CreateThread(function()
    Wait(2000)
    if GetConvar(Config.verifyTokenConvar, '') == '' then

    else

    end
end)
