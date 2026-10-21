
CreateThread(function()
    Wait(1400)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_faction_warning (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
            faction_id INT NOT NULL,
            citizenid VARCHAR(64) NULL,
            reason VARCHAR(300) NOT NULL,
            admin_name VARCHAR(60) NULL,
            admin_license VARCHAR(100) NULL,
            active TINYINT(1) NOT NULL DEFAULT 1,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            revoked_at DATETIME NULL,
            KEY idx_faction_warning (faction_id, active)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await('ALTER TABLE cookie_faction_warning MODIFY COLUMN citizenid VARCHAR(64) NULL')
    -- 구버전의 개인 경고는 폐기하고 팩션 단위 경고만 사용한다.
    MySQL.query.await('DELETE FROM cookie_faction_warning WHERE citizenid IS NOT NULL')
end)



CreateThread(function()
    Wait(1800)
    -- Faction colours are stored as strict RGB (#RRGGBB). Trim legacy RGBA values.
    pcall(function()
        MySQL.update.await([[
            UPDATE cookie_faction
            SET color = LEFT(UPPER(color), 7)
            WHERE color REGEXP '^#[0-9A-Fa-f]{8}$'
        ]])
        MySQL.update.await([[
            UPDATE cookie_faction
            SET color = '#FFB800'
            WHERE color IS NULL OR color NOT REGEXP '^#[0-9A-Fa-f]{6}$'
        ]])
    end)
end)

local function normalizeRgb(value)
    local c = tostring(value or ''):upper():gsub('%s+', '')
    if c:match('^#%x%x%x%x%x%x$') then return c end
    return nil
end

local function alog(...)
    if Config and Config.Debug then  end
end

local function anotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local function validType(t)
    for _, ft in ipairs(Config.FactionTypes or {}) do
        if ft.key == t then return ft end
    end
    return nil
end

local function isGovType(t)
    local ft = validType(t)
    return ft and ft.gov == true or false
end

local function validRgbColor(v)
    local c = tostring(v or ''):upper():gsub('%s+', '')
    if c:match('^#%x%x%x%x%x%x$') then return c end
    return nil
end

local function sourceOfCitizen(citizenid)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local p = src and exports.qbx_core:GetPlayer(src) or nil
        if p and p.PlayerData and p.PlayerData.citizenid == citizenid then return src end
    end
    return nil
end

local function membershipConflict(citizenid, targetFactionId)
    local row = MySQL.single.await([[
        SELECT m.faction_id, f.name, f.leader_citizenid
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id = m.faction_id AND f.is_active = 1
        WHERE m.citizenid = ? AND m.status = 'active'
        LIMIT 1
    ]], { citizenid })
    if row and tonumber(row.faction_id) ~= tonumber(targetFactionId) then
        return ('이미 %s 팩션에 소속되어 있습니다'):format(row.name or '다른')
    end
    local lead = MySQL.single.await([[
        SELECT id, name FROM cookie_faction
        WHERE is_active = 1 AND leader_citizenid = ? AND id <> ?
        LIMIT 1
    ]], { citizenid, tonumber(targetFactionId) or 0 })
    if lead then return ('이미 %s 팩션의 리더입니다'):format(lead.name or '다른') end
    return nil
end

local demoteExistingLeader

local function refreshFactionMembers(factionId)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local p = src and exports.qbx_core:GetPlayer(src) or nil
        local cid = p and p.PlayerData and p.PlayerData.citizenid or nil
        if cid then
            local row = MySQL.single.await(
                "SELECT 1 AS x FROM cookie_faction_member WHERE faction_id=? AND citizenid=? AND status='active' LIMIT 1",
                { factionId, cid })
            if row then
                TriggerClientEvent('cookie_admin:client:factionPane', src, CookieBuildFactionPane(src))
                if CookiePushJobDisplay then CookiePushJobDisplay(src) end
                if CookieRefreshNameTag then CookieRefreshNameTag(src) end
            end
        end
    end
end

local function slug(s)
    if type(s) ~= 'string' then return nil end
    local out = s:lower():gsub('[^%a%d_]', '')
    if #out < 2 or #out > 30 then return nil end
    return out
end

local function sendList(src)
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT f.id, f.faction_key, f.faction_type, f.job_name, f.name, f.color,
                   f.garage_key, f.disposition, f.duty, f.emoji, f.tag_name,
                   f.budget, f.leader_citizenid, f.is_active,
                   (SELECT COUNT(*) FROM cookie_faction_member m
                     WHERE m.faction_id = f.id AND m.status = 'active') AS member_count
            FROM cookie_faction f
            WHERE f.is_active = 1
            ORDER BY f.id
        ]], {})
    end)
    rows = (ok and rows) or {}

    for _, f in ipairs(rows) do
        local okS, shop = pcall(function()
            return MySQL.query.await([[
                SELECT id, model, label, price, min_grade, active
                FROM cookie_faction_shop WHERE faction_id = ? ORDER BY price ASC
            ]], { f.id })
        end)
        f.shop = (okS and shop) or {}

        local okM, mem = pcall(function()
            return MySQL.query.await([[
                SELECT m.citizenid, m.grade, m.department, m.duty, r.rank_name, cu.nickname, cu.gobun
                FROM cookie_faction_member m
                LEFT JOIN cookie_faction_rank r ON r.faction_id = m.faction_id AND r.grade = m.grade
                LEFT JOIN players p ON p.citizenid = m.citizenid
                LEFT JOIN cookie_user cu
                       ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
                        = SUBSTRING_INDEX(p.license, ':', -1)  COLLATE utf8mb4_unicode_ci
                WHERE m.faction_id = ? AND m.status = 'active'
                ORDER BY m.grade DESC
            ]], { f.id })
        end)
        f.members = (okM and mem) or {}
        for _, mm in ipairs(f.members) do
            mm.server_id = sourceOfCitizen(mm.citizenid)
            mm.online = mm.server_id ~= nil
            mm.duty = (mm.duty == 1 or mm.duty == true)
        end

        f.is_gov = isGovType(f.faction_type)
        f.ranks = MySQL.query.await([[
            SELECT grade, rank_name, is_leader, is_officer, salary
            FROM cookie_faction_rank WHERE faction_id = ? ORDER BY grade DESC
        ]], { f.id }) or {}
        if not f.is_gov then
            for _, rr in ipairs(f.ranks) do rr.salary = 0 end
        end

        -- 팩션 자체에 부여된 활성 경고만 표시한다. (구버전 개인 경고는 citizenid가 있어 제외)
        local okW, warns = pcall(function()
            return MySQL.query.await([[
                SELECT id, reason, admin_name, active,
                       DATE_FORMAT(created_at, '%Y.%m.%d %H:%i') AS created_at
                FROM cookie_faction_warning
                WHERE faction_id = ? AND citizenid IS NULL
                ORDER BY id DESC LIMIT 50
            ]], { f.id })
        end)
        f.warnings = (okW and warns) or {}
        f.warning_count = 0
        for _, w in ipairs(f.warnings) do
            if w.active == 1 or w.active == true then f.warning_count = f.warning_count + 1 end
        end

        f.leader_nickname = nil
        if f.leader_citizenid then
            for _, mm in ipairs(f.members) do
                if mm.citizenid == f.leader_citizenid then
                    f.leader_nickname = mm.nickname or mm.citizenid
                    break
                end
            end
        end
    end

    TriggerClientEvent('cookie_admin:client:factionAdminList', src, rows, Config.FactionTypes)
