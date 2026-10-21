# [cze-4995] nacos 中的短信配置迁移到数据库存取

> 状态：已确认（代码已完成，未上线）
> 模块及适用范围：wt-notification（OTP 短信发送拦截）、管理台 manager-data / manager-shiro / manager-website（消息中心）；全区域（各区域部署独立，各自建表导数）
> 负责人：cze
> 最后更新：2026-10-16

## 两分钟回忆

- **为什么做**：系统经常遭受各地的短信攻击，开发要按情况随时调整 OTP 短信条数拦截阈值。这些阈值原来放在 nacos 里，调整不方便。
- **一句话方案**：nacos 的 4 个阈值配置（`sms.optLimit`、`sms.optLimitJson`、`sms.hourOptLimit`、`sms.hourOptLimitJson`）迁到 panda_db 新表 `sms_limit_config`，每个区号一行。管理台「消息中心 → 短信条数拦截配置」负责增删改，保存后全量刷新到 Redis hash。wt-notification 发 OTP 前读 hash 判断阈值，计数改为 Lua 原子执行。
- **核心链路**：运营在管理台改阈值 → manager-data 写库 → 全量重建 `WT:SMS:OTP_LIMIT:DAY` / `WT:SMS:OTP_LIMIT:HOUR` → 上游投递 `wt_notify_otp_sms_queue` → `NotifyDoController.otpSms` → `OtpSmsLimiter.acquire(区号)` → 没超限就计数并发送；超限则不发送，记 WARN 日志并给告警号码发短信。
- **最容易忘的细节**：
  - 区号必须带 `+`（如 `+86`），默认配置那一行的区号固定写 `DEFAULT`。旧默认值里的 `"44"` 没带 `+`，一直匹配不上 `+44`，英国实际走的是全局默认值。
  - 上限为 `NULL` 表示继承 DEFAULT，为 `0` 表示禁发。停用某个区号就回落到 DEFAULT。
  - DEFAULT 行两个上限都必填，不能停用也不能删除。
  - 计数 key **沿用旧格式** `OTP_LIMIT_{yyyyMMdd}{区号}` 和 `OTP_LIMIT_{yyyyMMddHH}{区号}`，所以上线时计数不归零。
  - notification 只看 hash 里有没有 `DEFAULT` 来判断缓存是否缺失；某个区号没配置是正常情况。
  - 只拦 `otpSms` 队列，`otpSmsHuaWei`（glc 登录用的华为渠道）和普通短信 `sms()` 都不拦。
  - 告警接收号码 `sms.optLimitNotify` **仍留在 nacos**。
  - manager-data 的 Service **不能加 `@Transactional`**：它的 RedisTemplate 开启了事务支持，事务里的 Redis 写会延迟到事务提交后才执行。
  - 本机编译要用 JDK 17。默认的 JDK 25 和项目里的 Lombok 不兼容，会报一堆 getter 找不到。
- **当时的取舍**：
  - 表建在 panda_db（notification 自己的库），这样缓存缺失时 notification 能直接回源查库，不依赖管理台服务是否可用。manager-data 的主数据源 dev_db 本来就连 panda_db，不需要新增数据源。
  - Redis 可能是集群，所以日计数和小时计数各用一个只操作单 key 的原子脚本：先日后小时，小时超限时回退日计数。只有并发请求恰好卡在阈值边界时才可能有 1 条误差，可以接受。
  - 已有计数遇到修改阈值时**不清零**。阈值调到已发条数以下时，该区号立即被拦。
  - 不做小时上限不能大于日上限的校验。
- **当前待确认**：无（上线前需核对 Redis 配置，见第 5 节）

## 1. 背景、目标与范围

### 背景
系统经常遭受各地的短信攻击请求，开发人员要根据情况调整 OTP 短信的条数拦截配置。配置原来在 nacos，调整不便，所以统一整理到数据库，由管理台管理。

原来的调用代码（`NotifyDoController`）：
```java
private Integer queryAreaDayLimit(String areaCode) {
    JSONObject limitJson = JSONObject.parseObject(smsConfig.getOptLimitJson());
    if (limitJson.containsKey(areaCode)) {
        return limitJson.getInteger(areaCode);
    } else {
        return smsConfig.getOptLimit();
    }
}
// queryAreaHourLimit 同理，读 hourOptLimitJson / hourOptLimit
```

