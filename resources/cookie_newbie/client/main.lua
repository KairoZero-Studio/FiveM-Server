local opened = false

local function closeUi()
    if not opened then return end
    opened = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openUi()
    if opened then return end
    local state = lib.callback.await('cookie_newbie:getState', false)
    if not state or state.ok == false then
        lib.notify({
            title = '뉴비 시청',
            description = state and state.reason or '뉴비 정보를 불러오지 못했습니다.',
            type = 'error'
        })
        return
    end

    opened = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        data = state,
        guidePages = Config.GuidePages,
        educationPages = Config.EducationPages,
        title = Config.Title,
        educationTitle = Config.EducationTitle,
        verifyTitle = Config.VerifyTitle,
    })
end

RegisterNetEvent('cookie_newbie:client:open', openUi)
exports('Open', openUi)

if Config.EnableTestCommand then
    RegisterCommand(Config.TestCommand or 'newbiehall', function()
        openUi()
    end, false)
end

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('guideDone', function(_, cb)
    local result = lib.callback.await('cookie_newbie:guideDone', false)
    cb(result or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('issueIdentity', function(_, cb)
    local result = lib.callback.await('cookie_newbie:issueIdentity', false)
    cb(result or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('issueLicense', function(_, cb)
    local result = lib.callback.await('cookie_newbie:issueLicense', false)
    cb(result or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('educationDone', function(_, cb)
    local result = lib.callback.await('cookie_newbie:educationDone', false)
    cb(result or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('submitVerifyCode', function(data, cb)
    local result = lib.callback.await('cookie_newbie:submitVerifyCode', false, data and data.code)
    cb(result or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('claimReward', function(_, cb)
    local result = lib.callback.await('cookie_newbie:claimReward', false)
    cb(result or { ok=false, reason='서버 응답이 없습니다.' })
end)

RegisterNUICallback('refresh', function(_, cb)
    local state = lib.callback.await('cookie_newbie:getState', false)
    cb(state or { ok=false })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SetNuiFocus(false, false)
    end
end)
