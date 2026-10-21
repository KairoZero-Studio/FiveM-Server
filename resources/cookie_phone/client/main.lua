local function cookieUiFocus(on)
    local resourceName = GetCurrentResourceName()

    if on then
        if GetResourceState('cookie_core') == 'started' then
            local ok, owner, previousOwner = exports.cookie_core:Acquire(resourceName, false)
            if ok ~= true then return false, owner, previousOwner end
        end

        -- The resource that owns the NUI page must own the native NUI focus too.
        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
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

-- COOKIE PHONE V2
-- P toggles the phone. Qbox phone number + PMA-Voice calls.

local phoneOpen = false
local phoneBusy = false
local phoneObject = nil
local phoneAnimDict = 'cellphone@'
local phoneAnimName = 'cellphone_text_read_base'
local phoneModel = `prop_npc_phone_02`
local currentCall = nil
local myPhone = ''
local activeConversationPhone = nil
local dispatchPending = {}
local dispatchGpsBlip = nil
local dispatchGpsCallId = nil
local localAfk = false
local afkLastActivity = GetGameTimer()
local afkLastCoords = nil
local afkLastHeading = nil
local phoneCameraActive = false
local cameraCaptureBusy = false
local openPhone, closePhone

local cameraUiSuppressed = false
local cameraChatAdjusted = false
local cameraPrevInvBusy = nil
local cameraPrevInvHotkeys = nil

local function streetLabel(coords)
    if not coords then return '알 수 없는 위치' end
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    local street = streetHash and streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or ''
    local crossing = crossingHash and crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or ''
    if street ~= '' and crossing ~= '' then return street .. ' / ' .. crossing end
    if street ~= '' then return street end
    return ('%.0f, %.0f'):format(coords.x, coords.y)
end

local function taxiLocationData()
    local pos = GetEntityCoords(PlayerPedId())
    local result = {
        pickup = { x = pos.x, y = pos.y, z = pos.z },
        pickupLabel = streetLabel(pos),
        dest = nil,
        destLabel = nil,
        distance = nil,
    }

    local waypoint = GetFirstBlipInfoId(8)
    if waypoint and waypoint ~= 0 and DoesBlipExist(waypoint) then
        local d = GetBlipInfoIdCoord(waypoint)
        result.dest = { x = d.x, y = d.y, z = d.z }
        result.destLabel = streetLabel(d)
        result.distance = #(pos - d)
    end
    return result
end

local function findRepairVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        veh = GetClosestVehicle(GetEntityCoords(ped), 7.0, 0, 70)
    end
    if veh == 0 or not DoesEntityExist(veh) then return nil end

    local pos = GetEntityCoords(veh)
    local model = GetEntityModel(veh)
    local code = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(code)
    if not label or label == 'NULL' or label == '' then label = code end

    return {
        netId = VehToNet(veh),
        coord = { x = pos.x, y = pos.y, z = pos.z },
        label = label,
        plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', ''),
        engine = math.max(0, math.min(100, math.floor((GetVehicleEngineHealth(veh) / 1000.0) * 100 + 0.5))),
        body = math.max(0, math.min(100, math.floor((GetVehicleBodyHealth(veh) / 1000.0) * 100 + 0.5))),
    }
end

local function setPhoneState(value)
    local isOpen = value == true
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('cookiePhoneOpen', isOpen, true)
    end
    TriggerServerEvent('cookie_phone:server:phoneState', isOpen)
end

local function loadAnim(dict, timeout)
    RequestAnimDict(dict)
    local untilTime = GetGameTimer() + (timeout or 1500)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < untilTime do Wait(0) end
    return HasAnimDictLoaded(dict)
end

local function loadModel(model, timeout)
    RequestModel(model)
    local untilTime = GetGameTimer() + (timeout or 1500)
    while not HasModelLoaded(model) and GetGameTimer() < untilTime do Wait(0) end
    return HasModelLoaded(model)
end

local function removePhoneProp()
    if phoneObject and DoesEntityExist(phoneObject) then DeleteEntity(phoneObject) end
    phoneObject = nil
end

local function stopPhoneAnim()
    local ped = PlayerPedId()
    StopAnimTask(ped, phoneAnimDict, phoneAnimName, 2.0)
    removePhoneProp()
end

local function startPhoneAnim()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local animOk = loadAnim(phoneAnimDict, 1200)
    local modelOk = loadModel(phoneModel, 1200)

    if animOk then
        TaskPlayAnim(ped, phoneAnimDict, phoneAnimName, 3.0, -1.0, -1, 49, 0.0, false, false, false)
    end

    if modelOk then
        removePhoneProp()
        local pos = GetEntityCoords(ped)
        phoneObject = CreateObject(phoneModel, pos.x, pos.y, pos.z + 0.2, true, true, false)
        if phoneObject and phoneObject ~= 0 then
            AttachEntityToEntity(
                phoneObject, ped, GetPedBoneIndex(ped, 28422),
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                true, true, false, true, 1, true
            )
        end
        SetModelAsNoLongerNeeded(phoneModel)
    end
end

local function syncCallToNui()
    SendNUIMessage({
        action = 'callSync',
        call = currentCall
    })
end

local function requestPhoneData()
    TriggerServerEvent('cookie_phone:server:requestData')
end

local function nativeNotify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(tostring(message or ''))
    EndTextCommandThefeedPostTicker(false, false)
end

-- COOKIE PRO CAMERA ---------------------------------------------------------
local cameraCam = nil
local cameraMode = 'rear'           -- rear | front
local cameraOrientation = 'portrait' -- portrait | landscape
local cameraZoom = 1.0
local cameraFlash = 'auto'          -- auto | on | off
local cameraTimer = 0               -- 0 | 3 | 10
local cameraGrid = true
local cameraPitch = 0.0
local selfieOrbit = 0.0
local selfieHeight = 0.0
local cameraFlashUntil = 0
local cameraLastPhoto = nil