原逻辑有以下问题，本次一并修复：
- 先 get 再 set，计数不是原子操作，并发时会多放行。
- key 不存在时第一条写的是 0，实际放行了 limit+1 条。
- 先给日计数 +1 再查小时限额，被小时限额拦下的那条也算进了日计数。
- 告警 key `OTP_LIMIT_NOTIFY_DATE*` 没有设置 TTL，会一直累积。
- 小时超限的告警文案也写着"单日"。

### 目标
1. 短信条数拦截配置从 nacos 迁到管理台（消息中心目录下），可以按区号配置每天和每小时上限。管理台新增、修改、删除后自动刷新缓存，也可以手动刷新。
2. wt-notification 发送 OTP 短信前，直接按区号读缓存里的上限做判断。

### 范围
- 包含：
  - 新表 `sms_limit_config`
  - 管理台列表、新增、修改、删除、刷新缓存
  - wt-notification `otpSms` 的阈值读取与计数改造
  - 告警 key 加 TTL、告警文案区分"单日 / 单小时"
- 不包含：
  - `otpSmsHuaWei`、`sms()` 的拦截
  - 告警号码 `optLimitNotify` 的迁移
  - 清零某个区号当前计数的功能
  - 按手机号、IP 维度的拦截（计数维度仍只有区号）
- 涉及的系统或模块：
  - wt-notification：`OtpSmsLimiter`、`NotifyDoController`、`SmsConfig`
  - manager-data：`SmsLimitConfig*`
  - manager-shiro：`SmsLimitConfigClient`、`SmsLimitConfigController`
  - manager-website：`messageCenter/smsLimitConfig*`
  - 数据库：panda_db（业务表）、管理台权限库（`shiro_permission`）

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 运营在「短信条数拦截配置」点新增或修改并提交 | 有 `root:smsLimitConfig:edit` 权限 | shiro 校验权限 → Feign 转发 → manager-data 校验区号格式、上限 ≥ 0、DEFAULT 规则后写库 | 表里新增或更新一行，`update_by` 取请求头 `mg-name` | 校验不通过时返回提示，不写库 |
| 2 | 第 1 步写库成功后自动执行 | 库里有已启用的 DEFAULT 行，且两个上限都不为空 | 全量读表，只取已启用且不为 NULL 的值。先写临时 key `{WT:SMS:OTP_LIMIT:DAY}:TMP:uuid`，再 `RENAME` 成正式 key（小时同理） | Redis 的两个 hash 更新，无 TTL | 没有 DEFAULT 时提示"缓存未刷新"；Redis 失败时提示"保存成功，但缓存刷新失败" |
| 3 | 运营点删除（二次确认），或点"刷新缓存" | 分别需要 `delete` / `refresh` 权限 | 删除后同样全量刷新 | 该区号回落到 DEFAULT | DEFAULT 行不能删除 |
| 4 | 用户请求验证码，上游（wt-web、glc、tp）投递 MQ | — | `otpSms` 消费消息，清洗手机号 | — | — |
| 5 | `OtpSmsLimiter.acquire` | — | 区号归一化 → `HMGET` 两个 hash 的 `DEFAULT` 和该区号 → 得到日上限、小时上限 | — | 缺少 DEFAULT 时回源查库，用 `RENAMENX` 回填缓存（正式 key 已存在就不覆盖）；库里也没有时用硬编码的 500 / 200 并打 ERROR；回源结果在本地保留 60 秒 |
| 6 | 计数 | — | 日 key 执行脚本：当前值 ≥ 上限就拒绝，否则 `INCR` 并 `EXPIRE 86400`。然后小时 key 同样处理，`EXPIRE 3600` | 两个计数各加 1，继续选渠道发送 | 日超限：直接拦截。小时超限：回退日计数后拦截 |
| 7 | 被拦截 | — | 打 WARN 日志（区号、维度、当前条数、上限）→ `sendWarnSms` | 给 `optLimitNotify` 里的号码发告警短信 | 同一类型（日期或小时 + 区号）当天只告警一次，告警 key 的 TTL 为 25 小时 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| R1 上限取值 | 每条 OTP 发送前 | 按归一化后的区号匹配 hash field | 有该区号的值就用它，否则用 DEFAULT 的值 | 仅 `otpSms` | 某一项为 NULL 或该区号已停用时，这一项用 DEFAULT |
| R2 日拦截 | 每条 OTP 发送前 | `OTP_LIMIT_{yyyyMMdd}{区号}` 的当前值 ≥ 日上限 | 不发送、不计数，记 WARN，发告警 | 同上 | 上限为 0 时一条都不发，也不会创建计数 key |
| R3 小时拦截 | 日拦截通过之后 | `OTP_LIMIT_{yyyyMMddHH}{区号}` 的当前值 ≥ 小时上限 | 不发送，回退日计数，记 WARN，发告警 | 同上 | — |
| R4 缓存缺失兜底 | R1 读 hash 时 | 任一 hash 里没有 `DEFAULT` 这个 field | 查库并用 `RENAMENX` 回填缓存，不覆盖已存在的 key；库里也没有 DEFAULT 就用 500 / 200 | 同上 | 回源结果本地缓存 60 秒，避免每条短信都打库 |
| R5 区号规范 | 管理台保存时，以及 notification 读取时 | 去掉空白；没有 `+` 就补上；必须匹配 `\+\d{1,6}`，`DEFAULT` 不区分大小写 | 管理台：格式不对就拒绝保存。notification：格式不对就只用 DEFAULT | 两端 | 计数 key 仍用上游传来的原始区号，保证和线上已有 key 一致 |
| R6 DEFAULT 保护 | 管理台保存、删除时 | 区号为 DEFAULT | 两个上限必填，不能停用，不能删除 | 管理台 | — |
| R7 告警去重 | 被拦截时 | `OTP_LIMIT_NOTIFY_DATE{type}` 的值等于当天日期 | 跳过，不再告警 | notification | type 为"日期 + 区号"或"小时 + 区号"，日、小时分开去重 |

