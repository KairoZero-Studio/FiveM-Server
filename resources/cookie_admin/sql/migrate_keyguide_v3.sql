-- COOKIE KEY GUIDE V3 수동 참고용 마이그레이션
-- 서버 시작 시 cookie_admin/server/keyguide.lua가 동일 구조를 자동 생성/이관하므로
-- 정상 환경에서는 이 파일을 직접 실행할 필요가 없습니다.

CREATE TABLE IF NOT EXISTS cookie_keyguide_category (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    category_key VARCHAR(50) NOT NULL,
    label VARCHAR(60) NOT NULL,
    icon VARCHAR(16) NOT NULL DEFAULT '⌨',
    tone VARCHAR(20) NOT NULL DEFAULT 'default',
    visibility_mode ENUM('all','factions') NOT NULL DEFAULT 'all',
    sort_order INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_cookie_keyguide_category_key (category_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cookie_keyguide_category_faction (
    category_id INT UNSIGNED NOT NULL,
    faction_id INT NOT NULL,
    PRIMARY KEY (category_id, faction_id),
    KEY idx_cookie_keyguide_faction (faction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
