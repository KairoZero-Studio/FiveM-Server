print('[cookie_admin] KEY GUIDE V3.0 server loaded')

-- COOKIE KEY GUIDE V3
-- F3 > 내 정보 > 시스템 > 키 가이드
-- 관리자: F3 관리자 > 시스템 관리 > 키 가이드
--
-- 구조:
--   카테고리(= 유저 화면의 버튼) -> 공개 팩션(복수 선택 가능) -> 단축키 항목
-- 기존 V2 cookie_keyguide 데이터는 자동으로 "기본 단축키" 카테고리로 이관됩니다.

local DEFAULT_KEYS = {
    { key_name = 'P',   label = '휴대전화', description = 'COOKIE PHONE을 열거나 다시 눌러 집어넣습니다.', tone = 'phone', sort_order = 10 },
    { key_name = 'ESC', label = '메뉴',     description = 'COOKIE 메뉴를 엽니다.',                           tone = 'menu',  sort_order = 20 },
    { key_name = 'T',   label = '채팅',     description = '채팅 입력창을 열어 메시지를 입력합니다.',           tone = 'chat',  sort_order = 30 },
    { key_name = 'F3',  label = '내 정보',  description = 'F3 내 정보 패널을 엽니다.',                        tone = 'info',  sort_order = 40 },
    { key_name = 'N',   label = '말하기',   description = '음성 채팅으로 주변 사람에게 말합니다.',              tone = 'voice', sort_order = 50 },
    { key_name = 'CAPS LOCK', label = '상호작용', description = '바라보는 시민과 거래하거나 고백합니다.', tone = 'info', sort_order = 60 },
}

local POLICE_KEYS = {
    { key_name = 'NUM 7',   label = '경광등',        description = '순찰차 경광등을 켜거나 끕니다.',                         tone = 'police', sort_order = 10 },
    { key_name = 'NUM 8',   label = '사이렌',        description = '순찰차 사이렌을 켜거나 끕니다.',                         tone = 'police', sort_order = 20 },
    { key_name = 'NUM 9',   label = 'P.M 모드',      description = '앞 차량 정차 명령 모드를 켜거나 끕니다.',                  tone = 'police', sort_order = 30 },
    { key_name = 'Y',       label = '차량 정차 요청', description = 'P.M 모드에서 앞 차량에 정차 요청을 보냅니다.',              tone = 'warning', sort_order = 40 },
    { key_name = 'G',       label = '수갑',           description = '가까운 대상에게 수갑을 채우거나 해제합니다.',                tone = 'police', sort_order = 50 },
    { key_name = 'PAGE UP', label = '미란다 고지',   description = '가까운 대상에게 미란다 원칙을 고지합니다.',                  tone = 'info', sort_order = 60 },
    { key_name = 'H',       label = '호송',           description = '수갑이 채워진 가까운 대상을 호송하거나 해제합니다.',           tone = 'police', sort_order = 70 },
    { key_name = 'F1',      label = '지원 요청',      description = '근무 중인 같은 치안 팩션 인원에게 현재 위치 지원을 요청합니다.', tone = 'warning', sort_order = 80 },
}

local VALID_TONES = {
    default = true, phone = true, menu = true, chat = true, info = true,
    voice = true, warning = true, police = true, medical = true, mechanic = true
}

