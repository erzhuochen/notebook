# 数据库同步 — 钱包库（tp_db）接入拦截器

> 状态：已确认
> 模块及适用范围：manager-data；涉及 dev_db、tp_db 两个数据源及 PMM 同步链路；SG / EU / NA / JP 四个市场
> 负责人：
> 最后更新：2026-10-20

## 两分钟回忆

- **为什么做**：现有 `MybatisInterceptor` 已在 dev_db（panda_db）上实现跨市场数据库同步，钱包库（tp_db）的写操作不经过拦截器，`country_pay_type_map` 无法同步到 EU/NA/JP。
- **一句话方案**：在 `DataSourceConfigWallet` 上注册同一个拦截器实例，扩展接收端 `MiddleGroundController` 支持 tp_db；同时规定**同步表只允许在 SG 修改**，EU/NA/JP 修改时拦截器直接抛异常拒绝。
- **核心链路**：SG 钱包库写操作 → `MybatisInterceptor` 拦截 → 用 `pandaJdbcTemplate` 查 `sync_sql_config` → 有配置则调 `pmmClient.syncManagerSql` → PMM `sendCountryBody` 写死发往 EU/NA/JP → 各市场回调本地 `MiddleGroundController.sqlSync` → 取 `walletJdbcTemplate` 执行 SQL。
- **最容易忘的细节**：
  - PMM 的 `sendCountryBody` 写死发 EU/NA/JP，**只有从 SG 发起才是对的**；从 EU 发会发给自己、NA、JP，SG 收不到。所以加了"非 SG 禁止写同步表"的兜底（profile 为 `euprod`/`awsprod`/`jpprod` 时拦截）。
  - 同步按 `WHERE id = ?` 匹配，INSERT 去掉 id 靠自增 → **各市场表数据和 id、AUTO_INCREMENT 必须先对齐**，否则会改错行、删错行且不报错。
  - 上线顺序：兜底代码上线 → DBA 对齐数据 → 插 `sync_sql_config` 配置行（所有市场配置相同）。
- **当时的取舍**：选单主（只在 SG 写）而不是多主，因为"SQL 文本 + 自增 id"的同步机制做多主必然数据错乱；代价是 EU/NA/JP 运营要到 SG 后台改。拦截器在 `proceed()` 前同步，本地回滚不撤销远端，已接受。
- **当前待确认**：各环境 `sync_sql_config` 的 `is_cache`/`service_name`/`url` 值；上线前与运营确认 EU/NA/JP 没有人日常修改同步表。

## 1. 背景、目标与范围

### 背景
manager-data 通过 `MybatisInterceptor` 拦截 MyBatis 写操作，将 SQL 转发给 PMM，再分发到各市场实现数据库同步。该机制已在 dev_db（panda_db）和只读库上生效，但钱包库 `DataSourceConfigWallet` 未注册拦截器，tp_db 的写操作完全绕过同步链路。

排查过程中发现：PMM 只往 EU/NA/JP 发，且四个市场的 `sync_sql_config` 配置相同，因此在 EU/NA/JP 修改同步表时，数据会错发（发给自己 + 其他两个境外市场）且 SG 收不到——这个问题对现有 panda_db 同步表同样存在。

### 目标
- `country_pay_type_map` 在 SG 的增删改能同步到 EU/NA/JP 的 tp_db。
- 杜绝在 EU/NA/JP 修改同步表导致的数据不一致。

### 范围
- 包含：
  - `DataSourceConfigWallet` 注册拦截器、新增 `walletJdbcTemplate`
  - `MiddleGroundController` 接收端支持 tp_db
  - `MybatisInterceptor` URL 解析修复 + 非 SG 环境禁止写同步表
  - `country_pay_type_map` 数据对齐 + `sync_sql_config` 配置行
- 不包含：
  - 其他钱包表的同步
  - 接收端环境判断 `!SGPROD || !TEST` 恒为真的 bug
  - 事务提交后再同步的改造
  - panda_db 现有同步表的历史数据排查修复
  - 多主同步（EU/NA/JP 本地修改并同步回 SG）
