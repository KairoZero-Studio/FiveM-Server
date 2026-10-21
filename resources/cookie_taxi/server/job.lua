

local function jlog(...)
    if Config.Debug then  end
end

local function notify(src, msg, isErr)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, isErr and true or false)
end

local T = Config.Taxi
local JOB = 'taxi'

local assigned = {}

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cookie_taxi_debt (
                citizenid  VARCHAR(64) NOT NULL PRIMARY KEY,
                amount     INT         NOT NULL DEFAULT 0,
                updated_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)

    if ok then

    else

    end
end)

local function playerOf(src) return exports.qbx_core:GetPlayer(src) end

local function cidOf(src)
    local p = playerOf(src)
    return p and p.PlayerData and p.PlayerData.citizenid or nil
end

local function jobOf(src)
    local p = playerOf(src)
    return p and p.PlayerData and p.PlayerData.job or nil
end

function CookieTaxiIsHired(src)
    local j = jobOf(src)
    return j and j.name == JOB
end

function CookieTaxiOnDuty(src)
    local j = jobOf(src)
    return j and j.name == JOB and j.onduty == true
end

function CookieTaxiAssignedVeh(src)
    local a = assigned[src]
    return a and a.veh or nil
end

local available = {}

local npcCall = {}

function CookieTaxiAvailable(src)
    return available[src] == true
end

function CookieTaxiNpcCall(src)
    return npcCall[src] == true
end

RegisterNetEvent('cookie_taxi:server:setNpcCall', function(on)
    local src = source
    if not CookieTaxiOnDuty(src) then return end

    npcCall[src] = (on == true)
    notify(src, npcCall[src] and 'NPC 호출을 켰습니다' or 'NPC 호출을 껐습니다', false)
    CookieTaxiPushState(src)

    if npcCall[src] then TriggerEvent('cookie_taxi:server:driverReady') end
end)

function CookieTaxiSetAvailable(src, on, silent)
    if not CookieTaxiOnDuty(src) then
        if not silent then notify(src, '출근해야 합니다', true) end
        return
    end
    if not CookieTaxiAssignedVeh(src) then
        if not silent then notify(src, '배정받은 택시가 없습니다', true) end
        return
    end

    available[src] = (on == true)

    if not available[src] then

        if CookieTaxiReleaseCalls then CookieTaxiReleaseCalls(src) end
    end

    if not silent then
        notify(src, available[src] and '배차 대기를 시작합니다' or '배차 대기를 껐습니다', false)
    end
    CookieTaxiPushState(src)

    if available[src] then TriggerEvent('cookie_taxi:server:driverReady') end
end

RegisterNetEvent('cookie_taxi:server:setAvailable', function(on)
    CookieTaxiSetAvailable(source, on == true, false)
end)

AddEventHandler('playerDropped', function() available[source] = nil end)

