-- COOKIE ADMIN kick/ban persistence (2026-08-25)
-- server/main.lua also creates these tables automatically on resource start.
CREATE TABLE IF NOT EXISTS `cookie_admin_ban` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(80) NOT NULL,
  `target_gobun` INT NULL,
  `target_cid` VARCHAR(64) NULL,
  `target_name` VARCHAR(80) NULL,
  `reason` VARCHAR(300) NOT NULL,
  `admin_name` VARCHAR(60) NULL,
  `admin_license` VARCHAR(80) NULL,
  `expires_at` DATETIME NULL,
  `revoked_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ban_identifier` (`identifier`),
  KEY `idx_ban_active` (`identifier`,`revoked_at`,`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `cookie_admin_punishment_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `action` VARCHAR(16) NOT NULL,
  `admin_name` VARCHAR(60) NULL,
  `admin_license` VARCHAR(80) NULL,
  `admin_level` INT NULL,
  `target_server` INT NULL,
  `target_gobun` INT NULL,
  `target_cid` VARCHAR(64) NULL,
  `target_name` VARCHAR(80) NULL,
  `target_license` VARCHAR(80) NULL,
  `reason` VARCHAR(300) NULL,
  `minutes` INT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_punish_action` (`action`),
  KEY `idx_punish_target` (`target_gobun`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
