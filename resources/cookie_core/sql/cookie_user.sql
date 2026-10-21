-- cookie_core: 유저(사람=license) 단위 고번/뉴비 관리 테이블
-- 컨벤션: cookie_admin 동일 (InnoDB, utf8mb4_general_ci, id PK AI, 자연키 UNIQUE, created/updated_at)
-- 적용: oxmysql 사용 서버이므로 DB에 직접 1회 실행(아래 보고의 '적용 방법' 참고)
CREATE TABLE IF NOT EXISTS `cookie_user` (
  `id`            INT          AUTO_INCREMENT PRIMARY KEY,
  `license`       VARCHAR(255) NOT NULL UNIQUE,           -- 사람 식별(라이선스). 1인 1행
  `gobun`         INT          NOT NULL UNIQUE,            -- 고번(불변), 전원 1~ 자동 순차
  `nickname`      VARCHAR(50)  DEFAULT NULL,               -- A-3 인트로에서 설정. 현재 NULL
  `is_verified`   TINYINT(1)   NOT NULL DEFAULT 0,         -- Phase C 디스코드 검증. 현재 0
  `discord_id`    VARCHAR(50)  DEFAULT NULL,               -- Phase C
  `created_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  -- license/gobun은 UNIQUE 제약이 곧 인덱스 → 별도 INDEX 불필요
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