function CookieTaxiDrivers()
    local list = {}
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and CookieTaxiOnDuty(src) then list[#list + 1] = src end
    end
    return list
end

function CookieTaxiVehicleDef(key)
    for _, v in ipairs(T.Vehicles or {}) do
        if v.key == key then return v end
    end
    return nil
end

local function levelOf(src)
    local ok, lv = pcall(function() return exports.cookie_admin:getCivilLevel(src, T.Job or T.Skill) end)
    return (ok and tonumber(lv)) or 1
end

function CookieTaxiComma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

local function factionOf(src)
    local ok, m = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    return (ok and m) or nil
end

local function refreshLabels(src)
    TriggerEvent('cookie_admin:server:nameTagDirty', src)
    TriggerEvent('cookie_admin:server:jobDisplayDirty', src)
end

local function debtOf(cid)
    if not cid then return 0 end
    local row = MySQL.single.await('SELECT amount FROM cookie_taxi_debt WHERE citizenid = ?', { cid })
    return row and math.floor(row.amount or 0) or 0
end

local function chargeDamage(src, amount)
    local p = playerOf(src)
    local cid = cidOf(src)
    if not p or not cid or amount <= 0 then return 0 end

    local paid = 0
    if p.Functions.RemoveMoney('cash', amount, '택시 차량 변상') then
        paid = amount
    elseif p.Functions.RemoveMoney('bank', amount, '택시 차량 변상') then
        paid = amount
    end

    local left = amount - paid
    if left > 0 then
        MySQL.query.await([[
            INSERT INTO cookie_taxi_debt (citizenid, amount) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
        ]], { cid, left })
    end

    return paid, left
end

local function recallVehicle(src, silent)
    local a = assigned[src]
    if not a then return end

    if CookieTaxiCancelJob then CookieTaxiCancelJob(src, '차량 회수') end

    if CookieTaxiReleaseCalls then CookieTaxiReleaseCalls(src) end
    available[src] = nil

    local def = CookieTaxiVehicleDef(a.vehKey)
    local fee = 0

    if a.veh and DoesEntityExist(a.veh) then

        local health = GetEntityHealth(a.veh)
        local lost = math.max(0, (a.health0 or 1000) - health)
        local ratio = math.min(1.0, lost / 1000.0)
        fee = math.floor((def and def.repairFee or 0) * ratio)
        DeleteEntity(a.veh)
    else

        fee = math.floor(def and def.lossFee or 0)
    end

    assigned[src] = nil

    if fee > 0 then
        local _, left = chargeDamage(src, fee)
        if not silent then
            if left and left > 0 then
                notify(src, ('차량 변상금 %s원 중 %s원이 미납으로 남았습니다'):format(
                    CookieTaxiComma(fee), CookieTaxiComma(left)), true)
            else
                notify(src, ('차량 파손 변상금 %s원이 청구되었습니다'):format(CookieTaxiComma(fee)), true)
            end
        end
    elseif not silent then
        notify(src, '차량을 반납했습니다', false)
    end

end

local imgCache = nil

local function vehImages()
    if imgCache then return imgCache end

    local models = {}
    for _, v in ipairs(T.Vehicles or {}) do models[#models + 1] = v.model end
    if #models == 0 then imgCache = {} return imgCache end

    local out = {}
    local ok = pcall(function()
        local rows = MySQL.query.await(
            ('SELECT model, image FROM cookie_vehicle_image WHERE model IN (%s)')
                :format(('?,'):rep(#models):sub(1, -2)), models) or {}
        for _, r in ipairs(rows) do out[r.model] = r.image end
    end)
    if not ok then return {} end

    imgCache = out
    return imgCache
end

AddEventHandler('cookie_admin:server:vehicleImageSaved', function() imgCache = nil end)
RegisterCommand('taxiimgreload', function(src) if src == 0 then imgCache = nil  end end, false)

function CookieTaxiPushState(src)
    local skill = nil
    pcall(function() skill = exports.cookie_skill:get(src, T.Skill) end)

    local unlockedLevel = math.max(1, math.min(5, levelOf(src)))
    if type(skill) == 'table' then
        skill.level = unlockedLevel
        local okBonus, unlockedBonus = pcall(function()
            return exports.cookie_skill:bonusAtLevel(T.Skill, unlockedLevel)
        end)
        if okBonus and type(unlockedBonus) == 'table' then
            skill.bonus = unlockedBonus
        end
    end

    local a = assigned[src]
    local isFaction = factionOf(src) ~= nil

    local head = nil
    pcall(function() head = exports.cookie_core:getHeadInfo(src) end)

    local isAdmin = false
    pcall(function()
        isAdmin = (tonumber(exports.cookie_admin:getEffectiveLevel(src)) or 0) >= 3
    end)

    TriggerClientEvent('cookie_taxi:client:state', src, {
        isAdmin   = isAdmin,
        images    = vehImages(),
        available = CookieTaxiAvailable(src),
        npcCall   = CookieTaxiNpcCall(src),
        hired    = CookieTaxiIsHired(src),
        onDuty   = CookieTaxiOnDuty(src),
        level    = unlockedLevel,
        skill    = skill,
        debt     = debtOf(cidOf(src)),
        faction  = isFaction,
        assigned = a and { vehKey = a.vehKey, plate = a.plate } or nil,
        nick     = head and head.nick or nil,
        gobun    = head and head.gobun or nil,
    })
end

RegisterNetEvent('cookie_taxi:server:requestState', function()
    CookieTaxiPushState(source)
end)

RegisterNetEvent('cookie_taxi:server:hire', function()
    local src = source
    local p = playerOf(src)
    if not p then return end

    if CookieTaxiIsHired(src) then
        return notify(src, '이미 택시기사입니다', true)
    end

    local m = factionOf(src)
    if m then
        return notify(src, ('%s 소속이라 택시 일을 할 수 없습니다'):format(m.name), true)
    end

    local j = jobOf(src)
    if j and j.name and j.name ~= 'unemployed' and j.name ~= JOB then
        return notify(src, ('현재 %s 직업을 보유 중입니다. 기존 직업을 그만둔 뒤 취업하세요.'):format(j.label or j.name), true)
    end

    pcall(function() exports.cookie_admin:clearAllJobs(cidOf(src), JOB) end)

    local ok, res, err = pcall(function()
        return p.Functions.SetJob(JOB, 0)
    end)

    if not ok then

        return notify(src, '취업 처리 중 오류가 발생했습니다', true)
    end
    if res == false then

        return notify(src, '취업 처리에 실패했습니다 (서버 콘솔 확인)', true)
    end

    if not CookieTaxiIsHired(src) then
        local j = jobOf(src)

        return notify(src, '취업이 반영되지 않았습니다 (서버 콘솔 확인)', true)
    end

    refreshLabels(src)
    CookieTaxiPushState(src)

    TriggerClientEvent('cookie_taxi:client:line', src,
        T.Lines.hired or '잘 왔네. 오늘부터 자네도 택시기사야.')
    notify(src, '택시기사로 취업했습니다', false)

end)

RegisterNetEvent('cookie_taxi:server:quit', function()
    local src = source
    local p = playerOf(src)
    if not p or not CookieTaxiIsHired(src) then return end

    recallVehicle(src)
    pcall(function() p.Functions.SetJob('unemployed', 0) end)

    refreshLabels(src)
    CookieTaxiPushState(src)
    notify(src, '택시 일을 그만뒀습니다', false)

end)

AddEventHandler('cookie_taxi:server:forceQuit', function(src, reason)
    if not src or not assigned[src] then
        if src then CookieTaxiPushState(src) end
        return
    end

    recallVehicle(src, true)
    notify(src, ('택시 일이 해제되었습니다 (%s)'):format(reason or '직업 변경'), false)

end)

RegisterNetEvent('cookie_taxi:server:duty', function(on)
    local src = source
    local p = playerOf(src)
    if not p or not CookieTaxiIsHired(src) then
        return notify(src, '택시기사가 아닙니다', true)
    end

    local want = (on == true)
    if CookieTaxiOnDuty(src) == want then return end

    pcall(function() p.Functions.SetJobDuty(want) end)

    if not want then

        recallVehicle(src)
    end

    refreshLabels(src)
    CookieTaxiPushState(src)

    TriggerClientEvent('cookie_taxi:client:duty', src, { onDuty = want })
    if want then
        TriggerEvent('cookie_taxi:server:pushCallsTo', src)
        TriggerEvent('cookie_taxi:server:driverReady')
    end

    notify(src, want and '출근했습니다' or '퇴근했습니다', false)

end)

RegisterNetEvent('cookie_taxi:server:assign', function(vehKey)
    local src = source
    local p = playerOf(src)
    if not p then return end

    if not CookieTaxiIsHired(src) then
        return notify(src, '먼저 콜택시에 취업하세요', true)
    end
    if not CookieTaxiOnDuty(src) then
        return notify(src, '출근한 뒤에 차량을 배정받을 수 있습니다', true)
    end
    if assigned[src] then
        return notify(src, '이미 배정받은 택시가 있습니다', true)
    end

    local debt = debtOf(cidOf(src))
    if debt > 0 then
        return notify(src, ('미납 변상금 %s원을 먼저 갚으세요'):format(CookieTaxiComma(debt)), true)
    end

    local def = CookieTaxiVehicleDef(vehKey)
    if not def then return notify(src, '없는 차량입니다', true) end

    local lv = levelOf(src)
    if lv < (def.level or 1) then
        return notify(src, ('%s 는 LV%d 부터 배정됩니다'):format(def.label, def.level), true)
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local mePos = GetEntityCoords(ped)
    local meH = GetEntityHeading(ped)

    local rad = math.rad(meH)
    local fx, fy = -math.sin(rad), math.cos(rad)
    local rx, ry = math.cos(rad), math.sin(rad)

    local d = T.SpawnOffset or 5.0
    local spawnAt = vec4(
        mePos.x + rx * d - fx * (d * 0.6),
        mePos.y + ry * d - fy * (d * 0.6),
        mePos.z,
        (meH + 90.0) % 360.0
    )

    local plate = ('%s%04d'):format(T.PlatePrefix or 'TAXI', math.random(0, 9999))
    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({
            model = def.model,
            spawnSource = spawnAt,
            warp = false,
            bucket = GetPlayerRoutingBucket(src),
        })
    end)

    if not ok or not veh or not DoesEntityExist(veh) then

        return notify(src, '차량 배정에 실패했습니다 (모델 확인)', true)
    end

    SetVehicleNumberPlateText(veh, plate)
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)

    assigned[src] = {
        cid = cidOf(src),
        vehKey = def.key, plate = plate,
        veh = veh, netId = netId,
        health0 = GetEntityHealth(veh),
    }

    CookieTaxiPushState(src)
    TriggerClientEvent('cookie_taxi:client:assigned', src, {
        vehKey = def.key, label = def.label, plate = plate,
        netId = netId,
        ghost = T.GhostSeconds or 5,
    })

    TriggerEvent('cookie_taxi:server:driverReady')

    notify(src, ('%s 를 배정받았습니다'):format(def.label), false)

end)

RegisterNetEvent('cookie_taxi:server:returnVeh', function()
    local src = source
    if not assigned[src] then return notify(src, '배정받은 택시가 없습니다', true) end
    recallVehicle(src)
    CookieTaxiPushState(src)
end)

RegisterNetEvent('cookie_taxi:server:payDebt', function()
    local src = source
    local p = playerOf(src)
    local cid = cidOf(src)
    if not p or not cid then return end

    local debt = debtOf(cid)
    if debt <= 0 then return notify(src, '미납 변상금이 없습니다', false) end

    local paidOk = p.Functions.RemoveMoney('cash', debt, '택시 변상금 상환')
        or p.Functions.RemoveMoney('bank', debt, '택시 변상금 상환')
    if not paidOk then
        return notify(src, ('%s원이 부족합니다'):format(CookieTaxiComma(debt)), true)
    end

    MySQL.query.await('DELETE FROM cookie_taxi_debt WHERE citizenid = ?', { cid })
    notify(src, ('변상금 %s원을 갚았습니다'):format(CookieTaxiComma(debt)), false)
    CookieTaxiPushState(src)

end)

AddEventHandler('playerDropped', function()
    local src = source
    local a = assigned[src]
    if not a then return end

    local def = CookieTaxiVehicleDef(a.vehKey)
    local fee = 0
    if a.veh and DoesEntityExist(a.veh) then
        local lost = math.max(0, (a.health0 or 1000) - GetEntityHealth(a.veh))
        fee = math.floor((def and def.repairFee or 0) * math.min(1.0, lost / 1000.0))
        pcall(DeleteEntity, a.veh)
    else
        fee = math.floor(def and def.lossFee or 0)
    end

    if fee > 0 and a.cid then
        MySQL.query.await([[
            INSERT INTO cookie_taxi_debt (citizenid, amount) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount)
        ]], { a.cid, fee })

    end

    assigned[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, a in pairs(assigned) do
        if a.veh and DoesEntityExist(a.veh) then
            pcall(DeleteEntity, a.veh)
        end
    end
end)

CreateThread(function()
    Wait(3000)

    local prefix = T.PlatePrefix or 'TAXI'
    local n = 0

    for _, veh in ipairs(GetAllVehicles()) do
        local ok, plate = pcall(GetVehicleNumberPlateText, veh)
        if ok and type(plate) == 'string' then
            plate = plate:gsub('%s+$', '')
            if plate:sub(1, #prefix) == prefix then
                pcall(DeleteEntity, veh)
                n = n + 1
            end
        end
    end

    if n > 0 then

    end
end)

CreateThread(function()
    while true do
        Wait(30000)
        for src in pairs(assigned) do
            if not CookieTaxiIsHired(src) then

                recallVehicle(src, true)
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)

        local list = {}
        for src, a in pairs(assigned) do
            local free = CookieTaxiAvailable(src)
                and (not CookieTaxiHasJob or not CookieTaxiHasJob(src))
                and a.veh and DoesEntityExist(a.veh)

            if free then list[#list + 1] = a.netId end
        end

        TriggerClientEvent('cookie_taxi:client:taxiBlips', -1, list)
    end
end)