local function clamp(v, lo, hi)
    v = tonumber(v) or 0.0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function round1(v)
    return math.floor((tonumber(v) or 0.0) * 10.0 + 0.5) / 10.0
end

local function cameraFov()
    -- 0.5x ultra-wide ~ 88deg, 1x ~ 64deg, 3x ~ 25deg.
    local z = clamp(cameraZoom, 0.5, 3.0)
    local fov = 64.0 / z
    if z <= 0.55 then fov = 88.0 end
    if cameraOrientation == 'portrait' then fov = fov * 0.84 end
    return clamp(fov, 24.0, 88.0)
end

local function shouldUseFlash()
    if cameraFlash == 'on' then return true end
    if cameraFlash == 'off' then return false end
    local hour = GetClockHours()
    return hour >= 19 or hour < 7
end

local function syncCameraHud(active, extra)
    extra = extra or {}
    SendNUIMessage({
        action = 'cameraHud',
        active = active == true,
        mode = cameraMode,
        orientation = cameraOrientation,
        zoom = round1(cameraZoom),
        flash = cameraFlash,
        timer = cameraTimer,
        grid = cameraGrid,
        busy = cameraCaptureBusy,
        lastPhoto = cameraLastPhoto,
        flip = extra.flip == true,
    })
end

local function rotationToDirection(rot)
    local rx = math.rad(rot.x or 0.0)
    local rz = math.rad(rot.z or 0.0)
    local cosx = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * cosx, math.cos(rz) * cosx, math.sin(rx))
end

local function drawCameraFlash()
    if not cameraCam or cameraFlashUntil <= GetGameTimer() then return end
    local pos = GetCamCoord(cameraCam)
    local rot = GetCamRot(cameraCam, 2)
    local dir = rotationToDirection(rot)
    DrawSpotLight(
        pos.x, pos.y, pos.z,
        dir.x, dir.y, dir.z,
        255, 246, 225,
        28.0, 12.0, 1.2, 22.0, 2.0
    )
end

local function updateRearCamera(ped, lookX, lookY)
    -- Front/selfie mode uses PointCamAtCoord. Clear that target before returning
    -- to the rear camera, otherwise the scripted camera can stay locked on the ped.
    if cameraCam and DoesCamExist(cameraCam) then StopCamPointing(cameraCam) end

    local heading = GetEntityHeading(ped)
    heading = heading - (lookX * 4.4)
    SetEntityHeading(ped, heading)

    cameraPitch = clamp(cameraPitch - (lookY * 3.4), -58.0, 52.0)
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.12, 0.38, 0.69)
    SetCamCoord(cameraCam, pos.x, pos.y, pos.z)
    SetCamRot(cameraCam, cameraPitch, 0.0, heading, 2)
end

local function updateFrontCamera(ped, lookX, lookY)
    selfieOrbit = clamp(selfieOrbit - (lookX * 3.0), -32.0, 32.0)
    selfieHeight = clamp(selfieHeight + (lookY * 0.030), -0.28, 0.28)

    local angle = math.rad(selfieOrbit)
    local distance = 1.18 / clamp(cameraZoom, 0.75, 1.8)
    local localX = math.sin(angle) * distance
    local localY = math.cos(angle) * distance
    local pos = GetOffsetFromEntityInWorldCoords(ped, localX, localY, 0.70 + selfieHeight)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.03 + selfieHeight * 0.35)

    SetCamCoord(cameraCam, pos.x, pos.y, pos.z)
    PointCamAtCoord(cameraCam, head.x, head.y, head.z)
end

local function setCameraUiSuppressed(active)
    active = active == true
    if cameraUiSuppressed == active then return end
    cameraUiSuppressed = active

    -- Shared state used by COOKIE HUD and any future UI resources.
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('cookieCameraMode', active, true)
    end

    if active then
        -- Close/lock inventory and hotkeys while the camera owns the controls.
        cameraPrevInvBusy = LocalPlayer.state.invBusy
        cameraPrevInvHotkeys = LocalPlayer.state.invHotkeys

        if GetResourceState('ox_inventory') == 'started' then
            pcall(function() exports.ox_inventory:closeInventory() end)
            pcall(function() exports.ox_inventory:suppressItemNotifications(true) end)
        end

        LocalPlayer.state:set('invBusy', true, false)
        LocalPlayer.state:set('invHotkeys', false, false)

        -- The stock FiveM chat has three visibility states. COOKIE runs the
        -- default SHOW_WHEN_ACTIVE state, so two toggles force ALWAYS_HIDE.
        if GetResourceState('chat') == 'started' then
            ExecuteCommand('toggleChat')
            Wait(30)
            ExecuteCommand('toggleChat')
            cameraChatAdjusted = true
        end
    else
        if LocalPlayer and LocalPlayer.state then
            if cameraPrevInvBusy ~= nil then
                LocalPlayer.state:set('invBusy', cameraPrevInvBusy == true, false)
            else
                LocalPlayer.state:set('invBusy', false, false)
            end

            if cameraPrevInvHotkeys ~= nil then
                LocalPlayer.state:set('invHotkeys', cameraPrevInvHotkeys ~= false, false)
            else
                LocalPlayer.state:set('invHotkeys', true, false)
            end
        end

        if GetResourceState('ox_inventory') == 'started' then
            pcall(function() exports.ox_inventory:suppressItemNotifications(false) end)
        end

        cameraPrevInvBusy = nil
        cameraPrevInvHotkeys = nil

        if cameraChatAdjusted and GetResourceState('chat') == 'started' then
            -- ALWAYS_HIDE -> SHOW_WHEN_ACTIVE (restore COOKIE default)
            ExecuteCommand('toggleChat')
        end
        cameraChatAdjusted = false
    end
