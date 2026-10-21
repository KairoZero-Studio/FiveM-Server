-- STEP 2-D 작업3: '관업 관리' 탭 + '온보딩 보내기' 기능
-- 탭: 플레이어 관리 | 차량 관리 | ★관업 관리(신규, sort 3)
-- 기능: 온보딩 보내기 — 킥과 동급(min_level 2), 대상 필요.
--   danger_level=0 (빨간 폰트 금지). NUI가 send_onboarding을 노랑 계열로 별도 표시 + 2차 확인 모달.
--   복구 가능(재온보딩)하므로 밴/돈주기 같은 danger(빨강)와 구분.

INSERT INTO `cookie_admin_category` (`category_key`, `label`, `tab_min_level`, `sort_order`) VALUES
('onboarding', '관업 관리', 2, 3)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `tab_min_level` = VALUES(`tab_min_level`), `sort_order` = VALUES(`sort_order`);

INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`)
SELECT id, 'send_onboarding', '온보딩 보내기', 2, 0, 1, 1
FROM `cookie_admin_category` WHERE `category_key` = 'onboarding'
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `min_level` = VALUES(`min_level`);
