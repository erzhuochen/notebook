# [越权检查-18] contentType 为 multipart 时，新增请求体 userId 校验

> 状态：待确认（代码已完成，JDK 17 编译通过，未联调）
> 模块及适用范围：wt-web-gateway（工具类 `GatewayHttpUtil`、业务校验过滤器 `Pre40BusinessCheckGlobalFilter`）
> 负责人：erzhuochen
> 最后更新：2026-10-13

## 两分钟回忆

- **为什么做**：上传接口（如 `/web/payee/document/upload/single`）用 `multipart/form-data` 传文件，同时用表单字段传 `userId`。网关的 `Pre40BusinessCheckGlobalFilter` 会校验请求里的 userId 和 token 里的 userId 是否一致，但 `GatewayHttpUtil.getBodyContent` 遇到 multipart 一律返回 `null`，校验拿不到表单里的 userId，只能退而查 `?userId=` 这个 query 参数。攻击者只要带自己的 token，把 `userId` 放进表单字段（不放 query），就能以他人身份上传文件，校验完全被绕过。
- **一句话方案**：给 `GatewayHttpUtil` 加 `getMultipartTextField(exchange, name)`，从网关已经缓存的 multipart 原始字节里取出第一个同名的非文件字段；`Pre40BusinessCheckGlobalFilter` 在 query 取不到 userId 后，遇到 multipart 请求就改走这个方法，不再走只能匹配 JSON 的正则。
- **核心链路**：请求进入 → `PreCacheBodyGlobalPreFilter`（order 最高）把整个请求体缓存成内存 DataBuffer → Pre20 解析 token → Pre40 业务校验：query 里没有 `userId` 且请求是 multipart 时，从缓存字节里解析表单字段取 `userId` → 与 token 里的 userId 比较 → 不一致则按开关拦截（`open_verify_business_check`）或只记录 → 通过则照常转发。
- **最容易忘的细节**：
  - `getBodyContent` 的行为**没有改**，multipart 仍然返回 `null`。改它会波及 Pre10 验签（Pre10 用 `body + timestamp` 做 SHA1withRSA，multipart 时 body 是空串，纳入了就等于所有存量客户端验签失败）。
  - 判断“有 `filename=` 就是文件、没有就是普通文本参数”，这是 Spring MVC 自己区分 `MultipartFile` 和普通参数的规则。
  - 文件 part 只做字节比较找边界，不解码也不复制，所以二进制内容和编码问题都不会影响解析。
  - query 与表单都带 `userId` 时，两边都以 query 为准（Pre40 先查 query，Spring MVC 绑定也是 query 参数在前、取首个值）。
  - `parseParamUserId` 的 try/catch 是这次一并补的：`Long.parseLong` 一旦抛异常，会被 filter 最外层 catch 捕获，导致整个校验放行——这本身就是一个绕过口子。
- **当时的取舍**：
  - 不改 `getBodyContent` 的语义，新增独立方法，只有 Pre40 调用。既堵住漏洞，又不动验签。
  - 对所有 multipart 请求生效，不维护路径白名单。扫描开销有上限（见第 5 节）。
  - 不走 Spring 的响应式 `DefaultPartHttpMessageReader`（Pre40 的规则是同步的 `Function`），改为对缓存的字节做同步扫描，避免在 Netty 事件循环线程上 `block()`。
  - 不写单元测试，靠联调验证（用户决定）。
- **当前待确认**：本地无完整环境，query 与表单同时带 userId 时的实际优先级、10MB 请求体的扫描耗时都**没有实测**；手写边界扫描没有测试兜底，这是最需要联调覆盖的部分。

## 1. 背景、目标与范围

### 背景

