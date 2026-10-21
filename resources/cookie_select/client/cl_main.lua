local focusGuardUntil = 0

local function CookieSharedNuiFocus(hasFocus, hasCursor)
    hasFocus = hasFocus == true
    hasCursor = hasCursor == true

    if GetResourceState('cookie_core') == 'started' then
        if hasFocus then
            local ok, owner = exports.cookie_core:Acquire(GetCurrentResourceName(), false)

            -- 접속/온보딩 화면은 로그인 전에 반드시 마우스 포커스를 가져야 한다.
            -- 다른 UI가 시작 과정에서 포커스를 잘못 잡고 있으면 1회 정리 후 재획득한다.
            if not ok and not LocalPlayer.state.isLoggedIn then
                exports.cookie_core:ForceRelease()
                ok = exports.cookie_core:Acquire(GetCurrentResourceName(), false)
            end

            if ok then
                -- shared focus manager 상태와 실제 CEF cursor 상태가 엇갈리는 경우를 방지한다.
                SetNuiFocus(true, hasCursor)
                if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
                focusGuardUntil = 0
            else
                print(('^1[cookie_select]^7 NUI focus acquire failed (owner=%s)'):format(tostring(owner)))
            end
            return ok
        end

        focusGuardUntil = 0
        local ok = exports.cookie_core:Release(GetCurrentResourceName())
        SetNuiFocus(false, false)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        return ok
    end

    SetNuiFocus(hasFocus, hasCursor)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    focusGuardUntil = 0
    return true
end



local STAGE_PED  = vector4(-1500.0, -3000.0, -180.0, 180.0)
local STAGE_BODY = 0.55
local STAGE_CAM  = {
    forward = 3.2,
    up      = 1.35,
    right   = 0.6,
    aim     = 0.40,
    fov     = 40.0,

}

local STAGE_LIGHT = { forward = 1.2, up = 1.5, range = 4.0, front = 2.8, back = 2.0 }

local DEFAULT_SPAWN = vec4(-2253.56, 236.17, 174.61, 359.82)
local MODEL_TIMEOUT = 30000

-- 최초 접속 미리보기에서도 스토리 캐릭터(마이클 등)를 절대 사용하지 않는다.
-- 실제 GTA Online/illenium-appearance에서 의상·얼굴·헤어 편집이 가능한 Freemode Ped를 사용한다.
local DEFAULT_PREVIEW_MODEL = `mp_m_freemode_01`
local FEMALE_PREVIEW_MODEL = `mp_f_freemode_01`
local STORY_PED_MODELS = {
    [`player_zero`] = true, -- Michael
    [`player_one`] = true,  -- Franklin
    [`player_two`] = true,  -- Trevor
}

local legacyStoryPedDetected = false
local legacyStoryModelName = nil
local legacyRepairRunning = false

