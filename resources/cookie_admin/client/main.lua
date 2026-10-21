function CookieAdminSetNuiFocus(on, keep)
    local resourceName = GetCurrentResourceName()
    on = on == true
    keep = keep == true

    if on then
        if GetResourceState('cookie_core') == 'started' then
            local ok, owner, previousOwner = exports.cookie_core:Acquire(resourceName, keep)
            if ok ~= true then return false, owner, previousOwner end
        end

        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(keep) end
        if SetCursorLocation then SetCursorLocation(0.5, 0.5) end
        return true, resourceName, nil
    end

    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    if GetResourceState('cookie_core') == 'started' then
        exports.cookie_core:Release(resourceName)
    end
    return true, nil, nil
end

local function cookieUiFocus(on)
    return CookieAdminSetNuiFocus(on, false)
end

print('^2[cookie_admin] LABOR+DELIVERY V2 client loaded^7')

local function safeMugshotBase64(ped)
    if GetResourceState('MugShotBase64') ~= 'started' then return nil end
    local ok, mug = pcall(function()
        return exports['MugShotBase64']:GetMugShotBase64(ped, true)
    end)
    if not ok then return nil end
    return mug
end
local isOpen = false

function CookieAdminPanelIsOpen()
    return isOpen
end

local godActive = false
local savedState = nil
local godThread = nil

local noclipActive = false
local superJumpActive = false
local staminaActive = false
local sprintActive = false

local posCenter = nil
local posV3, posV4 = nil, nil
local posPedHeading = 0.0
local posShape = nil
local posRadius = 60.0
local boxLength = 80.0
local boxWidth = 60.0
local boxHeading = 0.0
local posPreview = false
local posGen = 0
local posPolyPoints = nil
local walkZoneCapture = false
local walkZoneCaptureGen = 0
local walkZonePoints = {}
local WALK_POINT_GAP = 2.5

local boxEditActive = false
local boxEditUI = false
local boxEditSnap = nil

local posSummary
local toggleBoxEditUI
local stopZonePreview

local NOCLIP_SPEED = 1.0
local NOCLIP_BOOST = 3.0

local SPRINT_MULT = 1.49
local SPRINT_MOVE_RATE = 1.35

local adminOwnsNuiFocus = false

local function acquireNuiFocus()
    local ok = cookieUiFocus(true)
    if ok == false then
        adminOwnsNuiFocus = false
        return false
    end
    adminOwnsNuiFocus = true
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    return true
end

local function releaseNuiFocus(force)
    -- 다른 리소스(cookie_select / cookie_esc / phone 등)가 가진 NUI 포커스를
    -- cookie_admin이 건드리지 않도록 관리자 UI가 실제로 소유한 경우에만 해제한다.
    if not force and not adminOwnsNuiFocus then return end
    cookieUiFocus(false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    adminOwnsNuiFocus = false
end

local adminOwnsFrontend = false

local function clearAdminFrontend(force)
    -- 접속/캐릭터 선택 중 다른 리소스가 사용 중인 frontend를
    -- cookie_admin이 임의로 닫지 않는다.
    if not force and not adminOwnsFrontend then return end

    if IsPauseMenuActive() then
        SetPauseMenuActive(false)
    end
    pcall(function() SetFrontendActive(false) end)
    adminOwnsFrontend = false
end

local function closePanel()
    -- 중요: isOpen=false 여도 return 하지 않는다.
    -- 좌표 캡처/서브 UI 전환 도중 상태가 꼬이면 NUI 포커스만 남을 수 있기 때문이다.
    isOpen = false

    boxEditActive, boxEditUI, boxEditSnap = false, false, nil
    walkZoneCapture = false
    walkZonePoints = {}
    walkZoneCaptureGen = walkZoneCaptureGen + 1
    if CookieStopPreview then CookieStopPreview(true) end
    if stopZonePreview then stopZonePreview() end
    clearAdminFrontend(false)

    releaseNuiFocus(true)
    SendNUIMessage({ action = 'hideForCapture', on = false })
    SendNUIMessage({ action = 'zoneUiClose' })
    SendNUIMessage({ action = 'close' })

    TriggerEvent('cookie_hud:client:hudVisible', true)

    local t = GlobalState.currentTime
    if t and t.hour then NetworkOverrideClockTime(math.floor(t.hour), math.floor(t.minute or 0), 0) end
    NetworkOverrideClockMillisecondsPerGameMinute(GlobalState.freezeTime and 99999999 or (GlobalState.timeScale or 2000))
end

-- 다른 관리자 모듈(쿠지 비콘 설치 등)에서 F3를 안전하게 닫을 때 사용
CookieAdminClosePanel = closePanel

RegisterNetEvent('cookie_admin:client:openPanel', function(payload)
    if isOpen then return end

    local myMugshot = safeMugshotBase64(cache.ped)

    if not acquireNuiFocus() then
        TriggerEvent('cookie_admin:client:notify', '다른 UI가 열려 있습니다. 먼저 닫아주세요.', true)
        return
    end
    isOpen = true

    TriggerEvent('cookie_hud:client:hudVisible', false)

    CreateThread(function()
        while isOpen do
            local t = GlobalState.currentTime
            if t and t.hour then NetworkOverrideClockTime(math.floor(t.hour), math.floor(t.minute or 0), 0) end
            Wait(0)
        end
    end)

    payload.action = 'open'
    payload.myMugshot = myMugshot
    SendNUIMessage(payload)

    SendNUIMessage({ action = 'toggleState', toggle = 'noclip', on = noclipActive })
    SendNUIMessage({ action = 'toggleState', toggle = 'superjump', on = superJumpActive })
    SendNUIMessage({ action = 'toggleState', toggle = 'stamina', on = staminaActive })
    SendNUIMessage({ action = 'toggleState', toggle = 'sprint', on = sprintActive })

    if posCenter then
        SendNUIMessage({
            action = 'posResult', shape = posShape, vec3 = posV3, vec4 = posV4, preview = posPreview,
            radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading,
            summary = posSummary(),
        })
    end

end)

RegisterCommand('cookieadmin', function()
    -- 팩션 상점 HUD가 열려 있으면 F3는 관리자 패널을 겹쳐 열지 않고 상점만 닫는다.
    if CookieFactionNpcShopIsOpen and CookieFactionNpcShopIsOpen() then
        TriggerEvent('cookie_admin:factionNpcForceClose')
        return
    end

    -- cookie_admin이 직접 열었던 frontend만 정리한다.
    -- 접속/캐릭터 선택 frontend는 절대 건드리지 않는다.
    clearAdminFrontend(false)
    -- F3는 열기뿐 아니라 닫기까지 담당한다.
    if walkZoneCapture then
        closePanel()
        return
    end
    if boxEditActive then
        closePanel()
        return
    end
    if isOpen then
        closePanel()
        return
    end
    if not NetworkIsPlayerActive(PlayerId()) then
        return
    end
    TriggerServerEvent('cookie_admin:server:requestOpen')
end, false)

RegisterKeyMapping('cookieadmin', '쿠키 패널', 'keyboard', 'F3')

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb({ ok = true })
end)

RegisterNUICallback('openMap', function(_, cb)
    cb({ ok = true })
    closePanel()
    CreateThread(function()
        Wait(180)
        -- SP pause를 쓰면 FiveM에서 Michael + 회색 배경 프론트엔드가 뜰 수 있다.
        -- 멀티플레이 pause frontend로 고정한다.
        adminOwnsFrontend = true
        ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), false, -1)
    end)
end)

RegisterNUICallback('openNativeMapMarkers', function(_, cb)
    cb({ ok = true })
    closePanel()
    CreateThread(function()
        Wait(150)
        if GetResourceState('cookie_mapmarkers') == 'started' then
            TriggerEvent('cookie_mapmarkers:client:openAdmin')
        else
            TriggerEvent('cookie_admin:client:notify', 'cookie_mapmarkers가 실행 중이 아닙니다.', true)
        end
    end)
end)

RegisterNUICallback('openEsc', function(_, cb)
    cb({ ok = true })
    CreateThread(function()
        Wait(120)
        TriggerEvent('cookie_esc:client:open')
    end)
end)

RegisterNUICallback('openCrosshair', function(_, cb)
    cb({ ok = true })
    CreateThread(function()
        Wait(120)
        TriggerEvent('cookie_crosshair:client:openEditor')
    end)
end)

RegisterNUICallback('runFeature', function(data, cb)
    if not data or not data.featureKey then
        cb({ ok = false })
        return
    end
    TriggerServerEvent('cookie_admin:server:runFeature', data.featureKey, data.targetServerId)
    cb({ ok = true })
end)