- **Pre40 已有的校验**：`Pre40BusinessCheckGlobalFilter`（order 40）只做一件事——token 里的 userId 和请求里的 userId 一致性校验。取不到任意一侧就放行（免登录、未带 userId 的接口天然放行，不需要维护白名单）。
- **取 userId 的现状**：`extractRequestUserId` 先查 query 参数 `userId`，查不到再读明文请求体，用正则 `(?:^|[\s{,])"userId"\s*:\s*"?(\d+)"?` 匹配 JSON 里的 `userId`。
- **漏洞成因**：`getBodyContent` 第一件事就是判断 content-type，含 `multipart/form-data` 直接 `return null`。这个设计本身是合理的——它要把整个 buffer 按 UTF-8 解码成字符串，如果对一个 10MB 的二进制上传体做这件事，会得到一个 10MB 的乱码字符串，接着 Pre10 拿它去验签、打 debug 日志，Pre40 再对它跑正则。所以跳过的**原因**是“不能把整个请求体当文本解码”，而不是“multipart 请求里没有 userId”。
- **具体接口**：`wt-web` 的 `PayeeDocumentsController.payeeDocumentsUploadSingle`（`/web/payee/document/upload/single`），签名是 `(@RequestParam("file") MultipartFile file, PayeeDocumentsDTO param, HttpServletRequest request)`。`param` 没有注解，Spring MVC 按普通对象处理，字段来自 query 或 multipart 文本字段；`PayeeDocumentsDTO.userId` 是 `Long`。这个方法不校验 token，`userId` 直接取自绑定结果，也就是说上游把 userId 交给了网关和客户端双方。网关这一层目前查不到表单里的 userId，等于没人校验。
- **注意**：查不到 userId 时 Pre40 是放行而不是拒绝，所以这个漏洞的表现是“悄悄放行”，日志里不会留下任何痕迹。

### 目标

- multipart 请求中表单字段里的 `userId`，必须和 token 里的 userId 一致，否则按现有开关决定拦截或记录。
- 不改变现有 JSON 请求的校验行为，不改变 `getBodyContent` 的对外语义，不改变 Pre10 的验签输入。
- 解析失败时不能让校验被绕过，也不能让本来能正常上传的请求失败。

### 范围

- 包含：
  - wt-web-gateway：`GatewayHttpUtil` 新增 `isMultipartFormData`、`getMultipartTextField` 及一组私有解析方法；`getBodyContent` 里原有的 content-type 判断改为调用 `isMultipartFormData`（行为不变）。
  - wt-web-gateway：`Pre40BusinessCheckGlobalFilter` 的 `extractRequestUserId` 增加 multipart 分支；新增 `parseParamUserId`。
- 不包含：
  - Pre10 验签纳入 multipart 参数（需要客户端同步改签名算法，属于另一件事）；
  - `application/x-www-form-urlencoded` 请求体里的 `userId`（Pre40 的正则同样匹配不到，是另一个更早存在的盲区）；
  - `getBodyContent` 的语义调整；
  - `PayeeDocumentsController` 自身的其他问题（见第 5 节“顺带发现”）；
  - 下游 `wt-web` / core 的接口改动。
