# [越权检查-17] switchLogin gToken 归属校验 + 加密报文解密后校验

> 状态：待确认（已上线过一版，出现误拦后紧急关闭；修复版已提交，等测试环境验证后再重新开启）
> 模块及适用范围：glc-web（越权校验拦截器、请求体解密）、glc-core（gToken 查询接口）；分支 `cze-越权`（从 release 新建）
> 负责人：erzhuochen
> 最后更新：2026-10-23

## 两分钟回忆

- **为什么做**：`/login/switchLogin` 只根据请求体里的 `gToken + countryCode` 找到要切换的账号，没有检查这个 `gToken` 是不是当前登录用户的。A 用自己的 token、填上 B 的 gToken，就能拿到 B 的 KYC 信息，还会以 B 的身份触发 switchCountry 或 autoRegister。另外，客户端带 `RS` 头时请求体是加密的，拦截器读不到明文，于是 userId 校验被直接跳过，gToken 校验也取不到值。
- **一句话方案**：
  - `UserOwnershipInterceptor` 对名单里的 URL 做校验：用 token 里的 **userId** 调用 core，查出这个用户在库里的 **gToken 列表**，请求体里的 gToken 不在列表中就拒绝。这个拦截器同时负责 `userSameSwitch` 的 userId 一致性校验。
  - `RequestBodyDecryptor` 负责按需解密请求体，并把明文缓存在 request 上，这样拦截器拿到的都是解密后的内容。
- **核心链路**：请求 → SignatureInterceptor（对密文原文验签）→ TokenInterceptor（解析 token）→ UserOwnershipInterceptor（解密后校验 userId 和 gToken）→ DecryptRequestBodyAdvice（复用已解密的明文）→ Controller。
- **最容易忘的细节**：
  - **查询只能用 userId，不能带上 token 里的 countryCode。** "选择市场"等很多操作都会重新签发 token，签发时 userId 不变，countryCode 换成新选的市场，甚至可能是另一个服务器上的市场。上一版按 `userId + countryCode` 查询，切换到新市场时查不到记录，正常用户被误拦（2026-10-22 线上事故）。
  - 一个 userId 可能对应多个 gToken（历史遗留），所以要查出列表，判断请求里的 gToken 是否在其中。
  - 只按 userId 查询的前提是 **userId 在所有服务器之间不重复**（leader 已确认）。要注意，各市场的 `global_user_kycs` 虽然是各自独立的表，但数据会通过 PMM 广播全量同步，每张表里都有所有服务器的行。
  - 解密发生在 `RequestBodyAdvice` 中，它**在所有拦截器之后才执行**，所以拦截器本身拿不到明文。
  - `MyRequestWrapper` 里的原始 body 必须保持为密文，否则 SignatureInterceptor 验签会失败。
  - 日志里的字段名不能包含 `token`、`key`、`sign` 等关键字，否则会被 `SensitiveDataConverter` 打码，排查时就看不到值。
  - 代码里 `verifyGTokenUrls` 的默认值是 `/login/switchLogin,`。在 Nacos 里关闭校验时，必须**显式配置为空字符串**，不能删掉这个配置项。
- **当时的取舍**：
  - 不加 Redis 缓存，每次都查库：名单里只有 1 个接口，开销可以接受。
  - 不在 Filter 里统一解密（影响面太大），也不把校验放到 RequestBodyAdvice 里（同一类校验会被拆到两个地方）。
  - 日志脱敏、token 过期检查都不在这次的范围内。
- **当前待确认**：在测试环境验证两个场景：①先选择市场，再切换到一个没有账号的新市场，应能通过；②越权请求应被拒绝。验证通过后，再把生产 Nacos 里的 `verifyGTokenUrls` 改回 `/login/switchLogin`。

## 1. 背景、目标与范围