## 4. 页面、字段与权限

### 页面交互
- 入口：消息中心 → 短信条数拦截配置（`/messageCenter/smsLimitConfig`）。
- 搜索：区号（`86`、`+86` 都可以）、状态（全部 / 启用 / 停用）。
- 列表列：编号、区号、每天上限、每小时上限、状态、备注、更新人、更新时间。上限为空时灰字显示"继承DEFAULT"，为 0 时红字显示"0（禁发）"。
- 工具箱：新增；刷新缓存（弹确认框"确定刷新短信条数拦截配置缓存吗？"）。
- 行操作：修改；删除（确认文案："确定删除区号 xx 的拦截配置吗？删除后该区号将使用 DEFAULT 配置。"）。DEFAULT 行不显示删除按钮。
- 编辑弹窗：
  - 区号：新增时填写，修改时只读。
  - 每天上限、每小时上限：只能填非负整数，留空表示继承 DEFAULT。
  - 状态：启用 / 停用，DEFAULT 行的"停用"选项禁用。
  - 备注。

### 数据字段（panda_db.sms_limit_config）
| 字段 | 来源 | 何时记录或更新 | 用途 | 特殊说明 |
| --- | --- | --- | --- | --- |
| area_code | 管理台录入 | 新增时 | 匹配区号 | 唯一索引 `uk_area_code`；新增后不能修改；`DEFAULT` 表示默认配置 |
| day_limit | 管理台录入 | 新增、修改 | 每天上限 | NULL 表示继承 DEFAULT，0 表示禁发 |
| hour_limit | 管理台录入 | 新增、修改 | 每小时上限 | 同上 |
| status | 管理台录入 | 新增、修改 | 1 启用，0 停用 | 停用后回落 DEFAULT |
| remark | 管理台录入 | 新增、修改 | 备注 | — |
| create_time / update_time | 系统 | 新增、修改 | 审计 | — |
| update_by | 请求头 `mg-name`（URL 解码） | 新增、修改 | 审计 | — |

