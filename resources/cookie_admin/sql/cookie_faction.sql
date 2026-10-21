-- 2026-07-11: 팩션 시스템 (Phase 2)
-- 원본(source of truth) = 이 테이블들. qbx job/grade에는 '동기화'만 한다.
-- 서버 부트 시 server/faction.lua의 멱등 마이그레이션이 동일 내용을 자동 적용한다(수동 실행 불필요).

CREATE TABLE IF NOT EXISTS `cookie_faction` (
  `id`               INT AUTO_INCREMENT PRIMARY KEY,
  `faction_key`      VARCHAR(40)  NOT NULL UNIQUE,   -- 'lspd'
  `faction_type`     VARCHAR(20)  NOT NULL,          -- police/security/corrections/fire/private/crime/civil
  `job_name`         VARCHAR(40)  NOT NULL,          -- 매핑되는 qbx job (police 등)
  `name`             VARCHAR(60)  NOT NULL,          -- '쿠키 경찰국'
  `label_short`      VARCHAR(20)  NULL,
  `color`            VARCHAR(10)  NULL,
  `budget`           BIGINT       NOT NULL DEFAULT 0,
  `leader_citizenid` VARCHAR(50)  NULL,
  `spawn_json`       TEXT         NULL,              -- vec4 스폰 좌표
  `is_active`        TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by`       VARCHAR(255) NULL,
  `created_at`       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  `updated_at`       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_job` (`job_name`),
  INDEX `idx_type` (`faction_type`)
);

-- 계급 = qbx job grade와 1:1
CREATE TABLE IF NOT EXISTS `cookie_faction_rank` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` INT         NOT NULL,
  `grade`      INT         NOT NULL,
  `rank_name`  VARCHAR(40) NOT NULL,
  `is_leader`  TINYINT(1)  NOT NULL DEFAULT 0,
  `is_officer` TINYINT(1)  NOT NULL DEFAULT 0,
  `salary`     INT         NOT NULL DEFAULT 0,
  `sort_order` INT         NOT NULL DEFAULT 0,
  UNIQUE KEY `uq_faction_grade` (`faction_id`, `grade`),
  CONSTRAINT `fk_rank_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
);

-- 멤버 (원본). qbx job/grade와 동기화됨.
CREATE TABLE IF NOT EXISTS `cookie_faction_member` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` INT         NOT NULL,
  `citizenid`  VARCHAR(50) NOT NULL,
  `grade`      INT         NOT NULL DEFAULT 0,
  `invited_by` VARCHAR(50) NULL,
  `status`     VARCHAR(16) NOT NULL DEFAULT 'active',  -- active/suspended
  `joined_at`  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_faction_member` (`faction_id`, `citizenid`),
  INDEX `idx_citizenid` (`citizenid`),
  CONSTRAINT `fk_member_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
);

-- 예산 내역 (cookie 자체 관리 수치 — D4 확정)
CREATE TABLE IF NOT EXISTS `cookie_faction_budget_log` (
  `id`              INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id`      INT          NOT NULL,
  `delta`           BIGINT       NOT NULL,
  `balance_after`   BIGINT       NOT NULL,
  `category`        VARCHAR(24)  NULL,   -- fine_income/salary/purchase/deposit
  `reason`          VARCHAR(120) NULL,
  `actor_citizenid` VARCHAR(50)  NULL,
  `created_at`      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_faction` (`faction_id`),
  CONSTRAINT `fk_budget_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
);

-- 구금 기록 (경찰/보안/교정 공용)
CREATE TABLE IF NOT EXISTS `cookie_faction_detention` (
  `id`                INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id`        INT          NOT NULL,
  `officer_citizenid` VARCHAR(50)  NULL,
  `target_citizenid`  VARCHAR(50)  NULL,
  `target_name`       VARCHAR(60)  NULL,
  `charge`            VARCHAR(120) NULL,
  `fine_amount`       INT          NOT NULL DEFAULT 0,
  `jail_seconds`      INT          NOT NULL DEFAULT 0,
  `note`              TEXT         NULL,
  `created_at`        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_faction` (`faction_id`),
  CONSTRAINT `fk_detention_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
);

-- 팩션 차량 registry (기존 LSPD 함대 방식 일반화)
CREATE TABLE IF NOT EXISTS `cookie_faction_vehicle` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` INT         NOT NULL,
  `model`      VARCHAR(40) NOT NULL,
  `plate`      VARCHAR(16) NULL,
  `min_grade`  INT         NOT NULL DEFAULT 0,
  `added_by`   VARCHAR(60) NULL,
  `created_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_faction` (`faction_id`),
  CONSTRAINT `fk_fveh_faction` FOREIGN KEY (`faction_id`) REFERENCES `cookie_faction`(`id`) ON DELETE CASCADE
);

-- 감사 로그
CREATE TABLE IF NOT EXISTS `cookie_faction_log` (
  `id`         INT AUTO_INCREMENT PRIMARY KEY,
  `faction_id` INT          NULL,
  `action`     VARCHAR(40)  NOT NULL,
  `actor`      VARCHAR(120) NULL,
  `detail`     TEXT         NULL,
  `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_faction` (`faction_id`)
);
