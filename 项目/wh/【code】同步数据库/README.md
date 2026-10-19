# 数据库同步 — 钱包库（tp_db）接入拦截器

> 状态：已确认
> 模块及适用范围：manager-data；涉及 dev_db、tp_db 两个数据源及 PMM 同步链路
> 负责人：
> 最后更新：2026-10-19

## 两分钟回忆

- **为什么做**：现有 `MybatisInterceptor` 已在 dev_db（panda_db）上实现跨市场数据库同步，钱包库（tp_db）的写操作不经过拦截器，`country_pay_type_map` 等配置表无法同步到 EU/NA/JP。
- **一句话方案**：在 `DataSourceConfigWallet` 上注册同一个拦截器实例，同时扩展接收端 `MiddleGroundController` 使其能对 tp_db 执行同步 SQL。
- **核心链路**：钱包库写操作 → `MybatisInterceptor.intercept` 拦截 → 用 `pandaJdbcTemplate` 查 `sync_sql_config`（`database_name = xxx_tp_db`，`table_name = country_pay_type_map`） → 有配置则调 `pmmClient.syncManagerSql` → PMM 分发到 EU/NA/JP → 各市场回调本地 `MiddleGroundController.sqlSync` → `JDBC_TEMPLATE_MAP` 取 `walletJdbcTemplate` 执行 SQL。
- **最容易忘的细节**：同步配置行要手动插到各环境 panda_db 的 `sync_sql_config` 表里，`database_name` 填该环境实际库名（如 `dev1_tp_db`）；没有这行数据，拦截器触发后会静默跳过，不报错。
- **当时的取舍**：拦截器在 `invocation.proceed()` 之前同步调用 PMM，本地事务回滚不会撤销已下发的同步 SQL；钱包库有 6 处事务写操作，这个风险已知、接受，后续单独排期处理。接收端环境判断 `!SGPROD || !TEST` 恒为真的 bug 也已知，不在本次范围，单独记录。
- **当前待确认**：各环境 `sync_sql_config` 配置行由谁插入、`is_cache`/`service_name`/`url` 的具体值。

## 1. 背景、目标与范围

### 背景
manager-data 通过 `MybatisInterceptor` 拦截 MyBatis 写操作，将 SQL 转发给 PMM，再分发到各市场实现数据库同步。该机制已在 dev_db（panda_db）和只读库上生效，但钱包库 `DataSourceConfigWallet` 未注册拦截器，tp_db 的写操作完全绕过同步链路。

### 目标
`country_pay_type_map` 的增删改操作能通过现有 PMM 链路同步到 EU/NA/JP 各市场的 tp_db。

### 范围
- 包含：`DataSourceConfigWallet` 注册拦截器；`MiddleGroundController` 接收端支持 tp_db；`MybatisInterceptor` URL 解析修复；`sync_sql_config` 中 `country_pay_type_map` 配置行。
- 不包含：其他钱包表的同步；接收端环境判断 bug 修复；事务提交后同步的改造。
- 涉及的系统或模块：manager-data（发送端 + 接收端）、PMM（转发）、EU/NA/JP 各市场 manager-data（接收执行）。

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 后台操作触发钱包库写操作 | tp_dbSqlSessionFactory 已注册拦截器 | MybatisInterceptor.intercept 触发，解析 SQL 和库名 | — | URL 无 `?` 时兼容处理，不抛异常 |
| 2 | 拦截器查同步配置 | panda_db sync_sql_config 有该表的配置行 | 用 pandaJdbcTemplate 查 sync_sql_config | 查到则继续；查不到则跳过同步，本地写照常执行 | 查询异常被捕获，不影响本地写 |
| 3 | 拦截器调 PMM | 上一步查到配置 | pmmClient.syncManagerSql(sqlSyncDTO)，Feign 同步调用 | — | 调用失败只打日志，不影响本地写 |
| 4 | PMM 分发 | — | sendCountryBody 将 SQL 发往 EU、NA、JP | — | — |
| 5 | 各市场接收执行 | JDBC_TEMPLATE_MAP 中有 tp_db | MiddleGroundController.sqlSync 取 walletJdbcTemplate 执行 SQL | 各市场 tp_db 数据同步 | databaseName 不含 tp_db 则被丢弃 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| R1 | MyBatis 执行 INSERT/UPDATE/DELETE | 操作的是 tp_db | 拦截器触发，提取表名和库名 | 所有 mapperWallet 下的写操作 | 表名提取依赖固定字符串截取，`INSERT...SELECT`、带库名前缀的表名会解析失败，静默跳过 |
| R2 | 拦截器命中 | `sync_sql_config` 中存在匹配的 `table_name + database_name`，且 `status = 1` | 构建 SqlSyncDTO 并调用 PMM 同步 | 已配置的表 | 未配置的表静默跳过 |
| R3 | PMM 接收到 sqlSyncDTO | `databaseName` 包含 `tp_db` | 从 `JDBC_TEMPLATE_MAP` 取 `walletJdbcTemplate` 执行 SQL | 各市场 manager-data 接收端 | 改动前只支持 panda_db 和 marketing_db，tp_db 会被丢弃 |

