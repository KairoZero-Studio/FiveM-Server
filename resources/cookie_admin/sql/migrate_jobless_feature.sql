-- 2026-07-19: 무직처리 기능 등록 (플레이어 관리 · 시민직 강제 해고)
--   ★ server/main.lua 부트 마이그레이션과 동일 내용(멱등). 수동 적용용 파일.
--   시민직(Config.CivilJobs) 대상을 강제로 무직(unemployed) 전환한다. 팩션원/무직은 서버 핸들러가 걸러냄.
--   danger 0 = 되돌릴 수 있음(대상이 NPC로 재취업 가능). requires_target 1.

INSERT INTO `cookie_admin_feature`
  (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`)
VALUES
  ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'jobless', '무직처리', 1, 0, 1, 14)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
