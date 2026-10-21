

local JOB = Config.Trucker.Job
local T = Config.Trucker

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function()
            return exports.cookie_core:Allow(src, key, windowMs, maxCount)
        end)
        if ok then return allowed == true end
    end
    return true
end

local function tlog(...) if T.Debug then  end end

local trucks = {}

local activeJob = {}

local destClaims = {}
local function destLocked(destId, forSrc)
    local c = destClaims[destId]
    if not c then return false end
    if c.releaseAt and os.time() >= c.releaseAt then destClaims[destId] = nil; return false end
    return c.by ~= forSrc
end

local function getP(src) return exports.qbx_core:GetPlayer(src) end
local function cidOf(src)
    local p = getP(src); return p and p.PlayerData and p.PlayerData.citizenid or nil
end
local function jobName(src)
    local p = getP(src); return p and p.PlayerData and p.PlayerData.job and p.PlayerData.job.name or nil
end
local function isHired(src) return jobName(src) == JOB end
local function onDuty(src)
    local p = getP(src); local j = p and p.PlayerData and p.PlayerData.job
    return j and j.name == JOB and j.onduty == true or false
end
local function notify(src, msg, err)
    TriggerClientEvent('cookie_admin:client:notify', src, msg, err and true or false)
end
local function levelOf(src)
    local ok, lv = pcall(function() return exports.cookie_admin:getCivilLevel(src, T.Job or T.Skill) end)
    return (ok and tonumber(lv)) or 1
end
local function skillRow(src)
    local ok, row = pcall(function() return exports.cookie_skill:get(src, T.Skill) end)
    return (ok and row) or nil
end
local function factionOf(src)
    local ok, m = pcall(function() return exports.cookie_admin:getFactionOf(src) end)
    return ok and m or nil
end

local function refreshLabels(src)
    TriggerEvent('cookie_admin:server:nameTagDirty', src)
    TriggerEvent('cookie_admin:server:jobDisplayDirty', src)
end

local PAYMULT = { 1.00, 1.10, 1.20, 1.35, 1.50 }
local function payMult(src)
    local lv = math.max(1, math.min(5, levelOf(src)))
    local ok, b = pcall(function() return exports.cookie_skill:bonusAtLevel(T.Skill, lv) end)
    if ok and type(b) == 'table' and tonumber(b.payMult) then
        return tonumber(b.payMult), lv
    end
    return PAYMULT[lv] or 1.0, lv
end

CreateThread(function()
    Wait(500)
    local ok, err = pcall(function()
        return exports.qbx_core:CreateJob(JOB, T.JobDef, true)
    end)
    if ok then
    else  end
end)

local function pushState(src)
    local hired = isHired(src)
    local lv = levelOf(src)
    local row = skillRow(src)
    TriggerClientEvent('cookie_trucker:client:state', src, {
        hired  = hired,
        onDuty = hired and onDuty(src) or false,
        level  = lv,
        exp    = row and (row.exp or row.total or 0) or 0,
        deliveries = row and (row.exp or 0) or 0,
        payMult = select(1, payMult(src)),
        hasTruck = trucks[src] ~= nil,
    })
end

local dialogNpc = {}
RegisterNetEvent('cookie_trucker:server:requestState', function(npcId)
    local src = source
    local n = tonumber(npcId)
    if n and n > 0 then dialogNpc[src] = math.floor(n) end
    pushState(src)
end)

RegisterNetEvent('cookie_trucker:server:hire', function()
    local src = source
    local p = getP(src); if not p then return end
    if isHired(src) then return notify(src, '이미 트럭기사입니다', true) end
    if factionOf(src) then return notify(src, '팩션 소속은 시민직에 취업할 수 없습니다', true) end

    local curJob = p.PlayerData and p.PlayerData.job
    if curJob and curJob.name and curJob.name ~= 'unemployed' and curJob.name ~= JOB then
        return notify(src, ('현재 %s 직업을 보유 중입니다. 기존 직업을 그만둔 뒤 취업하세요.'):format(curJob.label or curJob.name), true)
    end

    pcall(function() exports.cookie_admin:clearAllJobs(cidOf(src), JOB) end)
    local res = p.Functions.SetJob(JOB, 0)
    if res == false or not isHired(src) then

        return notify(src, '취업이 반영되지 않았습니다 (콘솔 확인)', true)
    end

    refreshLabels(src)
    TriggerClientEvent('cookie_trucker:client:line', src, T.Lines.hired)
    notify(src, '트럭커로 취업했습니다', false)
    pushState(src)

end)

