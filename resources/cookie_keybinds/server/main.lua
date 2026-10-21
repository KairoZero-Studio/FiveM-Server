local function notify(src, msg, isError)
    TriggerClientEvent('cookie_keybinds:client:notify', src, msg, isError == true)
end

local function getAdminLevel(src)
    if GetResourceState('cookie_admin') == 'started' then
        local ok, level = pcall(function()
            return exports.cookie_admin:getEffectiveLevel(src)
        end)
        if ok and tonumber(level) then
            return tonumber(level)
        end
    end
    return 0
end

local function isGuideAdmin(src)
    if getAdminLevel(src) >= (Config.AdminMinLevel or 4) then
        return true
    end

    if Config.AllowAceFallback then
        if Config.AdminAce and IsPlayerAceAllowed(src, Config.AdminAce) then
            return true
        end
        if IsPlayerAceAllowed(src, 'admin') then
            return true
        end
    end

    return false
end

local function playerHasGroup(src, name)
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not player.PlayerData then return false end

    local job = player.PlayerData.job
    if job and job.name == name then return true end

    local ok, result = pcall(function()
        return exports.qbx_core:HasGroup(src, name)
    end)
    return ok and result == true
end

local function decodeVisibility(value)
    if not value or value == '' then return {} end
    local ok, decoded = pcall(json.decode, value)
    if ok and type(decoded) == 'table' then return decoded end
    return {}
end

local function canSeeCategory(src, row)
    local mode = row.visibility_mode or 'all'
    if mode == 'all' then return true end

    if mode == 'admin' then
        local minLevel = tonumber(row.visibility_value) or Config.AdminMinLevel or 4
        if getAdminLevel(src) >= minLevel then return true end
        return Config.AllowAceFallback and isGuideAdmin(src)
    end

    if mode == 'jobs' then
        for _, name in ipairs(decodeVisibility(row.visibility_value)) do
            if playerHasGroup(src, tostring(name)) then return true end
        end
        return false
    end

    return false
end

