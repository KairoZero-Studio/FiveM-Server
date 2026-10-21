-- Phase 1-A: 존 정의 테이블. 동작=코드(TYPE_HANDLERS), 데이터=DB.
-- server.lua가 기동 시 이 CREATE를 그대로 실행하므로(부트스트랩) 이 파일은 참고/수동적용용이다.
--   ※ 이 코드베이스에는 원래 CREATE 부트스트랩 패턴이 없었다(cookie_admin은 sql/ 수동 적용).
--     존은 서버 없이는 아무것도 못 그리므로 여기서만 예외적으로 자동 생성한다.
--
-- 컬럼은 좌표 추출 도구 출력과 1:1이다.
--   box   : center_x/y/z + size_length/size_width/size_height + heading
--   sphere: center_x/y/z + radius
--
-- [중요] size_height 는 존의 '전체 두께'가 아니다. ox_lib box contains()가
--   glm_polygon_contains(polygon, coords, thickness/4) 를 쓰므로(imports/zones/shared.lua:342)
--   유효 수직 허용치는 대략 center_z ± size_height/4 다. 지면 ±10m 를 덮으려면 40.0 이 필요하다.

CREATE TABLE IF NOT EXISTS `cookie_zone` (
  `id`          INT AUTO_INCREMENT PRIMARY KEY,
  `type`        VARCHAR(32)  NOT NULL,           -- 'safezone' | 'fishing' | 'mining' | 'garage' 등 (client TYPE_HANDLERS 키)
  `shape`       VARCHAR(16)  NOT NULL,           -- 'box' | 'sphere'
  `center_x`    DOUBLE       NOT NULL,
  `center_y`    DOUBLE       NOT NULL,
  `center_z`    DOUBLE       NOT NULL,
  `size_length` DOUBLE       NULL,               -- box 전용
  `size_width`  DOUBLE       NULL,               -- box 전용
  `size_height` DOUBLE       NULL,               -- box 전용 (위 주석 참조)
  `radius`      DOUBLE       NULL,               -- sphere 전용
  `heading`     DOUBLE       NOT NULL DEFAULT 0, -- box 회전(도). sphere는 무시.
  `label`       VARCHAR(64)  NOT NULL,
  `fishing_type` VARCHAR(16)  NULL,              -- fishing 전용: normal | boat
  `fishing_region` VARCHAR(24) NULL,              -- fishing 전용: freshwater|coast|north|west|south|east|city|offshore
  `garage_kind` VARCHAR(16) NULL,               -- garage 전용: general | limited | faction
  `is_active`   TINYINT(1)   NOT NULL DEFAULT 1, -- 0 = 로드 제외(소프트 삭제)
  `teleport_x` DOUBLE NULL,
  `teleport_y` DOUBLE NULL,
  `teleport_z` DOUBLE NULL,
  `teleport_h` DOUBLE NULL,
  `created_by`  VARCHAR(64)  NULL,
  `created_at`  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_type` (`type`),
  INDEX `idx_active` (`is_active`)
);


-- 비콘 색상 (리소스 시작 시에도 자동 추가됨)
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_r` SMALLINT NULL;
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_g` SMALLINT NULL;
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_b` SMALLINT NULL;
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `beacon_a` SMALLINT NULL;

ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `garage_kind` VARCHAR(16) NULL;

ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_x` DOUBLE NULL;
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_y` DOUBLE NULL;
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_z` DOUBLE NULL;
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `teleport_h` DOUBLE NULL;

ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `fishing_region` VARCHAR(24) NULL;

-- V1.5.0 이동형(다각형) 범위 저장
ALTER TABLE `cookie_zone` ADD COLUMN IF NOT EXISTS `poly_points` LONGTEXT NULL;
-- shape='poly' 일 때 poly_points는 [{x,y,z}, ...] JSON 배열입니다.
