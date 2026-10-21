CREATE TABLE IF NOT EXISTS cookie_cosmetic_catalog (
    id INT NOT NULL AUTO_INCREMENT,
    code VARCHAR(64) NOT NULL,
    type VARCHAR(32) NOT NULL,
    label VARCHAR(96) NOT NULL,
    color VARCHAR(16) NOT NULL DEFAULT '#ffffff',
    style_json LONGTEXT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cookie_cosmetic_code (code),
    KEY idx_cookie_cosmetic_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS cookie_cosmetic_ownership (
    citizenid VARCHAR(64) NOT NULL,
    code VARCHAR(64) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 0,
    granted_by VARCHAR(64) NULL,
    granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid, code),
    KEY idx_cookie_cosmetic_owner_active (citizenid, active),
    CONSTRAINT fk_cookie_cosmetic_catalog
        FOREIGN KEY (code) REFERENCES cookie_cosmetic_catalog(code)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