end

local function stopPhoneCamera()
    if not phoneCameraActive then return end
    phoneCameraActive = false
    cameraCaptureBusy = false
    cameraFlashUntil = 0
    setCameraUiSuppressed(false)

    SendNUIMessage({ action = 'cameraHud', active = false })
    SendNUIMessage({ action = 'cameraCountdown', value = 0 })

    if cameraCam and DoesCamExist(cameraCam) then
        SetCamActive(cameraCam, false)
        RenderScriptCams(false, true, 220, true, true)
        DestroyCam(cameraCam, false)
    end
    cameraCam = nil

    FreezeEntityPosition(PlayerPedId(), false)
    ClearFocus()
    stopPhoneAnim()
end

local function cycleFlash()
    if cameraFlash == 'auto' then cameraFlash = 'on'
    elseif cameraFlash == 'on' then cameraFlash = 'off'
    else cameraFlash = 'auto' end
    syncCameraHud(true)
end

local function cycleTimer()
    if cameraTimer == 0 then cameraTimer = 3
    elseif cameraTimer == 3 then cameraTimer = 10
    else cameraTimer = 0 end
    syncCameraHud(true)
end

local function toggleOrientation()
    cameraOrientation = cameraOrientation == 'portrait' and 'landscape' or 'portrait'
    if cameraCam and DoesCamExist(cameraCam) then SetCamFov(cameraCam, cameraFov()) end
    syncCameraHud(true)
end

local function toggleCameraMode()
    cameraMode = cameraMode == 'rear' and 'front' or 'rear'
    cameraPitch = 0.0
    selfieOrbit = 0.0
    selfieHeight = 0.0
    if cameraMode == 'front' and cameraZoom < 0.75 then cameraZoom = 1.0 end
    if cameraCam and DoesCamExist(cameraCam) then
        if cameraMode == 'rear' then StopCamPointing(cameraCam) end
        SetCamFov(cameraCam, cameraFov())
    end
    syncCameraHud(true, { flip = true })
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function setZoom(delta)
    local nextZoom = cameraZoom + delta
    if cameraMode == 'front' then
        nextZoom = clamp(nextZoom, 0.75, 2.0)
    else
        nextZoom = clamp(nextZoom, 0.5, 3.0)
    end
    cameraZoom = round1(nextZoom)
    if cameraCam and DoesCamExist(cameraCam) then SetCamFov(cameraCam, cameraFov()) end
    syncCameraHud(true)
end

local function takePhonePhoto()
    if not phoneCameraActive or cameraCaptureBusy then return end
    cameraCaptureBusy = true
    syncCameraHud(true)

    CreateThread(function()
        local timer = tonumber(cameraTimer) or 0
        if timer > 0 then
            for left = timer, 1, -1 do
                if not phoneCameraActive then cameraCaptureBusy = false return end
                SendNUIMessage({ action = 'cameraCountdown', value = left })
                PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                Wait(1000)
            end
            SendNUIMessage({ action = 'cameraCountdown', value = 0 })
        end

        if not phoneCameraActive then cameraCaptureBusy = false return end

        local useFlash = shouldUseFlash()
        if useFlash then
            cameraFlashUntil = GetGameTimer() + 260
        end

        -- Hide the camera HUD briefly so screencapture receives a clean frame.
        SendNUIMessage({ action = 'cameraCaptureClean', active = true })
        Wait(70)

        TriggerServerEvent('cookie_phone:server:capturePhoto', {
            orientation = cameraOrientation,
            cameraMode = cameraMode,
            zoom = round1(cameraZoom),
        })

        PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
        Wait(120)
        SendNUIMessage({ action = 'cameraCaptureClean', active = false })
        SendNUIMessage({ action = 'cameraShutter', flash = useFlash })
    end)
end

local function startPhoneCamera()
    if phoneCameraActive then return end

    if phoneOpen then
        closePhone()
        Wait(260)
    end

    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end

    phoneCameraActive = true
    cameraCaptureBusy = false
    setCameraUiSuppressed(true)
    cameraMode = 'rear'
    cameraOrientation = 'portrait'
    cameraZoom = 1.0
    cameraFlash = 'auto'
    cameraTimer = 0
    cameraGrid = true
    cameraPitch = 0.0
    selfieOrbit = 0.0
    selfieHeight = 0.0

    startPhoneAnim()
    FreezeEntityPosition(ped, true)

    cameraCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(cameraCam, cameraFov())
    SetCamActive(cameraCam, true)
    RenderScriptCams(true, true, 240, true, true)

    syncCameraHud(true)

    CreateThread(function()
        while phoneCameraActive do
            Wait(0)
            ped = PlayerPedId()
            if IsEntityDead(ped) then
                stopPhoneCamera()
                break
            end

            HideHudAndRadarThisFrame()
            for component = 1, 22 do
                HideHudComponentThisFrame(component)
            end
            DisablePlayerFiring(PlayerId(), true)

            -- Camera owns these keys while open.
            for _, control in ipairs({1,2,22,23,24,25,26,37,44,45,47,75,140,141,142,191,199,200,241,242,245}) do
                DisableControlAction(0, control, true)
            end

            local lookX = GetDisabledControlNormal(0, 1)
            local lookY = GetDisabledControlNormal(0, 2)

            if cameraMode == 'front' then
                updateFrontCamera(ped, lookX, lookY)
            else
                updateRearCamera(ped, lookX, lookY)
            end

            if cameraCam and DoesCamExist(cameraCam) then
                SetCamFov(cameraCam, cameraFov())
            end

            drawCameraFlash()

            if IsDisabledControlJustPressed(0, 200) then
                stopPhoneCamera()
                break
            end

            if IsDisabledControlJustPressed(0, 26) then toggleCameraMode() end -- C
            if IsDisabledControlJustPressed(0, 45) then toggleOrientation() end -- R
            if IsDisabledControlJustPressed(0, 23) then cycleFlash() end -- F
            if IsDisabledControlJustPressed(0, 47) then -- G
                cameraGrid = not cameraGrid
                syncCameraHud(true)
            end
            if IsDisabledControlJustPressed(0, 245) then cycleTimer() end -- T
            if IsDisabledControlJustPressed(0, 241) then setZoom(0.1) end
            if IsDisabledControlJustPressed(0, 242) then setZoom(-0.1) end

            if (IsDisabledControlJustPressed(0, 22) or IsDisabledControlJustPressed(0, 191)) and not cameraCaptureBusy then
                takePhonePhoto()
            end
        end
    end)