local function modelHash(value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' and value ~= '' then return joaat(value) end
    return 0
end

local function isStoryPedModel(value)
    local hash = modelHash(value)
    return hash ~= 0 and STORY_PED_MODELS[hash] == true
end

local function storyModelLabel(value)
    local hash = modelHash(value)
    if hash == joaat('player_zero') then return '마이클' end
    if hash == joaat('player_one') then return '프랭클린' end
    if hash == joaat('player_two') then return '트레버' end
    return '스토리 캐릭터'
end

local function setFreemodeModel(model)
    local hash = modelHash(model)
    if hash == 0 then hash = DEFAULT_PREVIEW_MODEL end

    local ok = pcall(function()
        lib.requestModel(hash, MODEL_TIMEOUT)
        SetPlayerModel(PlayerId(), hash)
        SetModelAsNoLongerNeeded(hash)
        local ped = PlayerPedId()
        SetPedDefaultComponentVariation(ped)
        for _,prop in ipairs({0,1,2,6,7}) do ClearPedProp(ped, prop) end
    end)

    if not ok then
        print('^1[cookie_select]^7 failed to switch to freemode model')
        return false
    end
    return true
end

local function ensureFreemodePreviewPed()
    local ped = PlayerPedId()
    local currentModel = GetEntityModel(ped)

    -- 이미 Freemode 모델이면 그대로 사용한다.
    if currentModel == DEFAULT_PREVIEW_MODEL or currentModel == FEMALE_PREVIEW_MODEL then
        return true
    end

    local ok = pcall(function()
        lib.requestModel(DEFAULT_PREVIEW_MODEL, MODEL_TIMEOUT)
        SetPlayerModel(PlayerId(), DEFAULT_PREVIEW_MODEL)
        SetModelAsNoLongerNeeded(DEFAULT_PREVIEW_MODEL)

        local newPed = PlayerPedId()
        SetPedDefaultComponentVariation(newPed)
        ClearPedProp(newPed, 0)
        ClearPedProp(newPed, 1)
        ClearPedProp(newPed, 2)
        ClearPedProp(newPed, 6)
        ClearPedProp(newPed, 7)
    end)

    if not ok then
        print('^1[cookie_select]^7 Freemode preview model load failed')
        return false
    end

    print('^2[cookie_select]^7 Freemode preview ped active')
    return true
end

local flowActive = false

-- V8: do not repeatedly reset NUI focus; repeated resets can swallow CEF clicks.
local previewCam
local currentCharacter
local onboardingJustCompleted = false
local stageZ = STAGE_PED.z
local stageBlackout = false
local voidStageActive = false

local function ckLog(tag, msg)
    if GetConvar('cookie:introDebug', 'true') ~= 'true' then return end

end

local function blockEscapeThread()
    CreateThread(function()
        while flowActive do
            HideHudAndRadarThisFrame()

            if stageBlackout then NetworkOverrideClockTime(0, 0, 0) end
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 177, true)
            Wait(0)
        end
    end)
end

local function reportStage(stage)
    TriggerServerEvent('cookie_select:stage', stage)

end

local function showScreen(screen, extra)
    local msg = extra or {}
    msg.action = 'show'
    msg.screen = screen
    CookieSharedNuiFocus(true, true)
    SendNUIMessage(msg)

    reportStage(screen)
end

local function placePedOnStage()
    SetEntityCoords(cache.ped, STAGE_PED.x, STAGE_PED.y, stageZ, false, false, false, false)
    SetEntityHeading(cache.ped, STAGE_PED.w)
    FreezeEntityPosition(cache.ped, true)
end

local function setupPreviewCam()
    -- 최초 접속부터 항상 캐릭터가 보이도록 미리보기 카메라를 유지한다.
    -- 기존 카메라가 있으면 안전하게 교체해 중복 카메라가 쌓이지 않게 한다.
    if previewCam and DoesCamExist(previewCam) then
        SetCamActive(previewCam, false)
        DestroyCam(previewCam, true)
        previewCam = nil
    end

    placePedOnStage()

    local h = math.rad(STAGE_PED.w)
    local fx, fy = -math.sin(h), math.cos(h)
    local bodyZ  = stageZ + STAGE_BODY
    local chestZ = bodyZ + STAGE_CAM.aim

    local camX = STAGE_PED.x + fx * STAGE_CAM.forward
    local camY = STAGE_PED.y + fy * STAGE_CAM.forward
    local camZ = bodyZ + STAGE_CAM.up

    local dx, dy, dz = STAGE_PED.x - camX, STAGE_PED.y - camY, chestZ - camZ
    local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy = dx / dl, dy / dl
    local rgx, rgy = dy, -dx
    local rl = math.sqrt(rgx * rgx + rgy * rgy)
    rgx, rgy = rgx / rl, rgy / rl

    local aimX = STAGE_PED.x + rgx * STAGE_CAM.right
    local aimY = STAGE_PED.y + rgy * STAGE_CAM.right
    local aimZ = chestZ

    previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
        camX, camY, camZ, 0.0, 0.0, 0.0, STAGE_CAM.fov, false, 0)
    PointCamAtCoord(previewCam, aimX, aimY, aimZ)
    SetCamActive(previewCam, true)
    SetCamUseShallowDofMode(previewCam, true)
    SetCamNearDof(previewCam, 0.6)
    SetCamFarDof(previewCam, 3.0)
    SetCamDofStrength(previewCam, 0.6)
    RenderScriptCams(true, false, 1, true, true)

