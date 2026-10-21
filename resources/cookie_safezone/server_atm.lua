-- COOKIE ATM 비콘 V4
-- callback.await를 사용하지 않고 NetEvent 요청/응답으로 처리한다.
-- 현금 <-> 계좌 이동, 수수료 없음.

local atmBusy = {}

local function formatMoney(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local rev = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return rev:gsub('^,', '')
end

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function getBalanceFromPlayer(player)
    local money = player and player.PlayerData and player.PlayerData.money or {}
    return {
        cash = math.max(0, math.floor(tonumber(money and money.cash) or 0)),
        bank = math.max(0, math.floor(tonumber(money and money.bank) or 0)),
    }
end

local function sendBalance(src, player)
    local b = getBalanceFromPlayer(player or getPlayer(src))
    TriggerClientEvent('cookie_safezone:client:atmBalance', src, b)
end

local function sendResult(src, ok, message, player)
    local b = getBalanceFromPlayer(player or getPlayer(src))
    atmBusy[src] = nil
    TriggerClientEvent('cookie_safezone:client:atmTransferResult', src, {
        ok = ok == true,
        message = message or '',
        cash = b.cash,
        bank = b.bank,
    })
end

RegisterNetEvent('cookie_safezone:server:requestAtmBalance', function()
    local src = source
    if not CookieSafezoneAllowAction(src, 'atm_balance', 500, 2) then return end
    if not CookieSafezonePlayerNearType(src, 'atm', 4.0) then return end
    sendBalance(src)
end)

RegisterNetEvent('cookie_safezone:server:atmTransfer', function(direction, rawAmount)
    local src = source
    if not CookieSafezoneAllowAction(src, 'atm_transfer', 800, 1) then return end
    if not CookieSafezonePlayerNearType(src, 'atm', 4.0) then return sendResult(src, false, 'ATM 근처에서만 거래할 수 있습니다.') end

    if atmBusy[src] then
        return TriggerClientEvent('cookie_safezone:client:atmTransferResult', src, {
            ok = false,
            message = 'ATM 거래 처리 중입니다. 잠시 후 다시 시도하세요.',
            cash = getBalanceFromPlayer(getPlayer(src)).cash,
            bank = getBalanceFromPlayer(getPlayer(src)).bank,
        })
    end

    atmBusy[src] = true

    direction = tostring(direction or '')
    if direction ~= 'deposit' and direction ~= 'withdraw' then
        return sendResult(src, false, '올바르지 않은 거래 요청입니다.')
    end

    local amount = tonumber(rawAmount)
    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then
        return sendResult(src, false, '금액이 올바르지 않습니다.')
    end

    amount = math.floor(amount)
    if amount < 1 or amount > 2000000000 then
        return sendResult(src, false, '1원 이상 올바른 금액을 입력하세요.')
    end

    local player = getPlayer(src)
    if not player or not player.Functions then
        return sendResult(src, false, '플레이어 정보를 불러오지 못했습니다.', player)
    end

    local from = direction == 'deposit' and 'cash' or 'bank'
    local to = direction == 'deposit' and 'bank' or 'cash'
    local fromName = direction == 'deposit' and '현금' or '계좌'
    local actionName = direction == 'deposit' and '입금' or '출금'

    local b = getBalanceFromPlayer(player)
    if (tonumber(b[from]) or 0) < amount then
        return sendResult(src, false, ('%s 잔액이 부족합니다.'):format(fromName), player)
    end

    -- 이 서버의 기존 금전 처리 방식과 동일하게 Player.Functions를 사용한다.
    local okRemove, removed = pcall(function()
        return player.Functions.RemoveMoney(from, amount, ('ATM %s'):format(actionName))
    end)
    if not okRemove or not removed then
        return sendResult(src, false, ('%s 잔액이 부족하거나 거래에 실패했습니다.'):format(fromName), player)
    end

    local okAdd, added = pcall(function()
        return player.Functions.AddMoney(to, amount, ('ATM %s'):format(actionName))
    end)
    if not okAdd or not added then
        -- 입금/출금 반대편 지급 실패 시 원래 계정으로 즉시 복구한다.
        pcall(function() player.Functions.AddMoney(from, amount, 'ATM 거래 실패 복구') end)
        return sendResult(src, false, '거래 처리에 실패했습니다. 금액은 복구되었습니다.', player)
    end

    sendResult(src, true, ('%s %s원 완료'):format(actionName, formatMoney(amount)), player)
end)

AddEventHandler('playerDropped', function()
    atmBusy[source] = nil
end)
