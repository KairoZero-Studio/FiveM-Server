print('^2[COOKIE CHAT]^7 V2.6 AD 180s + leave/reboot integration loaded')


local function nickFallback(src)
    local player = exports.qbx_core:GetPlayer(src)
    if player and player.PlayerData and player.PlayerData.charinfo then
        local ci = player.PlayerData.charinfo
        return ('%s %s'):format(ci.firstname or '', ci.lastname or '')
    end
    return GetPlayerName(src) or ''
end

local function getEquippedChatTitle(src)
    -- Primary: COOKIE TITLE SYSTEM V3 (F3 title manager).
    if GetResourceState('cookie_admin') == 'started' then
        local ok, title = pcall(function()
            return exports.cookie_admin:getChatTextTitle(src)
        end)
        if ok and type(title) == 'table' then
            local text = tostring(title.text or title.name or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            if text ~= '' then
                return {
                    text = text:sub(1, 60),
                    color = tostring(title.color or '#FFE08A'),
                    bg = tostring(title.bg or '#251B0B'),
                }
            end
        end
    end

    -- Compatibility fallback: older cookie_identityfx chat titles.
    if GetResourceState('cookie_identityfx') == 'started' then
        local ok, title = pcall(function()
            return exports.cookie_identityfx:GetChatTitle(src)
        end)
        if ok and type(title) == 'table' then
            local text = tostring(title.text or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            if text ~= '' then
                return {
                    text = text:sub(1, 60),
                    color = tostring(title.color or '#FFE08A'),
                    bg = tostring(title.bg or '#251B0B'),
                }
            end
        end
    end

    return nil
end

local function getChatFaction(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end

    local ok, faction = pcall(function()
        return exports.cookie_admin:getFactionOf(src)
    end)

    if not ok or type(faction) ~= 'table' or not faction.id then return nil end
    return faction
end

local function buildHead(src)
    local ok, info = pcall(function() return exports.cookie_core:getHeadInfo(src) end)
    if not ok or not info then
        local nick = nickFallback(src)
        return {
            gobun = '-', label = '', nick = nick, isAdmin = false, isFaction = false,
            labelColor = nil, title = getEquippedChatTitle(src)
        }
    end

    local isAdmin = (info.job == '관리자')
    local label = ''
    local labelColor = nil
    local isFaction = false

    -- 시민직(정비/택시/낚시/광산 등)은 일반 채팅에 직업 뱃지를 표시하지 않습니다.
    -- 관리자 뱃지는 기존 동작을 유지하고, 팩션 소속자는 F3 팩션 관리의 색상을 그대로 사용합니다.
    if isAdmin then
        label = info.job or '관리자'
        labelColor = '#FF4D4F'
    elseif Config.showFactionTag ~= false then
        local faction = getChatFaction(src)
        if faction then
            local tag = tostring(faction.tagName or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            if tag == '' then
                tag = tostring(faction.name or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
            end
            if tag ~= '' then
                label = tag:sub(1, 30)
                labelColor = tostring(faction.color or '#FFB800')
                isFaction = true
            end
        end
    end

    return {
        gobun      = info.gobun or '-',
        label      = label,
        nick       = info.nick or '',
        isAdmin    = isAdmin,
        isFaction  = isFaction,
        labelColor = labelColor,
        title      = getEquippedChatTitle(src),
    }
end

local function getNearbyTarget(src)
    local srcCoords = GetEntityCoords(GetPlayerPed(src))
    local target = {}
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local pCoords = GetEntityCoords(GetPlayerPed(pid))
        if #(srcCoords - pCoords) <= Config.proximityDist then
            target[#target + 1] = pid
        end
    end
    return target
end

local function normalizeRgb(value)
    local c = tostring(value or ''):upper():gsub('%s+', '')
    if c:match('^#%x%x%x%x%x%x$') then return c end
    return nil
end

local function contrastText(hex)
    hex = normalizeRgb(hex) or '#FFB800'
    local r = tonumber(hex:sub(2,3), 16) or 255
    local g = tonumber(hex:sub(4,5), 16) or 184
    local b = tonumber(hex:sub(6,7), 16) or 0
    local y = (r * 299 + g * 587 + b * 114) / 1000
    return y >= 150 and '#171717' or '#FFFFFF'
end

local function getFactionMember(src)
    if GetResourceState('cookie_admin') ~= 'started' then return nil end
    local ok, m = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    if ok and type(m) == 'table' and m.id then return m end
    return nil
end

local function factionChannelAllowed(src)
    local m = getFactionMember(src)
    if not m then return false end

    local factionType = tostring(m.type or ''):lower()
    if Config.factionChatAllowedTypes and Config.factionChatAllowedTypes[factionType] then
        return true
    end

    local haystack = table.concat({
        tostring(m.key or ''),
        tostring(m.name or ''),
        tostring(m.jobName or ''),
    }, ' '):lower()

    for _, keyword in ipairs(Config.factionChatKeywords or {}) do
        keyword = tostring(keyword or ''):lower()
        if keyword ~= '' and haystack:find(keyword, 1, true) then
            return true
        end
    end

    return false
end

local function adminChannelAllowed(src)
    if GetResourceState('cookie_admin') ~= 'started' then return false end
    local ok, lv = pcall(function()
        return tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0
    end)
    return ok and (tonumber(lv) or 0) >= 1
end

local CHAT_MODE_NAMES = {
    'proximity',
    'ad',
    'rp',
    'admin',
    'faction',
    'whisper',
}

local function refreshChatModes(src)
    if GetResourceState('chat') ~= 'started' then return end

    for _, modeName in ipairs(CHAT_MODE_NAMES) do
        pcall(function()
            exports.chat:refreshModeForPlayer(src, modeName)
        end)
    end
end

local function registerChannels()

exports.chat:registerMode({
    name = 'proximity',
    displayName = '근접',
    color = '#ffffff',
    cb = function(source, message, hookRef)
        local target = getNearbyTarget(source)

        hookRef.setRouting(target)
    end
})

local function getFactionId(src)
    local m = getFactionMember(src)
    if not m or not factionChannelAllowed(src) then return nil end
    return m.id, m.name
end

exports.chat:registerMode({
    name = 'faction',
    displayName = '팩션',
    color = Config.channelColor.faction,
    isChannel = true,
    canUse = factionChannelAllowed,
    cb = function(source, message, hookRef)
        local fid = getFactionId(source)
        if not fid then
            TriggerClientEvent('chat:addMessage', source, {
                templateId = 'cookie_system',
                args = { '소속이 없어 팩션 채팅을 쓸 수 없습니다.' }
            })
            hookRef.cancel()
            return
        end

        local target = {}
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            if getFactionId(pid) == fid then target[#target + 1] = pid end
        end

        hookRef.setRouting(target)
    end
})

-- 귓속말은 고유번호 기반으로 서버에서 수신자를 검증합니다.
-- 채팅 채널에서: 고번 내용  (예: 15 안녕하세요)
exports.chat:registerMode({
    name = 'whisper',
    displayName = '귓속말',
    color = Config.channelColor.whisper or '#79c6ff',
    isChannel = true,
    cb = function(source, message, hookRef)
        -- 공통 뮤트/금칙어/도배 검사에서 차단한 내용은 귓속말로도 보낼 수 없습니다.
        if message.cookieBlocked then hookRef.cancel(); return end
        -- 먼저 실패를 기본값으로: 잘못된 입력은 누구에게도 전파하지 않습니다.
        hookRef.cancel()
        local raw = tostring(message.args and message.args[#message.args] or '')
        local gobunText, body = raw:match('^%s*(%d+)%s+(.+)%s*$')
        local gobun = gobunText and tonumber(gobunText)
        if not gobun or not body or body:match('^%s*$') then
            TriggerClientEvent('chat:addMessage', source, {
                templateId = 'cookie_system',
                args = { '귓속말 사용법: 귓속말 채널에서 [고번] [내용] (예: 15 안녕하세요)' }
            })
            return
        end
        body = body:gsub('^%s+', ''):gsub('%s+$', '')
        if #body > 500 then
            TriggerClientEvent('chat:addMessage', source, {
                templateId = 'cookie_system', args = { '귓속말은 최대 500바이트까지 보낼 수 있습니다.' }
            })
            return
        end
        local target = CookieChatFindByGobun(gobun)
        if not target or not GetPlayerName(target) then
            TriggerClientEvent('chat:addMessage', source, {
                templateId = 'cookie_system', args = { ('%d번은 현재 접속 중이 아닙니다.'):format(gobun) }
            })
            return
        end
        if tonumber(target) == tonumber(source) then
            TriggerClientEvent('chat:addMessage', source, {
                templateId = 'cookie_system', args = { '자기 자신에게 귓속말을 보낼 수 없습니다.' }
            })
            return
        end
        -- 원본 채널 메시지는 취소한 상태를 유지합니다. 아래의 두 대상에게만 전달.
        local sender = buildHead(source)
        local receiver = buildHead(target)
        local cleanBody = body:gsub('[%c]', ' ')
        local senderName = tostring(sender.nick or GetPlayerName(source) or '?')
        local receiverName = tostring(receiver.nick or GetPlayerName(target) or '?')
        local fromGobun = tostring(sender.gobun or source)
        local toGobun = tostring(receiver.gobun or gobun)
        local function sendPrivate(pid, direction, otherGobun, otherName)
            TriggerClientEvent('chat:addMessage', pid, {
                templateId = 'cookie_whisper',
                args = { direction, otherGobun, otherName, cleanBody }
            })
        end
        sendPrivate(source, '보냄 →', toGobun, receiverName)
        sendPrivate(target, '받음 ←', fromGobun, senderName)
    end
})

local adLast = {}

local function adCooldownKey(src)
    -- 재접속으로 광고 쿨타임을 우회하지 못하도록 license를 우선 사용합니다.
    return GetPlayerIdentifierByType(src, 'license2')
        or GetPlayerIdentifierByType(src, 'license')
        or ('src:' .. tostring(src))
end

exports.chat:registerMode({
    name = 'ad',
    displayName = '광고',
    color = Config.channelColor.ad,
    isChannel = true,
    cb = function(source, message, hookRef)
        local now = os.time()
        local cd = math.max(1, tonumber(Config.adCooldown) or 180)
        local key = adCooldownKey(source)
        local last = adLast[key] or 0
        local left = cd - (now - last)

        if left > 0 then
            TriggerClientEvent('chat:addMessage', source, {
                templateId = 'cookie_system',
                args = { ('광고 채팅은 %d초 후에 다시 쓸 수 있습니다.'):format(left) }
            })
            hookRef.cancel()
            return
        end

        adLast[key] = now
    end
})

exports.chat:registerMode({
    name = 'rp',
    displayName = 'RP',
    color = Config.channelColor.rp,
    isChannel = true,
    cb = function(source, message, hookRef)
        local dist = Config.rpDist or 0
        if dist <= 0 then return end

        local srcCoords = GetEntityCoords(GetPlayerPed(source))
        local target = {}
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            if #(srcCoords - GetEntityCoords(GetPlayerPed(pid))) <= dist then
                target[#target + 1] = pid
            end
        end

        hookRef.setRouting(target)
    end
})

exports.chat:registerMode({
    -- 내부 mode 이름은 기존 호환성을 위해 admin 유지, 화면 표시는 '시스템'.
    name = 'admin',
    displayName = '시스템',
    color = Config.channelColor.admin,
    isChannel = true,
    canUse = adminChannelAllowed,
    cb = function(source, message, hookRef)
        if not adminChannelAllowed(source) then
            hookRef.cancel()
            return
        end

        local target = {}
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            if adminChannelAllowed(pid) then
                target[#target + 1] = pid
            end
        end

        hookRef.setRouting(target)
    end
})

local function wrapClassFor(mode)
    if mode == 'admin' then return 'ck-wrap--admin' end
    if mode == 'proximity' then return 'ck-wrap--prox' end
    if mode == 'faction' then return 'ck-wrap--faction' end
    if mode == 'ad' then return 'ck-wrap--ad' end
    if mode == 'rp' then return 'ck-wrap--rp' end
    if mode == 'whisper' then return 'ck-wrap--whisper' end
    return ''
end

exports.chat:registerMessageHook(function(source, message, hookRef)
    if not source or source <= 0 then return end
    if message.templateId and message.templateId ~= '' then return end

    local head = buildHead(source)
    local text = (message.args and message.args[#message.args]) or message.message or ''
    local channel = message.mode or 'all'

    local left = CookieChatMuted(source)
    if left > 0 then
        TriggerClientEvent('chat:addMessage', source, {
            templateId = 'cookie_system',
            args = { ('채팅이 제한된 상태입니다. %d초 남았습니다.'):format(left) }
        })

        hookRef.updateMessage({ cookieBlocked = true })
        hookRef.cancel()
        return
    end

    local bad = CookieChatFilter(source, text)
    if bad then
        TriggerClientEvent('chat:addMessage', source, {
            templateId = 'cookie_system',
            args = { ('%s가 포함되어 메시지를 보내지 않았습니다.'):format(bad) }
        })

        hookRef.updateMessage({ cookieBlocked = true })
        hookRef.cancel()
        return
    end

    local spam = CookieChatSpam(source, text)
    if spam then
        hookRef.updateMessage({ cookieBlocked = true })
        hookRef.cancel()
        return
    end

    local wrapClass = wrapClassFor(message.mode) or ''
    local gobun     = tostring(head.gobun or '?')
    local label     = head.label or ''
    local nick      = head.nick or 'Unknown'
    local body      = text or ''

    local labelClass = (head.isAdmin and 'ck-chip--admin')
        or (head.isFaction and 'ck-chip--faction')
        or (label == '' and 'ck-chip--hide')
        or ''

    local labelBg = normalizeRgb(head.labelColor) or (head.isAdmin and '#FF4D4F') or '#FFB800'
    local labelText = contrastText(labelBg)

    local titleText, titleColor, titleBg = '', '#FFE08A', '#251B0B'
    if head.title then
        titleText = tostring(head.title.text or '')
        titleColor = normalizeRgb(head.title.color) or '#FFE08A'
        titleBg = normalizeRgb(head.title.bg) or '#251B0B'
    end

    hookRef.updateMessage({
        templateId = 'cookie_msg',
        color = false,
        args = {
            wrapClass, gobun, labelClass, label, nick, body,
            titleText, titleColor, titleBg, tostring(source), labelBg, labelText
        }
    })
end)

end

registerChannels()

CreateThread(function()
    Wait(1500)
    if GetResourceState('chat') ~= 'started' then return end
    for _, pid in ipairs(GetPlayers()) do
        refreshChatModes(tonumber(pid))
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= 'chat' then return end
    Wait(200)
    local ok, err = pcall(registerChannels)
    if ok then

    else

    end
end)

-- 관리자 권한/팩션 가입·탈퇴가 접속 중 바뀌어도 TAB 목록이 자동 갱신됩니다.
CreateThread(function()
    while true do
        Wait(5000)
        if GetResourceState('chat') == 'started' then
            for _, pid in ipairs(GetPlayers()) do
                refreshChatModes(tonumber(pid))
            end
        end
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(2500, function()
        if GetPlayerName(src) then refreshChatModes(src) end
    end)
end)

print('^2[COOKIE CHAT]^7 FACTION TAG COLOR V14.2.2 ready')

