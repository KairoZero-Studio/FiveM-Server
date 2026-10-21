

MedicConfig = {}

MedicConfig.Debug = false

MedicConfig.ReviveSeconds = 10

-- 자가재생동기: 소생 버튼 사용 시 1개를 자동 소모해 대기시간을 단축합니다.
MedicConfig.ReviveBoosterItem = 'self_regenerator'
MedicConfig.ReviveBoosterSeconds = 3
MedicConfig.ReviveBoosterConsume = true

MedicConfig.DownSystem = '%s님이 다운 하셨습니다.'

MedicConfig.Declares = {
    wipe = {
        pre = '%s님이 ', hl = 'RP중 전멸', post = ' 선언하셨습니다.', tone = 'wipe',
        status = 'RP중 전멸을 선언했습니다',
    },
    stop = {
        pre = '%s님이 ', hl = 'RP 중단', post = ' 신청하셨습니다.', tone = 'stop',
        status = 'RP 중단을 신청했습니다',
    },
    death = {
        pre = '%s님이 ', hl = 'RP중 사망', post = ' 하셨습니다.', tone = 'death',
        status = nil,
    },
}

function MedicLog(...)
    if MedicConfig.Debug then

    end
end
