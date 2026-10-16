# [越权检查-17] switchLogin gToken 归属校验 + 加密报文解密后校验

> 状态：待确认（代码已完成，JDK 17 编译通过，未联调）
> 模块及适用范围：glc-web（拦截器、解密）、glc-core（新增查询接口）；分支 `cze-越权`（从 release 新建）
> 负责人：erzhuochen
> 最后更新：2026-10-13

## 两分钟回忆

- **为什么做**：`/login/switchLogin` 只用请求体里的 `gToken + countryCode` 来定位要切换的账号，没有校验这个 `gToken` 属不属于当前登录用户。A 拿着自己的 token、填上 B 的 gToken，就能读取 B 的 KYC 信息，并以 B 的身份触发 switchCountry 或 autoRegister。另外，客户端带 `RS` 头时请求体是密文，拦截器读不到明文，`userSameSwitch` 的 userId 校验会被直接跳过，gToken 校验也取不到值。
- **一句话方案**：
  - 新增 `GTokenInterceptor`：对配置名单里的 URL，取 token 中的 `userId + countryCode`，调用 core 查数据库里的 gToken，与请求体里的 gToken 比较，不一致就拒绝。
  - 新增 `RequestBodyDecryptor`：按需解密请求体并缓存在 request 上，让两个拦截器都能在解密后再做校验。
- **核心链路**：请求 → SignatureInterceptor（对密文原文验签）→ TokenInterceptor（解析 token；开启 userSameSwitch 时，解密后比较 userId）→ GTokenInterceptor（在名单内则解密后比较 gToken）→ DecryptRequestBodyAdvice（复用已解密的明文）→ Controller。
- **最容易忘的细节**：
  - 解密发生在 `RequestBodyAdvice`，它在**所有拦截器之后**才执行，所以拦截器原本拿不到明文。
  - `MyRequestWrapper` 里的原始 body 必须保持密文，否则 SignatureInterceptor 验签会失败。
  - 拦截器里解密失败和验签失败都统一返回 `DECRYPT_FAIL`，和 advice 的 `@ExceptionHandler` 保持一致。
  - `verifyGTokenUrls` 的代码默认值是 `/login/switchLogin,`，不在 Nacos 配置也会生效。
  - 查询条件必须是 `userId + countryCode`，因为不同市场的 userId 可能重复。
- **当时的取舍**：
  - 没有加 Redis 缓存，每次直接查库：名单里接口少，开销可以接受。
  - 没有在 Filter 里统一解密（影响面太大），也没有把校验挪到 RequestBodyAdvice（同一类校验会被拆到两处）。
  - 日志脱敏和 token 过期检查都不在这次范围内。
- **当前待确认**：线上 Nacos 的 `userSameSwitch` 状态；`global_user_kycs` 的索引；名单内接口的客户端请求是否在 body 顶层带 `gToken`。

## 1. 背景、目标与范围

### 背景
- **gToken 是什么**：它是"全球账号"的标识，创建全球账号时用 `UUIDUtils.getUUIDString()` 生成，永久不变、没有签名、不会过期，存在 `global_user`、`global_user_kycs` 等表里。真正的登录凭证是请求头里的 `token`，它是 AES 加密加 HMAC 的自包含令牌，内含 `userId` 和 `countryCode` 等信息，但不包含 gToken，两者在代码里也没有关联。
- **switchLogin 的问题**：core 的 `GlobalUserController.switchLogin` 只按 `gToken + countryCode + server + vendor` 查 `global_user_kycs`。查到后，会用这条映射里的 userId 覆盖请求里的 `id`。web 层把 token 转发给了 core，但 core 没有用它。
- **攻击前提**：攻击者需要先拿到别人的 gToken。gToken 只会返回给本人，`/login/captcha/verify` 也要先通过验证码。但 glc-core 里有 20 多处日志明文打印了 gToken，所以能接触日志的人可以批量拿到 gToken，而日志里拿不到 token。这次修复就是堵住"拿到 gToken 等于能操作这个账号"这条路。
- **加密报文的问题**：客户端带 `RS` 头时，请求体是 `{"data":"signKey$aesKey$data$sign"}` 这样的密文。`TokenInterceptor.userSameSwitch` 取不到 userId 就直接放行（原代码注释写着"加密报文自然跳过"），等于留了一个绕过口子；而 gToken 校验取不到值就会拒绝，导致正常的加密请求也会被误拦。