- 涉及的市场、用户、系统或模块：所有走网关的 multipart 上传接口（`wt-web` 的 `PayeeDocumentsController`、`PayerDocumentsController`、`PayeeController`、`OcrController`、`ImageController`、`CardController`、`NetsController` 等）；wt-core、wt-entity 无改动。

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 客户端发起上传 | 无 | `PreCacheBodyGlobalPreFilter`（`Ordered.HIGHEST_PRECEDENCE`）调 `ServerWebExchangeUtils.cacheRequestBody`，把整个请求体（multipart 含文件）拼成一个内存 DataBuffer 存进 exchange 属性 `CACHED_REQUEST_BODY_ATTR` | 请求体可重复读 | 无 content-type 判断，multipart 一样缓存 |
| 2 | Pre20 Token 过滤器 | 无 | 解析 token 得到 `TokenInput` | — | 无 token 时后续 Pre40 因 `tokenInput` 为空而放行 |
| 3 | Pre40 业务校验 | `open_log_business_check=true` 且路径不在 `businessCheckExcludeUris` 里 | `checkUserIdConsistency`：token.userId 为 0 或请求里取不到 userId 就放行 | — | 抛异常时最外层 catch 放行 |
| 4 | 取请求里的 userId | 走到第 3 步的取数 | 先 `getQueryParams().getFirst("userId")`；为空时判断是否 multipart：是则 `getMultipartTextField(exchange, "userId")`，否则读明文 body 走 JSON 正则 | 得到一个字符串 | 见规则 R4、R7 |
| 5 | 一致性判断 | 两侧都取到 | 字符串比较 token.userId 和请求 userId（trim 后） | — | 不一致见第 6 步 |
| 6 | 不一致处理 | 比较结果为不相等 | 记 `RequestLog` 发 MQ（`WT_WEB_GATEWAY_LOG_TOPIC`）；开关 `open_verify_business_check` 为 true 时抛 `BusinessException(LOGIN_EXPIRED)` 拦截 | 日志 + 拦截 | 开关关闭时只记录、放行 |
| 7 | 转发下游 | 校验通过 | Spring Cloud Gateway 把缓存的 DataBuffer 原样转发给 `lb://consumer-web`；上游 controller 正常绑定 `MultipartFile` 和 `PayeeDocumentsDTO` | 上传成功 | 网关不注入任何 header，也不改写 multipart 请求体 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| R1 | `getBodyContent` 入口 | content-type 含 `multipart/form-data` | 返回 `null`（原行为，只是把判断抽成 `isMultipartFormData`） | 所有调用方，即 Pre10:141、Pre40:173 | 无 |
| R2 | Pre40 取 userId | query 参数 `userId` 非空 | 直接返回 query 值，不再看请求体 | 所有路径 | 优先级最高，与 Spring MVC 绑定一致 |
| R3 | Pre40 取 userId | query 里没有，且请求是 multipart | 调 `getMultipartTextField(exchange, "userId")` | 所有 multipart 路径 | 不做路径白名单 |
| R4 | multipart 字段解析 | content-type 是 multipart，但取不到 boundary；或缓存属性不是 `DataBuffer` | 返回 `null`；缺 boundary 打 `log.warn` | 所有 multipart 路径 | 字段不存在属于正常情况，返回 `null` 且不打 warn |
| R5 | multipart 字段解析 | part 头部含 `filename=` | 视为文件，只定位边界、不解码不复制内容，继续找下一个 part | 所有 multipart 路径 | 这些 part 不参与校验 |
| R6 | multipart 字段解析 | 第一个名字等于目标名、且不含 `filename=` 的 part | 按 UTF-8 解码该 part 的值并返回，**立即停止扫描** | 所有 multipart 路径 | 后面的 part（通常就是文件）不再扫描 |
| R7 | multipart 字段解析 | 请求体格式异常：找不到边界、part 头部不完整、part 缺少结束边界 | 抛 `MalformedMultipartException`，由 `getMultipartTextField` 捕获，打 `log.warn` 后返回 `null` | 所有 multipart 路径 | 只捕获这一个自定义异常类型，其他运行时异常会冒到 Pre40 最外层 catch（打 error 日志），避免把代码 bug 伪装成“格式异常”而静默放行 |
| R8 | 拦截判定 | 两侧 userId 都存在且字符串不相等 | 记日志；`open_verify_business_check=true` 时拦截返回 `LOGIN_EXPIRED` | 所有路径 | 与改动前一致，共用同一个开关，没为 multipart 单加开关 |
| R9 | 日志记录 | R8 命中，需要把请求 userId 写进 `RequestLog` | `parseParamUserId` 安全解析：`Long.parseLong` 失败时打 `log.warn` 并按 `null` 记录 | R8 | 拦截判定用字符串比较，在解析之前完成，所以解析失败不影响拦截结论 |

## 4. 页面、字段与权限（按需保留）

### 页面交互

无页面改动。校验失败返回的是现有错误码 `LOGIN_EXPIRED`，和 JSON 请求被拦截时完全一致，客户端不需要适配。

### 数据字段

| 字段 | 来源 | 何时记录或更新 | 用途 | 特殊说明 |
| --- | --- | --- | --- | --- |
| multipart 表单字段 `userId` | 客户端 FormData | 每个 multipart 请求解析一次（找到即停） | 与 token.userId 比较 | 也可以放 query，两者都以 query 为准 |
| token 里的 `userId` | 请求头 token（Pre20 解析出的 `TokenInput`） | 每请求 | 校验基准 | 为 0 时 Pre40 直接放行 |
| `CACHED_REQUEST_BODY_ATTR` | `PreCacheBodyGlobalPreFilter` | 请求进入时 | multipart 解析的唯一数据来源 | 整个请求体在内存里，含文件 |
| `businessCheckExcludeUris` | 网关配置 | 配置变更 | 排除不校验的路径（Ant 风格） | `WebGatewayConfigs:250` |
| `RequestLog`（MQ） | R8 命中时 | 一致性校验失败时 | 审计“userId 和 token 不一致” | 新增场景：以前 multipart 请求根本不会产生这条记录 |

