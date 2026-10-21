

local MIN_LEVEL = Config.ChatModMinLevel or 2

local function staffActionAllowed(src, admin, target)
    if CookieCanUseAdminPower then
        local ok, err = CookieCanUseAdminPower(src, admin)
        if not ok then return false, err end
    end
    if target and CookieCanTargetAdmin then
        local ok, err = CookieCanTargetAdmin(src, target)
        if not ok then return false, err end
    end
    return true
end

local function anotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_admin_chat_action` (
              `id`          INT AUTO_INCREMENT PRIMARY KEY,
              `action`      VARCHAR(20)  NOT NULL,   -- notice / warn / warn_revoke / mute / unmute
              `admin_name`  VARCHAR(60)  NULL,
              `admin_level` INT          NULL,
              `target_gobun` INT         NULL,
              `target_nick` VARCHAR(50)  NULL,
              `reason`      VARCHAR(300) NULL,
              `minutes`     INT          NULL,       -- 입막음 기간
              `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
              KEY `idx_action` (`action`),
              KEY `idx_target` (`target_gobun`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_admin_warn` (
              `id`         INT AUTO_INCREMENT PRIMARY KEY,
              `gobun`      INT          NOT NULL,
              `nickname`   VARCHAR(50)  NULL,
              `reason`     VARCHAR(300) NULL,
              `admin_name` VARCHAR(60)  NULL,
              `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
              KEY `idx_gobun` (`gobun`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})
    end)

    if ok then

    else

    end
end)

local function headOf(src)
    local ok, info = pcall(function() return exports.cookie_core:getHeadInfo(src) end)
    if ok and info then return info end
    return { gobun = nil, nick = GetPlayerName(src) or '?' }
end

local function logAction(admin, action, targetSrc, reason, minutes)
end

RegisterNetEvent('cookie_admin:server:sendNotice', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then
        return anotify(src,('공지는 LV%d 이상만 가능합니다'):format(MIN_LEVEL), true)
    end

    local allowed, allowErr = staffActionAllowed(src, admin, nil)
    if not allowed then return anotify(src, allowErr, true) end

    if type(data) == 'string' then data = { text = data } end
    if type(data) ~= 'table' then return end

    local text = type(data.text) == 'string' and data.text:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #text < 2 then
        return anotify(src,'공지 내용을 입력하세요', true)
    end
    if #text > 300 then
        return anotify(src,'공지는 300자 이내여야 합니다', true)
    end

    local seconds = math.floor(tonumber(data.seconds) or 0)
    if seconds < 0 then seconds = 0 end
    if seconds > 300 then seconds = 300 end

    TriggerClientEvent('cookie_hud:client:notice', -1, {
        text = text,
        seconds = seconds,
        hold = 6,
    })

    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'cookie_notice',
        args = { text }
    })

end)

RegisterNetEvent('cookie_admin:server:chatWarn', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then
        return anotify(src,('경고는 LV%d 이상만 가능합니다'):format(MIN_LEVEL), true)
    end
    if type(data) ~= 'table' then return end

    local target = tonumber(data.targetServerId)
    local reason = type(data.reason) == 'string' and data.reason:gsub('^%s+', ''):gsub('%s+$', '') or ''
    local revoke = data.revoke == true

    if not target or GetPlayerName(target) == nil then
        return anotify(src,'대상이 접속 중이 아닙니다', true)
    end
    local allowed, allowErr = staffActionAllowed(src, admin, target)
    if not allowed then return anotify(src, allowErr, true) end
    if #reason < 2 then
        return anotify(src,'사유를 입력하세요', true)
    end

    local t = headOf(target)

    if revoke then

        local row = MySQL.single.await(
            'SELECT id FROM cookie_admin_warn WHERE gobun = ? ORDER BY id DESC LIMIT 1', { t.gobun })
        if not row then
            return anotify(src,'회수할 경고가 없습니다', true)
        end
        MySQL.query.await('DELETE FROM cookie_admin_warn WHERE id = ?', { row.id })

        TriggerClientEvent('chat:addMessage', target, {
            templateId = 'cookie_system',
            args = { ('경고 1건이 회수되었습니다. 사유: %s'):format(reason) }
        })

        anotify(src,('%s (%s) 경고를 회수했습니다'):format(t.nick, tostring(t.gobun)), false)
        return
    end

    MySQL.insert.await([[
        INSERT INTO cookie_admin_warn (gobun, nickname, reason, admin_name)
        VALUES (?, ?, ?, ?)
    ]], { t.gobun, t.nick, reason, admin.admin_name })

    local cnt = MySQL.single.await('SELECT COUNT(*) AS n FROM cookie_admin_warn WHERE gobun = ?', { t.gobun })
    local n = (cnt and tonumber(cnt.n)) or 1

    TriggerClientEvent('chat:addMessage', target, {
        templateId = 'cookie_warn',
        args = { ('%s  (누적 %d회)'):format(reason, n) }
    })

    anotify(src,('%s (%s) 에게 경고를 발급했습니다 (누적 %d회)'):format(t.nick, tostring(t.gobun), n), false)

end)

RegisterNetEvent('cookie_admin:server:chatMute', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then
        return anotify(src,('입막음은 LV%d 이상만 가능합니다'):format(MIN_LEVEL), true)
    end
    if type(data) ~= 'table' then return end

    local target = tonumber(data.targetServerId)
    local reason = type(data.reason) == 'string' and data.reason:gsub('^%s+', ''):gsub('%s+$', '') or ''
    local unmute = data.unmute == true
    local minutes = math.floor(tonumber(data.minutes) or 10)

    if not target or GetPlayerName(target) == nil then
        return anotify(src,'대상이 접속 중이 아닙니다', true)
    end
    local allowed, allowErr = staffActionAllowed(src, admin, target)
    if not allowed then return anotify(src, allowErr, true) end
    if #reason < 2 then
        return anotify(src,'사유를 입력하세요', true)
    end
    if minutes < 1 then minutes = 1 end
    if minutes > 1440 then minutes = 1440 end

    local t = headOf(target)

    TriggerEvent('cookie_chat:server:mute', {
        target = target,
        unmute = unmute,
        minutes = minutes,
        reason = reason,
        byName = admin.admin_name,
    })

    if unmute then

        anotify(src,('%s (%s) 입막음을 해제했습니다'):format(t.nick, tostring(t.gobun)), false)
    else

        anotify(src,('%s (%s) 를 %d분간 입막음했습니다'):format(t.nick, tostring(t.gobun), minutes), false)
    end

end)
