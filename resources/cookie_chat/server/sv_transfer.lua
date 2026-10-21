

local MIN_AMOUNT = 1
local MAX_AMOUNT = 100000000
local COOLDOWN_MS = 2000

local lastPay = {}

local function notify(src, msg)
    TriggerClientEvent('chat:addMessage', src, {
        templateId = 'cookie_system',
        args = { msg }
    })
end

local function nameOf(src)
    local ok, info = pcall(function() return exports.cookie_core:getHeadInfo(src) end)
    if ok and info then
        return ('%s (%s)'):format(info.nick or '플레이어', tostring(info.gobun or '-'))
    end
    return GetPlayerName(src) or '플레이어'
end

RegisterNetEvent('cookie_chat:server:transfer', function(targetSrc, amount)
    local src = source

    targetSrc = tonumber(targetSrc)
    amount = tonumber(amount)

    if not targetSrc or not amount then
        return notify(src, '송금 정보가 올바르지 않습니다.')
    end
    amount = math.floor(amount)
    if amount < MIN_AMOUNT or amount > MAX_AMOUNT then
        return notify(src, ('송금 금액은 %s원 ~ %s원 사이여야 합니다.'):format(MIN_AMOUNT, MAX_AMOUNT))
    end
    if targetSrc == src then
        return notify(src, '자기 자신에게는 송금할 수 없습니다.')
    end

    local now = GetGameTimer()
    if lastPay[src] and (now - lastPay[src]) < COOLDOWN_MS then
        return notify(src, '잠시 후 다시 시도해주세요.')
    end
    lastPay[src] = now

    local sender = exports.qbx_core:GetPlayer(src)
    local target = exports.qbx_core:GetPlayer(targetSrc)
    if not sender then
        return notify(src, '내 계정 정보를 불러오지 못했습니다.')
    end
    if not target then
        return notify(src, '상대가 접속 중이 아닙니다.')
    end

    local bank = (sender.PlayerData and sender.PlayerData.money and sender.PlayerData.money.bank) or 0
    if bank < amount then
        return notify(src, ('은행 잔액이 부족합니다. (잔액 %s원)'):format(bank))
    end

    local okOut = sender.Functions.RemoveMoney('bank', amount, '채팅 은행송금')
    if not okOut then
        return notify(src, '출금에 실패했습니다.')
    end

    local okIn = target.Functions.AddMoney('bank', amount, '채팅 은행송금')
    if not okIn then

        sender.Functions.AddMoney('bank', amount, '송금 실패 원복')
        return notify(src, '상대에게 입금하지 못했습니다. 금액은 되돌려졌습니다.')
    end

    local sName, tName = nameOf(src), nameOf(targetSrc)
    local won = ('%d'):format(amount):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')

    notify(src, ('%s 님에게 %s원을 송금했습니다.'):format(tName, won))
    notify(targetSrc, ('%s 님에게서 %s원을 받았습니다.'):format(sName, won))

end)

AddEventHandler('playerDropped', function()
    lastPay[source] = nil
end)