end

RegisterNetEvent('cookie_phone:client:captureSaved', function(photo)
    cameraCaptureBusy = false
    cameraLastPhoto = photo and photo.image or cameraLastPhoto
    nativeNotify('사진을 갤러리에 저장했습니다.')
    SendNUIMessage({ action = 'galleryPhotoAdded', photo = photo or {} })
    if phoneCameraActive then syncCameraHud(true) end
end)

RegisterNetEvent('cookie_phone:client:captureFailed', function(message)
    cameraCaptureBusy = false
    nativeNotify(message or '사진 저장에 실패했습니다.')
    SendNUIMessage({ action = 'cameraCaptureClean', active = false })
    if phoneCameraActive then syncCameraHud(true) end
end)


RegisterNetEvent('cookie_phone:client:processCapturedPhoto', function(payload)
    payload = type(payload) == 'table' and payload or {}
    if not payload.token or not payload.image then
        cameraCaptureBusy = false
        return
    end
    SendNUIMessage({
        action = 'cameraProcessPhoto',
        token = tostring(payload.token),
        image = tostring(payload.image),
        orientation = payload.orientation == 'portrait' and 'portrait' or 'landscape',
        cameraMode = payload.cameraMode == 'front' and 'front' or 'rear',
        zoom = tonumber(payload.zoom) or 1.0,
    })
end)

RegisterNetEvent('cookie_phone:client:gallery', function(payload)
    local rows = payload and payload.rows or {}
    if type(rows) == 'table' and rows[1] and rows[1].image then
        cameraLastPhoto = rows[1].image
        if phoneCameraActive then syncCameraHud(true) end
    end
    SendNUIMessage({ action = 'galleryData', rows = rows })
end)

openPhone = function()
    if phoneOpen or phoneBusy or IsPauseMenuActive() then return end

    phoneBusy = true
    local ok, owner = cookieUiFocus(true)
    if ok == false then
        phoneBusy = false
        TriggerEvent('cookie_admin:client:notify', ('다른 UI(%s)가 열려 있습니다. 먼저 닫아주세요.'):format(tostring(owner or 'unknown')), true)
        return
    end
    phoneOpen = true
    setPhoneState(true)

    SendNUIMessage({ action = 'open' })
    startPhoneAnim()
    requestPhoneData()
    TriggerServerEvent('cookie_phone:server:requestSettings')
    TriggerServerEvent('cookie_phone:server:bankInfo')
    TriggerServerEvent('cookie_phone:server:requestMessages')
    TriggerServerEvent('cookie_taxi:server:phoneInfo')
    TriggerServerEvent('cookie_mechanic:server:phoneInfo')
    syncCallToNui()

    phoneBusy = false
end

closePhone = function()
    if not phoneOpen or phoneBusy then return end

    phoneBusy = true
    phoneOpen = false
    SendNUIMessage({ action = 'close' })
    cookieUiFocus(false)
    stopPhoneAnim()

    CreateThread(function()
        Wait(220)
        setPhoneState(false)
        phoneBusy = false
    end)
end

local function togglePhone()
    if phoneBusy then return end
    if phoneCameraActive then
        stopPhoneCamera()
        return
    end
    if phoneOpen then closePhone() else openPhone() end
end

local function ensurePhoneOpen()
    if phoneOpen then return end
    openPhone()
end

RegisterCommand('cookie_phone_toggle', function()
    togglePhone()
end, false)

RegisterKeyMapping('cookie_phone_toggle', 'COOKIE 휴대전화 열기/닫기', 'keyboard', 'P')

exports('isOpen', function() return phoneOpen end)
exports('toggle', togglePhone)
exports('open', openPhone)
exports('close', closePhone)

RegisterNetEvent('cookie_phone:client:data', function(data)
    data = data or {}
    myPhone = tostring(data.phone or '')
    SendNUIMessage({
        action = 'phoneData',
        phone = myPhone,
        profile = data.profile or {},
        contacts = data.contacts or {},
        history = data.history or {}
    })
end)

RegisterNetEvent('cookie_phone:client:incoming', function(data)
    currentCall = {
        id = tonumber(data.callId),
        number = tostring(data.number or ''),
        state = 'incoming',
        answeredAt = 0,
    }
    ensurePhoneOpen()
    syncCallToNui()
end)

RegisterNetEvent('cookie_phone:client:outgoing', function(data)
    currentCall = {
        id = tonumber(data.callId),
        number = tostring(data.number or ''),
        state = 'outgoing',
        answeredAt = 0,
    }
    ensurePhoneOpen()
    syncCallToNui()
end)

RegisterNetEvent('cookie_phone:client:connected', function(data)
    currentCall = {
        id = tonumber(data.callId),
        number = tostring(data.number or ''),
        state = 'active',
        answeredAt = tonumber(data.answeredAt) or os.time(),
    }
    ensurePhoneOpen()
    syncCallToNui()
end)

