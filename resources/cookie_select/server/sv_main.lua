

local function ckLog(tag, msg)
    if GetConvar('cookie:introDebug', 'true') ~= 'true' then return end

end

local function getLicense(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

lib.callback.register('cookie_select:isOnboarded', function(src)
    return exports.cookie_core:isOnboarded(src)
end)

local lastCheck = {}

lib.callback.register('cookie_select:checkNickname', function(src, nickname)
    nickname = nickname or ''
    local now = GetGameTimer()
    local prev = lastCheck[src]
    if prev and (now - prev.at) < 500 then

        if prev.nickname == nickname then
            return prev.result
        end
        return { ok = false, reason = '', pending = true }
    end

    local result = exports.cookie_core:checkNickname(nickname)
    lastCheck[src] = { at = now, nickname = nickname, result = result }

    return result
end)

lib.callback.register('cookie_select:issueJumin', function(src, age, gender)
    local result = exports.cookie_core:issueJumin(src, age, gender)

    return result
end)

lib.callback.register('cookie_select:genderConflict', function(src, gender)
    return exports.cookie_core:genderConflict(src, gender)
end)

lib.callback.register('cookie_select:getIdentity', function(src)
    return exports.cookie_core:getIdentity(src)
end)

lib.callback.register('cookie_select:issuePhone', function(src)
    local result = exports.cookie_core:issuePhone(src)

    return result
end)

lib.callback.register('cookie_select:complete', function(src, nickname)
    local result = exports.cookie_core:completeOnboarding(src, nickname or '')

    return result
end)

lib.callback.register('cookie_select:needsVerify', function(src)
    return exports.cookie_core:needsVerify(src)
end)

lib.callback.register('cookie_select:verifyInfo', function()
    return exports.cookie_core:getVerifyInfo()
end)

lib.callback.register('cookie_select:verifyRedeem', function(src, code)
    local r = exports.cookie_core:redeemCode(src, code or '')

    return r
end)

local VALID_STAGE = {
    welcome = true, consent = true, nick = true, verify = true, create = true,
    entry = true, editPrompt = true, customize = true, spawn = true,
}

RegisterNetEvent('cookie_select:stage', function(stage)
    local src = source
    if type(stage) ~= 'string' or not VALID_STAGE[stage] then

        return
    end
    Player(src).state:set('onboardingStage', stage, true)

end)

RegisterCommand('obstage', function(src, args)
    if GetConvar('cookie:introDebug', 'false') ~= 'true' then return end
    local target = tonumber(args[1])
    if not target then

        return
    end
    local v = Player(target).state.onboardingStage

end, true)

lib.callback.register('cookie_select:getMyNickname', function(src)
    local license = getLicense(src)
    if not license then return nil end
    local row = MySQL.single.await('SELECT nickname FROM cookie_user WHERE license = ?', { license })
    return row and row.nickname or nil
end)

local BANNED_NAME = { '운영자', '관리자', 'admin', 'gm', '시스템', '쿠키서버' }

local function validName(s)
    if type(s) ~= 'string' then return false end
    local len = utf8.len(s)
    if not len or len < 1 or len > 10 then return false end
    local lower = s:lower()
    for i = 1, #BANNED_NAME do
        if lower:find(BANNED_NAME[i], 1, true) then return false end
    end
    return true
end

lib.callback.register('cookie_select:validateCharacter', function(src, data)
    if type(data) ~= 'table' then
        return { ok = false, reason = '입력이 올바르지 않습니다' }
    end
    if not validName(data.lastname) then
        return { ok = false, reason = '성은 1~10자여야 하며 금지어를 포함할 수 없습니다' }
    end
    if not validName(data.firstname) then
        return { ok = false, reason = '이름은 1~10자여야 하며 금지어를 포함할 수 없습니다' }
    end
    if type(data.birthdate) ~= 'string' or not data.birthdate:match('^%d%d%d%d%-%d%d%-%d%d$') then
        return { ok = false, reason = '생년월일 형식(YYYY-MM-DD)이 올바르지 않습니다' }
    end
    if data.gender ~= '남' and data.gender ~= '여' then
        return { ok = false, reason = '성별을 선택해주세요' }
    end

    return { ok = true }
end)

AddEventHandler('playerDropped', function()
    lastCheck[source] = nil
end)

local function notify(src, color, msg)
    TriggerClientEvent('chat:addMessage', src, { args = { color .. '[cookie_select]', msg } })
end

RegisterCommand('introreset', function(src, args)

    if GetConvar('cookie:introDebug', 'false') ~= 'true' then
        if src == 0 then

        else
            notify(src, '^1', '개발 모드가 아닙니다')
        end
        return
    end

    if src == 0 then

        return
    end
    local license = getLicense(src)
    if not license then
        notify(src, '^1', 'license 확보 실패 - 리셋 중단')
        return
    end

    exports.cookie_core:resetOnboarding(license)

    if args[1] == 'full' then

        notify(src, '^5', '온보딩+캐릭터 리셋 진행 중... 곧 접속이 종료됩니다. 재접속해주세요')
        Wait(150)

        local license2 = GetPlayerIdentifierByType(src, 'license2')
        local rows = MySQL.query.await('SELECT citizenid FROM players WHERE license = ? OR license = ?', { license, license2 })
        local n = rows and #rows or 0
        for i = 1, n do

            exports.qbx_core:DeleteCharacter(rows[i].citizenid)
        end

    else
        notify(src, '^5', '온보딩 리셋 완료. 재접속하면 처음부터 진행됩니다')
    end
end, false)