### 目标
- 名单里的接口，请求体中的 gToken 必须属于 token 里的用户，否则拒绝。
- 不论请求是明文还是加密报文，userId 和 gToken 的校验都在解密之后进行，堵住加密报文的绕过口子。
- 不改变现有的加解密、响应加密、签名校验行为。

### 范围
- 包含：
  - glc-web：新增 `GTokenInterceptor`、`RequestBodyDecryptor`；修改 `TokenInterceptor`、`DecryptRequestBodyAdvice`、`WebAppConfigurer`、`CoreClient`、`CommonConfigs`。
  - glc-core：在 `GlobalUserController` 新增 gToken 查询接口。
- 不包含：
  - 白名单接口（`/login/set/password`、`/phone/bind`、`/email/bind`、`/verifyUser`、`/password/verify` 等，这些是未登录流程，没有 token 可以绑定）；
  - 日志脱敏（包括 `GlobalUserController.java:270` 明文打印密码的问题）；
  - token 过期检查（目前只判断了 `timestamp == 0`）；
  - core 侧 switchLogin 的业务逻辑。
- 涉及的市场、用户、系统或模块：所有市场；需要登录、又在 `verifyGTokenUrls` 名单里的接口；开启 `userSameSwitch` 后的所有接口。

## 2. 完整业务链路

| 步骤 | 触发者与触发时点 | 前置条件 | 系统动作 | 页面或数据结果 | 取消、失败或例外 |
| --- | --- | --- | --- | --- | --- |
| 1 | 客户端请求进入 | 无 | `HttpServletRequestReplacedFilter` 用 `MyRequestWrapper` 缓存原始 body，加密请求缓存的就是密文 | body 可以重复读取 | 无 |
| 2 | 拦截器 `SignatureInterceptor` | 带 `AUTH-SIGNATURE` 头 | 对**原始 body**（加密请求即密文）加时间戳做 RSA 验签 | — | 验签失败返回 `SIGNATURE_FAIL` |
| 3 | 拦截器 `TokenInterceptor` | 不在 excludePaths 里 | 解析 token，得到 `tokenObj`；做黑名单、环境等检查 | request 属性 `tokenObj` | 白名单 IP 且没带 token 时放行 |
| 4 | `TokenInterceptor` 中的 userSameSwitch | `userSameSwitch=true` | 先取 query 参数 `userId`；没有的话，调 `RequestBodyDecryptor.getPlainBody` 拿到明文，取顶层 `userId`，与 token 里的 userId 比较 | 加密请求的明文缓存到 request 属性 | 解密失败返回 `DECRYPT_FAIL`；不一致返回 `USER_NOT_LOGIN`；body 里没有 userId 则放行 |
| 5 | 拦截器 `GTokenInterceptor` | URL 匹配 `verifyGTokenUrls` | 取 `tokenObj` 的 userId 和 countryCode → 调 `getPlainBody` 拿明文，取顶层 `gToken` → Feign 调 core `query/gToken/{userId}/{countryCode}` → 比较两个 gToken | — | 见规则 R3 |
| 6 | `DecryptRequestBodyAdvice.beforeBodyRead` | Controller 有 `@RequestBody` 参数且请求带 `RS` 头 | 调 `requestBodyDecryptor.decrypt`，如果第 4 或第 5 步已经解密过，直接复用缓存 | Controller 收到明文对象 | 抛 `BusinessException` 后由 `@ExceptionHandler` 统一返回 `DECRYPT_FAIL` |
| 7 | Controller / core | 前面都通过 | 原有业务逻辑 | — | — |
| 8 | `EncryptResponseBodyAdvice` | 带 `RS` 头且业务处理成功 | 加密响应（未改动） | — | 失败响应 `!isSuc()` 不加密 |

## 3. 具体规则