- 涉及的系统或模块：manager-data（发送端 + 接收端）、PMM（转发）、四个市场的 manager-data。

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 运营在后台修改支付方式配置（`WalletCountryPayTypeController` edit/del） | tp_dbSqlSessionFactory 已注册拦截器 | `MybatisInterceptor.intercept` 触发，解析 SQL、表名、库名 | — | URL 无 `?` 时兼容处理 |
| 2 | 拦截器查同步配置 | — | 用 `pandaJdbcTemplate` 查 `sync_sql_config` | 查不到：跳过同步，本地写照常执行 | 查询异常被吞，不影响本地写 |
| 3 | 查到配置，判断当前环境 | — | profile 为 `euprod`/`awsprod`/`jpprod` → 抛 `SyncWriteForbiddenException` | 本地写**不执行**，前端收到 500，日志 `禁止修改同步表` | 只在 EU/NA/JP 生产拦截；SG、test、dev、local 放行 |
| 4 | SG 环境，拦截器调 PMM | — | `pmmClient.syncManagerSql(sqlSyncDTO)`，Feign 同步调用，在本地 SQL 执行**之前** | — | 调用失败只打日志，本地写照常执行，远端不同步 |
| 5 | 本地 SQL 执行 | — | `invocation.proceed()` | SG tp_db 数据更新 | 本地回滚不会撤销已发出的同步 |
| 6 | PMM 分发 | — | `sendCountryBody` 发往 EU、NA、JP | — | — |
| 7 | 各市场接收执行 | `JDBC_TEMPLATE_MAP` 中有 tp_db | `MiddleGroundController.sqlSync` 取 `walletJdbcTemplate` 执行 SQL | EU/NA/JP tp_db 数据同步 | `databaseName` 不含 panda_db/marketing_db/tp_db 则丢弃 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| R1 | MyBatis 执行 INSERT/UPDATE/DELETE | 操作的是 tp_db 或 dev_db | 拦截器触发，提取表名和库名 | 所有挂了拦截器的数据源 | 表名靠字符串截取，`INSERT...SELECT`、带库名前缀、UPDATE 小写 `set`、DELETE 无 WHERE 会解析失败，静默跳过 |
| R2 | R1 之后 | `sync_sql_config` 中有匹配的 `table_name + database_name` 且 `status = 1` | 进入 R3 判断 | 已配置的表 | 未配置的表跳过，不同步也不拦截 |
| R3 | R2 命中 | 当前 profile ∈ {`euprod`, `awsprod`, `jpprod`} | 抛 `SyncWriteForbiddenException`，阻止本地写和同步 | **所有**同步表（panda_db + tp_db） | 优先于 R4；SG/test/dev/local 不拦截 |
| R4 | R2 命中且 R3 未拦截 | — | 构建 SqlSyncDTO 调 PMM 同步 | SG 等允许写的环境 | 失败只打日志 |
| R5 | 接收端收到 sqlSyncDTO | `databaseName` 包含 `tp_db` | 用 `walletJdbcTemplate` 执行 SQL | EU/NA/JP manager-data | 改动前只支持 panda_db、marketing_db |

## 4. 数据字段

### sync_sql_config 配置行（插入各市场 panda_db，四个市场配置相同）

| 字段 | 值 | 说明 |
| --- | --- | --- |
| table_name | `country_pay_type_map` | 要同步的表 |
| database_name | `{env}_tp_db`（如 `dev1_tp_db`） | 各环境实际库名 |
| status | `1` | 1 生效，-1 失效 |
| is_cache | `0` 或 `1` | 是否在同步后触发缓存刷新 |
| service_name | 待确认 | is_cache=1 时使用 |
| url | 待确认 | is_cache=1 时使用 |

### 权限与操作
- `country_pay_type_map` 及所有同步表只能在 **SG 后台**修改；EU/NA/JP 后台修改会报错。

## 5. 边界与异常

- **跨市场**：PMM `sendCountryBody` 写死 EU/NA/JP。从 SG 发起正确；从 EU/NA/JP 发起会发给自己且 SG 收不到 → 已用 R3 拦截。
- **id 一致性**：UPDATE/DELETE 按 `WHERE id = ?`，INSERT 被 `handAutoInsertSql` 去掉 id 靠自增。各市场数据、id、AUTO_INCREMENT 不一致时会改错行、删错行且不报错 → 上线前 DBA 对齐。
- **事务回滚**：同步发生在本地 SQL 执行前，本地回滚不撤销远端。钱包库 6 处事务写操作均有此风险。已接受。
- **PMM 调用失败**：只打 error 日志，本地写照常执行，远端不同步，需人工补数据。
- **URL 无 `?`**：已修复。
- **拦截报错体验**：manager 无全局异常处理，EU/NA/JP 触发 R3 时前端看到通用 500，具体原因在日志。
- **接收端环境判断恒为真**：`!SGPROD || !TEST`，每个环境都执行同步 SQL。已知，不在本次范围。
- **历史数据**：此前 EU/NA/JP 若修改过 panda_db 同步表，SG 未收到、NA/JP 可能有重复 INSERT，数据可能已不一致。已知，单独处理。
- **插件顺序**：拦截器把 `invocation.getTarget()` 强转为 `CachingExecutor`，以后 tp_db 再加第二个插件会失败。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| SG 正常同步 | SG 环境；`sync_sql_config` 已有 `country_pay_type_map` 配置行 | 在 SG 后台新增/修改/删除一条支付方式 | 日志出现 `jdbc Url`、`表名 = country_pay_type_map,库名 = xxx_tp_db`、`sqlSyncDTO req`；EU/NA/JP tp_db 同步更新 |
| 无配置行 | `sync_sql_config` 无对应配置 | 同上 | 本地写成功，无 `sqlSyncDTO req` 日志，无报错 |
| EU 修改被拦截 | profile = `euprod`；已有配置行 | 在 EU 后台修改支付方式 | 请求失败，日志 `禁止修改同步表,表 country_pay_type_map 为跨市场同步表，只允许在 SG 修改`；EU 本地数据**未变**；无同步请求发出 |
| EU 修改非同步表 | profile = `euprod`；该表无配置行 | 在 EU 后台修改任意非同步表 | 正常写入，不受影响 |
| 测试环境不拦截 | profile = `test` / `dev1` | 修改同步表 | 正常写入并同步 |
| URL 无查询参数 | 钱包库 JDBC URL 不含 `?` | 在 SG 修改 | 正常解析库名并同步 |

