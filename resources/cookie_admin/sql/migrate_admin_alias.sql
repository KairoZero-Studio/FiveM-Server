-- 3-C: 관리자 권한부여 — 부여 시 운영자가 붙이는 별칭(메모) 컬럼.
-- 식별 키는 license(불변). admin_alias는 가독용 라벨이라 NULL 허용.
-- migrate_admin_pw.sql 의 ADD COLUMN IF NOT EXISTS ... AFTER 패턴 동일.
ALTER TABLE `cookie_admin`
  ADD COLUMN IF NOT EXISTS `admin_alias` VARCHAR(64) DEFAULT NULL AFTER `license`;