end

local function destroyPreviewCam()
    if not previewCam then return end
    SetCamActive(previewCam, false)
    DestroyCam(previewCam, true)
    RenderScriptCams(false, false, 1, true, true)
    DisplayRadar(true)
    previewCam = nil
end

local function applyPreviewPed(citizenId)
    local clothing, model = lib.callback.await('qbx_core:server:getPreviewPedData', false, citizenId)

    -- 예전에 player_zero / player_one / player_two가 저장된 유저는
    -- 해당 스토리 Ped를 다시 로드하지 않고 복구 대상으로 표시한다.
    if model and isStoryPedModel(model) then
        legacyStoryPedDetected = true
        legacyStoryModelName = storyModelLabel(model)
        print(('^3[cookie_select]^7 legacy story ped detected: %s'):format(legacyStoryModelName))
        setFreemodeModel(DEFAULT_PREVIEW_MODEL)
        return
    end

    legacyStoryPedDetected = false
    legacyStoryModelName = nil

    if model and clothing then
        lib.requestModel(model, MODEL_TIMEOUT)
        SetPlayerModel(cache.playerId, model)
        pcall(function()
            exports['illenium-appearance']:setPedAppearance(PlayerPedId(), json.decode(clothing))
        end)
        SetModelAsNoLongerNeeded(model)
    end
end

local function setupVoidStage(ped)
    SetFollowPedCamViewMode(2)
    DisplayRadar(false)

    while not IsScreenFadedOut() and cache.ped ~= PlayerPedId() do Wait(0) end

    placePedOnStage()

    local sc = GetEntityCoords(cache.ped)
    local staged = #(sc - vec3(STAGE_PED.x, STAGE_PED.y, STAGE_PED.z)) < 5.0

    if staged then
        NetworkStartSoloTutorialSession()
        while not NetworkIsInTutorialSession() do Wait(0) end

        NetworkOverrideClockTime(0, 0, 0)
        SetArtificialLightsState(true)
        stageBlackout = true
        voidStageActive = true

        CreateThread(function()
            local h = math.rad(STAGE_PED.w)
            local fx, fy = -math.sin(h), math.cos(h)
            local lz = stageZ + STAGE_LIGHT.up
            while voidStageActive do
                if stageBlackout then NetworkOverrideClockTime(0, 0, 0) end
                SetUseHiDof()
                DrawLightWithRange(STAGE_PED.x + fx * STAGE_LIGHT.forward, STAGE_PED.y + fy * STAGE_LIGHT.forward, lz,
                    255, 244, 214, STAGE_LIGHT.range, STAGE_LIGHT.front)
                DrawLightWithRange(STAGE_PED.x - fx * STAGE_LIGHT.forward, STAGE_PED.y - fy * STAGE_LIGHT.forward, lz,
                    255, 244, 214, STAGE_LIGHT.range, STAGE_LIGHT.back)
                Wait(0)
            end
        end)
    else

    end

    Wait(200)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    return staged
end

local function teardownVoidStage()
    voidStageActive = false
    if stageBlackout then
        SetArtificialLightsState(false)
        NetworkClearClockTimeOverride()
        stageBlackout = false
    end
    FreezeEntityPosition(cache.ped, false)
    NetworkEndTutorialSession()
end

