-- COOKIE TITLE SYSTEM V3 - TEXT ONLY
-- 채팅칭호: 글자만 / 1개 장착
-- 머리 위 칭호: 글자만 / 1개 장착
-- 이미지 채팅칭호/이모지 채팅칭호는 더 이상 사용하지 않음.

local titleReady = false
local titleInitBusy = false
local titleCache = {}

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function adminAuth(src)
    local license = licenseOf(src)
    if not license then return nil end

    local row = MySQL.single.await([[
        SELECT admin_name, admin_level, (pw_hash IS NOT NULL) AS has_pw
        FROM cookie_admin
        WHERE license = ? AND is_active = 1
        LIMIT 1
    ]], { license })

    if not row then return nil end

    local level = tonumber(row.admin_level) or 0
    local hasPw = row.has_pw == 1 or row.has_pw == true
    if level >= 5 and not hasPw then level = 4 end
    if level < 5 then return nil end

    return row
end

local function clean(v)
    return tostring(v or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
end

local function validColor(v, fallback)
    v = clean(v)
    if v:match('^#%x%x%x%x%x%x$') then return v end
    return fallback
end

local function ensureTables()
    if titleReady then return true end
    if titleInitBusy then
        while titleInitBusy do Wait(50) end
        return titleReady
    end

    titleInitBusy = true

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_title_catalog (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                kind VARCHAR(12) NOT NULL,
                chat_subtype VARCHAR(12) NOT NULL DEFAULT 'text',
                scope_type VARCHAR(12) NOT NULL,
                name VARCHAR(60) NOT NULL,
                chat_image MEDIUMTEXT NULL,
                head_text VARCHAR(60) NULL,
                head_color VARCHAR(16) NOT NULL DEFAULT '#FFE08A',
                head_bg VARCHAR(16) NOT NULL DEFAULT '#251B0B',
                target_gobun INT NULL,
                issue_limit INT UNSIGNED NOT NULL DEFAULT 0,
                is_active TINYINT(1) NOT NULL DEFAULT 1,
                created_by VARCHAR(60) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_cookie_title_kind (kind),
                INDEX idx_cookie_title_scope (scope_type),
                INDEX idx_cookie_title_target (target_gobun)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_title_ownership (
                title_id BIGINT UNSIGNED NOT NULL,
                gobun INT NOT NULL,
                granted_by VARCHAR(60) NULL,
                granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (title_id, gobun),
                INDEX idx_cookie_title_owner_gobun (gobun)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_title_equipped (
                gobun INT NOT NULL PRIMARY KEY,
                chat_title_id BIGINT UNSIGNED NULL,
                chat_text_title_id BIGINT UNSIGNED NULL,
                chat_emoji_title_id BIGINT UNSIGNED NULL,
                head_title_id BIGINT UNSIGNED NULL,
                head_order VARCHAR(20) NOT NULL DEFAULT 'title_first',
                lover_visible TINYINT(1) NOT NULL DEFAULT 1,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_cookie_title_eq_chat (chat_title_id),
                INDEX idx_cookie_title_eq_head (head_title_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        -- V1/V2 DB 호환 컬럼 보장
        pcall(function()
            MySQL.query.await([[ALTER TABLE cookie_title_catalog ADD COLUMN IF NOT EXISTS chat_subtype VARCHAR(12) NOT NULL DEFAULT 'text']])
        end)
        pcall(function()
            MySQL.query.await([[ALTER TABLE cookie_title_equipped ADD COLUMN IF NOT EXISTS chat_text_title_id BIGINT UNSIGNED NULL]])
        end)
        pcall(function()
            MySQL.query.await([[ALTER TABLE cookie_title_equipped ADD COLUMN IF NOT EXISTS chat_emoji_title_id BIGINT UNSIGNED NULL]])
        end)
        pcall(function()
            MySQL.query.await([[ALTER TABLE cookie_title_equipped ADD COLUMN IF NOT EXISTS head_order VARCHAR(20) NOT NULL DEFAULT 'title_first']])
        end)
        pcall(function()
            MySQL.query.await([[ALTER TABLE cookie_title_equipped ADD COLUMN IF NOT EXISTS lover_visible TINYINT(1) NOT NULL DEFAULT 1]])
        end)

        -- 예전 이미지 채팅칭호도 데이터 삭제 없이 '글자 칭호'로 전환.
        -- 표시문구가 없으면 칭호 이름을 사용한다.
        MySQL.update.await([[
            UPDATE cookie_title_catalog
            SET chat_subtype = 'text',
                head_text = CASE
                    WHEN head_text IS NULL OR head_text = '' THEN name
                    ELSE head_text
                END
            WHERE kind = 'chat'
        ]])

        -- V2 글자 슬롯을 기존 단일 채팅칭호 슬롯으로 복원.
        MySQL.update.await([[
            UPDATE cookie_title_equipped
            SET chat_title_id = chat_text_title_id
            WHERE chat_title_id IS NULL
              AND chat_text_title_id IS NOT NULL
        ]])
    end)

    titleInitBusy = false
    titleReady = ok

    if not ok then
        print(('[cookie_admin] TITLE SYSTEM V3 DB INIT ERROR: %s'):format(tostring(err)))
    end

    return ok
end

local function rowToPublic(r)
    if not r then return nil end

    local text = clean(r.head_text)
    if text == '' then text = clean(r.name) end

    return {
        id = tonumber(r.id),
        kind = clean(r.kind):lower(),
        scope = r.scope_type,
        name = r.name,
        text = text,
        color = r.head_color,
        bg = r.head_bg,
        targetGobun = r.target_gobun and tonumber(r.target_gobun) or nil,
        issueLimit = tonumber(r.issue_limit) or 0,
        issuedCount = tonumber(r.issued_count) or 0,
        active = r.is_active == 1 or r.is_active == true,
    }
end

local function refreshCache()
    if not ensureTables() then return end

    local rows = MySQL.query.await([[
        SELECT id, kind, scope_type, name, head_text,
               head_color, head_bg, target_gobun, issue_limit, is_active
        FROM cookie_title_catalog
        WHERE is_active = 1
    ]]) or {}

    titleCache = {}
    for _, r in ipairs(rows) do
        titleCache[tonumber(r.id)] = rowToPublic(r)
    end
end

local function gobunOfSource(src)
    local license = licenseOf(src)
    if not license then return nil end

    local row = MySQL.single.await(
        'SELECT gobun FROM cookie_user WHERE license = ? LIMIT 1',
        { license }
    )

    return row and tonumber(row.gobun) or nil
end

local function gobunExists(gobun)
    local row = MySQL.single.await(
        'SELECT nickname FROM cookie_user WHERE gobun = ? LIMIT 1',
        { gobun }
    )
    return row ~= nil, row and row.nickname or nil
end

local function ownsTitle(gobun, title)
    if not title or not title.active then return false end

    if title.scope == 'custom' then
        return tonumber(title.targetGobun) == tonumber(gobun)
    end

    if title.scope == 'event' then
        if (tonumber(title.issueLimit) or 0) <= 0 then
            return true
        end

        local row = MySQL.single.await(
            'SELECT 1 AS x FROM cookie_title_ownership WHERE title_id = ? AND gobun = ? LIMIT 1',
            { title.id, gobun }
        )
        return row ~= nil
    end

    return false
end

local function equippedRaw(gobun)
    local row = MySQL.single.await([[
        SELECT chat_title_id, chat_text_title_id, head_title_id, head_order, lover_visible
        FROM cookie_title_equipped
        WHERE gobun = ?
        LIMIT 1
    ]], { gobun })

    local chatId = nil
    if row then chatId = tonumber(row.chat_title_id or row.chat_text_title_id) end

    return {
        chat = chatId,
        head = row and tonumber(row.head_title_id) or nil,
        headOrder = row and clean(row.head_order) or 'title_first',
        loverVisible = row == nil or row.lover_visible == 1 or row.lover_visible == true,
    }
end

local function sanitizeEquipped(gobun)
    local e = equippedRaw(gobun)
    if e.headOrder ~= 'lover_first' then e.headOrder = 'title_first' end
    e.loverVisible = e.loverVisible ~= false

    local changed = false

    if e.chat then
        local t = titleCache[e.chat]
        if not t or t.kind ~= 'chat' or not ownsTitle(gobun, t) then
            e.chat = nil
            changed = true
        end
    end

    if e.head then
        local t = titleCache[e.head]
        if not t or t.kind ~= 'head' or not ownsTitle(gobun, t) then
            e.head = nil
            changed = true
        end
    end

    if changed then
        MySQL.query.await([[
            INSERT INTO cookie_title_equipped
                (gobun, chat_title_id, chat_text_title_id, head_title_id, head_order, lover_visible)
            VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                chat_title_id = VALUES(chat_title_id),
                chat_text_title_id = VALUES(chat_text_title_id),
                head_title_id = VALUES(head_title_id),
                head_order = VALUES(head_order),
                lover_visible = VALUES(lover_visible)
        ]], {
            gobun, e.chat, e.chat, e.head, e.headOrder, e.loverVisible and 1 or 0
        })
    end

    return e
end

-- 채팅 리소스가 읽는 단순 글자 칭호.
exports('getChatTextTitle', function(src)
    src = tonumber(src)
    if not src or not ensureTables() then return nil end
    if not next(titleCache) then refreshCache() end

    local gobun = gobunOfSource(src)
    if not gobun then return nil end

    local e = sanitizeEquipped(gobun)
    local t = e.chat and titleCache[e.chat] or nil
    if not t or t.kind ~= 'chat' then return nil end

    return {
        id = t.id,
        name = t.name,
        text = t.text ~= '' and t.text or t.name,
        color = validColor(t.color, '#FFE08A'),
        bg = validColor(t.bg, '#251B0B'),
    }
end)

function CookieGetHeadTitleForSource(src)
    src = tonumber(src)
    if not src or not ensureTables() then return nil end
    if not next(titleCache) then refreshCache() end

    local gobun = gobunOfSource(src)
    if not gobun then return nil end

    local e = sanitizeEquipped(gobun)
    local t = e.head and titleCache[e.head] or nil
    if not t or t.kind ~= 'head' then return nil end

    return {
        id = t.id,
        name = t.name,
        text = t.text,
        color = t.color,
        bg = t.bg,
    }
end

function CookieGetHeadDisplaySettingsForSource(src)
    src = tonumber(src)
    if not src or not ensureTables() then
        return { headOrder = 'title_first', loverVisible = true }
    end

    local gobun = gobunOfSource(src)
    if not gobun then
        return { headOrder = 'title_first', loverVisible = true }
    end

    local e = sanitizeEquipped(gobun)
    return {
        headOrder = e.headOrder,
        loverVisible = e.loverVisible,
    }
end

exports('getHeadTitle', function(src)
    return CookieGetHeadTitleForSource(tonumber(src))
end)

function CookieRefreshTitleState(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then return end
    if not ensureTables() then return end
    if not next(titleCache) then refreshCache() end

    local gobun = gobunOfSource(src)
    if not gobun then return end

    local e = sanitizeEquipped(gobun)
    local chat = e.chat and titleCache[e.chat] or nil
    local head = e.head and titleCache[e.head] or nil

    Player(src).state:set('cookieChatTextTitle',
        chat and { id = chat.id, text = chat.text } or false, true)

    Player(src).state:set('cookieHeadTitle',
        head and {
            id = head.id,
            name = head.name,
            text = head.text,
            color = head.color,
            bg = head.bg,
        } or false, true)

    Player(src).state:set('cookieTitleDisplay', {
        headOrder = e.headOrder,
        loverVisible = e.loverVisible,
    }, true)

    if CookieRefreshNameTag then
        pcall(CookieRefreshNameTag, src)
    else
        TriggerEvent('cookie_admin:server:nameTagDirty', src)
    end
end

local function refreshAllOnline()
    refreshCache()
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src then pcall(CookieRefreshTitleState, src) end
    end
end

local function userTitles(gobun)
    local rows = MySQL.query.await([[
        SELECT
            t.id, t.kind, t.scope_type, t.name, t.head_text,
            t.head_color, t.head_bg, t.target_gobun, t.issue_limit, t.is_active,
            (SELECT COUNT(*) FROM cookie_title_ownership o WHERE o.title_id = t.id) AS issued_count
        FROM cookie_title_catalog t
        WHERE t.is_active = 1
          AND (
                (t.scope_type = 'custom' AND t.target_gobun = ?)
             OR (t.scope_type = 'event' AND t.issue_limit = 0)
             OR EXISTS (
                    SELECT 1 FROM cookie_title_ownership o
                    WHERE o.title_id = t.id AND o.gobun = ?
                )
          )
        ORDER BY t.kind, t.id DESC
    ]], { gobun, gobun }) or {}

    local out = { chat = {}, head = {} }

    for _, r in ipairs(rows) do
        local t = rowToPublic(r)
        if t.kind == 'chat' then
            out.chat[#out.chat + 1] = t
        elseif t.kind == 'head' then
            out.head[#out.head + 1] = t
        end
    end

    return out
end

local function sendUserData(src, message, isError)
    if not ensureTables() then return end
    if not next(titleCache) then refreshCache() end

    local gobun = gobunOfSource(src)
    if not gobun then
        return TriggerClientEvent('cookie_admin:client:titleUserData', src, {
            gobun = nil,
            equipped = { chat = nil, head = nil },
            display = { headOrder = 'title_first', loverVisible = true },
            chat = {}, head = {},
        }, '고번 정보를 찾을 수 없습니다.', true)
    end

    local lists = userTitles(gobun)
    local e = sanitizeEquipped(gobun)

    TriggerClientEvent('cookie_admin:client:titleUserData', src, {
        gobun = gobun,
        equipped = { chat = e.chat, head = e.head },
        display = { headOrder = e.headOrder, loverVisible = e.loverVisible },
        chat = lists.chat,
        head = lists.head,
    }, message, isError == true)
end

local function adminRows()
    local rows = MySQL.query.await([[
        SELECT
            t.id, t.kind, t.scope_type, t.name, t.head_text,
            t.head_color, t.head_bg, t.target_gobun, t.issue_limit, t.is_active,
            (SELECT COUNT(*) FROM cookie_title_ownership o WHERE o.title_id = t.id) AS issued_count
        FROM cookie_title_catalog t
        ORDER BY t.kind, t.id DESC
    ]]) or {}

    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = rowToPublic(r) end
    return out
end

local function sendAdminData(src, message, isError)
    if not ensureTables() then return end
    TriggerClientEvent('cookie_admin:client:titleAdminData', src, { rows = adminRows() }, message, isError == true)
end

exports('refreshTitleState', function(src)
    src = tonumber(src)
    if not src then return false end
    local ok = pcall(CookieRefreshTitleState, src)
    return ok
end)

RegisterNetEvent('cookie_admin:server:requestTitles', function()
    sendUserData(source)
end)

RegisterNetEvent('cookie_admin:server:equipTitle', function(kind, titleId)
    local src = source
    if not ensureTables() then return end
    if not next(titleCache) then refreshCache() end

    kind = clean(kind):lower()
    if kind ~= 'chat' and kind ~= 'head' then return end

    local gobun = gobunOfSource(src)
    if not gobun then return sendUserData(src, '고번 정보를 찾을 수 없습니다.', true) end

    titleId = tonumber(titleId)
    if titleId then
        local t = titleCache[titleId]
        if not t or t.kind ~= kind or not ownsTitle(gobun, t) then
            return sendUserData(src, '보유하지 않았거나 사용할 수 없는 칭호입니다.', true)
        end
    end

    if kind == 'chat' then
        MySQL.query.await([[
            INSERT INTO cookie_title_equipped (gobun, chat_title_id, chat_text_title_id, chat_emoji_title_id)
            VALUES (?, ?, ?, NULL)
            ON DUPLICATE KEY UPDATE
                chat_title_id = VALUES(chat_title_id),
                chat_text_title_id = VALUES(chat_text_title_id),
                chat_emoji_title_id = NULL
        ]], { gobun, titleId, titleId })
    else
        MySQL.query.await([[
            INSERT INTO cookie_title_equipped (gobun, head_title_id)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE head_title_id = VALUES(head_title_id)
        ]], { gobun, titleId })
    end

    CookieRefreshTitleState(src)
    sendUserData(src, titleId and '칭호를 적용했습니다.' or '칭호를 해제했습니다.', false)
end)

RegisterNetEvent('cookie_admin:server:saveTitleDisplaySettings', function(data)
    local src = source
    if not ensureTables() or type(data) ~= 'table' then return end

    local gobun = gobunOfSource(src)
    if not gobun then return sendUserData(src, '고번 정보를 찾을 수 없습니다.', true) end

    local order = clean(data.headOrder):lower()
    if order ~= 'lover_first' then order = 'title_first' end

    local loverVisible = data.loverVisible ~= false

    MySQL.query.await([[
        INSERT INTO cookie_title_equipped (gobun, head_order, lover_visible)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            head_order = VALUES(head_order),
            lover_visible = VALUES(lover_visible)
    ]], { gobun, order, loverVisible and 1 or 0 })

    CookieRefreshTitleState(src)
    sendUserData(src, '머리 위 표시 설정을 저장했습니다.', false)
end)

RegisterNetEvent('cookie_admin:server:requestTitleAdmin', function()
    local src = source
    if not adminAuth(src) then return end
    sendAdminData(src)
end)

RegisterNetEvent('cookie_admin:server:saveTitleDefinition', function(data)
    local src = source
    local admin = adminAuth(src)
    if not admin or type(data) ~= 'table' or not ensureTables() then return end

    local id = tonumber(data.id)
    local kind = clean(data.kind):lower()
    local scope = clean(data.scope):lower()
    local name = clean(data.name)
    local text = clean(data.text)
    local active = data.active ~= false
    local targetGobun = tonumber(data.targetGobun)
    local issueLimit = math.floor(math.max(0, math.min(100000, tonumber(data.issueLimit) or 0)))
    local color = validColor(data.color, '#FFE08A')
    local bg = validColor(data.bg, '#251B0B')

    if kind ~= 'chat' and kind ~= 'head' then
        return sendAdminData(src, '칭호 종류가 올바르지 않습니다.', true)
    end
    if scope ~= 'custom' and scope ~= 'event' then
        return sendAdminData(src, '배포 유형이 올바르지 않습니다.', true)
    end
    if name == '' then
        return sendAdminData(src, '칭호 이름을 입력해주세요.', true)
    end
    if text == '' then
        return sendAdminData(src, '실제로 표시할 글자를 입력해주세요.', true)
    end

    if scope == 'custom' then
        if not targetGobun then
            return sendAdminData(src, '커스텀 칭호는 사용 유저 고번이 필요합니다.', true)
        end
        local exists = gobunExists(targetGobun)
        if not exists then
            return sendAdminData(src, ('%d번 유저를 찾을 수 없습니다.'):format(targetGobun), true)
        end
        issueLimit = 1
    else
        targetGobun = nil
    end

    if id then
        local old = MySQL.single.await('SELECT id FROM cookie_title_catalog WHERE id = ? LIMIT 1', { id })
        if not old then return sendAdminData(src, '수정할 칭호를 찾을 수 없습니다.', true) end

        MySQL.update.await([[
            UPDATE cookie_title_catalog
            SET kind = ?, chat_subtype = 'text', scope_type = ?, name = ?,
                chat_image = NULL, head_text = ?, head_color = ?, head_bg = ?,
                target_gobun = ?, issue_limit = ?, is_active = ?
            WHERE id = ?
        ]], {
            kind, scope, name, text, color, bg,
            targetGobun, issueLimit, active and 1 or 0, id
        })
    else
        id = MySQL.insert.await([[
            INSERT INTO cookie_title_catalog
                (kind, chat_subtype, scope_type, name, chat_image, head_text,
                 head_color, head_bg, target_gobun, issue_limit, is_active, created_by)
            VALUES (?, 'text', ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            kind, scope, name, text, color, bg,
            targetGobun, issueLimit, active and 1 or 0, clean(admin.admin_name)
        })
    end

    if not id then return sendAdminData(src, '칭호 저장에 실패했습니다.', true) end

    if scope == 'custom' then
        MySQL.query.await('DELETE FROM cookie_title_ownership WHERE title_id = ?', { id })
        MySQL.insert.await([[
            INSERT IGNORE INTO cookie_title_ownership (title_id, gobun, granted_by)
            VALUES (?, ?, ?)
        ]], { id, targetGobun, clean(admin.admin_name) })

        MySQL.update.await('UPDATE cookie_title_equipped SET chat_title_id = NULL, chat_text_title_id = NULL WHERE chat_title_id = ? OR chat_text_title_id = ?', { id, id })
        MySQL.update.await('UPDATE cookie_title_equipped SET head_title_id = NULL WHERE head_title_id = ?', { id })
    end

    refreshAllOnline()
    sendAdminData(src, '칭호 설정을 저장했습니다.', false)
end)

RegisterNetEvent('cookie_admin:server:grantEventTitle', function(titleId, gobun)
    local src = source
    local admin = adminAuth(src)
    if not admin or not ensureTables() then return end

    titleId = tonumber(titleId)
    gobun = tonumber(gobun)
    if not titleId or not gobun then return sendAdminData(src, '지급할 고번을 입력해주세요.', true) end

    local row = MySQL.single.await([[
        SELECT id, scope_type, issue_limit, is_active
        FROM cookie_title_catalog WHERE id = ? LIMIT 1
    ]], { titleId })

    if not row or row.scope_type ~= 'event' then
        return sendAdminData(src, '이벤트 칭호가 아닙니다.', true)
    end
    if row.is_active ~= 1 and row.is_active ~= true then
        return sendAdminData(src, '비활성 칭호는 지급할 수 없습니다.', true)
    end

    local limit = tonumber(row.issue_limit) or 0
    if limit <= 0 then
        return sendAdminData(src, '전체 공개 칭호는 별도 지급할 필요가 없습니다.', true)
    end

    local exists, nickname = gobunExists(gobun)
    if not exists then return sendAdminData(src, ('%d번 유저를 찾을 수 없습니다.'):format(gobun), true) end

    local already = MySQL.single.await(
        'SELECT 1 AS x FROM cookie_title_ownership WHERE title_id = ? AND gobun = ? LIMIT 1',
        { titleId, gobun }
    )
    if already then return sendAdminData(src, ('%d번 유저는 이미 이 칭호를 보유 중입니다.'):format(gobun), true) end

    local countRow = MySQL.single.await('SELECT COUNT(*) AS c FROM cookie_title_ownership WHERE title_id = ?', { titleId })
    local count = countRow and tonumber(countRow.c) or 0
    if count >= limit then return sendAdminData(src, ('지급 한도 %d개를 모두 사용했습니다.'):format(limit), true) end

    MySQL.insert.await([[
        INSERT INTO cookie_title_ownership (title_id, gobun, granted_by)
        VALUES (?, ?, ?)
    ]], { titleId, gobun, clean(admin.admin_name) })

    sendAdminData(src, ('%d번%s에게 칭호를 지급했습니다.'):format(gobun, nickname and (' ('..nickname..')') or ''), false)
end)

RegisterNetEvent('cookie_admin:server:revokeEventTitle', function(titleId, gobun)
    local src = source
    if not adminAuth(src) or not ensureTables() then return end

    titleId = tonumber(titleId)
    gobun = tonumber(gobun)
    if not titleId or not gobun then return end

    MySQL.query.await('DELETE FROM cookie_title_ownership WHERE title_id = ? AND gobun = ?', { titleId, gobun })
    MySQL.update.await('UPDATE cookie_title_equipped SET chat_title_id = NULL, chat_text_title_id = NULL WHERE gobun = ? AND (chat_title_id = ? OR chat_text_title_id = ?)', { gobun, titleId, titleId })
    MySQL.update.await('UPDATE cookie_title_equipped SET head_title_id = NULL WHERE gobun = ? AND head_title_id = ?', { gobun, titleId })

    refreshAllOnline()
    sendAdminData(src, ('%d번 유저의 칭호 지급을 취소했습니다.'):format(gobun), false)
end)

RegisterNetEvent('cookie_admin:server:deleteTitleDefinition', function(titleId)
    local src = source
    if not adminAuth(src) or not ensureTables() then return end

    titleId = tonumber(titleId)
    if not titleId then return end

    local row = MySQL.single.await('SELECT name FROM cookie_title_catalog WHERE id = ? LIMIT 1', { titleId })
    if not row then return sendAdminData(src, '삭제할 칭호를 찾을 수 없습니다.', true) end

    MySQL.update.await('UPDATE cookie_title_equipped SET chat_title_id = NULL, chat_text_title_id = NULL WHERE chat_title_id = ? OR chat_text_title_id = ?', { titleId, titleId })
    MySQL.update.await('UPDATE cookie_title_equipped SET chat_emoji_title_id = NULL WHERE chat_emoji_title_id = ?', { titleId })
    MySQL.update.await('UPDATE cookie_title_equipped SET head_title_id = NULL WHERE head_title_id = ?', { titleId })
    MySQL.query.await('DELETE FROM cookie_title_ownership WHERE title_id = ?', { titleId })
    MySQL.query.await('DELETE FROM cookie_title_catalog WHERE id = ?', { titleId })

    refreshAllOnline()
    sendAdminData(src, ('"%s" 칭호를 삭제했습니다.'):format(row.name), false)
end)

CreateThread(function()
    Wait(1200)
    if ensureTables() then
        refreshCache()
        Wait(700)
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            if src then pcall(CookieRefreshTitleState, src) end
        end
        print('[cookie_admin] COOKIE TITLE SYSTEM V3 TEXT ONLY loaded')
    end
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    CreateThread(function()
        Wait(2500)
        pcall(CookieRefreshTitleState, src)
    end)
end)

AddEventHandler('playerJoining', function()
    local src = source
    CreateThread(function()
        Wait(3500)
        pcall(CookieRefreshTitleState, src)
    end)
end)
