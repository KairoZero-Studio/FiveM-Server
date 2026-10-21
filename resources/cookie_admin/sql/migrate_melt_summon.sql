-- 2026-07-09: ① '끌고가기' → '소환하기' 개명  ② '녹임'(상태 초기화) 기능 추가
-- 적용: mysql -h 127.0.0.1 -P 3307 -u cookie -pcookie1234 Qbox_315020 < 이파일
--   (라벨은 DB가 진실 원천 — cookie_admin_feature.label)

UPDATE `cookie_admin_feature` SET `label` = '소환하기' WHERE `feature_key` = 'goto';

INSERT INTO `cookie_admin_feature`
  (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`)
VALUES
  ((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'melt', '녹임', 1, 0, 1, 12)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
