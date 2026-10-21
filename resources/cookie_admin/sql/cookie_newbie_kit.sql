-- COOKIE newbie reward kit configuration tables
-- reward_type: item / bank / cash / vehicle
-- vehicle일 때 item_name 컬럼에는 차량 SpawnCode가 저장됩니다.
-- 리소스 시작 시 자동 생성되므로 수동 실행은 필요하지 않습니다.
CREATE TABLE IF NOT EXISTS cookie_newbie_kit_config (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    initialized TINYINT(1) NOT NULL DEFAULT 0,
    updated_by VARCHAR(80) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cookie_newbie_kit_reward (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    sort_order INT UNSIGNED NOT NULL DEFAULT 0,
    reward_type VARCHAR(12) NOT NULL,
    item_name VARCHAR(80) NULL,
    item_count INT UNSIGNED NOT NULL DEFAULT 0,
    amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
    display_label VARCHAR(80) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_newbie_kit_sort(sort_order, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
