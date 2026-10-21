Config = {}

Config.RecentRecordLimit = 30
Config.RankingLimit = 10

-- 강도 RP 패배 시 자동 전과/범죄점수.
-- 승리한 경우에는 기록되지 않습니다.
Config.RobberyLossScores = {
    convenience = { label = '소형 강도 RP 패배', score = 15 },
    emptyhouse  = { label = '빈집 강도 RP 패배', score = 12 },
    bank        = { label = '대형 강도 RP 패배', score = 30 },
}