| 规则编号 | 触发时点 | 命中条件与匹配对象 | 处理动作 | 适用范围 | 例外及优先级 |
| --- | --- | --- | --- | --- | --- |
| R1 | 名单匹配 | 请求路径（去掉 contextPath）用 `AntPathMatcher` 匹配 `common.verifyGTokenUrls` 中逗号分隔的任意一项 | 匹配上才进入 gToken 校验 | glc-web 全部路径 | 名单为空等于关闭校验 |
| R2 | gToken 校验开始前 | 请求没带 `token` 头，且 IP 在 `userWhiteList` 里 | 放行 | 名单内 URL | 与 TokenInterceptor 的白名单逻辑保持一致 |
| R3 | gToken 校验 | 以下任一情况：`tokenObj` 为空、userId 为 0、countryCode 为空、body 不是 JSON、body 顶层没有 `gToken`、调 core 出异常、数据库查不到、两个 gToken 不相等 | 拒绝，返回 `USER_NOT_LOGIN`（和 TokenInterceptor 的 `outputResponse` 同一格式），记 error 日志（uri、tokenUserId、countryCode，**不打印 gToken**） | 名单内 URL | 解密失败按 R5 处理 |
| R4 | userId 校验 | `userSameSwitch=true`，且 query 参数或明文 body 顶层有 `userId` | 和 token 里的 userId 不相等就拒绝，返回 `USER_NOT_LOGIN` | TokenInterceptor 覆盖的全部路径 | 取不到 userId 时放行（保持原有逻辑） |
| R5 | 拦截器里的解密 | 请求带 `RS` 头，且需要读取 body | 调 `RequestBodyDecryptor` 解密并验签，失败就拒绝，返回 `DECRYPT_FAIL` | R3、R4 | 解密失败、验签失败、私钥为空，都统一返回 `DECRYPT_FAIL`（和 advice 一致） |
| R6 | 解密缓存 | 同一个请求已经解密成功 | 直接返回 request 属性 `GLC_DECRYPTED_PLAIN_BODY` 里的明文 | 拦截器和 advice | 解密失败不缓存，advice 会再尝试一次，然后由 `@ExceptionHandler` 处理 |

## 4. 页面、字段与权限（按需保留）

### 页面交互
无页面改动。前端在校验失败时收到的错误码，都是现有错误码（`USER_NOT_LOGIN` / `DECRYPT_FAIL`），失败响应也不会被加密，所以前端不需要适配。

### 数据字段
| 字段 | 来源 | 何时记录或更新 | 用途 | 特殊说明 |
| --- | --- | --- | --- | --- |
| `common.verifyGTokenUrls` | Nacos `logincenter.yml` / `CommonConfigs` 默认值 | 配置变更后刷新 | gToken 校验名单 | 代码默认值是 `/login/switchLogin,` |
| `common.userSameSwitch` | Nacos `logincenter.yml` | 同上 | userId 一致性校验开关 | 代码默认值是 `false` |
| request 属性 `GLC_DECRYPTED_PLAIN_BODY` | `RequestBodyDecryptor` | 第一次解密成功时 | 同一请求内复用明文 | 只在请求内有效 |
| `global_user_kycs.g_token` | 数据库 | 已有 | 按 `user_id + country_code` 查出 gToken | 复用 `selectGTokenByUserIdAndCountryCode` |

### 权限与操作记录
- 校验失败时记 error 日志：`gToken verify fail, <原因>, uri=..., tokenUserId=..., countryCode=...`；
- userId 不一致时沿用原有日志 `userId verify fail, ...`。

## 5. 边界与异常

- **跨市场、跨设备、重复操作**：
  - 查询条件是 token 里的 `userId + countryCode`，也就是当前登录的市场，不是要切换到的目标市场。switchLogin 请求里的 gToken 应该是当前用户的全球 gToken，各个市场共用这一个值，所以可以直接比较。
  - 重复请求由 SignatureInterceptor 负责防重放，这次没有改动。
- **数据缺失或变化时**：
  - 数据库查不到映射（比如老数据）时拒绝。
  - core 不可用时，名单内的接口全部会被拒绝。
  - 因为没有缓存，映射变化后马上就会生效。
- **撤销、解除、放行或回退时**：
  - 把 Nacos 里的 `verifyGTokenUrls` 设成空字符串，就能关闭 gToken 校验。
  - `userSameSwitch=false` 时会关闭 userId 校验，同时拦截器也不会再提前解密。
- **与其他规则同时命中时**：执行顺序是 SignatureInterceptor → MerchantInterceptor → TokenInterceptor → GTokenInterceptor，前面任何一个拒绝，后面的就不会执行。GTokenInterceptor 依赖 `tokenObj`，所以必须注册在 TokenInterceptor 之后。

## 6. 验收场景

