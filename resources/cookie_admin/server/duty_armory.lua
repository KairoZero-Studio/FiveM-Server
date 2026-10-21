

local function alog(...)
    if Config.Debug then  end
end

local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local ARMOR_ITEM = '__armor__'

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_faction_armory (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                faction_id  INT NOT NULL,
                kind        VARCHAR(16)  NOT NULL DEFAULT 'weapon',
                item        VARCHAR(64)  NOT NULL,
                label       VARCHAR(64)  NOT NULL,
                ammo_item   VARCHAR(32)  NULL,
                price       INT          NOT NULL DEFAULT 0,
                min_grade   INT          NOT NULL DEFAULT 0,
                active      TINYINT(1)   NOT NULL DEFAULT 1,
                created_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_faction_item (faction_id, item)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_faction_loadout (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                faction_id  INT NOT NULL,
                citizenid   VARCHAR(64) NOT NULL,
                item        VARCHAR(64) NOT NULL,
                count       INT NOT NULL DEFAULT 0,
                UNIQUE KEY uq_loadout (citizenid, item)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])

        MySQL.query.await("ALTER TABLE cookie_faction_member ADD COLUMN IF NOT EXISTS duty TINYINT(1) NOT NULL DEFAULT 0")
    end)

    if ok then

    else

    end
end)

CookieLastActive = CookieLastActive or {}

RegisterNetEvent('cookie_admin:server:activityPing', function()
    CookieLastActive[source] = os.time()
end)

AddEventHandler('playerDropped', function()
    CookieLastActive[source] = nil
end)

function CookieIsIdle(src)
    local last = CookieLastActive[src]
    if not last then return false end
    return (os.time() - last) >= (Config.DutyIdleMinutes or 30) * 60
end

local function isOnDuty(citizenid)
    local row = MySQL.single.await(
        "SELECT duty FROM cookie_faction_member WHERE citizenid = ? AND status = 'active' LIMIT 1",
        { citizenid })
    return (row and (row.duty == 1 or row.duty == true)) or false
end

local function returnLoadout(src, m)
    local rows = MySQL.query.await(
        'SELECT item, count FROM cookie_faction_loadout WHERE citizenid = ?', { m.citizenid }) or {}

    local removed = 0
    for _, r in ipairs(rows) do
        local n = math.max(0, math.floor(tonumber(r.count) or 0))
        if n > 0 then
            local ok = pcall(function()
                exports.ox_inventory:RemoveItem(src, r.item, n)
            end)
            if ok then removed = removed + 1 end
        end
    end

    MySQL.query.await('DELETE FROM cookie_faction_loadout WHERE citizenid = ?', { m.citizenid })

    TriggerClientEvent('cookie_admin:client:setArmor', src, 0)

    if removed > 0 then

    end
    return removed
end

local function dutyPayload(src)
    local m = CookieFactionMemberOf(src)
    if not m then return nil end
    return {
        faction  = m.name,
        rankName = m.rankName,
        onDuty   = isOnDuty(m.citizenid),
        idleMin  = Config.DutyIdleMinutes or 30,
    }
end

RegisterNetEvent('cookie_admin:server:requestDuty', function()
    local src = source
    local m = CookieFactionMemberOf(src)
    if not m then return notify(src, '팩션 소속이 아닙니다', true) end
    if CookieFactionIsGovType and not CookieFactionIsGovType(m.type) then
        return notify(src, '이 팩션은 출퇴근 시스템을 사용하지 않습니다', true)
    end
    local p = dutyPayload(src)
    if not p then return notify(src, '팩션 소속이 아닙니다', true) end
    TriggerClientEvent('cookie_admin:client:openDutyUI', src, p)
end)

