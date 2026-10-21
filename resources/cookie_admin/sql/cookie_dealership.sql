-- ============================================================
-- cookie_dealership : 전시장(차 판매소) 전시 목록 + 관리자 차량 로그
--   Phase 1 (2026-07-10). cookie_admin 부트 시 자동 생성(server/main.lua)되므로
--   이 파일은 참조/수동적용용. 멱등(IF NOT EXISTS).
-- ============================================================

-- 전시 목록: 관리자가 인게임에서 등록. 판매소 NUI가 브랜드 탭으로 렌더.
CREATE TABLE IF NOT EXISTS `cookie_dealership_vehicles` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `model`         VARCHAR(60)  NOT NULL,                 -- 스폰 코드 (qbx vehicles 키)
  `brand`         VARCHAR(40)  NOT NULL DEFAULT '기타',  -- 브랜드 탭 (제조사)
  `display_name`  VARCHAR(80)  NOT NULL,                 -- 표시 이름
  `price`         BIGINT       NOT NULL DEFAULT 0,       -- 판매 가격
  `category`      VARCHAR(30)  DEFAULT NULL,             -- 참고 카테고리(super/sedans...)
  `spec`          VARCHAR(120) DEFAULT NULL,             -- "중형·가솔린·오토" 등 스펙 문구
  `image`         LONGTEXT     DEFAULT NULL,             -- 일반 차고 차량 사진(data URI/URL)
  `sort_order`    INT          NOT NULL DEFAULT 0,       -- 탭 내 정렬
  `active`        TINYINT(1)   NOT NULL DEFAULT 1,       -- 노출 여부(0=숨김)
  `added_by`      VARCHAR(60)  DEFAULT NULL,             -- 등록 관리자명
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_model` (`model`),
  KEY `idx_brand_active` (`brand`, `active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 관리자 차량 행위 로그: 스폰(본인/대상), 전시 등록/삭제.
CREATE TABLE IF NOT EXISTS `cookie_admin_vehicle_log` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `admin_name`    VARCHAR(60)  DEFAULT NULL,
  `admin_license` VARCHAR(80)  DEFAULT NULL,
  `action`        VARCHAR(24)  NOT NULL,                 -- spawn_self / spawn_target / exhibit_add / exhibit_remove
  `model`         VARCHAR(60)  DEFAULT NULL,
  `target_name`   VARCHAR(60)  DEFAULT NULL,             -- 대상 스폰 시 대상명
  `detail`        VARCHAR(120) DEFAULT NULL,
  `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_admin`  (`admin_license`),
  KEY `idx_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
