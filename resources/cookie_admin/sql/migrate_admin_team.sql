-- 2026-07-11: 관리자 팀 축 도입 (팩션 시스템 Phase 1)
-- LV2~3 관리자를 단일 팀으로 전문화. LV4~5는 팀 무관 전권. LV1은 배정 불가(admin_team NULL).
-- 서버 부트 시 server/main.lua의 멱등 마이그레이션 스레드가 동일 내용을 자동 적용한다(수동 실행 불필요).

ALTER TABLE `cookie_admin`
  ADD COLUMN IF NOT EXISTS `admin_team` VARCHAR(32) NULL AFTER `admin_level`;

-- 각 탭(카테고리)의 소속 팀.
--   'general' = 팀 제한 없음(기존 동작 = min_level 게이트만, 모든 관리자 공통).
--   전문팀(faction/build/skin ...) = LV4+ 또는 배정팀 일치 시에만 노출.
ALTER TABLE `cookie_admin_category`
  ADD COLUMN IF NOT EXISTS `team_key` VARCHAR(32) NOT NULL DEFAULT 'general' AFTER `tab_min_level`;
