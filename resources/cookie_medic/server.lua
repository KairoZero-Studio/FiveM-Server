

local DEATH_BAG = 'qbx_medical:deathState'
local ALIVE = 1

local declared = {}
local reviveAt = {}
local lastState = {}
local boosterReserved = {}
local reviveCompleting = {}

local function isDown(src)
    local st = Player(src).state[DEATH_BAG]
    return st ~= nil and st ~= ALIVE
end

local function nickOf(src)
    local head = Player(src).state.ckHead
    if head and head.nick and head.nick ~= '' then return head.nick end
    return '무명'
end

local function systemMsg(text)
    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'cookie_system',
        args = { text },
    })
end

local function rpMsg(pre, hl, post, tone)
    TriggerClientEvent('chat:addMessage', -1, {
        templateId = 'cookie_rp',
        color = false,
        args = { pre, hl, post, tone },
    })
end

local function reviveFull(src)
    local ok, err = pcall(function()
        exports.qbx_medical:Revive(src)
        exports.qbx_medical:Heal(src)
    end)

    if ok then

    else

    end
end

local function boosterItemName()
    return tostring(MedicConfig.ReviveBoosterItem or 'self_regenerator')
end

local function reserveReviveBooster(src)
    if not MedicConfig.ReviveBoosterConsume then return false end
    if GetResourceState('ox_inventory') ~= 'started' then return false end

    local item = boosterItemName()
    local okCount, count = pcall(function()
        return exports.ox_inventory:Search(src, 'count', item)
    end)
    if not okCount or (tonumber(count) or 0) < 1 then return false end

    local okRemove, removed = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, 1)
    end)
    if not okRemove or not removed then return false end

    boosterReserved[src] = true
    return true
end

local function refundReservedBooster(src)
    if not boosterReserved[src] then return end
    boosterReserved[src] = nil
    if GetResourceState('ox_inventory') ~= 'started' then return end

    local item = boosterItemName()
    local ok, added = pcall(function()
        return exports.ox_inventory:AddItem(src, item, 1)
    end)
    if not ok or not added then
        print(('^1[cookie_medic]^7 자가재생동기 환불 실패: player=%s item=%s'):format(tostring(src), item))
    end
end

AddStateBagChangeHandler(DEATH_BAG, nil, function(bagName, _, value)
    local src = GetPlayerFromStateBagName(bagName)
    if not src or src == 0 then return end

    local prev = lastState[src]
    lastState[src] = value

    local wasDown = prev ~= nil and prev ~= ALIVE
    local nowDown = value ~= nil and value ~= ALIVE

    if nowDown and not wasDown then

    elseif wasDown and not nowDown then
        -- 재생동기 카운트 중 EMS/관리자 등 외부 소생이 먼저 이루어지면 아이템을 돌려줍니다.
        if boosterReserved[src] and not reviveCompleting[src] then
            refundReservedBooster(src)
        end

        declared[src] = nil
        reviveAt[src] = nil
        reviveCompleting[src] = nil
        boosterReserved[src] = nil
    end
end)

RegisterNetEvent('cookie_medic:server:declare', function(kind)
    local src = source

    if not isDown(src) then return end

    if kind == 'revive' then
        if reviveAt[src] then return end

        local secs = math.floor(MedicConfig.ReviveSeconds or 10)
        local boosted = reserveReviveBooster(src)
        if boosted then
            secs = math.max(1, math.floor(MedicConfig.ReviveBoosterSeconds or 3))
        end

        local token = {}
        reviveAt[src] = token
        TriggerClientEvent('cookie_medic:client:reviveMode', src, boosted, secs)

        CreateThread(function()
            for left = secs, 1, -1 do
                if reviveAt[src] ~= token then return end
                if not isDown(src) then reviveAt[src] = nil return end

                TriggerClientEvent('cookie_medic:client:reviveCount', src, left)
                Wait(1000)
            end
            if reviveAt[src] ~= token then return end
            if GetPlayerName(src) == nil then reviveAt[src] = nil return end
            if not isDown(src) then reviveAt[src] = nil return end

            reviveCompleting[src] = true
            reviveFull(src)
            declared[src] = nil
            reviveAt[src] = nil
            boosterReserved[src] = nil
            reviveCompleting[src] = nil

        end)
        return
    end

    local d = MedicConfig.Declares[kind]
    if not d then return end

    declared[src] = declared[src] or {}
    if declared[src][kind] then return end
    declared[src][kind] = true

    local nick = nickOf(src)
    rpMsg(d.pre:format(nick), d.hl, d.post, d.tone)

    if d.status then
        TriggerClientEvent('cookie_medic:client:status', src, d.status)
    end

end)

AddEventHandler('playerDropped', function()
    local src = source
    declared[src] = nil
    reviveAt[src] = nil
    lastState[src] = nil
    boosterReserved[src] = nil
    reviveCompleting[src] = nil
end)