RegisterNUICallback('punishPlayer', function(data, cb)
    TriggerServerEvent('cookie_admin:server:punishPlayer', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('startReboot', function(_, cb)
    TriggerServerEvent('cookie_admin:server:startReboot')
    cb({ ok = true })
end)

-- ============================================================
-- V14.3.4 REBOOT SAFE COUNTDOWN
--  · 리붓 카운트 동안 전원 무적 / 공격 차단 / 플레이어 및 탑승차량 충돌 해제
--  · 사망/다운 감지 시 1초 후 qbx_medical 부활 요청
--  · NUI 상단 공용 타이머와 관리자 버튼 카운트 동기화
-- ============================================================
local cookieRebootProtect = false
local cookieRebootRevivePending = false
local cookieRebootDeadSince = nil

local function cookieApplyRebootProtection(active)
    cookieRebootProtect = active == true

    local player = PlayerId()
    local ped = PlayerPedId()
    if ped == 0 then return end

    SetPlayerInvincible(player, cookieRebootProtect)
    SetEntityInvincible(ped, cookieRebootProtect)
    SetEntityCanBeDamaged(ped, not cookieRebootProtect)
    SetPedCanRagdoll(ped, not cookieRebootProtect)
    SetLocalPlayerAsGhost(cookieRebootProtect)
    NetworkSetFriendlyFireOption(not cookieRebootProtect)
    SetCanAttackFriendly(ped, not cookieRebootProtect, false)
    SetPlayerCanDoDriveBy(player, not cookieRebootProtect)
end

RegisterNetEvent('cookie_admin:client:rebootCountdown', function(seconds)
    local sec = math.max(0, math.floor(tonumber(seconds) or 0))
    -- 0초가 된 뒤 실제 연결 종료까지도 보호를 유지한다.
    cookieApplyRebootProtection(true)
    SendNUIMessage({ action = 'rebootCountdown', seconds = sec })
end)

CreateThread(function()
    while true do
        if not cookieRebootProtect then
            Wait(500)
        else
            local player = PlayerId()
            local ped = PlayerPedId()

            if ped ~= 0 then
                -- 다른 리소스가 상태를 다시 만지는 경우에도 매 프레임 안전 상태를 고정한다.
                SetPlayerInvincible(player, true)
                SetEntityInvincible(ped, true)
                SetEntityCanBeDamaged(ped, false)
                SetPedCanRagdoll(ped, false)
                DisablePlayerFiring(player, true)
                SetPlayerCanDoDriveBy(player, false)

                -- 총격 / 조준 / 근접 / 차량 공격을 모두 막는다.
                local blocked = { 24, 25, 37, 44, 69, 70, 91, 92, 140, 141, 142, 143, 257, 263, 264 }
                for i = 1, #blocked do
                    DisableControlAction(0, blocked[i], true)
                end

                -- 플레이어끼리, 그리고 플레이어가 탑승한 차량끼리 서로 통과한다.
                local myVeh = GetVehiclePedIsIn(ped, false)
                for _, otherPlayer in ipairs(GetActivePlayers()) do
                    if otherPlayer ~= player then
                        local otherPed = GetPlayerPed(otherPlayer)
                        if otherPed ~= 0 and DoesEntityExist(otherPed) then
                            SetEntityNoCollisionEntity(ped, otherPed, true)
                            if myVeh ~= 0 then
                                SetEntityNoCollisionEntity(myVeh, otherPed, true)
                            end

                            local otherVeh = GetVehiclePedIsIn(otherPed, false)
                            if otherVeh ~= 0 then
                                SetEntityNoCollisionEntity(ped, otherVeh, true)
                                if myVeh ~= 0 then
                                    SetEntityNoCollisionEntity(myVeh, otherVeh, true)
                                end
                            end
                        end
                    end
                end

                local st = LocalPlayer and LocalPlayer.state
                local isDead = IsEntityDead(ped) or GetEntityHealth(ped) <= 0
                    or (st and (st.isDead == true or st.dead == true or st.laststand == true))

                if isDead then
                    cookieRebootDeadSince = cookieRebootDeadSince or GetGameTimer()
                    if not cookieRebootRevivePending and GetGameTimer() - cookieRebootDeadSince >= 1000 then
                        cookieRebootRevivePending = true
                        TriggerServerEvent('cookie_admin:server:rebootEmergencyRevive')
                        CreateThread(function()
                            Wait(1500)
                            cookieRebootRevivePending = false
                        end)
                    end
                else
                    cookieRebootDeadSince = nil
                end
            end

            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if cookieRebootProtect then
        cookieApplyRebootProtection(false)
    end
end)

RegisterNUICallback('adminJail', function(data, cb)
    TriggerServerEvent('cookie_admin:server:adminJail', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('driverLicenseAction', function(data, cb)
    TriggerServerEvent('cookie_admin:server:driverLicenseAction', data or {})
    cb({ ok = true })
end)



RegisterNUICallback('factionPlayerAction', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionPlayerAction', data or {})
    cb({ ok = true })
end)

RegisterNUICallback('giveMoney', function(data, cb)
    TriggerServerEvent('cookie_admin:server:giveMoney', data.targetServerId, data.account, data.amount)
    cb('ok')
end)

RegisterNUICallback('giveWeapon', function(data, cb)
    TriggerServerEvent('cookie_admin:server:giveWeapon', data.targetServerId, data.weapon, data.amount, data.mode)
    cb('ok')
end)

RegisterNUICallback('spawnVehicle', function(data, cb)
    TriggerServerEvent('cookie_admin:server:spawnVehicle', data.model, data.targetServerId)
    cb('ok')
end)

RegisterNUICallback('targetVehicleAction', function(data, cb)
    data = data or {}
    TriggerServerEvent('cookie_admin:server:targetVehicleAction', data.action, data.targetServerId, data.model)
    cb({ ok = true })
end)

RegisterNUICallback('testSpawnVehicle', function(data, cb)
    TriggerServerEvent('cookie_admin:server:testSpawnVehicle', data.model)
    cb('ok')
end)

RegisterNUICallback('returnTestVehicle', function(_, cb)
    TriggerServerEvent('cookie_admin:server:returnTestVehicle')
    cb('ok')
end)

local previewActive = false
local previewCam = nil
local previewVeh = nil
local previewThread = false
local previewReturnCoords = nil
local previewReturnHeading = nil

local pvAngle = 210.0
local pvDist = 5.2
local pvHeight = 1.4
local pvAuto = true

function CookieStartPreviewCam()
    if not previewVeh or not DoesEntityExist(previewVeh) then return end
    local c = GetEntityCoords(previewVeh)
    if not previewCam then
        previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z + 1.5, 0.0, 0.0, 0.0, 50.0, false, 0)
        SetCamActive(previewCam, true)
        RenderScriptCams(true, true, 400, true, true)
    end
    if IsScreenFadedOut() then DoScreenFadeIn(350) end
    if previewThread then return end
    previewThread = true
    CreateThread(function()
        while previewActive and previewCam do
            DisplayRadar(false)
            if previewVeh and DoesEntityExist(previewVeh) then
                local vc = GetEntityCoords(previewVeh)
                if pvAuto then
                    pvAngle = pvAngle + 0.25
                    if pvAngle >= 360.0 then pvAngle = pvAngle - 360.0 end
                end
                local rad = pvAngle * 3.14159265 / 180.0
                SetCamCoord(previewCam, vc.x + pvDist * math.cos(rad), vc.y + pvDist * math.sin(rad), vc.z + pvHeight)
                PointCamAtEntity(previewCam, previewVeh, 0.0, 0.0, 0.0, true)

                DrawLightWithRange(vc.x + 4.0, vc.y + 4.0, vc.z + 4.5, 255, 244, 214, 18.0, 3.0)
                DrawLightWithRange(vc.x - 4.0, vc.y - 4.0, vc.z + 4.5, 255, 244, 214, 18.0, 2.5)
                DrawLightWithRange(vc.x, vc.y, vc.z + 6.0, 255, 250, 235, 20.0, 2.0)
            end
            Wait(0)
        end
        previewThread = false
    end)
end

RegisterNUICallback('previewSet', function(data, cb)
    if data then
        if data.angle ~= nil then pvAngle = math.max(0.0, math.min(360.0, tonumber(data.angle) or pvAngle)) end
        if data.distance ~= nil then pvDist = math.max(2.4, math.min(16.0, tonumber(data.distance) or pvDist)) end
        if data.height ~= nil then pvHeight = math.max(-1.5, math.min(7.0, tonumber(data.height) or pvHeight)) end
        if data.manual then pvAuto = false end
    end
    cb({ angle = pvAngle, distance = pvDist, height = pvHeight, auto = pvAuto })
end)

RegisterNUICallback('previewCam', function(data, cb)
    local a = data and data.action
    if a == 'rotL' then pvAngle = pvAngle - 12.0
    elseif a == 'rotR' then pvAngle = pvAngle + 12.0
    elseif a == 'zoomIn' then pvDist = math.max(2.4, pvDist - 0.6)
    elseif a == 'zoomOut' then pvDist = math.min(16.0, pvDist + 0.6)
    elseif a == 'up' then pvHeight = math.min(7.0, pvHeight + 0.4)
    elseif a == 'down' then pvHeight = math.max(-1.5, pvHeight - 0.4)
    elseif a == 'auto' then pvAuto = not pvAuto end
    cb({ auto = pvAuto })
end)

function CookieStopPreview()
    local wasActive = previewActive or previewCam ~= nil
    previewActive = false
    previewThread = false
    if previewCam then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(previewCam, false)
        previewCam = nil
    end
    previewVeh = nil
    pvAngle, pvDist, pvHeight, pvAuto = 210.0, 5.2, 1.4, true
    SetArtificialLightsState(false)
    NetworkClearClockTimeOverride()
    DisplayRadar(true)
    ClearFocus()
    local ped = PlayerPedId()
    if previewReturnCoords then
        if wasActive then DoScreenFadeOut(150) end
        SetEntityCoords(ped, previewReturnCoords.x, previewReturnCoords.y, previewReturnCoords.z, false, false, false, false)
        if previewReturnHeading then SetEntityHeading(ped, previewReturnHeading) end
        previewReturnCoords = nil
        previewReturnHeading = nil
        if wasActive then CreateThread(function() Wait(320); DoScreenFadeIn(300) end) end
    end
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    TriggerServerEvent('cookie_admin:server:cleanupPreviewVehicle')
    return wasActive
end

RegisterNUICallback('enterPreview', function(_, cb)
    previewActive = true
    local ped = PlayerPedId()
    previewReturnCoords = GetEntityCoords(ped)
    previewReturnHeading = GetEntityHeading(ped)
    DoScreenFadeOut(250)
    Wait(300)
    local pad = Config.VehiclePreviewPad
    SetEntityCoords(ped, pad.x, pad.y, pad.z, false, false, false, false)
    SetEntityHeading(ped, pad.w or 0.0)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    DisplayRadar(false)
    cb('ok')
end)

RegisterNUICallback('exitPreview', function(_, cb)
    CookieStopPreview()
    cb('ok')
end)

RegisterNUICallback('previewSpawn', function(data, cb)
    if data and data.model then
        TriggerServerEvent('cookie_admin:server:previewSpawnVehicle', data.model)
    end
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:previewVeh', function(netId, name)
    if not previewActive then return end

    local tries = 0
    while not NetworkDoesEntityExistWithNetworkId(netId) and tries < 300 do Wait(10); tries = tries + 1 end
    if not NetworkDoesEntityExistWithNetworkId(netId) then return end
    local veh = NetToVeh(netId)
    if not veh or veh == 0 then return end
    previewVeh = veh
    FreezeEntityPosition(veh, true)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    CookieStartPreviewCam()
end)

RegisterNUICallback('previewColor', function(data, cb)
    if previewVeh and DoesEntityExist(previewVeh) and data then
        local r = math.floor(tonumber(data.r) or 0)
        local g = math.floor(tonumber(data.g) or 0)
        local b = math.floor(tonumber(data.b) or 0)
        SetVehicleModKit(previewVeh, 0)
        SetVehicleCustomPrimaryColour(previewVeh, r, g, b)
        SetVehicleCustomSecondaryColour(previewVeh, r, g, b)
    end
    cb('ok')
end)

local testDriveActive = false
local testDriveReturn = nil

function CookieEndTestDrive()
    if not testDriveActive then return end
    testDriveActive = false
    DoScreenFadeOut(250)
    Wait(300)
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    if testDriveReturn then
        SetEntityCoords(ped, testDriveReturn.x, testDriveReturn.y, testDriveReturn.z, false, false, false, false)
        SetEntityHeading(ped, testDriveReturn.w or 0.0)
        testDriveReturn = nil
    end
    TriggerServerEvent('cookie_admin:server:endTestDrive')
    Wait(200)
    DoScreenFadeIn(400)
    pcall(function() exports.qbx_core:Notify('시승 종료', 'inform') end)
end

RegisterNUICallback('startTestDrive', function(data, cb)
    if data and data.model then
        if CookieStopPreview then CookieStopPreview() end
        TriggerServerEvent('cookie_admin:server:startTestDrive', data.model)
    end
    cb('ok')
end)

RegisterNUICallback('endTestDrive', function(_, cb)
    CookieEndTestDrive()
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:startTestDrive', function(netId, name)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    testDriveReturn = { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
    testDriveActive = true
    DoScreenFadeOut(300)
    Wait(350)
    if isOpen then closePanel() end
    local track = Config.TestDriveTrack
    SetEntityCoords(ped, track.x, track.y, track.z, false, false, false, false)
    SetEntityHeading(ped, track.w or 0.0)
    local tries = 0
    while not NetworkDoesEntityExistWithNetworkId(netId) and tries < 300 do Wait(10); tries = tries + 1 end
    if NetworkDoesEntityExistWithNetworkId(netId) then
        local veh = NetToVeh(netId)
        if veh and veh ~= 0 then
            local t = 0
            while not IsPedInVehicle(ped, veh, false) and t < 15 do SetPedIntoVehicle(ped, veh, -1); Wait(120); t = t + 1 end
        end
    end
    SetEntityInvincible(ped, true)
    DoScreenFadeIn(400)
    pcall(function() exports.qbx_core:Notify('시승 시작 차에서 내리거나 [X]로 종료', 'inform') end)
    CreateThread(function()
        Wait(3000)
        while testDriveActive do
            local p = PlayerPedId()
            local veh = GetVehiclePedIsIn(p, false)
            if veh == 0 then
                CookieEndTestDrive(); break
            elseif IsEntityUpsidedown(veh) then
                TaskLeaveVehicle(p, veh, 16)
            end
            Wait(500)
        end
    end)
end)

RegisterCommand('cookie_td_end', function()
    if testDriveActive then CookieEndTestDrive() end
end, false)
RegisterKeyMapping('cookie_td_end', '시승 종료', 'keyboard', 'X')

RegisterNUICallback('exhibitAdd', function(data, cb)
    TriggerServerEvent('cookie_admin:server:exhibitAdd', data)
    cb('ok')
end)

RegisterNUICallback('limitedVehicleSave', function(data, cb)
    TriggerServerEvent('cookie_admin:server:limitedVehicleSave', data)
    cb('ok')
end)

RegisterNUICallback('limitedVehicleDelete', function(data, cb)
    TriggerServerEvent('cookie_admin:server:limitedVehicleDelete', data and data.id)
    cb('ok')
end)

RegisterNUICallback('exhibitRemove', function(data, cb)
    TriggerServerEvent('cookie_admin:server:exhibitRemove', data)
    cb('ok')
end)

RegisterNUICallback('requestExhibitList', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestExhibitList')
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:exhibitList', function(list, limited, factions)
    SendNUIMessage({ action = 'exhibitList', list = list or {}, limited = limited or {}, factions = factions or {} })
end)

RegisterNUICallback('lspdFleetAdd', function(data, cb)
    TriggerServerEvent('cookie_admin:server:lspdFleetAdd', data and data.model)
    cb('ok')
end)

RegisterNUICallback('lspdFleetRemove', function(data, cb)
    TriggerServerEvent('cookie_admin:server:lspdFleetRemove', data and data.id)
    cb('ok')
end)

RegisterNUICallback('requestLspdFleet', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestLspdFleet')
    cb('ok')
end)

RegisterNUICallback('lspdFleetSeed', function(_, cb)
    TriggerServerEvent('cookie_admin:server:lspdFleetSeed')
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:lspdFleet', function(list)
    SendNUIMessage({ action = 'lspdFleet', list = list or {} })
end)

RegisterNetEvent('cookie_admin:client:notifyBottom', function(msg, isError)
    SendNUIMessage({ action = 'cookieAlert', message = msg, isWarn = isError and true or false })
end)

local weaponAmmoMap = nil
exports('getWeaponAmmo', function(weapon)
    if not weaponAmmoMap then
        weaponAmmoMap = {}
        for _, cat in ipairs(Config.Weapons or {}) do
            for _, it in ipairs(cat.items) do
                if it.ammo then
                    weaponAmmoMap[it.name] = it.ammo
                    weaponAmmoMap[GetHashKey(it.name)] = it.ammo
                end
            end
        end
    end
    return weaponAmmoMap[weapon]
end)

RegisterNUICallback('startDuty', function(_, cb)
    TriggerServerEvent('cookie_admin:server:startDuty')
    cb('ok')
end)

RegisterNUICallback('setAdminPw', function(data, cb)
    TriggerServerEvent('cookie_admin:server:setAdminPw', data.newPw)
    cb('ok')
end)

RegisterNUICallback('resetAdminPw', function(data, cb)
    TriggerServerEvent('cookie_admin:server:resetAdminPw', data.targetServerId)
    cb('ok')
end)

RegisterNUICallback('endDuty', function(_, cb)
    TriggerServerEvent('cookie_admin:server:endDuty')
    cb('ok')
end)

RegisterNUICallback('requestGrantList', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestGrantList')
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:grantList', function(list)
    SendNUIMessage({ action = 'grantList', players = list or {} })

end)

local function pushZoneList()
    TriggerServerEvent('cookie_safezone:server:requestZoneList')
end

RegisterNetEvent('cookie_safezone:client:zoneList', function(rows, factionMap)
    SendNUIMessage({
        action = 'zoneList',
        zones = rows or {},
        factions = factionMap or {},
    })

end)

RegisterNUICallback('sendNotice', function(data, cb)
    cb({ ok = true })
    data = data or {}
    TriggerServerEvent('cookie_admin:server:sendNotice', {
        text = data.text or '',
        seconds = tonumber(data.seconds) or 0,
    })
end)

RegisterNUICallback('requestNews', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestNews')
end)

RegisterNUICallback('newsAdd', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:newsAdd', data or {})
end)

RegisterNUICallback('newsEdit', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:newsEdit', data or {})
end)

RegisterNUICallback('newsToggle', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:newsToggle', (data and data.id) or 0)
end)

RegisterNUICallback('newsDelete', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:newsDelete', (data and data.id) or 0)
end)

RegisterNetEvent('cookie_admin:client:newsList', function(rows)
    SendNUIMessage({ action = 'newsList', rows = rows or {} })
end)

RegisterNUICallback('chatWarn', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:chatWarn', data or {})
end)

RegisterNUICallback('chatMute', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:chatMute', data or {})
end)

RegisterNUICallback('requestZoneList', function(_, cb)
    pushZoneList()
    cb('ok')
end)

-- V13.9.1: F3 > 좌표 관리 > 잠수존 좌표 관리
RegisterNUICallback('requestAfkZoneConfig', function(_, cb)
    cb('ok')
    TriggerServerEvent('cookie_admin:server:requestAfkZoneConfig')
end)

RegisterNUICallback('setAfkZoneCoord', function(data, cb)
    cb('ok')
    TriggerServerEvent('cookie_admin:server:setAfkZoneCoord', tostring(data and data.kind or ''))
end)

RegisterNUICallback('saveAfkZoneRadius', function(data, cb)
    cb('ok')
    TriggerServerEvent('cookie_admin:server:saveAfkZoneRadius', tonumber(data and data.radius))
end)

RegisterNetEvent('cookie_admin:client:afkZoneConfigData', function(cfg)
    SendNUIMessage({
        action = 'afkZoneConfigData',
        data = cfg or {},
    })
end)

RegisterNUICallback('deleteZone', function(data, cb)
    TriggerServerEvent('cookie_safezone:server:deleteZone', data and data.id)
    cb('ok')
end)

local function refreshZoneListIfOpen()
    if isOpen then pushZoneList() end
end
RegisterNetEvent('cookie_safezone:client:zoneRemoved', refreshZoneListIfOpen)
RegisterNetEvent('cookie_safezone:client:zoneAdded', refreshZoneListIfOpen)
RegisterNetEvent('cookie_safezone:client:zoneUpdated', refreshZoneListIfOpen)

local previewCam = nil
local previewGen = 0

local function zonePreviewCorners(z)
    local rad = math.rad(tonumber(z.heading) or 0.0)
    local cs, sn = math.cos(rad), math.sin(rad)
    local hl, hw = (tonumber(z.length) or 10.0) * 0.5, (tonumber(z.width) or 10.0) * 0.5
    local pts = { { hl, hw }, { hl, -hw }, { -hl, -hw }, { -hl, hw } }
    local out = {}
    for i = 1, 4 do
        local lx, ly = pts[i][1], pts[i][2]
        out[i] = vec3(z.cx + lx * cs - ly * sn, z.cy + lx * sn + ly * cs, z.cz)
    end
    return out
end

stopZonePreview = function()
    previewGen = previewGen + 1
    if previewCam then
        SetCamActive(previewCam, false)
        DestroyCam(previewCam, true)
        RenderScriptCams(false, false, 500, true, true)
        previewCam = nil
    end
    ClearFocus()
    SendNUIMessage({ action = 'zonePreviewState', on = false })
end

RegisterNUICallback('previewZone', function(z, cb)
    if not z or not z.cx then cb('ok') return end
    stopZonePreview()

    local reach
    if z.shape == 'sphere' then
        reach = tonumber(z.radius) or 20.0
    elseif z.shape == 'poly' and type(z.polyPoints) == 'table' then
        reach = 10.0
        for _,pt in ipairs(z.polyPoints) do
            local dx,dy=(tonumber(pt.x or pt[1]) or z.cx)-z.cx,(tonumber(pt.y or pt[2]) or z.cy)-z.cy
            reach=math.max(reach,math.sqrt(dx*dx+dy*dy))
        end
    else
        reach = math.sqrt(((tonumber(z.length) or 10.0) * 0.5) ^ 2 + ((tonumber(z.width) or 10.0) * 0.5) ^ 2)
    end
    local h = math.max(45.0, reach * 1.8)

    SetFocusPosAndVel(z.cx, z.cy, z.cz, 0.0, 0.0, 0.0)

    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        z.cx, z.cy, z.cz + h, 0.0, 0.0, 0.0, 55.0, false, 0)
    PointCamAtCoord(previewCam, z.cx, z.cy, z.cz)
    SetCamActive(previewCam, true)
    RenderScriptCams(true, true, 600, true, true)

    previewGen = previewGen + 1
    local myGen = previewGen
    local col = (z.type == 'garage') and { 62, 194, 106 } or { 255, 200, 0 }
    CreateThread(function()
        while previewGen == myGen and previewCam do
            if z.shape == 'sphere' then
                local r = tonumber(z.radius) or 20.0
                for i = 0, 63 do
                    local a1, a2 = (i / 64) * math.pi * 2.0, ((i + 1) / 64) * math.pi * 2.0
                    DrawLine(z.cx + math.cos(a1) * r, z.cy + math.sin(a1) * r, z.cz,
                        z.cx + math.cos(a2) * r, z.cy + math.sin(a2) * r, z.cz, col[1], col[2], col[3], 220)
                end
            elseif z.shape == 'poly' and type(z.polyPoints) == 'table' then
                for i=1,#z.polyPoints do
                    local a,b=z.polyPoints[i],z.polyPoints[i % #z.polyPoints + 1]
                    DrawLine(tonumber(a.x or a[1]),tonumber(a.y or a[2]),tonumber(a.z or a[3]),
                        tonumber(b.x or b[1]),tonumber(b.y or b[2]),tonumber(b.z or b[3]),col[1],col[2],col[3],220)
                end
            else
                local k = zonePreviewCorners(z)
                for i = 1, 4 do
                    local a, b = k[i], k[i % 4 + 1]
                    DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, col[1], col[2], col[3], 220)
                end
            end

            DrawMarker(28, z.cx, z.cy, z.cz + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                1.0, 1.0, 1.0, col[1], col[2], col[3], 180, false, false, 2, false, nil, nil, false)
            Wait(0)
        end
    end)

    SendNUIMessage({ action = 'zonePreviewState', on = true, label = z.label })

    cb('ok')
end)

RegisterNUICallback('closeZonePreview', function(_, cb)
    stopZonePreview()
    cb('ok')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stopZonePreview() end
end)

RegisterNUICallback('changeAdminLevel', function(data, cb)
    TriggerServerEvent('cookie_admin:server:changeAdminLevel', data and data.targetServerId, data and data.level)
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:forceClosePanel', function()
    closePanel()
end)

RegisterNUICallback('grantAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:grantAdmin', data.targetLicense, data.alias, data.pw, data.level, data.team)
    cb('ok')
end)

RegisterNUICallback('factionDeposit', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionDeposit', data and data.amount, data and data.reason)
    cb('ok')
end)

RegisterNUICallback('factionWithdraw', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionWithdraw', data and data.amount, data and data.reason)
    cb('ok')
end)

RegisterNUICallback('requestFactionPane', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestFactionPane')
    cb('ok')
end)

RegisterNUICallback('facRankSave', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facRankSave', data)
    cb('ok')
end)

RegisterNUICallback('facRankDelete', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facRankDelete', data and data.grade)
    cb('ok')
end)

RegisterNUICallback('facMemberSave', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facMemberSave', data)
    cb('ok')
end)

RegisterNUICallback('facMemberKick', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facMemberKick', data and data.citizenid)
    cb('ok')
end)

RegisterNUICallback('facBuyVehicle', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facBuyVehicle', data and data.id)
    cb('ok')
end)

RegisterNUICallback('factionShopSave', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionShopSave', data)
    cb('ok')
end)

RegisterNUICallback('factionShopDelete', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionShopDelete', data and data.id)
    cb('ok')
end)

RegisterNUICallback('factionFleetAdd', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionFleetAdd', data)
    cb('ok')
end)

RegisterNUICallback('factionBudgetAdjust', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionBudgetAdjust', data)
    cb('ok')
end)

RegisterNUICallback('setAdminAlias', function(data, cb)
    TriggerServerEvent('cookie_admin:server:setAdminAlias',
        data and data.targetServerId, data and data.name)
    cb('ok')
end)

RegisterNUICallback('requestLogs', function(data, cb)
    TriggerServerEvent('cookie_admin:server:requestLogs', data and data.kind)
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:logs', function(kind, rows)
    SendNUIMessage({ action = 'logs', kind = kind, rows = rows or {} })
end)

RegisterNUICallback('facPreviewVehicle', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facPreviewVehicle', data and data.model)
    cb('ok')
end)

RegisterNUICallback('facShopGrade', function(data, cb)
    TriggerServerEvent('cookie_admin:server:facShopGrade', data and data.id, data and data.grade)
    cb('ok')
end)

RegisterNUICallback('captureVehImage', function(data, cb)
    cb('ok')
    local model = data and data.model
    if not model then return end

    CreateThread(function()
        SendNUIMessage({ action = 'hideForCapture', on = true })
        releaseNuiFocus()
        Wait(220)

        exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = 0.85 }, function(dataUrl)
            acquireNuiFocus()
            SendNUIMessage({ action = 'hideForCapture', on = false })
            if dataUrl and dataUrl ~= '' then
                SendNUIMessage({ action = 'vehShot', model = model, data = dataUrl })
            else
                SendNUIMessage({ action = 'toast', message = '캡처에 실패했습니다', isWarn = true })
            end
        end)
    end)