| 场景 | 给定条件 | 执行操作 | 预期结果 |
| --- | --- | --- | --- |
| 正常流程-明文 | A 登录，body 里是 A 的 gToken | 调 `/login/switchLogin` | 正常切换 |
| 正常流程-加密 | A 登录，带 `RS` 头，加密 body 里是 A 的 gToken | 调 `/login/switchLogin` | 正常切换；同一请求只解密一次（"请求明文"日志只打印一次） |
| 越权-明文 | A 的 token，body 里是 B 的 gToken | 调 `/login/switchLogin` | 返回 `USER_NOT_LOGIN`，有 `gToken not match` 日志 |
| 越权-加密 | A 的 token，加密 body 里是 B 的 gToken | 调 `/login/switchLogin` | 返回 `USER_NOT_LOGIN` |
| 缺少 gToken | 名单内接口，body 里没有 `gToken` | 调用 | 返回 `USER_NOT_LOGIN`，有 `gToken not found` 日志 |
| 报文篡改 | 带 `RS` 头，密文或签名被改 | 调名单内接口 | 返回 `DECRYPT_FAIL` |
| userId 加密绕过 | `userSameSwitch=true`，A 的 token，加密 body 里 `userId` 是 B | 调任意需要登录的接口 | 返回 `USER_NOT_LOGIN`（之前会被放行） |
| 不在名单内的加密接口 | 带 `RS` 头 | 调普通接口 | Controller 能正常收到明文，行为和改动前一样 |
| core 不可用 | glc-core 还没部署新接口 | 调名单内接口 | 返回 `USER_NOT_LOGIN`，有 `query gToken error` 日志 |

## 7. 关键决定与待确认

### 关键决定
| 决定 | 原因或依据 | 放弃的方案 / 已接受的风险 |
| --- | --- | --- |
| 用 URL 名单，在拦截器里比较请求 gToken 和数据库 gToken | 可以通过配置扩展到其他接口，不需要改 Controller | 放弃了"服务端直接用 token 推导 gToken、忽略入参"的做法 |
| 按 `userId + countryCode` 查询 | 不同市场的 userId 来自各自独立的系统，可能重复 | 放弃了只按 userId 查（`queryGTokenByUserId` 用的是 `limit 1`，可能查到别的市场的记录） |
| 不加缓存，每次 Feign 调 core 查库 | 名单里接口少；gToken 映射不会变 | 接受每个请求多一次 HTTP 调用加一次查库；需要确认索引 |
| 取不到 gToken、查不到映射、core 出错时一律拒绝 | 如果放行，攻击者只要不传或换个格式就能绕过 | 接受 core 故障时名单内接口不可用 |
| 新建独立的 `GTokenInterceptor` | TokenInterceptor 已经很长；拆开后可以独立开关 | — |
| 加密报文采用方案 B：按需解密并缓存在 request 上 | 只有需要校验的请求才会提前解密，现有加解密链路不变 | 放弃方案 A（在 Filter 里统一提前解密，影响面大，还要自己处理异常响应）和方案 C（在 RequestBodyAdvice.afterBodyRead 里校验，同一类校验被拆到两处，返回方式也不统一） |
| `MyRequestWrapper` 的原始 body 保持密文 | SignatureInterceptor 是对原始 body 验签的 | — |
| 拦截器里解密或验签失败统一返回 `DECRYPT_FAIL` | advice 的 `@ExceptionHandler` 会把所有 `BusinessException` 都转成 `DECRYPT_FAIL`，保持一致 | 前端无法区分解密失败和验签失败（和改动前一样） |
| 私钥为空时保持原有行为（最后验签失败） | 兼容 | — |
| 不写单元测试，靠联调验证 | 用户决定 | — |
| 日志脱敏、token 过期检查不在这次范围内 | 用户决定 | 已知风险：gToken 和明文密码仍然会出现在日志里；token 永久有效 |

### 待确认
| 问题 | 为什么影响实施 | 需要谁确认 |
| --- | --- | --- |
| 线上 Nacos 里 `userSameSwitch` 的状态 | 如果已经开启，上线后加密请求会马上开始校验 userId，之前被跳过的不一致请求会开始被拒绝 | 开发 / 运维 |
| `global_user_kycs` 有没有 `(user_id, country_code)` 索引 | 每个名单内请求都会查一次，没有索引会全表扫描 | DBA |
| 名单内接口的客户端请求是否都在 body 顶层带 `gToken` | 不带就会被误拦 | 前端 / 联调 |
| 部署顺序 | `verifyGTokenUrls` 默认就包含 switchLogin，**必须先部署 glc-core 再部署 glc-web**，否则 switchLogin 请求会全部被拒绝 | 发布负责人 |
| 是否把 `/login/userInfo`、`/global/auth/user/unbind` 加进名单 | 这两个接口也信任 body 里的 gToken | 开发 |

## 8. 原型与附件