local function cleanText(v, maxLen)
    local s = tostring(v or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > (maxLen or 80) then s = s:sub(1, maxLen or 80) end
    return s
end

local function cleanKey(v)
    return cleanText(v, 24):upper()
end

local function safeSlug(v)
    local s = tostring(v or ''):lower():gsub('[^%a%d_%-]', '_'):gsub('_+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    if #s > 50 then s = s:sub(1, 50) end
    return s
end

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
end

local function effectiveAdmin(src)
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

    row.effective_level = level
    return row
end

local function activeFactionList()
    local rows = MySQL.query.await([[
        SELECT id, faction_key, faction_type, job_name, name, emoji, color
        FROM cookie_faction
        WHERE is_active = 1
        ORDER BY name ASC, id ASC
    ]], {}) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(row.id),
            key = cleanText(row.faction_key, 40),
            type = cleanText(row.faction_type, 30),
            jobName = cleanText(row.job_name, 40),
            name = cleanText(row.name, 80),
            emoji = cleanText(row.emoji, 32),
            color = cleanText(row.color, 20),
        }
    end
    return out
end

local function currentFactionId(src)
    -- cookie_admin/server/faction.lua가 keyguide.lua보다 먼저 로드되므로 기존 멤버십 함수를 우선 사용합니다.
    if type(CookieFactionMemberOf) == 'function' then
        local ok, member = pcall(CookieFactionMemberOf, src)
        if ok and member and member.id then return tonumber(member.id) end
    end

    local player = exports.qbx_core:GetPlayer(src)
    local cid = player and player.PlayerData and player.PlayerData.citizenid
    if not cid then return nil end

    local id = MySQL.scalar.await([[
        SELECT m.faction_id
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id = m.faction_id AND f.is_active = 1
        WHERE m.citizenid = ? AND m.status = 'active'
        LIMIT 1
    ]], { cid })
    return tonumber(id)
end

local function categoryFactionIds(categoryId)
    local rows = MySQL.query.await([[
        SELECT faction_id
        FROM cookie_keyguide_category_faction
        WHERE category_id = ?
        ORDER BY faction_id
    ]], { categoryId }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local id = tonumber(row.faction_id)
        if id then out[#out + 1] = id end
    end
    return out
end

local function itemRows(categoryId, includeDisabled)
    local whereActive = includeDisabled and '' or 'AND is_active = 1'
    local rows = MySQL.query.await(([[
        SELECT id, category_id, key_name, label, description, tone, sort_order, is_active
        FROM cookie_keyguide
        WHERE category_id = ? %s
        ORDER BY sort_order ASC, id ASC
    ]]):format(whereActive), { categoryId }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            id = tonumber(row.id),
            categoryId = tonumber(row.category_id),
            key = cleanKey(row.key_name),
            title = cleanText(row.label, 50),
            desc = cleanText(row.description, 160),
            tone = cleanText(row.tone, 20),
            order = tonumber(row.sort_order) or 0,
            enabled = row.is_active == 1 or row.is_active == true,
        }
    end
    return out
end

local function categoryRows(includeDisabled)
    local where = includeDisabled and '' or 'WHERE c.is_active = 1'
    local rows = MySQL.query.await(([[
        SELECT c.id, c.category_key, c.label, c.icon, c.tone, c.visibility_mode,
               c.sort_order, c.is_active
        FROM cookie_keyguide_category c
        %s
        ORDER BY c.sort_order ASC, c.id ASC
    ]]):format(where)) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local id = tonumber(row.id)
        out[#out + 1] = {
            id = id,
            categoryKey = cleanText(row.category_key, 50),
            label = cleanText(row.label, 60),
            icon = cleanText(row.icon, 16),
            tone = cleanText(row.tone, 20),
            visibilityMode = row.visibility_mode == 'factions' and 'factions' or 'all',
            factionIds = categoryFactionIds(id),
            order = tonumber(row.sort_order) or 0,
            enabled = row.is_active == 1 or row.is_active == true,
            items = itemRows(id, includeDisabled),
        }
    end
    return out
end

local function visibleCategories(src)
    local factionId = currentFactionId(src)
    local out = {}

    for _, cat in ipairs(categoryRows(false)) do
        local visible = cat.visibilityMode == 'all'

        if cat.visibilityMode == 'factions' and factionId then
            for _, allowedId in ipairs(cat.factionIds or {}) do
                if tonumber(allowedId) == factionId then
                    visible = true
                    break
                end
            end
        end

        if visible and #cat.items > 0 then
            -- 유저 화면에는 공개 대상 ID 자체를 노출할 이유가 없습니다.
            cat.factionIds = nil
            cat.visibilityMode = nil
            out[#out + 1] = cat
        end
    end

    return out
end

local function ensureCategory(categoryKey, label, icon, tone, visibilityMode, sortOrder)
    local row = MySQL.single.await(
        'SELECT id FROM cookie_keyguide_category WHERE category_key = ? LIMIT 1',
        { categoryKey }
    )
    if row and row.id then return tonumber(row.id), false end

    local id = MySQL.insert.await([[
        INSERT INTO cookie_keyguide_category
            (category_key, label, icon, tone, visibility_mode, sort_order, is_active)
        VALUES (?, ?, ?, ?, ?, ?, 1)
    ]], { categoryKey, label, icon, tone, visibilityMode, sortOrder })

    return tonumber(id), true
end

local function seedItems(categoryId, rows)
    if not categoryId then return end
    for _, row in ipairs(rows) do
        local exists = MySQL.scalar.await([[
            SELECT id FROM cookie_keyguide
            WHERE category_id = ? AND key_name = ?
            LIMIT 1
        ]], { categoryId, row.key_name })

        if not exists then
            MySQL.insert.await([[
                INSERT INTO cookie_keyguide
                    (category_id, key_name, label, description, tone, sort_order, is_active)
                VALUES (?, ?, ?, ?, ?, ?, 1)
            ]], {
                categoryId, row.key_name, row.label, row.description,
                row.tone, row.sort_order
            })
        end
    end
end

local function tableExists(name)
    local n = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema = DATABASE() AND table_name = ?
    ]], { name })
    return (tonumber(n) or 0) > 0
end

local function columnExists(tableName, columnName)
    local n = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?
    ]], { tableName, columnName })
    return (tonumber(n) or 0) > 0