## 7. 关键决定与待确认

### 关键决定

| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 复用同一个 MybatisInterceptor bean | 逻辑一致，库名从连接 URL 动态解析 | 放弃新建副本（避免逻辑分叉） |
| sync_sql_config 沿用 panda_db 中的同一张表 | 拦截器固定用 pandaJdbcTemplate 查配置；集中管理 | 放弃在 tp_db 另建配置表 |
| 接收端一起改，支持 tp_db | 接收端原来只认 panda_db/marketing_db，不改则钱包 SQL 被静默丢弃 | — |
| **单主：同步表只允许在 SG 修改** | PMM 只往 EU/NA/JP 发；"SQL 文本 + 自增 id"做多主必然 id 错位 | 放弃多主（B）和转发到 SG（C）；代价是境外运营要到 SG 后台操作 |
| 代码兜底，用黑名单 `euprod`/`awsprod`/`jpprod` | 只靠约定会有人误改且无报错；白名单会导致测试环境不能写 | 放弃纯约定；放弃白名单 |
| 兜底覆盖所有同步表（含 panda_db） | 四市场 sync_sql_config 相同，panda_db 同步表也有同样问题 | 改变了现有行为：境外不能再改 panda_db 同步表 |
| 拦截器抛异常，不做友好提示 | 正常不会触发，逐个 Controller 加判断覆盖不全 | 前端只看到 500 |
| 上线前对齐各市场 `country_pay_type_map` 数据 | 按 id 同步要求各市场 id 完全一致 | — |
| 事务提交前同步不改造 | 需求为"模仿现有形式" | 本地回滚与远端不一致 |
| 接收端环境判断 bug、历史数据不在本次处理 | 需确认原意 / 需 DBA 比对，与本次代码无关 | 延续现状 |

### 待确认

| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| `sync_sql_config` 配置行的 service_name、url、is_cache 值 | 没有配置行同步不会触发；is_cache=1 需正确的刷新地址 | 业务 / 运维 |
| EU/NA/JP 目前是否有人日常修改同步表 | 兜底上线后他们会直接报错 | 运营 |
| 接收端 `!SGPROD \|\| !TEST` 的原意 | 修复会改变现有同步的环境过滤 | 原始开发者 |

## 8. 改动文件

| 文件 | 改动内容 |
| --- | --- |
| `manager-data/.../config/DataSourceConfigWallet.java` | 注入 MybatisInterceptor，`setPlugins` 注册到 tp_dbSqlSessionFactory；新增 `walletJdbcTemplate` bean |
| `manager-data/.../intercept/MybatisInterceptor.java` | 修复 URL 无 `?` 时抛异常；新增 `SYNC_FORBIDDEN_PROFILES` 与 `SyncWriteForbiddenException`，EU/NA/JP 生产环境修改同步表时抛出（不被外层 catch 吞掉） |
| `manager-data/.../controller/MiddleGroundController.java` | 注入 `walletJdbcTemplate`，加 `TP_DB` 常量，注册进 `JDBC_TEMPLATE_MAP`，`Stream.of` 加入 `TP_DB` |

编译：manager-data 需用 **JDK 17** 编译（pom `java.version=17`）；用 JDK 25 编译时 lombok 1.18.32 不兼容，会报大量 getter 找不到。

### 上线步骤
1. 发布 manager-data（四个市场）。
2. 与运营确认 EU/NA/JP 不再在本地修改同步表。
3. DBA 以 SG 为准对齐 EU/NA/JP 的 `country_pay_type_map` 数据和 AUTO_INCREMENT。
4. 四个市场 panda_db 插入 `sync_sql_config` 配置行。
5. 在 SG 修改一条数据验证同步；在 EU 尝试修改验证被拦截。

## 9. 变更记录

| 日期 | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | --- | --- | --- |
| 2026-10-19 | 初始实现：钱包库注册拦截器、接收端支持 tp_db、URL 解析修复 | 钱包库接入数据库同步链路 | R1、R2、R4、R5 |
| 2026-10-20 | 新增非 SG 环境禁止修改同步表；补充数据对齐和上线步骤 | PMM 只往 EU/NA/JP 发，境外修改会错发且 SG 收不到 | 新增 R3；新增"EU 修改被拦截"等验收场景 |
