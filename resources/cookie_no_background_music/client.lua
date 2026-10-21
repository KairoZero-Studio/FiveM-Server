-- COOKIE NO BACKGROUND MUSIC V1
-- GTA/FiveM의 배경/상황 음악을 줄이기 위한 전용 리소스.
-- 차량 라디오, 효과음, 발소리, 총소리, 음성채팅을 끄는 목적이 아닙니다.

local muteScenes = {
    'FBI_HEIST_H5_MUTE_AMBIENCE_SCENE',
    'CHARACTER_CHANGE_IN_SKY_SCENE',
    'DLC_MPHEIST_TRANSITION_TO_APT_FADE_IN_RADIO_SCENE'
}

local function applyNoBackgroundMusic()
    -- 비행 중 자동으로 재생되는 배경 음악 제거
    SetAudioFlag('DisableFlightMusic', true)

    -- 메뉴/프론트엔드 계열 자동 음악 억제
    SetAudioFlag('PlayMenuMusic', false)

    -- GTA의 상황/미션 계열 배경 스코어를 억제하는 데 쓰이는 오디오 씬
    for _, scene in ipairs(muteScenes) do
        if not IsAudioSceneActive(scene) then
            StartAudioScene(scene)
        end
    end
end

CreateThread(function()
    Wait(1000)
    applyNoBackgroundMusic()

    -- 다른 리소스나 GTA 상태 전환으로 오디오 씬이 풀리는 경우 다시 적용
    while true do
        Wait(10000)
        applyNoBackgroundMusic()
    end
end)

AddEventHandler('playerSpawned', function()
    Wait(1000)
    applyNoBackgroundMusic()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- 리소스를 끄면 우리가 시작한 오디오 씬은 원상복구
    for _, scene in ipairs(muteScenes) do
        if IsAudioSceneActive(scene) then
            StopAudioScene(scene)
        end
    end

    SetAudioFlag('DisableFlightMusic', false)
end)