### Redis
| key | 类型 | 写入方 | 读取方 | 说明 |
| --- | --- | --- | --- | --- |
| `WT:SMS:OTP_LIMIT:DAY` / `WT:SMS:OTP_LIMIT:HOUR` | hash，field 为区号或 DEFAULT，value 为 Integer | manager-data（notification 回源时也会写） | notification | 无 TTL。value 只能存 Integer，不能存 POJO，否则会带上 `@class`，跨服务反序列化失败 |
| `OTP_LIMIT_{yyyyMMdd}{区号}` / `OTP_LIMIT_{yyyyMMddHH}{区号}` | String（纯数字） | notification 的 Lua 脚本 | notification | 每次计数后 `EXPIRE` 86400 / 3600 |
| `OTP_LIMIT_NOTIFY_DATE{type}` | String | notification | notification | TTL 25 小时 |

### 权限与操作记录
- 权限标识：`root:smsLimitConfig:list`（菜单）、`:edit`、`:refresh`、`:delete`。
- 权限数据（`shiro_code` 为 110-19 系列）：

| shiro_code | shiro_name | name | parent | node_name | level |
| --- | --- | --- | --- | --- | --- |
| 110-19 | root:smsLimitConfig:list | 短信条数拦截配置 | messageCenter | smsLimitConfig | 2 |
| 110-19-1 | root:smsLimitConfig:edit | 短信条数拦截配置编辑 | smsLimitConfig | smsLimitConfigEdit | 3 |
| 110-19-2 | root:smsLimitConfig:refresh | 短信条数拦截配置刷新 | smsLimitConfig | smsLimitConfigRefresh | 3 |
| 110-19-3 | root:smsLimitConfig:delete | 短信条数拦截配置删除 | smsLimitConfig | smsLimitConfigDelete | 3 |

- 插入时**不写主键**，交给自增，避免和生产环境已有 id 冲突。执行前先查一下 `shiro_code` 和 `shiro_name` 是否已被占用。角色授权在管理台「角色管理」里勾选。
- 操作记录：shiro 的 edit、delete、refresh 三个接口加了 `@AccessLogging`；表上另有 `update_by` / `update_time`。

## 5. 边界与异常

- **跨区域**：prod、eu、sg 等各区域各自建表、导数、刷新缓存。
- **Redis 实例**：manager-data 用 `manager-redis.properties`，notification 用 `redis.properties`。从间接证据看是同一个实例（`LANG_DICT_MSG` 也是这样跨服务共享的），**上线前需要到 nacos 逐个环境核对 host 和 database**。
- **数据缺失**：
  - hash 里缺少 DEFAULT：notification 回源查库，并用 `RENAMENX` 回填，正式 key 已存在时不覆盖。
  - 库里也没有 DEFAULT：用 500 / 200 并打 ERROR。
  - 查库异常：同样走硬编码默认值，不会因此拒发。
