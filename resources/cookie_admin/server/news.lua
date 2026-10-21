

local MIN_LEVEL = Config.NewsMinLevel or 2

local function anotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `cookie_news` (
              `id`         INT AUTO_INCREMENT PRIMARY KEY,
              `kind`       VARCHAR(10)  NOT NULL,          -- update | banner
              `badge`      VARCHAR(20)  NULL,              -- 패치노트 / 채용 등 (update 전용)
              `title`      VARCHAR(80)  NULL,
              `body`       VARCHAR(300) NULL,
              `image`      VARCHAR(300) NULL,              -- banner 전용 (또는 update 썸네일)
              `author`     VARCHAR(60)  NULL,
              `active`     TINYINT(1)   NOT NULL DEFAULT 1,
              `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
              KEY `idx_kind` (`kind`, `active`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
        ]], {})
    end)

    pcall(function()
        MySQL.query.await("ALTER TABLE `cookie_news` MODIFY `body` TEXT NULL", {})
    end)

    pcall(function()
        MySQL.query.await("ALTER TABLE `cookie_news` MODIFY `image` MEDIUMTEXT NULL", {})
    end)

    if ok then

    else

    end
end)

local function pushNews(src)
    local rows = MySQL.query.await([[
        SELECT id, kind, badge, title, body, image, author, active
        FROM cookie_news
        ORDER BY id DESC
    ]], {}) or {}
    TriggerClientEvent('cookie_admin:client:newsList', src, rows)
end

RegisterNetEvent('cookie_admin:server:requestNews', function()
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then return end
    pushNews(src)
end)

RegisterNetEvent('cookie_admin:server:newsAdd', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then
        return anotify(src, ('소식 관리는 LV%d 이상만 가능합니다'):format(MIN_LEVEL), true)
    end
    if type(data) ~= 'table' then return end

    local function trim(s, max)
        s = type(s) == 'string' and s:gsub('^%s+', ''):gsub('%s+$', '') or ''
        if max and #s > max then s = s:sub(1, max) end
        return s
    end

    local kind = (data.kind == 'banner') and 'banner' or 'update'
    local badge = trim(data.badge, 20)
    local title = trim(data.title, 80)
    local body = trim(data.body, 4000)

    local image = trim(data.image, 1500000)

    if kind == 'banner' then

        if image == '' then
            return anotify(src, '이미지 주소를 입력하세요', true)
        end
        title, body, badge = '', '', ''
    else
        if title == '' then
            return anotify(src, '제목을 입력하세요', true)
        end
        if badge == '' then badge = '패치노트' end
    end

    MySQL.insert.await([[
        INSERT INTO cookie_news (kind, badge, title, body, image, author)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { kind, badge, title, body, image, admin.admin_name })

    anotify(src, kind == 'banner' and '소식을 등록했습니다' or '업데이트 내역을 등록했습니다', false)

    pushNews(src)
end)

RegisterNetEvent('cookie_admin:server:newsEdit', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then
        return anotify(src, ('소식 관리는 LV%d 이상만 가능합니다'):format(MIN_LEVEL), true)
    end
    if type(data) ~= 'table' then return end

    local id = math.floor(tonumber(data.id) or 0)
    if id <= 0 then return end

    local row = MySQL.single.await('SELECT kind FROM cookie_news WHERE id = ?', { id })
    if not row then
        return anotify(src, '항목을 찾을 수 없습니다', true)
    end

    local function trim(s, max)
        s = type(s) == 'string' and s:gsub('^%s+', ''):gsub('%s+$', '') or ''
        if max and #s > max then s = s:sub(1, max) end
        return s
    end

    if row.kind == 'banner' then
        local image = trim(data.image, 1500000)
        if image == '' then
            return anotify(src, '이미지를 선택하거나 주소를 입력하세요', true)
        end
        MySQL.update.await('UPDATE cookie_news SET image = ? WHERE id = ?', { image, id })
    else
        local title = trim(data.title, 80)
        if title == '' then
            return anotify(src, '제목을 입력하세요', true)
        end
        local badge = trim(data.badge, 20)
        if badge == '' then badge = '패치노트' end
        MySQL.update.await([[
            UPDATE cookie_news SET badge = ?, title = ?, body = ? WHERE id = ?
        ]], { badge, title, trim(data.body, 4000), id })
    end

    anotify(src, '수정했습니다', false)

    pushNews(src)
end)

RegisterNetEvent('cookie_admin:server:newsToggle', function(id)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then return end

    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return end

    MySQL.update.await('UPDATE cookie_news SET active = 1 - active WHERE id = ?', { id })
    pushNews(src)
end)

RegisterNetEvent('cookie_admin:server:newsDelete', function(id)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < MIN_LEVEL then return end

    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return end

    MySQL.query.await('DELETE FROM cookie_news WHERE id = ?', { id })
    anotify(src, '삭제했습니다', false)

    pushNews(src)
end)