### 权限与操作记录

- 校验不一致时沿用原有 `recordBusinessCheckLog`，`description` 是 `"网关请求:userId和token不一致"`，`detail` 带 token.userId 和请求 userId，写到 `WT_WEB_GATEWAY_LOG_TOPIC`。
- `parseParamUserId` 解析失败时额外打一条 warn，带上原始值（例如 `0x7B`），便于排查客户端发了什么。

## 5. 边界与异常

- **跨市场、跨设备、重复操作**：不涉及市场维度，比较的是同一个 token 内的 userId；防重放仍由 Pre10 的 sign + redis 负责，本次未改动。
- **数据缺失或变化时**：
  - 请求里没有 `userId`（query 和表单都没有）：返回 `null`，Pre40 放行，与改动前一致。
  - 缓存属性不是 `DataBuffer`（例如请求体为空）：返回 `null`，不进解析。
  - token 里 userId 为 0（免登录场景）：Pre40 在取数之前就放行了，不触发扫描。
- **性能边界**：
  - 最费时的“把整个请求体（含文件）读进内存”在 `PreCacheBodyGlobalPreFilter` 已经发生，本次只是对这份已有的字节再扫一遍，没有新增 I/O。
  - 新方案不解码文件内容，只做字节比较找边界，文件部分不复制。
  - 命中 R6 就停止扫描，只要客户端把参数放在文件前面（常见的 FormData 顺序），扫描在碰到文件之前就结束了。文件排在最前面时，需要逐字节扫过文件内容去找边界。**10MB 请求体的实际耗时没有实测**，本地无完整环境。
  - 扫描的前置条件较多，实际触发面很小：总开关打开、路径不在排除名单、token.userId 不为 0、query 里没有 `userId`。
- **撤销、解除、放行或回退时**：
  - `open_log_business_check=false` 可以整体关闭 Pre40；
  - `open_verify_business_check=false` 时只记录不拦截（上线初期可以先用这个状态观察）；
  - 把接口加进 `businessCheckExcludeUris` 可以单独放行；
  - 回退代码即可，`GatewayHttpUtil` 与 Pre40 的改动都是新增，`getBodyContent` 语义未变。
- **与其他规则同时命中时**：过滤器顺序是 PreCacheBody（最高）→ Pre10 验签 → Pre20 token → Pre30 解密 → Pre40 业务校验 → Post 系列。Pre10 对 multipart 请求的验签输入仍是 `"" + timestamp`，**本次没有把它改成表单参数**；如果要改，必须和客户端同步发版，否则所有存量的签名上传请求都会验签失败。

- **顺带发现、本次不处理**：
  - `PayeeDocumentsController.payeeDocumentsUploadSingle` 里 `file` 是 `required = false`，为 null 时 `file.getSize()` 抛 NPE；异常被 `catch (Exception)` 吞掉后方法继续执行 `dealOldDocuments`，会把旧文件处理掉。
  - 同类内部调用 `fileUpload` 绕过了 Spring 代理，方法上的 `@Async("webExecutor")` 不生效。
  - `wt-web` 的 `HttpHelper.getBodyString` 用 `readLine()` 读原始流，会破坏 multipart 的二进制内容（顺带丢掉所有换行）。目前上传能正常工作，推测是因为 hiddenmethod filter 先触发了 Tomcat 对 part 的解析——这是静态推断，没有实际运行验证。
  - `Pre40BusinessCheckGlobalFilter` 的 JSON 正则对 `application/x-www-form-urlencoded` 请求体同样无效，`userId=123` 这种形式查不到。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| 正常流程 | A 登录，FormData 里 `userId` 是 A 的，带文件 | 调 `/web/payee/document/upload/single` | 正常上传 |
