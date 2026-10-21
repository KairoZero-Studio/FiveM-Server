

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_chat_mute` (
              `license`    VARCHAR(255) NOT NULL PRIMARY KEY,
              `gobun`      INT          NULL,
              `until_at`   DATETIME     NOT NULL,
              `reason`     VARCHAR(200) NULL,
              `muted_by`   VARCHAR(60)  NULL,
              `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_chat_log` (
              `id`         INT AUTO_INCREMENT PRIMARY KEY,
              `gobun`      INT          NULL,
              `nickname`   VARCHAR(50)  NULL,
              `channel`    VARCHAR(20)  NULL,
              `message`    TEXT         NULL,
              `blocked`    VARCHAR(20)  NULL,   -- filter / spam / mute / null(정상)
              `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
              KEY `idx_gobun` (`gobun`),
              KEY `idx_blocked` (`blocked`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})
    end)

    if ok then

    else

    end
end)

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function isAdmin(src)
    return IsPlayerAceAllowed(src, Config.adminAce)
end

local function headOf(src)
    local ok, info = pcall(function() return exports.cookie_core:getHeadInfo(src) end)
    if ok and info then return info end
    return { gobun = nil, nick = GetPlayerName(src) or '?' }
end

function CookieChatFindByGobun(gobun)
    gobun = tonumber(gobun)
    if not gobun then return nil end
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local info = headOf(pid)
        if tonumber(info.gobun) == gobun then return pid, info end
    end
    return nil
end

local function notify(src, msg)
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'cookie_system',
        args = { msg }
    })
end

local function normalize(text)
    local s = tostring(text or ''):lower()
    s = s:gsub('[%s%p%d]', '')
    return s
end

function CookieChatFilter(src, text)
    if not Config.filterEnabled then return nil end

    local admin = isAdmin(src)

    if not (admin and Config.filterAdminExempt) then
        local norm = normalize(text)
        for i = 1, #Config.bannedWords do
            local w = normalize(Config.bannedWords[i])
            if w ~= '' and norm:find(w, 1, true) then
                return '금칙어'
            end
        end
    end

    if Config.blockLinks and not (admin and Config.linkAdminExempt) then
        local lower = tostring(text or ''):lower()
        for i = 1, #Config.linkPatterns do
            if lower:find(Config.linkPatterns[i]) then
                return '외부 링크'
            end
        end
    end

    return nil
end

local recent = {}

function CookieChatSpam(src, text)
    if not Config.spamEnabled then return nil end

    if isAdmin(src) and Config.filterAdminExempt then return nil end

    local now = os.time()
    local win = Config.spamWindow or 8

    local list = recent[src] or {}

    local keep = {}
    for i = 1, #list do
        if (now - list[i].t) <= win then keep[#keep + 1] = list[i] end
    end

    keep[#keep + 1] = { t = now, msg = tostring(text or '') }
    recent[src] = keep

    if #keep > (Config.spamMaxMessages or 5) then
        CookieChatMuteSeconds(src, Config.spamMuteSeconds or 30, '도배(연속 전송)', '시스템')
        recent[src] = nil
        return '도배'
    end

    local same = 0
    local last = keep[#keep].msg
    for i = #keep, 1, -1 do
        if keep[i].msg == last then
            same = same + 1
        else
            break
        end
    end

    if same >= (Config.spamSameRepeat or 5) then
        CookieChatMuteSeconds(src, Config.spamMuteSeconds or 30, '도배(같은 내용 반복)', '시스템')
        recent[src] = nil
        return '도배'
    end

    return nil
end

local muteCache = {}

function CookieChatMuted(src)
    local license = getLicense(src)
    if not license then return 0 end

    local cached = muteCache[license]
    if cached then
        local left = cached - os.time()
        if left > 0 then return left end
        muteCache[license] = nil
        return 0
    end

    local row = MySQL.single.await(
        'SELECT UNIX_TIMESTAMP(until_at) AS until_ts FROM cookie_chat_mute WHERE license = ? AND until_at > NOW()',
        { license })
    if not row then return 0 end

    muteCache[license] = tonumber(row.until_ts) or 0
    return math.max(0, muteCache[license] - os.time())
end

local function durText(seconds)
    if seconds < 60 then return ('%d초'):format(seconds) end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if s == 0 then return ('%d분'):format(m) end
    return ('%d분 %d초'):format(m, s)
end

function CookieChatMuteSeconds(src, seconds, reason, byName)
    local license = getLicense(src)
    if not license then return false end

    seconds = math.max(1, math.floor(tonumber(seconds) or 60))
    local info = headOf(src)

    MySQL.query.await([[
        INSERT INTO cookie_chat_mute (license, gobun, until_at, reason, muted_by)
        VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND), ?, ?)
        ON DUPLICATE KEY UPDATE
            until_at = VALUES(until_at), reason = VALUES(reason), muted_by = VALUES(muted_by)
    ]], { license, info.gobun, seconds, reason or '-', byName or '-' })

    muteCache[license] = os.time() + seconds

    notify(src, ('채팅이 %s간 제한되었습니다. 사유: %s'):format(durText(seconds), reason or '-'))

    return true
end

function CookieChatMute(src, minutes, reason, byName)
    minutes = tonumber(minutes) or Config.muteDefaultMinutes or 10
    return CookieChatMuteSeconds(src, math.floor(minutes * 60), reason, byName)
end

function CookieChatUnmute(src)
    local license = getLicense(src)
    if not license then return false end
    MySQL.query.await('DELETE FROM cookie_chat_mute WHERE license = ?', { license })
    muteCache[license] = nil
    return true
end

function CookieChatLog(src, channel, message, blocked)
end

AddEventHandler('playerDropped', function()
    recent[source] = nil
end)

AddEventHandler('cookie_chat:server:mute', function(data)
    if type(data) ~= 'table' then return end
    local target = tonumber(data.target)
    if not target or GetPlayerName(target) == nil then return end

    if data.unmute then
        CookieChatUnmute(target)
        notify(target, '채팅 제한이 해제되었습니다.')
    else
        CookieChatMute(target, data.minutes, data.reason or '관리자 조치', data.byName or '관리자')
    end
end)

RegisterCommand('공지', function(src, args, raw)
    if src == 0 then return end
    if not isAdmin(src) then
        return notify(src, '공지 권한이 없습니다.')
    end

    local msg = raw:sub(#'/공지' + 2)
    msg = msg:gsub('^%s+', ''):gsub('%s+$', '')
    if msg == '' then
        return notify(src, '사용법: /공지 <내용>')
    end

    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'cookie_notice',
        args = { msg }
    })

end, false)

