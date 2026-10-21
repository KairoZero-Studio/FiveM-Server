-- cookie_intro 온보딩: 별명 중복 방지 + 약관 동의 기록
-- 적용: oxmysql 사용 서버 → DB에 1회 직접 실행
--   mysql -u cookie -pcookie1234 -P 3307 Qbox_315020 < migrate_2026_intro.sql

-- 별명 중복 방지(NULL은 다중 허용됨 → 온보딩 전 유저 공존 가능)
ALTER TABLE cookie_user ADD UNIQUE KEY uq_nickname (nickname);

-- 약관 동의 기록(온보딩 완료 시각). nickname+consent_at 모두 있으면 온보딩 완료로 판정
ALTER TABLE cookie_user
  ADD COLUMN consent_at DATETIME NULL AFTER nickname;
