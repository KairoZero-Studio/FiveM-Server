
local L = Config.Labor
local JOB = L.Job

local active = {}

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function() return exports.cookie_core:Allow(src, key, windowMs, maxCount) end)
        if ok then return allowed == true end
    end
    return true
end

local function getP(src)
    return exports.qbx_core:GetPlayer(src)
end

local function cid(src)
    local p = getP(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function job(src)
    local p = getP(src)
    return p and p.PlayerData and p.PlayerData.job or nil
end

local function isHired(src)
    local j = job(src)
    return j and j.name == JOB
end

local function isDuty(src)
    local j = job(src)
    return j and j.name == JOB and j.onduty == true
end

local function notify(src, msg, err)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, err and true or false)
end

local function factionOf(src)
    local ok, f = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    return ok and f or nil
end

local function level(src)
    local ok, v = pcall(function() return exports.cookie_admin:getCivilLevel(src, L.Job or L.Skill) end)
    return ok and tonumber(v) or 1
end

local function skillRow(src)
    local ok, v = pcall(function() return exports.cookie_skill:get(src, L.Skill) end)
    return ok and v or nil
end

local function payMult(src)
    local lv = math.max(1, math.min(5, level(src)))
    local ok, b = pcall(function() return exports.cookie_skill:bonusAtLevel(L.Skill, lv) end)
    if ok and type(b) == 'table' and tonumber(b.payMult) then
        return tonumber(b.payMult), lv
    end
    return (L.PayMult and L.PayMult[lv]) or 1.0, lv
end

local function refreshLabels(src)
    TriggerEvent('cookie_admin:server:nameTagDirty', src)
    TriggerEvent('cookie_admin:server:jobDisplayDirty', src)
end

CreateThread(function()
    Wait(800)
    local ok, err = pcall(function()
        return exports.qbx_core:CreateJob(JOB, L.JobDef, true)
    end)
    if not ok and L.Debug then print('[cookie_labor] CreateJob:', err) end
end)

local function pushState(src, npcId)
    local row = skillRow(src)
    local mult, lv = payMult(src)
    TriggerClientEvent('cookie_labor:client:state', src, {
        npcId = tonumber(npcId),
        hired = isHired(src),
        onDuty = isDuty(src),
        level = lv,
        exp = row and (row.exp or row.total or 0) or 0,
        payMult = mult,
        active = active[src] ~= nil,
    })
end

RegisterNetEvent('cookie_labor:server:requestState', function(npcId)
    pushState(source, npcId)
end)

RegisterNetEvent('cookie_labor:server:hire', function(npcId)
    local src = source
    local p = getP(src)
    if not p then return end
    if isHired(src) then return notify(src, '이미 건설 인부입니다.', true) end
    if factionOf(src) then return notify(src, '팩션 소속은 시민직에 취업할 수 없습니다.', true) end

    local curJob = p.PlayerData and p.PlayerData.job
    if curJob and curJob.name and curJob.name ~= 'unemployed' and curJob.name ~= JOB then
        return notify(src, ('현재 %s 직업을 보유 중입니다. 기존 직업을 그만둔 뒤 취업하세요.'):format(curJob.label or curJob.name), true)
    end

    pcall(function() exports.cookie_admin:clearAllJobs(cid(src), JOB) end)
    local ok = p.Functions.SetJob(JOB, 0)
    if ok == false then return notify(src, '취업 처리에 실패했습니다.', true) end

    refreshLabels(src)
    notify(src, '건설 인부로 취업했습니다.', false)
    TriggerClientEvent('cookie_labor:client:line', src, L.Lines.hired)
    pushState(src, npcId)
end)

RegisterNetEvent('cookie_labor:server:quit', function(npcId)
    local src = source
    local p = getP(src)
    if not p or not isHired(src) then return end

    active[src] = nil
    pcall(function() p.Functions.SetJobDuty(false) end)
    pcall(function() p.Functions.SetJob('unemployed', 0) end)
    refreshLabels(src)

    TriggerClientEvent('cookie_labor:client:cancelTask', src)
    notify(src, '건설 인부 일을 그만뒀습니다.', false)
    pushState(src, npcId)
end)

AddEventHandler('cookie_labor:server:forceQuit', function(src, reason)
    if not src then return end
    active[src] = nil
    TriggerClientEvent('cookie_labor:client:cancelTask', src)
    notify(src, ('건설 인부 직업이 해제되었습니다 (%s)'):format(reason or '직업 변경'), false)
    pushState(src)
end)

local function taskRows(npcId)
    local ok, rows = pcall(function()
        return exports.cookie_labor:tasksForNpc(npcId)
    end)
    if ok and type(rows) == 'table' then return rows end
    return {}
end

