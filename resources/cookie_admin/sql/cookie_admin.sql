CREATE TABLE IF NOT EXISTS `cookie_admin` (
  `id`           INT AUTO_INCREMENT PRIMARY KEY,
  `license`      VARCHAR(255) NOT NULL UNIQUE,
  `user_id`      INT          NULL,
  `admin_name`   VARCHAR(60)  NOT NULL,
  `admin_level`  TINYINT      NOT NULL DEFAULT 1,
  `total_minute` INT          NOT NULL DEFAULT 0,
  `is_active`    TINYINT(1)   NOT NULL DEFAULT 1,
  `last_seen_at` TIMESTAMP    NULL,
  `created_by`   VARCHAR(255) NULL,
  `updated_by`   VARCHAR(255) NULL,
  `created_at`   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_license` (`license`),
  INDEX `idx_level` (`admin_level`)
);