## 4. 数据字段

### sync_sql_config 配置行（需手动插入各环境 panda_db）

| 字段 | 值 | 说明 |
| --- | --- | --- |
| table_name | `country_pay_type_map` | 要同步的表 |
| database_name | `{env}_tp_db`（如 `dev1_tp_db`） | 各环境实际库名 |
| status | `1` | 1 生效，-1 失效 |
| is_cache | `0` 或 `1` | 是否在同步后触发缓存刷新 |
| service_name | 待确认 | is_cache=1 时使用 |
| url | 待确认 | is_cache=1 时使用 |

## 5. 边界与异常

- **事务回滚不一致**：拦截器在 `invocation.proceed()` 前调 PMM，本地回滚不会通知远端撤销。钱包库有 6 处事务写操作（`WalletServiceImpl` 3 处显式指定，另有 3 处走 `@Primary` 默认事务管理器），均存在此风险。已接受，后续排期。
- **URL 无 `?`**：已修复，兼容没有查询参数的 JDBC URL。
- **PMM 调用失败**：只打 error 日志，本地写照常执行，远端不同步。需人工补数据或重新触发。
- **接收端环境判断恒为真**：`!SGPROD || !TEST` 恒为真，每个环境都会执行同步 SQL。原意应为 `&&`，已知 bug，不在本次范围。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| 正常同步 | panda_db sync_sql_config 已有 country_pay_type_map 配置行 | 在后台对 country_pay_type_map 执行一次写操作 | 日志出现 `jdbc Url`、`表名 = country_pay_type_map,库名 = xxx_tp_db`、`sqlSyncDTO req`；PMM 收到请求；各市场 tp_db 数据同步 |
| 无配置行 | panda_db sync_sql_config 无对应配置行 | 同上 | 本地写成功，日志无 sqlSyncDTO，无报错 |
| URL 无查询参数 | 钱包库 JDBC URL 不含 `?` | 同上 | 拦截器正常解析库名，不抛异常 |
| 接收端 databaseName 不匹配 | sqlSyncDTO.databaseName 不含 tp_db | 直接调 /middleGround/syncConfiguration | SQL 被丢弃，返回 true，无异常 |

## 7. 关键决定与待确认

### 关键决定

| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 复用同一个 MybatisInterceptor bean，不新建钱包专用拦截器 | 逻辑完全一致，库名从连接 URL 动态解析，不绑定具体数据源 | 放弃新建副本（避免两边逻辑分叉） |
| sync_sql_config 沿用 panda_db 中的同一张表 | 拦截器已固定用 pandaJdbcTemplate 查配置；集中管理优于分散 | 放弃在 tp_db 另建配置表 |
| 接收端环境判断 bug 不在本次修复 | 改动会影响现有 panda_db 同步行为，需先确认原意 | 已接受：各环境均执行同步 SQL 的现状延续 |
| 事务提交前同步不改造 | 本次需求明确为"模仿现有形式" | 已接受：本地回滚与远端不一致的风险 |

### 待确认

| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| 各环境 sync_sql_config 配置行的 service_name、url、is_cache 值 | 没有配置行同步不会触发；is_cache=1 时需要正确的缓存刷新地址 | 业务 / 运维 |
| 接收端环境判断 `!SGPROD \|\| !TEST` 的原意 | 修复会改变现有 panda_db 同步的环境过滤行为 | 原始开发者 |

## 8. 改动文件

| 文件 | 改动内容 |
| --- | --- |
| [DataSourceConfigWallet.java](../../../../workspace/wh/manager/manager-data/src/main/java/com/wotransfer/dataManagement/config/DataSourceConfigWallet.java) | 注入 MybatisInterceptor，setPlugins 注册到 tp_dbSqlSessionFactory，新增 walletJdbcTemplate bean |
| [MybatisInterceptor.java](../../../../workspace/wh/manager/manager-data/src/main/java/com/wotransfer/dataManagement/intercept/MybatisInterceptor.java) | 修复 URL 无 `?` 时 indexOf 返回 -1 导致 substring 抛异常的问题 |
| [MiddleGroundController.java](../../../../workspace/wh/manager/manager-data/src/main/java/com/wotransfer/dataManagement/controller/MiddleGroundController.java) | 注入 walletJdbcTemplate，加 TP_DB 常量，注册进 JDBC_TEMPLATE_MAP，Stream.of 加入 TP_DB |

## 9. 变更记录

| 日期 | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | --- | --- | --- |
| 2026-10-19 | 初始实现 | 钱包库接入数据库同步链路 | R1、R2、R3 全部新增 |