RegisterNetEvent('cookie_phone:client:ended', function(data)
    local old = currentCall
    currentCall = nil
    SendNUIMessage({
        action = 'callEnded',
        reason = data and data.reason or 'ended',
        callId = data and data.callId or (old and old.id),
    })
end)

RegisterNetEvent('cookie_phone:client:failed', function(data)
    SendNUIMessage({
        action = 'callFailed',
        reason = data and data.reason or 'failed',
        number = data and data.number or '',
    })
end)

RegisterNetEvent('cookie_phone:client:error', function(message)
    SendNUIMessage({
        action = 'toast',
        message = tostring(message or '전화 처리 중 오류가 발생했습니다.'),
        isError = true
    })
end)






RegisterNetEvent('cookie_phone:client:bankState', function(data)
    SendNUIMessage({
        action = 'bankState',
        data = data or {}
    })
end)

RegisterNetEvent('cookie_phone:client:bankNearby', function(rows)
    SendNUIMessage({
        action = 'bankNearby',
        rows = rows or {}
    })
end)

RegisterNetEvent('cookie_phone:client:bankNotice', function(data)
    SendNUIMessage({
        action = 'bankNotice',
        message = data and data.message or '',
        isError = data and data.isError == true
    })
end)

RegisterNetEvent('cookie_phone:client:bankIncoming', function(data)
    SendNUIMessage({
        action = 'bankIncoming',
        data = data or {}
    })

    if not phoneOpen then
        local amount = tonumber(data and data.amount) or 0
        local fromPhone = tostring(data and data.fromPhone or '')
        pcall(function()
            lib.notify({
                title = 'COOKIE BANK 입금',
                description = ('%s원 입금 · %s'):format(amount, fromPhone),
                type = 'success',
                duration = 4500,
                position = 'top-right'
            })
        end)
    end
end)

RegisterNetEvent('cookie_phone:client:settings', function(data)
    SendNUIMessage({
        action = 'phoneSettings',
        settings = data or {}
    })
end)

RegisterNetEvent('cookie_phone:client:taxiStatus', function(data)
    SendNUIMessage({ action = 'taxiStatus', data = data or {} })
end)

RegisterNetEvent('cookie_phone:client:mechanicStatus', function(data)
    SendNUIMessage({ action = 'mechanicStatus', data = data or {} })
end)

RegisterNetEvent('cookie_phone:client:messagesState', function(data)
    SendNUIMessage({
        action = 'messagesState',
        conversations = data and data.conversations or {},
        unread = data and data.unread or 0,
    })
end)

RegisterNetEvent('cookie_phone:client:conversation', function(data)
    activeConversationPhone = tostring(data and data.phone or '')
    SendNUIMessage({
        action = 'conversation',
        conversation = data or {}
    })
end)

RegisterNetEvent('cookie_phone:client:newMessage', function(data)
    local fromPhone = tostring(data and data.fromPhone or '')
    SendNUIMessage({
        action = 'newMessage',
        message = data or {}
    })

    -- If phone is closed, show a small non-invasive system notification.
    if not phoneOpen then
        local body = tostring(data and data.body or '')
        if #body > 72 then body = body:sub(1, 72) .. '…' end
        pcall(function()
            lib.notify({
                title = '새 메시지',
                description = body ~= '' and body or ('전화번호 ' .. fromPhone),
                type = 'inform',
                duration = 4500,
                position = 'top-right'
            })
        end)
    end
end)

RegisterNetEvent('cookie_phone:client:messageSent', function(data)
    SendNUIMessage({
        action = 'messageSent',
        message = data or {}
    })
end)

RegisterNetEvent('cookie_phone:client:messagesRead', function(data)
    SendNUIMessage({
        action = 'messagesRead',
        phone = data and data.phone or ''
    })
end)

RegisterNetEvent('cookie_phone:client:toast', function(message, isError)
    SendNUIMessage({
        action = 'toast',
        message = tostring(message or ''),
        isError = isError == true
    })
end)

RegisterNetEvent('cookie_phone:client:nearby', function(rows)
    SendNUIMessage({
        action = 'nearbyContacts',
        rows = rows or {}
    })
end)

RegisterNetEvent('cookie_phone:client:contactOffer', function(data)
    ensurePhoneOpen()
    SendNUIMessage({
        action = 'contactOffer',
        offer = data or {}
    })
end)

local function dispatchCallLabel(id)
    return ('CALL #%04d'):format(tonumber(id) or 0)
end

local function dispatchNotify(title, message, kind)
    SendNUIMessage({ action = 'dispatchNotice', data = { title = title, message = message, type = kind or 'info' } })
end

local function clearDispatchGps()
    if dispatchGpsBlip and DoesBlipExist(dispatchGpsBlip) then
        SetBlipRoute(dispatchGpsBlip, false)
        RemoveBlip(dispatchGpsBlip)
    end
    dispatchGpsBlip = nil
    dispatchGpsCallId = nil
end

local function setDispatchGps(call)
    if type(call) ~= 'table' or not call.x or not call.y then return end
    clearDispatchGps()
    dispatchGpsCallId = tonumber(call.id)
    dispatchGpsBlip = AddBlipForCoord(tonumber(call.x)+0.0, tonumber(call.y)+0.0, tonumber(call.z or 0)+0.0)
    SetBlipSprite(dispatchGpsBlip, 280)
    SetBlipColour(dispatchGpsBlip, 1)
    SetBlipScale(dispatchGpsBlip, 0.86)
    SetBlipAsShortRange(dispatchGpsBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('%s 신고 위치'):format(dispatchCallLabel(call.id)))
    EndTextCommandSetBlipName(dispatchGpsBlip)
    SetBlipRoute(dispatchGpsBlip, true)
    SetBlipRouteColour(dispatchGpsBlip, 1)
    SetNewWaypoint(tonumber(call.x)+0.0, tonumber(call.y)+0.0)