RegisterNetEvent('cookie_admin:server:dutyToggle', function()
    local src = source
    local m = CookieFactionMemberOf(src)
    if not m then return notify(src, '팩션 소속이 아닙니다', true) end
    if CookieFactionIsGovType and not CookieFactionIsGovType(m.type) then
        return notify(src, '이 팩션은 출퇴근 시스템을 사용하지 않습니다', true)
    end

    local now = isOnDuty(m.citizenid)
    local next_ = not now

    MySQL.update.await(
        "UPDATE cookie_faction_member SET duty = ? WHERE citizenid = ? AND status = 'active'",
        { next_ and 1 or 0, m.citizenid })

    local player = exports.qbx_core:GetPlayer(src)
    if player and player.Functions and player.Functions.SetJobDuty then
        pcall(function() player.Functions.SetJobDuty(next_) end)
    end

    if next_ then
        CookieLastActive[src] = os.time()
        notify(src, ('%s 뱃지를 착용했습니다'):format(m.name), false)
    else
        local n = returnLoadout(src, m)
        if n > 0 then
            notify(src, ('%s 뱃지를 반납하고 지급품을 회수했습니다'):format(m.name), false)
        else
            notify(src, ('%s 뱃지를 반납했습니다'):format(m.name), false)
        end
    end

    if CookieRefreshNameTag then pcall(CookieRefreshNameTag, src) end
    TriggerClientEvent('cookie_admin:client:dutyState', src, next_)
    TriggerClientEvent('cookie_admin:client:openDutyUI', src, dutyPayload(src))
    TriggerEvent('cookie_police:server:dutyChanged', src, next_, m.id, m.citizenid, m.nickname or GetPlayerName(src) or m.rankName)

end)

function CookieFactionForceOffDuty(citizenid, actorName)
    if not citizenid or citizenid == '' then return false, '시민번호 없음' end
    local member = MySQL.single.await([[
        SELECT m.faction_id, m.duty, f.name, f.faction_type
        FROM cookie_faction_member m
        JOIN cookie_faction f ON f.id = m.faction_id AND f.is_active = 1
        WHERE m.citizenid = ? AND m.status = 'active' LIMIT 1
    ]], { citizenid })
    if not member then return false, '팩션 소속이 아닙니다' end
    if CookieFactionIsGovType and not CookieFactionIsGovType(member.faction_type) then
        return false, '출퇴근제를 사용하지 않는 팩션입니다'
    end

    MySQL.update.await(
        "UPDATE cookie_faction_member SET duty = 0 WHERE citizenid = ? AND status = 'active'",
        { citizenid })

    local targetSrc
    for _, pid in ipairs(GetPlayers()) do
        local s = tonumber(pid)
        local p = s and exports.qbx_core:GetPlayer(s) or nil
        if p and p.PlayerData and p.PlayerData.citizenid == citizenid then targetSrc = s break end
    end

    if targetSrc then
        local p = exports.qbx_core:GetPlayer(targetSrc)
        if p and p.Functions and p.Functions.SetJobDuty then
            pcall(function() p.Functions.SetJobDuty(false) end)
        end
        local m = CookieFactionMemberOf(targetSrc)
        if m then returnLoadout(targetSrc, m) end
        CookieLastActive[targetSrc] = nil
        if CookieRefreshNameTag then pcall(CookieRefreshNameTag, targetSrc) end
        if CookiePushJobDisplay then pcall(CookiePushJobDisplay, targetSrc) end
        TriggerClientEvent('cookie_admin:client:dutyState', targetSrc, false)
        TriggerClientEvent('cookie_admin:client:factionPane', targetSrc, CookieBuildFactionPane(targetSrc))
        if actorName and actorName ~= '' then
            notify(targetSrc, ('관리자 %s에 의해 강제 퇴근 처리되었습니다'):format(actorName), true)
        end
    end
    return true, nil, targetSrc
end

exports('forceFactionOffDuty', function(citizenid, actorName)
    return CookieFactionForceOffDuty(citizenid, actorName)
end)