local function validTasks(npcId)
    local out = {}
    for _, r in ipairs(taskRows(npcId)) do
        if r.hasSource and r.hasDest then out[#out+1] = r end
    end
    return out
end

local function assign(src, npcId)
    if not isDuty(src) then return false end

    local rows = validTasks(npcId)
    if #rows == 0 then
        notify(src, L.Lines.noTask, true)
        active[src] = nil
        return false
    end

    local pick = rows[math.random(1, #rows)]
    active[src] = {
        npcId = tonumber(npcId),
        taskId = tonumber(pick.id),
        label = pick.label,
        total = tonumber(pick.box_count) or L.DefaultCount,
        delivered = 0,
        reward = tonumber(pick.reward) or L.DefaultReward,
        carrying = false,
        lastActionAt = 0,
        source = { x=pick.source_x, y=pick.source_y, z=pick.source_z },
        dest = { x=pick.dest_x, y=pick.dest_y, z=pick.dest_z },
    }

    TriggerClientEvent('cookie_labor:client:task', src, active[src])
    notify(src, L.Lines.taskAssigned, false)
    return true
end

RegisterNetEvent('cookie_labor:server:duty', function(on, npcId)
    local src = source
    local p = getP(src)
    if not p or not isHired(src) then return notify(src, '건설 인부가 아닙니다.', true) end

    local want = on == true
    pcall(function() p.Functions.SetJobDuty(want) end)

    if not want then
        active[src] = nil
        TriggerClientEvent('cookie_labor:client:cancelTask', src)
        notify(src, L.Lines.dutyOff, false)
    else
        notify(src, L.Lines.dutyOn, false)
        assign(src, npcId)
    end

    refreshLabels(src)
    pushState(src, npcId)
end)

RegisterNetEvent('cookie_labor:server:requestTask', function(npcId)
    local src = source
    if not isDuty(src) then return notify(src, '먼저 출근하세요.', true) end
    if active[src] then
        return TriggerClientEvent('cookie_labor:client:task', src, active[src])
    end
    assign(src, npcId)
end)

local function near(src, c, radius)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local p = GetEntityCoords(ped)
    return #(p - vec3(c.x + 0.0, c.y + 0.0, c.z + 0.0)) <= radius
end

RegisterNetEvent('cookie_labor:server:pickup', function()
    local src = source
    if not cookieAllowAction(src, 'labor_pickup', 1000, 2) then return end
    local a = active[src]
    if not a or not isDuty(src) then return end
    if a.delivered >= a.total then return end
    if a.carrying then return notify(src, '이미 상자를 들고 있습니다.', true) end
    local now = GetGameTimer()
    if now - (a.lastActionAt or 0) < 700 then return end
    if not near(src, a.source, 4.0) then return notify(src, '상자 더미 근처에서만 들 수 있습니다.', true) end

    a.carrying = true
    a.lastActionAt = now
    TriggerClientEvent('cookie_labor:client:pickupApproved', src)
end)

RegisterNetEvent('cookie_labor:server:deliver', function()
    local src = source
    if not cookieAllowAction(src, 'labor_deliver', 1000, 2) then return end
    local a = active[src]
    if not a or not isDuty(src) then return end
    if a.delivered >= a.total then return end
    if not a.carrying then return notify(src, '먼저 상자를 들어야 합니다.', true) end
    local now = GetGameTimer()
    if now - (a.lastActionAt or 0) < 700 then return end
    if not near(src, a.dest, 4.0) then return notify(src, '운반 위치에서 내려놓으세요.', true) end

    a.carrying = false
    a.lastActionAt = now
    a.delivered = a.delivered + 1

    local perBox = math.floor((a.reward or 0) / math.max(1, a.total))
    if a.delivered < a.total then
        TriggerClientEvent('cookie_labor:client:delivered', src, {
            delivered = a.delivered,
            total = a.total,
            perBox = perBox,
        })
        return
    end

    local p = getP(src)
    local mult, lv = payMult(src)
    local pay = math.floor((a.reward or 0) * mult)

    if p and pay > 0 then
        p.Functions.AddMoney('bank', pay, '건설 인부 작업 완료')
    end

    pcall(function()
        exports.cookie_skill:addExp(src, L.Skill, math.max(1, a.total * (L.ExpPerBox or 1)))
        exports.cookie_skill:record(src, L.Skill, pay)
    end)

    local npcId = a.npcId
    active[src] = nil

    TriggerClientEvent('cookie_labor:client:completed', src, {
        pay = pay,
        level = lv,
        npcId = npcId,
    })

    -- 출근 상태면 잠깐 뒤 새 작업을 자동 배정.
    SetTimeout(2500, function()
        if GetPlayerPing(src) > 0 and isDuty(src) and not active[src] then
            assign(src, npcId)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    active[source] = nil
end)