| 正常流程-参数在文件前 | 同上，`userId` 字段排在 `file` 之前 | 同上 | 正常上传，扫描在文件前就结束 |
| 越权（本次修复的目标） | A 的 token，FormData 里 `userId` 是 B 的，**query 不带 userId** | 同上 | `open_verify_business_check=true` 时返回 `LOGIN_EXPIRED`，并产生一条“userId和token不一致”的 RequestLog；改动前会被放行 |
| 参数在文件之后 | `userId` 字段排在 `file` 之后 | 同上 | 能被解析出来并正常拦截，验证需要扫过文件内容 |
| query 优先 | query 带 A 的 `userId`，FormData 里带 B 的 | 同上 | 以 query 为准（放行）；需同时确认上游 controller 绑定的也是 A——**这一条依赖两个未实测的行为假设，联调时重点验证** |
| 字段名也叫 userId 的文件 | 文件 part 的 `name` 是 `userId`（带 filename） | 同上 | 该 part 被当作文件跳过，不参与校验 |
| 边界格式 | boundary 带引号、body 带 preamble（首个边界前有额外内容）、part 无 header | 各种构造的 multipart 请求 | 均能正确解析或按 R7 返回 null |
| 缺少 boundary | content-type 是 multipart 但没有 boundary 参数 | 同上 | 返回 null，打一条 warn，请求不被拦截 |
| 请求体被截断 | 传输中断，最后一个 part 没有结束边界 | 同上 | 走 R7，打 warn 返回 null，请求不被拦截（不因为解析失败而拒绝正常上传） |
| 非 multipart 请求 | JSON 请求体 | 调任意接口 | 走原有正则分支，行为与改动前完全一致 |
| Pre10 验签 | 带 `AUTH-SIGNATURE` 的 multipart 请求 | 调上传接口 | 验签输入仍是空 body + timestamp，存量客户端不受影响 |
| 校验被绕过 | 请求 userId 是 `0x7B` 这类 `parseLong` 不接受的值 | 构造请求 | 字符串比较判定为不一致，按开关拦截/记录；`parseParamUserId` 打 warn，不因异常放行 |
| 上游绑定异常 | 请求 userId 是 `"0123"`（带前导零） | 构造请求 | 网关认为不一致会拦截；若有客户端这么发，属于误报，需要评估 |

## 7. 关键决定与待确认

### 关键决定

| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 不改 `getBodyContent`，新增 `getMultipartTextField` | 改 `getBodyContent` 会让 Pre10 的验签输入从 `"" + timestamp` 变成表单参数串，所有存量带签名的上传请求立刻验签失败，必须和客户端同步发版 | 放弃“直接改 `getBodyContent` 让所有 multipart 都返回参数串” |
| 只给 Pre40 用，不纳入 Pre10 验签 | 验签纳入 multipart 参数是独立的、需要客户端配合的改动，混在一起会让这次修复无法单独上线 | 接受 multipart 请求的签名仍然只覆盖 timestamp |
| 对所有 multipart 请求生效，不维护路径白名单 | 上传接口很多（wt-web 里至少 8 个 controller 用 `MultipartFile`），白名单需要人工维护，新接口容易漏 | 放弃按路径 + 正则取参数的方案（原方案受限于正则只能匹配 JSON）；接受多一点扫描开销 |
| 用 `filename=` 判断 part 是不是文件 | 与 Spring MVC 区分 `MultipartFile` 和普通参数的规则一致，不依赖具体接口的字段名 | 放弃“按字段名排除 `file`”（写死字段名，换接口就失效） |
| 手写同步字节扫描，不用 Spring 的 `DefaultPartHttpMessageReader` | Pre40 的规则是同步的 `Function<ServerWebExchange, BusinessException>`，改用 Spring 的响应式 reader 要么在 Netty 事件循环线程上 `block()`，要么把整个 filter 改成异步；字节本来就在内存里，扫一遍是 O(n) | 接受约 60 行手写解析代码；接受没有单元测试覆盖的风险（用户决定不写测试） |
| 文件 part 不解码、不复制 | 解码二进制会得到乱码，复制会白白占用内存 | — |
| 找到第一个匹配字段就停止扫描 | 满足“扫描耗时可控”的要求；Pre40 只关心第一个值 | 放弃一次性返回全部文本字段的 `Map` 方案（必须扫完整个请求体） |
| 解析失败返回 null + warn，不抛异常 | 网关不该因为“想读个参数做审计”而让本来能正常上传的请求失败；Pre40 本身遇到异常也是放行，两边一致 | 接受格式异常时校验被跳过（但会留 warn 日志） |
| 自定义 `MalformedMultipartException`，只捕获它 | 如果 catch `RuntimeException`，代码 bug（buffer 类型意外、下标越界）会被当成“格式异常”静默返回 null，进而变成校验放行——错误会被伪装成漏洞 | 放弃直接用 `RuntimeException`，多 4 行代码 |
| 共用 `open_verify_business_check` 开关，不为 multipart 单加开关 | 合法请求里表单的 userId 本来就该等于 token 里的 userId，误拦截风险低；再加开关只会增加配置维护量 | 放弃“先只记录一段时间再开拦截”的独立开关；如果存在代他人上传的合法场景，需要重新评估 |
| 把 `Long.parseLong` 换成 `parseParamUserId` 安全解析 | `parseLong` 失败会抛异常，被 filter 最外层 catch 捕获后整个校验放行，这本身就是绕过口子（`0x7B` 这类值 Spring MVC 能绑定、`parseLong` 不接受） | 放弃“直接用字符串记录日志”；接受日志里 `paramUserId` 可能为空 |
| 不写单元测试 | 用户决定 | 已知风险：手写的边界扫描没有测试兜底，边界情况（引号 boundary、截断请求体、文件名也叫 userId）只能靠联调覆盖 |