end

local function pendingDispatchCount()
    local n = 0
    for _ in pairs(dispatchPending) do n = n + 1 end
    return n
end

local function newestPendingDispatch()
    local best
    for _, call in pairs(dispatchPending) do
        if not best or (tonumber(call.id) or 0) > (tonumber(best.id) or 0) then best = call end
    end
    return best
end

local function acceptNewestDispatch()
    if localAfk then return end
    local call = newestPendingDispatch()
    if not call then return end
    TriggerServerEvent('cookie_phone:server:dispatchAccept', tonumber(call.id))
end

RegisterNetEvent('cookie_phone:client:dispatchIncoming', function(call)
    if type(call) ~= 'table' or not call.id or localAfk then return end
    local myPos = GetEntityCoords(PlayerPedId())
    if call.x and call.y then
        call.distance = #(myPos - vector3(tonumber(call.x)+0.0, tonumber(call.y)+0.0, tonumber(call.z or myPos.z)+0.0)) / 1000.0
    end
    dispatchPending[tonumber(call.id)] = call
    SendNUIMessage({ action = 'dispatchIncoming', data = call })
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end)

RegisterNetEvent('cookie_phone:client:dispatchRemove', function(callId)
    callId = tonumber(callId)
    if callId then dispatchPending[callId] = nil end
    SendNUIMessage({ action = 'dispatchRemove', id = callId })
end)

RegisterNetEvent('cookie_phone:client:dispatchClearIncoming', function()
    dispatchPending = {}
    SendNUIMessage({ action = 'dispatchClearIncoming' })
end)

RegisterNetEvent('cookie_phone:client:dispatchNotice', function(data)
    data = type(data) == 'table' and data or {}
    dispatchNotify(tostring(data.title or '긴급연락'), tostring(data.message or ''), tostring(data.type or 'info'))
    if data.sound ~= false then PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
    if phoneOpen then TriggerServerEvent('cookie_phone:server:dispatchOverviewPush') end
end)

RegisterNetEvent('cookie_phone:client:dispatchAcceptedSelf', function(call)
    if type(call) ~= 'table' then return end
    dispatchPending[tonumber(call.id)] = nil
    SendNUIMessage({ action = 'dispatchRemove', id = call.id })
    setDispatchGps(call)
    dispatchNotify(dispatchCallLabel(call.id), ('%s 콜을 접수했습니다. GPS가 등록되었습니다.'):format(call.callerName or '신고자'), 'success')
    if phoneOpen then TriggerServerEvent('cookie_phone:server:dispatchOverviewPush') end
end)

RegisterNetEvent('cookie_phone:client:dispatchGps', function(call)
    if type(call) ~= 'table' then return end
    setDispatchGps(call)
    dispatchNotify(dispatchCallLabel(call.id), '신고 위치를 GPS에 등록했습니다.', 'success')
end)

RegisterNetEvent('cookie_phone:client:dispatchGpsClear', function()
    clearDispatchGps()
    dispatchNotify('긴급연락', '콜 GPS를 해제했습니다.', 'info')
end)

RegisterNetEvent('cookie_phone:client:dispatchOverview', function(data)
    SendNUIMessage({ action = 'dispatchOverview', data = data or {} })
end)

RegisterNUICallback('phoneDispatchOverview', function(_, cb)
    local r = lib.callback.await('cookie_phone:dispatchOverview', false)
    cb(r or { ok = false, targets = {}, ownCalls = {}, assignedCalls = {} })
end)

RegisterNUICallback('phoneDispatchCreate', function(data, cb)
    local r = lib.callback.await('cookie_phone:dispatchCreate', false, data or {})
    cb(r or { ok = false, reason = '서버 응답 없음' })
end)

RegisterNUICallback('phoneDispatchCancel', function(data, cb)
    local r = lib.callback.await('cookie_phone:dispatchCancel', false, tonumber(data and data.id))
    cb(r or { ok = false, reason = '서버 응답 없음' })
end)

RegisterNUICallback('phoneDispatchClose', function(data, cb)
    local r = lib.callback.await('cookie_phone:dispatchClose', false, tonumber(data and data.id), tostring(data and data.reason or ''))
    cb(r or { ok = false, reason = '서버 응답 없음' })
end)

RegisterNUICallback('phoneDispatchGps', function(data, cb)
    local r = lib.callback.await('cookie_phone:dispatchGetCall', false, tonumber(data and data.id))
    if r and r.ok and r.call then setDispatchGps(r.call) end
    cb(r or { ok = false, reason = '서버 응답 없음' })
end)

RegisterNUICallback('phoneDispatchGpsClear', function(_, cb)
    clearDispatchGps()
    cb({ ok = true })
end)

RegisterCommand('cookie_dispatch_accept', function()
    acceptNewestDispatch()
end, false)
RegisterKeyMapping('cookie_dispatch_accept', 'COOKIE 콜 접수', 'keyboard', 'ADD')

RegisterCommand('cookie_dispatch_clear_gps', function()
    clearDispatchGps()
end, false)
RegisterKeyMapping('cookie_dispatch_clear_gps', 'COOKIE 콜 GPS 해제', 'keyboard', 'SUBTRACT')

CreateThread(function()
    while true do
        if next(dispatchPending) and not localAfk then
            Wait(0)
            if not phoneOpen and IsControlJustPressed(0, 241) then
                acceptNewestDispatch()
                Wait(350)
            end
        else
            Wait(250)
        end
    end
end)

