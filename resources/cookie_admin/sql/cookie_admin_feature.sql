CREATE TABLE IF NOT EXISTS `cookie_admin_category` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `category_key`  VARCHAR(40)  NOT NULL UNIQUE,
  `label`         VARCHAR(40)  NOT NULL,
  `tab_min_level` TINYINT      NOT NULL DEFAULT 1,
  `sort_order`    INT          NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS `cookie_admin_feature` (
  `id`              INT AUTO_INCREMENT PRIMARY KEY,
  `category_id`     INT          NOT NULL,
  `feature_key`     VARCHAR(40)  NOT NULL UNIQUE,
  `label`           VARCHAR(40)  NOT NULL,
  `min_level`       TINYINT      NOT NULL DEFAULT 1,
  `danger_level`    TINYINT      NOT NULL DEFAULT 0,
  `requires_target` TINYINT(1)   NOT NULL DEFAULT 1,
  `sort_order`      INT          NOT NULL DEFAULT 0,
  INDEX `idx_category` (`category_id`),
  INDEX `idx_min_level` (`min_level`),
  CONSTRAINT `fk_feature_category` FOREIGN KEY (`category_id`)
    REFERENCES `cookie_admin_category` (`id`) ON DELETE CASCADE
);

INSERT INTO `cookie_admin_category` (`category_key`, `label`, `tab_min_level`, `sort_order`) VALUES
('player',  '플레이어 관리', 1, 1),
('vehicle', '차량 관리',     1, 2)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`) VALUES
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'goto',      '끌고가기',   1, 0, 1, 1),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'tp',        '텔포',       1, 0, 1, 2),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'spectate',  '관전',       1, 0, 1, 3),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'heal',      '치료',       1, 0, 1, 4),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'revive',    '부활',       1, 0, 1, 5),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'cuff',      '수갑',       1, 0, 1, 6),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'jail',      '감옥',       1, 1, 1, 7),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'kick',      '킥',         2, 1, 1, 8),
((SELECT id FROM cookie_admin_category WHERE category_key='player'),  'ban',       '밴',         3, 2, 1, 9),
((SELECT id FROM cookie_admin_category WHERE category_key='vehicle'), 'veh_spawn', '스폰',  1, 0, 1, 1),
((SELECT id FROM cookie_admin_category WHERE category_key='vehicle'), 'veh_del',   '삭제',  1, 0, 1, 2),
((SELECT id FROM cookie_admin_category WHERE category_key='vehicle'), 'veh_fix',   '수리',  1, 0, 1, 3),
((SELECT id FROM cookie_admin_category WHERE category_key='vehicle'), 'veh_give',  '지급',  3, 0, 1, 4)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- 2026-08-25: 부상 치료 제거. 체력 회복과 즉시 부활만 유지.
DELETE FROM `cookie_admin_feature` WHERE `feature_key` IN ('heal', 'cure_wound');

INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`) VALUES
((SELECT id FROM cookie_admin_category WHERE category_key='player'), 'hp_restore', '체력 회복', 1, 0, 1, 4)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

UPDATE `cookie_admin_feature` SET `sort_order` = 5 WHERE `feature_key` = 'revive';

-- #25: cuff~ban 한 칸씩 밀어 revive(6)와의 동률 해소
UPDATE `cookie_admin_feature` SET `sort_order` = 7  WHERE `feature_key` = 'cuff';
UPDATE `cookie_admin_feature` SET `sort_order` = 8  WHERE `feature_key` = 'jail';
UPDATE `cookie_admin_feature` SET `sort_order` = 9  WHERE `feature_key` = 'kick';
UPDATE `cookie_admin_feature` SET `sort_order` = 10 WHERE `feature_key` = 'ban';

-- #2-D: 돈주기 (현금/계좌 송금) — danger 1(빨간 폰트 + 입력 모달), ADMIN(3) 이상
INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`)
SELECT id, 'give_money', '돈 주기', 3, 1, 1, 11
FROM `cookie_admin_category` WHERE `category_key` = 'player'
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- #긴급-2 B-1: 배고픔/수분 회복 — danger 0(일반), 누구나(1), 대상 필요
INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`)
SELECT id, 'cure_food', '배고픔 회복', 1, 0, 1, 12
FROM `cookie_admin_category` WHERE `category_key` = 'player'
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`)
SELECT id, 'cure_water', '수분 회복', 1, 0, 1, 13
FROM `cookie_admin_category` WHERE `category_key` = 'player'
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- 2026-08-26: 접속 플레이어 지급 기능을 '지급 관리' 탭으로 통합
INSERT INTO `cookie_admin_category` (`category_key`, `label`, `tab_min_level`, `sort_order`) VALUES
('grant', '지급 관리', 3, 3)
ON DUPLICATE KEY UPDATE `label`=VALUES(`label`), `tab_min_level`=VALUES(`tab_min_level`), `sort_order`=VALUES(`sort_order`);

SET @cookie_grant_cat := (SELECT id FROM cookie_admin_category WHERE category_key='grant' LIMIT 1);
INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`) VALUES
(@cookie_grant_cat, 'give_money', '돈 지급', 3, 0, 1, 1),
(@cookie_grant_cat, 'give_item', '아이템 지급', 3, 0, 1, 2),
(@cookie_grant_cat, 'veh_give', '차량 지급', 3, 0, 1, 3)
ON DUPLICATE KEY UPDATE `category_id`=VALUES(`category_id`), `label`=VALUES(`label`), `min_level`=VALUES(`min_level`), `danger_level`=VALUES(`danger_level`), `sort_order`=VALUES(`sort_order`);


-- V14.2.8: 지급 관리 > 아이템 압수
SET @cookie_grant_cat := (SELECT id FROM cookie_admin_category WHERE category_key='grant' LIMIT 1);
INSERT INTO `cookie_admin_feature` (`category_id`, `feature_key`, `label`, `min_level`, `danger_level`, `requires_target`, `sort_order`) VALUES
(@cookie_grant_cat, 'confiscate_item', '아이템 압수', 3, 1, 1, 4)
ON DUPLICATE KEY UPDATE `category_id`=VALUES(`category_id`), `label`=VALUES(`label`), `min_level`=VALUES(`min_level`), `danger_level`=VALUES(`danger_level`), `sort_order`=VALUES(`sort_order`);