end)

RegisterNUICallback('saveVehImage', function(data, cb)
    TriggerServerEvent('cookie_admin:server:saveVehicleImage', data and data.model, data and data.image)
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:factionPane', function(pane)
    SendNUIMessage({ action = 'factionPane', faction = pane })
end)

RegisterNUICallback('requestFactionList', function(_, cb)
    TriggerServerEvent('cookie_admin:server:factionList')
    cb('ok')
end)

RegisterNUICallback('factionCreate', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionCreate', data)
    cb('ok')
end)

RegisterNUICallback('factionUpdate', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionUpdate', data and data.id, data)
    cb('ok')
end)

RegisterNUICallback('factionDelete', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionDelete', data and data.id)
    cb('ok')
end)

RegisterNUICallback('factionSetLeader', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionSetLeader', data and data.id, data and data.targetServerId)
    cb('ok')
end)

RegisterNUICallback('factionAddMember', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionAddMember', data and data.id, data and data.targetServerId)
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:factionAdminList', function(list, types)
    SendNUIMessage({ action = 'factionAdminList', factions = list or {}, types = types or {} })
end)

local function toggleFeedback(key, on, label)
    SendNUIMessage({ action = 'toggleState', toggle = key, on = on })
    SendNUIMessage({
        action = 'toast',
        message = on and (label .. ' ON') or (label .. ' OFF'),
        isWarn = false,
        tone = on and 'toggle-on' or 'toggle-off',
    })