RegisterCommand('경고', function(src, args, raw)
    if src == 0 then return end
    if not isAdmin(src) then
        return notify(src, '경고 권한이 없습니다.')
    end

    if #args == 0 then
        return notify(src, '사용법: /경고 <고유번호> <내용>  또는  /경고 <내용>(전체)')
    end

    local target, rest
    local maybeGobun = tonumber(args[1])

    if maybeGobun then
        local pid = CookieChatFindByGobun(maybeGobun)
        if not pid then
            return notify(src, ('%d번은 접속 중이 아닙니다.'):format(maybeGobun))
        end
        target = pid

        rest = raw:sub(#('/경고 ' .. args[1]) + 2)
    else
        rest = raw:sub(#'/경고' + 2)
    end

    rest = rest:gsub('^%s+', ''):gsub('%s+$', '')
    if rest == '' then
        return notify(src, '경고 내용을 입력해주세요.')
    end

    TriggerClientEvent('chat:addMessage', target or -1, {
        templateId = 'cookie_warn',
        args = { rest }
    })

    if target then
        notify(src, ('%d번에게 경고를 보냈습니다.'):format(maybeGobun))
    end

end, false)

RegisterCommand('입막음', function(src, args)
    if src == 0 then return end
    if not isAdmin(src) then
        return notify(src, '뮤트 권한이 없습니다.')
    end

    local gobun = tonumber(args[1])
    if not gobun then
        return notify(src, '사용법: /입막음 <고유번호> [분]')
    end

    local pid, info = CookieChatFindByGobun(gobun)
    if not pid then
        return notify(src, ('%d번은 접속 중이 아닙니다.'):format(gobun))
    end

    local minutes = tonumber(args[2]) or Config.muteDefaultMinutes or 10
    local me = headOf(src)

    CookieChatMute(pid, minutes, '관리자 조치', me.nick)
    notify(src, ('%s (%d) 님을 %d분간 입막음했습니다.'):format(info.nick, gobun, minutes))
end, false)

RegisterCommand('입막음해제', function(src, args)
    if src == 0 then return end
    if not isAdmin(src) then
        return notify(src, '뮤트 권한이 없습니다.')
    end

    local gobun = tonumber(args[1])
    if not gobun then
        return notify(src, '사용법: /입막음해제 <고유번호>')
    end

    local pid, info = CookieChatFindByGobun(gobun)
    if not pid then
        return notify(src, ('%d번은 접속 중이 아닙니다.'):format(gobun))
    end

    CookieChatUnmute(pid)
    notify(pid, '채팅 제한이 해제되었습니다.')
    notify(src, ('%s (%d) 님의 입막음을 해제했습니다.'):format(info.nick, gobun))
end, false)
