local Locations = {}
local Active = {}
local Cooldowns = {}


-- HUD와 공유하는 강도 네임태그 숨김 범위.
-- 편의점/빈집 모두 진행 중인 강도 범위 안의 플레이어 머리 위 이름을 숨긴다.
local function refreshNameHideZones()
    local zones = {}

    for id, state in pairs(Active) do
        if state and state.loc and state.phase ~= nil then
            zones[#zones + 1] = {
                id = tonumber(id),
                type = tostring(state.loc.type or 'convenience'),
                x = tonumber(state.loc.x) or 0.0,
                y = tonumber(state.loc.y) or 0.0,
                z = tonumber(state.loc.z) or 0.0,
                radius = math.max(5.0, tonumber(state.loc.combatRadius) or 45.0),
                boundaryMode = tostring(state.loc.boundaryMode or 'circle'),
                boundaryPoints = state.loc.boundaryPoints or {},
            }
        end
    end

    GlobalState.cookieRobberyNameHideZones = zones
end

local function now()
    return os.time()
end

local function notify(src, message, isError, duration)
    TriggerClientEvent('cookie_admin:client:notify', src, message, isError == true, duration or 4500)
end

local function player(src)
    return exports.qbx_core:GetPlayer(tonumber(src))
end

local function citizenId(src)
    local p = player(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function displayName(src)
    local ok, name = pcall(function()
        return exports.cookie_core:getNickname(src)
    end)
    if ok and name and name ~= '' then return name end

    local p = player(src)
    local ci = p and p.PlayerData and p.PlayerData.charinfo
    if ci then
        local full = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
        if full ~= '' then return full end
    end

    return GetPlayerName(src) or ('#' .. tostring(src))
end

local function factionMember(src)
    local ok, data = pcall(function()
        return exports.cookie_admin:getFactionMember(src)
    end)
    return ok and data or nil
end

local function isLaw(src, requireDuty)
    local member = factionMember(src)
    if not member then return false end
    local ftype = tostring(member.type or ''):lower()
    if not Config.LawFactionTypes[ftype] then return false end
    if requireDuty and member.duty ~= true then return false end
    return true
end

local function countLawOnDuty()
    local count = 0

    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src then
            local member = factionMember(src)
            if member and member.duty == true then
                local ftype = tostring(member.type or ''):lower()
                if Config.LawFactionTypes[ftype] then
                    count = count + 1
                end
            end
        end
    end

    return count
end

local function countFactionOnDuty(factionId)
    factionId = tonumber(factionId)
    if not factionId then return 0 end

    local count = 0

    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src then
            local member = factionMember(src)
            if member
                and member.duty == true
                and tonumber(member.id) == factionId
            then
                count = count + 1
            end
        end
    end

    return count
end

local function checkStartRequirements(loc)
    local rules = type(loc.requirements) == 'table' and loc.requirements or {}

    -- 장소에 직접 설정한 조건이 있으면 각 팩션이 자기 최소 인원을 모두 충족해야 함.
    if #rules > 0 then
        for _, rule in ipairs(rules) do
            local required = math.max(1, math.floor(tonumber(rule.minDuty) or 1))
            local current = countFactionOnDuty(rule.factionId)

            if current < required then
                return false, {
                    name = tostring(rule.factionName or ('팩션 #' .. tostring(rule.factionId))),
                    required = required,
                    current = current,
                }
            end
        end

        return true
    end

    -- 아직 장소별 조건이 없는 기존 데이터 보호용.
    local fallback = math.max(0, math.floor(tonumber(Config.FallbackLawOnDuty) or 0))
    if fallback <= 0 then return true end

    local current = countLawOnDuty()
    if current < fallback then
        return false, {
            name = '경찰/보안국',
            required = fallback,
            current = current,
        }
    end

    return true
end

local function ped(src)
    local p = GetPlayerPed(tonumber(src))
    if not p or p == 0 then return nil end
    return p
end

local function coordsOf(src)
    local p = ped(src)
    if not p then return nil end
    return GetEntityCoords(p)
end

local function isAlive(src)
    local p = ped(src)
    if not p then return false end
    return GetEntityHealth(p) > 0
end

local function distanceToLocation(src, loc)
    local c = coordsOf(src)
    if not c then return 99999.0 end
    return #(c - vec3(loc.x, loc.y, loc.z))
end

local function decodeBoundaryPoints(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    local points = {}
    for _, point in ipairs(decoded) do
        if type(point) == 'table' then
            local x,y,z = tonumber(point.x),tonumber(point.y),tonumber(point.z)
            if x and y and z then points[#points+1]={x=x,y=y,z=z} end
        end
    end
    return points
end

local function normalizeLocation(row)
    return {
        id = tonumber(row.id),
        type = tostring(row.robbery_type or 'convenience'),
        label = tostring(row.label or '편의점'),
        x = tonumber(row.x) or 0.0,
        y = tonumber(row.y) or 0.0,
        z = tonumber(row.z) or 0.0,
        heading = tonumber(row.heading) or 0.0,
        interactDistance = tonumber(row.interact_distance) or 2.5,
        crewRadius = tonumber(row.crew_radius) or Config.DefaultCrewRadius,
        combatRadius = tonumber(row.combat_radius) or 45.0,
        failRadius = tonumber(row.fail_radius) or 55.0,
        boundaryMode = tostring(row.boundary_mode or 'circle') == 'polygon' and 'polygon' or 'circle',
        boundaryPoints = decodeBoundaryPoints(row.boundary_points),
        threatSeconds = math.max(1, tonumber(row.threat_seconds) or 8),
        responseWaitSeconds = math.max(10, tonumber(row.response_wait_seconds) or 90),
        lootSeconds = math.max(1, tonumber(row.loot_seconds) or 30),
        cooldownSeconds = math.max(10, tonumber(row.cooldown_seconds) or 600),
        cashMin = math.max(0, math.floor(tonumber(row.cash_min) or 0)),
        cashMax = math.max(0, math.floor(tonumber(row.cash_max) or 0)),
        requiredLootAmount = math.max(0, math.floor(tonumber(row.required_loot_amount) or 0)),
        minCrew = math.max(1, math.floor(tonumber(row.min_crew) or 1)),
        dispatchText = tostring(row.dispatch_text or ''),
        enabled = row.enabled == 1 or row.enabled == true,
        sortOrder = tonumber(row.sort_order) or 100,
        rewards = {},
        lootPoints = {},
        requirements = {},
    }
end

local function publicLocations()
    local out = {}
    for _, loc in pairs(Locations) do
        if loc.enabled then
            out[#out + 1] = {
                id = loc.id,
                type = loc.type,
                label = loc.label,
                x = loc.x, y = loc.y, z = loc.z,
                interactDistance = loc.interactDistance,
                combatRadius = loc.combatRadius,
                boundaryMode = loc.boundaryMode,
                boundaryPoints = loc.boundaryPoints,
            }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function reloadLocations()
    local rows = MySQL.query.await([[
        SELECT *
        FROM cookie_robbery_location
        ORDER BY sort_order, id
    ]], {}) or {}

    local rewardRows = MySQL.query.await([[
        SELECT *
        FROM cookie_robbery_reward
        WHERE enabled = 1
        ORDER BY robbery_id, sort_order, id
    ]], {}) or {}

    local lootPointRows = MySQL.query.await([[
        SELECT *
        FROM cookie_robbery_loot_point
        WHERE enabled = 1
        ORDER BY robbery_id, sort_order, id
    ]], {}) or {}

    local requirementRows = MySQL.query.await([[
        SELECT rr.robbery_id, rr.faction_id, rr.min_duty, rr.sort_order,
               f.name AS faction_name, f.faction_type
        FROM cookie_robbery_requirement rr
        LEFT JOIN cookie_faction f ON f.id = rr.faction_id
        ORDER BY rr.robbery_id, rr.sort_order, rr.id
    ]], {}) or {}

    local nextLocations = {}
    for _, row in ipairs(rows) do
        local loc = normalizeLocation(row)
        nextLocations[loc.id] = loc
    end

    for _, row in ipairs(rewardRows) do
        local rid = tonumber(row.robbery_id)
        if nextLocations[rid] then
            nextLocations[rid].rewards[#nextLocations[rid].rewards + 1] = {
                id = tonumber(row.id),
                item = tostring(row.item_name or ''):lower(),
                label = tostring(row.label or row.item_name or ''),
                min = math.max(1, math.floor(tonumber(row.min_amount) or 1)),
                max = math.max(1, math.floor(tonumber(row.max_amount) or 1)),
                chance = math.max(0.0, math.min(100.0, tonumber(row.chance) or 100.0)),
            }
        end
    end

    for _, row in ipairs(lootPointRows) do
        local rid = tonumber(row.robbery_id)
        if nextLocations[rid] then
            nextLocations[rid].lootPoints[#nextLocations[rid].lootPoints + 1] = {
                id = tonumber(row.id),
                label = tostring(row.label or '대형 RP 전리품'),
                x = tonumber(row.x) or 0.0,
                y = tonumber(row.y) or 0.0,
                z = tonumber(row.z) or 0.0,
                item = tostring(row.item_name or ''):lower(),
                itemLabel = tostring(row.item_label or row.item_name or ''),
                min = math.max(1, math.floor(tonumber(row.min_amount) or 1)),
                max = math.max(1, math.floor(tonumber(row.max_amount) or 1)),
                lootSeconds = math.max(1, math.floor(tonumber(row.loot_seconds) or 10)),
            }
        end
    end

    for _, row in ipairs(requirementRows) do
        local rid = tonumber(row.robbery_id)
        if nextLocations[rid] then
            nextLocations[rid].requirements[#nextLocations[rid].requirements + 1] = {
                factionId = tonumber(row.faction_id),
                factionName = tostring(row.faction_name or ('팩션 #' .. tostring(row.faction_id))),
                factionType = tostring(row.faction_type or ''),
                minDuty = math.max(1, math.floor(tonumber(row.min_duty) or 1)),
            }
        end
    end

    Locations = nextLocations
    TriggerClientEvent('cookie_robbery:client:setLocations', -1, publicLocations())

    local count = 0
    for _ in pairs(Locations) do count = count + 1 end
    print(('^2[cookie_robbery]^7 locations reloaded: %d'):format(count))
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
        print(('^2[cookie_robbery]^7 migration added %s.%s'):format(tableName, columnName))
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

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_robbery_log (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            robbery_id INT UNSIGNED NULL,
            robbery_label VARCHAR(80) NOT NULL,
            starter_citizenid VARCHAR(64) NULL,
            starter_name VARCHAR(80) NULL,
            status VARCHAR(24) NOT NULL,
            cash_reward BIGINT NOT NULL DEFAULT 0,
            item_reward_json LONGTEXT NULL,
            detail VARCHAR(255) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            KEY idx_cookie_robbery_log_location (robbery_id, created_at),
            KEY idx_cookie_robbery_log_citizen (starter_citizenid, created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})
end

CreateThread(function()
    print('^2[cookie_robbery]^7 V1.5.2 server starting')
    ensureTables()
    reloadLocations()
    refreshNameHideZones()
    print('^2[cookie_robbery]^7 V1.5.2 server ready')
end)

AddEventHandler('cookie_robbery:server:reloadConfig', function()
    reloadLocations()
end)

RegisterNetEvent('cookie_robbery:server:requestLocations', function()
    TriggerClientEvent('cookie_robbery:client:setLocations', source, publicLocations())
end)

local function logRobbery(state, status, cash, items, detail)
    local leader = state.starter
    MySQL.insert.await([[
        INSERT INTO cookie_robbery_log
            (robbery_id, robbery_label, starter_citizenid, starter_name,
             status, cash_reward, item_reward_json, detail)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        state.id,
        state.loc.label,
        state.starterCitizenId,
        state.starterName,
        status,
        math.floor(tonumber(cash) or 0),
        json.encode(items or {}),
        detail,
    })
end

local function sendCrew(state, eventName, ...)
    for src in pairs(state.crew) do
        if GetPlayerPing(src) > 0 then
            TriggerClientEvent(eventName, src, ...)
        end
    end
end

local function sendDispatch(state)
    local loc = state.loc
    local text = loc.dispatchText
    if text == '' then
        if loc.type == 'emptyhouse' then
            text = ('%s 빈집 침입 연락 · 통무방으로 이동 후 현장 대응 바랍니다.'):format(loc.label)
        elseif loc.type == 'bank' then
            text = ('%s 은행 대형 강도 연락 · 통무방으로 이동 후 현장 대응 바랍니다.'):format(loc.label)
        else
            text = ('%s 편의점 강도 연락 · 통무방으로 이동 후 현장 대응 바랍니다.'):format(loc.label)
        end
    end

    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src and isLaw(src, true) then
            TriggerClientEvent('cookie_robbery:client:dispatch', src, {
                robberyId = state.id,
                label = loc.label,
                text = text,
                coords = { x = loc.x, y = loc.y, z = loc.z },
                seconds = Config.DispatchBlipSeconds,
            })
        end
    end
end

local function armedServer(src)
    local p = ped(src)
    if not p then return false end
    local weapon = GetSelectedPedWeapon(p)
    return weapon and weapon ~= 0 and weapon ~= `WEAPON_UNARMED`
end


local AllowedMeleeHashes = {}

CreateThread(function()
    for _, weaponName in ipairs((Config.EmptyHouse and Config.EmptyHouse.allowedMeleeWeapons) or {}) do
        AllowedMeleeHashes[joaat(weaponName)] = true
    end
end)

local function selectedWeapon(src)
    local p = ped(src)
    if not p then return `WEAPON_UNARMED` end
    return GetSelectedPedWeapon(p)
end

local function isMeleeWeaponServer(src)
    local weapon = selectedWeapon(src)
    if not weapon or weapon == 0 or weapon == `WEAPON_UNARMED` then
        return false
    end
    return AllowedMeleeHashes[weapon] == true
end

local function isFirearmWeaponServer(src)
    local weapon = selectedWeapon(src)
    if not weapon or weapon == 0 or weapon == `WEAPON_UNARMED` then
        return false
    end

    -- 허용 근접무기가 아닌 무장을 총기/기타 무기로 취급.
    -- 빈집에서는 시작을 막는다.
    return AllowedMeleeHashes[weapon] ~= true
end

local function collectCrew(starter, loc)
    local crew = {}
    local origin = coordsOf(starter)
    if not origin then return crew end

    crew[starter] = true

    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src and src ~= starter and not isLaw(src, false) and isAlive(src) and armedServer(src) then
            local c = coordsOf(src)
            if c and #(c - origin) <= loc.crewRadius then
                crew[src] = true
            end
        end
    end

    return crew
end

local function cooldownLeft(id)
    local untilAt = Cooldowns[id] or 0
    return math.max(0, untilAt - now())
end

RegisterNetEvent('cookie_robbery:server:beginThreat', function(id)
    local src = source
    id = tonumber(id)
    local loc = id and Locations[id] or nil
    if not loc or not loc.enabled then
        return notify(src, '이 강도 장소는 사용할 수 없습니다.', true)
    end

    if isLaw(src, false) then
        return notify(src, '경찰/보안국 소속은 강도를 시작할 수 없습니다.', true)
    end

    if Active[id] then
        return notify(src, '이미 진행 중인 강도입니다.', true)
    end

    local cd = cooldownLeft(id)
    if cd > 0 then
        return notify(src, ('이 RP 장소는 아직 정리 중입니다. %d분 %d초 후 가능'):format(
            math.floor(cd / 60), cd % 60
        ), true)
    end

    if not isAlive(src) or distanceToLocation(src, loc) > (loc.interactDistance + 1.5) then
        return notify(src, '강도 시작 위치에서 너무 멉니다.', true)
    end

    -- 장소별 필수 출근 팩션 조건.
    local allowed, missing = checkStartRequirements(loc)
    if not allowed then
        if (missing.current or 0) <= 0 then
            return notify(
                src,
                ('현재 %s 출근 인원이 없어 RP를 시작할 수 없습니다. 필요 %d명'):format(
                    missing.name,
                    missing.required
                ),
                true,
                6000
            )
        end

        return notify(
            src,
            ('%s 출근 인원이 부족합니다. 필요 %d명 / 현재 %d명'):format(
                missing.name,
                missing.required,
                missing.current
            ),
            true,
            6000
        )
    end

    if loc.type == 'emptyhouse' then
        if Config.EmptyHouse and Config.EmptyHouse.blockFirearms and isFirearmWeaponServer(src) then
            return notify(src, '빈집 강도는 총기를 사용할 수 없습니다. 근접무기만 사용하세요.', true)
        end
        if Config.EmptyHouse and Config.EmptyHouse.requireMelee and not isMeleeWeaponServer(src) then
            return notify(src, '빈집 강도는 근접무기를 든 상태에서 시작해야 합니다.', true)
        end
    elseif loc.type == 'bank' then
        if (not Config.Bank or Config.Bank.requireFirearm ~= false) and not armedServer(src) then
            return notify(src, '대형 RP는 총기를 꺼낸 상태에서 시작해야 합니다.', true)
        end
    elseif Config.RequireFirearm and not armedServer(src) then
        return notify(src, '소형 RP는 총기를 꺼낸 상태에서 시작해야 합니다.', true)
    end

    local initialCrew = collectCrew(src, loc)
    local crewCount = 0
    for _ in pairs(initialCrew) do crewCount = crewCount + 1 end

    if loc.type == 'bank' and crewCount < (loc.minCrew or 1) then
        return notify(
            src,
            ('대형 RP는 최소 %d명의 무장 강도팀이 필요합니다. 현재 %d명'):format(
                loc.minCrew or 1,
                crewCount
            ),
            true
        )
    end

    if loc.type == 'bank' and (#(loc.lootPoints or {}) == 0 or (loc.requiredLootAmount or 0) <= 0) then
        return notify(src, '대형 RP 설정에 전리품 비콘/요구 수량이 없습니다. 관리자에게 문의하세요.', true)
    end

    local crewCitizens={}
    for crewSrc in pairs(initialCrew) do
        local cid=citizenId(crewSrc)
        if cid then
            crewCitizens[#crewCitizens+1]={
                citizenid=cid,
                name=displayName(crewSrc)
            }
        end
    end

    local state = {
        id = id,
        loc = loc,
        starter = src,
        starterCitizenId = citizenId(src),
        starterName = displayName(src),
        crew = initialCrew,
        crewCitizens = crewCitizens,
        crimeRecorded = false,
        phase = 'threat',
        startedAt = now(),
        threatEndsAt = now() + (
            loc.type == 'emptyhouse'
                and ((Config.EmptyHouse and Config.EmptyHouse.breakInSeconds) or loc.threatSeconds)
                or loc.threatSeconds
        ),
        engaged = false,
        clearSince = nil,
        awaySince = {},
        lootBusy = false,
        looter = nil,
        bankLootedPoints = {},
        bankLootBusy = false,
        bankLooter = nil,
        bankLootTotal = 0,
        bankEscrowByPlayer = {},
    }

    Active[id] = state
    refreshNameHideZones()

    -- 장소 쿨타임만 사용. 개인 쿨타임은 없음.
    Cooldowns[id] = now() + loc.cooldownSeconds

    sendCrew(state, 'cookie_robbery:client:crewStarted', {
        id = id,
        label = loc.label,
        type = loc.type,
        phase = 'threat',
        starter = src,
        threatSeconds = loc.type == 'emptyhouse'
            and ((Config.EmptyHouse and Config.EmptyHouse.breakInSeconds) or loc.threatSeconds)
            or loc.threatSeconds,
        coords = { x = loc.x, y = loc.y, z = loc.z },
        combatRadius = loc.combatRadius,
        boundaryMode = loc.boundaryMode,
        boundaryPoints = loc.boundaryPoints,
        requiredLootAmount = loc.requiredLootAmount,
        bankLootPoints = loc.type == 'bank' and loc.lootPoints or nil,
    })

    sendDispatch(state)

    -- 진행 중 RP는 모든 타입에서 범위를 더 진하게 표시.
    TriggerClientEvent('cookie_robbery:client:boundaryStart', -1, {
        robberyId = id,
        type = loc.type,
        x = loc.x, y = loc.y, z = loc.z,
        radius = loc.combatRadius,
        boundaryMode = loc.boundaryMode,
        boundaryPoints = loc.boundaryPoints,
        label = loc.label,
    })

    if loc.type == 'emptyhouse' then
        notify(src, ('%s 빈집 침입을 시작했습니다. 근접무기로 진입 지점을 파손하세요.'):format(loc.label), false)
    elseif loc.type == 'bank' then
        notify(src, ('%s 대형 RP를 시작했습니다. 보안 진입 절차를 진행하세요.'):format(loc.label), false)
    else
        notify(src, ('%s 강도를 시작했습니다. 점원을 위협하세요.'):format(loc.label), false)
    end
    logRobbery(state, 'started', 0, {}, ('crew=%d'):format((function()
        local n=0 for _ in pairs(state.crew) do n=n+1 end return n
    end)()))
end)

RegisterNetEvent('cookie_robbery:server:threatFinished', function(id)
    local src = source
    id = tonumber(id)
    local state = id and Active[id] or nil
    if not state or state.phase ~= 'threat' or not state.crew[src] then return end

    if now() + 1 < state.threatEndsAt then
        return notify(src, '위협 시간이 아직 끝나지 않았습니다.', true)
    end

    if not isAlive(src) or distanceToLocation(src, state.loc) > state.loc.failRadius then
        return
    end

    if state.loc.type == 'bank' then
        state.phase = 'bank_loot'
        state.bankLootTotal = 0
        state.bankLootedPoints = {}
        state.bankLootBusy = false
        state.bankLooter = nil

        sendCrew(state, 'cookie_robbery:client:phase', {
            id = id,
            type = 'bank',
            phase = 'bank_loot',
            label = state.loc.label,
            requiredLootAmount = state.loc.requiredLootAmount,
            bankLootTotal = 0,
            bankLootPoints = state.loc.lootPoints,
        })

        sendCrew(
            state,
            'cookie_robbery:client:status',
            ('대형 RP 전리품을 먼저 확보하세요. 목표 수량: %d개'):format(state.loc.requiredLootAmount or 0),
            false
        )
        return
    end

    state.phase = 'combat'
    state.combatStartedAt = now()
    state.responseDeadline = now() + state.loc.responseWaitSeconds

    sendCrew(state, 'cookie_robbery:client:phase', {
        id = id,
        phase = 'combat',
        label = state.loc.label,
        responseWaitSeconds = state.loc.responseWaitSeconds,
    })

    sendCrew(state, 'cookie_robbery:client:status',
        '전멸전 시작 · 교전 종료 후 경찰이 현장 비콘에서 결과를 기록합니다.', false)
end)

local function aliveCrew(state)
    local alive = {}
    for src in pairs(state.crew) do
        if GetPlayerPing(src) > 0 and isAlive(src) and distanceToLocation(src, state.loc) <= state.loc.failRadius then
            alive[#alive + 1] = src
            state.awaySince[src] = nil
        else
            if GetPlayerPing(src) > 0 and isAlive(src) then
                state.awaySince[src] = state.awaySince[src] or now()
                if now() - state.awaySince[src] <= Config.LeaveGraceSeconds then
                    alive[#alive + 1] = src
                end
            end
        end
    end
    return alive
end


local function endPublicBoundary(state)
    if state and state.loc then
        TriggerClientEvent('cookie_robbery:client:boundaryEnd', -1, state.id)
    end
end

local function recordRobberyLossCrime(state,reason)
    if not state or state.crimeRecorded then return end
    state.crimeRecorded=true

    if GetResourceState('cookie_crime')~='started' then return end

    local def=nil
    pcall(function()
        def=exports.cookie_crime:GetRobberyLossDefinition(state.loc and state.loc.type)
    end)
    if not def then return end

    for _,who in ipairs(state.crewCitizens or {}) do
        if who.citizenid then
            local ok,recordOk,err=pcall(function()
                return exports.cookie_crime:AddRecord({
                    citizenid=who.citizenid,
                    nickname=who.name,
                    charges={{
                        id='robbery_loss_'..tostring(state.loc and state.loc.type or 'unknown'),
                        category='강도 RP',
                        label=def.label,
                        score=tonumber(def.score) or 0
                    }},
                    crimeScore=tonumber(def.score) or 0,
                    fine=0,
                    jailMinutes=0,
                    licenseMinutes=0,
                    sourceType='robbery_loss',
                    sourceLabel=(state.loc and state.loc.label) or '강도 RP',
                    agencyType='system',
                    agencyName='강도 RP',
                    officerName='SYSTEM'
                })
            end)
            if not ok or recordOk~=true then
                print(('[cookie_robbery] 강도 패배 전과 저장 실패 cid=%s · %s'):format(
                    tostring(who.citizenid),tostring(ok and err or recordOk)
                ))
            end
        end
    end
end

local function failRobbery(state, reason)
    if not state or not Active[state.id] then return end
    recordRobberyLossCrime(state,reason)
    Active[state.id] = nil
    refreshNameHideZones()
    endPublicBoundary(state)
    sendCrew(state, 'cookie_robbery:client:ended', {
        id = state.id,
        success = false,
        message = reason or '강도에 실패했습니다.',
    })

    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        if src and isLaw(src, true) then
            TriggerClientEvent('cookie_robbery:client:dispatchEnd', src, state.id)
        end
    end

    logRobbery(state, 'failed', 0, {}, reason)
end

local function unlockLoot(state, message)
    if not state or state.phase ~= 'combat' then return end
    state.phase = 'loot'
    state.lootBusy = false
    state.looter = nil
    sendCrew(state, 'cookie_robbery:client:phase', {
        id = state.id,
        phase = 'loot',
        label = state.loc.label,
        lootSeconds = state.loc.lootSeconds,
    })
    sendCrew(state, 'cookie_robbery:client:status',
        message or '현장이 정리되었습니다. E를 눌러 금고와 계산대를 터세요.', false)
end

CreateThread(function()
    while true do
        Wait(1000)

        for id, state in pairs(Active) do
            if state.phase == 'threat' then
                if #aliveCrew(state) < 1 then
                    failRobbery(state, '강도팀이 전멸하거나 현장을 이탈해 강도가 실패했습니다.')
                end

            elseif state.phase == 'bank_loot' then
                if #aliveCrew(state) < 1 then
                    failRobbery(state, '대형 RP팀 전멸 · 요구 전리품을 확보하지 못했습니다.')
                end

            elseif state.phase == 'combat' then
                local crew = aliveCrew(state)
                if #crew < 1 then
                    failRobbery(state, '강도팀 전멸 · 강도가 실패했습니다.')
                elseif now() >= state.responseDeadline then
                    -- RP가 끝났는데 경찰이 결과를 입력하지 않는 경우를 위한 교착 방지 장치.
                    if state.loc.type == 'bank' then
                        -- 은행은 전리품 조건을 이미 달성한 상태에서 combat으로 넘어오므로
                        -- 결과 미입력 시 강도팀 승리로 최종 처리한다.
                        TriggerEvent('cookie_robbery:server:finishBankByTimeout', state.id)
                    else
                        unlockLoot(state, '경찰 측 결과가 입력되지 않아 금고가 자동 해제되었습니다.')
                    end
                end

            elseif state.phase == 'loot' then
                if #aliveCrew(state) < 1 then
                    failRobbery(state, '강도팀 전멸 · 금고를 확보하지 못했습니다.')
                end
            end
        end
    end
end)



local function bankPointById(state, pointId)
    pointId = tonumber(pointId)
    if not state or not state.loc then return nil end
    for _, point in ipairs(state.loc.lootPoints or {}) do
        if tonumber(point.id) == pointId then return point end
    end
    return nil
end

local function addBankEscrow(state, src, point, amount)
    state.bankEscrowByPlayer[src] = state.bankEscrowByPlayer[src] or {}
    local bucket = state.bankEscrowByPlayer[src]
    local key = point.item

    bucket[key] = bucket[key] or {
        item = point.item,
        label = point.itemLabel or point.item,
        amount = 0,
    }
    bucket[key].amount = bucket[key].amount + amount
end

local function aggregateBankEscrow(state)
    local aggregate = {}
    for _, bucket in pairs(state.bankEscrowByPlayer or {}) do
        for item, row in pairs(bucket) do
            aggregate[item] = aggregate[item] or {
                item = item,
                label = row.label or item,
                amount = 0,
            }
            aggregate[item].amount = aggregate[item].amount + (tonumber(row.amount) or 0)
        end
    end

    local out = {}
    for _, row in pairs(aggregate) do out[#out + 1] = row end
    table.sort(out, function(a, b) return tostring(a.item) < tostring(b.item) end)
    return out
end

local function bankPayoutRecipients(state)
    local out = {}
    for src in pairs(state.crew or {}) do
        if GetPlayerPing(src) > 0 and player(src) then
            out[#out + 1] = src
        end
    end
    if #out == 0 and state.starter and GetPlayerPing(state.starter) > 0 then
        out[1] = state.starter
    end
    return out
end

local function giveBankEscrow(state)
    local delivered = {}

    for originalSrc, bucket in pairs(state.bankEscrowByPlayer or {}) do
        local target = (GetPlayerPing(originalSrc) > 0 and player(originalSrc)) and originalSrc or state.starter

        if target and GetPlayerPing(target) > 0 then
            for _, row in pairs(bucket) do
                local amount = math.max(0, math.floor(tonumber(row.amount) or 0))
                if amount > 0 then
                    local canCarry = true
                    local okCarry, result = pcall(function()
                        return exports.ox_inventory:CanCarryItem(target, row.item, amount)
                    end)
                    if okCarry then canCarry = result == true end

                    if canCarry then
                        local added = false
                        pcall(function()
                            added = exports.ox_inventory:AddItem(target, row.item, amount) == true
                        end)
                        if added then
                            delivered[#delivered + 1] = {
                                item = row.item,
                                label = row.label,
                                amount = amount,
                                receiver = displayName(target),
                            }
                        else
                            notify(target, ('대형 RP 전리품 %s x%d 지급에 실패했습니다. 관리자에게 문의하세요.'):format(
                                row.label or row.item,
                                amount
                            ), true)
                        end
                    else
                        notify(target, ('인벤토리 공간 부족 · %s x%d를 받을 수 없습니다.'):format(
                            row.label or row.item,
                            amount
                        ), true)
                    end
                end
            end
        end
    end

    return delivered
end

local function giveBankCash(state)
    local minCash = math.min(state.loc.cashMin or 0, state.loc.cashMax or 0)
    local maxCash = math.max(state.loc.cashMin or 0, state.loc.cashMax or 0)
    local total = maxCash > 0 and math.random(minCash, maxCash) or 0
    if total <= 0 then return 0 end

    local recipients = bankPayoutRecipients(state)
    if #recipients == 0 then return 0 end

    local each = math.floor(total / #recipients)
    local remain = total - (each * #recipients)

    for index, src in ipairs(recipients) do
        local amount = each + (index == 1 and remain or 0)
        local p = player(src)
        if p and amount > 0 then
            p.Functions.AddMoney('cash', amount, '은행 강도 최종 성공 보상')
            notify(src, ('은행 강도 현금 분배: %s원'):format(amount), false)
        end
    end

    return total
end

local function finishBankSuccess(state, reason)
    if not state or not Active[state.id] or state.loc.type ~= 'bank' then return end
    if (state.bankLootTotal or 0) < (state.loc.requiredLootAmount or 0) then return end

    endPublicBoundary(state)

    local delivered = giveBankEscrow(state)
    local cash = giveBankCash(state)

    Active[state.id] = nil
    refreshNameHideZones()

    local summary = aggregateBankEscrow(state)
    local parts = {}
    for _, row in ipairs(summary) do
        parts[#parts + 1] = ('%s x%d'):format(row.label or row.item, row.amount or 0)
    end

    local message = ('은행 강도 성공 · 확보 전리품 %d/%d'):format(
        state.bankLootTotal or 0,
        state.loc.requiredLootAmount or 0
    )
    if cash > 0 then message = message .. (' · 현금 %s원'):format(cash) end
    if #parts > 0 then message = message .. ' · ' .. table.concat(parts, ', ') end

    sendCrew(state, 'cookie_robbery:client:ended', {
        id = state.id,
        success = true,
        message = message,
    })

    for _, raw in ipairs(GetPlayers()) do
        local law = tonumber(raw)
        if law and isLaw(law, true) then
            TriggerClientEvent('cookie_robbery:client:dispatchEnd', law, state.id)
        end
    end

    logRobbery(
        state,
        'success',
        cash,
        delivered,
        reason or 'bank final elimination victory'
    )
end

RegisterNetEvent('cookie_robbery:server:beginBankLootPoint', function(id, pointId)
    local src = source
    id = tonumber(id)
    local state = id and Active[id] or nil

    if not state or state.loc.type ~= 'bank' or state.phase ~= 'bank_loot' or not state.crew[src] then
        return
    end

    if state.bankLootBusy then
        return notify(src, '다른 강도팀원이 이미 대형 RP 전리품을 확보 중입니다.', true)
    end

    local point = bankPointById(state, pointId)
    if not point then
        return notify(src, '대형 RP 전리품 비콘을 찾을 수 없습니다.', true)
    end

    if state.bankLootedPoints[point.id] then
        return notify(src, '이미 턴 전리품 위치입니다.', true)
    end

    if not isAlive(src) then return end

    local c = coordsOf(src)
    local pc = vec3(point.x, point.y, point.z)
    if not c or #(c - pc) > 3.0 then
        return notify(src, '전리품 비콘 가까이에서 시도하세요.', true)
    end

    state.bankLootBusy = true
    state.bankLooter = src
    state.bankLootPoint = point.id
    state.bankLootEndsAt = now() + point.lootSeconds

    sendCrew(state, 'cookie_robbery:client:bankLootStarted', {
        id = id,
        pointId = point.id,
        looter = src,
        looterName = displayName(src),
        label = point.label,
        itemLabel = point.itemLabel,
        seconds = point.lootSeconds,
    })
end)

RegisterNetEvent('cookie_robbery:server:cancelBankLootPoint', function(id)
    local src = source
    local state = Active[tonumber(id)]
    if not state or state.loc.type ~= 'bank' or state.bankLooter ~= src then return end
    state.bankLootBusy = false
    state.bankLooter = nil
    state.bankLootPoint = nil
    state.bankLootEndsAt = nil
    sendCrew(state, 'cookie_robbery:client:status', '대형 RP 전리품 회수가 중단되었습니다.', true)
end)

RegisterNetEvent('cookie_robbery:server:finishBankLootPoint', function(id, pointId)
    local src = source
    local state = Active[tonumber(id)]

    if not state or state.loc.type ~= 'bank' or state.phase ~= 'bank_loot' then return end
    if state.bankLooter ~= src or not state.bankLootBusy then return end
    if tonumber(state.bankLootPoint) ~= tonumber(pointId) then return end
    if now() + 1 < (state.bankLootEndsAt or 0) then return end

    local point = bankPointById(state, pointId)
    if not point or state.bankLootedPoints[point.id] then
        state.bankLootBusy = false
        state.bankLooter = nil
        return
    end

    local c = coordsOf(src)
    if not c or #(c - vec3(point.x, point.y, point.z)) > 3.5 or not isAlive(src) then
        state.bankLootBusy = false
        state.bankLooter = nil
        state.bankLootPoint = nil
        return notify(src, '전리품 위치에서 벗어나 회수가 취소되었습니다.', true)
    end

    local mn = math.min(point.min, point.max)
    local mx = math.max(point.min, point.max)
    local amount = math.random(mn, mx)

    state.bankLootedPoints[point.id] = true
    state.bankLootTotal = (state.bankLootTotal or 0) + amount
    addBankEscrow(state, src, point, amount)

    state.bankLootBusy = false
    state.bankLooter = nil
    state.bankLootPoint = nil
    state.bankLootEndsAt = nil

    sendCrew(state, 'cookie_robbery:client:bankLootProgress', {
        id = state.id,
        pointId = point.id,
        amount = amount,
        itemLabel = point.itemLabel,
        total = state.bankLootTotal,
        required = state.loc.requiredLootAmount,
    })

    if state.bankLootTotal >= state.loc.requiredLootAmount then
        state.phase = 'combat'
        state.combatStartedAt = now()
        state.responseDeadline = now() + state.loc.responseWaitSeconds

        sendCrew(state, 'cookie_robbery:client:phase', {
            id = state.id,
            type = 'bank',
            phase = 'combat',
            label = state.loc.label,
            bankLootTotal = state.bankLootTotal,
            requiredLootAmount = state.loc.requiredLootAmount,
            responseWaitSeconds = state.loc.responseWaitSeconds,
        })

        sendCrew(
            state,
            'cookie_robbery:client:status',
            ('필요 전리품 %d개 확보 완료 · 이제 최종 전멸전에서 승리해야 합니다.'):format(
                state.bankLootTotal
            ),
            false
        )
    end
end)

AddEventHandler('cookie_robbery:server:finishBankByTimeout', function(id)
    local state = Active[tonumber(id)]
    if not state or state.loc.type ~= 'bank' or state.phase ~= 'combat' then return end
    finishBankSuccess(state, 'bank result timeout auto victory')
end)

RegisterNetEvent('cookie_robbery:server:policeResult', function(id, result)
    local src = source
    id = tonumber(id)
    result = tostring(result or '')
    local state = id and Active[id] or nil

    if not state then
        return notify(src, '이미 종료된 강도입니다.', true)
    end

    local bankEarlyPhase = state.loc.type == 'bank' and state.phase == 'bank_loot'
    if state.phase ~= 'combat' and not bankEarlyPhase then
        return notify(src, '현재는 경찰 교전 결과를 기록할 단계가 아닙니다.', true)
    end

    -- 신고를 받은 것과 별개로 결과 기록 시점에 다시 근무중 치안 팩션인지 검증.
    if not isLaw(src, true) then
        return notify(src, '근무 중 경찰/보안국만 교전 결과를 기록할 수 있습니다.', true)
    end

    local maxDistance = math.max(
        tonumber(Config.PoliceResultDistance) or 3.5,
        tonumber(state.loc.interactDistance) or 2.5
    ) + 1.0

    if distanceToLocation(src, state.loc) > maxDistance then
        return notify(src, '점원 비콘 가까이에서 결과를 기록하세요.', true)
    end

    local officer = displayName(src)

    if result == 'police_win' then
        failRobbery(
            state,
            ('경찰 측 승리 · %s님이 현장 결과를 확정했습니다.'):format(officer)
        )

        notify(src, '경찰 측 승리로 기록했습니다. 강도가 종료되었습니다.', false)
        return
    end

    if result == 'police_lose' then
        if state.loc.type == 'bank' then
            if state.phase ~= 'combat' or (state.bankLootTotal or 0) < (state.loc.requiredLootAmount or 0) then
                return notify(
                    src,
                    ('대형 RP팀이 요구 전리품을 아직 확보하지 못했습니다. 현재 %d / %d'):format(
                        state.bankLootTotal or 0,
                        state.loc.requiredLootAmount or 0
                    ),
                    true
                )
            end

            notify(src, '경찰 측 패배로 기록했습니다. 은행 강도가 최종 성공 처리됩니다.', false)
            finishBankSuccess(
                state,
                ('police_lose by %s after bank loot quota'):format(officer)
            )
            return
        end

        endPublicBoundary(state)
        unlockLoot(
            state,
            ('경찰 측 패배 · %s님이 결과를 확정했습니다. 금고가 해제되었습니다.'):format(officer)
        )

        notify(src, '경찰 측 패배로 기록했습니다. 강도팀의 전리품 회수가 가능해졌습니다.', false)

        -- 경찰 쪽 노란 연락 마커는 결과 확정 즉시 제거.
        for _, raw in ipairs(GetPlayers()) do
            local law = tonumber(raw)
            if law and isLaw(law, true) then
                TriggerClientEvent('cookie_robbery:client:dispatchEnd', law, id)
            end
        end

        MySQL.insert.await([[
            INSERT INTO cookie_robbery_log
                (robbery_id, robbery_label, starter_citizenid, starter_name,
                 status, cash_reward, item_reward_json, detail)
            VALUES (?, ?, ?, ?, 'police_result', 0, '[]', ?)
        ]], {
            state.id,
            state.loc.label,
            state.starterCitizenId,
            state.starterName,
            ('police_lose by %s'):format(officer),
        })
        return
    end

    notify(src, '잘못된 결과 값입니다.', true)
end)

RegisterNetEvent('cookie_robbery:server:beginLoot', function(id)
    local src = source
    id = tonumber(id)
    local state = id and Active[id] or nil

    if not state or state.phase ~= 'loot' or not state.crew[src] then return end
    if state.lootBusy then
        return notify(src, '다른 공범이 이미 금고를 털고 있습니다.', true)
    end
    if not isAlive(src) or distanceToLocation(src, state.loc) > (state.loc.interactDistance + 2.0) then
        return notify(src, '금고/계산대 근처에서 시도하세요.', true)
    end

    state.lootBusy = true
    state.looter = src
    state.lootEndsAt = now() + state.loc.lootSeconds

    sendCrew(state, 'cookie_robbery:client:lootStarted', {
        id = id,
        looter = src,
        looterName = displayName(src),
        seconds = state.loc.lootSeconds,
    })
end)

local function giveRewards(src, state)
    local p = player(src)
    if not p then return 0, {} end

    local loc = state.loc
    local cashMin = math.min(loc.cashMin, loc.cashMax)
    local cashMax = math.max(loc.cashMin, loc.cashMax)
    local cash = cashMax > 0 and math.random(cashMin, cashMax) or 0

    if cash > 0 then
        p.Functions.AddMoney('cash', cash, '편의점 강도 전리품')
    end

    local itemRewards = {}

    for _, reward in ipairs(loc.rewards or {}) do
        if reward.item ~= '' and math.random() * 100.0 <= reward.chance then
            local mn = math.min(reward.min, reward.max)
            local mx = math.max(reward.min, reward.max)
            local amount = math.random(mn, mx)

            local canCarry = true
            local okCarry, result = pcall(function()
                return exports.ox_inventory:CanCarryItem(src, reward.item, amount)
            end)
            if okCarry then canCarry = result == true end

            if canCarry then
                local added = false
                pcall(function()
                    added = exports.ox_inventory:AddItem(src, reward.item, amount) == true
                end)

                if added then
                    itemRewards[#itemRewards + 1] = {
                        item = reward.item,
                        label = reward.label,
                        amount = amount,
                    }
                end
            end
        end
    end

    return cash, itemRewards
end

RegisterNetEvent('cookie_robbery:server:lootFinished', function(id)
    local src = source
    id = tonumber(id)
    local state = id and Active[id] or nil

    if not state or state.phase ~= 'loot' or state.looter ~= src or not state.lootBusy then return end
    if now() + 1 < (state.lootEndsAt or 0) then
        return notify(src, '아직 전리품을 챙기는 중입니다.', true)
    end
    if not isAlive(src) or distanceToLocation(src, state.loc) > (state.loc.interactDistance + 3.0) then
        state.lootBusy = false
        state.looter = nil
        return notify(src, '금고에서 너무 멀어 전리품 회수가 취소되었습니다.', true)
    end

    local cash, items = giveRewards(src, state)
    endPublicBoundary(state)
    Active[id] = nil
    refreshNameHideZones()

    local itemText = {}
    for _, r in ipairs(items) do
        itemText[#itemText + 1] = ('%s x%d'):format(r.label or r.item, r.amount)
    end

    local msg = ('강도 성공 · 현금 %s원'):format(tostring(cash))
    if #itemText > 0 then
        msg = msg .. ' · ' .. table.concat(itemText, ', ')
    end

    sendCrew(state, 'cookie_robbery:client:ended', {
        id = id,
        success = true,
        message = msg,
    })

    for _, raw in ipairs(GetPlayers()) do
        local law = tonumber(raw)
        if law and isLaw(law, true) then
            TriggerClientEvent('cookie_robbery:client:dispatchEnd', law, id)
        end
    end

    logRobbery(state, 'success', cash, items, ('looter=%s'):format(displayName(src)))
end)

RegisterNetEvent('cookie_robbery:server:lootCancelled', function(id)
    local src = source
    id = tonumber(id)
    local state = id and Active[id] or nil
    if not state or state.phase ~= 'loot' or state.looter ~= src then return end
    state.lootBusy = false
    state.looter = nil
    sendCrew(state, 'cookie_robbery:client:status', '전리품 회수가 중단되었습니다. 다시 시도할 수 있습니다.', true)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, state in pairs(Active) do
        if state.crew[src] then
            state.crew[src] = nil
            state.awaySince[src] = nil
            if state.looter == src then
                state.lootBusy = false
                state.looter = nil
            end
            if state.bankLooter == src then
                state.bankLootBusy = false
                state.bankLooter = nil
                state.bankLootPoint = nil
                state.bankLootEndsAt = nil
            end
        end
    end
end)

RegisterCommand('robberydiag', function(src)
    local locationCount, activeCount = 0, 0
    for _ in pairs(Locations) do locationCount = locationCount + 1 end
    for _ in pairs(Active) do activeCount = activeCount + 1 end
    local msg = ('locations=%d active=%d'):format(locationCount, activeCount)

    if src == 0 then
        print('[cookie_robbery] ' .. msg)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { '^3[cookie_robbery]', msg } })
    end
end, false)


AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        GlobalState.cookieRobberyNameHideZones = {}
    end
end)