### 背景
- **gToken 是什么**：gToken 是"全球账号"的标识，创建全球账号时由 `UUIDUtils.getUUIDString()` 生成。它永久不变、不签名、不会过期，存放在 `global_user`、`global_user_kycs` 等表里。真正的登录凭证是请求头里的 `token`，它是一个 AES 加密加 HMAC 签名的自包含令牌，里面有 `userId`、`countryCode`、`env` 等信息，但没有 gToken，代码里也没有把两者关联起来。
- **switchLogin 的问题**：core 的 `GlobalUserController.switchLogin` 只按 `gToken + countryCode + server + vendor` 查询 `global_user_kycs`，查到后用记录里的 userId 覆盖请求里的 `id`。web 层把 token 转发给了 core，但 core 没有使用它。
- **攻击前提**：攻击者要先拿到别人的 gToken。gToken 只会返回给本人，`/login/captcha/verify` 也要先通过验证码；但 glc-core 里有 20 多处日志明文打印了 gToken，能接触日志的人可以批量拿到 gToken，而日志里拿不到 token。这次修复就是让"拿到 gToken 就能操作这个账号"不再成立。
- **加密报文的问题**：客户端带 `RS` 头时，请求体是 `{"data":"signKey$aesKey$data$sign"}` 形式的密文。原来的 userId 校验在取不到 userId 时直接放行（原代码注释写的是"加密报文自然跳过"），这就留下了一个绕过口子；而 gToken 校验取不到值时会拒绝，导致正常的加密请求被误拦。
- **2026-10-22 线上误拦**：第一版上线后，用户切换到一个**自己还没有账号的新市场**时被拦截，日志是 `gToken not match, countryCode=JPN/DEU`。原因如下：
  - 切换之前，前端会先走"选择市场"这一步，这一步（还有其他很多地方）会重新签发 token：**userId 保持不变，countryCode 换成新选的市场**。代码里的例子有 wt-web 的 `POST /payer/v2/update`，它的 userId 强制取自旧 token，countryCode 取自请求体。
  - 拦截器按 `(userId, 新市场 countryCode)` 查询。用户在新市场还没有账号，自然查不到。以 JPN 为例：JP_SERVER 上只有日本，用户在日本又没有账号，所以 token 里的 userId 一定来自其他服务器，这就是**跨服务器漂移**。
  - 处理过程：先在 Nacos 里把 `verifyGTokenUrls` 设为空，关闭校验止血；之后把查询条件改成只按 userId。

### 目标
- 名单里的接口，请求体中的 gToken 必须属于 token 里的用户，否则拒绝。
- 不管请求是明文还是加密报文，userId 和 gToken 的校验都在解密之后进行，堵住加密报文的绕过口子。
- 不改变现有的加解密、响应加密、签名校验行为。
- 不受 token 里 countryCode 刷新的影响，用户正常切换市场时不能被误拦。

### 范围
- 包含：
  - glc-web：新增 `UserOwnershipInterceptor`、`RequestBodyDecryptor`；修改 `TokenInterceptor`（把 userSameSwitch 校验移出去）、`DecryptRequestBodyAdvice`、`WebAppConfigurer`、`CoreClient`、`CommonConfigs`。
  - glc-core：在 `GlobalUserController` 新增 `GET global/user/query/gToken/{userId}` 接口，在 mapper 新增 `selectGTokenListByUserId`。
- 不包含：
  - 白名单接口（`/login/set/password`、`/phone/bind`、`/email/bind`、`/verifyUser`、`/password/verify` 等）。这些都是未登录流程，没有 token 可以绑定。
  - 日志脱敏（包括 `GlobalUserController.java:270` 明文打印密码的问题）。
  - token 过期检查（目前只判断了 `timestamp == 0`）。
  - token 签发方的问题（比如"选择市场"会生成 userId 和 countryCode 不一致的 token），以及 core 端 switchLogin 的业务逻辑。
