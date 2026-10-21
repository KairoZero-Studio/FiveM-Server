-- cookie_core 뉴비 인증(디스코드) — 2026-07-12 (v2, 흐름 반전 반영)
-- 적용: mysql -u cookie -pcookie1234 -P 3307 Qbox_315020 < migrate_2026_verify.sql
--
-- 흐름
--   디스코드 [뉴비 인증] 버튼 → 봇 → 서버가 6자리 코드 발급(디스코드ID에 묶임)
--   → 유저가 게임 화면에 코드 입력 → 서버가 대조 → 그 자리에서 고번 발급 → 온보딩 진행
--
-- 설계
--  · 코드는 '디스코드 계정'에 묶인다. 게임 라이선스는 코드를 쓰는 순간 결합된다.
--    (발급 시점엔 서버가 그 사람이 게임에서 누군지 모른다 — 그래서 license를 키로 못 쓴다)
--  · 코드 자체가 PK. 재발급하면 이전 미사용 코드는 만료시킨다.

DROP TABLE IF EXISTS `cookie_verify`;

CREATE TABLE `cookie_verify` (
  `code`         VARCHAR(12)  NOT NULL PRIMARY KEY,   -- 6자리 숫자(문자열, 앞자리 0 허용)
  `discord_id`   VARCHAR(50)  NOT NULL,               -- 코드를 받아간 디스코드 계정
  `discord_tag`  VARCHAR(64)  DEFAULT NULL,           -- 로그/문의 대응용
  `issued_at`    DATETIME     NOT NULL,
  `expires_at`   DATETIME     NOT NULL,
  `used_at`      DATETIME     DEFAULT NULL,           -- 사용됨(1회용)
  `used_license` VARCHAR(255) DEFAULT NULL,           -- 어떤 게임 계정이 썼는지
  KEY `idx_discord` (`discord_id`),
  KEY `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 인증 시각 기록. is_verified/discord_id는 기존 컬럼 재사용.
ALTER TABLE `cookie_user`
  ADD COLUMN IF NOT EXISTS `verified_at` DATETIME NULL AFTER `discord_id`;

-- 한 디스코드 계정 = 한 사람(다중계정 차단). NULL은 다중 허용.
ALTER TABLE `cookie_user`
  ADD UNIQUE KEY `uq_discord` (`discord_id`);