### 待确认

| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| query 与表单同时带 `userId` 时的实际优先级 | 结论依赖两个未实测的行为假设：Pre40 先查 query（代码可读），以及 Spring MVC 绑定 `Long` 时取第一个值、Tomcat 把 query 参数排在表单之前（推断）。如果假设不成立，攻击者可以放一个 query 值骗过网关、再靠表单值影响业务 | 开发 / 联调 |
| 10MB 请求体的扫描耗时 | 本地无完整环境，没有实测。文件排在参数之前时需要逐字节扫过文件内容 | 开发 / 联调 |
| 是否存在合法的“表单 userId ≠ token userId”场景（如代他人上传、运营后台） | 直接决定上线后会不会误拦截 | 产品 / 开发 |
| 线上 `open_log_business_check`、`open_verify_business_check` 的当前状态 | 决定这次改动是立刻生效拦截，还是只产生日志 | 运维 |
| `businessCheckExcludeUris` 里是否已经包含上传类接口 | 如果包含，本次改动对那个接口不生效 | 开发 / 运维 |
| 上游是否有客户端在表单里发 `"0123"` 这类带前导零的 userId | 网关按字符串比较会判定不一致并拦截，可能是误报 | 前端 / 联调 |

## 8. 原型与附件

| 内容 | 文件或链接 | 对应的需求步骤 |
| --- | --- | --- |
| 越权检查的通用判断方法 | [如何判断是否越权？.md](./如何判断是否越权？.md) | 背景 |
| 同一系列的另一处越权修复 | [[越权检查-17] switchLogin gToken 归属校验 + 加密报文解密后校验.md](./[越权检查-17]%20switchLogin%20gToken%20归属校验%20+%20加密报文解密后校验.md) | 背景 |
| 网关的请求体工具类 | `wt-web-gateway/.../utils/GatewayHttpUtil.java`（`isMultipartFormData` :67、`getMultipartTextField` :77、`findTextField` :101、`MalformedMultipartException` :178） | R1、R3–R7 |
| 业务校验过滤器 | `wt-web-gateway/.../filters/Pre40BusinessCheckGlobalFilter.java`（`extractRequestUserId` :152、multipart 分支 :157、`parseParamUserId` :180） | R2、R8、R9 |
| 请求体缓存 | `wt-web-gateway/.../filters/PreCacheBodyGlobalPreFilter.java` | 步骤 1 |
| 受影响的接口 | `wt-web/.../payee/controller/PayeeDocumentsController.java:94`（`/upload/single`） | 背景 |
| 签名过滤器（未改动，说明为何不能改 `getBodyContent`） | `wt-web-gateway/.../filters/Pre10SignatureGlobalFilter.java:141` | R1、第 5 节 |

## 9. 变更记录