- 涉及的市场、用户、系统或模块：所有市场；`verifyGTokenUrls` 名单里需要登录的接口（目前只有 `/login/switchLogin`）；开启 `userSameSwitch` 后的所有需要登录的接口。

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 客户端请求进入 | 无 | `HttpServletRequestReplacedFilter` 用 `MyRequestWrapper` 缓存原始 body；如果是加密请求，缓存的就是密文 | body 可以重复读取 | 无 |
| 2 | 拦截器 `SignatureInterceptor` | 请求带 `AUTH-SIGNATURE` 头 | 用**原始 body**（加密请求就是密文）加上时间戳做 RSA 验签 | — | 验签失败返回 `SIGNATURE_FAIL` |
| 3 | 拦截器 `TokenInterceptor` | 路径不在 excludePaths 中 | 解析 token，得到 `tokenObj`；检查黑名单、环境等 | request 上多了 `tokenObj` 属性 | IP 在白名单里且没带 token 时放行 |
| 4 | `UserOwnershipInterceptor.verifyUserId` | `userSameSwitch=true` | 优先取 query 参数里的 `userId`；没有的话，调用 `RequestBodyDecryptor.getPlainBody` 拿到明文 body，取顶层的 `userId`，与 token 里的 userId 比较 | 加密请求的明文被缓存到 request 属性上 | 解密失败返回 `DECRYPT_FAIL`；不一致返回 `USER_NOT_LOGIN`；body 里没有 userId 时放行 |
| 5 | `UserOwnershipInterceptor.verifyGToken` | 请求路径匹配 `verifyGTokenUrls` | 取 `tokenObj` 里的 userId → 调用 `getPlainBody` 拿到明文，取顶层的 `gToken` → 通过 Feign 调用 core 的 `GET query/gToken/{userId}` 拿到 gToken 列表 → 检查请求里的 gToken 是否在列表中 | — | 见规则 R3 |
| 6 | `DecryptRequestBodyAdvice.beforeBodyRead` | Controller 有 `@RequestBody` 参数，且请求带 `RS` 头 | 调用 `requestBodyDecryptor.decrypt`；如果第 4 或第 5 步已经解密过，直接复用缓存 | Controller 收到明文对象 | 抛出 `BusinessException` 后，由 `@ExceptionHandler` 统一返回 `DECRYPT_FAIL` |
| 7 | Controller / core | 前面的步骤都通过 | 执行原有业务逻辑 | — | — |
| 8 | `EncryptResponseBodyAdvice` | 请求带 `RS` 头，且业务成功 | 加密响应（这部分没有改动） | — | 失败响应（`!isSuc()`）不加密 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| R1 | 名单匹配 | 请求路径（去掉 contextPath 后）用 `AntPathMatcher` 匹配 `common.verifyGTokenUrls` 中逗号分隔的任意一项 | 匹配上才做 gToken 校验 | UserOwnershipInterceptor 覆盖的路径（排除路径与 TokenInterceptor 相同） | 名单为空时相当于关闭校验 |
| R2 | 校验开始前 | 请求没带 `token` 头，并且 IP 在 `userWhiteList` 中 | 放行 | 同上 | 与 TokenInterceptor 的白名单逻辑保持一致 |
| R3 | gToken 校验 | 以下任何一种情况：`tokenObj` 为空、userId 为 0、body 不是 JSON、body 顶层没有 `gToken`、调用 core 出现异常、按 **userId** 查到的 gToken 列表为空、请求里的 gToken 不在列表中 | 拒绝，返回 `USER_NOT_LOGIN`（格式与 TokenInterceptor 的 `outputResponse` 相同），并记录 error 日志（见第 4 节，**不打印 gToken 的值**） | 名单内的 URL | 解密失败按 R5 处理；**不检查也不使用 token 里的 countryCode** |
| R4 | userId 校验 | `userSameSwitch=true`，并且 query 参数或明文 body 顶层有 `userId` | 与 token 里的 userId 不相等就拒绝，返回 `USER_NOT_LOGIN` | UserOwnershipInterceptor 覆盖的全部路径 | 取不到 userId 时放行（保持原有逻辑） |
| R5 | 拦截器中的解密 | 请求带 `RS` 头，并且需要读取 body | 调用 `RequestBodyDecryptor` 解密并验签，失败就拒绝，返回 `DECRYPT_FAIL` | R3、R4 | 解密失败、验签失败、私钥为空，都统一返回 `DECRYPT_FAIL`（与 advice 保持一致） |
| R6 | 解密缓存 | 同一个请求已经解密成功过 | 直接返回 request 属性 `GLC_DECRYPTED_PLAIN_BODY` 里的明文 | 拦截器和 advice | 解密失败的结果不缓存，advice 会再尝试解密一次，失败后由 `@ExceptionHandler` 处理 |

## 4. 页面、字段与权限（按需保留）

### 页面交互
没有页面改动。校验失败时前端收到的都是已有的错误码（`USER_NOT_LOGIN` / `DECRYPT_FAIL`），失败响应也不会被加密，前端不需要做任何适配。