end

local function migrateLegacyKeybindGuide()
    -- 우리가 이전에 분리형 cookie_keybinds에서 사용하던 테이블도 같은 DB에 남아 있을 수 있습니다.
    -- 해당 데이터를 현재 cookie_admin V3 구조로 가능한 범위에서 흡수합니다.
    if not tableExists('cookie_keyguide_item') then return end

    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT category_id, key_label, label, description, sort_order, enabled
            FROM cookie_keyguide_item
            ORDER BY category_id, sort_order, id
        ]], {})
    end)
    if not ok or not rows then return end

    for _, row in ipairs(rows) do
        local categoryId = tonumber(row.category_id)
        local key = cleanKey(row.key_label)
        local title = cleanText(row.label, 50)
        if categoryId and key ~= '' and title ~= '' then
            local exists = MySQL.scalar.await([[
                SELECT id FROM cookie_keyguide
                WHERE category_id = ? AND key_name = ?
                LIMIT 1
            ]], { categoryId, key })

            if not exists then
                MySQL.insert.await([[
                    INSERT INTO cookie_keyguide
                        (category_id, key_name, label, description, tone, sort_order, is_active)
                    VALUES (?, ?, ?, ?, 'default', ?, ?)
                ]], {
                    categoryId,
                    key,
                    title,
                    cleanText(row.description, 160),
                    tonumber(row.sort_order) or 0,
                    (row.enabled == 0 or row.enabled == false) and 0 or 1
                })
            end
        end
    end
end

