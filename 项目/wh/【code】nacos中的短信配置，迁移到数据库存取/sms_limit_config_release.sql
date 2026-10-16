-- =====================================================================
-- 短信条数拦截配置：nacos -> 管理台  上线 SQL
-- 执行顺序：① 建表(panda_db) → ② 导入数据(panda_db) → ③ 菜单权限(管理台权限库) → 上线 manager → 刷新缓存 → 上线 wt-notification
-- =====================================================================


-- ① 建表：panda_db（wt-notification 与 manager-data 主数据源 dev_db 所连的库）
CREATE TABLE `sms_limit_config` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `area_code`   VARCHAR(16)  NOT NULL COMMENT '区号，如 +86；DEFAULT 为默认配置',
  `day_limit`   INT          DEFAULT NULL COMMENT '每天条数上限；NULL 继承 DEFAULT，0 禁发',
  `hour_limit`  INT          DEFAULT NULL COMMENT '每小时条数上限；NULL 继承 DEFAULT，0 禁发',
  `status`      TINYINT      NOT NULL DEFAULT 1 COMMENT '1 启用 0 停用（停用后回落 DEFAULT）',
  `remark`      VARCHAR(255) DEFAULT NULL COMMENT '备注',
  `create_time` DATETIME     DEFAULT NULL COMMENT '创建时间',
  `update_time` DATETIME     DEFAULT NULL COMMENT '更新时间',
  `update_by`   VARCHAR(64)  DEFAULT NULL COMMENT '更新人',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_area_code` (`area_code`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '短信条数拦截配置';


-- ② 导入数据：按各环境 nacos 当前值填写（示例，勿直接执行）
--   sms.optLimit / sms.hourOptLimit           -> DEFAULT 行（两列必填）
--   sms.optLimitJson / sms.hourOptLimitJson    -> 每个区号一行，只配了其中一项的另一列留 NULL
--   注意：区号必须带 "+"。旧默认值里的 "44" 从未匹配上 "+44"，导入时请确认是否按 "+44" 生效
-- INSERT INTO sms_limit_config (area_code, day_limit, hour_limit, status, remark, create_time, update_time, update_by) VALUES
--   ('DEFAULT', 20000, 500,  1, '默认配置', NOW(), NOW(), 'init'),
--   ('+94',     1000,  200,  1, '',         NOW(), NOW(), 'init');


-- ③ 菜单与权限：管理台权限库（manager-shiro 的 shiro_permission 所在库）
-- 1. 执行前检查：以下两条查询都应返回 0 行，否则说明 code 或权限名已被占用
SELECT * FROM shiro_permission WHERE shiro_code IN ('110-19', '110-19-1', '110-19-2', '110-19-3');
SELECT * FROM shiro_permission WHERE shiro_name LIKE 'root:smsLimitConfig%';

-- 2. 插入：主键交给自增生成，避免与生产环境已有 id 冲突
INSERT INTO shiro_permission (shiro_code, shiro_name, name, parent, node_name, url, level, sublevel, type, icon) VALUES
  ('110-19',   'root:smsLimitConfig:list',    '短信条数拦截配置',     'messageCenter',  'smsLimitConfig',        '/messageCenter/smsLimitConfig',                       2, 1, 1, 'layui-icon-auz'),
  ('110-19-1', 'root:smsLimitConfig:edit',    '短信条数拦截配置编辑', 'smsLimitConfig', 'smsLimitConfigEdit',    '/messageCenter/smsLimitConfig/smsLimitConfigEdit',    3, 0, 1, 'layui-icon-fire'),
  ('110-19-2', 'root:smsLimitConfig:refresh', '短信条数拦截配置刷新', 'smsLimitConfig', 'smsLimitConfigRefresh', '/messageCenter/smsLimitConfig/smsLimitConfigRefresh', 3, 0, 1, 'layui-icon-fire'),
  ('110-19-3', 'root:smsLimitConfig:delete',  '短信条数拦截配置删除', 'smsLimitConfig', 'smsLimitConfigDelete',  '/messageCenter/smsLimitConfig/smsLimitConfigDelete',  3, 0, 1, 'layui-icon-fire');

-- 3. 执行后核对：应返回 4 行
SELECT * FROM shiro_permission WHERE shiro_name LIKE 'root:smsLimitConfig%' ORDER BY shiro_permission_id;