### 数据字段
| 字段 | 来源 | 何时记录或更新 | 用途 | 特殊说明 |
| --- | --- | --- | --- | --- |
| `common.verifyGTokenUrls` | Nacos `logincenter.yml` / `CommonConfigs` 默认值 | 配置变更后自动刷新 | gToken 校验的 URL 名单 | 代码默认值是 `/login/switchLogin,`；关闭校验时必须显式配置为空字符串 |
| `common.userSameSwitch` | Nacos `logincenter.yml` | 同上 | userId 一致性校验的开关 | 代码默认值是 `false` |
| request 属性 `GLC_DECRYPTED_PLAIN_BODY` | `RequestBodyDecryptor` | 第一次解密成功时 | 在同一个请求内复用明文 | 只在当前请求内有效 |
| `global_user_kycs.g_token` | 数据库（各市场的库都有一张表，通过 PMM 广播全量同步） | 已有字段 | 用 `selectGTokenListByUserId` 按 `user_id` 查出 gToken 列表 | `user_id` 上已有索引；一个 userId 可能对应多个 gToken（历史遗留） |
| token 里的 `countryCode` | 签发 token 的接口 | 选择市场、kycInfo、payer update 等很多地方都会刷新 | **不参与校验** | 可能和 userId 所在的市场不一致 |

### 权限与操作记录
- gToken 校验失败时记录 error 日志，格式为 `ownership verify fail, <原因>, uri=..., loginUserId=...`。具体原因有：
  - `login info invalid`：tokenObj 为空，或 userId 为 0
  - `decrypt request body error`：请求体解密失败
  - `gtk not found in body`：请求体里没有 gToken
  - `query gtk error`：调用 core 出现异常
  - `gtk not found in db, ..., loginCountry=...`：数据库里没有查到这个 userId 的 gToken
  - `gtk not match, ..., loginCountry=..., dbCount=...`：查到了列表，但请求里的 gToken 不在列表中
- userId 不一致时的日志：`userId verify fail, uri=..., loginUserId=..., paramUserId=...`。
- 字段名都避开了 `token` 关键字，uri 和 userId 不会被打码。`loginCountry` 只是用来辅助排查的。

## 5. 边界与异常

- **跨市场、跨设备、重复操作**：
  - 只按 token 里的 userId 查询，无论用户当前在哪个市场、选了哪个市场、要切换到哪个市场（包括还没有账号的新市场），查到的都是这个用户自己的 gToken 列表。
  - token 里的 countryCode 发生跨服务器漂移时（比如 SG 的 userId 搭配 countryCode=JPN），因为查询不使用 countryCode，所以不受影响。
  - 重复请求由 SignatureInterceptor 防重放，这次没有改动。
- **数据缺失或变化时**：
  - 数据库查不到这个 userId 的任何 gToken 时拒绝。
  - core 不可用时，名单内的接口都会被拒绝。
  - 没有缓存，映射关系变化后马上生效。
- **撤销、解除、放行或回退时**：
  - 把 Nacos 里的 `verifyGTokenUrls` 设为空字符串，就能关闭 gToken 校验。
  - 把 `userSameSwitch` 设为 `false`，就能关闭 userId 校验；如果名单也为空，拦截器就不会提前解密。
