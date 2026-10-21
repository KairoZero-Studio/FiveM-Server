

local function flog(...)
    if Config and Config.Debug then  end
end

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_key` VARCHAR(40) NOT NULL UNIQUE,
          `faction_type` VARCHAR(20) NOT NULL,
          `job_name` VARCHAR(40) NOT NULL,
          `name` VARCHAR(60) NOT NULL,
          `label_short` VARCHAR(20) NULL,
          `color` VARCHAR(10) NULL,
          `budget` BIGINT NOT NULL DEFAULT 0,
          `leader_citizenid` VARCHAR(50) NULL,
          `spawn_json` TEXT NULL,
          `is_active` TINYINT(1) NOT NULL DEFAULT 1,
          `created_by` VARCHAR(255) NULL,
          `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          INDEX `idx_job` (`job_name`),
          INDEX `idx_type` (`faction_type`)
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_rank` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NOT NULL,
          `grade` INT NOT NULL,
          `rank_name` VARCHAR(40) NOT NULL,
          `is_leader` TINYINT(1) NOT NULL DEFAULT 0,
          `is_officer` TINYINT(1) NOT NULL DEFAULT 0,
          `salary` INT NOT NULL DEFAULT 0,
          `sort_order` INT NOT NULL DEFAULT 0,
          UNIQUE KEY `uq_faction_grade` (`faction_id`, `grade`),
          CONSTRAINT `fk_rank_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_member` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NOT NULL,
          `citizenid` VARCHAR(50) NOT NULL,
          `grade` INT NOT NULL DEFAULT 0,
          `invited_by` VARCHAR(50) NULL,
          `status` VARCHAR(16) NOT NULL DEFAULT 'active',
          `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE KEY `uq_faction_member` (`faction_id`, `citizenid`),
          INDEX `idx_citizenid` (`citizenid`),
          CONSTRAINT `fk_member_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_budget_log` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NOT NULL,
          `delta` BIGINT NOT NULL,
          `balance_after` BIGINT NOT NULL,
          `category` VARCHAR(24) NULL,
          `reason` VARCHAR(120) NULL,
          `actor_citizenid` VARCHAR(50) NULL,
          `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_faction` (`faction_id`),
          CONSTRAINT `fk_budget_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_detention` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NOT NULL,
          `officer_citizenid` VARCHAR(50) NULL,
          `target_citizenid` VARCHAR(50) NULL,
          `target_name` VARCHAR(60) NULL,
          `charge` VARCHAR(120) NULL,
          `fine_amount` INT NOT NULL DEFAULT 0,
          `jail_seconds` INT NOT NULL DEFAULT 0,
          `note` TEXT NULL,
          `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_faction` (`faction_id`),
          CONSTRAINT `fk_detention_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_vehicle` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NOT NULL,
          `model` VARCHAR(40) NOT NULL,
          `plate` VARCHAR(16) NULL,
          `min_grade` INT NOT NULL DEFAULT 0,
          `added_by` VARCHAR(60) NULL,
          `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_faction` (`faction_id`),
          CONSTRAINT `fk_fveh_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_log` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NULL,
          `action` VARCHAR(40) NOT NULL,
          `actor` VARCHAR(120) NULL,
          `detail` TEXT NULL,
          `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_faction` (`faction_id`)
        )
    ]], {})

    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `image_url` VARCHAR(255) NULL", {})
    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `image_file` VARCHAR(80) NULL", {})

    MySQL.query.await("ALTER TABLE `cookie_faction_member` ADD COLUMN IF NOT EXISTS `department` VARCHAR(40) NULL", {})
    MySQL.query.await("ALTER TABLE `cookie_faction_member` ADD COLUMN IF NOT EXISTS `duty` TINYINT(1) NOT NULL DEFAULT 0", {})

    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `emoji` VARCHAR(64) NULL", {})
    MySQL.query.await("ALTER TABLE `cookie_faction` MODIFY COLUMN `emoji` VARCHAR(64) NULL", {})

    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `tag_name` VARCHAR(20) NULL", {})

    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `garage_key` VARCHAR(40) NULL", {})

    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `disposition` VARCHAR(40) NULL", {})
    MySQL.query.await("ALTER TABLE `cookie_faction` ADD COLUMN IF NOT EXISTS `duty` VARCHAR(120) NULL", {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_faction_shop` (
          `id` INT AUTO_INCREMENT PRIMARY KEY,
          `faction_id` INT NOT NULL,
          `model` VARCHAR(40) NOT NULL,
          `label` VARCHAR(60) NULL,
          `price` BIGINT NOT NULL DEFAULT 0,
          `min_grade` INT NOT NULL DEFAULT 0,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `added_by` VARCHAR(60) NULL,
          `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          INDEX `idx_faction` (`faction_id`),
          CONSTRAINT `fk_shop_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
        )
    ]], {})

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cookie_vehicle_image` (
          `model` VARCHAR(40) NOT NULL PRIMARY KEY,
          `image` MEDIUMTEXT NOT NULL,
          `updated_by` VARCHAR(60) NULL,
          `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]], {})

    MySQL.update.await([[
        UPDATE cookie_faction SET garage_key = 'cookie_lspd'
        WHERE faction_type = 'police' AND (garage_key IS NULL OR garage_key = '')
    ]], {})

end)

-- 과거 버전의 중복 소속은 가장 최근 멤버십 1개만 남기고 삭제한다.
CreateThread(function()
    Wait(2500)
    pcall(function()
        MySQL.query.await([[
            DELETE oldm
            FROM cookie_faction_member oldm
            JOIN cookie_faction_member newm
              ON newm.citizenid = oldm.citizenid
             AND newm.id > oldm.id
        ]], {})
    end)
end)

CreateThread(function()
    Wait(5000)

    local okD, dedup = pcall(function()
        return MySQL.update.await([[
            DELETE v FROM cookie_faction_vehicle v
            JOIN cookie_faction_vehicle keep
              ON keep.faction_id = v.faction_id
             AND keep.model = v.model
             AND keep.id < v.id
        ]], {})
    end)
    if okD and dedup and dedup > 0 then

    end

    local okP, dedupV = pcall(function()
        return MySQL.update.await([[
            DELETE pv FROM player_vehicles pv
            JOIN player_vehicles keep
              ON keep.garage = pv.garage
             AND keep.vehicle = pv.vehicle
             AND keep.citizenid = pv.citizenid
             AND keep.id < pv.id
            WHERE pv.citizenid LIKE 'FACTION\_%'
        ]], {})
    end)
    if okP and dedupV and dedupV > 0 then

    end

    pcall(function()
        MySQL.query.await([[
            ALTER TABLE `cookie_faction_vehicle`
            ADD UNIQUE KEY IF NOT EXISTS `uq_faction_model` (`faction_id`, `model`)
        ]], {})
    end)

    local ok, orphans = pcall(function()
        return MySQL.query.await([[
            SELECT v.id, v.faction_id, v.model, f.garage_key
            FROM cookie_faction_vehicle v
            JOIN cookie_faction f ON f.id = v.faction_id
            LEFT JOIN player_vehicles pv
                   ON pv.garage = f.garage_key AND pv.vehicle = v.model
            WHERE f.garage_key IS NOT NULL AND f.garage_key <> '' AND pv.id IS NULL
        ]], {})
    end)
    if not ok or not orphans or #orphans == 0 then return end

    local fixed, failed = 0, 0
    for _, o in ipairs(orphans) do
        local ownerCid = 'FACTION_' .. o.faction_id
        CookieEnsureFactionOwner(ownerCid)

        local okv, vid = pcall(function()
            return exports.qbx_vehicles:CreatePlayerVehicle({
                model = o.model,
                citizenid = ownerCid,
                garage = o.garage_key,
            })
        end)

        if okv and vid then
            fixed = fixed + 1

        else
            failed = failed + 1

        end
    end

end)

CreateThread(function()
    Wait(7000)

    local ok, n = pcall(function()
        return MySQL.update.await([[
            UPDATE player_vehicles pv
            JOIN cookie_faction f ON f.garage_key = pv.garage
            SET pv.state = 1
            WHERE pv.state <> 1
        ]], {})
    end)

    if not ok then

        return
    end

    if (n or 0) > 0 then

    else

    end
end)

function CookieEnsureFactionOwner(cid)
    if not cid or cid == '' then return false end

    local exists = MySQL.single.await('SELECT 1 AS x FROM players WHERE citizenid = ?', { cid })
    if exists then return true end

    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO players
              (citizenid, license, name, money, charinfo, job, gang, position, metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            cid,
            'faction:' .. cid,
            cid,
            json.encode({ cash = 0, bank = 0 }),
            json.encode({ firstname = cid, lastname = '' }),
            json.encode({ name = 'unemployed', grade = { level = 0, name = 'Freelancer' } }),
            json.encode({}),
            json.encode({ x = 0.0, y = 0.0, z = 0.0 }),
            json.encode({}),
        })
    end)

    if not ok then

        return false
    end

    return true
end

function CookieFactionLog(factionId, action, actor, detail)
end

function CookieFactionIsGovType(factionType)
    for _, ft in ipairs(Config.FactionTypes or {}) do
        if ft.key == factionType then return ft.gov == true end
    end
    return false
end

function CookieFactionSeedRanks(factionId, factionType)
    local preset = (Config.FactionRankPreset and Config.FactionRankPreset[factionType])
        or (Config.FactionRankPreset and Config.FactionRankPreset.default)
    if not preset then return 0 end
    local n = 0
    for i, r in ipairs(preset) do
        MySQL.query.await([[
            INSERT INTO cookie_faction_rank (faction_id, grade, rank_name, is_leader, is_officer, salary, sort_order)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE rank_name = VALUES(rank_name)
        ]], { factionId, r.grade, r.name, r.leader and 1 or 0, r.officer and 1 or 0, CookieFactionIsGovType(factionType) and (r.salary or 0) or 0, i })
        n = n + 1
    end

    return n
end

local function buildQbxGrades(factionId)
    local f = MySQL.single.await('SELECT faction_type FROM cookie_faction WHERE id = ?', { factionId })
    local isGov = f and CookieFactionIsGovType(f.faction_type) or false
    local rows = MySQL.query.await(
        'SELECT grade, rank_name, salary FROM cookie_faction_rank WHERE faction_id = ? ORDER BY grade', { factionId }
    ) or {}
    local grades = {}
    for _, r in ipairs(rows) do
        grades[r.grade] = { name = r.rank_name, payment = isGov and (tonumber(r.salary) or 0) or 0 }
    end
    return grades, #rows, isGov
end

function CookieFactionEnsureJob(factionId)
    local f = MySQL.single.await('SELECT job_name, name, faction_type FROM cookie_faction WHERE id = ?', { factionId })
    if not f then return false, '팩션 없음' end

    local grades, cnt, isGov = buildQbxGrades(factionId)
    if cnt == 0 then return false, '계급이 없습니다' end

    local existing = exports.qbx_core:GetJob(f.job_name)
    if not existing then
        local ok, err = exports.qbx_core:CreateJob(f.job_name, {
            label = f.name,
            defaultDuty = not isGov,
            offDutyPay = false,
            grades = grades,
        }, true)
        if not ok then return false, err end
    else
        -- DB 계급/급여가 재시작 후에도 Qbox 런타임에 그대로 반영되게 동기화한다.
        for grade, def in pairs(grades) do
            pcall(function()
                exports.qbx_core:UpsertJobGrade(f.job_name, grade, def, true)
            end)
        end
    end

    return true, nil
end

local function dropCivilJobIfAny(citizenid)
    local src = nil
    for _, pid in ipairs(GetPlayers()) do
        local s = tonumber(pid)
        local p = s and exports.qbx_core:GetPlayer(s)
        if p and p.PlayerData and p.PlayerData.citizenid == citizenid then src = s break end
    end
    if not src then return end

    local job = exports.qbx_core:GetPlayer(src).PlayerData.job
    local def = job and job.name and (Config.CivilJobs or {})[job.name]
    if not def or not def.quitEvent then return end

    TriggerEvent(def.quitEvent, src, '팩션 가입')

end

function CookieClearAllJobs(citizenid, exceptJob)
    if not citizenid then return end

    local p = exports.qbx_core:GetPlayerByCitizenId(citizenid)
        or exports.qbx_core:GetOfflinePlayer(citizenid)
    if not p or not p.PlayerData then return end

    for jobName in pairs(p.PlayerData.jobs or {}) do
        if jobName ~= exceptJob and jobName ~= 'unemployed' then
            local ok, err = pcall(function()
                exports.qbx_core:RemovePlayerFromJob(citizenid, jobName)
            end)

        end
    end
end

exports('clearAllJobs', function(citizenid, exceptJob)
    return CookieClearAllJobs(citizenid, exceptJob)
end)

function CookieFactionSyncMemberJob(citizenid, jobName, grade)
    if not citizenid or not jobName then return false end

    dropCivilJobIfAny(citizenid)
    CookieClearAllJobs(citizenid, jobName)

    local ok, err = pcall(function()
        exports.qbx_core:AddPlayerToJob(citizenid, jobName, grade or 0)
        exports.qbx_core:SetPlayerPrimaryJob(citizenid, jobName)
    end)
    if not ok then return false end

    -- 계급 변경/리더 변경 시 Qbox가 duty 값을 기본값으로 되돌리지 않게 DB 근무상태를 다시 적용한다.
    local member = MySQL.single.await([[
        SELECT m.duty, f.faction_type
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id=m.faction_id AND f.is_active=1
        WHERE m.citizenid=? AND f.job_name=? AND m.status='active' LIMIT 1
    ]], { citizenid, jobName })
    local src = nil
    for _, pid in ipairs(GetPlayers()) do
        local s = tonumber(pid)
        local op = s and exports.qbx_core:GetPlayer(s) or nil
        if op and op.PlayerData and op.PlayerData.citizenid == citizenid then src = s break end
    end
    if src and member then
        local player = exports.qbx_core:GetPlayer(src)
        if player and player.Functions and player.Functions.SetJobDuty then
            local desired = CookieFactionIsGovType(member.faction_type)
                and (member.duty == 1 or member.duty == true)
                or true
            pcall(function() player.Functions.SetJobDuty(desired) end)
        end
    end
    return true
end

function CookieFactionClearMemberJob(citizenid)
    if not citizenid then return false end

    CookieClearAllJobs(citizenid, nil)

    local ok = pcall(function()
        exports.qbx_core:SetPlayerPrimaryJob(citizenid, 'unemployed')
    end)
    return ok
end


local function cookieFactionSourceOfCitizen(citizenid)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local player = src and exports.qbx_core:GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.citizenid == citizenid then
            return src
        end
    end
    return nil
end

-- 한 캐릭터는 하나의 팩션 소속만 유지한다.
-- keepFactionId가 있으면 해당 팩션만 남기고, nil이면 소속을 전부 제거한다.
function CookieFactionPurgeMembership(citizenid, keepFactionId)
    if not citizenid or citizenid == '' then return false end
    keepFactionId = tonumber(keepFactionId)

    local oldRows = MySQL.query.await(
        'SELECT faction_id FROM cookie_faction_member WHERE citizenid = ?',
        { citizenid }
    ) or {}

    local removingOld = false
    for _, row in ipairs(oldRows) do
        if not keepFactionId or tonumber(row.faction_id) ~= keepFactionId then
            removingOld = true
            break
        end
    end

    if removingOld then
        if keepFactionId then
            MySQL.update.await(
                'UPDATE cookie_faction SET leader_citizenid = NULL WHERE leader_citizenid = ? AND id <> ?',
                { citizenid, keepFactionId }
            )
            MySQL.query.await(
                'DELETE FROM cookie_faction_member WHERE citizenid = ? AND faction_id <> ?',
                { citizenid, keepFactionId }
            )
        else
            MySQL.update.await(
                'UPDATE cookie_faction SET leader_citizenid = NULL WHERE leader_citizenid = ?',
                { citizenid }
            )
            MySQL.query.await(
                'DELETE FROM cookie_faction_member WHERE citizenid = ?',
                { citizenid }
            )
        end

        -- 예전 팩션에서 지급받은 근무 장비도 같이 정리한다.
        local src = cookieFactionSourceOfCitizen(citizenid)
        local okRows, loadoutRows = pcall(function()
            return MySQL.query.await(
                'SELECT item, count FROM cookie_faction_loadout WHERE citizenid = ?',
                { citizenid }
            ) or {}
        end)
        if okRows and type(loadoutRows) == 'table' then
            if src then
                for _, item in ipairs(loadoutRows) do
                    local count = math.max(0, math.floor(tonumber(item.count) or 0))
                    if count > 0 and item.item then
                        pcall(function()
                            exports.ox_inventory:RemoveItem(src, item.item, count)
                        end)
                    end
                end
                TriggerClientEvent('cookie_admin:client:setArmor', src, 0)
            end
            pcall(function()
                MySQL.query.await(
                    'DELETE FROM cookie_faction_loadout WHERE citizenid = ?',
                    { citizenid }
                )
            end)
        end
    end

    if not keepFactionId then
        CookieFactionClearMemberJob(citizenid)
    end

    return removingOld
end

exports('purgeFactionMembership', function(citizenid, keepFactionId)
    return CookieFactionPurgeMembership(citizenid, keepFactionId)
end)

function CookieNormalizeFactionColor(value)
    local c = tostring(value or ''):upper():gsub('%s+', '')
    if c:match('^#%x%x%x%x%x%x$') then return c end
    return '#FFB800'
end

function CookieFactionMemberOf(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    local cid = player.PlayerData and player.PlayerData.citizenid
    if not cid then return nil end

    local row = MySQL.single.await([[
        SELECT f.id, f.faction_key, f.faction_type, f.name, f.color, f.job_name, f.leader_citizenid,
               f.image_url, f.image_file, f.emoji, f.tag_name,
               m.grade, m.duty, r.rank_name, r.is_leader, r.is_officer
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id = m.faction_id AND f.is_active = 1
        LEFT JOIN cookie_faction_rank r ON r.faction_id = f.id AND r.grade = m.grade
        WHERE m.citizenid = ? AND m.status = 'active'
        LIMIT 1
    ]], { cid })
    if not row then return nil end

    local rankName = row.rank_name
    if rankName == '-' then rankName = nil end
    if not rankName or rankName == '' then
        local job = player.PlayerData and player.PlayerData.job or nil
        if job and job.name == row.job_name and job.grade then
            rankName = job.grade.name or job.grade.label
        end
    end
    if (not rankName or rankName == '') and row.leader_citizenid == cid then
        local lr = MySQL.single.await([[
            SELECT rank_name FROM cookie_faction_rank
            WHERE faction_id = ? AND is_leader = 1 ORDER BY grade DESC LIMIT 1
        ]], { row.id })
        rankName = lr and lr.rank_name or rankName
    end
    if not rankName or rankName == '' then rankName = ('G%s'):format(tostring(row.grade or 0)) end

    return {
        id = row.id,
        key = row.faction_key,
        type = row.faction_type,
        name = row.name,
        color = CookieNormalizeFactionColor(row.color),
        imageUrl = row.image_url,
        imageFile = row.image_file,
        emoji = row.emoji,
        tagName = row.tag_name,
        jobName = row.job_name,
        citizenid = cid,
        grade = row.grade,
        duty = (row.duty == 1 or row.duty == true),
        rankName = rankName,
        isLeader = (row.is_leader == 1 or row.is_leader == true),
        isOfficer = (row.is_officer == 1 or row.is_officer == true),
    }
end

function CookieCivilJobOf(src)
    local p = exports.qbx_core:GetPlayer(src)
    local job = p and p.PlayerData and p.PlayerData.job
    if not job or not job.name then return nil end

    local def = (Config.CivilJobs or {})[job.name]
    if not def then return nil end

    return def, job.name, (job.onduty == true)
end

function CookieCivilLevel(src, skillKey)
    if not skillKey then return 1 end
    local ok, lv = pcall(function() return exports.cookie_admin:getCivilLevel(src, skillKey) end)
    if ok and tonumber(lv) then return tonumber(lv) end
    return 1
end

function CookieJobDisplay(src)
    local m = CookieFactionMemberOf(src)
    if m then
        local rank = m.rankName
        if not rank or rank == '' or rank == '-' then return m.name end
        return ('%s %s'):format(m.name, rank)
    end

    local def = CookieCivilJobOf(src)
    if def then
        return def.label
    end

    return '백수'
end

exports('getJobDisplay', function(src)
    return CookieJobDisplay(src)
end)

exports('getFactionMember', function(src)
    return CookieFactionMemberOf(src)
end)

exports('isGovernmentFactionType', function(factionType)
    return CookieFactionIsGovType(factionType)
end)

exports('getCivilJob', function(src)
    local def, name, onDuty = CookieCivilJobOf(src)
    if not def then return nil end
    return {
        key    = name,
        label  = def.label,
        emoji  = def.emoji,
        skill  = def.skill,
        level  = CookieCivilLevel(src, def.skill),
        onDuty = onDuty and true or false,
    }
end)

RegisterNetEvent('cookie_admin:server:requestJobDisplay', function()
    local src = source
    TriggerClientEvent('cookie_admin:client:jobDisplay', src, CookieJobDisplay(src))
end)

function CookiePushJobDisplay(src)
    if not src then return end
    TriggerClientEvent('cookie_admin:client:jobDisplay', src, CookieJobDisplay(src))
end

AddEventHandler('cookie_admin:server:jobDisplayDirty', function(src)
    if src then CookiePushJobDisplay(src) end
end)

function CookieBuildFactionPane(src)
    local m = CookieFactionMemberOf(src)
    if not m then return nil end

    local pane = {
        id = m.id,
        name = m.name,
        type = m.type,
        color = m.color,
        imageUrl = m.imageUrl,
        imageFile = m.imageFile,
        myGrade = m.grade,
        myRank = m.rankName,
        isLeader = m.isLeader,
        isOfficer = m.isOfficer,
        isGov = CookieFactionIsGovType(m.type),
    }

    if m.isLeader or m.isOfficer then
        local f = MySQL.single.await('SELECT budget FROM cookie_faction WHERE id = ?', { m.id })
        pane.budget = (f and f.budget) or 0

        local okL, blog = pcall(function()
            return MySQL.query.await([[
                SELECT bl.delta, bl.balance_after, bl.category, bl.reason, bl.created_at,
                       bl.actor_citizenid, cu.nickname AS actor_nick
                FROM cookie_faction_budget_log bl
                LEFT JOIN players p ON p.citizenid = bl.actor_citizenid
                LEFT JOIN cookie_user cu
                       ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
                        = SUBSTRING_INDEX(p.license, ':', -1)  COLLATE utf8mb4_unicode_ci
                WHERE bl.faction_id = ?
                ORDER BY bl.id DESC LIMIT 20
            ]], { m.id })
        end)
        pane.budgetLog = (okL and blog) or {}
    end

    local MEMBER_SQL = [[
        SELECT m.citizenid, m.grade, %s r.rank_name, cu.nickname, cu.gobun
        FROM cookie_faction_member m
        LEFT JOIN cookie_faction_rank r ON r.faction_id = m.faction_id AND r.grade = m.grade
        LEFT JOIN players p ON p.citizenid = m.citizenid
        LEFT JOIN cookie_user cu
               ON SUBSTRING_INDEX(cu.license, ':', -1) COLLATE utf8mb4_unicode_ci
                = SUBSTRING_INDEX(p.license, ':', -1)  COLLATE utf8mb4_unicode_ci
        WHERE m.faction_id = ? AND m.status = 'active'
        ORDER BY m.grade DESC, m.joined_at ASC
    ]]

    local ok, rows = pcall(function()
        return MySQL.query.await(MEMBER_SQL:format('m.department,'), { m.id })
    end)
    if not ok then

        local ok2, rows2 = pcall(function()
            return MySQL.query.await(MEMBER_SQL:format(''), { m.id })
        end)
        rows = ok2 and rows2 or {}
        if not ok2 then  end
    end
    pane.members = rows or {}

    local deps = (Config.FactionDepartments and Config.FactionDepartments[m.type])
        or (Config.FactionDepartments and Config.FactionDepartments.default) or {}
    pane.departments = deps

    pane.ranks = MySQL.query.await([[
        SELECT grade, rank_name, is_leader, is_officer, salary
        FROM cookie_faction_rank WHERE faction_id = ? ORDER BY grade DESC
    ]], { m.id }) or {}

    local okV, veh = pcall(function()
        return MySQL.query.await([[
            SELECT v.model, v.plate, v.min_grade, s.label
            FROM cookie_faction_vehicle v
            LEFT JOIN cookie_faction_shop s ON s.faction_id = v.faction_id AND s.model = v.model
            WHERE v.faction_id = ? ORDER BY v.min_grade, v.model
        ]], { m.id })
    end)
    pane.vehicles = (okV and veh) or {}

    pane.detentions = MySQL.query.await([[
        SELECT target_name, charge, fine_amount, jail_seconds, created_at
        FROM cookie_faction_detention WHERE faction_id = ?
        ORDER BY id DESC LIMIT 20
    ]], { m.id }) or {}

    if m.isLeader or m.isOfficer then
        local okS, shop = pcall(function()
            return MySQL.query.await([[
                SELECT s.id, s.model, s.label, s.price, s.min_grade, vi.image
                FROM cookie_faction_shop s
                LEFT JOIN cookie_vehicle_image vi ON vi.model = s.model
                WHERE s.faction_id = ? AND s.active = 1 ORDER BY s.price ASC
            ]], { m.id })
        end)
        pane.shop = (okS and shop) or {}
    end

    return pane
end

RegisterNetEvent('cookie_admin:server:saveVehicleImage', function(model, dataUrl)
    local src = source
    if not CookieAdminTeamAuth or not CookieAdminTeamAuth(src, 'faction') then

        return
    end

    model = tostring(model or ''):lower():gsub('[^%w_]', '')
    if #model < 2 then return end

    if type(dataUrl) ~= 'string' or not dataUrl:match('^data:image/') then
        TriggerClientEvent('cookie_admin:client:notify', src, '이미지 형식이 올바르지 않습니다', true)
        return
    end

    if #dataUrl > 400000 then
        TriggerClientEvent('cookie_admin:client:notify', src, '이미지가 너무 큽니다', true)
        return
    end

    MySQL.query.await([[
        INSERT INTO cookie_vehicle_image (model, image, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE image = VALUES(image), updated_by = VALUES(updated_by)
    ]], { model, dataUrl, 'admin' })

    TriggerClientEvent('cookie_admin:client:notify', src, ('%s 썸네일을 저장했습니다'):format(model), false)
end)

exports('getFactionOf', function(src)
    return CookieFactionMemberOf(src)
end)

local BUDGET_MAX = 1000000000

local function fnotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

local function factionBudget(factionId)
    local row = MySQL.single.await('SELECT budget FROM cookie_faction WHERE id = ?', { factionId })
    return (row and tonumber(row.budget)) or 0
end

local function budgetLedger(factionId, delta, balanceAfter, category, reason, actorCid)
end

local function budgetGate(src)
    local m = CookieFactionMemberOf(src)
    if not m then return nil, '팩션 소속이 아닙니다' end
    if not (m.isLeader or m.isOfficer) then return nil, '간부 이상만 예산을 다룰 수 있습니다' end
    return m, nil
end

local function pushFactionPane(src)
    TriggerClientEvent('cookie_admin:client:factionPane', src, CookieBuildFactionPane(src))
end

RegisterNetEvent('cookie_admin:server:factionDeposit', function(amount, reason)
    local src = source
    local m, err = budgetGate(src)
    if not m then return fnotify(src, err, true) end

    local amt = math.floor(tonumber(amount) or 0)
    if amt <= 0 or amt > BUDGET_MAX then return fnotify(src, '금액이 올바르지 않습니다', true) end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    if not player.Functions.RemoveMoney('bank', amt, '팩션 예산 입금') then
        return fnotify(src, '계좌 잔액이 부족합니다', true)
    end

    MySQL.update.await('UPDATE cookie_faction SET budget = budget + ? WHERE id = ?', { amt, m.id })
    local bal = factionBudget(m.id)

    fnotify(src, ('예산에 $%s 입금했습니다 (잔액 $%s)'):format(comma(amt), comma(bal)), false)
    pushFactionPane(src)
end)

RegisterNetEvent('cookie_admin:server:factionWithdraw', function(amount, reason)
    local src = source
    local m, err = budgetGate(src)
    if not m then return fnotify(src, err, true) end

    local amt = math.floor(tonumber(amount) or 0)
    if amt <= 0 or amt > BUDGET_MAX then return fnotify(src, '금액이 올바르지 않습니다', true) end

    local why = type(reason) == 'string' and reason:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #why < 2 then return fnotify(src, '출금 사유를 입력하세요', true) end
    why = why:sub(1, 120)

    local affected = MySQL.update.await(
        'UPDATE cookie_faction SET budget = budget - ? WHERE id = ? AND budget >= ?',
        { amt, m.id, amt }
    )
    if not affected or affected < 1 then
        return fnotify(src, '팩션 예산이 부족합니다', true)
    end

    local bal = factionBudget(m.id)

    local player = exports.qbx_core:GetPlayer(src)
    if player then player.Functions.AddMoney('bank', amt, '팩션 예산 출금') end

    fnotify(src, ('예산에서 $%s 출금했습니다 (잔액 $%s)'):format(comma(amt), comma(bal)), false)
    pushFactionPane(src)
end)

function CookieFactionAddIncome(factionId, amount, category, reason, actorCid)
    local amt = math.floor(tonumber(amount) or 0)
    if not factionId or amt <= 0 then return false, 0 end
    MySQL.update.await('UPDATE cookie_faction SET budget = budget + ? WHERE id = ?', { amt, factionId })
    local bal = factionBudget(factionId)

    return true, bal
end

exports('addFactionIncome', function(factionId, amount, category, reason, actorCid)
    return CookieFactionAddIncome(factionId, amount, category, reason, actorCid)
end)

function CookieFactionSpend(factionId, amount, category, reason, actorCid)
    local amt = math.floor(tonumber(amount) or 0)
    if not factionId or amt <= 0 then return false, 0 end

    local aff = MySQL.update.await(
        'UPDATE cookie_faction SET budget = budget - ? WHERE id = ? AND budget >= ?',
        { amt, factionId, amt })
    if not aff or aff < 1 then return false, factionBudget(factionId) end

    local bal = factionBudget(factionId)

    return true, bal
end

function CookieFactionBudget(factionId)
    return factionBudget(factionId)
end

function CookiePushFactionPane(src)
    TriggerClientEvent('cookie_admin:client:factionPane', src, CookieBuildFactionPane(src))
end

function CookieFactionRecordDetention(factionId, officerCid, targetCid, targetName, charge, fine, jailSeconds, note)
    if not factionId then return false end
    local fineAmt = math.floor(tonumber(fine) or 0)
    MySQL.insert.await([[
        INSERT INTO cookie_faction_detention
          (faction_id, officer_citizenid, target_citizenid, target_name, charge, fine_amount, jail_seconds, note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { factionId, officerCid, targetCid, targetName, charge, fineAmt, math.floor(tonumber(jailSeconds) or 0), note })

    if fineAmt > 0 then

        CookieFactionAddIncome(factionId, fineAmt, 'fine_income', charge or '', officerCid)
    end

    return true
end

exports('recordDetention', function(factionId, officerCid, targetCid, targetName, charge, fine, jailSeconds, note)
    return CookieFactionRecordDetention(factionId, officerCid, targetCid, targetName, charge, fine, jailSeconds, note)
end)

RegisterNetEvent('cookie_admin:server:requestFactionPane', function()
    local src = source
    TriggerClientEvent('cookie_admin:client:factionPane', src, CookieBuildFactionPane(src))
end)

local function facLeader(src)
    local m = CookieFactionMemberOf(src)
    if not m or not m.isLeader then return nil, '리더만 가능합니다' end
    return m, nil
end

local function facOfficer(src)
    local m = CookieFactionMemberOf(src)
    if not m or not (m.isLeader or m.isOfficer) then return nil, '간부 이상만 가능합니다' end
    return m, nil
end

local function srcOfCitizen(cid)
    for _, pid in ipairs(GetPlayers()) do
        local s = tonumber(pid)
        local p = exports.qbx_core:GetPlayer(s)
        if p and p.PlayerData and p.PlayerData.citizenid == cid then return s end
    end
    return nil
end

RegisterNetEvent('cookie_admin:server:facRankSave', function(data)
    local src = source
    if true then return fnotify(src, '계급/팩션원 관리는 F3 > 서버 팩션 관리에서만 가능합니다', true) end
    local m, err = facLeader(src)
    if not m then return fnotify(src, err, true) end
    if type(data) ~= 'table' then return end

    local grade = math.floor(tonumber(data.grade) or -1)
    if grade < 0 or grade > 50 then return fnotify(src, '계급 번호는 0~50입니다', true) end

    local name = type(data.name) == 'string' and data.name:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #name < 1 then return fnotify(src, '계급명을 입력하세요', true) end
    name = name:sub(1, 40)

    local salary = math.max(0, math.floor(tonumber(data.salary) or 0))
    local isOfficer = data.isOfficer and 1 or 0
    local isLeader = data.isLeader and 1 or 0

    local oldGrade = tonumber(data.oldGrade)
    oldGrade = oldGrade and math.floor(oldGrade) or nil

    if oldGrade and oldGrade ~= grade then

        local taken = MySQL.single.await(
            'SELECT 1 AS x FROM cookie_faction_rank WHERE faction_id = ? AND grade = ?', { m.id, grade })
        if taken then return fnotify(src, ('계급 번호 %d는 이미 사용 중입니다'):format(grade), true) end

        MySQL.update.await([[
            UPDATE cookie_faction_rank
            SET grade = ?, rank_name = ?, is_leader = ?, is_officer = ?, salary = ?, sort_order = ?
            WHERE faction_id = ? AND grade = ?
        ]], { grade, name, isLeader, isOfficer, salary, grade, m.id, oldGrade })

        MySQL.update.await(
            'UPDATE cookie_faction_member SET grade = ? WHERE faction_id = ? AND grade = ?',
            { grade, m.id, oldGrade })

        pcall(function()
            exports.qbx_core:UpsertJobGrade(m.jobName, grade, { name = name, payment = salary }, true)
        end)

        local moved = MySQL.query.await(
            "SELECT citizenid FROM cookie_faction_member WHERE faction_id = ? AND grade = ? AND status = 'active'",
            { m.id, grade }) or {}
        for _, mm in ipairs(moved) do
            CookieFactionSyncMemberJob(mm.citizenid, m.jobName, grade)
            local ts = srcOfCitizen(mm.citizenid)
            if ts then CookiePushJobDisplay(ts) end
        end

        pcall(function() exports.qbx_core:RemoveJobGrade(m.jobName, oldGrade, true) end)

        fnotify(src, ('계급 "%s"를 G%d → G%d 로 옮겼습니다'):format(name, oldGrade, grade), false)
        pushFactionPane(src)
        return
    end

    MySQL.query.await([[
        INSERT INTO cookie_faction_rank (faction_id, grade, rank_name, is_leader, is_officer, salary, sort_order)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          rank_name = VALUES(rank_name), is_leader = VALUES(is_leader),
          is_officer = VALUES(is_officer), salary = VALUES(salary)
    ]], { m.id, grade, name, isLeader, isOfficer, salary, grade })

    pcall(function()
        exports.qbx_core:UpsertJobGrade(m.jobName, grade, { name = name, payment = salary }, true)
    end)

    fnotify(src, ('계급 "%s"(%d)를 저장했습니다'):format(name, grade), false)
    pushFactionPane(src)
end)

RegisterNetEvent('cookie_admin:server:facRankDelete', function(grade)
    local src = source
    if true then return fnotify(src, '계급/팩션원 관리는 F3 > 서버 팩션 관리에서만 가능합니다', true) end
    local m, err = facLeader(src)
    if not m then return fnotify(src, err, true) end

    local g = math.floor(tonumber(grade) or -1)
    if g < 0 then return end

    local row = MySQL.single.await(
        'SELECT rank_name, is_leader FROM cookie_faction_rank WHERE faction_id = ? AND grade = ?', { m.id, g })
    if not row then return fnotify(src, '계급을 찾을 수 없습니다', true) end
    if row.is_leader == 1 or row.is_leader == true then
        return fnotify(src, '리더 계급은 삭제할 수 없습니다', true)
    end

    local used = MySQL.single.await(
        "SELECT COUNT(*) AS n FROM cookie_faction_member WHERE faction_id = ? AND grade = ? AND status = 'active'",
        { m.id, g })
    if used and tonumber(used.n) > 0 then
        return fnotify(src, ('이 계급에 팩션원 %d명이 있습니다 먼저 이동시키세요'):format(tonumber(used.n)), true)
    end

    MySQL.query.await('DELETE FROM cookie_faction_rank WHERE faction_id = ? AND grade = ?', { m.id, g })
    pcall(function() exports.qbx_core:RemoveJobGrade(m.jobName, g, true) end)

    fnotify(src, ('계급 "%s"를 삭제했습니다'):format(row.rank_name), false)
    pushFactionPane(src)
end)

RegisterNetEvent('cookie_admin:server:facMemberSave', function(data)
    local src = source
    if true then return fnotify(src, '계급/팩션원 관리는 F3 > 서버 팩션 관리에서만 가능합니다', true) end
    local m, err = facOfficer(src)
    if not m then return fnotify(src, err, true) end
    if type(data) ~= 'table' or type(data.citizenid) ~= 'string' then return end

    local cid = data.citizenid
    local target = MySQL.single.await(
        "SELECT grade FROM cookie_faction_member WHERE faction_id = ? AND citizenid = ? AND status = 'active'",
        { m.id, cid })
    if not target then return fnotify(src, '팩션원을 찾을 수 없습니다', true) end

    local grade = math.floor(tonumber(data.grade) or -1)
    local rank = MySQL.single.await(
        'SELECT rank_name, is_leader FROM cookie_faction_rank WHERE faction_id = ? AND grade = ?', { m.id, grade })
    if not rank then return fnotify(src, '없는 계급입니다', true) end

    if (rank.is_leader == 1 or rank.is_leader == true) and not m.isLeader then
        return fnotify(src, '리더 계급 임명은 리더만 가능합니다', true)
    end

    local dep = nil
    if type(data.department) == 'string' and data.department ~= '' then
        local list = (Config.FactionDepartments and Config.FactionDepartments[m.type])
            or (Config.FactionDepartments and Config.FactionDepartments.default) or {}
        for _, d in ipairs(list) do
            if d == data.department then dep = d break end
        end
        if not dep then return fnotify(src, '없는 부서입니다', true) end
    end

    MySQL.update.await(
        'UPDATE cookie_faction_member SET grade = ?, department = ? WHERE faction_id = ? AND citizenid = ?',
        { grade, dep, m.id, cid })

    CookieFactionSyncMemberJob(cid, m.jobName, grade)

    fnotify(src, ('팩션원을 "%s"(%s)로 변경했습니다'):format(rank.rank_name, dep or '부서 없음'), false)

    local tsrc = srcOfCitizen(cid)
    if tsrc then
        TriggerClientEvent('cookie_admin:client:factionPane', tsrc, CookieBuildFactionPane(tsrc))
        CookiePushJobDisplay(tsrc)
    end
    pushFactionPane(src)
end)

RegisterNetEvent('cookie_admin:server:facBuyVehicle', function(shopId)
    local src = source
    local m, err = facOfficer(src)
    if not m then return fnotify(src, err, true) end

    local sid = math.floor(tonumber(shopId) or 0)
    if sid <= 0 then return end

    local item = MySQL.single.await([[
        SELECT model, label, price, min_grade FROM cookie_faction_shop
        WHERE id = ? AND faction_id = ? AND active = 1
    ]], { sid, m.id })
    if not item then return fnotify(src, '구매할 수 없는 차량입니다', true) end

    local dup = MySQL.single.await(
        'SELECT 1 AS x FROM cookie_faction_vehicle WHERE faction_id = ? AND model = ?',
        { m.id, item.model })
    if dup then
        return fnotify(src, ('%s은(는) 이미 보유 중입니다'):format(item.label or item.model), true)
    end

    local price = math.max(0, math.floor(tonumber(item.price) or 0))
    local vname = item.label or item.model

    local affected = MySQL.update.await(
        'UPDATE cookie_faction SET budget = budget - ? WHERE id = ? AND budget >= ?',
        { price, m.id, price })
    if not affected or affected < 1 then
        return fnotify(src, '팩션 예산이 부족합니다', true)
    end

    local f = MySQL.single.await(
        'SELECT garage_key, faction_type, faction_key FROM cookie_faction WHERE id = ?', { m.id })
    local garage = (f and f.garage_key and f.garage_key ~= '' and f.garage_key)
        or ((f and f.faction_type == 'police') and 'cookie_lspd')
        or ('cookie_' .. ((f and f.faction_key) or m.key or 'faction'))

    local ownerCid = 'FACTION_' .. m.id
    CookieEnsureFactionOwner(ownerCid)

    local okv, verr = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = item.model,
            citizenid = ownerCid,
            garage = garage,
        })
    end)

    if not okv or not verr then

        MySQL.update.await('UPDATE cookie_faction SET budget = budget + ? WHERE id = ?', { price, m.id })

        fnotify(src, ('차고 등록 실패 예산은 차감되지 않았습니다 (%s)'):format(tostring(verr)), true)
        pushFactionPane(src)
        return
    end

    local bal = factionBudget(m.id)

    MySQL.insert.await(
        'INSERT INTO cookie_faction_vehicle (faction_id, model, min_grade, added_by) VALUES (?, ?, ?, ?)',
        { m.id, item.model, item.min_grade or 0, m.citizenid })

    fnotify(src, ('%s 구매 완료 예산 $%s 차감 (잔액 $%s)'):format(vname, comma(price), comma(bal)), false)
    pushFactionPane(src)
end)

RegisterNetEvent('cookie_admin:server:facShopGrade', function(shopId, grade)
    local src = source
    local m, err = facLeader(src)
    if not m then return fnotify(src, err, true) end

    local sid = math.floor(tonumber(shopId) or 0)
    local g = math.floor(tonumber(grade) or -1)
    if sid <= 0 or g < 0 then return end

    local rank = MySQL.single.await(
        'SELECT rank_name FROM cookie_faction_rank WHERE faction_id = ? AND grade = ?', { m.id, g })
    if not rank then return fnotify(src, '없는 계급입니다', true) end

    local aff = MySQL.update.await(
        'UPDATE cookie_faction_shop SET min_grade = ? WHERE id = ? AND faction_id = ?', { g, sid, m.id })
    if not aff or aff < 1 then return fnotify(src, '차량을 찾을 수 없습니다', true) end

    local item = MySQL.single.await('SELECT model, label FROM cookie_faction_shop WHERE id = ?', { sid })
    if item then
        MySQL.update.await(
            'UPDATE cookie_faction_vehicle SET min_grade = ? WHERE faction_id = ? AND model = ?',
            { g, m.id, item.model })
    end

    fnotify(src, ('%s 출고 계급을 "%s" 이상으로 설정했습니다'):format(
        (item and (item.label or item.model)) or '차량', rank.rank_name), false)
    pushFactionPane(src)
end)

RegisterNetEvent('cookie_admin:server:facMemberKick', function(citizenid)
    local src = source
    if true then return fnotify(src, '계급/팩션원 관리는 F3 > 서버 팩션 관리에서만 가능합니다', true) end
    local m, err = facOfficer(src)
    if not m then return fnotify(src, err, true) end
    if type(citizenid) ~= 'string' then return end
    if citizenid == m.citizenid then return fnotify(src, '본인은 추방할 수 없습니다', true) end

    local row = MySQL.single.await([[
        SELECT mm.grade, r.is_leader FROM cookie_faction_member mm
        LEFT JOIN cookie_faction_rank r ON r.faction_id = mm.faction_id AND r.grade = mm.grade
        WHERE mm.faction_id = ? AND mm.citizenid = ? AND mm.status = 'active'
    ]], { m.id, citizenid })
    if not row then return fnotify(src, '팩션원을 찾을 수 없습니다', true) end
    if (row.is_leader == 1 or row.is_leader == true) then
        return fnotify(src, '리더는 추방할 수 없습니다', true)
    end

    -- 추방 시 현재 팩션만 비활성화하지 않고 예전 소속 기록까지 전부 제거한다.
    if CookieFactionPurgeMembership then
        CookieFactionPurgeMembership(citizenid, nil)
    else
        MySQL.query.await('DELETE FROM cookie_faction_member WHERE citizenid = ?', { citizenid })
        CookieFactionClearMemberJob(citizenid)
    end

    fnotify(src, '팩션원을 추방했습니다', false)

    local tsrc = srcOfCitizen(citizenid)
    if tsrc then
        TriggerClientEvent('cookie_admin:client:factionPane', tsrc, nil)
        CookiePushJobDisplay(tsrc)
        TriggerClientEvent('cookie_admin:client:notify', tsrc, ('%s에서 추방되었습니다'):format(m.name), true)
    end
    pushFactionPane(src)
end)


-- 삭제되었거나 더 이상 소속되지 않은 팩션 직업이 Qbox 주직업에 남아 있으면 자동 정리한다.
-- 로딩 순간의 일시적 불일치로 정상 소속을 지우지 않도록 60초 연속 불일치일 때만 DB를 정리한다.
local staleFactionMismatchAt = {}
local function cleanupStaleFactionJob(src)
    local p = exports.qbx_core:GetPlayer(src)
    local pd = p and p.PlayerData or nil
    if not pd or not pd.citizenid or not pd.job or not pd.job.name then return end

    -- 1) DB에는 팩션 소속인데 실제 Qbox 주직업이 그 팩션이 아니면 예전 소속으로 본다.
    local activeMem = MySQL.single.await([[
        SELECT m.faction_id, f.job_name
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id=m.faction_id AND f.is_active=1
        WHERE m.citizenid=? AND m.status='active' LIMIT 1
    ]], { pd.citizenid })

    if activeMem and tostring(activeMem.job_name or '') ~= tostring(pd.job.name or '') then
        local now = os.time()
        staleFactionMismatchAt[src] = staleFactionMismatchAt[src] or now
        if (now - staleFactionMismatchAt[src]) < 60 then return end

        MySQL.update.await(
            'UPDATE cookie_faction SET leader_citizenid=NULL WHERE id=? AND leader_citizenid=?',
            { activeMem.faction_id, pd.citizenid })
        MySQL.query.await('DELETE FROM cookie_faction_member WHERE citizenid=?', { pd.citizenid })

        -- 현재 시민직/다른 주직업은 건드리지 않고 예전 팩션 job만 제거한다.
        pcall(function()
            exports.qbx_core:RemovePlayerFromJob(pd.citizenid, activeMem.job_name)
        end)

        local loadout = MySQL.query.await(
            'SELECT item, count FROM cookie_faction_loadout WHERE citizenid=?', { pd.citizenid }) or {}
        for _, item in ipairs(loadout) do
            local count = math.max(0, math.floor(tonumber(item.count) or 0))
            if count > 0 and item.item then
                pcall(function() exports.ox_inventory:RemoveItem(src, item.item, count) end)
            end
        end
        MySQL.query.await('DELETE FROM cookie_faction_loadout WHERE citizenid=?', { pd.citizenid })
        TriggerClientEvent('cookie_admin:client:setArmor', src, 0)

        if CookiePushJobDisplay then CookiePushJobDisplay(src) end
        if CookieRefreshNameTag then CookieRefreshNameTag(src) end
        TriggerClientEvent('cookie_admin:client:factionPane', src, nil)
        staleFactionMismatchAt[src] = nil
        return
    end

    staleFactionMismatchAt[src] = nil

    -- 2) 실제 Qbox 주직업은 팩션 job인데 DB 소속이 없거나 팩션이 삭제된 경우 Qbox 잔여 job을 정리한다.
    if not activeMem then
        local f = MySQL.single.await(
            'SELECT id FROM cookie_faction WHERE job_name=? ORDER BY is_active DESC, id DESC LIMIT 1',
            { pd.job.name })
        if f then
            CookieFactionClearMemberJob(pd.citizenid)
            if CookiePushJobDisplay then CookiePushJobDisplay(src) end
            if CookieRefreshNameTag then CookieRefreshNameTag(src) end
        end
    end
end

CreateThread(function()
    Wait(9000)
    while true do
        for _, pid in ipairs(GetPlayers()) do
            local src = tonumber(pid)
            if src then cleanupStaleFactionJob(src) end
        end
        Wait(30000)
    end
end)

-- COOKIE FACTION V2: 재시작 시 활성 팩션의 계급/급여를 Qbox job에 다시 적용한다.
CreateThread(function()
    Wait(6500)
    local rows = MySQL.query.await('SELECT id FROM cookie_faction WHERE is_active = 1 ORDER BY id') or {}
    for _, row in ipairs(rows) do
        pcall(function() CookieFactionEnsureJob(row.id) end)
    end

    -- 탈퇴/제거/삭제된 팩션의 옛 소속은 기록으로 남기지 않고 완전히 제거한다.
    MySQL.query.await("DELETE FROM cookie_faction_member WHERE status <> 'active'")
    MySQL.query.await([[
        DELETE m FROM cookie_faction_member m
        LEFT JOIN cookie_faction f ON f.id=m.faction_id
        WHERE f.id IS NULL OR f.is_active=0
    ]])

    -- 기존 버전에서 중복으로 남은 활성 소속은 가장 최근 1개만 남긴다.
    MySQL.query.await([[
        DELETE oldm FROM cookie_faction_member oldm
        JOIN cookie_faction_member newm
          ON newm.citizenid = oldm.citizenid AND newm.id > oldm.id
        WHERE oldm.status='active' AND newm.status='active'
    ]])
    local idx = MySQL.single.await([[
        SELECT 1 AS ok FROM information_schema.statistics
        WHERE table_schema = DATABASE()
          AND table_name = 'cookie_faction_member'
          AND index_name = 'uq_cookie_faction_citizen'
        LIMIT 1
    ]])
    if not idx then
        MySQL.query.await('ALTER TABLE cookie_faction_member ADD UNIQUE KEY uq_cookie_faction_citizen (citizenid)')
    end
end)
