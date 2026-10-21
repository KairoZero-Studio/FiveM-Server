

local function getLicense(src)
    local license = GetPlayerIdentifierByType(src, 'license2')
    if not license then
        license = GetPlayerIdentifierByType(src, 'license')
    end
    return license
end

local function fetchUser(license)
    return MySQL.single.await(
        'SELECT gobun FROM cookie_user WHERE license = ?',
        { license }
    )
end

local function isLicenseOnboarded(license)
    local row = MySQL.single.await(
        'SELECT 1 AS x FROM cookie_user WHERE license = ? AND nickname IS NOT NULL AND consent_at IS NOT NULL',
        { license }
    )
    return row ~= nil
end

local function getNicknameFor(license)
    local row = MySQL.single.await('SELECT nickname FROM cookie_user WHERE license = ?', { license })
    return row and row.nickname or nil
end

local function issueGobun(license)

    local existing = MySQL.single.await('SELECT gobun FROM cookie_user WHERE license = ?', { license })
    if existing then
        return existing.gobun
    end

    for attempt = 1, 2 do

        local maxRow = MySQL.single.await('SELECT MAX(gobun) AS maxg FROM cookie_user')
        local nextGobun = (maxRow and maxRow.maxg) and (maxRow.maxg + 1) or Config.gobunStart

        local ok, insertId = pcall(function()
            return MySQL.insert.await(
                'INSERT INTO cookie_user (license, gobun) VALUES (?, ?)',
                { license, nextGobun }
            )
        end)

        if ok and insertId then

            return nextGobun
        end

        local raced = MySQL.single.await('SELECT gobun FROM cookie_user WHERE license = ?', { license })
        if raced then

            return raced.gobun
        end

    end

    return nil
end

CookieIssueGobun = issueGobun

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local license = getLicense(src)
    if not license then

        return
    end

    if isLicenseOnboarded(license) then

        local nick = getNicknameFor(license)
        if nick and nick ~= '' then
            exports.chat:addMessage(-1, {
                templateId = 'cookie_join',
                args = { ('%s님 어서오세요! 쿠키서버 입니다!'):format(nick) }
            })

            TriggerClientEvent('cookie_hud:setName', src, nick)

            local user = fetchUser(license)
            Player(src).state:set('ckHead', { gobun = user and user.gobun or 0, nick = nick }, true)
        end
    else

    end
end)

exports('getGobun', function(src)
    local license = getLicense(src)
    if not license then return nil end
    local user = fetchUser(license)
    if not user then return nil end
    return user.gobun
end)

local function getGobunFor(src)
    local license = getLicense(src)
    if not license then return nil end
    local user = fetchUser(license)
    if not user then return nil end
    return user.gobun
end