- **与其他规则同时命中时**：执行顺序是 SignatureInterceptor → MerchantInterceptor → TokenInterceptor → UserOwnershipInterceptor，前面任何一个拒绝了，后面的都不会执行。UserOwnershipInterceptor 依赖 `tokenObj`，所以必须注册在 TokenInterceptor 之后，排除路径也要保持一致。
- **已知前提**：userId 在所有服务器之间不重复（leader 已确认）。如果以后某个服务器的 ID 分配方式变了，导致不同服务器的 userId 撞号，只按 userId 查询就可能查到另一个服务器上同号用户的 gToken，从而产生越权。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| 正常流程-明文 | A 已登录，body 里是 A 的 gToken | 调用 `/login/switchLogin` | 正常切换 |
| 正常流程-加密 | A 已登录，请求带 `RS` 头，加密 body 里是 A 的 gToken | 调用 `/login/switchLogin` | 正常切换；同一个请求只解密一次（"请求明文"日志只打印一次） |
| **选择市场后切换到新市场** | A 在新市场还没有账号；先完成"选择市场"（token 里的 countryCode 被刷新为新市场） | 调用 `/login/switchLogin` 切换到新市场 | **正常切换**（10-22 事故场景的回归测试） |
| 越权-明文 | 用 A 的 token，body 里是 B 的 gToken | 调用 `/login/switchLogin` | 返回 `USER_NOT_LOGIN`，日志里有 `gtk not match` |
| 越权-加密 | 用 A 的 token，加密 body 里是 B 的 gToken | 调用 `/login/switchLogin` | 返回 `USER_NOT_LOGIN` |
| 缺少 gToken | 名单内的接口，body 里没有 `gToken` | 调用接口 | 返回 `USER_NOT_LOGIN`，日志里有 `gtk not found in body` |
| 报文被篡改 | 请求带 `RS` 头，密文或签名被改过 | 调用名单内的接口 | 返回 `DECRYPT_FAIL` |
| userId 加密绕过 | `userSameSwitch=true`，用 A 的 token，加密 body 里的 `userId` 是 B 的 | 调用任意需要登录的接口 | 返回 `USER_NOT_LOGIN`（修复前会被放行） |
| 不在名单内的加密接口 | 请求带 `RS` 头 | 调用普通接口 | Controller 能正常收到明文，行为和改动前一样 |
| core 不可用 | glc-core 不可用 | 调用名单内的接口 | 返回 `USER_NOT_LOGIN`，日志里有 `query gtk error` |

## 7. 关键决定与待确认

### 关键决定
| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 用 URL 名单，在拦截器里比较请求中的 gToken 和数据库里的 gToken | 后续可以通过配置扩展到其他接口，不需要改 Controller | 放弃了"服务端直接根据 token 推导 gToken，忽略入参"的方案 |
| **只按 `userId` 查询，不使用 token 里的 countryCode** | token 里的 countryCode 会被"选择市场"等很多地方刷新，可能与 userId 所在的市场不一致，甚至跨服务器；刷新的地方太多，没法逐个修改；leader 确认 userId 在全局不重复 | 放弃了：① `userId + countryCode`（10-22 线上误拦）；② `userId + server`，其中 server 由 countryCode 推导（跨服务器漂移时同样会误拦）；③ `userId + server`，其中 server 由 token 里的 env 推导（无法在测试环境验证，日本的 env 值也不确定）；④ 从源头修改 token 签发方（需要跨团队协作）。**接受的风险**：以后如果出现跨服务器的 userId 撞号，校验可能被绕过 |
| 查 gToken 列表，判断请求中的 gToken 是否在列表中 | 一个 userId 可能对应多个 gToken（历史遗留），这些 gToken 都属于同一个人 | — |
| core 接口直接改成 `query/gToken/{userId}`，不保留旧接口 | 生产上校验已经关闭，旧版 web 不会调用这个接口，所以没有兼容问题 | 放弃了新旧接口同时保留的方案 |
| 把校验合并到 `UserOwnershipInterceptor`（同时负责 userId 和 gToken 两种校验） | 越权相关的校验集中在一个地方；TokenInterceptor 只负责解析 token | — |
| 不加缓存，每次都通过 Feign 调用 core 查库 | 名单里只有 1 个接口；`user_id` 上已有索引 | 接受每个请求多一次 HTTP 调用和一次查库 |
| 取不到 gToken、查不到记录、调用 core 出错时一律拒绝 | 如果放行，攻击者只要不传 gToken 或者换个格式就能绕过 | 接受 core 故障时名单内接口不可用 |
| 加密报文采用方案 B：按需解密，并把结果缓存在 request 上 | 只有需要校验的请求才会提前解密，现有加解密链路不变 | 放弃了方案 A（在 Filter 里统一提前解密，影响面大，还要自己处理异常响应）和方案 C（在 RequestBodyAdvice.afterBodyRead 里校验，校验被拆到两个地方，返回方式也不统一） |
| `MyRequestWrapper` 里的原始 body 保持为密文 | SignatureInterceptor 是用原始 body 验签的 | — |
| 拦截器里解密失败或验签失败，统一返回 `DECRYPT_FAIL` | advice 的 `@ExceptionHandler` 会把所有 `BusinessException` 都转成 `DECRYPT_FAIL`，这里保持一致 | 前端无法区分解密失败和验签失败（和改动前一样） |
| 日志字段名避开 `token` 等脱敏关键字，并把失败原因拆分成多种 | 第一版日志里的 `gToken`/`tokenUserId` 被 `SensitiveDataConverter` 打码，排查时多走了弯路 | gToken 的值仍然不打印 |
| 不写单元测试，靠联调验证 | 用户的决定 | — |
| 日志脱敏、token 过期检查不在这次范围内 | 用户的决定 | 已知风险：gToken 和明文密码仍然会出现在日志里；token 永久有效 |