local function fetchAll()
    local categories = MySQL.query.await([[
        SELECT id, category_key, label, icon, visibility_mode, visibility_value, enabled, sort_order
        FROM cookie_keyguide_category
        ORDER BY sort_order, id
    ]]) or {}

    local items = MySQL.query.await([[
        SELECT id, category_id, item_key, key_label, label, description, enabled, sort_order
        FROM cookie_keyguide_item
        ORDER BY category_id, sort_order, id
    ]]) or {}

    local byCat = {}
    for _, item in ipairs(items) do
        item.enabled = item.enabled == 1 or item.enabled == true
        byCat[item.category_id] = byCat[item.category_id] or {}
        byCat[item.category_id][#byCat[item.category_id] + 1] = item
    end

    for _, cat in ipairs(categories) do
        cat.enabled = cat.enabled == 1 or cat.enabled == true
        cat.items = byCat[cat.id] or {}
    end

    return categories
end

local function fetchVisible(src)
    local result = {}
    for _, cat in ipairs(fetchAll()) do
        if cat.enabled and canSeeCategory(src, cat) then
            local out = {
                id = cat.id,
                key = cat.category_key,
                label = cat.label,
                icon = cat.icon,
                items = {}
            }

            for _, item in ipairs(cat.items or {}) do
                if item.enabled then
                    out.items[#out.items + 1] = {
                        id = item.id,
                        key = item.item_key,
                        keyLabel = item.key_label,
                        label = item.label,
                        description = item.description,
                    }
                end
            end

            if #out.items > 0 then
                result[#result + 1] = out
            end
        end
    end
    return result
end

local function safeKey(value)
    value = tostring(value or ''):lower()
    value = value:gsub('[^a-z0-9_%-]', '_')
    value = value:gsub('_+', '_')
    value = value:gsub('^_+', ''):gsub('_+$', '')
    return value:sub(1, 64)
end

local function normalizeVisibility(mode, value)
    if mode == 'jobs' then
        local arr = {}
        if type(value) == 'table' then
            for _, v in ipairs(value) do
                local s = tostring(v):gsub('^%s+', ''):gsub('%s+$', '')
                if s ~= '' then arr[#arr + 1] = s end
            end
        else
            for token in tostring(value or ''):gmatch('[^,]+') do
                local s = token:gsub('^%s+', ''):gsub('%s+$', '')
                if s ~= '' then arr[#arr + 1] = s end
            end
        end
        return json.encode(arr)
    elseif mode == 'admin' then
        return tostring(math.max(1, tonumber(value) or Config.AdminMinLevel or 4))
    end
    return nil
end

local function sendAdminData(src)
    TriggerClientEvent('cookie_keybinds:client:adminData', src, fetchAll())
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_keyguide_category (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            category_key VARCHAR(64) NOT NULL,
            label VARCHAR(80) NOT NULL,
            icon VARCHAR(16) NULL,
            visibility_mode ENUM('all','jobs','admin') NOT NULL DEFAULT 'all',
            visibility_value TEXT NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT NOT NULL DEFAULT 100,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_cookie_keyguide_category_key (category_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_keyguide_item (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            category_id BIGINT UNSIGNED NOT NULL,
            item_key VARCHAR(64) NOT NULL,
            key_label VARCHAR(32) NOT NULL,
            label VARCHAR(100) NOT NULL,
            description VARCHAR(255) NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT NOT NULL DEFAULT 100,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uq_cookie_keyguide_item_key (category_id, item_key),
            KEY idx_cookie_keyguide_item_category (category_id),
            CONSTRAINT fk_cookie_keyguide_item_category
                FOREIGN KEY (category_id) REFERENCES cookie_keyguide_category(id)
                ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    local jobsJson = json.encode(Config.PoliceGuideJobs or { 'police', 'security' })

    MySQL.query.await([[
        INSERT INTO cookie_keyguide_category
            (category_key, label, icon, visibility_mode, visibility_value, enabled, sort_order)
        VALUES
            ('police_shortcuts', '경찰 단축키', '🚓', 'jobs', ?, 1, 40)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            icon = VALUES(icon)
    ]], { jobsJson })

    -- 기존 카테고리가 최초 seed 기본값일 때만 공개 대상을 police/security로 보정.
    MySQL.update.await([[
        UPDATE cookie_keyguide_category
        SET visibility_mode='jobs', visibility_value=?
        WHERE category_key='police_shortcuts'
          AND (visibility_mode='all' OR visibility_value IS NULL OR visibility_value='')
    ]], { jobsJson })

    local categoryId = MySQL.scalar.await(
        "SELECT id FROM cookie_keyguide_category WHERE category_key='police_shortcuts' LIMIT 1"
    )

    if categoryId then
        for _, it in ipairs(Config.PoliceGuideItems or {}) do
            -- 관리자 수정값을 보존하기 위해 중복이면 아무것도 덮어쓰지 않습니다.
            MySQL.query.await([[
                INSERT IGNORE INTO cookie_keyguide_item
                    (category_id, item_key, key_label, label, description, enabled, sort_order)
                VALUES (?, ?, ?, ?, ?, 1, ?)
            ]], { categoryId, it.key, it.keyLabel, it.label, it.description, it.sort or 100 })
        end
    end

    print('^2[cookie_keybinds]^7 V2.0 keybind + key guide DB/UI loaded')
end)

RegisterNetEvent('cookie_keybinds:server:requestGuide', function()
    local src = source
    TriggerClientEvent('cookie_keybinds:client:guideData', src, fetchVisible(src), isGuideAdmin(src))
end)

RegisterNetEvent('cookie_keybinds:server:requestAdmin', function()
    local src = source
    if not isGuideAdmin(src) then
        notify(src, '키 가이드 관리 권한이 없습니다.', true)
        return
    end
    sendAdminData(src)
end)

RegisterNetEvent('cookie_keybinds:server:saveCategory', function(data)
    local src = source
    if not isGuideAdmin(src) or type(data) ~= 'table' then return end

    local id = tonumber(data.id)
    local key = safeKey(data.categoryKey)
    local label = tostring(data.label or ''):sub(1, 80)
    local icon = tostring(data.icon or ''):sub(1, 16)
    local mode = tostring(data.visibilityMode or 'all')
    if mode ~= 'all' and mode ~= 'jobs' and mode ~= 'admin' then mode = 'all' end

    if key == '' or label == '' then
        notify(src, '카테고리 내부키와 표시 이름을 입력하세요.', true)
        return
    end

    local storedValue = normalizeVisibility(mode, data.visibilityValue)
    local enabled = data.enabled == false and 0 or 1
    local sortOrder = tonumber(data.sortOrder) or 100

    local ok, err = pcall(function()
        if id then
            MySQL.update.await([[
                UPDATE cookie_keyguide_category
                SET category_key=?, label=?, icon=?, visibility_mode=?, visibility_value=?, enabled=?, sort_order=?
                WHERE id=?
            ]], { key, label, icon, mode, storedValue, enabled, sortOrder, id })
        else
            MySQL.insert.await([[
                INSERT INTO cookie_keyguide_category
                    (category_key, label, icon, visibility_mode, visibility_value, enabled, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ]], { key, label, icon, mode, storedValue, enabled, sortOrder })
        end
    end)

    if not ok then
        notify(src, '저장 실패: 내부키가 중복되었는지 확인하세요.', true)
        print(('[cookie_keybinds] saveCategory error: %s'):format(err))
        return
    end

    sendAdminData(src)
    notify(src, '키 가이드 카테고리를 저장했습니다.', false)
end)

RegisterNetEvent('cookie_keybinds:server:deleteCategory', function(id)
    local src = source
    if not isGuideAdmin(src) then return end
    id = tonumber(id)
    if not id then return end

    MySQL.update.await('DELETE FROM cookie_keyguide_category WHERE id=?', { id })
    sendAdminData(src)
    notify(src, '카테고리를 삭제했습니다.', false)
end)

RegisterNetEvent('cookie_keybinds:server:saveItem', function(data)
    local src = source
    if not isGuideAdmin(src) or type(data) ~= 'table' then return end

    local id = tonumber(data.id)
    local categoryId = tonumber(data.categoryId)
    local itemKey = safeKey(data.itemKey)
    local keyLabel = tostring(data.keyLabel or ''):sub(1, 32)
    local label = tostring(data.label or ''):sub(1, 100)
    local description = tostring(data.description or ''):sub(1, 255)
    local enabled = data.enabled == false and 0 or 1
    local sortOrder = tonumber(data.sortOrder) or 100

    if not categoryId or itemKey == '' or keyLabel == '' or label == '' then
        notify(src, '카테고리, 내부키, 표시 키, 기능명을 모두 입력하세요.', true)
        return
    end

    local exists = MySQL.scalar.await('SELECT id FROM cookie_keyguide_category WHERE id=? LIMIT 1', { categoryId })
    if not exists then
        notify(src, '존재하지 않는 카테고리입니다.', true)
        return
    end

    local ok, err = pcall(function()
        if id then
            MySQL.update.await([[
                UPDATE cookie_keyguide_item
                SET category_id=?, item_key=?, key_label=?, label=?, description=?, enabled=?, sort_order=?
                WHERE id=?
            ]], { categoryId, itemKey, keyLabel, label, description, enabled, sortOrder, id })
        else
            MySQL.insert.await([[
                INSERT INTO cookie_keyguide_item
                    (category_id, item_key, key_label, label, description, enabled, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ]], { categoryId, itemKey, keyLabel, label, description, enabled, sortOrder })
        end
    end)

    if not ok then
        notify(src, '저장 실패: 같은 카테고리 내부키가 중복되었는지 확인하세요.', true)
        print(('[cookie_keybinds] saveItem error: %s'):format(err))
        return
    end

    sendAdminData(src)
    notify(src, '키 가이드 항목을 저장했습니다.', false)
end)

RegisterNetEvent('cookie_keybinds:server:deleteItem', function(id)
    local src = source
    if not isGuideAdmin(src) then return end
    id = tonumber(id)
    if not id then return end

    MySQL.update.await('DELETE FROM cookie_keyguide_item WHERE id=?', { id })
    sendAdminData(src)
    notify(src, '단축키 항목을 삭제했습니다.', false)
end)

exports('IsKeyGuideAdmin', isGuideAdmin)
