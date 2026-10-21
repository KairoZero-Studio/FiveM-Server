SetConvarReplicated('chat_showJoins', 'false')
SetConvarReplicated('chat_showQuits', 'false')

-- COOKIE CHAT LEAVE REASON V14.2.9
-- FiveM playerDropped: reason, resourceName, clientDropReason
-- 관리자 킥/밴은 DropPlayer 직전에 markDrop 로 정확한 종류/사유를 넘겨 분류한다.

local dropMarks = {}

local function cleanText(v, maxLen)
    local s = tostring(v or '')
    s = s:gsub('%^%d', '')
    s = s:gsub('[\r\n\t]+', ' ')
    s = s:gsub('%s+', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #s > maxLen then
        s = s:sub(1, maxLen) .. '…'
    end
    return s
end

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function identitySnapshot(src)
    local fallbackName = cleanText(GetPlayerName(src) or '', 64)
    local stateGobun, stateNick

    pcall(function()
        local p = Player(src)
        local h = p and p.state and p.state.ckHead or nil
        if type(h) == 'table' then
            stateGobun = tonumber(h.gobun)
            stateNick = cleanText(h.nick, 64)
        end
    end)

    local license = getLicense(src)
    local row
    if license then
        local ok, result = pcall(function()
            return MySQL.single.await(
                'SELECT gobun, nickname FROM cookie_user WHERE license = ? LIMIT 1',
                { license }
            )
        end)
        if ok then row = result end
    end

    local gobun = row and tonumber(row.gobun) or stateGobun
    local nick = row and cleanText(row.nickname, 64) or stateNick
    if not nick or nick == '' then nick = fallbackName end
    if not nick or nick == '' then nick = '알 수 없는 유저' end

    return gobun, nick
end

local function containsAny(text, words)
    for i = 1, #words do
        if text:find(words[i], 1, true) then return true end
    end
    return false
end

local function classifyDrop(reason, resourceName, clientDropReason, marked)
    if marked then
        if marked.kind == 'ban' then
            return '밴', cleanText(marked.detail, 140)
        elseif marked.kind == 'kick' then
            return '킥', cleanText(marked.detail, 140)
        elseif marked.kind == 'reboot' then
            return '리붓 후 다시 접속해주세요', ''
        end
    end

    local raw = cleanText(reason, 240)
    local lower = raw:lower()
    local code = tonumber(clientDropReason) or 0

    -- 다른 관리자/txAdmin/외부 리소스의 밴/킥도 문구로 최대한 정확히 잡는다.
    if containsAny(lower, {
        'you have been banned', 'you are banned', 'banned', ' ban ', '[ban]',
        '이용이 제한', '밴되었습니다', '밴 되었습니다', '영구밴', '영구 밴', '차단되었습니다'
    }) then
        return '밴', raw
    end

    if containsAny(lower, {
        'kicked', 'kick', '추방', '서버에서 제거', '관리자에 의해 서버에서 추방'
    }) then
        return '킥', raw
    end

    -- 명시적인 크래시 문자열이 오는 경우에만 크래시로 단정한다.
    if containsAny(lower, {
        'crash', 'crashed', 'game crashed', 'fatal error', 'citizenfx fatal', 'gta5.exe'
    }) then
        return '크래시', ''
    end

    -- FiveM ClientDropReason enum 기준
    -- 2 CLIENT = 클라이언트가 정상적으로 disconnect를 요청함.
    if code == 2 or containsAny(lower, { 'exiting', 'quit', 'client initiated disconnect' }) then
        return '게임 종료', ''
    end

    -- 3 SERVER = 서버가 연결 종료. 밴은 위에서 걸렀으므로 일반적으로 킥으로 표시.
    if code == 3 then
        return '킥', raw
    end

    -- 4 중복 클라이언트가 기존 세션을 밀어냄.
    if code == 4 then
        return '강제 종료', '중복 접속으로 기존 연결 종료'
    end

    -- 5/6은 연결 타임아웃. 작업관리자 종료/인터넷 단절/일부 크래시는 서버에서
    -- 서로 완전히 구별할 수 없어 강제 종료로 묶고 상세 원인을 남긴다.
    if code == 5 or code == 6 or containsAny(lower, {
        'timed out', 'timeout', 'connection lost', 'connection closed', 'network error'
    }) then
        return '강제 종료', '연결 시간 초과/연결 끊김'
    end

    if code == 7 then
        return '서버 종료', ''
    end

    -- 리소스 강제 Drop / rate limit / OneSync 보호 종료
    if code == 1 or (code >= 8 and code <= 11) then
        return '강제 종료', raw
    end

    -- 알 수 없는 비정상 드롭은 원문이 있으면 같이 보여준다.
    return '강제 종료', raw
end

-- 서버 내부 전용 이벤트. RegisterNetEvent가 아니므로 클라이언트가 임의로 킥/밴 표식을 만들 수 없다.
AddEventHandler('cookie_chat:server:markDrop', function(target, kind, detail)
    target = tonumber(target)
    kind = tostring(kind or ''):lower()
    if not target or (kind ~= 'kick' and kind ~= 'ban' and kind ~= 'reboot') then return end

    dropMarks[target] = {
        kind = kind,
        detail = cleanText(detail, 180),
        expires = os.time() + 15,
    }
end)

AddEventHandler('playerJoining', function()
    local src = source
    dropMarks[src] = nil
end)

-- txAdmin에서 직접 킥/밴해도 입력한 사유를 동일한 퇴장 메시지에 사용합니다.
AddEventHandler('txAdmin:events:playerKicked', function(data)
    if type(data) ~= 'table' then return end
    local target = tonumber(data.target or data.targetNetId)
    if not target then return end
    dropMarks[target] = {
        kind = 'kick',
        detail = cleanText(data.reason or data.dropMessage, 180),
        expires = os.time() + 15,
    }
end)

AddEventHandler('txAdmin:events:playerBanned', function(data)
    if type(data) ~= 'table' then return end
    local target = tonumber(data.targetNetId or data.target)
    if not target then return end
    dropMarks[target] = {
        kind = 'ban',
        detail = cleanText(data.reason or data.kickMessage, 180),
        expires = os.time() + 15,
    }
end)

AddEventHandler('playerDropped', function(reason, resourceName, clientDropReason)
    local src = source
    local mark = dropMarks[src]
    dropMarks[src] = nil

    if mark and mark.expires and mark.expires < os.time() then
        mark = nil
    end

    local gobun, nick = identitySnapshot(src)
    local category, detail = classifyDrop(reason, resourceName, clientDropReason, mark)

    local suffix = ''
    detail = cleanText(detail, 180)
    if detail ~= '' then
        -- 관리자 사유는 간결하게 괄호에 표시. DropPlayer 전체 문구는 너무 길면 자동 컷.
        suffix = (' (%s)'):format(detail)
    end

    local prefix = gobun and (('[%d] '):format(gobun)) or ''
    local message = ('%s%s님이 서버에서 나갔습니다. 사유: %s%s'):format(
        prefix, nick, category, suffix
    )

    exports.chat:addMessage(-1, {
        templateId = 'cookie_leave',
        args = { message }
    })

    print(('[cookie_chat] LEAVE src=%s name=%s reason=%s raw=%s code=%s resource=%s'):format(
        tostring(src), tostring(nick), tostring(category), cleanText(reason, 220),
        tostring(clientDropReason or 0), tostring(resourceName or '-')
    ))
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    print('[cookie_chat] V14.3.0 LEAVE REASON + REBOOT ready')
end)