local function armoryPayload(src)
    local m = CookieFactionMemberOf(src)
    if not m then return nil end

    local rows = MySQL.query.await([[
        SELECT a.id, a.kind, a.item, a.label, a.ammo_item, a.price, a.min_grade,
               r.rank_name
        FROM cookie_faction_armory a
        LEFT JOIN cookie_faction_rank r ON r.faction_id = a.faction_id AND r.grade = a.min_grade
        WHERE a.faction_id = ? AND a.active = 1
        ORDER BY a.kind ASC, a.min_grade ASC, a.label ASC
    ]], { m.id }) or {}

    local items = {}
    for _, r in ipairs(rows) do
        items[#items + 1] = {
            id       = r.id,
            kind     = r.kind,
            item     = r.item,

            img      = (Config.ArmoryImageAlias and Config.ArmoryImageAlias[r.item]) or r.item,
            label    = r.label,
            price    = r.price,
            minGrade = r.min_grade,
            rankName = r.rank_name,
            locked   = (m.grade or 0) < (r.min_grade or 0),
        }
    end

    local inv = {}
    local okI, list = pcall(function() return exports.ox_inventory:GetInventoryItems(src) end)
    if okI and type(list) == 'table' then
        for _, it in pairs(list) do
            if it and it.name then
                inv[#inv + 1] = { name = it.name, label = it.label or it.name, count = it.count or 1 }
            end
        end
        table.sort(inv, function(a, b) return (a.label or '') < (b.label or '') end)
    end

    return {
        faction  = m.name,
        rankName = m.rankName,
        grade    = m.grade or 0,
        onDuty   = isOnDuty(m.citizenid),
        budget   = CookieFactionBudget(m.id) or 0,
        charge   = Config.ArmoryChargeBudget and true or false,
        maxQty   = Config.ArmoryMaxQty or 20,
        items    = items,
        inv      = inv,
    }
end

RegisterNetEvent('cookie_admin:server:requestArmory', function()
    local src = source
    local p = armoryPayload(src)
    if not p then return notify(src, '팩션 소속이 아닙니다', true) end
    TriggerClientEvent('cookie_admin:client:openArmoryUI', src, p)
end)

local function addLoadout(factionId, citizenid, item, n)
    MySQL.query.await([[
        INSERT INTO cookie_faction_loadout (faction_id, citizenid, item, count)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE count = count + VALUES(count)
    ]], { factionId, citizenid, item, n })
end

RegisterNetEvent('cookie_admin:server:armoryBuy', function(rowId, qty)
    local src = source
    local m = CookieFactionMemberOf(src)
    if not m then return notify(src, '팩션 소속이 아닙니다', true) end

    if not isOnDuty(m.citizenid) then
        return notify(src, '근무를 시작해야 무장할 수 있습니다', true)
    end

    local id = tonumber(rowId)
    if not id then return end

    local row = MySQL.single.await(
        'SELECT * FROM cookie_faction_armory WHERE id = ? AND faction_id = ? AND active = 1',
        { id, m.id })
    if not row then return notify(src, '지급하지 않는 품목입니다', true) end

    if (m.grade or 0) < (row.min_grade or 0) then
        return notify(src, '계급이 부족합니다', true)
    end

    local n = math.floor(tonumber(qty) or 1)
    if row.kind ~= 'ammo' then n = 1 end
    if n < 1 then n = 1 end
    if n > (Config.ArmoryMaxQty or 20) then n = Config.ArmoryMaxQty or 20 end

    local cost = (row.price or 0) * n

    local charged = false
    if Config.ArmoryChargeBudget and cost > 0 then
        local ok, bal = CookieFactionSpend(m.id, cost, 'armory',
            ('%s %d'):format(row.label, n), m.citizenid)
        if not ok then
            return notify(src, ('예산이 부족합니다 (잔액 %d)'):format(bal or 0), true)
        end
        charged = true
    end

    if row.kind == 'armor' then
        TriggerClientEvent('cookie_admin:client:setArmor', src, Config.ArmorValue or 100)

        notify(src, '방탄복을 착용했습니다', false)
        TriggerClientEvent('cookie_admin:client:openArmoryUI', src, armoryPayload(src))
        return
    end

    local giveName = (row.kind == 'ammo' and row.ammo_item and row.ammo_item ~= '')
        and row.ammo_item or row.item

    local okAdd = false
    local okCall, ret = pcall(function()
        return exports.ox_inventory:AddItem(src, giveName, n)
    end)
    if okCall and ret ~= false then okAdd = true end

    if not okAdd then
        if charged then
            CookieFactionAddIncome(m.id, cost, 'armory_refund',
                ('%s 지급 실패 환불'):format(row.label), m.citizenid)
        end
        return notify(src, '인벤토리에 넣을 수 없습니다 (무게/공간 확인)', true)
    end

    addLoadout(m.id, m.citizenid, giveName, n)

    notify(src, ('%s 지급 완료'):format(row.label), false)
    if not charged and cost > 0 then

    end

    if CookiePushFactionPane then pcall(CookiePushFactionPane, src) end
    TriggerClientEvent('cookie_admin:client:openArmoryUI', src, armoryPayload(src))
end)

local function catalog()
    local allowed = {}
    for _, name in ipairs(Config.ArmoryLineup or {}) do allowed[name] = true end

    local byName = {}
    for _, cat in ipairs(Config.Weapons or {}) do
        for _, w in ipairs(cat.items or {}) do
            if allowed[w.name] then
                byName[w.name] = { item = w.name, label = w.label, ammo = w.ammo, group = cat.label }
            end
        end
    end

    local weapons, ammo, seenAmmo = {}, {}, {}
    for _, name in ipairs(Config.ArmoryLineup or {}) do
        local w = byName[name]
        if w then
            weapons[#weapons + 1] = w
            if w.ammo and not seenAmmo[w.ammo] then
                seenAmmo[w.ammo] = true
                ammo[#ammo + 1] = {
                    item = w.ammo,
                    label = (Config.AmmoLabels and Config.AmmoLabels[w.ammo]) or w.ammo,
                    group = w.group,
                }
            end
        end
    end

    local armor = {
        { item = ARMOR_ITEM, label = Config.ArmorLabel or '근무 케블라', group = '방탄복' },
    }
    return { weapon = weapons, ammo = ammo, armor = armor }
end

local function pushArmoryAdmin(src, fid)
    local rows, ranks = {}, {}

    local ok, err = pcall(function()
        rows = MySQL.query.await([[
            SELECT a.id, a.kind, a.item, a.label, a.ammo_item, a.price, a.min_grade, a.active,
                   r.rank_name
            FROM cookie_faction_armory a
            LEFT JOIN cookie_faction_rank r ON r.faction_id = a.faction_id AND r.grade = a.min_grade
            WHERE a.faction_id = ?
            ORDER BY a.kind ASC, a.min_grade ASC, a.label ASC
        ]], { fid }) or {}

        ranks = MySQL.query.await(
            'SELECT grade, rank_name FROM cookie_faction_rank WHERE faction_id = ? ORDER BY grade ASC',
            { fid }) or {}
    end)

    if not ok then

        notify(src, '무장고 목록을 불러오지 못했습니다', true)
    end

    local cat = catalog()

    TriggerClientEvent('cookie_admin:client:armoryAdmin', src, {
        factionId = fid,
        rows = rows,
        ranks = ranks,
        catalog = cat,
    })

end

RegisterNetEvent('cookie_admin:server:requestArmoryAdmin', function(factionId)
    local src = source

    if not CookieAdminTeamAuth(src, 'faction') then

        return notify(src, '팩션팀 권한이 필요합니다', true)
    end

    local fid = math.floor(tonumber(factionId) or 0)
    if fid <= 0 then

        return
    end
    pushArmoryAdmin(src, fid)
end)

RegisterNetEvent('cookie_admin:server:armorySave', function(p)
    local src = source
    if not CookieAdminTeamAuth(src, 'faction') then
        return notify(src, '팩션팀 권한이 필요합니다', true)
    end
    if type(p) ~= 'table' then return end

    local fid = math.floor(tonumber(p.factionId) or 0)
    local kind = tostring(p.kind or 'weapon')
    if fid <= 0 then return end
    if not (kind == 'weapon' or kind == 'ammo' or kind == 'armor') then return end

    local item = tostring(p.item or '')
    local label = tostring(p.label or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if item == '' or label == '' then return notify(src, '품목과 표시명을 입력하세요', true) end

    local price = math.max(0, math.floor(tonumber(p.price) or 0))
    local grade = math.max(0, math.floor(tonumber(p.minGrade) or 0))
    local active = (p.active == false or p.active == 0) and 0 or 1

    MySQL.query.await([[
        INSERT INTO cookie_faction_armory (faction_id, kind, item, label, ammo_item, price, min_grade, active)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            kind = VALUES(kind), label = VALUES(label), ammo_item = VALUES(ammo_item),
            price = VALUES(price), min_grade = VALUES(min_grade), active = VALUES(active)
    ]], { fid, kind, item, label, p.ammoItem, price, grade, active })

    notify(src, ('%s %s'):format(label, active == 1 and '등록했습니다' or '비활성화했습니다'), false)
    pushArmoryAdmin(src, fid)
end)

RegisterNetEvent('cookie_admin:server:armoryDelete', function(rowId, factionId)
    local src = source
    if not CookieAdminTeamAuth(src, 'faction') then
        return notify(src, '팩션팀 권한이 필요합니다', true)
    end

    local id = math.floor(tonumber(rowId) or 0)
    local fid = math.floor(tonumber(factionId) or 0)
    if id <= 0 or fid <= 0 then return end

    MySQL.query.await('DELETE FROM cookie_faction_armory WHERE id = ? AND faction_id = ?', { id, fid })
    notify(src, '등록을 해제했습니다', false)
    pushArmoryAdmin(src, fid)
end)
