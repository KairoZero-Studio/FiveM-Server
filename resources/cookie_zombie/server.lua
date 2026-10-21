

local Z = Config.Zombie

local sessions = {}
local playerBucket = {}
local bucketSeq = Z.BucketBase or 7100
local lastKill = {}

local function cookieAllowAction(src, key, windowMs, maxCount)
    if GetResourceState('cookie_core') == 'started' then
        local ok, allowed = pcall(function() return exports.cookie_core:Allow(src, key, windowMs, maxCount) end)
        if ok then return allowed == true end
    end
    return true
end
local claimedKills = {}
local zombieModelHashes = {}
for _, name in ipairs(Z.Models or { Z.Model or 'a_m_m_tramp_01' }) do zombieModelHashes[joaat(name)] = true end

local function dbg(...) if Z.Debug then  end end

local function killTarget(n)
    local t = Z.KillTargets and Z.KillTargets[n]
    if t then return t end
    return 100 + math.max(0, n - 1) * (Z.KillTargetPerExtra or 150)
end

local function nearStaging(src)
    if playerBucket[src] then return false end
    local ped = GetPlayerPed(src); if not ped or ped == 0 then return false end
    local c = Z.StartNpc.coord
    return #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) <= (Z.StagingRadius or 12.0)
end

local function hasTicket(src)
    if not Z.RequireTicket then return true end
    local ok, cnt = pcall(function() return exports.ox_inventory:GetItemCount(src, Z.TicketItem) end)
    return ok and cnt and cnt >= 1
end

function zEndFor(src, reason)
    local bucket = playerBucket[src]
    playerBucket[src] = nil
    if bucket and sessions[bucket] then
        sessions[bucket].members[src] = nil
        local any = false; for _ in pairs(sessions[bucket].members) do any = true break end
        if not any then sessions[bucket] = nil; dbg('세션 종료(비었음)', bucket) end
    end
    SetPlayerRoutingBucket(src, 0)
    TriggerClientEvent('cookie_zombie:client:exit', src, { back = Z.PlayCoord, reason = reason })
end