local function initSchema()
    -- 카테고리 테이블: 과거 cookie_keybinds V2가 같은 이름의 테이블을 만들었어도
    -- 아래 ALTER 단계에서 V3 컬럼을 보강합니다.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_keyguide_category (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            category_key VARCHAR(50) NOT NULL,
            label VARCHAR(60) NOT NULL,
            icon VARCHAR(16) NOT NULL DEFAULT '⌨',
            tone VARCHAR(20) NOT NULL DEFAULT 'default',
            visibility_mode VARCHAR(16) NOT NULL DEFAULT 'all',
            sort_order INT NOT NULL DEFAULT 0,
            is_active TINYINT(1) NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_cookie_keyguide_category_key (category_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide_category ADD COLUMN tone VARCHAR(20) NOT NULL DEFAULT 'default' AFTER icon") end)
    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide_category ADD COLUMN is_active TINYINT(1) NOT NULL DEFAULT 1 AFTER sort_order") end)
    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide_category MODIFY COLUMN category_key VARCHAR(50) NOT NULL") end)
    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide_category MODIFY COLUMN label VARCHAR(60) NOT NULL") end)
    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide_category MODIFY COLUMN icon VARCHAR(16) NOT NULL DEFAULT '⌨'") end)
    -- V2 ENUM('all','jobs','admin') -> V3에서는 factions 값을 넣을 수 있도록 VARCHAR로 확장.
    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide_category MODIFY COLUMN visibility_mode VARCHAR(16) NOT NULL DEFAULT 'all'") end)

    if columnExists('cookie_keyguide_category', 'enabled') then
        pcall(function()
            MySQL.update.await('UPDATE cookie_keyguide_category SET is_active = enabled')
        end)
    end

    -- V2의 경찰 카테고리 키를 V3 표준 키로 승격.
    local oldPolice = MySQL.single.await([[
        SELECT id FROM cookie_keyguide_category
        WHERE category_key = 'police_shortcuts'
        LIMIT 1
    ]])
    local newPolice = MySQL.single.await([[
        SELECT id FROM cookie_keyguide_category
        WHERE category_key = 'police'
        LIMIT 1
    ]])
    if oldPolice and not newPolice then
        MySQL.update.await([[
            UPDATE cookie_keyguide_category
            SET category_key='police', label='경찰 단축키', icon='🚓',
                tone='police', visibility_mode='factions'
            WHERE id=?
        ]], { tonumber(oldPolice.id) })
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_keyguide_category_faction (
            category_id INT UNSIGNED NOT NULL,
            faction_id INT NOT NULL,
            PRIMARY KEY (category_id, faction_id),
            KEY idx_cookie_keyguide_faction (faction_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- V2 플랫 테이블이 없으면 V3 형태로 생성.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_keyguide (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            category_id INT UNSIGNED NULL,
            key_name VARCHAR(24) NOT NULL,
            label VARCHAR(50) NOT NULL,
            description VARCHAR(160) NOT NULL DEFAULT '',
            tone VARCHAR(20) NOT NULL DEFAULT 'default',
            sort_order INT NOT NULL DEFAULT 0,
            is_active TINYINT(1) NOT NULL DEFAULT 1,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            KEY idx_cookie_keyguide_category (category_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- 기존 cookie_admin KEY GUIDE V2 -> V3 안전 마이그레이션.
    pcall(function() MySQL.query.await('ALTER TABLE cookie_keyguide ADD COLUMN category_id INT UNSIGNED NULL AFTER id') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_keyguide MODIFY COLUMN key_name VARCHAR(24) NOT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_keyguide MODIFY COLUMN label VARCHAR(50) NOT NULL') end)
    pcall(function() MySQL.query.await("ALTER TABLE cookie_keyguide MODIFY COLUMN description VARCHAR(160) NOT NULL DEFAULT ''") end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_keyguide DROP INDEX uq_cookie_keyguide_key') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_keyguide ADD KEY idx_cookie_keyguide_category (category_id)') end)
    pcall(function() MySQL.query.await('ALTER TABLE cookie_keyguide ADD UNIQUE KEY uq_cookie_keyguide_category_key (category_id, key_name)') end)

    local defaultId = ensureCategory('default', '기본 단축키', '⌨️', 'default', 'all', 10)

    -- 구버전 데이터에서 category_id=NULL인 키(예: ESC)가 이미 기본 카테고리에
    -- 존재하면 일괄 UPDATE 시 uq_cookie_keyguide_category_key 중복 오류가 난다.
    -- 먼저 NULL 그룹 자체의 중복과 기본 카테고리와의 충돌 행을 정리한 뒤 이동한다.
    pcall(function()
        MySQL.query.await([[
            DELETE a FROM cookie_keyguide a
            INNER JOIN cookie_keyguide b
              ON a.category_id IS NULL
             AND b.category_id IS NULL
             AND a.key_name = b.key_name
             AND a.id > b.id
        ]])
    end)
    pcall(function()
        MySQL.query.await([[
            DELETE n FROM cookie_keyguide n
            INNER JOIN cookie_keyguide d
              ON d.category_id = ?
             AND d.key_name = n.key_name
            WHERE n.category_id IS NULL
        ]], { defaultId })
    end)

    MySQL.update.await('UPDATE cookie_keyguide SET category_id = ? WHERE category_id IS NULL', { defaultId })
    seedItems(defaultId, DEFAULT_KEYS)

    -- 분리형 cookie_keybinds V2에 저장된 기존 카테고리/키가 있으면 흡수.
    migrateLegacyKeybindGuide()

    local policeId, policeCreated = ensureCategory('police', '경찰 단축키', '🚓', 'police', 'factions', 20)
    seedItems(policeId, POLICE_KEYS)

    -- 신규 생성 또는 구버전 마이그레이션 직후 공개 팩션 연결값이 비어 있으면
    -- 현재 police/security 팩션만 자동 선택합니다.
    -- 관리자가 이후 저장한 값은 비어 있을 수 없도록 검증하므로 덮어쓸 일이 없습니다.
    local policeLinks = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM cookie_keyguide_category_faction WHERE category_id = ?',
        { policeId }
    )) or 0

    if policeCreated or policeLinks == 0 then
        local policeFactions = MySQL.query.await([[
            SELECT id
            FROM cookie_faction
            WHERE is_active = 1
              AND (
                    LOWER(COALESCE(faction_type,'')) IN ('police','security')
                 OR LOWER(COALESCE(job_name,'')) IN ('police','security')
              )
            ORDER BY id
        ]], {}) or {}

        for _, f in ipairs(policeFactions) do
            MySQL.query.await([[
                INSERT IGNORE INTO cookie_keyguide_category_faction (category_id, faction_id)
                VALUES (?, ?)
            ]], { policeId, tonumber(f.id) })
        end
    end

    -- V2에서 jobs/admin 공개 방식이 남아 있으면 안전하게 변환.
    MySQL.update.await([[
        UPDATE cookie_keyguide_category
        SET visibility_mode = 'all'
        WHERE visibility_mode NOT IN ('all','factions')
          AND category_key <> 'police'
    ]])
    MySQL.update.await([[
        UPDATE cookie_keyguide_category
        SET visibility_mode = 'factions'
        WHERE category_key = 'police'
    ]])
end

CreateThread(function()
    Wait(1000)
    local ok, err = pcall(initSchema)
    if not ok then
        print(('^1[cookie_admin] KEY GUIDE V3 schema error: %s^7'):format(tostring(err)))
    end
end)

RegisterNetEvent('cookie_admin:server:requestKeyGuide', function()
    local src = source
    TriggerClientEvent('cookie_admin:client:keyGuideData', src, {
        categories = visibleCategories(src)
    })
end)

RegisterNetEvent('cookie_admin:server:requestKeyGuideAdmin', function()
    local src = source
    if not effectiveAdmin(src) then return end

    TriggerClientEvent('cookie_admin:client:keyGuideAdminData', src, {
        categories = categoryRows(true),
        factions = activeFactionList()
    })
end)

local function normalizeSnapshot(data)
    local categories = type(data.categories) == 'table' and data.categories or {}
    if #categories < 1 then return nil, '최소 1개의 버튼(카테고리)이 필요합니다.' end
    if #categories > 30 then return nil, '키 가이드 버튼은 최대 30개까지 만들 수 있습니다.' end

    local catKeys = {}
    local normalized = {}
    local totalItems = 0

    for ci, cat in ipairs(categories) do
        if type(cat) == 'table' then
            local label = cleanText(cat.label, 60)
            if label == '' then return nil, ('%d번째 버튼 이름이 비어 있습니다.'):format(ci) end

            local categoryKey = safeSlug(cat.categoryKey)
            if categoryKey == '' then
                categoryKey = ('guide_%d_%d'):format(os.time(), ci)
            end
            if catKeys[categoryKey] then
                categoryKey = ('%s_%d'):format(categoryKey, ci)
            end
            catKeys[categoryKey] = true

            local visibilityMode = cat.visibilityMode == 'factions' and 'factions' or 'all'
            local factionIds, factionSeen = {}, {}
            if visibilityMode == 'factions' then
                for _, rawId in ipairs(type(cat.factionIds) == 'table' and cat.factionIds or {}) do
                    local id = tonumber(rawId)
                    if id and not factionSeen[id] then
                        factionSeen[id] = true
                        factionIds[#factionIds + 1] = id
                    end
                end
                if #factionIds < 1 then
                    return nil, ('"%s" 버튼은 공개할 팩션을 1개 이상 선택해야 합니다.'):format(label)
                end
            end

            local tone = cleanText(cat.tone, 20):lower()
            if not VALID_TONES[tone] then tone = 'default' end

            local items, itemKeys = {}, {}
            for ii, row in ipairs(type(cat.items) == 'table' and cat.items or {}) do
                if type(row) == 'table' then
                    local key = cleanKey(row.key)
                    local title = cleanText(row.title, 50)
                    local desc = cleanText(row.desc, 160)
                    local itemTone = cleanText(row.tone, 20):lower()
                    if not VALID_TONES[itemTone] then itemTone = tone end

                    if key ~= '' or title ~= '' or desc ~= '' then
                        if key == '' or title == '' then
                            return nil, ('"%s" 버튼의 %d번째 단축키에 키와 기능명을 모두 입력하세요.'):format(label, ii)
                        end
                        if itemKeys[key] then
                            return nil, ('"%s" 버튼 안에 "%s" 키가 중복되어 있습니다.'):format(label, key)
                        end
                        itemKeys[key] = true
                        totalItems = totalItems + 1
                        if totalItems > 200 then
                            return nil, '전체 키 가이드 항목은 최대 200개까지 등록할 수 있습니다.'
                        end

                        items[#items + 1] = {
                            id = tonumber(row.id),
                            key = key,
                            title = title,
                            desc = desc,
                            tone = itemTone,
                            enabled = row.enabled ~= false,
                            order = #items * 10,
                        }
                    end
                end
            end

            normalized[#normalized + 1] = {
                id = tonumber(cat.id),
                categoryKey = categoryKey,
                label = label,
                icon = cleanText(cat.icon, 16),
                tone = tone,
                visibilityMode = visibilityMode,
                factionIds = factionIds,
                enabled = cat.enabled ~= false,
                order = #normalized * 10,
                items = items,
            }
        end
    end

    if #normalized < 1 then return nil, '최소 1개의 버튼(카테고리)이 필요합니다.' end
    return normalized
end

RegisterNetEvent('cookie_admin:server:saveKeyGuideAdmin', function(data)
    local src = source
    local admin = effectiveAdmin(src)
    if not admin or type(data) ~= 'table' then return end

    local categories, err = normalizeSnapshot(data)
    if not categories then
        return TriggerClientEvent('cookie_admin:client:keyGuideAdminSaved', src, false, err or '저장할 수 없습니다.')
    end

    local ok, saveErr = pcall(function()
        local keepCategoryIds = {}

        for _, cat in ipairs(categories) do
            local categoryId = cat.id

            if categoryId then
                MySQL.update.await([[
                    UPDATE cookie_keyguide_category
                    SET category_key=?, label=?, icon=?, tone=?, visibility_mode=?,
                        sort_order=?, is_active=?
                    WHERE id=?
                ]], {
                    cat.categoryKey, cat.label, cat.icon, cat.tone, cat.visibilityMode,
                    cat.order, cat.enabled and 1 or 0, categoryId
                })
            else
                categoryId = MySQL.insert.await([[
                    INSERT INTO cookie_keyguide_category
                        (category_key, label, icon, tone, visibility_mode, sort_order, is_active)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ]], {
                    cat.categoryKey, cat.label, cat.icon, cat.tone, cat.visibilityMode,
                    cat.order, cat.enabled and 1 or 0
                })
            end

            categoryId = tonumber(categoryId)
            if not categoryId then error(('카테고리 저장 실패: %s'):format(cat.label)) end
            keepCategoryIds[#keepCategoryIds + 1] = categoryId

            MySQL.query.await('DELETE FROM cookie_keyguide_category_faction WHERE category_id = ?', { categoryId })
            if cat.visibilityMode == 'factions' then
                for _, factionId in ipairs(cat.factionIds) do
                    -- 존재하는 활성 팩션만 연결
                    local exists = MySQL.scalar.await(
                        'SELECT id FROM cookie_faction WHERE id = ? AND is_active = 1 LIMIT 1',
                        { factionId }
                    )
                    if exists then
                        MySQL.query.await([[
                            INSERT IGNORE INTO cookie_keyguide_category_faction (category_id, faction_id)
                            VALUES (?, ?)
                        ]], { categoryId, factionId })
                    end
                end
            end

            local keepItemIds = {}
            for _, item in ipairs(cat.items) do
                local itemId = item.id
                if itemId then
                    MySQL.update.await([[
                        UPDATE cookie_keyguide
                        SET category_id=?, key_name=?, label=?, description=?, tone=?,
                            sort_order=?, is_active=?
                        WHERE id=?
                    ]], {
                        categoryId, item.key, item.title, item.desc, item.tone,
                        item.order, item.enabled and 1 or 0, itemId
                    })
                else
                    itemId = MySQL.insert.await([[
                        INSERT INTO cookie_keyguide
                            (category_id, key_name, label, description, tone, sort_order, is_active)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    ]], {
                        categoryId, item.key, item.title, item.desc, item.tone,
                        item.order, item.enabled and 1 or 0
                    })
                end

                itemId = tonumber(itemId)
                if itemId then keepItemIds[#keepItemIds + 1] = itemId end
            end

            if #keepItemIds > 0 then
                local marks = {}
                for _ = 1, #keepItemIds do marks[#marks + 1] = '?' end
                local params = { categoryId }
                for _, id in ipairs(keepItemIds) do params[#params + 1] = id end
                MySQL.query.await(
                    ('DELETE FROM cookie_keyguide WHERE category_id = ? AND id NOT IN (%s)'):format(table.concat(marks, ',')),
                    params
                )
            else
                MySQL.query.await('DELETE FROM cookie_keyguide WHERE category_id = ?', { categoryId })
            end
        end

        if #keepCategoryIds > 0 then
            local marks = {}
            for _ = 1, #keepCategoryIds do marks[#marks + 1] = '?' end
            local deleteIds = MySQL.query.await(
                ('SELECT id FROM cookie_keyguide_category WHERE id NOT IN (%s)'):format(table.concat(marks, ',')),
                keepCategoryIds
            ) or {}

            for _, row in ipairs(deleteIds) do
                local id = tonumber(row.id)
                MySQL.query.await('DELETE FROM cookie_keyguide WHERE category_id = ?', { id })
                MySQL.query.await('DELETE FROM cookie_keyguide_category_faction WHERE category_id = ?', { id })
            end
            MySQL.query.await(
                ('DELETE FROM cookie_keyguide_category WHERE id NOT IN (%s)'):format(table.concat(marks, ',')),
                keepCategoryIds
            )
        end
    end)

    if not ok then
        print(('^1[cookie_admin] KEY GUIDE V3 save error: %s^7'):format(tostring(saveErr)))
        return TriggerClientEvent(
            'cookie_admin:client:keyGuideAdminSaved',
            src, false,
            '저장에 실패했습니다. 버튼 내부키/단축키 중복 여부를 확인하세요.'
        )
    end

    TriggerClientEvent('cookie_admin:client:keyGuideAdminSaved', src, true, '키 가이드 설정을 저장했습니다.')
    TriggerClientEvent('cookie_admin:client:keyGuideAdminData', src, {
        categories = categoryRows(true),
        factions = activeFactionList()
    })
end)
