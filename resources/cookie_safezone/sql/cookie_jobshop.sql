CREATE TABLE IF NOT EXISTS `cookie_jobshop_item` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_name` VARCHAR(40) NOT NULL,
  `item_name` VARCHAR(80) NOT NULL,
  `label` VARCHAR(80) NOT NULL,
  `price` INT NOT NULL DEFAULT 0,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  `sort_order` INT NOT NULL DEFAULT 0,
  `added_by` VARCHAR(60) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_cookie_jobshop_job_item` (`job_name`, `item_name`),
  INDEX `idx_cookie_jobshop_job_active` (`job_name`, `active`, `sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `cookie_jobshop_item`
  (`job_name`, `item_name`, `label`, `price`, `active`, `sort_order`, `added_by`)
VALUES
  ('mechanic', 'repairkit', '수리키트', 25000, 1, 10, 'default seed');
