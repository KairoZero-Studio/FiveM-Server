-- COOKIE COUPLE SYSTEM V1 CLIENT

local coupleActionOpen = false
local coupleProposalOpen = false
local coupleActionTarget = nil

local function adminPanelOpen()
    return CookieAdminPanelIsOpen and CookieAdminPanelIsOpen() or false
end

local function restoreFocus()
    if adminPanelOpen() then
        CookieAdminSetNuiFocus(true, false)
    else
        CookieAdminSetNuiFocus(false, false)
    end
end

local function rotToDir(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vec3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function lookedAtPlayer(maxDistance)
    local cam = GetGameplayCamCoord()
    local dir = rotToDir(GetGameplayCamRot(2))
    local dest = cam + dir * maxDistance

    local ray = StartShapeTestRay(
        cam.x, cam.y, cam.z,
        dest.x, dest.y, dest.z,
        -1, PlayerPedId(), 7
    )
    local _, hit, _, _, entity = GetShapeTestResult(ray)

    if hit == 1 and entity and entity ~= 0 and IsEntityAPed(entity) and IsPedAPlayer(entity) then
        local playerIndex = NetworkGetPlayerIndexFromPed(entity)
        if playerIndex and playerIndex ~= -1 and playerIndex ~= PlayerId() then
            return GetPlayerServerId(playerIndex)
        end
    end

    -- Raycast can miss a moving ped. Fallback to the nearest player inside a narrow camera cone.
    local me = PlayerPedId()
    local myPos = GetEntityCoords(me)
    local forward = dir
    local best, bestScore = nil, -1.0

    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            if ped and ped ~= 0 and DoesEntityExist(ped) then
                local pos = GetEntityCoords(ped)
                local delta = pos - myPos
                local dist = #delta
                if dist > 0.01 and dist <= maxDistance then
                    local normalized = delta / dist
                    local dot = forward.x * normalized.x + forward.y * normalized.y + forward.z * normalized.z
                    if dot > 0.94 and dot > bestScore then
                        bestScore = dot
                        best = GetPlayerServerId(pid)
                    end
                end
            end
        end
    end

    return best
end

local function closeAction()
    coupleActionOpen = false
    coupleActionTarget = nil
    SendNUIMessage({ action = 'coupleActionClose' })
    if not coupleProposalOpen then restoreFocus() end
end


RegisterNetEvent('cookie_admin:client:coupleInteraction', function(data)
    if not data or not data.target then return end
    coupleActionOpen = true
    coupleActionTarget = tonumber(data.target)
    CookieAdminSetNuiFocus(true, false)
    SendNUIMessage({
        action = 'coupleInteraction',
        data = data
    })
end)

RegisterNetEvent('cookie_admin:client:coupleInteractionClose', function()
    closeAction()
end)

RegisterNetEvent('cookie_admin:client:coupleProposalIncoming', function(data)
    closeAction()
    coupleProposalOpen = true
    CookieAdminSetNuiFocus(true, false)
    SendNUIMessage({
        action = 'coupleProposalIncoming',
        data = data or {}
    })
end)

RegisterNetEvent('cookie_admin:client:coupleProposalClosed', function()
    coupleProposalOpen = false
    SendNUIMessage({ action = 'coupleProposalClose' })
    restoreFocus()
end)

RegisterNetEvent('cookie_admin:client:coupleData', function(data, message, isError)
    SendNUIMessage({
        action = 'coupleData',
        data = data or {},
        message = message,
        isError = isError == true
    })
end)

RegisterNetEvent('cookie_admin:client:coupleAdminData', function(data)
    SendNUIMessage({
        action = 'coupleAdminData',
        data = data or {}
    })
end)

RegisterNetEvent('cookie_admin:client:coupleAdminSaved', function(ok, message)
    SendNUIMessage({
        action = 'coupleAdminSaved',
        ok = ok == true,
        message = message or ''
    })
end)

RegisterNUICallback('requestCouple', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestCouple')
end)

RegisterNUICallback('buyCoupleRing', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:buyCoupleRing')
end)

RegisterNUICallback('coupleInteractionClose', function(_, cb)
    cb({ ok = true })
    closeAction()
end)

RegisterNUICallback('sendCoupleProposal', function(data, cb)
    cb({ ok = true })
    local target = tonumber(data and data.target) or coupleActionTarget
    if target == -999 then
        closeAction()
        TriggerEvent('cookie_admin:client:notify', '테스트 시민에게 고백을 전송했습니다. 테스트 모드에서는 실제 커플 관계가 생성되지 않습니다.', false)
        CreateThread(function()
            Wait(900)
            TriggerEvent('cookie_admin:client:notify', '테스트 시민: 고백 UI 정상 작동 ♥', false)
        end)
        return
    end
    if target then TriggerServerEvent('cookie_admin:server:sendCoupleProposal', target) end
end)

RegisterNUICallback('replyCoupleProposal', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.id)
    local accepted = data and data.accepted == true
    if id then TriggerServerEvent('cookie_admin:server:replyCoupleProposal', id, accepted) end
end)

RegisterNUICallback('breakupCouple', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:breakupCouple')
end)

RegisterNUICallback('requestCoupleAdmin', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestCoupleAdmin')
end)

RegisterNUICallback('saveCoupleAdmin', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveCoupleAdmin', data or {})
end)


-- Register interaction key last so a key-mapper problem can never stop
-- requestCouple / buyCoupleRing NUI callbacks from being registered.
RegisterCommand('cookie_couple_interact', function()
    if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) or adminPanelOpen() or coupleProposalOpen then return end

    if coupleActionOpen then
        closeAction()
        return
    end

    local target = lookedAtPlayer(4.0)
    if not target then
        TriggerEvent('cookie_admin:client:notify', '가까운 상대방을 바라본 뒤 CAPSLOCK을 눌러주세요.', true)
        return
    end

    TriggerServerEvent('cookie_admin:server:requestCoupleInteraction', target)
end, false)

-- CAPSLOCK은 cookie_interaction 통합 상호작용 메뉴가 담당합니다.
print('[cookie_admin][couple] CAPSLOCK delegated to cookie_interaction')
