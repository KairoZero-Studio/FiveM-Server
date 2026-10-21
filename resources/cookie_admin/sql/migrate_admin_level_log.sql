-- #K-19: 관리자 레벨 변경 감사 로그
-- 기존에 감사 테이블이 없어 신설한다(admin_audit_log 라는 이름의 테이블은 이 코드베이스에 존재하지 않았다).
-- 식별 키는 license(불변). 이름은 변경 시점 스냅샷이라 나중에 바뀌어도 기록은 남는다.
--   old_level / new_level: 0 = 관리자 아님(is_active=0 또는 행 없음), 1~5 = admin_level.
--   자격 레벨(admin_level) 기준이며 발효 레벨(effectiveLevel)이 아니다 — 발효는 비번 설정 여부로 파생된다.

CREATE TABLE IF NOT EXISTS `cookie_admin_level_log` (
  `id`             INT AUTO_INCREMENT PRIMARY KEY,
  `actor_license`  VARCHAR(255) NOT NULL,
  `actor_name`     VARCHAR(60)  NOT NULL,
  `target_license` VARCHAR(255) NOT NULL,
  `target_name`    VARCHAR(60)  NOT NULL,
  `old_level`      TINYINT      NOT NULL,
  `new_level`      TINYINT      NOT NULL,
  `created_at`     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_target` (`target_license`),
  INDEX `idx_actor` (`actor_license`),
  INDEX `idx_created` (`created_at`)
);