end

RegisterNUICallback('toggleNoclip', function(_, cb)
    TriggerServerEvent('cookie_admin:server:toggleNoclip')
    cb('ok')
end)
RegisterNUICallback('toggleSuperJump', function(_, cb)
    TriggerServerEvent('cookie_admin:server:toggleSuperJump')
    cb('ok')
end)
RegisterNUICallback('toggleStamina', function(_, cb)
    TriggerServerEvent('cookie_admin:server:toggleStamina')
    cb('ok')
end)
RegisterNUICallback('toggleSprint', function(_, cb)
    TriggerServerEvent('cookie_admin:server:toggleSprint')
    cb('ok')
end)

RegisterNUICallback('extractPos', function(data, cb)
    TriggerServerEvent('cookie_admin:server:extractPos', data and data.shape)
    cb('ok')
end)

local POS_SEG = 64
local BOX_EDGE_STEP = 2.0
local BOX_EDGE_MAX = 24
local BOX_H = 4.0

local function drawCenterDot(c)
    DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.4, 0.4, 0.4, 33, 171, 97, 200, false, false, 2, false, nil, nil, false)
end

local function drawCirclePreview()
    local c, r = posCenter, posRadius

    DrawMarker(1, c.x, c.y, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        r * 2.0, r * 2.0, 0.6, 255, 184, 0, 45, false, false, 2, false, nil, nil, false)

    for i = 0, POS_SEG - 1 do
        local a = (i / POS_SEG) * math.pi * 2.0
        DrawMarker(1, c.x + math.cos(a) * r, c.y + math.sin(a) * r, c.z - 1.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 2.5, 255, 184, 0, 170, false, false, 2, false, nil, nil, false)
    end
    drawCenterDot(c)
end

local function boxCorners()
    local c = posCenter
    local rad = math.rad(boxHeading)
    local cs, sn = math.cos(rad), math.sin(rad)
    local hl, hw = boxLength * 0.5, boxWidth * 0.5
    local local_ = { { hl, hw }, { hl, -hw }, { -hl, -hw }, { -hl, hw } }
    local out = {}
    for i = 1, 4 do
        local lx, ly = local_[i][1], local_[i][2]
        out[i] = vector3(c.x + lx * cs - ly * sn, c.y + lx * sn + ly * cs, c.z)
    end
    return out
end

local function drawBoxPreview()
    local c = posCenter
    local k = boxCorners()
    local topZ = c.z - 1.0 + BOX_H

    for i = 1, 4 do
        local a = k[i]
        local b = k[i % 4 + 1]

        DrawMarker(1, a.x, a.y, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            1.0, 1.0, BOX_H, 255, 184, 0, 200, false, false, 2, false, nil, nil, false)

        DrawLine(a.x, a.y, c.z - 1.0, b.x, b.y, c.z - 1.0, 255, 184, 0, 220)
        DrawLine(a.x, a.y, topZ, b.x, b.y, topZ, 255, 184, 0, 160)
        DrawLine(a.x, a.y, c.z - 1.0, a.x, a.y, topZ, 255, 184, 0, 160)

        local dx, dy = b.x - a.x, b.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        local segs = math.min(BOX_EDGE_MAX, math.max(2, math.floor(len / BOX_EDGE_STEP)))
        for s = 1, segs - 1 do
            local t = s / segs
            DrawMarker(1, a.x + dx * t, a.y + dy * t, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.6, 0.6, 2.0, 255, 184, 0, 150, false, false, 2, false, nil, nil, false)
        end
    end
    drawCenterDot(c)
end

local function drawPolyPreview()
    if not posPolyPoints or #posPolyPoints < 3 then return end
    local n = #posPolyPoints
    for i = 1, n do
        local a = posPolyPoints[i]
        local b = posPolyPoints[i % n + 1]
        DrawLine(a.x, a.y, a.z + 0.08, b.x, b.y, b.z + 0.08, 255, 184, 0, 235)
        DrawMarker(1, a.x, a.y, a.z - 0.7, 0.0,0.0,0.0, 0.0,0.0,0.0,
            0.55,0.55,2.4, 255,184,0,165, false,false,2,false,nil,nil,false)
    end
    if posCenter then drawCenterDot(posCenter) end
end

local function startPosThread()
    posGen = posGen + 1
    local myGen = posGen
    CreateThread(function()
        while posPreview and posCenter and posGen == myGen do
            if posShape == 'box' then drawBoxPreview() elseif posShape == 'poly' then drawPolyPreview() else drawCirclePreview() end
            Wait(0)
        end
    end)
end

local function num(n)
    if n % 1 == 0 then return ('%d'):format(n) end
    return ('%.1f'):format(n)
end

function posSummary()
    if posShape == 'box' then
        return ('size = %sm × %sm, heading = %s°'):format(num(boxLength), num(boxWidth), num(boxHeading))
    elseif posShape == 'poly' then
        return ('이동형 다각형 · %d개 지점'):format(posPolyPoints and #posPolyPoints or 0)
    end
    return ('radius = %sm'):format(num(posRadius))
end

local function refreshPosStrings()
    if not posCenter then return end
    posV3 = ('vec3(%.2f, %.2f, %.2f)'):format(posCenter.x, posCenter.y, posCenter.z)
    posV4 = ('vec4(%.2f, %.2f, %.2f, %.2f)'):format(posCenter.x, posCenter.y, posCenter.z, posPedHeading)
end

local function refreshPosPreview()
    if posPreview and posCenter then startPosThread() end
end

RegisterNetEvent('cookie_admin:client:applyExtractPos', function(shape)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)

    posCenter = c
    posPedHeading = h
    refreshPosStrings()
    local v3, v4 = posV3, posV4
    posShape = (shape == 'box') and 'box' or 'circle'
    posPolyPoints = nil

    if posShape == 'box' then boxHeading = math.floor(h + 0.5) % 360 end

    refreshPosPreview()

    SendNUIMessage({
        action = 'posResult', shape = posShape, vec3 = v3, vec4 = v4, preview = posPreview,
        radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading,
        summary = posSummary(),
    })

    TriggerEvent('chat:addMessage', { args = { '^5[좌표]', 'center = ' .. v3 } })
    TriggerEvent('chat:addMessage', { args = { '^5[좌표]', v4 } })
    TriggerEvent('chat:addMessage', { args = { '^5[좌표]', posSummary() } })

end)

RegisterNUICallback('setPosShapeValue', function(data, cb)
    data = data or {}
    local key, v = data.key, tonumber(data.value)
    if v then

        if key == 'radius' then posRadius = math.max(1.0, math.min(200.0, v + 0.0))
        elseif key == 'length' then boxLength = math.max(1.0, math.min(200.0, v + 0.0))
        elseif key == 'width' then boxWidth = math.max(1.0, math.min(200.0, v + 0.0))
        elseif key == 'heading' then boxHeading = (v + 0.0) % 360
        end
    end

    cb({
        summary = posSummary(),
        radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading,
    })
end)

RegisterNUICallback('nudgePosCenter', function(data, cb)
    if not posCenter then cb({}) return end
    data = data or {}
    local dx = tonumber(data.dx) or 0.0
    local dy = tonumber(data.dy) or 0.0
    posCenter = vec3(posCenter.x + dx, posCenter.y + dy, posCenter.z)
    refreshPosStrings()
    cb({ summary = posSummary(), vec3 = posV3, vec4 = posV4 })
end)

local function sendBoxEditState()
    SendNUIMessage({
        action = 'boxEditState', session = boxEditActive, ui = boxEditUI, shape = posShape,
        radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading,
        summary = posSummary(),
        vec3 = posV3, vec4 = posV4,
    })
end

local function showBoxEditUI()
    boxEditUI = true
    acquireNuiFocus()
    sendBoxEditState()
end

local function hideBoxEditUI()
    boxEditUI = false
    releaseNuiFocus()
    sendBoxEditState()
end

function toggleBoxEditUI()
    if not boxEditActive then return end
    if boxEditUI then hideBoxEditUI() else showBoxEditUI() end
end

local function endBoxEditSession()
    boxEditActive, boxEditUI, boxEditSnap = false, false, nil
    posPreview = false
    posGen = posGen + 1
    SendNUIMessage({ action = 'posPreviewState', on = false })
    acquireNuiFocus()
    sendBoxEditState()
end

RegisterNUICallback('enterBoxEdit', function(_, cb)

    if not posCenter then
        SendNUIMessage({ action = 'toast', message = '먼저 좌표를 추출하세요', isWarn = true })
        cb('ok')
        return
    end
    boxEditActive = true

    boxEditSnap = {
        radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading, center = posCenter,
    }

    posPreview = true
    startPosThread()
    showBoxEditUI()

    cb('ok')
end)

RegisterNUICallback('hideBoxEditUI', function(_, cb)
    if not boxEditActive then cb('ok') return end
    hideBoxEditUI()

    cb('ok')
end)

local zoneEditId = nil
local zoneEditType = nil
local zoneEditLabel = nil
local zoneEditFaction = nil
local zoneEditFishingType = nil
local zoneEditFishingRegion = nil
local zoneEditBeaconColor = nil
local zoneEditTeleport = nil

local function hexToRgb(hex)
    if type(hex) ~= 'string' then return nil end
    hex = hex:gsub('#', '')
    if not hex:match('^%x%x%x%x%x%x$') then return nil end
    return tonumber(hex:sub(1,2),16), tonumber(hex:sub(3,4),16), tonumber(hex:sub(5,6),16)
end

