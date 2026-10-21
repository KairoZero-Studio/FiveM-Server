-- cookie_core 마이그레이션: display_gobun 폐기 + 중복 인덱스 제거 + 고번 초기화(1부터)
-- 기존에 cookie_user.sql(구버전)으로 생성된 테이블에만 1회 적용.
ALTER TABLE `cookie_user` DROP COLUMN `display_gobun`;
ALTER TABLE `cookie_user` DROP INDEX `idx_license`;
ALTER TABLE `cookie_user` DROP INDEX `idx_gobun`;
TRUNCATE TABLE `cookie_user`;   -- 테스트 발급분 제거 → 다음 접속자부터 고번 1
