CREATE TABLE IF NOT EXISTS cookie_robbery_location (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    robbery_type VARCHAR(32) NOT NULL DEFAULT 'convenience',
    label VARCHAR(80) NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    heading FLOAT NOT NULL DEFAULT 0,
    interact_distance DECIMAL(6,2) NOT NULL DEFAULT 2.50,
    crew_radius DECIMAL(6,2) NOT NULL DEFAULT 12.00,
    combat_radius DECIMAL(6,2) NOT NULL DEFAULT 45.00,
    fail_radius DECIMAL(6,2) NOT NULL DEFAULT 55.00,
    boundary_mode VARCHAR(16) NOT NULL DEFAULT 'circle',
    boundary_points LONGTEXT NULL,
    threat_seconds INT NOT NULL DEFAULT 8,
    response_wait_seconds INT NOT NULL DEFAULT 90,
    loot_seconds INT NOT NULL DEFAULT 30,
    cooldown_seconds INT NOT NULL DEFAULT 600,
    cash_min BIGINT NOT NULL DEFAULT 2500000,
    cash_max BIGINT NOT NULL DEFAULT 3500000,
    required_loot_amount INT NOT NULL DEFAULT 0,
    min_crew INT NOT NULL DEFAULT 1,
    dispatch_text VARCHAR(180) NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    sort_order INT NOT NULL DEFAULT 100,
    updated_by VARCHAR(60) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_cookie_robbery_location_type (robbery_type, enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cookie_robbery_reward (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    robbery_id INT UNSIGNED NOT NULL,
    item_name VARCHAR(80) NOT NULL,
    label VARCHAR(80) NOT NULL,
    min_amount INT NOT NULL DEFAULT 1,
    max_amount INT NOT NULL DEFAULT 1,
    chance DECIMAL(6,2) NOT NULL DEFAULT 100.00,
    sort_order INT NOT NULL DEFAULT 100,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    KEY idx_cookie_robbery_reward_location (robbery_id),
    CONSTRAINT fk_cookie_robbery_reward_location
        FOREIGN KEY (robbery_id) REFERENCES cookie_robbery_location(id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cookie_robbery_log (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    robbery_id INT UNSIGNED NULL,
    robbery_label VARCHAR(80) NOT NULL,
    starter_citizenid VARCHAR(64) NULL,
    starter_name VARCHAR(80) NULL,
    status VARCHAR(24) NOT NULL,
    cash_reward BIGINT NOT NULL DEFAULT 0,
    item_reward_json LONGTEXT NULL,
    detail VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_cookie_robbery_log_location (robbery_id, created_at),
    KEY idx_cookie_robbery_log_citizen (starter_citizenid, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS cookie_robbery_loot_point (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    robbery_id INT UNSIGNED NOT NULL,
    label VARCHAR(80) NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    item_name VARCHAR(80) NOT NULL,
    item_label VARCHAR(80) NOT NULL,
    min_amount INT NOT NULL DEFAULT 1,
    max_amount INT NOT NULL DEFAULT 1,
    loot_seconds INT NOT NULL DEFAULT 10,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    sort_order INT NOT NULL DEFAULT 100,
    PRIMARY KEY (id),
    KEY idx_cookie_robbery_loot_point_location (robbery_id),
    CONSTRAINT fk_cookie_robbery_loot_point_location
        FOREIGN KEY (robbery_id) REFERENCES cookie_robbery_location(id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS cookie_robbery_requirement (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    robbery_id INT UNSIGNED NOT NULL,
    faction_id INT NOT NULL,
    min_duty INT NOT NULL DEFAULT 1,
    sort_order INT NOT NULL DEFAULT 100,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cookie_robbery_requirement (robbery_id, faction_id),
    KEY idx_cookie_robbery_requirement_location (robbery_id),
    KEY idx_cookie_robbery_requirement_faction (faction_id),
    CONSTRAINT fk_cookie_robbery_requirement_location
        FOREIGN KEY (robbery_id) REFERENCES cookie_robbery_location(id)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
