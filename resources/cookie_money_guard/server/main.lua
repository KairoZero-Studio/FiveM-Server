local protected = {
    cash = true,
    bank = true,
    crypto = true,
}

local hookIds = {}
local repairing = false

local function moneyNumber(value)
    value = tonumber(value)
    if not value then return 0 end
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.floor(value + 0.5)
end

local function clampOnlinePlayer(src, player)
    if not player or not player.PlayerData or not player.PlayerData.money then return 0 end

    local repaired = 0
    for moneyType in pairs(protected) do
        local current = moneyNumber(player.PlayerData.money[moneyType])
        if current < 0 then
            local ok = exports.qbx_core:SetMoney(src, moneyType, 0, 'COOKIE MONEY GUARD negative balance repair')
            if ok ~= false then
                repaired = repaired + 1
                print(('[COOKIE MONEY GUARD] repaired online %s balance for source %s: %s -> 0')
                    :format(moneyType, tostring(src), tostring(current)))
            end
        end
    end
    return repaired
end

local function repairOnlinePlayers()
    local repaired = 0
    local players = exports.qbx_core:GetQBPlayers()
    if type(players) ~= 'table' then return 0 end

    for src, player in pairs(players) do
        repaired = repaired + clampOnlinePlayer(src, player)
    end
    return repaired
end

local function repairDatabasePlayers()
    if repairing then return 0 end
    repairing = true

    local changed = 0
    local rows = MySQL.query.await('SELECT citizenid, money FROM players') or {}

    for _, row in ipairs(rows) do
        local ok, money = pcall(json.decode, row.money or '{}')
        if ok and type(money) == 'table' then
            local dirty = false
            for moneyType in pairs(protected) do
                local current = moneyNumber(money[moneyType])
                if current < 0 then
                    money[moneyType] = 0
                    dirty = true
                end
            end

            if dirty then
                MySQL.update.await(
                    'UPDATE players SET money = ? WHERE citizenid = ?',
                    { json.encode(money), row.citizenid }
                )
                changed = changed + 1
            end
        end
    end

    repairing = false
    if changed > 0 then
        print(('[COOKIE MONEY GUARD] repaired %d player DB row(s) with negative balances.'):format(changed))
    end
    return changed
end

local function registerHooks()
    hookIds.removeMoney = exports.qbx_core:registerHook('removeMoney', function(payload)
        if type(payload) ~= 'table' or not protected[payload.moneyType] then return true end

        local src = tonumber(payload.source)
        local amount = moneyNumber(payload.amount)
        if not src or amount < 0 then return false end

        local current = exports.qbx_core:GetMoney(src, payload.moneyType)
        current = moneyNumber(current)

        if current < 0 then
            exports.qbx_core:SetMoney(src, payload.moneyType, 0, 'COOKIE MONEY GUARD auto repair')
            print(('[COOKIE MONEY GUARD] blocked %s withdrawal: balance was already negative (%s). source=%s')
                :format(payload.moneyType, current, src))
            return false
        end

        if current - amount < 0 then
            print(('[COOKIE MONEY GUARD] blocked overdraft: source=%s type=%s balance=%s requested=%s')
                :format(src, payload.moneyType, current, amount))
            return false
        end

        return true
    end)

    hookIds.setMoney = exports.qbx_core:registerHook('setMoney', function(payload)
        if type(payload) ~= 'table' or not protected[payload.moneyType] then return true end
        local amount = tonumber(payload.amount)
        if not amount or amount < 0 then
            print(('[COOKIE MONEY GUARD] blocked negative SetMoney: source=%s type=%s amount=%s')
                :format(tostring(payload.source), tostring(payload.moneyType), tostring(payload.amount)))
            return false
        end
        return true
    end)
end

local function repairAll()
    local db = repairDatabasePlayers()
    local online = repairOnlinePlayers()
    print(('[COOKIE MONEY GUARD] scan complete. DB repaired=%d, online balances repaired=%d')
        :format(db, online))
end

CreateThread(function()
    while GetResourceState('qbx_core') ~= 'started' do
        Wait(500)
    end

    Wait(1000)
    registerHooks()
    repairAll()
end)

-- Fix a character immediately when they finish loading.
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    SetTimeout(1000, function()
        if not GetPlayerName(src) then return end
        clampOnlinePlayer(src, exports.qbx_core:GetPlayer(src))
    end)
end)

-- Safety net: catches another resource directly corrupting an in-memory balance.
CreateThread(function()
    while true do
        Wait(30000)
        repairOnlinePlayers()
    end
end)

-- Server console / RCON command for manual verification and repair.
RegisterCommand('moneyguard_check', function(src)
    if src ~= 0 then return end
    repairAll()
end, true)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if hookIds.removeMoney then pcall(function() exports.qbx_core:removeHooks(hookIds.removeMoney) end) end
    if hookIds.setMoney then pcall(function() exports.qbx_core:removeHooks(hookIds.setMoney) end) end
end)
