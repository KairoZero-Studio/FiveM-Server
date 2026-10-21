

local function slog(...)
    if Config.Debug then  end
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_skill (
                citizenid  VARCHAR(64) NOT NULL,
                skill      VARCHAR(32) NOT NULL,
                level      INT         NOT NULL DEFAULT 1,
                exp        INT         NOT NULL DEFAULT 0,
                total_job  INT         NOT NULL DEFAULT 0,
                total_pay  BIGINT      NOT NULL DEFAULT 0,
                updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (citizenid, skill)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)

    if ok then

    else

    end
end)

local function cidOf(src)
    local p = exports.qbx_core:GetPlayer(src)
    if not p then return nil end
    return p.PlayerData and p.PlayerData.citizenid or nil
end

local function defOf(skill)
    return Config.Skills and Config.Skills[skill] or nil
end

local function levelFromExp(skill, exp)
    local def = defOf(skill)
    if not def then return 1 end

    local lv = 1
    for _, row in ipairs(def.levels) do
        if exp >= row.exp then lv = row.level else break end
    end
    return lv
end

local function rowOfLevel(skill, level)
    local def = defOf(skill)
    if not def then return nil end
    for _, row in ipairs(def.levels) do
        if row.level == level then return row end
    end
    return def.levels[1]
end

local function nextExpOf(skill, level)
    local def = defOf(skill)
    if not def then return nil end
    for _, row in ipairs(def.levels) do
        if row.level == level + 1 then return row.exp end
    end
    return nil
end

local function fetch(cid, skill)
    return MySQL.single.await(
        'SELECT level, exp, total_job, total_pay FROM cookie_skill WHERE citizenid = ? AND skill = ?',
        { cid, skill })
end

function CookieSkillGet(src, skill)
    local cid = cidOf(src)
    if not cid or not defOf(skill) then return nil end

    local row = fetch(cid, skill) or { level = 1, exp = 0, total_job = 0, total_pay = 0 }
    local exp = math.floor(tonumber(row.exp) or 0)
    local lv = levelFromExp(skill, exp)
    local nxt = nextExpOf(skill, lv)
    local cur = (rowOfLevel(skill, lv) or {}).exp or 0

    return {
        skill     = skill,
        label     = (defOf(skill).label) or skill,
        level     = lv,
        maxLevel  = defOf(skill).maxLevel or 5,
        exp       = exp,
        levelExp  = cur,
        nextExp   = nxt,
        need      = nxt and (nxt - exp) or 0,
        bonus     = rowOfLevel(skill, lv),
        nextBonus = nxt and rowOfLevel(skill, lv + 1) or nil,
        total_job = math.floor(tonumber(row.total_job) or 0),
        total_pay = math.floor(tonumber(row.total_pay) or 0),
    }
end

function CookieSkillLevel(src, skill)
    local g = CookieSkillGet(src, skill)
    return g and g.level or 1
end

function CookieSkillBonus(src, skill)
    local g = CookieSkillGet(src, skill)
    return g and g.bonus or rowOfLevel(skill, 1)
end

function CookieSkillTable(skill)
    local def = defOf(skill)
    return def and def.levels or {}
end

function CookieSkillAddExp(src, skill, amount)
    local cid = cidOf(src)
    local def = defOf(skill)
    if not cid or not def then return nil end

    local add = math.floor(tonumber(amount) or 0)
    if add <= 0 then return CookieSkillLevel(src, skill) end

    local before = fetch(cid, skill)
    local oldExp = before and math.floor(tonumber(before.exp) or 0) or 0
    local oldLv = levelFromExp(skill, oldExp)

    local newExp = oldExp + add
    local newLv = levelFromExp(skill, newExp)

    MySQL.query.await([[
        INSERT INTO cookie_skill (citizenid, skill, level, exp)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE level = VALUES(level), exp = VALUES(exp)
    ]], { cid, skill, newLv, newExp })

    -- 중앙 시민직은 EXP 조건 달성만으로 자동 승급하지 않는다.
    -- 실제 해금 레벨은 F3 > 내정보 > 직업 레벨의 수동 승급이 기준이다.
    if newLv > oldLv and def.manualPromotion ~= true then
        TriggerClientEvent('cookie_skill:client:levelUp', src, {
            skill = skill,
            label = def.label or skill,
            level = newLv,
            bonus = rowOfLevel(skill, newLv),
        })
    end

    return newLv
end

function CookieSkillRecord(src, skill, pay)
    local cid = cidOf(src)
    if not cid or not defOf(skill) then return end

    local amt = math.max(0, math.floor(tonumber(pay) or 0))
    MySQL.query.await([[
        INSERT INTO cookie_skill (citizenid, skill, level, exp, total_job, total_pay)
        VALUES (?, ?, 1, 0, 1, ?)
        ON DUPLICATE KEY UPDATE total_job = total_job + 1, total_pay = total_pay + VALUES(total_pay)
    ]], { cid, skill, amt })
end

exports('get',    function(src, skill)         return CookieSkillGet(src, skill) end)
exports('level',  function(src, skill)         return CookieSkillLevel(src, skill) end)
exports('bonus',  function(src, skill)         return CookieSkillBonus(src, skill) end)
exports('bonusAtLevel', function(skill, level) return rowOfLevel(skill, math.max(1, math.floor(tonumber(level) or 1))) end)
exports('addExp', function(src, skill, amount) return CookieSkillAddExp(src, skill, amount) end)
exports('record', function(src, skill, pay)    return CookieSkillRecord(src, skill, pay) end)
exports('levels', function(skill)              return CookieSkillTable(skill) end)