local function spawnFlow(isNew, coords)

    if not isNew and coords then
        local d = #(vec3(coords.x, coords.y, coords.z) - vec3(STAGE_PED.x, STAGE_PED.y, STAGE_PED.z))
        if d < 50.0 then

            coords = DEFAULT_SPAWN
        end
    end

    CookieSharedNuiFocus(false, false)
    flowActive = false
    SendNUIMessage({ action = 'hide' })

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    destroyPreviewCam()

    teardownVoidStage()

    -- 신규 유저는 최초 접속에서 외형 편집기를 열지 않는다.
    -- 동물/바닐라 ped 선택을 막기 위해 기본 freemode 인간 모델로 바로 스폰시킨다.
    local spawnData = {
        x = coords.x, y = coords.y, z = coords.z, heading = coords.w
    }
    if isNew then
        spawnData.model = DEFAULT_PREVIEW_MODEL
    end

    pcall(function()
        exports.spawnmanager:spawnPlayer(spawnData)
    end)

    -- 신규 캐릭터는 Freemode 모델을 유지하고 기본 의상 슬롯을 정상화한다.
    -- 이후 시청 옷장/illenium-appearance에서 옷·얼굴·헤어를 자유롭게 변경 가능하다.
    if isNew then
        CreateThread(function()
            Wait(250)
            local ped = PlayerPedId()
            if GetEntityModel(ped) ~= DEFAULT_PREVIEW_MODEL then
                ensureFreemodePreviewPed()
                ped = PlayerPedId()
            end
            SetPedDefaultComponentVariation(ped)
        end)
    end

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
    TriggerServerEvent('qb-houses:server:SetInsideMeta', 0, false)
    TriggerServerEvent('qb-apartments:server:SetInsideMeta', 0, 0, false)

    DoScreenFadeIn(800)

    -- 최초 접속 외형 꾸미기(qb-clothes / illenium-appearance)는 실행하지 않는다.
    -- 외형 변경은 뉴비 시청 옷장에서만 진행한다.
    reportStage('spawn')

    -- COOKIE SCREENFIX V1: spawn confirmed; no effect on welcome/character selection.
    CreateThread(function()
        Wait(2000)
        local screenBlack = IsScreenFadedOut() or IsScreenFadingOut()
        local previewLeft = previewCam and DoesCamExist(previewCam) or false
        print(('[cookie_select][screenfix] postspawn before: fade=%s preview=%s flowActive=%s'):format(
            tostring(screenBlack), tostring(previewLeft), tostring(flowActive)))
        -- Hide only the cookie_select NUI owned by this resource.
        SendNUIMessage({ action = 'hide' })
        pcall(function() CookieSharedNuiFocus(false, false) end)
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
        if previewLeft then
            destroyPreviewCam()
        end
        if screenBlack or previewLeft then
            RenderScriptCams(false, false, 0, true, true)
            ClearFocus()
            DoScreenFadeIn(700)
        end
        Wait(800)
        print(('[cookie_select][screenfix] postspawn after: fadedOut=%s preview=%s'):format(
            tostring(IsScreenFadedOut()), tostring(previewCam and DoesCamExist(previewCam) or false)))
    end)
end

local function proceedToSelection()
    local characters = lib.callback.await('qbx_core:server:getCharacters')
    local count = characters and #characters or 0

    if count == 0 then
        -- 신규 유저는 별명만 정하면 내부 Qbox 캐릭터를 자동 생성한다.
        -- 실명/생년월일 입력 화면은 더 이상 최초 접속에서 노출하지 않는다.
        local nick = lib.callback.await('cookie_select:getMyNickname', false) or '플레이어'
        local newData = lib.callback.await('qbx_core:server:createCharacter', false, {
            firstname = nick,
            lastname = 'COOKIE',
            nationality = 'COOKIE',
            gender = 0,
            birthdate = '2000-01-01',
            cid = 1,
        })
        if not newData then
            lib.notify({ title='COOKIE', description='캐릭터 자동 생성에 실패했습니다. 다시 접속해주세요.', type='error' })
            return
        end
        spawnFlow(true, DEFAULT_SPAWN)
        return
    end

    currentCharacter = characters[1]
    applyPreviewPed(currentCharacter.citizenid)
    setupPreviewCam()
    DoScreenFadeIn(1000)

    local nick = lib.callback.await('cookie_select:getMyNickname', false) or '플레이어'
    showScreen('entry', { nick = nick })
end

local function afterVerify()
    local onboarded = lib.callback.await('cookie_select:isOnboarded', false)
    if onboarded then

        proceedToSelection()
    else

        showScreen('consent')
    end
end

local function gateVerify()
    local needs = lib.callback.await('cookie_select:needsVerify', false)
    if not needs then
        afterVerify()
        return
    end
    local info = lib.callback.await('cookie_select:verifyInfo', false)

    showScreen('verify', { info = info or { ok = false } })
