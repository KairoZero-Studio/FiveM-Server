-- 3-A: LV5 관리자 2차인증용 비밀번호 컬럼 (SHA2-256 + per-row salt)
-- 평문 미저장. pw_hash = SHA2(CONCAT(pw, pw_salt), 256) → 64 hex chars.
-- cookie_admin_duty_minute.sql 의 ADD COLUMN IF NOT EXISTS ... AFTER 패턴 동일.
ALTER TABLE `cookie_admin`
  ADD COLUMN IF NOT EXISTS `pw_hash` CHAR(64)   DEFAULT NULL AFTER `admin_level`,
  ADD COLUMN IF NOT EXISTS `pw_salt` VARCHAR(32) DEFAULT NULL AFTER `pw_hash`;