- **Redis 不可用**：计数脚本抛出的异常会被 `otpSms` 外层 catch 吞掉，这条短信不发，MQ 消息照常确认（和改造前一致）。
- **修改阈值**：即时生效，已有计数不清零。
- **刷新的中间状态**：两个 hash 是分别 `RENAME` 的，中间有毫秒级窗口，可能读到"日上限是新值、小时上限是旧值"，可以接受。
- **回源和刷新并发**：notification 回源查到的是旧快照，如果管理台恰好刚刷新完，用 `RENAME` 回填会把新配置覆盖回去；hash 又没有 TTL，之后也不会再回源，于是旧值一直生效（比如紧急设的禁发静默失效）。所以 notification 回填用 `RENAMENX`，只在 key 不存在时写入；管理台是配置的权威来源，刷新仍用无条件 `RENAME`，总能覆盖 notification 的回填。
- **多个管理员同时刷新**（未修复）：先读库的刷新可能后写入，用旧快照覆盖新配置。概率很低，但触发场景和攻击时的紧急封禁重叠。可以在 `refresh()` 外加 Redis 锁来修复（key 为 `WT:SMS:OTP_LIMIT:REFRESH_LOCK`，带 TTL，释放时用 Lua 比对 value），已验证方案可行，但对应的提交已回滚，暂不上线。
- **集群兼容**：临时 key 用 hash tag `{正式key}:TMP:uuid`，保证在集群模式下和正式 key 落在同一个 slot。
- **上线当天**：旧计数 key 里的值比实际发送数少 1（旧逻辑第一条记为 0），当天会多放行 1 条，第二天恢复正常。
- **`evalMethod` 传参**：参数必须是数字（Integer/Long）。它用 value 序列化器序列化参数，传 String 会带上引号，Lua 里 `tonumber` 得到 nil。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| 正常放行 | DEFAULT 为 20000/500，`+86` 没有配置 | 发一条 `+86` 的 OTP | 发送成功，日、小时计数各加 1，TTL 分别为 86400 / 3600 |
| 精确放行 limit 条 | `+94` 日上限为 2 | 连续发 3 条 | 前 2 条发送，第 3 条被拦截，WARN 日志里维度为"每天" |
| 禁发 | `+94` 日上限为 0 | 发 1 条 | 被拦截，不创建计数 key |
| 小时拦截回退 | 小时上限为 1，日上限足够 | 同一小时连发 2 条 | 第 2 条被拦截，日计数回到 1，告警文案为"单小时" |
| 继承 | `+44` 的日上限为 NULL，小时上限为 100 | 发送 | 日上限用 DEFAULT，小时上限为 100 |
| 停用 | `+44` 已停用 | 发送 | 两个上限都用 DEFAULT |
| 区号录入 | 新增时区号填 `86` | 保存 | 存为 `+86`；填 `abc` 时提示格式不正确 |
| DEFAULT 保护 | — | 删除或停用 DEFAULT 行，或把它的上限清空 | 都被拒绝 |
| 缓存缺失 | 手动删掉两个 hash | 发 1 条 OTP | 从库里回填 hash，日志记 WARN"已从数据库回填，DAY:true，HOUR:true" |
| 库里也无配置 | 表为空，hash 也不存在 | 发送 | 按 500 / 200 判断，日志记 ERROR；60 秒内不重复查库 |
| 旧计数兼容 | 旧逻辑写下的 key 值为 5，没有 TTL | 发送 | 接着累加到 6，并补上 TTL |
| 告警去重 | 同一区号当天反复超限 | 多次触发 | 每种类型当天只发一次告警短信 |

已用本地 Redis 3.2 验证过：放行和拦截、禁发、旧 key 兼容、回退、manager 写入的 hash 在 notification 能读成 Integer、`evalMethod` 返回 `List<Long>`。三个 Java 模块已用 JDK 17 编译通过。管理台页面还没在浏览器里实际测试。

## 7. 关键决定与待确认

### 关键决定
| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 一张表，每个区号一行，日、小时上限放在同一行，DEFAULT 单独一行 | 一行就能看清一个区号的完整策略 | 放弃"区号 + 维度"拆成多行的方案 |
| NULL 表示继承，0 表示禁发，不提供"不限制" | 攻击时最常用的操作是直接封某个区号；不提供"不限制"，防止误配后完全失守 | 要放开就设一个很大的值 |
| 表建在 panda_db | notification 能直接回源，不依赖管理台服务 | manager-data 跨业务库访问（dev_db 本来就连 panda_db） |
| 管理台直接写 Redis | 已有 `LANG_DICT_MSG`、`GLC:CAPTCHA:*` 先例 | 放弃"notification 提供内部接口 + token"的方案（已废弃的旧改造） |
| 缓存缺失时回源查库，再不行用硬编码默认值 | 拒发会导致全站收不到验证码，放行会在攻击时失守 | 放弃"回落到 nacos 旧配置" |
| 先写临时 key 再 RENAME | 避免"先删后写"中间出现空缓存 | 两个 hash 之间有毫秒级的不一致 |
| notification 回填用 `RENAMENX`，管理台刷新用 `RENAME` | 防止旧快照覆盖新配置，同时让管理台始终是权威来源 | 多个管理员并发刷新的问题（旧快照覆盖）暂未修复，对应提交已回滚 |
| 计数沿用旧 key 格式 | 上线当天计数不归零 | — |
| 日、小时分两个单 key 脚本，小时超限时回退日计数 | Redis 可能是集群，多 key 脚本会跨 slot 报错 | 只有并发恰好卡在阈值边界时可能有 1 条误差 |
| 不拦 `otpSmsHuaWei` | 需求方决定 | 攻击者如果走 glc 登录（华为渠道）可以绕过限额 |
| 告警号码留在 nacos | 需求方决定 | 攻击期间要加告警人，还得改 nacos |
| 增删改后自动刷新，同时保留手动刷新按钮 | 攻击场景下需要"改完立刻确认生效" | — |
| 支持物理删除（需二次确认）和停用 | 攻击过后临时加的区号需要清理 | 删除依赖 `@AccessLogging` 留痕 |
| 不校验"小时上限不大于日上限" | 需求方决定 | 可能误配 |