local function zonePayload(zType, label, factionId, fishingType, fishingRegion, beaconColor, teleport)
    if not posCenter then return nil end
    local shape = (posShape == 'box') and 'box' or ((posShape == 'poly') and 'poly' or 'sphere')
    local p = {
        type = zType, shape = shape, label = label,
        cx = posCenter.x, cy = posCenter.y, cz = posCenter.z,
        heading = boxHeading,
        factionId = factionId,
        fishingType = (zType == 'fishing') and ((fishingType == 'boat') and 'boat' or 'normal') or nil,
        fishingRegion = (zType == 'fishing') and tostring(fishingRegion or (((fishingType == 'boat') and 'offshore') or 'coast')) or nil,
    }
    if zType == 'teleport' and type(teleport) == 'table' then
        p.teleportX = tonumber(teleport.x)
        p.teleportY = tonumber(teleport.y)
        p.teleportZ = tonumber(teleport.z)
        p.teleportH = tonumber(teleport.h) or 0.0
    end
    local br, bg, bb = hexToRgb(beaconColor)
    if br then p.beaconR, p.beaconG, p.beaconB, p.beaconA = br, bg, bb, 130 end
    if shape == 'sphere' then
        p.radius = posRadius
    elseif shape == 'box' then
        p.length = boxLength
        p.width = boxWidth
        p.height = 40.0
    else
        p.height = 40.0
        p.points = {}
        for _, pt in ipairs(posPolyPoints or {}) do
            p.points[#p.points+1] = { x=pt.x+0.0, y=pt.y+0.0, z=pt.z+0.0 }
        end
    end
    return p
end

local function walkCaptureDraw(points, current)
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        DrawLine(a.x,a.y,a.z+0.08,b.x,b.y,b.z+0.08,255,184,0,235)
    end
    for _,pt in ipairs(points) do
        DrawMarker(28, pt.x,pt.y,pt.z+0.18, 0.0,0.0,0.0, 0.0,0.0,0.0,
            0.28,0.28,0.28,255,184,0,220,false,false,2,false,nil,nil,false)
    end
    if #points>0 and current then
        local last=points[#points]
        DrawLine(last.x,last.y,last.z+0.08,current.x,current.y,current.z+0.08,255,255,255,200)
        if #points>=2 then
            local first=points[1]
            DrawLine(current.x,current.y,current.z+0.08,first.x,first.y,first.z+0.08,255,184,0,130)
        end
    end
end

local function restoreWalkCaptureUi()
    acquireNuiFocus()
    SendNUIMessage({ action='hideForCapture', on=false })
end

RegisterNUICallback('startWalkZoneCapture', function(data, cb)
    data = data or {}
    local zType = tostring(data.type or '')
    if zType ~= 'safezone' and zType ~= 'fishing' and zType ~= 'mining' and zType ~= 'afkzone' then
        cb({ok=false, error='보호구역/낚시 포인트/광산/잠수존만 이동형 범위를 사용할 수 있습니다'})
        return
    end
    cb({ok=true})
    if walkZoneCapture then return end

    walkZoneCapture=true
    walkZoneCaptureGen=walkZoneCaptureGen+1
    local myGen=walkZoneCaptureGen
    walkZonePoints={}
    posPreview=false
    posGen=posGen+1
    releaseNuiFocus()
    SendNUIMessage({action='hideForCapture',on=true})

    local ped=PlayerPedId()
    local start=GetEntityCoords(ped)
    walkZonePoints[1]=vec3(start.x,start.y,start.z)

    CreateThread(function()
        while walkZoneCapture and myGen==walkZoneCaptureGen do
            ped=PlayerPedId()
            local c=GetEntityCoords(ped)
            walkCaptureDraw(walkZonePoints,c)

            local last=walkZonePoints[#walkZonePoints]
            -- V13.9.10: ENTER로 완료하거나 ESC/BACKSPACE로 취소하기 전까지 계속 기록.
            if last and #(c-last) >= WALK_POINT_GAP then
                walkZonePoints[#walkZonePoints+1]=vec3(c.x,c.y,c.z)
            end

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('~y~이동 범위 지정~s~  걸으면 자동 기록 | ~INPUT_FRONTEND_RDOWN~ 완료 | ~INPUT_FRONTEND_CANCEL~ 취소  (%d개)'):format(#walkZonePoints))
            EndTextCommandDisplayHelp(0,false,false,-1)

            if IsControlJustReleased(0,191) then -- ENTER
                if #walkZonePoints < 3 then
                    TriggerEvent('cookie_admin:client:notify','최소 3개 지점이 필요합니다',true)
                else
                    local final=GetEntityCoords(ped)
                    if #(final-walkZonePoints[#walkZonePoints]) > 1.0 then
                        walkZonePoints[#walkZonePoints+1]=vec3(final.x,final.y,final.z)
                    end
                    local sx,sy,sz=0.0,0.0,0.0
                    posPolyPoints={}
                    for _,pt in ipairs(walkZonePoints) do
                        posPolyPoints[#posPolyPoints+1]=vec3(pt.x,pt.y,pt.z)
                        sx,sy,sz=sx+pt.x,sy+pt.y,sz+pt.z
                    end
                    posCenter=vec3(sx/#posPolyPoints,sy/#posPolyPoints,sz/#posPolyPoints)
                    posPedHeading=GetEntityHeading(ped)
                    posShape='poly'
                    refreshPosStrings()
                    posPreview=true
                    refreshPosPreview()
                    walkZoneCapture=false
                    restoreWalkCaptureUi()
                    SendNUIMessage({
                        action='posResult',shape='poly',vec3=posV3,vec4=posV4,preview=true,
                        radius=posRadius,length=boxLength,width=boxWidth,heading=boxHeading,
                        polyCount=#posPolyPoints,summary=posSummary(),
                    })
                    TriggerEvent('cookie_admin:client:notify',('이동형 범위 %d개 지점을 기록했습니다'):format(#posPolyPoints),false)
                    break
                end
            elseif IsControlJustReleased(0,202) or IsControlJustReleased(0,177) then -- ESC/BACKSPACE
                walkZoneCapture=false
                walkZonePoints={}
                restoreWalkCaptureUi()
                TriggerEvent('cookie_admin:client:notify','이동 범위 지정을 취소했습니다',true)
                break
            end
            Wait(0)
        end
    end)
end)

RegisterNUICallback('saveZone', function(data, cb)
    data = data or {}
    if not posCenter then
        SendNUIMessage({ action = 'toast', message = '먼저 좌표를 추출하세요', isWarn = true })
        cb('ok')
        return
    end
    local p = zonePayload(data.type, data.label, tonumber(data.factionId), data.fishingType, data.fishingRegion, data.beaconColor, {
        x = data.teleportX, y = data.teleportY, z = data.teleportZ, h = data.teleportH
    })
    TriggerServerEvent('cookie_safezone:server:createZone', p)

    cb('ok')
end)

RegisterNUICallback('updateFishingPointSettings', function(data, cb)
    data = data or {}
    local id = tonumber(data.id)
    if id then
        TriggerServerEvent('cookie_safezone:server:updateFishingSettings', id, data.fishingType, data.fishingRegion)
    end
    cb('ok')
end)

-- 좌표 관리 > 낚시/광산 출현 설정 V1.5.8
-- NUI -> cookie_admin client -> 각 실제 리소스 server event 로 직접 연결한다.
-- cookie_admin server export 중계를 제거해 DB await/export 경계에서 응답이 유실되는 문제를 차단한다.
RegisterNUICallback('requestFishingPointFish', function(data, cb)
    cb({ ok=true, version='1.5.9' })
    local id = tonumber(data and data.id)
    if not id then SendNUIMessage({ action = 'fishingZoneSettingsError', message = '낚시 포인트 ID가 올바르지 않습니다.' }); return end
    TriggerServerEvent('cookie_admin:server:requestFishingZoneSettingsV159', id)
end)

RegisterNUICallback('saveFishingPointFish', function(data, cb)
    cb({ ok=true, version='1.5.9' })
    TriggerServerEvent('cookie_admin:server:saveFishingZoneSettingsV159', data or {})
end)

RegisterNetEvent('cookie_admin:client:fishingZoneSettingsData', function(data)
    SendNUIMessage({ action = 'fishingZoneSettingsData', data = data or {} })
end)
RegisterNetEvent('cookie_admin:client:fishingZoneSettingsError', function(message)
    SendNUIMessage({ action = 'fishingZoneSettingsError', message = tostring(message or '어종 설정을 불러오지 못했습니다.') })
end)

RegisterNUICallback('requestMiningZoneSettings', function(data, cb)
    cb('ok')
    local id = tonumber(data and data.id)
    if not id then
        SendNUIMessage({ action = 'miningZoneSettingsError', message = '광산 ID가 올바르지 않습니다.' })
        return
    end
    TriggerServerEvent('cookie_mining:server:zoneSettingsRequest', id)
end)

RegisterNUICallback('saveMiningZoneSettings', function(data, cb)
    cb('ok')
    TriggerServerEvent('cookie_mining:server:zoneSettingsSave', data or {})
end)

RegisterNetEvent('cookie_admin:client:miningZoneSettingsData', function(data)
    SendNUIMessage({ action = 'miningZoneSettingsData', data = data or {} })
end)
RegisterNetEvent('cookie_admin:client:miningZoneSettingsError', function(message)
    SendNUIMessage({ action = 'miningZoneSettingsError', message = tostring(message or '광물 설정을 불러오지 못했습니다.') })
end)

RegisterNUICallback('updateTeleportTarget', function(data, cb)
    data = data or {}
    local id = tonumber(data.id)
    if not id then cb('ok') return end

    local p = {
        type = tostring(data.type or 'teleport'),
        shape = tostring(data.shape or 'sphere'),
        label = tostring(data.label or '텔레포트'),
        cx = tonumber(data.cx), cy = tonumber(data.cy), cz = tonumber(data.cz),
        heading = tonumber(data.heading) or 0.0,
        radius = tonumber(data.radius),
        length = tonumber(data.length), width = tonumber(data.width), height = tonumber(data.height),
        factionId = tonumber(data.factionId),
        fishingType = data.fishingType,
        fishingRegion = data.fishingRegion,
        garageKind = data.garageKind,
        beaconR = tonumber(data.beaconR), beaconG = tonumber(data.beaconG),
        beaconB = tonumber(data.beaconB), beaconA = tonumber(data.beaconA),
        teleportX = tonumber(data.teleportX), teleportY = tonumber(data.teleportY),
        teleportZ = tonumber(data.teleportZ), teleportH = tonumber(data.teleportH) or 0.0,
    }
    TriggerServerEvent('cookie_safezone:server:updateZone', id, p)
    cb('ok')
end)

RegisterNUICallback('setZoneFaction', function(data, cb)
    data = data or {}
    local id = tonumber(data.id)
    if not id then cb('ok') return end
    TriggerServerEvent('cookie_safezone:server:setZoneFaction', id, tonumber(data.factionId))

    cb('ok')
end)

RegisterNUICallback('editZone', function(data, cb)
    data = data or {}
    local id = tonumber(data.id)
    if not id then cb('ok') return end
    if data.shape == 'poly' then
        SendNUIMessage({ action='toast', message='이동형 다각형은 새 이동 범위 지정으로 다시 만들어 주세요', isWarn=true })
        cb('ok')
        return
    end

    posShape = (data.shape == 'box') and 'box' or 'circle'
    posCenter = vec3(data.cx + 0.0, data.cy + 0.0, data.cz + 0.0)
    posPedHeading = tonumber(data.heading) or 0.0
    if posShape == 'box' then
        boxLength = tonumber(data.length) or 80.0
        boxWidth = tonumber(data.width) or 60.0
        boxHeading = tonumber(data.heading) or 0.0
    else
        posRadius = tonumber(data.radius) or 60.0
    end
    refreshPosStrings()

    zoneEditId, zoneEditType, zoneEditLabel = id, data.type, data.label
    zoneEditFaction = tonumber(data.factionId)
    zoneEditFishingType = data.fishingType
    zoneEditFishingRegion = data.fishingRegion
    if data.beaconR and data.beaconG and data.beaconB then
        zoneEditBeaconColor = ('#%02X%02X%02X'):format(data.beaconR, data.beaconG, data.beaconB)
    else
        zoneEditBeaconColor = nil
    end
    zoneEditTeleport = {
        x = tonumber(data.teleportX), y = tonumber(data.teleportY),
        z = tonumber(data.teleportZ), h = tonumber(data.teleportH) or 0.0
    }

    boxEditActive = true
    boxEditSnap = {
        radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading, center = posCenter,
    }
    posPreview = true
    startPosThread()
    showBoxEditUI()

    SendNUIMessage({
        action = 'posResult', shape = posShape, vec3 = posV3, vec4 = posV4, preview = true,
        radius = posRadius, length = boxLength, width = boxWidth, heading = boxHeading, summary = posSummary(),
    })

    cb('ok')
end)

RegisterNUICallback('confirmBoxEdit', function(_, cb)
    if not boxEditActive then cb('ok') return end
    local wasZone, zType, zLabel, zFac, zFish, zFishRegion, zColor, zTeleport = zoneEditId, zoneEditType, zoneEditLabel, zoneEditFaction, zoneEditFishingType, zoneEditFishingRegion, zoneEditBeaconColor, zoneEditTeleport
    zoneEditId, zoneEditType, zoneEditLabel, zoneEditFaction, zoneEditFishingType, zoneEditFishingRegion, zoneEditBeaconColor, zoneEditTeleport = nil, nil, nil, nil, nil, nil, nil, nil

    endBoxEditSession()

    if wasZone then

        TriggerServerEvent('cookie_safezone:server:updateZone', wasZone, zonePayload(zType, zLabel, zFac, zFish, zFishRegion, zColor, zTeleport))

    else
        TriggerEvent('chat:addMessage', { args = { '^5[좌표]', 'center = ' .. tostring(posV3) } })
        TriggerEvent('chat:addMessage', { args = { '^5[좌표]', posSummary() } })

    end
    cb('ok')
end)

RegisterNUICallback('cancelBoxEdit', function(_, cb)
    if not boxEditActive then cb('ok') return end

    zoneEditId, zoneEditType, zoneEditLabel, zoneEditFaction, zoneEditFishingType, zoneEditFishingRegion, zoneEditBeaconColor, zoneEditTeleport = nil, nil, nil, nil, nil, nil, nil, nil
    if boxEditSnap then
        posRadius = boxEditSnap.radius
        boxLength, boxWidth, boxHeading = boxEditSnap.length, boxEditSnap.width, boxEditSnap.heading
        posCenter = boxEditSnap.center
        refreshPosStrings()
    end
    endBoxEditSession()

    cb('ok')
end)

RegisterNUICallback('togglePosPreview', function(_, cb)
    if not posCenter then
        SendNUIMessage({ action = 'toast', message = '먼저 좌표를 추출하세요', isWarn = true })
        cb('ok')
        return
    end
    posPreview = not posPreview
    if posPreview then startPosThread() end
    SendNUIMessage({ action = 'posPreviewState', on = posPreview })

    cb('ok')
end)

RegisterNUICallback('stopPosPreview', function(_, cb)
    posPreview = false
    SendNUIMessage({ action = 'posPreviewState', on = false })
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:applyNoclip', function()
    noclipActive = not noclipActive

    if noclipActive then
        CreateThread(function()
            local lastLog = 0
            while noclipActive do
                local ped = PlayerPedId()

                SetEntityVisible(ped, false, false)
                SetEntityCollision(ped, false, false)
                SetEntityInvincible(ped, true)

                local camRot = GetGameplayCamRot(2)
                local pitch = math.rad(camRot.x)
                local yaw = math.rad(camRot.z)
                local cosPitch = math.cos(pitch)
                local fwd = vector3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
                local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)

                local speed = NOCLIP_SPEED
                if IsControlPressed(0, 21) then speed = speed * NOCLIP_BOOST end

                local dx, dy, dz = 0.0, 0.0, 0.0
                if IsControlPressed(0, 32) then dx = dx + fwd.x * speed; dy = dy + fwd.y * speed; dz = dz + fwd.z * speed end
                if IsControlPressed(0, 33) then dx = dx - fwd.x * speed; dy = dy - fwd.y * speed; dz = dz - fwd.z * speed end
                if IsControlPressed(0, 34) then dx = dx - right.x * speed; dy = dy - right.y * speed end
                if IsControlPressed(0, 35) then dx = dx + right.x * speed; dy = dy + right.y * speed end
                if IsControlPressed(0, 44) then dz = dz + speed end
                if IsControlPressed(0, 38) then dz = dz - speed end

                local cur = GetEntityCoords(ped)
                if dx ~= 0.0 or dy ~= 0.0 or dz ~= 0.0 then

                    SetEntityCoordsNoOffset(ped, cur.x + dx, cur.y + dy, cur.z + dz, true, true, true)
                end

                SetEntityVelocity(ped, 0.0, 0.0, 0.0)
                SetEntityHeading(ped, camRot.z)

                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 23, true)

                if Config.Debug then
                    local now = GetGameTimer()
                    if now - lastLog > 1000 then
                        lastLog = now

                    end
                end
                Wait(0)
            end
        end)
    else

        local ped = PlayerPedId()
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        SetEntityInvincible(ped, false)
    end

    toggleFeedback('noclip', noclipActive, '노클립')
end)

RegisterNetEvent('cookie_admin:client:applySuperJump', function()
    superJumpActive = not superJumpActive
    if superJumpActive then
        CreateThread(function()
            while superJumpActive do
                SetSuperJumpThisFrame(PlayerId())
                Wait(0)
            end
        end)
    end
    toggleFeedback('superjump', superJumpActive, '슈퍼점프')
end)

RegisterNetEvent('cookie_admin:client:applyStamina', function()
    staminaActive = not staminaActive
    if staminaActive then
        CreateThread(function()
            while staminaActive do
                RestorePlayerStamina(PlayerId(), 1.0)
                Wait(1000)
            end
        end)
    end
    toggleFeedback('stamina', staminaActive, '무한스태미나')
end)

RegisterNetEvent('cookie_admin:client:applySprint', function()
    sprintActive = not sprintActive
    if sprintActive then
        CreateThread(function()
            while sprintActive do
                SetRunSprintMultiplierForPlayer(PlayerId(), SPRINT_MULT)
                SetPedMoveRateOverride(PlayerPedId(), SPRINT_MOVE_RATE)
                Wait(0)
            end
        end)
    else

        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
        SetPedMoveRateOverride(PlayerPedId(), 1.0)
    end
    toggleFeedback('sprint', sprintActive, '질주부스트')
end)

RegisterNUICallback('requestPersonalStorage', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestPersonalStorage')
    cb({ ok = true })
end)

RegisterNetEvent('cookie_admin:client:personalStorage', function(data)
    SendNUIMessage({ action = 'personalStorageData', data = data or {} })
end)


RegisterNetEvent('cookie_admin:client:restoreSkinNow', function()
    exports['cookie_skins']:restoreSkin()
    CookieRefreshMugshot()
end)

RegisterNetEvent('cookie_admin:client:deletePackVehicle', function(netId, plate)
    local ped = PlayerPedId()
    local veh = 0
    if netId and netId > 0 then
        veh = NetToVeh(netId)
    end
    if veh == 0 or not DoesEntityExist(veh) then
        local pos = GetEntityCoords(ped)
        local found = GetClosestVehicle(pos.x, pos.y, pos.z, 8.0, 0, 71)
        if found ~= 0 and DoesEntityExist(found) then
            local foundPlate = string.gsub(GetVehicleNumberPlateText(found) or '', '%s+', '')
            local wantPlate = string.gsub(tostring(plate or ''), '%s+', '')
            if wantPlate == '' or foundPlate == wantPlate then
                veh = found
            end
        end
    end
    if veh ~= 0 and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
    end
end)

local function useLimitedInventoryItem(data, onSuccess)
    if GetResourceState('ox_inventory') ~= 'started' then
        TriggerEvent('cookie_admin:client:notify', 'ox_inventory가 실행 중이 아닙니다.', true)
        return
    end
    exports.ox_inventory:useItem(data, function(used)
        if not used then return end
        onSuccess(used)
    end)
end

exports('skinPackKit', function(data)
    useLimitedInventoryItem(data, function()
        TriggerServerEvent('cookie_admin:server:useSkinPackKit')
    end)
end)

exports('vehiclePackKit', function(data)
    useLimitedInventoryItem(data, function()
        local ped = PlayerPedId()
        if ped == 0 or IsEntityDead(ped) then return end
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then
            TriggerEvent('cookie_admin:client:notify', '차량에 탑승한 상태에서만 사용할 수 있습니다.', true)
            return
        end
        if GetPedInVehicleSeat(veh, -1) ~= ped then
            TriggerEvent('cookie_admin:client:notify', '운전석에서만 차량 포장이 가능합니다.', true)
            return
        end
        local model = GetEntityModel(veh)
        local plate = string.gsub(GetVehicleNumberPlateText(veh) or '', '^%s*(.-)%s*$', '%1')
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('cookie_admin:server:useVehiclePackKit', {
            model = model and tostring(GetDisplayNameFromVehicleModel(model) or '') or '',
            plate = plate,
            netId = netId,
        })
    end)
end)


RegisterNUICallback('unpackLimitedVehicle', function(data, cb)
    if data and data.ownedId then TriggerServerEvent('cookie_admin:server:unpackLimitedVehicle', data.ownedId) end
    cb({ ok = true })
end)

RegisterNUICallback('placeFurniture', function(data, cb)
    local raw = data and tostring(data.ownedId or '') or ''
    local ownedId = tonumber(raw:gsub('^packed:', ''))
    cb({ ok = ownedId ~= nil })
    if not ownedId then return end
    if CookieAdminClosePanel then CookieAdminClosePanel() end
    Wait(100)
    if GetResourceState('cookie_assets') ~= 'started' then
        TriggerEvent('cookie_admin:client:notify', 'cookie_assets 리소스가 실행 중이 아닙니다.', true)
        return
    end
    TriggerEvent('cookie_assets:client:beginFurniturePlacement', ownedId)
end)

RegisterNUICallback('toggleCosmetic', function(data, cb)
    local raw = data and tostring(data.ownedId or '') or ''
    local ownedId = tonumber(raw:gsub('^packed:', ''))
    cb({ ok = ownedId ~= nil })
    if ownedId then
        TriggerServerEvent('cookie_assets:server:toggleCosmetic', ownedId)
    end
end)

RegisterNUICallback('applySkin', function(data, cb)
    if data and data.ownedId then
        TriggerServerEvent('cookie_admin:server:equipLimitedSkin', data.ownedId)
    else
        TriggerServerEvent('cookie_admin:server:applySkin', data.model)
    end
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:applySkin', function(model)
    exports['cookie_skins']:applySkin(model)
    CookieRefreshMugshot()
end)

RegisterNUICallback('restoreSkin', function(_, cb)
    exports['cookie_skins']:restoreSkin()
    CookieRefreshMugshot()
    cb('ok')
end)

function CookieRefreshMugshot()
    CreateThread(function()
        Wait(600)
        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then return end

        local mug = safeMugshotBase64(ped)
        if mug then
            SendNUIMessage({ action = 'mugshot', myMugshot = mug })
        end
    end)
end

RegisterNetEvent('cookie_admin:client:notify', function(message, isWarn, tone)
    SendNUIMessage({ action = 'toast', message = message, isWarn = isWarn or false, tone = tone })
end)

local function saveAdminState()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    savedState = {
        x = coords.x, y = coords.y, z = coords.z,
        heading = heading,
        health = GetEntityHealth(ped),
        armor = GetPedArmour(ped),
    }

end

local function godOn()
    if godActive then return end
    godActive = true
    local ped = PlayerPedId()
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(PlayerId(), true)
    godThread = CreateThread(function()
        while godActive do
            local p = PlayerPedId()
            SetEntityInvincible(p, true)
            SetPlayerInvincible(PlayerId(), true)
            SetPedCanRagdoll(p, false)
            ClearPedBloodDamage(p)
            Wait(0)
        end
    end)

end

local function godOff()
    godActive = false
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetPlayerInvincible(PlayerId(), false)
    SetPedCanRagdoll(ped, true)

end

local function restoreAdminState()
    if not savedState then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, savedState.x, savedState.y, savedState.z, false, false, false, false)
    SetEntityHeading(ped, savedState.heading)

    savedState = nil
end

RegisterNetEvent('cookie_admin:client:stateChanged', function(newState)
    SendNUIMessage({ action = 'stateChanged', state = newState })

    if newState == 'duty' then
        saveAdminState()
        godOn()
    elseif newState == 'rp' then
        godOff()
        restoreAdminState()
        exports['cookie_skins']:restoreSkin()
    end
end)

RegisterNetEvent('cookie_admin:client:repairVehicles', function(netIds)
    if type(netIds) ~= 'table' then return end

    CreateThread(function()
        for _, netId in ipairs(netIds) do
            netId = tonumber(netId)
            if netId and netId > 0 then
                local veh = NetworkGetEntityFromNetworkId(netId)
                if veh and veh ~= 0 and DoesEntityExist(veh) and IsEntityAVehicle(veh) then
                    local untilAt = GetGameTimer() + 700
                    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < untilAt do
                        NetworkRequestControlOfEntity(veh)
                        Wait(0)
                    end

                    SetVehicleFixed(veh)
                    SetVehicleDeformationFixed(veh)
                    SetVehicleEngineHealth(veh, 1000.0)
                    SetVehicleBodyHealth(veh, 1000.0)
                    SetVehiclePetrolTankHealth(veh, 1000.0)
                    SetVehicleDirtLevel(veh, 0.0)
                    SetVehicleUndriveable(veh, false)
                    SetVehicleEngineOn(veh, true, true, false)
                end
            end
        end
    end)
end)

-- COOKIE ADMIN REPAIR V2.1: 수리 대상자에게 보이는 실제 차량 기준으로 수리
-- 서버 권한 인증을 통과한 admin->server 요청만 이 이벤트를 발생시킨다.
RegisterNetEvent('cookie_admin:client:repairNearestForAdmin', function(ticket, maxDistance)
    ticket = tonumber(ticket)
    if not ticket then return end
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        TriggerServerEvent('cookie_admin:server:repairClientResult', ticket, 'no_vehicle')
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        vehicle = 0
        local pos = GetEntityCoords(ped)
        local best = math.min(tonumber(maxDistance) or 8.0, 10.0)
        -- 서버 GetAllVehicles()보다 로컬 스트리밍 차량 목록이 확실한 경우가 있다.
        local pool = GetGamePool('CVehicle')
        for _, candidate in ipairs(pool or {}) do
            if candidate and candidate ~= 0 and DoesEntityExist(candidate) then
                local dist = #(GetEntityCoords(candidate) - pos)
                if dist < best then
                    best = dist
                    vehicle = candidate
                end
            end
        end
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        TriggerServerEvent('cookie_admin:server:repairClientResult', ticket, 'no_vehicle')
        return
    end

    CreateThread(function()
        -- OneSync 차량의 네트워크 소유자가 다른 사람일 수 있어 최대 1.5초 제어권 확보.
        local deadline = GetGameTimer() + 1500
        if NetworkGetEntityIsNetworked(vehicle) then
            while DoesEntityExist(vehicle) and not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
                NetworkRequestControlOfEntity(vehicle)
                Wait(50)
            end
            if not NetworkHasControlOfEntity(vehicle) then
                TriggerServerEvent('cookie_admin:server:repairClientResult', ticket, 'no_control')
                return
            end
        end
        if not DoesEntityExist(vehicle) then
            TriggerServerEvent('cookie_admin:server:repairClientResult', ticket, 'no_vehicle')
            return
        end
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetVehicleUndriveable(vehicle, false)
        -- 관리자 수리는 엔진을 강제로 켜지 않는다 (시동키 시스템과 충돌 방지).
        TriggerServerEvent('cookie_admin:server:repairClientResult', ticket, 'ok')
    end)
end)

RegisterNetEvent('cookie_admin:client:restoreHp', function(targetServerId)
    local targetPed
    if targetServerId == GetPlayerServerId(PlayerId()) then
        targetPed = PlayerPedId()
    else
        local targetPlayer = GetPlayerFromServerId(targetServerId)
        if targetPlayer == -1 then return end
        targetPed = GetPlayerPed(targetPlayer)
    end
    if targetPed == 0 then return end
    local maxHp = GetEntityMaxHealth(targetPed)
    local before = GetEntityHealth(targetPed)
    SetEntityHealth(targetPed, maxHp)
    Wait(0)
    local after = GetEntityHealth(targetPed)

end)

RegisterNetEvent('cookie_admin:client:teleportTo', function(coords, heading)
    local ped = PlayerPedId()
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, heading)

    if savedState then
        savedState.x = coords.x
        savedState.y = coords.y
        savedState.z = coords.z
        savedState.heading = heading
    end

end)

RegisterNetEvent('cookie_admin:client:bringTo', function(adminCoords, adminHeading)
    local ped = PlayerPedId()
    local rad = math.rad(adminHeading)
    local fx = -math.sin(rad)
    local fy = math.cos(rad)
    local tx = adminCoords.x + fx * 1.5
    local ty = adminCoords.y + fy * 1.5
    local tz = adminCoords.z
    SetEntityCoords(ped, tx, ty, tz, false, false, false, false)
    SetEntityHeading(ped, (adminHeading + 180.0) % 360.0)

end)

RegisterNetEvent('cookie_admin:client:melt', function()
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    ClearPedSecondaryTask(ped)
    DetachEntity(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEnableHandcuffs(ped, false)
    SetPedCanRagdoll(ped, true)
    SetEntityCollision(ped, true, true)
    SetEntityAlpha(ped, 255, false)
    ResetEntityAlpha(ped)
    SetPlayerControl(PlayerId(), true, 0)
    SetEntityInvincible(ped, false)

end)

local zoneUiOpen = false

local function openZoneUi(msg)
    zoneUiOpen = true
    acquireNuiFocus()
    SendNUIMessage(msg)
end

CreateThread(function()
    while true do
        if zoneUiOpen then
            if IsControlJustReleased(0, 200) or IsControlJustReleased(0, 322) then
                zoneUiOpen = false
                releaseNuiFocus()
                SendNUIMessage({ action = 'zoneUiClose' })
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

local function closeZoneUi()
    zoneUiOpen = false
    releaseNuiFocus()
    SendNUIMessage({ action = 'zoneUiClose' })
end

RegisterNetEvent('cookie_admin:client:openDuty', function()
    TriggerServerEvent('cookie_admin:server:requestDuty')
end)

RegisterNetEvent('cookie_admin:client:openArmory', function()
    TriggerServerEvent('cookie_admin:server:requestArmory')
end)

RegisterNetEvent('cookie_admin:client:openDutyUI', function(payload)
    if not payload then return end
    payload.action = 'dutyOpen'
    openZoneUi(payload)
end)

RegisterNetEvent('cookie_admin:client:openArmoryUI', function(payload)
    if not payload then return end
    payload.action = 'armoryOpen'
    openZoneUi(payload)
end)

RegisterNetEvent('cookie_admin:client:dutyState', function(_)
    TriggerServerEvent('cookie_admin:server:requestJobDisplay')
end)

RegisterNetEvent('cookie_admin:client:setArmor', function(amount)
    local ped = PlayerPedId()
    local v = math.floor(tonumber(amount) or 0)
    if v <= 0 then
        SetPedArmour(ped, 0)
        return
    end
    SetPlayerMaxArmour(PlayerId(), v)
    SetPedArmour(ped, v)
end)

RegisterNUICallback('dutyToggle', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:dutyToggle')
end)

RegisterNUICallback('armoryBuy', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:armoryBuy', data and data.id, data and data.qty)
end)

RegisterNUICallback('armoryGrade', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:armoryGrade', data and data.id, data and data.grade)
end)

RegisterNUICallback('closeZoneUi', function(_, cb)
    cb({ ok = true })
    closeZoneUi()
end)

local function buildArmoryCatalog()

    local allowed, order = {}, {}
    for i, name in ipairs(Config.ArmoryLineup or {}) do
        allowed[name] = true
        order[name] = i
    end

    local byName = {}
    for _, cat in ipairs(Config.Weapons or {}) do
        for _, w in ipairs(cat.items or {}) do
            if allowed[w.name] then
                byName[w.name] = {
                    item = w.name, label = w.label, ammo = w.ammo, group = cat.label,

                    img = (Config.ArmoryImageAlias and Config.ArmoryImageAlias[w.name]) or w.name,
                }
            end
        end
    end

    local weapons, ammo, seenAmmo = {}, {}, {}
    for _, name in ipairs(Config.ArmoryLineup or {}) do
        local w = byName[name]
        if w then
            weapons[#weapons + 1] = w

            if w.ammo and not seenAmmo[w.ammo] then
                seenAmmo[w.ammo] = true
                ammo[#ammo + 1] = {
                    item = w.ammo,
                    label = (Config.AmmoLabels and Config.AmmoLabels[w.ammo]) or w.ammo,
                    group = w.group,
                }
            end
        end
    end

    return {
        weapon = weapons,
        ammo = ammo,
        armor = { { item = '__armor__', label = Config.ArmorLabel or '근무 케블라', group = '방탄복' } },
    }
end

RegisterNUICallback('requestArmoryAdmin', function(data, cb)
    cb({ ok = true })
    local fid = data and data.factionId

    SendNUIMessage({
        action = 'armoryCatalog',
        factionId = fid,
        catalog = buildArmoryCatalog(),
    })

    TriggerServerEvent('cookie_admin:server:requestArmoryAdmin', fid)
end)

RegisterNUICallback('armorySave', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:armorySave', data)
end)

RegisterNUICallback('armoryDelete', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:armoryDelete', data and data.id, data and data.factionId)
end)

RegisterNetEvent('cookie_admin:client:armoryAdmin', function(payload)
    if not payload then return end
    payload.action = 'armoryAdmin'
    SendNUIMessage(payload)
end)

local ACTIVITY_CONTROLS = {
    30,
    31,
    21,
    22,
    24,
    25,
    38,
    245,
    1, 2,
}

CreateThread(function()
    local lastPing = 0
    local active = false

    while true do

        if not active then
            for _, c in ipairs(ACTIVITY_CONTROLS) do
                if IsControlPressed(0, c) or IsDisabledControlPressed(0, c) then
                    active = true
                    break
                end
            end
        end

        local now = GetGameTimer()
        if active and (now - lastPing) > 60000 then
            lastPing = now
            active = false
            TriggerServerEvent('cookie_admin:server:activityPing')
        end

        Wait(500)
    end
end) 


RegisterNUICallback('requestDevMode', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestDevMode')
    cb({ ok=true })
end)

RegisterNUICallback('setDevMode', function(data, cb)
    TriggerServerEvent('cookie_admin:server:setDevMode', data or {})
    cb({ ok=true })
end)

RegisterNUICallback('addDevWhitelist', function(data, cb)
    TriggerServerEvent('cookie_admin:server:addDevWhitelist', data or {})
    cb({ ok=true })
end)

RegisterNUICallback('removeDevWhitelist', function(data, cb)
    TriggerServerEvent('cookie_admin:server:removeDevWhitelist', data or {})
    cb({ ok=true })
end)

RegisterNUICallback('refreshDevWhitelist', function(_, cb)
    TriggerServerEvent('cookie_admin:server:refreshDevWhitelist')
    cb({ ok=true })
end)

RegisterNetEvent('cookie_admin:client:devModeData', function(data)
    SendNUIMessage({ action='devModeData', data=data or {} })
end)

RegisterNetEvent('cookie_admin:client:devModeError', function(message)
    SendNUIMessage({ action='devModeError', message=tostring(message or '개발모드 데이터를 불러오지 못했습니다.') })
end)

RegisterNUICallback('requestRankingAdmin', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestRankingAdmin')
    cb({ ok=true })
end)

RegisterNUICallback('resetRankings', function(data, cb)
    TriggerServerEvent('cookie_admin:server:resetRankings', data or {})
    cb({ ok=true })
end)

RegisterNetEvent('cookie_admin:client:rankingAdminData', function(data)
    SendNUIMessage({ action='rankingAdminData', data=data or {} })
end)

RegisterNetEvent('cookie_admin:client:rankingAdminError', function(message)
    SendNUIMessage({ action='rankingAdminError', message=tostring(message or '순위표 관리 데이터를 불러오지 못했습니다.') })
end)

RegisterNUICallback('requestFishingSystem', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestFishingSystem')
end)

RegisterNUICallback('saveFishingSystem', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveFishingSystem', data or {})
end)

RegisterNetEvent('cookie_admin:client:fishingSystemData', function(data)
    SendNUIMessage({ action = 'fishingSystemData', data = data })
end)


RegisterNUICallback('requestFishingCollection', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_fishing:server:collectionRequest')
end)

RegisterNetEvent('cookie_admin:client:fishingCollectionData', function(data)
    SendNUIMessage({ action = 'fishingCollectionData', data = data or {} })
end)


RegisterNUICallback('requestMiningCollection', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_mining:server:collectionRequest')
end)

RegisterNetEvent('cookie_admin:client:miningCollectionData', function(data)
    SendNUIMessage({ action = 'miningCollectionData', data = data or {} })
end)

RegisterNUICallback('requestMiningSystem', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestMiningSystem')
end)

RegisterNUICallback('saveMiningSystem', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:saveMiningSystem', data or {})
end)

RegisterNetEvent('cookie_admin:client:miningSystemData', function(data)
    SendNUIMessage({ action = 'miningSystemData', data = data or {} })
end)

RegisterNetEvent('cookie_admin:client:miningSystemError', function(msg)
    SendNUIMessage({ action = 'miningSystemError', message = tostring(msg or '광산 설정을 불러오지 못했습니다') })
end)


RegisterNUICallback('jobLevelUp', function(data, cb)
    cb({ok=true})
    TriggerServerEvent('cookie_admin:server:jobLevelUp', data and data.jobKey)
end)

RegisterNUICallback('requestJobLevelSystem', function(_, cb)
    cb({ok=true})
    TriggerServerEvent('cookie_admin:server:requestJobLevelSystem')
end)

RegisterNUICallback('saveJobLevelSystem', function(data, cb)
    cb({ok=true})
    TriggerServerEvent('cookie_admin:server:saveJobLevelSystem', data)
end)

RegisterNetEvent('cookie_admin:client:jobLevelsRefresh', function(data)
    SendNUIMessage({action='jobLevelsRefresh',data=data or {}})
end)

RegisterNetEvent('cookie_admin:client:jobLevelSystemData', function(data)
    SendNUIMessage({action='jobLevelSystemData',data=data or {}})
end)


-- Emergency developer command: if F3 keymapping is stale after resource restart,
-- this invokes the exact same F3 open command path.
RegisterCommand('cookieadminopen', function()
    ExecuteCommand('cookieadmin')
end, false)

-- NUI 포커스가 비정상적으로 남았을 때 콘솔/채팅에서 즉시 복구.
RegisterCommand('f3fix', function()
    isOpen = false
    boxEditActive, boxEditUI, boxEditSnap = false, false, nil
    walkZoneCapture = false
    walkZonePoints = {}
    if CookieStopPreview then CookieStopPreview(true) end
    if stopZonePreview then stopZonePreview() end
    clearAdminFrontend(true)
    -- 비상 복구 명령은 관리자 프리뷰 잔여 카메라까지 강제로 끝낸다.
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    DisplayRadar(true)
    releaseNuiFocus(true)
    SendNUIMessage({ action = 'hideForCapture', on = false })
    SendNUIMessage({ action = 'zoneUiClose' })
    SendNUIMessage({ action = 'close' })
    TriggerEvent('cookie_hud:client:hudVisible', true)
    TriggerEvent('cookie_admin:client:notify', '관리자 UI/카메라/프론트엔드를 복구했습니다', false)
end, false)

RegisterNetEvent('cookie_admin:client:forceClose', function()
    closePanel()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- 중요: 여기서 cookieUiFocus(false)를 호출하면
    -- 접속 직후 cookie_select의 '시작 플레이' NUI 포커스를 빼앗을 수 있다.
    -- 관리자 NUI 시각 상태만 초기화하고 포커스는 건드리지 않는다.
    isOpen = false
    adminOwnsNuiFocus = false
    adminOwnsFrontend = false
    SendNUIMessage({ action = 'close' })
    SendNUIMessage({ action = 'zoneUiClose' })
    SendNUIMessage({ action = 'hideForCapture', on = false })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if CookieStopPreview then CookieStopPreview(true) end
    if stopZonePreview then stopZonePreview() end
    clearAdminFrontend(false)
    -- cookie_admin이 실제로 포커스를 가진 상태에서만 반환한다.
    releaseNuiFocus(false)
end)

-- ─────────────────────────────────────────────────────────────
-- 편의점 상품 관리 (비콘 관리 → 공용 상품 카탈로그)
-- 실제 DB/구매 처리는 cookie_safezone에서 담당한다.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback('requestConvenienceAdmin', function(_, cb)
    TriggerServerEvent('cookie_safezone:server:requestConvenienceAdmin')
    cb('ok')
end)

RegisterNUICallback('saveConvenienceFood', function(data, cb)
    TriggerServerEvent('cookie_safezone:server:saveConvenienceFood', data or {})
    cb('ok')
end)

RegisterNUICallback('deleteConvenienceFood', function(data, cb)
    TriggerServerEvent('cookie_safezone:server:deleteConvenienceFood', data and data.id)
    cb('ok')
end)

RegisterNetEvent('cookie_safezone:client:convenienceAdmin', function(rows)
    SendNUIMessage({
        action = 'convenienceAdmin',
        rows = rows or {},
    })
end)

-- ─────────────────────────────────────────────────────────────
-- 시민직업 도구 상점 관리
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback('requestJobShopAdmin', function(_, cb)
    TriggerServerEvent('cookie_safezone:server:requestJobShopAdmin')
    cb('ok')
end)

RegisterNUICallback('saveJobShopItem', function(data, cb)
    TriggerServerEvent('cookie_safezone:server:saveJobShopItem', data or {})
    cb('ok')
end)

RegisterNUICallback('deleteJobShopItem', function(data, cb)
    TriggerServerEvent('cookie_safezone:server:deleteJobShopItem', data and data.id)
    cb('ok')
end)

RegisterNetEvent('cookie_safezone:client:jobShopAdmin', function(data)
    SendNUIMessage({
        action = 'jobShopAdmin',
        data = data or {},
    })
end)

-- ─────────────────────────────────────────────────────────────
-- 팩션 관리자 V2 (서버 팩션 관리 전용)
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback('factionRankSaveAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionRankSaveAdmin', data or {})
    cb('ok')
end)

RegisterNUICallback('factionRankDeleteAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionRankDeleteAdmin', data or {})
    cb('ok')
end)

RegisterNUICallback('factionMemberRankAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionMemberRankAdmin', data or {})
    cb('ok')
end)

RegisterNUICallback('factionMemberRemoveAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionMemberRemoveAdmin', data or {})
    cb('ok')
end)

RegisterNUICallback('factionWarningAddAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionWarningAddAdmin', data or {})
    cb('ok')
end)

RegisterNUICallback('factionWarningRevokeAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionWarningRevokeAdmin', data or {})
    cb('ok')
end)

RegisterNUICallback('factionForceOffDutyAdmin', function(data, cb)
    TriggerServerEvent('cookie_admin:server:factionForceOffDutyAdmin', data or {})
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────
-- 경제 시스템 관리 (시민 기본 급여)
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback('requestEconomySystem', function(_, cb)
    TriggerServerEvent('cookie_admin:server:requestEconomySystem')
    cb('ok')
end)

RegisterNUICallback('saveEconomySystem', function(data, cb)
    TriggerServerEvent('cookie_admin:server:saveEconomySystem', data or {})
    cb('ok')
end)

RegisterNetEvent('cookie_admin:client:economySystemData', function(data)
    SendNUIMessage({ action = 'economySystemData', data = data or {} })
end)

print('^2[cookie_admin]^7 F3 admin client ready · V0.7.2')


-- 2026-09-25 관리자 뉴비가이드 기능: 위치 확인 / 끌고가기
local cookieAdminDraggedBy = nil

RegisterNetEvent('cookie_admin:client:showTargetLocation', function(targetName, x, y, z)
    local msg = ('%s 위치: X %.2f / Y %.2f / Z %.2f'):format(tostring(targetName or '대상'), tonumber(x) or 0.0, tonumber(y) or 0.0, tonumber(z) or 0.0)
    TriggerEvent('chat:addMessage', { args = { '^5[위치 확인]', msg } })
    SendNUIMessage({ action = 'toast', message = msg, isWarn = false })
end)

RegisterNetEvent('cookie_admin:client:toggleAdminDrag', function(adminServerId)
    local ped = PlayerPedId()
    if cookieAdminDraggedBy then
        DetachEntity(ped, true, false)
        cookieAdminDraggedBy = nil
        return
    end
    local player = GetPlayerFromServerId(tonumber(adminServerId) or -1)
    if player == -1 then return end
    local adminPed = GetPlayerPed(player)
    if not DoesEntityExist(adminPed) then return end
    cookieAdminDraggedBy = tonumber(adminServerId)
    AttachEntityToEntity(ped, adminPed, 11816, 0.45, 0.45, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
end)

CreateThread(function()
    while true do
        if cookieAdminDraggedBy then
            local p = GetPlayerFromServerId(cookieAdminDraggedBy)
            if p == -1 or not DoesEntityExist(GetPlayerPed(p)) or IsEntityDead(PlayerPedId()) then
                DetachEntity(PlayerPedId(), true, false)
                cookieAdminDraggedBy = nil
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

print('^2[cookie_admin]^7 FOCUS ISOLATION V1.5.4 active')

print('^2[cookie_admin]^7 FISH/MINING DIRECT SETTINGS V1.5.8 active')

print('^2[cookie_admin]^7 FISH SETTINGS HARD FIX V1.5.9 active')

print('^2[cookie_admin]^7 VISUAL RECOVERY V1.6.3 active')

print('^2[cookie_admin]^7 JOIN SCREEN ISOLATION V1.6.4 active')

print('^2[cookie_admin]^7 RESOURCE RECOVERY V1.6.5 active')

print('^2[cookie_admin]^7 PERSONAL STORAGE + PACK KIT CLIENT V1.7.0 active')

print('^2[cookie_admin]^7 FISHING SYSTEM UI ROUTE FIX V13.2 ready')

print('^2[cookie_admin]^7 AFK WALK ZONE UNLIMITED V13.9.10 ready')


-- ============================================================
-- COOKIE ITEM CONFISCATION V14.2.8
-- ============================================================
RegisterNUICallback('requestTargetInventory', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:requestTargetInventory', data and data.targetServerId)
end)

RegisterNUICallback('confiscateItem', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:confiscateItem', data or {})
end)

RegisterNUICallback('confiscateAllItems', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_admin:server:confiscateAllItems', data and data.targetServerId)
end)

RegisterNetEvent('cookie_admin:client:targetInventory', function(payload)
    SendNUIMessage({ action = 'targetInventory', data = payload or {} })
end)

-- COOKIE STORE V2: F3 System Management launcher (isolated callback)
RegisterNUICallback('cookieStoreLaunch',function(_,cb)
    cb({ok=true})
    closePanel()
    SetTimeout(120,function()
        TriggerEvent('cookie_store:client:launchAdmin')
    end)
end)

-- COOKIE STORE V2: F3 customer-facing HUD (retains admin manager)
RegisterNUICallback('cookieStoreUserLaunch', function(_,cb)
    cb({ok=true})
    closePanel()
    SetTimeout(180, function()
        if GetResourceState('cookie_store') == 'started' then
            TriggerServerEvent('cookie_store:server:open', false)
        else
            lib.notify({title='COOKIE STORE', description='cookie_store 리소스가 시작되지 않았습니다.',type='error'})
        end
    end)
end)

-- F3 인트라넷 판매 목록 관리 (기존 NUI/관리 패널 보존)
RegisterNUICallback('ciCatalogAdminList', function(d, cb)
    TriggerServerEvent('cookie_admin:ciCatalogList', d and d.factionId)
    cb({ok=true})
end)
RegisterNUICallback('ciCatalogAdminSave', function(d, cb)
    TriggerServerEvent('cookie_admin:ciCatalogSave', d)
    cb({ok=true})
end)
RegisterNUICallback('ciCatalogAdminDelete', function(d, cb)
    TriggerServerEvent('cookie_admin:ciCatalogDelete', d)
    cb({ok=true})
end)
RegisterNetEvent('cookie_admin:ciCatalogData', function(fid, rows)
    SendNUIMessage({action='ciCatalogAdminData', factionId=fid, rows=rows or {}})
end)

-- F3 faction NPC admin NUI hooks. Position is captured server-side from admin ped.
RegisterNUICallback('ciFactionNpcList',function(d,cb) TriggerServerEvent('cookie_admin:factionNpcAdminList',d and d.factionId);cb({ok=true}) end)
RegisterNUICallback('ciFactionNpcPlace',function(d,cb) TriggerServerEvent('cookie_admin:factionNpcAdminPlace',d);cb({ok=true}) end)
RegisterNUICallback('ciFactionNpcUpdate',function(d,cb) TriggerServerEvent('cookie_admin:factionNpcAdminUpdate',d);cb({ok=true}) end)
RegisterNUICallback('ciFactionNpcDelete',function(d,cb) TriggerServerEvent('cookie_admin:factionNpcAdminDelete',d);cb({ok=true}) end)
RegisterNetEvent('cookie_admin:factionNpcAdminData',function(fid,rows) SendNUIMessage({action='ciFactionNpcData',factionId=fid,rows=rows or {}}) end)