RegisterNetEvent('cookie_trucker:server:quit', function()
    local src = source
    local p = getP(src); if not p or not isHired(src) then return end
    recallTruck(src)
    cancelJob(src)
    pcall(function() p.Functions.SetJob('unemployed', 0) end)
    refreshLabels(src)
    notify(src, '트럭 일을 그만뒀습니다', false)
    pushState(src)

end)

AddEventHandler('cookie_trucker:server:forceQuit', function(src, reason)
    if not src then return end
    recallTruck(src)
    cancelJob(src)
    notify(src, ('트럭 일이 해제되었습니다 (%s)'):format(reason or '직업 변경'), false)
    pushState(src)

end)

RegisterNetEvent('cookie_trucker:server:duty', function(on)
    local src = source
    local p = getP(src); if not p or not isHired(src) then return notify(src, '트럭커가 아닙니다', true) end
    local want = (on == true)
    if onDuty(src) == want then return end
    pcall(function() p.Functions.SetJobDuty(want) end)
    if not want then recallTruck(src); cancelJob(src) end
    refreshLabels(src)
    notify(src, want and '출근했습니다' or '퇴근했습니다', false)
    pushState(src)
end)

RegisterNetEvent('cookie_trucker:server:requestJobs', function()
    if CookieTruckerPayCfg then CookieTruckerPayCfg() end
    local src = source
    if not isHired(src) then return end
    local out = {}
    local dbDests = (CookieTruckerDests and CookieTruckerDests(dialogNpc[src])) or {}

    local lv = levelOf(src)
    local cap = lv * ((T.Cargo and T.Cargo.PerLevel) or 15)
    local cargo = T.Cargo or {}
    local avgBox = math.floor(((cargo.PriceMin or 315) + (cargo.PriceMax or 450)) / 2)
    for _, d in ipairs(dbDests) do
        if d.x and not destLocked(d.id, src) then
            local distKm = math.max(1, math.floor(#(T.Origin - vec3(d.x, d.y, d.z)) / 1000.0 + 0.5))
            local estPay = math.min(T.MaxPay, cap * avgBox + distKm * (T.PerKmReward or 500))
            out[#out+1] = { id = 'd' .. d.id, dest = d.label, from = '물류창고',
                            distKm = distKm, pay = estPay, img = d.image }
        end
    end
    TriggerClientEvent('cookie_trucker:client:jobs', src, out)
end)

local spawnRot = {}
function callTruck(src)
    if trucks[src] then return true end
    if not onDuty(src) then notify(src, T.Lines.needDuty, true); return false end

    local spawnAt
    local npcId = dialogNpc[src]
    local slots = (npcId and CookieTruckerSpawns) and CookieTruckerSpawns(npcId) or {}
    if #slots > 0 then
        local rot = spawnRot[npcId] or 0
        local slot = slots[(rot % #slots) + 1]
        spawnRot[npcId] = rot + 1
        spawnAt = vec4(slot.x, slot.y, slot.z, slot.h or 0.0)
    else

        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped); local h = GetEntityHeading(ped)
        local rad = math.rad(h)
        spawnAt = vec4(c.x + math.sin(rad) * T.SpawnOffset + math.cos(rad) * 2.0,
                       c.y - math.cos(rad) * T.SpawnOffset + math.sin(rad) * 2.0, c.z, h)
        notify(src, '출발지(주차장)가 설정되지 않아 옆에 스폰합니다', true)
    end

    local plate = ('%s%04d'):format(T.PlatePrefix, math.random(0, 9999))
    local ok, netId, veh = pcall(function()
        return qbx.spawnVehicle({ model = T.Truck.model, spawnSource = spawnAt, warp = false, bucket = GetPlayerRoutingBucket(src) })
    end)

    if type(netId) == 'table' then netId, veh = netId.netId, netId.veh end
    if not ok or not veh or veh == 0 then
        notify(src, '트럭 호출 실패 (모델 확인: ' .. tostring(T.Truck.model) .. ')', true)

        return false
    end
    pcall(function() SetVehicleNumberPlateText(veh, plate) end)
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)
    trucks[src] = { veh = veh, netId = netId, plate = plate }

    local lv = levelOf(src)
    local cargo = T.Cargo or { PerLevel = 15, PriceMin = 300, PriceMax = 415 }
    TriggerClientEvent('cookie_trucker:client:trucked', src, {
        netId    = netId,
        ghost    = T.GhostSeconds,
        alpha    = T.GhostAlpha,
        outline  = T.SpawnOutlineSeconds or 10,
        level    = lv,
        cap      = lv * (cargo.PerLevel or 15),
        loaded   = 0,
        priceMin = cargo.PriceMin or 300,
        priceMax = cargo.PriceMax or 415,

        npcCalled  = T.Lines.called,
        acceptLine = T.Lines.acceptGo,
        warnLine   = T.Lines.spawnWarn,
        goLine     = T.Lines.goStock,
    })

    return true
end

function recallTruck(src)
    local t = trucks[src]; if not t then return end
    pcall(function() if t.veh and DoesEntityExist(t.veh) then DeleteEntity(t.veh) end end)
    trucks[src] = nil
end

local function vc(t) return vec3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end
local function nearServer(src, c, r)
    if not c then return false end
    local ped = GetPlayerPed(src); if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vc(c)) <= (r or 8.0)
end

local function resolveDest(npcId, destId)
    local dbDests = (CookieTruckerDests and CookieTruckerDests(npcId)) or {}
    for _, d in ipairs(dbDests) do
        if ('d' .. d.id) == destId and d.x then
            return { id = d.id, label = d.label, x = d.x, y = d.y, z = d.z, pay = d.pay }
        end
    end
    return nil
end

local function randomStock(npcId)
    local s = (CookieTruckerStocks and CookieTruckerStocks(npcId)) or {}
    local pool = {}
    for _, r in ipairs(s) do if r.x then pool[#pool+1] = r end end
    if #pool == 0 then return nil end
    local r = pool[math.random(1, #pool)]
    return { label = r.label, x = r.x, y = r.y, z = r.z }
end
local function firstSpawn(npcId)
    local s = (CookieTruckerSpawns and CookieTruckerSpawns(npcId)) or {}
    local r = s[1]
    if r and r.x then return { label = r.label or '운송지역', x = r.x, y = r.y, z = r.z } end
    return nil
end

function cancelJob(src)
    local j = activeJob[src]; if not j then return end
    if j.destId and destClaims[j.destId] and destClaims[j.destId].by == src and not destClaims[j.destId].releaseAt then
        destClaims[j.destId] = nil
    end
    activeJob[src] = nil
    TriggerClientEvent('cookie_trucker:client:jobCancel', src)
end

RegisterNetEvent('cookie_trucker:server:accept', function(destId)
    local src = source
    if not cookieAllowAction(src, 'trucker_accept', 1000, 1) then return end
    if not isHired(src) then return notify(src, T.Lines.needHire, true) end
    if not onDuty(src) then return notify(src, T.Lines.needDuty, true) end
    if activeJob[src] then return notify(src, '이미 진행 중인 배송이 있습니다', true) end

    local npcId = dialogNpc[src]
    local dest = resolveDest(npcId, destId)
    if not dest then return notify(src, '배송지를 찾을 수 없습니다', true) end
    if destLocked(dest.id, src) then return notify(src, '다른 기사가 진행 중이거나 최근 완료한 배송지입니다', true) end
    local stock = randomStock(npcId)
    if not stock then return notify(src, '이 관리인의 물류창고(재고지)가 설정되지 않았습니다', true) end
    local ret = firstSpawn(npcId) or { label = '운송지역', x = T.Origin.x, y = T.Origin.y, z = T.Origin.z }

    if not callTruck(src) then return end

    local lv = levelOf(src)
    local cap = lv * ((T.Cargo and T.Cargo.PerLevel) or 15)

    local distKm = math.max(1, math.floor(#(T.Origin - vc(dest)) / 1000.0 + 0.5))
    local cargo = T.Cargo or {}
    local pmin, pmax = cargo.PriceMin or 315, cargo.PriceMax or 450
    local boxReward = 0
    for _ = 1, cap do boxReward = boxReward + math.random(pmin, pmax) end
    local pay = math.min(T.MaxPay, boxReward + distKm * (T.PerKmReward or 500))

    destClaims[dest.id] = { by = src }
    activeJob[src] = { stage = 'go_stock', stock = stock, dest = dest, ret = ret, destId = dest.id,
                       cap = cap, loaded = 0, distKm = distKm, pay = pay, t0 = os.time() }

    TriggerClientEvent('cookie_trucker:client:jobStart', src, {
        stock = stock, dest = dest, ret = ret, cap = cap, distKm = distKm,
        lines = {
            atStock = T.Lines.atStock, loadingGo = T.Lines.loadingGo, loadDone = T.Lines.loadDone,
            toDeliver = T.Lines.toDeliver, atDest = T.Lines.atDest, allUnload = T.Lines.allUnload,
        },
    })

    pushState(src)
end)

RegisterNetEvent('cookie_trucker:server:loadOne', function()
    local src = source
    if not cookieAllowAction(src, 'trucker_load', 300, 1) then return end
    local j = activeJob[src]; if not j then return end
    if j.stage ~= 'go_stock' and j.stage ~= 'loading' then return end
    if j.loaded >= j.cap then return end
    if not nearServer(src, j.stock, 30.0) then return end
    j.stage = 'loading'
    j.loaded = j.loaded + 1
    local full = j.loaded >= j.cap
    if full then j.stage = 'go_deliver' end
    TriggerClientEvent('cookie_trucker:client:cargo', src, { loaded = j.loaded, cap = j.cap, full = full, dir = 'load' })
end)

RegisterNetEvent('cookie_trucker:server:unloadOne', function()
    local src = source
    if not cookieAllowAction(src, 'trucker_unload', 300, 1) then return end
    local j = activeJob[src]; if not j then return end
    if j.stage ~= 'go_deliver' and j.stage ~= 'unloading' then return end
    if j.loaded <= 0 then return end
    if not nearServer(src, j.dest, 30.0) then return end
    j.stage = 'unloading'
    j.loaded = j.loaded - 1
    local empty = j.loaded <= 0
    if empty then j.stage = 'return' end
    TriggerClientEvent('cookie_trucker:client:cargo', src, { loaded = j.loaded, cap = j.cap, empty = empty, dir = 'unload' })
end)

RegisterNetEvent('cookie_trucker:server:finishJob', function()
    local src = source
    if not cookieAllowAction(src, 'trucker_finish', 1200, 1) then return end
    local j = activeJob[src]; if not j or j.stage ~= 'return' then return end
    if not nearServer(src, j.ret, 32.0) then return end

    local pay = j.pay or math.min(T.MaxPay, math.floor((T.BasePay + T.PerKm * j.distKm) * select(1, payMult(src))))
    local p = getP(src)
    if not p then return end
    local okPay, paid = pcall(function() return p.Functions.AddMoney('bank', pay, '트럭 배송 보수') end)
    if not okPay or paid == false then return notify(src, '배송 보수 지급에 실패했습니다. 다시 완료를 눌러주세요.', true) end
    pcall(function() exports.cookie_skill:addExp(src, T.Skill, T.ExpPerDelivery or 1) end)
    pcall(function() exports.cookie_skill:record(src, T.Skill, pay) end)

    if j.destId then destClaims[j.destId] = { by = src, releaseAt = os.time() + (T.ClaimCooldown or 300) } end

    recallTruck(src)
    activeJob[src] = nil
    TriggerClientEvent('cookie_trucker:client:receipt', src, {
        pay = pay, from = j.stock.label or '물류창고', to = j.dest.label or '배송지',
        date = os.date('%Y-%m-%d %H:%M'),
    })

    pushState(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    cancelJob(src)
    recallTruck(src)
    dialogNpc[src] = nil
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, t in pairs(trucks) do
        pcall(function() if t.veh and DoesEntityExist(t.veh) then DeleteEntity(t.veh) end end)
    end
end)
