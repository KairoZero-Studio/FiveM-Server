local function clean(v, maxLen)
    local s = tostring(v or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > (maxLen or 80) then s = s:sub(1, maxLen or 80) end
    return s
end

local function adminAllowed(src)
    local ok, level = pcall(function()
        return exports.cookie_admin:getEffectiveLevel(src)
    end)
    return ok and (tonumber(level) or 0) >= 5
end

local function adminName(src)
    local license = GetPlayerIdentifierByType(src, 'license2') or GetPlayerIdentifierByType(src, 'license')
    if not license then return GetPlayerName(src) or ('#' .. tostring(src)) end
    local row = MySQL.single.await('SELECT admin_name FROM cookie_admin WHERE license=? AND is_active=1 LIMIT 1', { license })
    return row and row.admin_name or GetPlayerName(src) or ('#' .. tostring(src))
end

local function ensureColumn(tableName, columnName, ddl)
    local exists = MySQL.single.await(
        ('SHOW COLUMNS FROM `%s` LIKE ?'):format(tableName),
        { columnName }
    )
    if not exists then
        MySQL.query.await(
            ('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, ddl),
            {}
        )
    end
end

local function ensureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_robbery_location (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            robbery_type VARCHAR(32) NOT NULL DEFAULT 'convenience',
            label VARCHAR(80) NOT NULL,
            x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL,
            heading FLOAT NOT NULL DEFAULT 0,
            interact_distance DECIMAL(6,2) NOT NULL DEFAULT 2.50,
            crew_radius DECIMAL(6,2) NOT NULL DEFAULT 12.00,
            combat_radius DECIMAL(6,2) NOT NULL DEFAULT 45.00,
            fail_radius DECIMAL(6,2) NOT NULL DEFAULT 55.00,
            boundary_mode VARCHAR(16) NOT NULL DEFAULT 'circle',
            boundary_points LONGTEXT NULL,
            threat_seconds INT NOT NULL DEFAULT 8,
            response_wait_seconds INT NOT NULL DEFAULT 90,
            loot_seconds INT NOT NULL DEFAULT 30,
            cooldown_seconds INT NOT NULL DEFAULT 600,
            cash_min BIGINT NOT NULL DEFAULT 2500000,
            cash_max BIGINT NOT NULL DEFAULT 3500000,
            dispatch_text VARCHAR(180) NULL,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT NOT NULL DEFAULT 100,
            updated_by VARCHAR(60) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            KEY idx_cookie_robbery_location_type (robbery_type, enabled)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})

    ensureColumn(
        'cookie_robbery_location',
        'required_loot_amount',
        '`required_loot_amount` INT NOT NULL DEFAULT 0 AFTER `cash_max`'
    )
    ensureColumn(
        'cookie_robbery_location',
        'min_crew',
        '`min_crew` INT NOT NULL DEFAULT 1 AFTER `required_loot_amount`'
    )
    ensureColumn(
        'cookie_robbery_location',
        'boundary_mode',
        "`boundary_mode` VARCHAR(16) NOT NULL DEFAULT 'circle' AFTER `fail_radius`"
    )
    ensureColumn(
        'cookie_robbery_location',
        'boundary_points',
        '`boundary_points` LONGTEXT NULL AFTER `boundary_mode`'
    )

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_robbery_loot_point (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            robbery_id INT UNSIGNED NOT NULL,
            label VARCHAR(80) NOT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            item_name VARCHAR(80) NOT NULL,
            item_label VARCHAR(80) NOT NULL,
            min_amount INT NOT NULL DEFAULT 1,
            max_amount INT NOT NULL DEFAULT 1,
            loot_seconds INT NOT NULL DEFAULT 10,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT NOT NULL DEFAULT 100,
            KEY idx_cookie_robbery_loot_point_location (robbery_id),
            CONSTRAINT fk_cookie_robbery_loot_point_location
                FOREIGN KEY (robbery_id) REFERENCES cookie_robbery_location(id)
                ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_robbery_requirement (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            robbery_id INT UNSIGNED NOT NULL,
            faction_id INT NOT NULL,
            min_duty INT NOT NULL DEFAULT 1,
            sort_order INT NOT NULL DEFAULT 100,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_cookie_robbery_requirement (robbery_id, faction_id),
            KEY idx_cookie_robbery_requirement_location (robbery_id),
            KEY idx_cookie_robbery_requirement_faction (faction_id),
            CONSTRAINT fk_cookie_robbery_requirement_location
                FOREIGN KEY (robbery_id) REFERENCES cookie_robbery_location(id)
                ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_robbery_reward (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            robbery_id INT UNSIGNED NOT NULL,
            item_name VARCHAR(80) NOT NULL,
            label VARCHAR(80) NOT NULL,
            min_amount INT NOT NULL DEFAULT 1,
            max_amount INT NOT NULL DEFAULT 1,
            chance DECIMAL(6,2) NOT NULL DEFAULT 100.00,
            sort_order INT NOT NULL DEFAULT 100,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            KEY idx_cookie_robbery_reward_location (robbery_id),
            CONSTRAINT fk_cookie_robbery_reward_location
                FOREIGN KEY (robbery_id) REFERENCES cookie_robbery_location(id)
                ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})
end

CreateThread(ensureTables)

local function loadData()
    local rows = MySQL.query.await([[
        SELECT *
        FROM cookie_robbery_location
        ORDER BY sort_order, id
    ]], {}) or {}

    local rewards = MySQL.query.await([[
        SELECT *
        FROM cookie_robbery_reward
        ORDER BY robbery_id, sort_order, id
    ]], {}) or {}

    local lootPoints = MySQL.query.await([[
        SELECT *
        FROM cookie_robbery_loot_point
        ORDER BY robbery_id, sort_order, id
    ]], {}) or {}

    local requirements = MySQL.query.await([[
        SELECT rr.robbery_id, rr.faction_id, rr.min_duty, rr.sort_order,
               f.name AS faction_name, f.faction_type
        FROM cookie_robbery_requirement rr
        LEFT JOIN cookie_faction f ON f.id = rr.faction_id
        ORDER BY rr.robbery_id, rr.sort_order, rr.id
    ]], {}) or {}

    local factions = MySQL.query.await([[
        SELECT id, name, faction_type, faction_key
        FROM cookie_faction
        WHERE is_active = 1
        ORDER BY faction_type, name, id
    ]], {}) or {}

    local byId = {}
    local out = {}

    for _, row in ipairs(rows) do
        local v = {
            id = tonumber(row.id),
            type = row.robbery_type or 'convenience',
            label = row.label,
            x = tonumber(row.x) or 0,
            y = tonumber(row.y) or 0,
            z = tonumber(row.z) or 0,
            heading = tonumber(row.heading) or 0,
            interactDistance = tonumber(row.interact_distance) or 2.5,
            crewRadius = tonumber(row.crew_radius) or 12,
            combatRadius = tonumber(row.combat_radius) or 45,
            failRadius = tonumber(row.fail_radius) or 55,
            boundaryMode = tostring(row.boundary_mode or 'circle') == 'polygon' and 'polygon' or 'circle',
            boundaryPoints = (function()
                if type(row.boundary_points) ~= 'string' or row.boundary_points == '' then return {} end
                local ok, decoded = pcall(json.decode, row.boundary_points)
                return ok and type(decoded) == 'table' and decoded or {}
            end)(),
            threatSeconds = tonumber(row.threat_seconds) or 8,
            responseWaitSeconds = tonumber(row.response_wait_seconds) or 90,
            lootSeconds = tonumber(row.loot_seconds) or 30,
            cooldownSeconds = tonumber(row.cooldown_seconds) or 600,
            cashMin = tonumber(row.cash_min) or 0,
            cashMax = tonumber(row.cash_max) or 0,
            requiredLootAmount = tonumber(row.required_loot_amount) or 0,
            minCrew = tonumber(row.min_crew) or 1,
            dispatchText = row.dispatch_text or '',
            enabled = row.enabled == 1 or row.enabled == true,
            sortOrder = tonumber(row.sort_order) or 100,
            rewards = {},
            bankLootPoints = {},
            requirements = {},
        }
        out[#out + 1] = v
        byId[v.id] = v
    end

    for _, row in ipairs(rewards) do
        local parent = byId[tonumber(row.robbery_id)]
        if parent then
            parent.rewards[#parent.rewards + 1] = {
                id = tonumber(row.id),
                item = row.item_name,
                label = row.label,
                min = tonumber(row.min_amount) or 1,
                max = tonumber(row.max_amount) or 1,
                chance = tonumber(row.chance) or 100,
                enabled = row.enabled == 1 or row.enabled == true,
            }
        end
    end

    for _, row in ipairs(lootPoints) do
        local parent = byId[tonumber(row.robbery_id)]
        if parent then
            parent.bankLootPoints[#parent.bankLootPoints + 1] = {
                id = tonumber(row.id),
                label = row.label,
                x = tonumber(row.x) or 0,
                y = tonumber(row.y) or 0,
                z = tonumber(row.z) or 0,
                item = row.item_name,
                itemLabel = row.item_label,
                min = tonumber(row.min_amount) or 1,
                max = tonumber(row.max_amount) or 1,
                lootSeconds = tonumber(row.loot_seconds) or 10,
                enabled = row.enabled == 1 or row.enabled == true,
            }
        end
    end

    for _, row in ipairs(requirements) do
        local parent = byId[tonumber(row.robbery_id)]
        if parent then
            parent.requirements[#parent.requirements + 1] = {
                factionId = tonumber(row.faction_id),
                factionName = row.faction_name or ('팩션 #' .. tostring(row.faction_id)),
                factionType = row.faction_type or '',
                minDuty = math.max(1, math.floor(tonumber(row.min_duty) or 1)),
            }
        end
    end

    local factionOptions = {}
    for _, row in ipairs(factions) do
        factionOptions[#factionOptions + 1] = {
            id = tonumber(row.id),
            name = row.name,
            type = row.faction_type,
            key = row.faction_key,
        }
    end

    return {
        locations = out,
        factions = factionOptions,
        defaults = {
            type = 'convenience',
            label = '소형 RP',
            interactDistance = 2.5,
            crewRadius = 12,
            combatRadius = 45,
            failRadius = 55,
            boundaryMode = 'circle',
            boundaryPoints = {},
            threatSeconds = 8,
            responseWaitSeconds = 90,
            lootSeconds = 30,
            cooldownSeconds = 600,
            cashMin = 2500000,
            cashMax = 3500000,
            requiredLootAmount = 0,
            minCrew = 1,
            dispatchText = '강도 연락 · 통무방으로 이동 후 현장 대응 바랍니다.',
            enabled = true,
        }
    }
end

RegisterNetEvent('cookie_admin:server:requestRobberyAdmin', function()
    local src = source
    if not adminAllowed(src) then return end
    TriggerClientEvent('cookie_admin:client:robberyAdminData', src, loadData())
end)

RegisterNetEvent('cookie_admin:server:saveRobberyLocation', function(data)
    local src = source
    if not adminAllowed(src) or type(data) ~= 'table' then return end

    local id = tonumber(data.id)
    local rtype = clean(data.type or 'convenience', 32):lower()
    local label = clean(data.label, 80)
    local x = tonumber(data.x)
    local y = tonumber(data.y)
    local z = tonumber(data.z)
    local heading = tonumber(data.heading) or 0
    local interact = math.max(1.0, math.min(6.0, tonumber(data.interactDistance) or 2.5))
    local crewRadius = math.max(3.0, math.min(30.0, tonumber(data.crewRadius) or 12.0))
    local combatRadius = math.max(15.0, math.min(120.0, tonumber(data.combatRadius) or 45.0))
    local failRadius = math.max(combatRadius, math.min(160.0, tonumber(data.failRadius) or 55.0))
    local boundaryMode = tostring(data.boundaryMode or 'circle') == 'polygon' and 'polygon' or 'circle'
    local boundaryPoints = {}
    if type(data.boundaryPoints) == 'table' then
        for _,point in ipairs(data.boundaryPoints) do
            if type(point)=='table' then
                local px,py,pz=tonumber(point.x),tonumber(point.y),tonumber(point.z)
                if px and py and pz then
                    boundaryPoints[#boundaryPoints+1]={
                        x=math.floor(px*1000+0.5)/1000,
                        y=math.floor(py*1000+0.5)/1000,
                        z=math.floor(pz*1000+0.5)/1000,
                    }
                end
            end
        end
    end
    if boundaryMode=='polygon' and #boundaryPoints<3 then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved',src,false,'다각형 범위는 꼭짓점을 최소 3개 지정해야 합니다.')
    end
    if #boundaryPoints>32 then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved',src,false,'다각형 범위는 꼭짓점을 최대 32개까지 지정할 수 있습니다.')
    end
    local threat = math.max(1, math.min(60, math.floor(tonumber(data.threatSeconds) or 8)))
    local response = math.max(10, math.min(900, math.floor(tonumber(data.responseWaitSeconds) or 90)))
    local loot = math.max(1, math.min(180, math.floor(tonumber(data.lootSeconds) or 30)))
    local cooldown = math.max(60, math.min(86400, math.floor(tonumber(data.cooldownSeconds) or 600)))
    local cashMin = math.max(0, math.floor(tonumber(data.cashMin) or 0))
    local cashMax = math.max(cashMin, math.floor(tonumber(data.cashMax) or cashMin))
    local requiredLootAmount = math.max(0, math.min(100000, math.floor(tonumber(data.requiredLootAmount) or 0)))
    local minCrew = math.max(1, math.min(20, math.floor(tonumber(data.minCrew) or 1)))
    local dispatchText = clean(data.dispatchText, 180)
    local enabled = data.enabled ~= false and 1 or 0
    local rewards = type(data.rewards) == 'table' and data.rewards or {}
    local bankLootPoints = type(data.bankLootPoints) == 'table' and data.bankLootPoints or {}
    local requirements = type(data.requirements) == 'table' and data.requirements or {}

    if label == '' or not x or not y or not z then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '이름과 좌표를 확인하세요.')
    end

    if #requirements > 12 then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '필수 출근 팩션은 장소당 최대 12개입니다.')
    end

    if #rewards > 20 then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '물품 보상은 장소당 최대 20개입니다.')
    end

    if #bankLootPoints > 30 then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '대형 RP 털이 비콘은 장소당 최대 30개입니다.')
    end

    if rtype == 'bank' then
        if requiredLootAmount < 1 then
            return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '대형 RP는 요구 전리품 수량을 1개 이상 설정하세요.')
        end
        if #bankLootPoints < 1 then
            return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '대형 RP는 털이 비콘을 최소 1개 추가해야 합니다.')
        end
    end

    local normalizedRequirements = {}
    local usedFactions = {}

    for index, row in ipairs(requirements) do
        if type(row) == 'table' then
            local factionId = tonumber(row.factionId)
            local minDuty = math.max(1, math.min(100, math.floor(tonumber(row.minDuty) or 1)))

            if factionId and not usedFactions[factionId] then
                local faction = MySQL.single.await(
                    'SELECT id FROM cookie_faction WHERE id=? AND is_active=1 LIMIT 1',
                    { factionId }
                )

                if faction then
                    usedFactions[factionId] = true
                    normalizedRequirements[#normalizedRequirements + 1] = {
                        factionId = factionId,
                        minDuty = minDuty,
                        order = index * 10,
                    }
                end
            end
        end
    end

    local normalizedRewards = {}
    for index, row in ipairs(rewards) do
        if type(row) == 'table' then
            local item = clean(row.item, 80):lower()
            local rlabel = clean(row.label, 80)
            local mn = math.max(1, math.min(100000, math.floor(tonumber(row.min) or 1)))
            local mx = math.max(mn, math.min(100000, math.floor(tonumber(row.max) or mn)))
            local chance = math.max(0, math.min(100, tonumber(row.chance) or 100))
            if item ~= '' then
                normalizedRewards[#normalizedRewards + 1] = {
                    item = item,
                    label = rlabel ~= '' and rlabel or item,
                    min = mn,
                    max = mx,
                    chance = chance,
                    enabled = row.enabled ~= false,
                    order = index * 10,
                }
            end
        end
    end


    local normalizedBankLootPoints = {}
    for index, row in ipairs(bankLootPoints) do
        if type(row) == 'table' then
            local bx = tonumber(row.x)
            local by = tonumber(row.y)
            local bz = tonumber(row.z)
            local item = clean(row.item, 80):lower()
            local labelPoint = clean(row.label, 80)
            local itemLabel = clean(row.itemLabel, 80)
            local mn = math.max(1, math.min(100000, math.floor(tonumber(row.min) or 1)))
            local mx = math.max(mn, math.min(100000, math.floor(tonumber(row.max) or mn)))
            local seconds = math.max(1, math.min(180, math.floor(tonumber(row.lootSeconds) or 10)))

            if bx and by and bz and item ~= '' then
                normalizedBankLootPoints[#normalizedBankLootPoints + 1] = {
                    label = labelPoint ~= '' and labelPoint or ('전리품 비콘 ' .. tostring(index)),
                    x = bx, y = by, z = bz,
                    item = item,
                    itemLabel = itemLabel ~= '' and itemLabel or item,
                    min = mn,
                    max = mx,
                    lootSeconds = seconds,
                    order = index * 10,
                }
            end
        end
    end

    local who = adminName(src)

    if id then
        MySQL.update.await([[
            UPDATE cookie_robbery_location
            SET robbery_type=?, label=?, x=?, y=?, z=?, heading=?,
                interact_distance=?, crew_radius=?, combat_radius=?, fail_radius=?,
                boundary_mode=?, boundary_points=?,
                threat_seconds=?, response_wait_seconds=?, loot_seconds=?, cooldown_seconds=?,
                cash_min=?, cash_max=?, required_loot_amount=?, min_crew=?,
                dispatch_text=?, enabled=?, updated_by=?
            WHERE id=?
        ]], {
            rtype, label, x, y, z, heading,
            interact, crewRadius, combatRadius, failRadius,
            boundaryMode, json.encode(boundaryPoints),
            threat, response, loot, cooldown,
            cashMin, cashMax, requiredLootAmount, minCrew,
            dispatchText, enabled, who,
            id
        })
    else
        id = MySQL.insert.await([[
            INSERT INTO cookie_robbery_location
                (robbery_type, label, x, y, z, heading,
                 interact_distance, crew_radius, combat_radius, fail_radius,
                 boundary_mode, boundary_points,
                 threat_seconds, response_wait_seconds, loot_seconds, cooldown_seconds,
                 cash_min, cash_max, required_loot_amount, min_crew,
                 dispatch_text, enabled, updated_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            rtype, label, x, y, z, heading,
            interact, crewRadius, combatRadius, failRadius,
            boundaryMode, json.encode(boundaryPoints),
            threat, response, loot, cooldown,
            cashMin, cashMax, requiredLootAmount, minCrew,
            dispatchText, enabled, who
        })
    end

    id = tonumber(id)
    if not id then
        return TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, false, '저장 중 DB 오류가 발생했습니다.')
    end

    MySQL.update.await('DELETE FROM cookie_robbery_requirement WHERE robbery_id=?', { id })

    for _, rule in ipairs(normalizedRequirements) do
        MySQL.insert.await([[
            INSERT INTO cookie_robbery_requirement
                (robbery_id, faction_id, min_duty, sort_order)
            VALUES (?, ?, ?, ?)
        ]], {
            id, rule.factionId, rule.minDuty, rule.order
        })
    end

    MySQL.update.await('DELETE FROM cookie_robbery_reward WHERE robbery_id=?', { id })

    for _, r in ipairs(normalizedRewards) do
        MySQL.insert.await([[
            INSERT INTO cookie_robbery_reward
                (robbery_id, item_name, label, min_amount, max_amount, chance, sort_order, enabled)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            id, r.item, r.label, r.min, r.max, r.chance, r.order, r.enabled and 1 or 0
        })
    end

    MySQL.update.await('DELETE FROM cookie_robbery_loot_point WHERE robbery_id=?', { id })

    if rtype == 'bank' then
        for _, point in ipairs(normalizedBankLootPoints) do
            MySQL.insert.await([[
                INSERT INTO cookie_robbery_loot_point
                    (robbery_id, label, x, y, z, item_name, item_label,
                     min_amount, max_amount, loot_seconds, sort_order, enabled)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
            ]], {
                id,
                point.label,
                point.x, point.y, point.z,
                point.item, point.itemLabel,
                point.min, point.max,
                point.lootSeconds,
                point.order
            })
        end
    end

    TriggerEvent('cookie_robbery:server:reloadConfig')
    TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, true, 'RP 장소 설정을 저장했습니다.')
    TriggerClientEvent('cookie_admin:client:robberyAdminData', src, loadData())
end)

RegisterNetEvent('cookie_admin:server:deleteRobberyLocation', function(id)
    local src = source
    if not adminAllowed(src) then return end
    id = tonumber(id)
    if not id then return end

    MySQL.update.await('DELETE FROM cookie_robbery_location WHERE id=?', { id })
    TriggerEvent('cookie_robbery:server:reloadConfig')
    TriggerClientEvent('cookie_admin:client:robberyAdminSaved', src, true, 'RP 장소를 삭제했습니다.')
    TriggerClientEvent('cookie_admin:client:robberyAdminData', src, loadData())
end)

print('^2[cookie_admin]^7 robbery admin V1.5.1 loaded')