| 日期 | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | --- | --- | --- |
| 2026-10-13 | `GatewayHttpUtil` 新增 `isMultipartFormData`、`getMultipartTextField` 及私有解析方法；`getBodyContent` 的 content-type 判断改为调用 `isMultipartFormData`（行为不变） | multipart 请求的表单参数取不到，userId 校验被绕过 | R1、R3–R7 |
| 2026-10-13 | `Pre40BusinessCheckGlobalFilter.extractRequestUserId` 增加 multipart 分支 | 同上 | R2、R3 |
| 2026-10-13 | 新增 `parseParamUserId`，`recordBusinessCheckLog` 的请求 userId 改由它安全解析 | `Long.parseLong` 抛异常会被最外层 catch 吞掉导致整个校验放行 | R9 |
| 2026-10-13 | 决定不改 `getBodyContent` 语义、不纳入 Pre10 验签、不写单元测试 | 避免影响存量客户端的签名；用户决定不写测试 | R1、第 5 节 |

## 代码改动

**`GatewayHttpUtil.java`（wt-web-gateway）**

- 新增 `isMultipartFormData(exchange)`：判断 content-type 是否含 `multipart/form-data`。`getBodyContent` 里原来那段内联判断改调它，行为完全不变。
- 新增 `getMultipartTextField(exchange, name)`：非 multipart、缓存属性不是 `DataBuffer`、没有 boundary、字段不存在、解析异常，这些情况都返回 `null`；只有缺 boundary 和格式异常会打日志。
- 新增私有的 `findTextField` / `parseContentDisposition` / `decode` / `indexOf` / `startsWith`：
  - 第一个边界与后续边界分开找，兼容首边界之前有 preamble 的请求体；
  - 每个 part 先找空行定位头部结束，再找 `\r\n--boundary` 定位内容结束；不匹配的 part 直接用定位结果跳到下一个，不解析内容；
  - 用 `ContentDisposition.parse` 解析 `Content-Disposition` 头，`filename` 为空才算普通字段；
  - 所有定位都基于字节比较，不对文件内容做解码。
- 新增私有静态嵌套类 `MalformedMultipartException`，只用于表示“请求体本身不规范”，由 `getMultipartTextField` 精确捕获。catch 里还带了 `IllegalArgumentException`，这一条是顺手加的，实际没有对应的抛出点，可以删掉（见待确认外的讨论）。

**`Pre40BusinessCheckGlobalFilter.java`（wt-web-gateway）**

- `extractRequestUserId`：查完 query 之后增加 multipart 分支，调 `getMultipartTextField(exchange, "userId")`，非 multipart 请求仍走原来的明文 body + JSON 正则。
- 新增 `parseParamUserId(raw)`：`Long.parseLong` 失败时打 warn 并返回 `null`。
- `checkUserIdConsistency` 里记日志的调用改为 `recordBusinessCheckLog(..., parseParamUserId(trimmed))`；拦截判定用的是字符串比较（`StrUtil.equals(tokenUserIdStr, trimmed)`），在解析之前完成，所以解析失败不影响拦截结论。

## 上线前需要注意

1. **先确认 `open_verify_business_check` 的线上状态**：如果是 true，这次改动上线后 multipart 上传接口会**立刻开始拦截** userId 不一致的请求；建议先在 false 状态（只记录）跑一段时间，看 RequestLog 里有没有“userId和token不一致”的记录。
2. **确认 `businessCheckExcludeUris` 是否包含上传接口**：包含的话本次改动不生效，需要先确认名单。
3. **编译要用 JDK 17**：本机默认 JDK 是 25，Lombok 注解处理器不会运行，会报出一百多条“找不到方法”的假错误（包括未改动的 `getBodyContent` 调用点）。用 `JAVA_HOME=~/.jdks/ms-17.0.15 mvn -o compile` 编译通过。
4. **建议重点联调的场景**：
   - query 和表单同时带不同 `userId`：确认网关拦截的是哪一个，以及上游 controller 实际绑定的是哪一个；
   - `userId` 字段排在 `file` 之后：确认仍能解析出来并拦截；
   - `userId` 和文件 part 同名、boundary 带引号、请求体截断：确认走 R5/R7 而不是误拦；
   - 一个 10MB 的上传：确认扫描没有带来可感知的延迟。