end

local function startFlow()
    if flowActive then return end

    if LocalPlayer.state.isLoggedIn then

        return
    end
    flowActive = true

    DoScreenFadeOut(0)
    blockEscapeThread()

    -- FiveM 최초 접속 기본 페드가 player_zero(마이클)인 경우가 있어서
    -- 스테이지에 올리기 전에 반드시 커스터마이징 가능한 Freemode Ped로 교체한다.
    ensureFreemodePreviewPed()
    Wait(50)
    setupVoidStage(PlayerPedId())

    -- 기존에는 온보딩이 끝난 뒤에만 미리보기 카메라를 켜서
    -- 최초 접속의 이용 동의/별명 화면에서는 캐릭터 스테이지가 보이지 않았다.
    -- 이제 접속 플로우 시작 즉시 스테이지 + 캐릭터를 보여준다.
    setupPreviewCam()
    Wait(100)
    DoScreenFadeIn(500)

    -- 최초 진입 시 예전처럼 환영/접속 시작 화면을 먼저 보여준다.
    -- 시작하기를 누른 뒤 기존 유저는 캐릭터 입장 화면으로,
    -- 신규 유저는 이용 동의 -> 별명 설정으로 이어진다.
    showScreen('welcome')
end

RegisterNUICallback('welcomeDone', function(_, cb)
    cb({ ok = true })
    -- 현재 쿠키서버의 간소화된 온보딩 흐름은 유지한다.
    -- 예전 Discord 인증 단계까지 되돌리지는 않는다.
    afterVerify()
end)

RegisterNUICallback('verifyRedeem', function(data, cb)
    local r = lib.callback.await('cookie_select:verifyRedeem', false, (data and data.code) or '')
    cb(r or { ok = false, reason = '서버 응답이 없습니다' })
end)

RegisterNUICallback('verifyDone', function(_, cb)
    cb({ ok = true })
    local needs = lib.callback.await('cookie_select:needsVerify', false)
    if needs then

        SendNUIMessage({ action = 'verifyReject' })
        return
    end
    afterVerify()
end)

RegisterNUICallback('consentDone', function(_, cb)
    cb({ ok = true })
    showScreen('nick')
end)

RegisterNUICallback('checkNick', function(data, cb)
    cb(lib.callback.await('cookie_select:checkNickname', false, (data and data.nickname) or ''))
end)

RegisterNUICallback('genderConflict', function(data, cb)
    cb(lib.callback.await('cookie_select:genderConflict', false, (data and data.gender) or ''))
end)

RegisterNUICallback('issueJumin', function(data, cb)
    cb(lib.callback.await('cookie_select:issueJumin', false,
        (data and data.age) or 0, (data and data.gender) or ''))
end)

RegisterNUICallback('issuePhone', function(_, cb)
    cb(lib.callback.await('cookie_select:issuePhone', false))
end)

RegisterNUICallback('submitNick', function(data, cb)
    local result = lib.callback.await('cookie_select:complete', false, (data and data.nickname) or '')
    cb(result)
    if result and result.ok then
        onboardingJustCompleted = true

        proceedToSelection()
    end
end)

RegisterNUICallback('createChar', function(data, cb)
    data = data or {}
    local check = lib.callback.await('cookie_select:validateCharacter', false, data)
    if not check.ok then
        cb(check)
        return
    end

    local newData = lib.callback.await('qbx_core:server:createCharacter', false, {
        firstname = data.firstname,
        lastname = data.lastname,
        nationality = '대한민국',
        gender = data.gender == '남' and 0 or 1,
        birthdate = data.birthdate,
        cid = 1,
    })
    if not newData then
        cb({ ok = false, reason = '캐릭터 생성에 실패했습니다' })
        return
    end
    cb({ ok = true })

    spawnFlow(true, DEFAULT_SPAWN)
end)