local function getJobName(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.job and player.PlayerData.job.name or nil
end

local function getJobLabel(src)
    local name = getJobName(src)
    return (name and Config.jobLabels[name]) or '시민'
end

local function getNick(src)
    local license = getLicense(src)
    if license then
        local nickname = getNicknameFor(license)
        if nickname and nickname ~= '' then return nickname end
    end
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.charinfo then
        local ci = player.PlayerData.charinfo
        return ('%s %s'):format(ci.firstname or '', ci.lastname or '')
    end
    return GetPlayerName(src) or ''
end

local function getDutyState(src)
    local ok, state = pcall(function() return exports.cookie_admin:getState(src) end)
    if ok and state then return state end
    return 'rp'
end

-- 채팅 칩은 출퇴근 여부가 아니라 실제 팩션 소속을 기준으로 표시한다.
-- ESC 유저리스트의 정부 팩션 인원 집계(출근자만)는 cookie_esc에서 별도로 처리한다.
local function normalizeRgb(value)
    local c = tostring(value or ''):upper():gsub('%s+', '')
    if c:match('^#%x%x%x%x%x%x$') then return c end
    return nil
end

local function getFactionChatInfo(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil, nil end

    local ok, faction = pcall(function()
        return exports.cookie_admin:getFactionOf(src)
    end)
    if not ok or not faction then return nil, nil end

    local label
    local tag = tostring(faction.tagName or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if tag ~= '' then
        label = tag
    else
        local typeLabels = (Config and Config.factionChatLabels) or {}
        local byType = typeLabels[tostring(faction.type or '')]
        if byType and byType ~= '' then
            label = byType
        else
            local name = tostring(faction.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if name ~= '' then label = name end
        end
    end

    return label, normalizeRgb(faction.color)
end

exports('getHeadInfo', function(src)
    local duty = getDutyState(src)
    local middle
    local chipColor

    -- 관리자 근무 중에는 관리자 칩을 최우선으로 유지한다.
    if duty == 'duty' then
        middle = '관리자'
        chipColor = '#FF4D4F'
    else
        -- 경찰/보안국을 포함한 실제 팩션 소속은 퇴근 중에도 채팅에 표시한다.
        local factionLabel, factionColor = getFactionChatInfo(src)
        if factionLabel and factionLabel ~= '' then
            middle = factionLabel
            chipColor = factionColor
        elseif Config.hideDefaultJobChip then
            local name = getJobName(src)
            middle = (name == nil or name == Config.defaultJob) and '' or getJobLabel(src)
        else
            middle = getJobLabel(src)
        end
    end

    local info = {
        gobun = getGobunFor(src),
        job   = middle,
        nick  = getNick(src),
        color = chipColor,
    }

    return info
end)

local function validateNickname(nickname)
    if type(nickname) ~= 'string' then
        return { ok = false, reason = '별명을 입력해주세요' }
    end

    local len = utf8.len(nickname)
    if not len then
        return { ok = false, reason = '별명 형식이 올바르지 않습니다' }
    end
    if len < Config.nicknameMin or len > Config.nicknameMax then
        return { ok = false, reason = ('%d~%d자로 입력해주세요'):format(Config.nicknameMin, Config.nicknameMax) }
    end

    for _, cp in utf8.codes(nickname) do
        local isAscii  = (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
        local isHangul = cp >= 0xAC00 and cp <= 0xD7A3
        if not (isAscii or isHangul) then
            return { ok = false, reason = '한글/영문/숫자만 사용할 수 있습니다' }
        end
    end

    local lower = nickname:lower()
    for i = 1, #Config.bannedNicknames do
        if lower == Config.bannedNicknames[i] then
            return { ok = false, reason = '사용할 수 없는 별명입니다' }
        end
    end

    return { ok = true, reason = '사용 가능한 별명입니다' }
end

exports('isOnboarded', function(src)
    local license = getLicense(src)
    if not license then return false end
    return isLicenseOnboarded(license)
end)

exports('getNickname', function(src)
    local license = getLicense(src)
    if not license then return nil end
    return getNicknameFor(license)
end)

exports('checkNickname', function(nickname)
    local base = validateNickname(nickname)
    if not base.ok then return base end

    local dup = MySQL.single.await(
        'SELECT 1 AS x FROM cookie_user WHERE BINARY nickname = ? LIMIT 1',
        { nickname }
    )
    if dup then
        return { ok = false, reason = '이미 사용 중인 별명입니다' }
    end
    return { ok = true, reason = '사용 가능한 별명입니다' }
end)

exports('completeOnboarding', function(src, nickname)
    local license = getLicense(src)
    if not license then
        return { ok = false, reason = '식별 실패' }
    end

    local check = validateNickname(nickname)
    if not check.ok then
        return check
    end

    local gobun = issueGobun(license)
    if not gobun then
        return { ok = false, reason = '고번 발급 실패' }
    end

    -- V1.0 신규 흐름:
    -- 최초 온보딩에서는 이용 동의 + 별명만 완료한다.
    -- 주민번호/전화번호/운전면허/교육은 뉴비 시청에서 별도로 진행한다.
    local dup = MySQL.single.await(
        'SELECT 1 AS x FROM cookie_user WHERE BINARY nickname = ? AND license <> ? LIMIT 1',
        { nickname, license }
    )
    if dup then
        return { ok = false, reason = '이미 사용 중인 별명입니다' }
    end

    local ok = pcall(function()
        MySQL.update.await(
            'UPDATE cookie_user SET nickname = ?, consent_at = NOW() WHERE license = ?',
            { nickname, license }
        )
    end)
    if not ok then
        return { ok = false, reason = '이미 사용 중인 별명입니다' }
    end

    return { ok = true, gobun = gobun, nickname = nickname }
end)

exports('resetOnboarding', function(license)
    if type(license) ~= 'string' or license == '' then
        return false
    end

    -- 온보딩 재설정은 로그인 단계만 초기화한다.
    -- 뉴비 시청에서 발급받은 주민번호/전화번호 등은 보존한다.
    MySQL.update.await([[
        UPDATE cookie_user
        SET nickname = NULL, consent_at = NULL
        WHERE license = ?
    ]], { license })

    return true
end)

CreateThread(function()
    local function hasColumn(col)
        local row = MySQL.single.await([[
            SELECT 1 AS x FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cookie_user' AND COLUMN_NAME = ?
            LIMIT 1
        ]], { col })
        return row ~= nil
    end

    local added = {}
    if not hasColumn('jumin') then
        MySQL.query.await("ALTER TABLE cookie_user ADD COLUMN jumin VARCHAR(14) NULL UNIQUE")
        added[#added + 1] = 'jumin'
    end
    if not hasColumn('age') then
        MySQL.query.await("ALTER TABLE cookie_user ADD COLUMN age TINYINT UNSIGNED NULL")
        added[#added + 1] = 'age'
    end
    if not hasColumn('phone') then
        MySQL.query.await("ALTER TABLE cookie_user ADD COLUMN phone VARCHAR(20) NULL UNIQUE")
        added[#added + 1] = 'phone'
    end
    if not hasColumn('gender') then

        MySQL.query.await("ALTER TABLE cookie_user ADD COLUMN gender VARCHAR(2) NULL")
        added[#added + 1] = 'gender'
    end

    if #added > 0 then

    end
end)

local AGE_MIN, AGE_MAX = 18, 80

local function validateAge(age)
    age = tonumber(age)
    if not age or age % 1 ~= 0 then
        return nil, '나이는 숫자로 입력해주세요'
    end
    if age < AGE_MIN or age > AGE_MAX then
        return nil, ('나이는 %d~%d세만 가능합니다'):format(AGE_MIN, AGE_MAX)
    end
    return math.floor(age), nil
end

local function makeJumin(age, gender)
    local birthYear = tonumber(os.date('%Y')) - age

    local base = (birthYear >= 2000) and 3 or 1
    local s = base + ((gender == '여') and 1 or 0)

    return ('%d%06d'):format(s, math.random(0, 999999))
end

local function makePhone()
    return ('010-%04d-%04d'):format(math.random(0, 9999), math.random(0, 9999))
end

local function issueUnique(column, license, generator, tries)

    local cur = MySQL.single.await(
        ('SELECT `%s` AS v FROM cookie_user WHERE license = ?'):format(column), { license }
    )
    if cur and cur.v and cur.v ~= '' then
        return cur.v, true
    end

    for _ = 1, (tries or 20) do
        local value = generator()
        local dup = MySQL.single.await(
            ('SELECT 1 AS x FROM cookie_user WHERE `%s` = ? LIMIT 1'):format(column), { value }
        )
        if not dup then
            local ok = pcall(function()
                MySQL.update.await(
                    ('UPDATE cookie_user SET `%s` = ? WHERE license = ?'):format(column),
                    { value, license }
                )
            end)
            if ok then return value, false end
        end
    end
    return nil, false
end

exports('issueJumin', function(src, age, gender)
    local license = getLicense(src)
    if not license then return { ok = false, reason = '식별 실패' } end

    local clean, err = validateAge(age)
    if not clean then return { ok = false, reason = err } end

    if gender ~= '남' and gender ~= '여' then
        return { ok = false, reason = '성별을 선택해주세요' }
    end

    if not issueGobun(license) then
        return { ok = false, reason = '고번 발급 실패' }
    end

    MySQL.update.await(
        'UPDATE cookie_user SET age = ?, gender = ? WHERE license = ?',
        { clean, gender, license }
    )

    local jumin, existed = issueUnique('jumin', license, function()
        return makeJumin(clean, gender)
    end)
    if not jumin then
        return { ok = false, reason = '주민등록번호 발급 실패' }
    end

    return { ok = true, jumin = jumin, age = clean, gender = gender }
end)

local function issuePhoneInternal(src)
    local license = getLicense(src)
    if not license then return { ok = false, reason = '식별 실패' } end

    if not issueGobun(license) then
        return { ok = false, reason = '고번 발급 실패' }
    end

    local phone, existed = issueUnique('phone', license, makePhone)
    if not phone then
        return { ok = false, reason = '전화번호 발급 실패' }
    end

    return { ok = true, phone = phone }
end

exports('issuePhone', function(src)
    return issuePhoneInternal(src)
end)

-- 뉴비 시청 전용 주민번호. 실제 주민등록번호 형식을 사용하지 않는 COOKIE 전용 번호다.
local function issueNewbieJumin(src)
    local license = getLicense(src)
    if not license then return { ok = false, reason = '식별 실패' } end

    local gobun = issueGobun(license)
    if not gobun then return { ok = false, reason = '고번 발급 실패' } end

    local row = MySQL.single.await('SELECT jumin FROM cookie_user WHERE license = ?', { license })
    if row and row.jumin and row.jumin ~= '' then
        return { ok = true, jumin = row.jumin, existed = true }
    end

    -- 고번 기반이라 중복되지 않고, 실제 대한민국 주민번호와 혼동되지 않는다.
    local jumin = ('CKR-%06d'):format(tonumber(gobun) or 0)
    local ok = pcall(function()
        MySQL.update.await('UPDATE cookie_user SET jumin = ? WHERE license = ?', { jumin, license })
    end)
    if not ok then return { ok = false, reason = '주민번호 발급 실패' } end

    return { ok = true, jumin = jumin, existed = false }
end

exports('issueNewbieJumin', function(src)
    return issueNewbieJumin(src)
end)

exports('issueNewbieIdentity', function(src)
    local jr = issueNewbieJumin(src)
    if not jr or not jr.ok then return jr or { ok=false, reason='주민번호 발급 실패' } end

    local pr = issuePhoneInternal(src)
    if not pr or not pr.ok then
        return { ok = false, reason = (pr and pr.reason) or '전화번호 발급 실패', jumin = jr.jumin }
    end

    return { ok = true, jumin = jr.jumin, phone = pr.phone }
end)

local FREEMODE = { ['남'] = 'mp_m_freemode_01', ['여'] = 'mp_f_freemode_01' }

local function fetchChars(license)
    local rows = MySQL.query.await(
        'SELECT citizenid, charinfo FROM players WHERE license = ?', { license }
    ) or {}
    local out = {}
    for i = 1, #rows do
        local ci = rows[i].charinfo
        if type(ci) == 'string' then ci = json.decode(ci) end
        if type(ci) == 'table' then
            out[#out + 1] = {
                citizenid = rows[i].citizenid,
                gender = (tonumber(ci.gender) == 1) and '여' or '남',
                charinfo = ci,
            }
        end
    end
    return out
end

exports('genderConflict', function(src, gender)
    local license = getLicense(src)
    if not license then return { conflict = false } end
    if gender ~= '남' and gender ~= '여' then return { conflict = false } end

    local chars = fetchChars(license)
    local n, current = 0, nil
    for i = 1, #chars do
        if chars[i].gender ~= gender then
            n = n + 1
            current = chars[i].gender
        end
    end

    if n == 0 then return { conflict = false } end
    return { conflict = true, current = current, count = n }
end)

function CookieApplyGenderChange(license, gender)
    local chars = fetchChars(license)
    local changed = 0

    for i = 1, #chars do
        local c = chars[i]
        if c.gender ~= gender then
            c.charinfo.gender = (gender == '여') and 1 or 0
            MySQL.update.await(
                'UPDATE players SET charinfo = ? WHERE citizenid = ?',
                { json.encode(c.charinfo), c.citizenid }
            )

            MySQL.query.await('DELETE FROM playerskins WHERE citizenid = ?', { c.citizenid })
            changed = changed + 1

        end
    end

    return changed
end

exports('getIdentity', function(src)
    local license = getLicense(src)
    if not license then return nil end
    return MySQL.single.await(
        'SELECT gobun, nickname, jumin, age, phone, gender FROM cookie_user WHERE license = ?',
        { license }
    )
end)

SetConvarReplicated('cookie:introDebug', Config.introDebug and 'true' or 'false')

