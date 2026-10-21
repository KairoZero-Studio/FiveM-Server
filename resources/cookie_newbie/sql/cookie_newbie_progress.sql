CREATE TABLE IF NOT EXISTS cookie_newbie_progress (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    license VARCHAR(255) NOT NULL,
    guide_done TINYINT(1) NOT NULL DEFAULT 0,
    identity_done TINYINT(1) NOT NULL DEFAULT 0,
    license_done TINYINT(1) NOT NULL DEFAULT 0,
    education_done TINYINT(1) NOT NULL DEFAULT 0,
    verify_done TINYINT(1) NOT NULL DEFAULT 0,
    completed_at DATETIME NULL,
    reward_claimed_at DATETIME NULL,
    reward_opened_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cookie_newbie_license (license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
