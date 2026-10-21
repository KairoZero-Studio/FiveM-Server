-- COOKIE CHAT V2.3 - ALWAYS VISIBLE

local FORCE_KVP = 'cookie_chat_always_visible_v23'
local forceFinished = false

local function waitForBaseChat()
    local untilAt = GetGameTimer() + 15000

    while GetResourceState('chat') ~= 'started' and GetGameTimer() < untilAt do
        Wait(250)
    end

    return GetResourceState('chat') == 'started'
end

local function forceAlwaysVisibleOnce()
    if forceFinished then return end
    forceFinished = true

    if not waitForBaseChat() then
        print('^1[cookie_chat]^7 ALWAYS VISIBLE: base chat resource not started')
        return
    end

    -- V2.3 적용을 이미 완료한 클라이언트면 base chat의 저장된
    -- ALWAYS_SHOW 상태를 건드리지 않는다.
    if GetResourceKvpInt(FORCE_KVP) == 1 then
        print('^2[cookie_chat]^7 ALWAYS VISIBLE: saved state active')
        return
    end

    -- chat NUI / toggleChat command 등록 대기.
    Wait(2500)

    -- 쿠키서버에서 현재 확인된 기본 상태는 SHOW_WHEN_ACTIVE.
    -- 한 번 토글하면 FiveM chat이 ALWAYS_SHOW로 전환하고
    -- 자기 resource KVP hideState=1을 저장한다.
    ExecuteCommand('toggleChat')

    SetResourceKvpInt(FORCE_KVP, 1)

    print('^2[cookie_chat]^7 ALWAYS VISIBLE: forced base chat to ALWAYS_SHOW')
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    CreateThread(function()
        Wait(500)
        forceAlwaysVisibleOnce()
    end)
end)

CreateThread(function()
    Wait(1000)
    forceAlwaysVisibleOnce()
end)

-- 상태가 꼬였을 때 F8:
-- cookie_chat_reset_visible
-- 이후 FiveM 재접속.
RegisterCommand('cookie_chat_reset_visible', function()
    SetResourceKvpInt(FORCE_KVP, 0)
    print('^3[cookie_chat]^7 ALWAYS VISIBLE state reset. Reconnect to apply again.')
end, false)
