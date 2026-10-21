local detained = false
local detentionEndsAt = 0
local detentionCharge = ''

local chaseVisible = false
local chaseId = nil
local appearanceVisible = false
local appearanceId = nil
local appearanceEndsAt = 0
local appearanceRole = nil
local appearanceTarget = nil

local function notify(message, isError)
    TriggerEvent('cookie_admin:client:notify', message, isError == true)
end

-- 벌금/구금 벌금 영수증은 포커스를 빼앗지 않는 HUD 형태로 표시합니다.
RegisterNetEvent('cookie_police:client:fineReceipt', function(data)
    data = type(data) == 'table' and data or {}
    SendNUIMessage({
        action = 'fineReceipt',
        data = {
            receiptNo = tostring(data.receiptNo or '-'),
            faction = tostring(data.faction or '경찰청'),
            officer = tostring(data.officer or '-'),
            reason = tostring(data.reason or '-'),
            amount = math.max(0, math.floor(tonumber(data.amount) or 0)),
            paid = data.paid == true,
            paymentMethod = tostring(data.paymentMethod or (data.paid == true and '납부 완료' or '미납')),
            issuedAt = tostring(data.issuedAt or '')
        }
    })
end)

RegisterNetEvent('cookie_police:client:openTargetInventory', function(targetServerId)
    if GetResourceState('ox_inventory') ~= 'started' then
        return notify('ox_inventory가 실행 중이 아닙니다.', true)
    end

    local ok, err = pcall(function()
        exports.ox_inventory:openInventory('player', tonumber(targetServerId))
    end)
    if not ok then
        notify(('소지품 검사를 열지 못했습니다: %s'):format(tostring(err)), true)
    end
end)

RegisterNetEvent('cookie_police:client:chaseHud', function(data)
    data = type(data) == 'table' and data or {}

    if data.visible == false then
        if not data.chaseId or tonumber(data.chaseId) == tonumber(chaseId) then
            chaseVisible = false
            chaseId = nil
            SendNUIMessage({ action='chase', visible=false })
        end
        return
    end

    chaseVisible = true
    chaseId = tonumber(data.chaseId)

    SendNUIMessage({
        action='chase',
        visible=true,
        chaseId=chaseId,
        kind=data.kind,
        role=data.role,
        target=data.target,
        reason=data.reason,
        seconds=tonumber(data.seconds) or 0
    })
end)


RegisterNetEvent('cookie_police:client:appearanceRequest', function(data)
    data = type(data) == 'table' and data or {}
    CreateThread(function()
        local targetName = tostring(data.targetName or '시민')
        local faction = tostring(data.faction or '경찰/보안국')
        local reason = tostring(data.reason or '조사')
        local result = lib.alertDialog({
            header = faction .. ' 출석 요구서',
            content = ('%s님, %s로 출석 바랍니다.\n\n수락 시 10분 이내 출석해야 합니다.\n거절 시 즉시 수배 등록됩니다.'):format(targetName, reason),
            centered = true,
            cancel = true,
            labels = { confirm = '수락', cancel = '거절' }
        })
        TriggerServerEvent('cookie_police:server:appearanceRespond', tonumber(data.id), result == 'confirm')
    end)
end)

RegisterNetEvent('cookie_police:client:appearanceHud', function(data)
    data = type(data) == 'table' and data or {}
    if data.visible == false then
        if not data.id or tonumber(data.id) == tonumber(appearanceId) then
            appearanceVisible = false
            appearanceId = nil
            appearanceEndsAt = 0
            appearanceRole = nil
            appearanceTarget = nil
            SendNUIMessage({ action='appearance', visible=false })
        end
        return
    end

    appearanceVisible = true
    appearanceId = tonumber(data.id)
    appearanceRole = tostring(data.role or 'target')
    appearanceTarget = tostring(data.target or '-')
    appearanceEndsAt = GetGameTimer() + math.max(0, tonumber(data.seconds) or 0) * 1000
    SendNUIMessage({
        action='appearance', visible=true,
        role=appearanceRole, target=appearanceTarget,
        seconds=math.max(0, tonumber(data.seconds) or 0)
    })
end)

CreateThread(function()
    while true do
        if appearanceVisible then
            local remain = math.max(0, math.ceil((appearanceEndsAt - GetGameTimer()) / 1000))
            SendNUIMessage({ action='appearanceTick', seconds=remain, role=appearanceRole, target=appearanceTarget })
            if remain <= 0 then
                appearanceVisible = false
                SendNUIMessage({ action='appearance', visible=false })
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

local function teleportTo(data)
    if not data then return end
    local ped = PlayerPedId()

    DoScreenFadeOut(250)
    local untilAt = GetGameTimer() + 1200
    while not IsScreenFadedOut() and GetGameTimer() < untilAt do Wait(10) end

    SetEntityCoordsNoOffset(
        ped,
        data.x + 0.0, data.y + 0.0, data.z + 0.0,
        false, false, false
    )
    SetEntityHeading(ped, data.h + 0.0)

    Wait(150)
    DoScreenFadeIn(250)
end

RegisterNetEvent('cookie_police:client:setDetained', function(seconds, charge, shouldTeleport)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    detained = seconds > 0
    detentionEndsAt = detained and (GetGameTimer() + seconds * 1000) or 0
    detentionCharge = tostring(charge or '')

    LocalPlayer.state:set('cookieDetained', detained, true)

    if detained then
        if shouldTeleport and Config.Detention and Config.Detention.teleport then
            teleportTo(Config.Detention.jail)
        end
        SendNUIMessage({
            action='detention',
            visible=true,
            seconds=seconds,
            charge=detentionCharge
        })
    else
        SendNUIMessage({ action='detention', visible=false })
        if Config.Detention and Config.Detention.teleport then
            teleportTo(Config.Detention.release)
        end
    end
end)

CreateThread(function()
    while true do
        if detained then
            local remain = math.max(
                0,
                math.ceil((detentionEndsAt - GetGameTimer()) / 1000)
            )

            SendNUIMessage({
                action='detentionTick',
                seconds=remain,
                charge=detentionCharge
            })

            local ped = PlayerPedId()
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)
            DisableControlAction(0, 45, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)

            if IsPedArmed(ped, 7) then
                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            end

            Wait(250)
        else
            Wait(700)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action='detention', visible=false })
    SendNUIMessage({ action='chase', visible=false })
    SendNUIMessage({ action='appearance', visible=false })
end)

CreateThread(function()
    Wait(1800)
    TriggerServerEvent('cookie_police:server:requestDetentionState')
    TriggerServerEvent('cookie_police:server:requestAppearanceState')
end)
