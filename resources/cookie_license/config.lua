Config = {}

-- 게임 내 고유 운전면허번호.
-- 실제 대한민국 운전면허번호 형식을 모방하지 않고 COOKIE 전용 번호를 사용합니다.
Config.NumberPrefix = 'CKD-'
Config.NumberDigits = 6

-- 경찰/관리자가 입력 가능한 최대 면허 정지 시간.
-- 수동 정지 입력은 1~60분. 죄목표에서는 0분(정지 없음)도 사용.
Config.MinSuspendMinutes = 1
Config.MaxSuspendMinutes = 60

-- 기존 시민에게도 자동으로 면허번호를 발급.
Config.BackfillExistingCitizens = false

-- 만료된 정지를 몇 초마다 정리할지.
Config.ExpirySweepSeconds = 60

-- 자동 만료 시 Discord에도 '자동 정지 해제' 로그 전송.
Config.LogAutomaticRestore = true

-- =========================================================
-- 면허 Discord 로그 V1.1
--
-- 1) 공통 면허 로그
--    - 자동 정지 해제
--    - 관리자 정지/해제
--    - 기타 시스템 면허 처리
--
-- 2) 경찰청 면허정지 로그
--    - 경찰청 F5 정지
--    - 경찰청 F5 정지 해제
--
-- 3) 보안국 면허정지 로그
--    - 보안국 F5 정지
--    - 보안국 F5 정지 해제
--
-- URL 직접 입력 또는 server.cfg 둘 다 지원.
-- =========================================================
Config.DiscordWebhooks = {
    license = '',
    police_license = 'https://discord.com/api/webhooks/1544628316688875561/nCDXuaZS9-wH7IBLY5YLI3Is3KnlvWH5ZEynnHyHN6EAZAl36c5sEzfG49XJ8WVeJY-i',
    security_license = 'https://discord.com/api/webhooks/1544628517285924895/o-LPebmhYzKVxrvg6vESR1kCjnwDSkoZovtySGPhGIqTA6ovPKzxJUgpB709-5INROZt',
}

-- server.cfg 방식:
-- set cookie_log_license "공통 면허 로그 웹훅"
-- set cookie_log_police_license "경찰청 면허정지 로그 웹훅"
-- set cookie_log_security_license "보안국 면허정지 로그 웹훅"

Config.DiscordBotName = 'COOKIE 면허 로그'
Config.DiscordAvatarURL = ''
