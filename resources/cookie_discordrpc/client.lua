local Context = {
    nickname = '시민',
    players = 0,
    max = 48,
    factionActivity = nil,
    factionPriority = nil,
    jobActivity = nil,
    jobPriority = nil,
}

local Activities = {}

local function debugPrint(...)
    if Config.Debug then
        print('^5[cookie_discordrpc]^7', ...)
    end
end

local function truncateUtf8ish(text, maxBytes)
    text = tostring(text or '')
    if #text <= maxBytes then return text end
    return text:sub(1, maxBytes)
end

local function setActivity(key, text, priority)
    key = tostring(key or 'custom')
    text = tostring(text or '')
    if text == '' then
        Activities[key] = nil
        return
    end

    Activities[key] = {
        text = text,
        priority = tonumber(priority) or 50,
    }
end

local function clearActivity(key)
    Activities[tostring(key or 'custom')] = nil
end

exports('SetActivity', function(key, text, priority)
    setActivity(key, text, priority)
end)

exports('ClearActivity', function(key)
    clearActivity(key)
end)

RegisterNetEvent('cookie_discordrpc:client:setActivity', function(key, text, priority)
    setActivity(key, text, priority)
end)

RegisterNetEvent('cookie_discordrpc:client:clearActivity', function(key)
    clearActivity(key)
end)

local function resolveActivity()
    local bestText = Config.DefaultActivity or '🍪 쿠키시티 생활 중'
    local bestPriority = Config.ActivityPriority.default or 0

    if Context.jobActivity and (Context.jobPriority or 0) > bestPriority then
        bestText = Context.jobActivity
        bestPriority = Context.jobPriority or 0
    end

    if Context.factionActivity and (Context.factionPriority or 0) > bestPriority then
        bestText = Context.factionActivity
        bestPriority = Context.factionPriority or 0
    end

    for _, row in pairs(Activities) do
        if row and row.text and (row.priority or 0) > bestPriority then
            bestText = row.text
            bestPriority = row.priority or 0
        end
    end

    return bestText
end

local function renderPresence()
    local activity = resolveActivity()
    local text = tostring(Config.PresenceFormat or '{nickname} | {activity} | {players}/{max}명')

    text = text:gsub('{nickname}', tostring(Context.nickname or '시민'))
    text = text:gsub('{activity}', tostring(activity or Config.DefaultActivity))
    text = text:gsub('{players}', tostring(Context.players or 0))
    text = text:gsub('{max}', tostring(Context.max or 48))

    -- Rich Presence state 길이 과다 방지.
    return truncateUtf8ish(text, 120)
end

local function applyStaticDiscordConfig()
    local appId = tostring(Config.ApplicationId or '')
    if appId == '' or appId == 'PUT_YOUR_APPLICATION_ID_HERE' then
        debugPrint('Application ID가 설정되지 않았습니다.')
        return false
    end

    SetDiscordAppId(appId)

    if Config.LargeAsset and Config.LargeAsset ~= '' then
        SetDiscordRichPresenceAsset(Config.LargeAsset)
        if Config.LargeAssetText and Config.LargeAssetText ~= '' then
            SetDiscordRichPresenceAssetText(Config.LargeAssetText)
        end
    end

    if Config.SmallAsset and Config.SmallAsset.enabled and Config.SmallAsset.key ~= '' then
        SetDiscordRichPresenceAssetSmall(Config.SmallAsset.key)
        if Config.SmallAsset.text and Config.SmallAsset.text ~= '' then
            SetDiscordRichPresenceAssetSmallText(Config.SmallAsset.text)
        end
    end

    for index, button in ipairs(Config.Buttons or {}) do
        if index > 2 then break end
        if button.enabled and button.label and button.url
            and button.label ~= '' and button.url:match('^https://') then
            SetDiscordRichPresenceAction(index - 1, button.label, button.url)
        end
    end

    return true
end

RegisterNetEvent('cookie_discordrpc:client:context', function(data)
    if type(data) ~= 'table' then return end

    Context.nickname = data.nickname or Context.nickname
    Context.players = tonumber(data.players) or Context.players
    Context.max = tonumber(data.max) or Context.max
    Context.factionActivity = data.factionActivity
    Context.factionPriority = tonumber(data.factionPriority)
    Context.jobActivity = data.jobActivity
    Context.jobPriority = tonumber(data.jobPriority)

    -- Qbox/기타 리소스가 RPC 설정을 만졌더라도 COOKIE 값을 다시 적용.
    applyStaticDiscordConfig()
    SetRichPresence(renderPresence())
end)

CreateThread(function()
    Wait(1500)

    local configured = applyStaticDiscordConfig()

    while true do
        if configured then
            -- 항상 COOKIE SERVER의 App ID / 이미지 / 버튼을 다시 선언.
            applyStaticDiscordConfig()
            TriggerServerEvent('cookie_discordrpc:server:requestContext')
            Wait(math.max(
                5000,
                tonumber(Config.ForceReapplyMs)
                    or tonumber(Config.RefreshMs)
                    or 15000
            ))
        else
            Wait(10000)
            configured = applyStaticDiscordConfig()
        end
    end
end)

-- 리소스가 다시 시작돼도 기존 수동 Activity는 사라지므로
-- 관련 리소스들이 자신의 이벤트에서 다시 SetActivity를 호출하면 된다.
AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        CreateThread(function()
            Wait(1200)
            applyStaticDiscordConfig()
            TriggerServerEvent('cookie_discordrpc:server:requestContext')
        end)
    end
end)
