-- 3-B-3: 개발자 권한(is_dev) — 비번 재설정 등 최상위 권한 게이트.
-- ★ 게임 내 부여 불가. DB 직접 심기만 (아래 UPDATE는 운영자가 수동 1회).
ALTER TABLE `cookie_admin`
  ADD COLUMN IF NOT EXISTS `is_dev` TINYINT(1) NOT NULL DEFAULT 0 AFTER `admin_level`;

-- 지혁님(장지혁) 계정에 개발자 권한 부여 (수동 심기)
UPDATE `cookie_admin` SET `is_dev` = 1 WHERE `admin_name` = '장지혁';