local function customizeOnStage()
    reportStage('customize')
    destroyPreviewCam()
    CookieSharedNuiFocus(false, false)
    SendNUIMessage({ action = 'hide' })

    local conf = {
        ped = true, headBlend = true, faceFeatures = true, headOverlays = true,
        components = true,
        componentConfig = { masks = true, upperBody = true, lowerBody = true, bags = true, shoes = true,
            scarfAndChains = true, bodyArmor = true, shirts = true, decals = true, jackets = true },
        props = true,
        propConfig = { hats = true, glasses = true, ear = true, watches = true, bracelets = true },
        tattoos = true,
        enableExit = true,
        automaticFade = false
    }

    local done = false
    local saved = false
    exports['illenium-appearance']:startPlayerCustomization(function(appearance)
        if appearance then
            TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
            saved = true
        end
        done = true
    end, conf)

    while not done do Wait(0) end
    return saved
end


local function suggestedGender()
    if currentCharacter then
        local gender = currentCharacter.gender
        if gender == nil and type(currentCharacter.charinfo) == 'table' then
            gender = currentCharacter.charinfo.gender
        end
        if tonumber(gender) == 1 or tostring(gender):lower() == 'female' then return 'female' end
    end
    return 'male'
end

local function chooseRecoveryGender(reason)
    local fallback = suggestedGender()
    local input = lib.inputDialog('캐릭터 복구', {
        {
            type = 'select',
            label = '복구할 캐릭터 성별',
            description = (reason or '스토리 캐릭터가 감지되었습니다.') .. ' 온라인 Freemode 캐릭터로 변환합니다.',
            required = true,
            default = fallback,
            options = {
                { value = 'male', label = '남성' },
                { value = 'female', label = '여성' },
            }
        }
    })
    return (input and input[1]) or fallback
end

local function runLegacyCharacterRepair(reason, fromCommand)
    if legacyRepairRunning then return false end
    legacyRepairRunning = true

    local gender = chooseRecoveryGender(reason)
    local targetModel = gender == 'female' and FEMALE_PREVIEW_MODEL or DEFAULT_PREVIEW_MODEL

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end

    local switched = setFreemodeModel(targetModel)
    if not switched then
        DoScreenFadeIn(250)
        legacyRepairRunning = false
        lib.notify({ title='COOKIE', description='Freemode 캐릭터 전환에 실패했습니다.', type='error' })
        return false
    end

    if flowActive then
        placePedOnStage()
        setupPreviewCam()
    end

    DoScreenFadeIn(350)
    local saved = customizeOnStage()

    if saved then
        legacyStoryPedDetected = false
        legacyStoryModelName = nil
        lib.notify({ title='COOKIE', description='캐릭터 복구가 완료되었습니다. 새 외형이 저장되었습니다.', type='success' })
    else
        lib.notify({ title='COOKIE', description='외형 저장을 취소했습니다. 다음 접속 때 복구 안내가 다시 표시될 수 있습니다.', type='warning' })
    end

    legacyRepairRunning = false
    return saved
end

local function enterWithCharacter(openEditor)
    if not currentCharacter then
        return
    end

    lib.callback.await('qbx_core:server:loadCharacter', false, currentCharacter.citizenid)
    local pos = currentCharacter.position or DEFAULT_SPAWN

    -- 기존 DB에 마이클/프랭클린/트레버가 저장된 유저는
    -- 게임 입장 직전에 Freemode로 1회 복구하고 외형을 다시 저장한다.
    if legacyStoryPedDetected then
        local label = legacyStoryModelName or '스토리 캐릭터'
        runLegacyCharacterRepair(label .. ' 스킨이 저장되어 있습니다.', false)
        spawnFlow(false, pos)
        return
    end

    if openEditor then
        customizeOnStage()
    end
    spawnFlow(false, pos)
end

RegisterNUICallback('enterGame', function(_, cb)
    cb({ ok = true })
    if not currentCharacter then
        return
    end

    -- 온보딩 직후에도 외형 편집 화면을 띄우지 않고 바로 입장한다.
    -- 외형 수정은 뉴비 시청 옷장에서만 가능하게 운영한다.
    enterWithCharacter(false)
end)

RegisterNUICallback('editDecline', function(_, cb)
    cb({ ok = true })

    enterWithCharacter(false)
end)

