local ECON_DEFAULT_CITIZEN_SALARY = 10
local ECON_CITIZEN_PAY_INTERVAL = 30 * 60 * 1000

local function econNotify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr == true)
end

local function econAuth(src)
    local admin = CookieAdminTeamAuth and CookieAdminTeamAuth(src, 'general') or nil
    if not admin or (tonumber(admin.admin_level) or 0) < 5 then return nil end
    return admin
end

local function ensureEconomyTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS cookie_server_setting (
            setting_key VARCHAR(64) NOT NULL PRIMARY KEY,
            setting_value VARCHAR(255) NOT NULL,
            updated_by VARCHAR(80) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        INSERT IGNORE INTO cookie_server_setting (setting_key, setting_value)
        VALUES ('citizen_salary', ?)
    ]], { tostring(ECON_DEFAULT_CITIZEN_SALARY) })
end

local function citizenSalary()
    ensureEconomyTable()
    local row = MySQL.single.await(
        "SELECT setting_value FROM cookie_server_setting WHERE setting_key='citizen_salary' LIMIT 1"
    )
    return math.max(0, math.floor(tonumber(row and row.setting_value) or ECON_DEFAULT_CITIZEN_SALARY))
end

function CookieApplyCitizenSalary(value)
    local salary = math.max(0, math.floor(tonumber(value) or citizenSalary()))
    local job = exports.qbx_core:GetJob('unemployed')
    local grade = job and job.grades and (job.grades[0] or job.grades['0']) or nil
    local gradeName = (grade and grade.name) or '시민'

    -- Qbox 기본 payday와 중복 지급되지 않게 unemployed 기본 payment는 0으로 둔다.
    pcall(function()
        exports.qbx_core:UpsertJobGrade('unemployed', 0, {
            name = gradeName,
            payment = 0,
        }, true)
    end)
    return salary
end

CreateThread(function()
    Wait(2500)
    ensureEconomyTable()
    CookieApplyCitizenSalary(citizenSalary())
end)

-- 시민(unemployed) 전용 30분 급여. 서버 전체 주기로 지급하며 팩션/시민직 근무자는 제외된다.
CreateThread(function()
    Wait(ECON_CITIZEN_PAY_INTERVAL)
    while true do
        local salary = citizenSalary()
        if salary > 0 then
            for _, pid in ipairs(GetPlayers()) do
                local src = tonumber(pid)
                local p = src and exports.qbx_core:GetPlayer(src) or nil
                local pd = p and p.PlayerData or nil
                if p and pd and pd.job and pd.job.name == 'unemployed' then
                    local ok = pcall(function()
                        p.Functions.AddMoney('bank', salary, '쿠키 시민 30분 급여')
                    end)
                    if ok then
                        TriggerClientEvent('cookie_admin:client:notify', src, ('시민 30분 급여 %d원이 계좌로 지급되었습니다'):format(salary), false)
                    end
                end
            end
        end
        Wait(ECON_CITIZEN_PAY_INTERVAL)
    end
end)

RegisterNetEvent('cookie_admin:server:requestEconomySystem', function()
    local src = source
    if not econAuth(src) then return econNotify(src, '시스템 관리 권한이 없습니다', true) end
    TriggerClientEvent('cookie_admin:client:economySystemData', src, {
        citizenSalary = citizenSalary(),
    })
end)

RegisterNetEvent('cookie_admin:server:saveEconomySystem', function(data)
    local src = source
    local admin = econAuth(src)
    if not admin then return econNotify(src, '시스템 관리 권한이 없습니다', true) end
    if type(data) ~= 'table' then return end

    local salary = math.floor(tonumber(data.citizenSalary) or -1)
    if salary < 0 or salary > 1000000000 then
        return econNotify(src, '시민 급여 금액이 올바르지 않습니다', true)
    end

    ensureEconomyTable()
    MySQL.query.await([[
        INSERT INTO cookie_server_setting (setting_key, setting_value, updated_by)
        VALUES ('citizen_salary', ?, ?)
        ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value), updated_by=VALUES(updated_by)
    ]], { tostring(salary), admin.admin_name or '관리자' })

    CookieApplyCitizenSalary(salary)
    econNotify(src, ('시민 30분 급여를 %d원으로 변경했습니다'):format(salary), false)
    TriggerClientEvent('cookie_admin:client:economySystemData', src, { citizenSalary = salary })
end)