### 待确认
| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| 在测试环境验证"选择市场后切换到新市场"和"越权"两个场景 | 两个都通过后，才能把生产的 `verifyGTokenUrls` 改回 `/login/switchLogin` | 开发 / 测试 |
| 线上 Nacos 里 `userSameSwitch` 的状态 | 如果已经开启，加密请求会开始做 userId 校验，之前被跳过的不一致请求会开始被拒绝 | 开发 / 运维 |
| （可选）在生产库执行 `SELECT COUNT(*) FROM (SELECT user_id FROM global_user_kycs GROUP BY user_id HAVING COUNT(DISTINCT server) > 1) t;` | 用数据证明 userId 没有跨服务器撞号（同步逻辑 `insertSyncUserKyc` 用的唯一键是 `(userId, countryCode)`，和"userId 全局唯一"的说法不完全吻合） | 开发 |
| 是否把 `/login/userInfo`、`/global/auth/user/unbind` 也加进名单 | 这两个接口同样直接信任 body 里的 gToken | 开发 |

## 8. 原型与附件

| 内容 | 文件或链接 | 对应的需求步骤 |
| --- | --- | --- |
| switchLogin 流程与越权分析 | [glc-web.md](./glc-web.md) | 背景 |
| 新增：越权校验拦截器 | `glc-web/.../interceptor/UserOwnershipInterceptor.java`（`verifyUserId` :68、`verifyGToken` :101） | 步骤 4、5，R1–R4 |
| 新增：请求体解密组件 | `glc-web/.../interceptor/RequestBodyDecryptor.java`（`getPlainBody` :54、`decrypt` :73） | R5、R6 |
| 修改：把解密逻辑抽到组件中 | `glc-web/.../interceptor/DecryptRequestBodyAdvice.java`（:104） | 步骤 6 |
| 修改：注册拦截器 | `glc-web/.../interceptor/WebAppConfigurer.java`（:69-72） | 步骤 4、5 |
| 修改：Feign 方法 | `glc-web/.../client/CoreClient.java`（:46 `queryGTokenList(userId)`） | 步骤 5 |
| 修改：名单配置 | `glc-web/.../config/CommonConfigs.java`（:306 `verifyGTokenUrls`） | R1 |
| 新增：core 查询接口 | `glc-core/.../controller/GlobalUserController.java`（:977 `GET global/user/query/gToken/{userId}`） | 步骤 5 |
| 新增：mapper | `glc-core/.../mapper/GlobalUserKycsMapper.xml`（:65 `selectGTokenListByUserId`） | 步骤 5 |
| 签发漂移 token 的接口举例 | `wt/wt-web/.../payer/controller/PayerController.java`（:117 `POST update`，:162 `setToken(旧userId, 请求体countryCode)`） | 背景 - 线上误拦 |
| 日志打码规则 | 公共包 `com.wotransfer.core.utils.SensitiveDataConverter`（在 glc-web 的 `logback-spring.xml:3` 中配置） | 第 4 节日志 |

## 9. 变更记录