end

RegisterNetEvent('cookie_admin:server:factionList', function()
    local src = source
    if not CookieAdminTeamAuth(src, 'faction') then

        return
    end
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionCreate', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local ft = validType(data.type)
    if not ft then return anotify(src, '팩션 타입이 올바르지 않습니다', true) end

    local name = type(data.name) == 'string' and data.name:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #name < 2 then return anotify(src, '조직 이름을 입력하세요', true) end
    name = name:sub(1, 60)

    local key = slug(data.key)
    if not key then
        local try, n = ft.key, 1
        while MySQL.single.await('SELECT id FROM cookie_faction WHERE faction_key = ?', { try }) do
            n = n + 1
            try = ft.key .. n
        end
        key = try
    end

    local jobName = slug(data.jobName) or ((ft.key == 'police') and 'police' or key)

    if MySQL.single.await('SELECT id FROM cookie_faction WHERE faction_key = ?', { key }) then
        return anotify(src, '이미 존재하는 팩션 키입니다', true)
    end

    local trim = function(s, n)
        if type(s) ~= 'string' then return nil end
        local v = s:gsub('^%s+', ''):gsub('%s+$', '')
        return v ~= '' and v:sub(1, n) or nil
    end

    local garageKey = (ft.key == 'police') and 'cookie_lspd' or ('cookie_' .. key)
    local rgb = normalizeRgb(data.color or '#2F6FED')
    if not rgb then return anotify(src, '조직 색상은 #000000 형식의 RGB 6자리로 입력하세요', true) end

    local id = MySQL.insert.await([[
        INSERT INTO cookie_faction
          (faction_key, faction_type, job_name, name, color, disposition, duty, garage_key, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { key, ft.key, jobName, name,
          rgb,
          trim(data.disposition, 40),
          trim(data.duty, 120),
          garageKey,
          admin.admin_name })
    if not id then return anotify(src, '팩션 생성에 실패했습니다', true) end

    CookieFactionSeedRanks(id, ft.key)
    if ft.key == 'crime' and type(CookieSeedCrimeCatalog) == 'function' then
        local seeded, seedErr = pcall(CookieSeedCrimeCatalog, id)
        if not seeded then print(('^1[cookie_admin] crime catalog seed failed faction=%s: %s^7'):format(tostring(id),tostring(seedErr))) end
    end
    local ok, err = CookieFactionEnsureJob(id)

    if ok then
        anotify(src, ('%s(%s) 팩션을 생성했습니다'):format(name, ft.label), false)
    else
        anotify(src, ('팩션은 생성됐지만 job 연동 실패: %s'):format(tostring(err)), true)
    end
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionUpdate', function(id, data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end

    local fid = math.floor(tonumber(id) or 0)
    if fid <= 0 or type(data) ~= 'table' then return end

    local f = MySQL.single.await('SELECT id, name FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    local name = type(data.name) == 'string' and data.name:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #name < 2 then return anotify(src, '팩션 이름을 입력하세요', true) end

    local disp = nil
    if type(data.disposition) == 'string' then
        local d = data.disposition:gsub('^%s+', ''):gsub('%s+$', '')
        if d ~= '' then disp = d:sub(1, 40) end
    end
    local duty = nil
    if type(data.duty) == 'string' then
        local d = data.duty:gsub('^%s+', ''):gsub('%s+$', '')
        if d ~= '' then duty = d:sub(1, 120) end
    end

    local emoji = nil
    if type(data.emoji) == 'string' then
        local e = data.emoji:gsub('^%s+', ''):gsub('%s+$', '')
        if e ~= '' then emoji = e:sub(1, 64) end
    end

    local tagName = nil
    if type(data.tagName) == 'string' then
        local t = data.tagName:gsub('^%s+', ''):gsub('%s+$', '')
        if t ~= '' then tagName = t:sub(1, 20) end
    end

    local rgb = normalizeRgb(data.color)
    if not rgb then return anotify(src, '조직 색상은 #000000 형식의 RGB 6자리로 입력하세요', true) end

    MySQL.update.await(
        'UPDATE cookie_faction SET name = ?, color = ?, disposition = ?, duty = ?, emoji = ?, tag_name = ? WHERE id = ?', {
        name:sub(1, 60),
        rgb,
        disp, duty, emoji, tagName, fid,
    })

    anotify(src, ('%s 팩션 정보를 저장했습니다'):format(name), false)

    for _, pid in ipairs(GetPlayers()) do
        local psrc = tonumber(pid)
        local mem = CookieFactionMemberOf(psrc)
        if mem and mem.id == fid then
            TriggerClientEvent('cookie_admin:client:factionPane', psrc, CookieBuildFactionPane(psrc))
            CookiePushJobDisplay(psrc)

            if CookieRefreshNameTag then pcall(CookieRefreshNameTag, psrc) end
        end
    end
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionDelete', function(id)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end

    local fid = math.floor(tonumber(id) or 0)
    if fid <= 0 then return end

    local f = MySQL.single.await('SELECT id, name FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    -- 팩션 자체를 삭제할 때도 소속원들의 예전 소속/팩션직이 남지 않게 먼저 정리한다.
    local members = MySQL.query.await(
        "SELECT citizenid FROM cookie_faction_member WHERE faction_id = ? AND status = 'active'",
        { fid }
    ) or {}
    for _, member in ipairs(members) do
        if CookieFactionPurgeMembership then
            CookieFactionPurgeMembership(member.citizenid, nil)
        else
            MySQL.query.await('DELETE FROM cookie_faction_member WHERE citizenid = ?', { member.citizenid })
            if CookieFactionClearMemberJob then CookieFactionClearMemberJob(member.citizenid) end
        end
    end

    -- 팩션 삭제 시 그 팩션 전용 전시/차고 설정도 함께 삭제한다.
    MySQL.query.await('DELETE FROM cookie_faction_shop WHERE faction_id = ?', { fid })
    pcall(function() MySQL.query.await('DELETE FROM cookie_faction_vehicle WHERE faction_id = ?', { fid }) end)
    MySQL.update.await('UPDATE cookie_faction SET is_active = 0, leader_citizenid = NULL WHERE id = ?', { fid })

    -- 삭제된 팩션을 사용하던 비콘은 공용으로 전환.
    pcall(function()
        MySQL.update.await('UPDATE cookie_zone SET faction_id = NULL WHERE faction_id = ?', { fid })
    end)
    TriggerEvent('cookie_safezone:server:reloadFactionMap')

    anotify(src, ('%s 팩션을 제거했습니다'):format(f.name), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionSetLeader', function(id, targetServerId)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end

    local fid = math.floor(tonumber(id) or 0)
    local tsrc = math.floor(tonumber(targetServerId) or 0)
    if fid <= 0 or tsrc <= 0 then return end

    local f = MySQL.single.await(
        'SELECT id, name, job_name FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    local target = exports.qbx_core:GetPlayer(tsrc)
    if not target then return anotify(src, '대상을 찾을 수 없습니다 (접속 종료?)', true) end
    local cid = target.PlayerData and target.PlayerData.citizenid
    if not cid then return anotify(src, '대상의 시민번호를 확인할 수 없습니다', true) end

    local lead = MySQL.single.await([[
        SELECT grade FROM cookie_faction_rank
        WHERE faction_id = ? AND is_leader = 1 ORDER BY grade DESC LIMIT 1
    ]], { fid })
    if not lead then return anotify(src, '리더 계급이 정의되지 않았습니다', true) end

    -- 한 캐릭터는 동시에 두 팩션에 소속되거나 여러 팩션의 리더가 될 수 없다.
    local conflict = membershipConflict(cid, fid)
    if conflict then return anotify(src, conflict, true) end

    -- 기존 리더는 최고 간부 계급으로 자동 강등하여 리더가 여러 명 남지 않게 한다.
    demoteExistingLeader(fid, cid, f)

    MySQL.query.await([[
        INSERT INTO cookie_faction_member (faction_id, citizenid, grade, invited_by, status, duty)
        VALUES (?, ?, ?, ?, 'active', 0)
        ON DUPLICATE KEY UPDATE grade = VALUES(grade), status = 'active'
    ]], { fid, cid, lead.grade, admin.admin_name })

    MySQL.update.await('UPDATE cookie_faction SET leader_citizenid = ? WHERE id = ?', { cid, fid })

    CookieFactionSyncMemberJob(cid, f.job_name, lead.grade)

    local nm = target.PlayerData.charinfo
    local tname = nm and ((nm.firstname or '') .. ' ' .. (nm.lastname or '')) or cid

    anotify(src, ('%s님을 %s 리더로 임명했습니다'):format(tname, f.name), false)
    TriggerClientEvent('cookie_admin:client:notify', tsrc, ('%s 리더로 임명되었습니다'):format(f.name), false)

    TriggerClientEvent('cookie_admin:client:factionPane', tsrc, CookieBuildFactionPane(tsrc))
    CookiePushJobDisplay(tsrc)
    if CookieRefreshNameTag then CookieRefreshNameTag(tsrc) end
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionShopSave', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local fid = math.floor(tonumber(data.factionId) or 0)
    if fid <= 0 then return end

    local model = type(data.model) == 'string' and data.model:lower():gsub('[^%w_]', '') or ''
    if #model < 2 then return anotify(src, '차량 모델명을 입력하세요', true) end

    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local minGrade = math.max(0, math.floor(tonumber(data.minGrade) or 0))
    local label = (type(data.label) == 'string' and data.label ~= '') and data.label:sub(1, 60) or model

    local active = (data.active == false or data.active == 0 or data.active == '0') and 0 or 1

    local sid = math.floor(tonumber(data.id) or 0)
    if sid > 0 then
        MySQL.update.await([[
            UPDATE cookie_faction_shop SET model = ?, label = ?, price = ?, min_grade = ?, active = ?
            WHERE id = ? AND faction_id = ?
        ]], { model, label, price, minGrade, active, sid, fid })
        anotify(src, ('%s %s ($%d)'):format(label, (active == 1) and '전시 중' or '전시 중지', price), false)

        for _, pid in ipairs(GetPlayers()) do
            local psrc = tonumber(pid)
            local mem = CookieFactionMemberOf and CookieFactionMemberOf(psrc)
            if mem and mem.id == fid then
                TriggerClientEvent('cookie_admin:client:factionPane', psrc, CookieBuildFactionPane(psrc))
            end
        end
    else
        MySQL.insert.await([[
            INSERT INTO cookie_faction_shop (faction_id, model, label, price, min_grade, added_by)
            VALUES (?, ?, ?, ?, ?, ?)
        ]], { fid, model, label, price, minGrade, admin.admin_name })
        anotify(src, ('%s 을(를) 카탈로그에 추가했습니다 ($%d)'):format(label, price), false)
    end

    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionShopDelete', function(id)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end

    local sid = math.floor(tonumber(id) or 0)
    if sid <= 0 then return end

    local row = MySQL.single.await('SELECT faction_id, label FROM cookie_faction_shop WHERE id = ?', { sid })
    if not row then return anotify(src, '카탈로그 항목을 찾을 수 없습니다', true) end

    MySQL.query.await('DELETE FROM cookie_faction_shop WHERE id = ?', { sid })

    anotify(src, ('%s 을(를) 카탈로그에서 제거했습니다'):format(row.label or '-'), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionBudgetAdjust', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local fid = math.floor(tonumber(data.factionId) or 0)
    local amt = math.floor(tonumber(data.amount) or 0)
    local mode = (data.mode == 'take') and 'take' or 'add'
    if fid <= 0 or amt <= 0 or amt > 1000000000 then
        return anotify(src, '금액이 올바르지 않습니다', true)
    end

    local why = type(data.reason) == 'string' and data.reason:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #why < 2 then return anotify(src, '사유를 입력하세요', true) end
    why = why:sub(1, 120)

    local f = MySQL.single.await('SELECT id, name FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    if mode == 'take' then
        local aff = MySQL.update.await(
            'UPDATE cookie_faction SET budget = budget - ? WHERE id = ? AND budget >= ?', { amt, fid, amt })
        if not aff or aff < 1 then return anotify(src, '팩션 예산이 부족합니다', true) end
    else
        MySQL.update.await('UPDATE cookie_faction SET budget = budget + ? WHERE id = ?', { amt, fid })
    end

    local row = MySQL.single.await('SELECT budget FROM cookie_faction WHERE id = ?', { fid })
    local bal = (row and tonumber(row.budget)) or 0

    anotify(src, ('%s 예산을 %s했습니다 (잔액 %d)'):format(f.name, (mode == 'take') and '회수' or '추가', bal), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:requestLogs', function(kind)
    local src = source

    local admin = CookieAdminTeamAuth(src, 'general')
    if not admin or admin.admin_level < 4 then

        return
    end

    local rows = {}
    if kind == 'faction_budget' or not kind then
        local ok, r = pcall(function()

            return MySQL.query.await([[
                SELECT bl.created_at, f.name AS faction, bl.delta, bl.balance_after,
                       bl.category, bl.reason,
                       COALESCE(cu.nickname, bl.actor_citizenid) AS actor
                FROM cookie_faction_budget_log bl
                LEFT JOIN cookie_faction f ON f.id = bl.faction_id
                LEFT JOIN players p ON p.citizenid = bl.actor_citizenid
                LEFT JOIN cookie_user cu
                       ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
                        = SUBSTRING_INDEX(p.license, ':', -1)  COLLATE utf8mb4_unicode_ci
                ORDER BY bl.id DESC LIMIT 200
            ]], {})
        end)
        rows = (ok and r) or {}

    elseif kind == 'chat_mod' then

        local ok, r = pcall(function()
            return MySQL.query.await([[
                SELECT created_at, action, admin_name, target_gobun, target_nick, reason, minutes
                FROM cookie_admin_chat_action
                ORDER BY id DESC LIMIT 200
            ]], {})
        end)
        rows = (ok and r) or {}

    elseif kind == 'trade' then
        local ok, r = pcall(function()
            return MySQL.query.await([[
                SELECT id, trade_id, created_at, status,
                       a_gobun, a_name, a_faction, a_offer,
                       b_gobun, b_name, b_faction, b_offer
                FROM cookie_trade_log
                ORDER BY id DESC
                LIMIT 200
            ]], {})
        end)
        rows = (ok and r) or {}

    elseif kind == 'transfer' then
        local ok, r = pcall(function()
            return MySQL.query.await([[
                SELECT t.id, t.created_at, t.amount, t.memo, t.transfer_mode,
                       t.sender_phone, t.receiver_phone,
                       su.gobun AS sender_gobun, su.nickname AS sender_name,
                       ru.gobun AS receiver_gobun, ru.nickname AS receiver_name
                FROM cookie_phone_bank_transfer t
                LEFT JOIN cookie_user su
                       ON su.license COLLATE utf8mb4_general_ci
                        = t.sender_license COLLATE utf8mb4_general_ci
                LEFT JOIN cookie_user ru
                       ON ru.license COLLATE utf8mb4_general_ci
                        = t.receiver_license COLLATE utf8mb4_general_ci
                ORDER BY t.id DESC
                LIMIT 200
            ]], {})
        end)
        rows = (ok and r) or {}

    elseif kind == 'suggestion' then
        local ok, r = pcall(function()
            return MySQL.query.await([[
                SELECT id,created_at,gobun,nickname,category,title,body,status
                FROM cookie_suggestion
                ORDER BY id DESC
                LIMIT 200
            ]], {})
        end)
        rows = (ok and r) or {}
    end

    TriggerClientEvent('cookie_admin:client:logs', src, kind or 'faction_budget', rows)
end)

RegisterNetEvent('cookie_admin:server:factionFleetAdd', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local fid = math.floor(tonumber(data.factionId) or 0)
    local model = type(data.model) == 'string' and data.model:lower():gsub('[^%w_]', '') or ''
    if fid <= 0 or #model < 2 then return anotify(src, '팩션과 차량을 선택하세요', true) end

    local f = MySQL.single.await(
        'SELECT id, name, faction_key, faction_type, garage_key FROM cookie_faction WHERE id = ? AND is_active = 1',
        { fid })
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    local garage = (f.garage_key and f.garage_key ~= '' and f.garage_key)
        or ((f.faction_type == 'police') and 'cookie_lspd')
        or ('cookie_' .. f.faction_key)

    local ownerCid = 'FACTION_' .. fid
    if CookieEnsureFactionOwner then CookieEnsureFactionOwner(ownerCid) end

    local ok, vid = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = ownerCid,
            garage = garage,
        })
    end)
    if not ok or not vid then

        return anotify(src, '차고 투입 실패 (모델 확인)', true)
    end

    MySQL.insert.await(
        'INSERT INTO cookie_faction_vehicle (faction_id, model, min_grade, added_by) VALUES (?, ?, ?, ?)',
        { fid, model, math.max(0, math.floor(tonumber(data.minGrade) or 0)), admin.admin_name })

    anotify(src, ('%s 차고에 %s 투입 완료 (무료)'):format(f.name, model), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionAddMember', function(id, targetServerId)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end

    local fid = math.floor(tonumber(id) or 0)
    local tsrc = math.floor(tonumber(targetServerId) or 0)
    if fid <= 0 or tsrc <= 0 then return end

    local f = MySQL.single.await(
        'SELECT id, name, job_name FROM cookie_faction WHERE id = ? AND is_active = 1', { fid })
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    local target = exports.qbx_core:GetPlayer(tsrc)
    if not target then return anotify(src, '대상을 찾을 수 없습니다', true) end
    local cid = target.PlayerData and target.PlayerData.citizenid
    if not cid then return end

    local low = MySQL.single.await(
        'SELECT grade FROM cookie_faction_rank WHERE faction_id = ? ORDER BY grade ASC LIMIT 1', { fid })
    local grade = (low and low.grade) or 0

    local conflict = membershipConflict(cid, fid)
    if conflict then return anotify(src, conflict, true) end

    local already = MySQL.single.await(
        "SELECT 1 AS x FROM cookie_faction_member WHERE faction_id=? AND citizenid=? AND status='active' LIMIT 1",
        { fid, cid })
    if already then return anotify(src, '이미 해당 팩션 소속입니다', true) end

    MySQL.query.await([[
        INSERT INTO cookie_faction_member (faction_id, citizenid, grade, invited_by, status, duty)
        VALUES (?, ?, ?, ?, 'active', 0)
        ON DUPLICATE KEY UPDATE grade = VALUES(grade), status = 'active'
    ]], { fid, cid, grade, admin.admin_name })

    CookieFactionSyncMemberJob(cid, f.job_name, grade)

    anotify(src, ('%s 팩션에 팩션원을 추가했습니다'):format(f.name), false)
    TriggerClientEvent('cookie_admin:client:factionPane', tsrc, CookieBuildFactionPane(tsrc))
    CookiePushJobDisplay(tsrc)
    if CookieRefreshNameTag then CookieRefreshNameTag(tsrc) end
    sendList(src)
end)

-- ─────────────────────────────────────────────────────────────
-- COOKIE FACTION ADMIN V2: 계급 / 팩션원 / 경고 / 강제 퇴근
-- ─────────────────────────────────────────────────────────────

local function factionAdminRow(fid)
    return MySQL.single.await(
        'SELECT id, name, job_name, faction_type FROM cookie_faction WHERE id=? AND is_active=1 LIMIT 1',
        { fid })
end

demoteExistingLeader = function(fid, exceptCitizenid, f)
    local current = MySQL.single.await(
        'SELECT leader_citizenid FROM cookie_faction WHERE id=? AND is_active=1 LIMIT 1', { fid })
    local oldCid = current and current.leader_citizenid or nil
    if not oldCid or oldCid == '' or oldCid == exceptCitizenid then return end

    local fallback = MySQL.single.await([[
        SELECT grade FROM cookie_faction_rank
        WHERE faction_id=? AND is_leader=0
        ORDER BY is_officer DESC, grade DESC LIMIT 1
    ]], { fid })
    if fallback then
        MySQL.update.await(
            "UPDATE cookie_faction_member SET grade=? WHERE faction_id=? AND citizenid=? AND status='active'",
            { fallback.grade, fid, oldCid })
        CookieFactionSyncMemberJob(oldCid, f.job_name, fallback.grade)
        local oldSrc = sourceOfCitizen(oldCid)
        if oldSrc then
            TriggerClientEvent('cookie_admin:client:factionPane', oldSrc, CookieBuildFactionPane(oldSrc))
            if CookiePushJobDisplay then CookiePushJobDisplay(oldSrc) end
            if CookieRefreshNameTag then CookieRefreshNameTag(oldSrc) end
        end
    end
end

local function rankAdminSyncJob(f, grade, rankName, salary)
    local pay = isGovType(f.faction_type) and math.max(0, math.floor(tonumber(salary) or 0)) or 0
    pcall(function()
        exports.qbx_core:UpsertJobGrade(f.job_name, grade, { name = rankName, payment = pay }, true)
    end)
end

RegisterNetEvent('cookie_admin:server:factionRankSaveAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local fid = math.floor(tonumber(data.factionId) or 0)
    local f = factionAdminRow(fid)
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end

    local grade = math.floor(tonumber(data.grade) or -1)
    if grade < 0 or grade > 50 then return anotify(src, '계급 번호는 0~50입니다', true) end
    local name = type(data.name) == 'string' and data.name:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if name == '' then return anotify(src, '계급명을 입력하세요', true) end
    name = name:sub(1, 40)

    local salary = isGovType(f.faction_type) and math.max(0, math.floor(tonumber(data.salary) or 0)) or 0
    if salary > 1000000000 then return anotify(src, '급여는 10억 원 이하로 설정하세요', true) end
    local isOfficer = data.isOfficer == true and 1 or 0
    local isLeader = data.isLeader == true and 1 or 0
    local oldGrade = tonumber(data.oldGrade)
    oldGrade = oldGrade and math.floor(oldGrade) or nil

    local oldRow = nil
    if oldGrade ~= nil then
        oldRow = MySQL.single.await(
            'SELECT rank_name, is_leader FROM cookie_faction_rank WHERE faction_id=? AND grade=? LIMIT 1',
            { fid, oldGrade })
        if not oldRow then return anotify(src, '기존 계급을 찾을 수 없습니다', true) end
    end

    -- 등급 번호를 옮기는 경우 중복 여부를 먼저 검증한다.
    if oldGrade ~= nil and oldGrade ~= grade then
        local dup = MySQL.single.await(
            'SELECT 1 AS x FROM cookie_faction_rank WHERE faction_id=? AND grade=? LIMIT 1', { fid, grade })
        if dup then return anotify(src, ('G%d 계급은 이미 존재합니다'):format(grade), true) end
    end

    if isLeader == 1 then
        MySQL.update.await('UPDATE cookie_faction_rank SET is_leader=0 WHERE faction_id=?', { fid })
    end

    if oldGrade ~= nil and oldGrade ~= grade then
        MySQL.update.await([[
            UPDATE cookie_faction_rank
            SET grade=?, rank_name=?, is_leader=?, is_officer=?, salary=?, sort_order=?
            WHERE faction_id=? AND grade=?
        ]], { grade, name, isLeader, isOfficer, salary, grade, fid, oldGrade })
        MySQL.update.await('UPDATE cookie_faction_member SET grade=? WHERE faction_id=? AND grade=?',
            { grade, fid, oldGrade })

        local moved = MySQL.query.await(
            "SELECT citizenid FROM cookie_faction_member WHERE faction_id=? AND grade=? AND status='active'",
            { fid, grade }) or {}
        for _, m in ipairs(moved) do CookieFactionSyncMemberJob(m.citizenid, f.job_name, grade) end
        pcall(function() exports.qbx_core:RemoveJobGrade(f.job_name, oldGrade, true) end)
    else
        MySQL.query.await([[
            INSERT INTO cookie_faction_rank
                (faction_id, grade, rank_name, is_leader, is_officer, salary, sort_order)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE rank_name=VALUES(rank_name), is_leader=VALUES(is_leader),
                is_officer=VALUES(is_officer), salary=VALUES(salary), sort_order=VALUES(sort_order)
        ]], { fid, grade, name, isLeader, isOfficer, salary, grade })
    end

    rankAdminSyncJob(f, grade, name, salary)

    if isLeader == 1 then
        local leader = MySQL.single.await(
            "SELECT citizenid FROM cookie_faction_member WHERE faction_id=? AND grade=? AND status='active' ORDER BY id ASC LIMIT 1",
            { fid, grade })
        if leader then
            demoteExistingLeader(fid, leader.citizenid, f)
            MySQL.update.await('UPDATE cookie_faction SET leader_citizenid=? WHERE id=?', { leader.citizenid, fid })
        else
            MySQL.update.await('UPDATE cookie_faction SET leader_citizenid=NULL WHERE id=?', { fid })
        end
    elseif oldRow and (oldRow.is_leader == 1 or oldRow.is_leader == true) then
        MySQL.update.await('UPDATE cookie_faction SET leader_citizenid=NULL WHERE id=?', { fid })
    end

    refreshFactionMembers(fid)
    anotify(src, ('%s G%d 계급을 저장했습니다%s'):format(name, grade,
        isGovType(f.faction_type) and (' · 급여 '..salary..'원') or ''), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionRankDeleteAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    local fid = math.floor(tonumber(data and data.factionId) or 0)
    local grade = math.floor(tonumber(data and data.grade) or -1)
    local f = factionAdminRow(fid)
    if not f or grade < 0 then return end

    local row = MySQL.single.await(
        'SELECT rank_name, is_leader FROM cookie_faction_rank WHERE faction_id=? AND grade=? LIMIT 1',
        { fid, grade })
    if not row then return anotify(src, '계급을 찾을 수 없습니다', true) end
    if row.is_leader == 1 or row.is_leader == true then return anotify(src, '리더 계급은 삭제할 수 없습니다', true) end

    local used = MySQL.scalar.await(
        "SELECT COUNT(*) FROM cookie_faction_member WHERE faction_id=? AND grade=? AND status='active'",
        { fid, grade }) or 0
    if tonumber(used) > 0 then return anotify(src, '해당 계급의 팩션원을 먼저 다른 계급으로 변경하세요', true) end

    MySQL.query.await('DELETE FROM cookie_faction_rank WHERE faction_id=? AND grade=?', { fid, grade })
    pcall(function() exports.qbx_core:RemoveJobGrade(f.job_name, grade, true) end)
    refreshFactionMembers(fid)
    anotify(src, ('%s 계급을 삭제했습니다'):format(row.rank_name or ('G'..grade)), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionMemberRankAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local fid = math.floor(tonumber(data.factionId) or 0)
    local grade = math.floor(tonumber(data.grade) or -1)
    local cid = tostring(data.citizenid or '')
    local f = factionAdminRow(fid)
    if not f or cid == '' or grade < 0 then return end

    local mem = MySQL.single.await(
        "SELECT 1 AS x FROM cookie_faction_member WHERE faction_id=? AND citizenid=? AND status='active' LIMIT 1",
        { fid, cid })
    if not mem then return anotify(src, '팩션원을 찾을 수 없습니다', true) end
    local rank = MySQL.single.await(
        'SELECT rank_name, is_leader FROM cookie_faction_rank WHERE faction_id=? AND grade=? LIMIT 1',
        { fid, grade })
    if not rank then return anotify(src, '없는 계급입니다', true) end

    if rank.is_leader == 1 or rank.is_leader == true then
        local conflict = membershipConflict(cid, fid)
        if conflict then return anotify(src, conflict, true) end
        demoteExistingLeader(fid, cid, f)
        MySQL.update.await('UPDATE cookie_faction SET leader_citizenid=? WHERE id=?', { cid, fid })
    else
        local cur = MySQL.single.await('SELECT leader_citizenid FROM cookie_faction WHERE id=? LIMIT 1', { fid })
        if cur and cur.leader_citizenid == cid then
            MySQL.update.await('UPDATE cookie_faction SET leader_citizenid=NULL WHERE id=?', { fid })
        end
    end

    MySQL.update.await('UPDATE cookie_faction_member SET grade=? WHERE faction_id=? AND citizenid=?',
        { grade, fid, cid })
    CookieFactionSyncMemberJob(cid, f.job_name, grade)
    local tsrc = sourceOfCitizen(cid)
    if tsrc then
        TriggerClientEvent('cookie_admin:client:factionPane', tsrc, CookieBuildFactionPane(tsrc))
        if CookiePushJobDisplay then CookiePushJobDisplay(tsrc) end
        if CookieRefreshNameTag then CookieRefreshNameTag(tsrc) end
    end
    anotify(src, ('팩션원 계급을 %s(으)로 변경했습니다'):format(rank.rank_name or ('G'..grade)), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionMemberRemoveAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local fid = math.floor(tonumber(data.factionId) or 0)
    local cid = tostring(data.citizenid or '')
    local reason = tostring(data.reason or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if reason == '' then reason = '관리자 팩션직 제거' end
    reason = reason:sub(1, 300)
    local f = factionAdminRow(fid)
    if not f or cid == '' then return end

    local mem = MySQL.single.await(
        "SELECT 1 AS x FROM cookie_faction_member WHERE faction_id=? AND citizenid=? AND status='active' LIMIT 1",
        { fid, cid })
    if not mem then return anotify(src, '팩션원을 찾을 수 없습니다', true) end

    CookieFactionPurgeMembership(cid, nil)
    local tsrc = sourceOfCitizen(cid)
    if tsrc then
        TriggerClientEvent('cookie_admin:client:factionPane', tsrc, nil)
        if CookiePushJobDisplay then CookiePushJobDisplay(tsrc) end
        if CookieRefreshNameTag then CookieRefreshNameTag(tsrc) end
        TriggerClientEvent('cookie_admin:client:notify', tsrc,
            ('%s 소속이 관리자에 의해 제거되었습니다 · 사유: %s'):format(f.name, reason), true)
    end
    MySQL.insert.await('INSERT INTO cookie_faction_log (faction_id, action, actor, detail) VALUES (?, ?, ?, ?)',
        { fid, 'admin_remove_member', admin.admin_name, ('citizenid=%s / %s'):format(cid, reason) })
    anotify(src, '팩션직을 제거했습니다', false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionWarningAddAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    local fid = math.floor(tonumber(data and data.factionId) or 0)
    local reason = tostring(data and data.reason or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local f = factionAdminRow(fid)
    if not f then return anotify(src, '팩션을 찾을 수 없습니다', true) end
    if #reason < 2 then return anotify(src, '경고 사유를 2글자 이상 입력하세요', true) end

    MySQL.insert.await([[
        INSERT INTO cookie_faction_warning
            (faction_id, citizenid, reason, admin_name, admin_license, active)
        VALUES (?, NULL, ?, ?, ?, 1)
    ]], { fid, reason:sub(1,300), admin.admin_name or '관리자', admin.license })
    MySQL.insert.await('INSERT INTO cookie_faction_log (faction_id, action, actor, detail) VALUES (?, ?, ?, ?)',
        { fid, 'faction_warning', admin.admin_name, reason:sub(1,300) })
    anotify(src, ('%s 팩션에 경고를 부여했습니다'):format(f.name), false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionWarningRevokeAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    local fid = math.floor(tonumber(data and data.factionId) or 0)
    local wid = math.floor(tonumber(data and data.warningId) or 0)
    if fid <= 0 or wid <= 0 then return end
    local aff = MySQL.update.await([[
        UPDATE cookie_faction_warning SET active=0, revoked_at=NOW()
        WHERE id=? AND faction_id=? AND citizenid IS NULL AND active=1
    ]], { wid, fid })
    if not aff or aff < 1 then return anotify(src, '활성 경고를 찾을 수 없습니다', true) end
    anotify(src, '팩션 경고를 회수했습니다', false)
    sendList(src)
end)

RegisterNetEvent('cookie_admin:server:factionForceOffDutyAdmin', function(data)
    local src = source
    local admin = CookieAdminTeamAuth(src, 'faction')
    if not admin then return anotify(src, '팩션 관리 권한이 없습니다', true) end
    local fid = math.floor(tonumber(data and data.factionId) or 0)
    local cid = tostring(data and data.citizenid or '')
    local f = factionAdminRow(fid)
    if not f or cid == '' then return end
    if not isGovType(f.faction_type) then return anotify(src, '정부 팩션만 강제 퇴근할 수 있습니다', true) end
    local mem = MySQL.single.await(
        "SELECT duty FROM cookie_faction_member WHERE faction_id=? AND citizenid=? AND status='active' LIMIT 1",
        { fid, cid })
    if not mem then return anotify(src, '팩션원을 찾을 수 없습니다', true) end
    if not (mem.duty == 1 or mem.duty == true) then return anotify(src, '이미 퇴근 상태입니다', true) end

    local ok, err = CookieFactionForceOffDuty(cid, admin.admin_name or '관리자')
    if not ok then return anotify(src, err or '강제 퇴근 실패', true) end
    anotify(src, ('%s 팩션원을 강제 퇴근 처리했습니다'):format(f.name), false)
    sendList(src)
end)