| 内容 | 文件或链接 | 对应的需求步骤 |
| --- | --- | --- |
| switchLogin 流程与越权分析 | [glc-web.md](./glc-web.md) | 背景 |
| 新增：gToken 校验拦截器 | `glc-web/.../interceptor/GTokenInterceptor.java` | 步骤 5，R1–R3 |
| 新增：请求体解密组件 | `glc-web/.../interceptor/RequestBodyDecryptor.java`（`getPlainBody` :54、`decrypt` :73） | R5、R6 |
| 修改：userId 校验改为解密后进行 | `glc-web/.../interceptor/TokenInterceptor.java`（:111 起、`getParamUserId`） | 步骤 4，R4 |
| 修改：解密逻辑抽取到组件中 | `glc-web/.../interceptor/DecryptRequestBodyAdvice.java`（:104） | 步骤 6 |
| 修改：注册拦截器 | `glc-web/.../interceptor/WebAppConfigurer.java`（:70） | 步骤 5 |
| 修改：Feign 方法 | `glc-web/.../client/CoreClient.java`（:44 `queryGToken`） | 步骤 5 |
| 修改：名单配置 | `glc-web/.../config/CommonConfigs.java`（:306 `verifyGTokenUrls`） | R1 |
| 新增：core 查询接口 | `glc-core/.../controller/GlobalUserController.java`（:977 `GET global/user/query/gToken/{userId}/{countryCode}`） | 步骤 5 |

## 9. 变更记录

| 日期  | 改了什么 | 为什么改 | 影响哪些规则或场景 |
| --- | ---- | ---- | --------- |
| 2026-10-13 | 新增 GTokenInterceptor、core 的 gToken 查询接口和 `verifyGTokenUrls` 配置 | switchLogin 没有校验 gToken 的归属 | R1–R3 |
| 2026-10-13 | 去掉 Redis 缓存方案，改为每次直接查库 | 用户决定，简化实现 | R3 |
| 2026-10-13 | 新增 RequestBodyDecryptor；TokenInterceptor 和 GTokenInterceptor 改为解密后再校验；DecryptRequestBodyAdvice 改为复用组件 | 加密报文会绕过 userId 校验，并导致 gToken 校验误拦 | R3–R6 |
## 代码改动

**新增 `RequestBodyDecryptor.java`**

- 原来 `DecryptRequestBodyAdvice` 里的解密和验签逻辑原样搬到了这里，包括 Redis 和配置文件两处私钥来源、RSA/AES/HMAC、`ThreadContext` 标志位、"请求明文"日志。
- `getPlainBody(request)`：请求没有 `RS` 头时返回原始 body；有 `RS` 头时解密并验签，明文存进 request 属性，同一个请求只解密一次。
- `decrypt(request, cipherBody)`：给 advice 调用，会先看缓存，有就直接用。
- `MyRequestWrapper` 里的原始 body 仍然是密文，`SignatureInterceptor` 的验签不受影响。

**`DecryptRequestBodyAdvice.java`**

- `MyHttpInputMessage` 改为调用 `requestBodyDecryptor.decrypt(...)`，删掉了原来那段解密代码和已经不再使用的字段、import。
- `@ExceptionHandler` 没有改动。

**`TokenInterceptor.java`**

- `userSameSwitch` 的 `getParamUserId` 改为从 `getPlainBody` 读取 body，加密请求现在也会校验 userId 是否一致。
- 解密失败时直接拒绝请求。

**`GTokenInterceptor.java`**

- `getParamGToken` 改为从 `getPlainBody` 读取 body，名单里的接口现在也可以使用加密报文。
- 解密失败时直接拒绝请求。
- `outputResponse` 加了一个可以传错误码的重载。

## 上线前需要注意

1. **Nacos 里 `userSameSwitch` 的状态**：如果已经开启，上线后加密请求会立刻开始校验 userId 是否一致。
2. **`verifyGTokenUrls` 的默认值**：`CommonConfigs` 里这个默认值被改成了 `"/login/switchLogin,"`（这是你在本地改的）。这样即使 Nacos 没有配置，switchLogin 也会被校验，所以**必须先部署 glc-core**，否则 Feign 调用会失败，所有 switchLogin 请求都会被拒绝。
3. **联调建议覆盖这些场景**：
    - 明文请求，URL 在名单内和不在名单内各测一次；
    - 加密请求，gToken 正确时放行，gToken 错误时拒绝；
    - 篡改加密报文，应返回 `DECRYPT_FAIL`；
    - 不在名单内的普通加密接口，确认 Controller 能正常收到明文。