| 日期 | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | --- | --- | --- |
| 2026-10-13 | 新增 GTokenInterceptor、core 的 gToken 查询接口和 `verifyGTokenUrls` 配置 | switchLogin 没有校验 gToken 是否属于当前用户 | R1–R3 |
| 2026-10-13 | 放弃 Redis 缓存方案，改为每次直接查库 | 用户决定简化实现 | R3 |
| 2026-10-13 | 新增 RequestBodyDecryptor；拦截器改为解密后再校验；DecryptRequestBodyAdvice 改为复用这个组件 | 加密报文会绕过 userId 校验，还会导致 gToken 校验误拦 | R3–R6 |
| 2026-10-14 | 把 GTokenInterceptor 和 TokenInterceptor 里的 userSameSwitch 校验合并到 `UserOwnershipInterceptor` | 越权校验集中管理 | R3、R4 |
| 2026-10-14 | 从查询单个 gToken 改为查询 gToken 列表，判断是否包含 | 一个 userId 可能对应多个 gToken（历史遗留） | R3 |
| 2026-10-22 | 线上误拦，在 Nacos 里把 `verifyGTokenUrls` 设为空，关闭校验 | 用户切换到新市场时被拦截：token 里的 countryCode 已被"选择市场"刷新为新市场 | R1 |
| 2026-10-23 | 查询条件从 `userId + countryCode` 改为只用 `userId`；core 接口改为 `query/gToken/{userId}`；删除"countryCode 为空就拒绝"的检查；日志字段名避开脱敏关键字，失败原因拆分为 `not found in db` 和 `not match` | token 里的 countryCode 不可信；userId 全局唯一（leader 已确认）；之前的日志被打码，无法排查 | R3、第 4 节日志、第 6 节新增回归场景 |

## 代码改动

**`UserOwnershipInterceptor.java`（新增，取代第一版的 GTokenInterceptor）**

- `verifyUserId`：开启 `userSameSwitch` 后，比较 query 参数或明文 body 顶层的 userId 与 token 里的 userId。这段逻辑原来在 TokenInterceptor 里，已经移过来。
- `verifyGToken`：对名单内的 URL，用 token 里的 userId 调用 `coreClient.queryGTokenList(userId)`，判断请求里的 gToken 是否在返回的列表中。不使用 token 里的 countryCode。
- 读取 body 时统一通过 `requestBodyDecryptor.getPlainBody`，加密请求也能正常校验。解密失败时直接拒绝请求。

**`RequestBodyDecryptor.java`（新增）**

- `DecryptRequestBodyAdvice` 里原有的解密和验签逻辑原样搬到这里，包括 Redis 和配置文件两个私钥来源、RSA/AES/HMAC、`ThreadContext` 标志位，以及"请求明文"日志。
- `getPlainBody(request)`：请求没有 `RS` 头时返回原始 body；有 `RS` 头时解密并验签，把明文存到 request 属性上，同一个请求只解密一次。
- `decrypt(request, cipherBody)`：供 advice 调用，会先检查缓存，有就直接使用。
- `MyRequestWrapper` 里的原始 body 仍然是密文，`SignatureInterceptor` 的验签不受影响。

**`DecryptRequestBodyAdvice.java`**

- `MyHttpInputMessage` 改为调用 `requestBodyDecryptor.decrypt(...)`，删掉了原来的解密代码以及不再用到的字段和 import。
- `@ExceptionHandler` 没有改动。

**glc-core**

- `GlobalUserController`：`GET query/gToken/{userId}`，返回 `List<String>`。
- `GlobalUserKycsMapper`：`selectGTokenListByUserId`，SQL 是 `select g_token from global_user_kycs where user_id=#{userId}`，不加 `limit`。

## 上线前需要注意

1. **重新开启校验的顺序**：先发布 glc-core 和 glc-web（生产上校验目前是关闭的，两者谁先发都可以）→ 在测试环境验证第 6 节的"选择市场后切换到新市场"和"越权"两个场景 → 都通过后，把生产 Nacos 里的 `verifyGTokenUrls` 改回 `/login/switchLogin`。
2. **关闭校验的方法**：`verifyGTokenUrls` 必须显式配置为空字符串。如果直接删掉这个配置项，就会用代码里的默认值 `/login/switchLogin,`，校验会被重新打开。
3. **`userSameSwitch` 的状态**：如果已经开启，上线后加密请求会马上开始做 userId 一致性校验。
4. **排查方法**：在日志里搜 `ownership verify fail`。如果原因是 `gtk not found in db`，说明这个 userId 在库里没有任何 gToken；如果是 `gtk not match`，说明查到了列表（`dbCount`），但请求里的 gToken 不在列表中。