### 待确认
| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| 各环境 `manager-redis.properties` 和 `redis.properties` 是否指向同一个 host 和 db | 不一致的话，管理台写的缓存 notification 读不到，会一直走回源或硬编码默认值 | 上线前到 nacos 核对（cze） |
| 生产 nacos 里 4 个配置项的当前值，以及 `"44"` 这类不带 `+` 的写法要不要改成 `+44` 生效 | 决定导入的初始数据 | cze 导数时确认 |

## 8. 原型与附件

| 内容                   | 文件或链接                                                     | 对应的需求步骤  |
| -------------------- | --------------------------------------------------------- | -------- |
| 上线 SQL（建表、导数模板、菜单权限） | ./sms_limit_config_release.sql                            | 上线       |


**上线顺序**：
1. panda_db 建表
2. 按各环境 nacos 当前值导入数据
3. 管理台权限库插入菜单和权限，并给角色授权
4. 上线 manager-data、manager-shiro、manager-website
5. 在管理台点一次"刷新缓存"
6. 上线 wt-notification
7. 删除 nacos 里的 `sms.optLimit` / `optLimitJson` / `hourOptLimit` / `hourOptLimitJson`

**代码清单**（分支均为 `cze-4995`）：
- wt-notification：
  - 新增 `component/OtpSmsLimiter.java`、`dao/SmsLimitConfigMapper.java`、`pojo/model/SmsLimitConfig.java`
  - 修改 `controller/NotifyDoController.java`（`otpSms`、`sendWarnSms`，删除 `queryArea*Limit`）、`configuration/SmsConfig.java`（删除 4 个字段）
- manager-data：`pojo/model/SmsLimitConfig`、`mapper/SmsLimitConfigMapper`、`service/SmsLimitConfigService` + `impl`、`controller/SmsLimitConfigController`（`/data/messageCenter/smsLimitConfig/{list,edit,delete,refresh}`）
- manager-shiro：`client/data/SmsLimitConfigClient`、`controller/data/SmsLimitConfigController`
- manager-website：`views/screen/messageCenter/smsLimitConfig.htm`、`views/tpl/messageCenter/smsLimitConfigEdit.tpl`、`static/js/controller/messageCenter/smsLimitConfig.js`、`smsLimitConfigEdit.js`

## 9. 变更记录

| 日期  | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | ---- | ---- | --------- |
| 2026-10-16 | 需求评审完成，代码实现完成 | — | 全部 |
| 2026-10-16 | 计数从"单个 Lua 同时处理两个 key"改为"两个单 key 脚本，小时超限时回退日计数" | Redis 可能是集群，多 key 脚本会跨 slot | R2、R3 |
| 2026-10-16 | 权限 `shiro_code` 从 110-18 系列调整为 110-19 系列；插入时不写主键 | 编号按实际环境调整；避免生产主键冲突 | 第 4 节 权限 |
| 2026-10-16 | 两个 `SmsLimitConfig` 实体改用 Lombok `@Data` | 精简代码 | 无 |
| 2026-10-16 | 代码兜底默认上限从 20000 / 500 改为 500 / 200 | 缓存和库都没有配置时按更保守的值拦截 | R4 |
| 2026-10-16 | notification 回填改用 `RENAMENX`；管理台刷新加 Redis 锁 | 评审发现回源的旧快照可能覆盖管理台刚刷新的新配置（如禁发），而且会持续失效 | R4、第 2 节步骤 2 和 5 |