RegisterNUICallback('editAccept', function(_, cb)
    cb({ ok = true })

    enterWithCharacter(true)
end)

CreateThread(function()
    while true do
        Wait(0)
        if NetworkIsSessionStarted() then
            pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
            Wait(250)
            startFlow()
            break
        end
    end

    while NetworkIsInTutorialSession() do
        SetEntityInvincible(PlayerPedId(), true)
        Wait(250)
    end
    SetEntityInvincible(PlayerPedId(), false)
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    if GetInvokingResource() then return end

    TriggerEvent('chat:addMessage', {
        args = { '^3[쿠키]', '재접속하시면 캐릭터를 다시 선택할 수 있습니다.' }
    })
end)


local function manualCharacterRepairCommand()
    if flowActive then
        lib.notify({ title='COOKIE', description='현재 접속 화면에서는 캐릭터 입장 후 복구해주세요.', type='warning' })
        return
    end

    local currentModel = GetEntityModel(PlayerPedId())
    if not isStoryPedModel(currentModel) then
        lib.notify({ title='COOKIE', description='현재 캐릭터는 마이클/프랭클린/트레버 스킨이 아닙니다.', type='inform' })
        return
    end

    CreateThread(function()
        runLegacyCharacterRepair(storyModelLabel(currentModel) .. ' 스킨이 감지되었습니다.', true)
    end)
end

RegisterCommand('캐릭터복구', manualCharacterRepairCommand, false)
RegisterCommand('charfix', manualCharacterRepairCommand, false)

RegisterCommand('obstage_c', function(_, args)
    if GetConvar('cookie:introDebug', 'false') ~= 'true' then return end
    local target = tonumber(args[1])
    if not target then

        return
    end
    local v = Player(target).state.onboardingStage

end, false)

AddStateBagChangeHandler('onboardingStage', nil, function(bagName, _, value)
    if GetConvar('cookie:introDebug', 'false') ~= 'true' then return end

end)

if GetConvar('cookie:introDebug', 'false') == 'true' then
    RegisterCommand('selectstage', function()
        local p = GetEntityCoords(cache.ped)
        local hd = GetEntityHeading(cache.ped)

        local interior = GetInteriorAtCoords(p.x, p.y, p.z)
        local ready = interior ~= 0 and IsInteriorReady(interior) or false
        local found, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 1.0, false)

        if previewCam and DoesCamExist(previewCam) then
            local c = GetCamCoord(previewCam)

        else

        end
    end, false)
end

print('^2[cookie_select]^7 STORY PED AUTO RECOVERY V1.7.3 active')

-- COOKIE SCREENFIX V1: manual diagnostic and recovery, safe to call after login only.
RegisterCommand('cookie_screen_state', function()
    local ped = PlayerPedId()
    local exists = ped ~= 0 and DoesEntityExist(ped)
    local previewLeft = previewCam and DoesCamExist(previewCam) or false
    print(('[cookie_select][screenfix] STATE flowActive=%s previewCam=%s fadeOut=%s fadingOut=%s fadingIn=%s pedExists=%s'):format(
        tostring(flowActive), tostring(previewLeft), tostring(IsScreenFadedOut()),
        tostring(IsScreenFadingOut()), tostring(IsScreenFadingIn()), tostring(exists)))
end, false)

RegisterCommand('cookie_screen_fix', function()
    if not NetworkIsSessionStarted() then
        print('[cookie_select][screenfix] Session is not started. Aborted.')
        return
    end
    print(('[cookie_select][screenfix] MANUAL recovery start; flowActive=%s'):format(tostring(flowActive)))
    SendNUIMessage({ action = 'hide' })
    pcall(function() CookieSharedNuiFocus(false, false) end)
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    if previewCam and DoesCamExist(previewCam) then
        destroyPreviewCam()
    end
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    DoScreenFadeIn(800)
    CreateThread(function()
        Wait(1000)
        print(('[cookie_select][screenfix] MANUAL recovery finished. fadedOut=%s'):format(tostring(IsScreenFadedOut())))
    end)
end, false)