-- V13.9.0: 잠수 판정/이동은 cookie_afkzone이 전담한다.
-- 휴대전화 긴급콜 시스템은 cookieAfk 상태만 구독하여 잠수 중 콜을 받지 않는다.
local function applyDispatchAfkState(value, initial)
    local nextAfk = value == true
    if localAfk == nextAfk and not initial then return end
    localAfk = nextAfk

    if localAfk then
        dispatchPending = {}
        SendNUIMessage({ action = 'dispatchClearIncoming' })
        if not initial then
            dispatchNotify('잠수 상태', '잠수존에 입장하여 긴급콜 수신이 일시 중지됩니다.', 'info')
        end
    else
        if not initial then
            dispatchNotify('잠수 해제', '잠수존에서 나와 온라인 상태로 복귀했습니다.', 'success')
        end
        TriggerServerEvent('cookie_phone:server:dispatchSyncPending')
    end
end

AddStateBagChangeHandler('cookieAfk', nil, function(bagName, _, value)
    local mine = ('player:%s'):format(GetPlayerServerId(PlayerId()))
    if bagName ~= mine then return end
    applyDispatchAfkState(value, false)
end)

CreateThread(function()
    Wait(2500)
    applyDispatchAfkState(LocalPlayer.state.cookieAfk == true, true)
end)

local COOKIE_PHONE_MAP_LOCATIONS = {
    { id='main_square', label='메인 광장', category='주요 시설', x=190.00, y=-932.09 },
    { id='main_garage', label='메인 차고', category='차량', x=255.23, y=-788.39 },
    { id='city_hall', label='시청', category='주요 시설', x=-2237.32, y=249.76 },
    { id='police', label='경찰청', category='공공기관', x=-339.42, y=-253.27 },
    { id='security', label='보안국', category='공공기관', x=302.41, y=6632.19 },
    { id='hospital', label='필박스 병원', category='공공기관', x=298.0, y=-584.0 },
    { id='repair_shop', label='정비소', category='시민 서비스', x=-350.7, y=-136.5 },
    { id='delivery', label='배달기사', category='시민직', x=-50.84, y=-1763.95 },
    { id='construction', label='건설 인부', category='시민직', x=125.27, y=-396.01 },
    { id='taxi', label='택시 기사', category='시민직', x=599.51, y=89.73 },
    { id='trucker', label='트럭 기사', category='시민직', x=915.28, y=-3235.59 },
    { id='bank', label='은행', category='금융', x=255.206, y=225.303 },
    { id='prison', label='볼링브로크 교도소', category='공공기관', x=1847.12, y=2586.05 },
}

RegisterNUICallback('phoneMapList', function(_, cb)
    cb({ ok=true, rows=COOKIE_PHONE_MAP_LOCATIONS })
end)

RegisterNUICallback('phoneMapWaypoint', function(data, cb)
    local id=tostring(data and data.id or '')
    for _,p in ipairs(COOKIE_PHONE_MAP_LOCATIONS) do
        if p.id==id then
            SetNewWaypoint(p.x+0.0,p.y+0.0)
            cb({ok=true,label=p.label})
            return
        end
    end
    cb({ok=false,error='not_found'})
end)

-- Phone map app -> real GTA/ESC map.
-- Keep this identical to cookie_esc's map launcher so both paths behave the same.
RegisterNUICallback('phoneOpenGtaMap', function(_, cb)
    cb({ ok = true })
    closePhone()

    CreateThread(function()
        -- Let NUI focus and the phone animation release before opening the frontend.
        Wait(220)
        ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_SP_PAUSE'), false, 44)
    end)
end)

RegisterNUICallback('phoneClose', function(_, cb)
    cb({ ok = true })
    closePhone()
end)

RegisterNUICallback('phoneRefresh', function(_, cb)
    cb({ ok = true })
    requestPhoneData()
    TriggerServerEvent('cookie_phone:server:requestMessages')
end)

RegisterNUICallback('phoneCameraOpen', function(_, cb)
    startPhoneCamera()
    cb({ ok = true })
end)


RegisterNUICallback('phoneCameraProcessed', function(data, cb)
    cb({ ok = true })
    data = type(data) == 'table' and data or {}
    if not data.token or not data.image then
        cameraCaptureBusy = false
        return
    end
    TriggerLatentServerEvent('cookie_phone:server:saveProcessedPhoto', 1048576, {
        token = tostring(data.token),
        image = tostring(data.image),
    })
end)

RegisterNUICallback('phoneGalleryRefresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:requestGallery')
end)

RegisterNUICallback('phoneGalleryDelete', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:deleteGalleryPhoto', data and data.id)
end)

RegisterNUICallback('phoneSaveMessagePhoto', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:saveMessagePhoto', data and data.messageId)
end)






RegisterNUICallback('phoneBankInfo', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:bankInfo')
end)

RegisterNUICallback('phoneBankNearby', function(_, cb)
    local me = PlayerPedId()
    local myCoords = GetEntityCoords(me)
    local candidates = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 then
                local distance = #(myCoords - GetEntityCoords(ped))
                if distance <= 5.0 then
                    candidates[#candidates + 1] = {
                        serverId = GetPlayerServerId(player),
                        distance = distance,
                    }
                end
            end
        end
    end

    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:bankNearby', candidates)
end)

RegisterNUICallback('phoneBankTransfer', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:bankTransfer', data or {})
end)

RegisterNUICallback('phoneSettingsRefresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:requestSettings')
end)

RegisterNUICallback('phoneSettingsSave', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:saveSettings', data or {})
end)

RegisterNUICallback('phoneSettingsReset', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:resetSettings')
end)

RegisterNUICallback('phoneTaxiPreview', function(_, cb)
    local data = taxiLocationData()
    cb({ ok = true, data = data })
end)