local function aliveIds(s)
    local out = {}
    for m in pairs(s.members) do if not s.dead[m] then out[#out + 1] = m end end
    return out
end

function zEndSessionAll(bucket, reason)
    local s = sessions[bucket]; if not s then return end
    s.active = false
    local list = {}; for m in pairs(s.members) do list[#list + 1] = m end
    for _, m in ipairs(list) do
        if reason == 'win' then
            local wr = Z.WinReward or {}
            local w = math.random(wr.moneyMin or 80000, wr.moneyMax or 150000)
            local mp = exports.qbx_core:GetPlayer(m)
            if mp then pcall(function() mp.Functions.AddMoney(wr.account or 'bank', w, '좀비존 클리어 보상') end) end
            TriggerClientEvent('cookie_zombie:client:missionEnd', m, { result = 'win', reward = w, kills = s.kills, target = s.target })
        else
            TriggerClientEvent('cookie_zombie:client:missionEnd', m, { result = 'fail', kills = s.kills, target = s.target })
        end
        zEndFor(m, reason)
    end
    sessions[bucket] = nil
    for k in pairs(claimedKills) do if k:sub(1, #tostring(bucket)+1) == tostring(bucket)..':' then claimedKills[k]=nil end end
    dbg('세션 종료', bucket, reason)
end

RegisterNetEvent('cookie_zombie:server:start', function()
    local starter = source
    if playerBucket[starter] then return end

    local members = {}
    for _, sid in ipairs(GetPlayers()) do
        sid = tonumber(sid)
        if sid and (sid == starter or nearStaging(sid)) and #members < (Z.PartyMax or 4) then
            members[#members + 1] = sid
        end
    end
    if #members == 0 then members = { starter } end

    if Z.RequireTicket then
        for _, sid in ipairs(members) do
            if not hasTicket(sid) then
                TriggerClientEvent('cookie_admin:client:notify', starter, '파티원 중 입장 티켓이 없는 사람이 있습니다', true)
                return
            end
        end
        if Z.TicketConsume then
            for _, sid in ipairs(members) do pcall(function() exports.ox_inventory:RemoveItem(sid, Z.TicketItem, 1) end) end
        end
    end

    bucketSeq = bucketSeq + 1
    local bucket = bucketSeq
    local target = killTarget(#members)
    sessions[bucket] = { members = {}, dead = {}, target = target, kills = 0, active = true }
    pcall(function()
        SetRoutingBucketPopulationEnabled(bucket, false)
        SetRoutingBucketEntityLockdownMode(bucket, 'relaxed')
    end)
    for _, sid in ipairs(members) do
        SetPlayerRoutingBucket(sid, bucket)
        playerBucket[sid] = bucket
        sessions[bucket].members[sid] = true
        TriggerClientEvent('cookie_zombie:client:enter', sid, {
            bucket = bucket, target = target, count = #members, spawn = Z.PlayCoord,
        })
    end
    dbg('입장', ('bucket=%d 인원=%d 목표=%d'):format(bucket, #members, target))
end)

local function rateOk(src)
    local now = GetGameTimer(); local r = lastKill[src]
    if not r or (now - r.t) > (Z.RateWindowMs or 3000) then lastKill[src] = { t = now, n = 1 }; return true end
    r.n = r.n + 1; return r.n <= (Z.RateMax or 15)
end

RegisterNetEvent('cookie_zombie:server:kill', function(netId)
    local src = source
    if not cookieAllowAction(src, 'zombie_kill', 1000, 8) then return end
    local bucket = playerBucket[src]; if not bucket then return end
    local s = sessions[bucket]; if not s or not s.active then return end
    if not rateOk(src) then return end
    netId = tonumber(netId)
    if not netId or netId <= 0 then return end
    local claimKey = tostring(bucket)..':'..tostring(netId)
    if claimedKills[claimKey] then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) or GetEntityType(ent) ~= 1 then return end
    if (GetEntityHealth(ent) or 1) > 0 then return end
    if not zombieModelHashes[GetEntityModel(ent)] then return end
    local pp = GetPlayerPed(src)
    if pp == 0 or #(GetEntityCoords(pp) - GetEntityCoords(ent)) > 180.0 then return end
    claimedKills[claimKey] = true

    local rw = Z.KillReward or {}
    local p = exports.qbx_core:GetPlayer(src)
    if p then
        local a = math.random(rw.moneyMin or 800, rw.moneyMax or 2200)
        pcall(function() p.Functions.AddMoney(rw.account or 'cash', a, '좀비 처치 보상') end)
    end
    pcall(function() exports.cookie_skill:addExp(src, 'zombie', rw.expPerKill or 1) end)
    for _, d in ipairs(Z.Drops or {}) do
        if d.item and math.random(1, 100) <= (d.chance or 0) then
            pcall(function() exports.ox_inventory:AddItem(src, d.item, math.random(d.min or 1, d.max or 1)) end)
        end
    end

    s.kills = s.kills + 1
    for m in pairs(s.members) do
        TriggerClientEvent('cookie_zombie:client:progress', m, { kills = s.kills, target = s.target })
    end

    if s.kills >= s.target then
        zEndSessionAll(bucket, 'win')
    end
end)

RegisterNetEvent('cookie_zombie:server:died', function()
    local src = source
    local bucket = playerBucket[src]; if not bucket then return end
    local s = sessions[bucket]; if not s or not s.active then return end
    if s.dead[src] then return end
    s.dead[src] = true

    local alive = aliveIds(s)
    if #alive == 0 then

        zEndSessionAll(bucket, 'fail')
    else

        TriggerClientEvent('cookie_zombie:client:spectate', src, { alive = alive })
        for m in pairs(s.members) do
            if not s.dead[m] then end
        end

        for m in pairs(s.members) do
            if s.dead[m] then TriggerClientEvent('cookie_zombie:client:aliveList', m, { alive = alive }) end
        end
    end
end)

RegisterNetEvent('cookie_zombie:server:leave', function()
    if playerBucket[source] then zEndFor(source, 'leave') end
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastKill[src] = nil
    local bucket = playerBucket[src]
    playerBucket[src] = nil
    if bucket and sessions[bucket] then
        local s = sessions[bucket]
        s.members[src] = nil; s.dead[src] = nil
        local anyMember = false; for _ in pairs(s.members) do anyMember = true break end
        if not anyMember then
            sessions[bucket] = nil
        elseif s.active then
            local anyAlive = false; for m in pairs(s.members) do if not s.dead[m] then anyAlive = true break end end
            if not anyAlive then zEndSessionAll(bucket, 'fail') end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(playerBucket) do pcall(function() SetPlayerRoutingBucket(src, 0) end) end
end)