RegisterNUICallback('phoneTaxiInfo', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:phoneInfo')
end)

RegisterNUICallback('phoneTaxiRequest', function(_, cb)
    local data = taxiLocationData()
    if not data.dest then
        cb({ ok = false, error = 'waypoint' })
        return
    end
    cb({ ok = true, data = data })
    TriggerServerEvent('cookie_taxi:server:phoneRequest', data)
end)

RegisterNUICallback('phoneTaxiCancel', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_taxi:server:phoneCancel')
end)

RegisterNUICallback('phoneMechanicScan', function(_, cb)
    cb({ ok = true, vehicle = findRepairVehicle() })
end)

RegisterNUICallback('phoneMechanicInfo', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_mechanic:server:phoneInfo')
end)

RegisterNUICallback('phoneMechanicRequest', function(_, cb)
    local vehicle = findRepairVehicle()
    if not vehicle then
        cb({ ok = false, error = 'vehicle' })
        return
    end
    cb({ ok = true, vehicle = vehicle })
    TriggerServerEvent('cookie_mechanic:server:playerRequest', {
        netId = vehicle.netId,
        coord = vehicle.coord,
        label = ('%s 긴급 정비 · %s'):format(vehicle.label or '시민 차량', vehicle.plate or '')
    })
end)

RegisterNUICallback('phoneMechanicCancel', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_mechanic:server:cancelPlayerRequest')
end)

RegisterNUICallback('phoneMessagesRefresh', function(_, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:requestMessages')
end)

RegisterNUICallback('phoneOpenConversation', function(data, cb)
    cb({ ok = true })
    local phone = data and data.phone or ''
    activeConversationPhone = tostring(phone or '')
    TriggerServerEvent('cookie_phone:server:openConversation', phone)
end)

RegisterNUICallback('phoneSendMessage', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:sendMessage', data or {})
end)

RegisterNUICallback('phoneMarkRead', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:markConversationRead', data and data.phone)
end)

RegisterNUICallback('phoneDeleteConversation', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:deleteConversation', data and data.phone)
end)

RegisterNUICallback('phoneSaveProfile', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:saveProfile', data or {})
end)

RegisterNUICallback('phoneSaveContact', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:saveContact', data or {})
end)

RegisterNUICallback('phoneDeleteContact', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:deleteContact', data and data.id)
end)

RegisterNUICallback('phoneFavoriteContact', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:setFavorite', data and data.id, data and data.favorite == true)
end)

RegisterNUICallback('phoneBlockContact', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:setBlocked', data and data.id, data and data.blocked == true)
end)

RegisterNUICallback('phoneNearby', function(_, cb)
    local me = PlayerPedId()
    local myCoords = GetEntityCoords(me)
    local candidates = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local ped = GetPlayerPed(player)
            if ped and ped ~= 0 then
                local distance = #(myCoords - GetEntityCoords(ped))
                if distance <= 5.0 then
                    candidates[#candidates + 1] = {
                        serverId = GetPlayerServerId(player),
                        distance = distance,
                    }
                end
            end
        end
    end

    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:requestNearby', candidates)
end)

RegisterNUICallback('phoneShareContact', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:shareContact', data and data.serverId)
end)

RegisterNUICallback('phoneAcceptShare', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:acceptShare', data and data.shareId)
end)

RegisterNUICallback('phoneDeclineShare', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:declineShare', data and data.shareId)
end)

RegisterNUICallback('phoneDial', function(data, cb)
    cb({ ok = true })
    TriggerServerEvent('cookie_phone:server:dial', data and data.number or '')
end)

RegisterNUICallback('phoneAccept', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.callId) or (currentCall and currentCall.id)
    if id then TriggerServerEvent('cookie_phone:server:accept', id) end
end)

RegisterNUICallback('phoneDecline', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.callId) or (currentCall and currentCall.id)
    if id then TriggerServerEvent('cookie_phone:server:decline', id) end
end)

RegisterNUICallback('phoneCancel', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.callId) or (currentCall and currentCall.id)
    if id then TriggerServerEvent('cookie_phone:server:cancel', id) end
end)

RegisterNUICallback('phoneHangup', function(data, cb)
    cb({ ok = true })
    local id = tonumber(data and data.callId) or (currentCall and currentCall.id)
    if id then TriggerServerEvent('cookie_phone:server:hangup', id) end
end)

-- P belongs to COOKIE phone, not GTA pause.
CreateThread(function()
    while true do
        Wait(0)
        DisableControlAction(0, 199, true)
        DisableControlAction(2, 199, true)

        if phoneOpen then
            -- Prevent accidental combat while clicking the phone.
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)

            if IsEntityDead(PlayerPedId()) then
                closePhone()
            end
        end
    end
end)

CreateThread(function()
    Wait(1300)
    setPhoneState(false)
    TriggerEvent('cookie_chat:escMode', false)
    TriggerEvent('cookie_hud:client:hudVisible', true)
    requestPhoneData()
    applyDispatchAfkState(LocalPlayer.state.cookieAfk == true, true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    setPhoneState(false)
    cookieUiFocus(false)
    stopPhoneAnim()
end)


-- COOKIE PHONE recovery diagnostic.
RegisterCommand('cookie_phone_keycheck', function()
    print('[cookie_phone] P binding command exists: cookie_phone_toggle')
    TriggerEvent('cookie_phone:client:toast', 'COOKIE PHONE P 키 바인딩이 로드되어 있습니다.', false)
end, false)


-- COOKIE PRO CAMERA CLEANUP
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if phoneCameraActive then stopPhoneCamera() else setCameraUiSuppressed(false) end
end)
print('^2[COOKIE PHONE]^7 MESSAGE PHOTO SAVE CLIENT V13.9.0 ready')
