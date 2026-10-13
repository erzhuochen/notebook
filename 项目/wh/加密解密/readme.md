# glc 项目加密解密流程

> 项目：`D:\workspace\wh\glc`（`glc-web` 对外网关 + `glc-core` 内部服务）
> 加解密工具类大多在外部 jar `com.wotransfer:core:3.0.1-SNAPSHOT` 中（`AES2Util`、`RsaUtil`、`SignatureUtil`、`AlgorithmUtil`、`TokenManagerUtil`），没有源码，下文涉及它们的细节来自 `javap` 反编译字节码。

项目里一共有 5 套相互独立的加密/签名机制：

| # | 机制 | 位置 | 作用 |
|---|---|---|---|
| 1 | 报文加解密（RS 协议） | glc-web `DecryptRequestBodyAdvice` / `EncryptResponseBodyAdvice` / `RequestBodyDecryptor` | 客户端 ↔ glc-web 的请求体、响应体加密 |
| 2 | 请求签名 | glc-web `SignatureInterceptor` | 第三方直调接口的 RSA 验签 + 防重放 |
| 3 | 登录 token | 外部 jar `TokenInputUtil` / `TokenManagerUtil` | 请求头 `token` 的生成与解析 |
| 4 | 服务端间加密调用 | glc-core `CryptoComponent.sendEncryptedHttpRequest` | glc-core → 各国后端，复用 RS 协议 |
| 5 | 数据库字段加密 | glc-core `CryptoComponent` | 密码、手机号、邮箱落库加密 |

---

## 0. 一个请求在 glc-web 中的完整处理顺序

```
HTTP 请求
 │
 ├─ Filter: HttpServletRequestReplacedFilter
 │     把 request 包成 MyRequestWrapper，body 读成字符串缓存，可重复读（此时仍是密文）
 │
 ├─ DispatcherServlet
 │   ├─ 拦截器 preHandle（按注册顺序）
 │   │    1. SignatureInterceptor   有 AUTH-SIGNATURE 头 → 对【原始 body】RSA 验签
 │   │    2. MerchantInterceptor    商户码
 │   │    3. TokenInterceptor       解析 token 头 → request 属性 tokenObj；userSameSwitch 时比对 body.userId
 │   │    4. GTokenInterceptor      名单内 URL：比对 body.gToken 与 token 用户在库中的 gToken
 │   │       （3、4 需要 body 字段时调用 RequestBodyDecryptor.getPlainBody，按需提前解密）
 │   │
 │   ├─ 参数解析：@RequestBody
 │   │    RequestBodyAdvice.beforeBodyRead → DecryptRequestBodyAdvice
 │   │       有 RS 头 → RequestBodyDecryptor.decrypt（拦截器解过就直接用缓存）
 │   │    HttpMessageConverter 反序列化 → Controller 参数
 │   │
 │   ├─ Controller 方法
 │   │
 │   └─ ResponseBodyAdvice.beforeBodyWrite → EncryptResponseBodyAdvice
 │        有 RS 头 且 成功 且 URL 在加密名单 → 加密响应
 │
HTTP 响应
```

要点：
- **`RequestBodyAdvice` 一定在所有拦截器之后执行**。它是 `@RequestBody` 参数解析的一环，而参数解析发生在 `applyPreHandle` 全部通过之后（`DispatcherServlet.doDispatch` 中 `ha.handle()` 之前先执行 `applyPreHandle`）。所以拦截器直接读 body 只能读到密文。
- Controller 方法没有 `@RequestBody` 参数时，`RequestBodyAdvice` 根本不执行，请求体也就不会被解密。
- `DecryptRequestBodyAdvice` 上的 `@Order(2)` 只决定它在多个 `RequestBodyAdvice` 之间的顺序，不能让它排到拦截器前面。

---

## 1. 报文加解密（RS 协议）

### 1.1 报文格式

加密后的请求体、响应体都是：

```json
{ "data": "RSA(hmacKey)$RSA(aesKey)$AES(明文)$HMAC(明文)" }
```

| 段 | 内容 |
|---|---|
| `rawData[0]` | 用 RSA 公钥加密的 hmacKey |
| `rawData[1]` | 用 RSA 公钥加密的 aesKey |
| `rawData[2]` | 用 aesKey 对明文 JSON 做 AES 加密的结果（Base64） |
| `rawData[3]` | 用 hmacKey 对**明文**做 HMAC-SHA256 的签名（Base64） |

### 1.2 算法

| 环节 | 实现 |
|---|---|
| 随机密钥 | `AlgorithmUtil.getRandomAesKey()`：`KeyGenerator("AES")` 128 位，`SecureRandom("SHA1PRNG")`，用 UUID 作种子。aesKey 和 hmacKey 每次各生成一个 |
| 对称加密 | `AES2Util.encrypt/decrypt(data, key, iv)`：`AES/CBC/PKCS5Padding`（BouncyCastle），**IV 固定为常量 `AES_NONCE = "Kwed#^6e34ons*&J"`** |
| 非对称加密 | `RsaUtil.rsaEncrypt/rsaDecrypt`：私钥为 PKCS8 格式，`Cipher.getInstance("RSA")`，即 JDK 默认的 `RSA/ECB/PKCS1Padding` |
| 完整性 | `SignatureUtil.sha256HMACSignBase64(明文, hmacKey)` |

这是典型的**数字信封**：用 RSA 传输随机的对称密钥，用 AES 加密数据本体，用 HMAC 保证完整性。

### 1.3 触发条件：请求头 `RS`

- **请求**：只要请求头带 `RS`（值不为空），body 就会被当作密文解密。**加不加密由客户端决定**。
- **响应**：见 1.5。

### 1.4 请求解密（客户端 → glc-web）

核心逻辑在 `glc-web/.../interceptor/RequestBodyDecryptor.java`（原本写在 `DecryptRequestBodyAdvice.MyHttpInputMessage` 里，后来抽出来给拦截器共用）。

```
1. JSON.parseObject(body).getString("data").split("\\$") → 4 段
2. 取服务端私钥：Redis "Panda-Server-RSA-Pri"，取不到就用配置 common.serverPriKey
3. aesKey  = RSA 私钥解密 rawData[1]
   data    = AES 解密 rawData[2]（aesKey + 固定 IV）
   hmacKey = RSA 私钥解密 rawData[0]
   ↳ 这一段出现任何异常：ThreadContext.decrypt = false，抛 BusinessException(DECRYPT_FAIL)
4. 重新计算 HMAC(data, hmacKey)，和 rawData[3] 比较
   ThreadContext.sign = 比较结果
   ↳ 不相等：抛 BusinessException(SIGN_VERIFY_FAIL)
5. 明文存入 request 属性 GLC_DECRYPTED_PLAIN_BODY，同一请求只解密一次
```

两个入口：
- `getPlainBody(request)`：给拦截器用。没有 RS 头时直接返回原始 body。
- `decrypt(request, cipherBody)`：给 `DecryptRequestBodyAdvice` 用。

失败时前端收到什么：
- 在 advice 中失败：`DecryptRequestBodyAdvice` 的 `@ExceptionHandler(BusinessException.class)` 会把**所有** `BusinessException` 都转成 `DECRYPT_FAIL`。所以解密失败、验签失败、私钥为空，前端看到的**都是 `DECRYPT_FAIL`**。
- 在拦截器中失败：`TokenInterceptor` 和 `GTokenInterceptor` 自己 `outputResponse(DECRYPT_FAIL)`，和上面保持一致。
- 私钥为空时不会抛解密异常，data 和 hmacKey 都是空串，然后在第 4 步验签失败。

`ThreadContext`（ThreadLocal）里有 3 个标志位，每次在 `beforeBodyRead` 时 `init()`：
- `needRSA`：请求是否带 RS 头
- `decrypt`：解密是否成功
- `sign`：验签是否成功

### 1.5 响应加密（glc-web → 客户端）

位置：`glc-web/.../interceptor/EncryptResponseBodyAdvice.java`

```
if 请求头没有 RS            → 原样返回
pubKey = 客户端公钥（见下）
if pubKey 为空：
    成功响应 → 改成 SECURE_CREDENTIAL_EXPIRED 返回
    失败响应 → 原样返回
if common.encode.configEncodeFlag == true 且 URL 不在 common.encode.uris 里 → 原样返回
if 响应不是成功（!isSuc）   → 原样返回（错误响应永远是明文）
否则：
    生成 aesKey、hmacKey
    data = AES(JSON(响应), aesKey)
    sign = HMAC(JSON(响应), hmacKey)
    用客户端公钥 RSA 加密 aesKey、hmacKey
    响应头加 RS: 1
    返回 {"data": "RSA(hmacKey)$RSA(aesKey)$data$sign"}
加密过程中出现任何异常 → 记日志，返回明文
```

客户端公钥从 Redis 取，key 带年月后缀（`DateUtils.getCurrDateStr()` 是 `yyyyMMdd`，取前 6 位）：
- `RSA-0-pub-{yyyyMM}`
- `RSA-1-pub-{yyyyMM}`（两个都存在时**以 RSA-1 为准**）

配置（前缀 `common.encode`，`EncodeUrlDataConfig`）：
- `uris`：需要加密响应的 URL，逗号分隔，**精确匹配**，默认是 `/web/user/login`
- `configEncodeFlag`：默认 `true`。为 true 时只加密名单内的 URL；为 false 时所有带 RS 头的成功响应都加密

### 1.6 密钥汇总

| 方向 | 加密方用 | 解密方用 | 存放位置 |
|---|---|---|---|
| 客户端 → glc-web | 服务端公钥（客户端持有） | 服务端私钥 | Redis `Panda-Server-RSA-Pri`，兜底配置 `common.serverPriKey` |
| glc-web → 客户端 | 客户端公钥 | 客户端私钥（客户端持有） | Redis `RSA-0-pub-yyyyMM` / `RSA-1-pub-yyyyMM` |

---

## 2. 请求签名（SignatureInterceptor）

位置：`glc-web/.../interceptor/SignatureInterceptor.java`，拦截器顺序 1，作用于所有路径。用于第三方直调接口。

**请求头带 `AUTH-SIGNATURE` 时：**
1. 时效校验：`AUTH-TIMESTAMP` 距今超过 `glc.common.signature.expireTime`（默认 3 分钟）→ `INTERFACE_TIMEOUT`
2. 防重放：`MD5(sign + uri)` 作为 Redis key，已存在 → 直接返回 `SUCCESS_CODE` 并拦截；不存在就写入，TTL 为 expireTime
3. 验签：`SHA1withRSA`，公钥是 `glc.common.signature.publicKey`，签名内容是 **原始 body + timestamp**，失败 → `SIGNATURE_FAIL`

**没有签名头时：** 解析 token。如果是韩国 token，且 `source` 在 `whiteSource`（默认 `2,3,4`）里，返回 401 `SIGNATURE_FAIL`。也就是说韩国的这些客户端来源必须走签名。

⚠️ 签名是对**原始 body**（加密请求就是密文）计算的。所以任何改造都**不能**把 `MyRequestWrapper` 里的原始 body 替换成明文，否则签名会失败。

---

## 3. 登录 token（请求头 `token`）

工具类在外部 jar 里：`TokenInputUtil`（业务封装）和 `TokenManagerUtil`（底层加解密）。

**明文内容**（`key=value` 用 `#` 连接），例如：
```
userId=%d#kycStatus=%d#env=%s#countryCode=%s#lang=%d#timestamp=%d
```

**生成**（`TokenManagerUtil.generateToken`）：
1. 随机生成 3 个 key（`generateRandomKey`）
2. 每个 key 和 `MASTER_KEY` 做 XOR 混淆（`calcXorKey`）
3. 用 `AesUtil.aesEncrypt` 加密明文，再用其中一个 key 对密文做 `HMAC-SHA256`
4. 各段 Base64 后，按 `%s#%s#%s#%s#%s` 拼成 5 段

**解析**（`parseTokenStr`）：按 `#` 拆开 → `reverseKey` 还原 key → 重算 HMAC 比对（不一致时打日志 `sha256 hash compare result is not equal`）→ AES 解密。

**特点：**
- 自包含：服务端不存 token，没有吊销机制。
- `TokenInterceptor` 只拒绝 `timestamp == 0` 的 token，**没有过期检查**。
- 下发：登录、注册时调用 `TokenInputUtil.setToken2UsersResponse`，放进 `ResultRich.responseHeader.token`。
- 拦截器解析后存入 request 属性 `tokenObj`（`BaseConst.TOKEN_OBJ`），Controller 用 `TokenInputUtil.getTokenInputObj(request)` 获取。

---

## 4. 服务端间加密调用（glc-core → 各国后端）

位置：`glc-core/.../utils/CryptoComponent.java`，`sendEncryptedHttpRequest` / `sendExtraEncryptedHttpRequest` / `sendEncryptedHttpRequestByResEntity`。glc-core 的 `backendPost` 就是调用的这几个方法。

使用**和第 1 节相同的 RS 报文协议**，只是 glc-core 站在客户端的角色：

```
请求：
  请求头 RS: 1，token: <写死的固定 token>
  body = encryptRequest(data)
       aesKey/hmacKey 随机生成，用后端公钥加密（Redis "Panda-Server-RSA-Pub"）
POST commonConfigs.getServerUrl(server) + uri

响应：decryptRequest(responseBody)
  data 字段不含 "$" → 当作明文直接解析
  私钥：Redis "SERVER_PRI_KEY"
        取不到 → GET common.serverKeyUrl?version=1 获取并写入 Redis
        私钥 = 返回 model 中 f + a + e + c 四个字段拼接
  解密或验签出现异常 → 重新拉取一次私钥再试
  验签不通过 / 最终失败 → 把原始响应当作明文解析返回（不报错）
```

glc-core **自己没有** `RequestBodyAdvice` / `ResponseBodyAdvice`。glc-web 通过 Feign 调用 glc-core 时是明文。

---

## 5. 数据库字段加密（glc-core）

位置：`CryptoComponent`

**密钥加载（信封加密）**：
- 配置项：`login.key` / `encrypt.key`（明文 key），或者 `login.dek` / `encrypt.dek`（被加密的 DEK）
- 如果 KEK 文件 `encrypt.kek.path`（默认 `/home/key/panda_kek_1.0.key`）存在，并且配置了 DEK，就用 KEK 解密 DEK，得到 `loginKey` / `dataKey`

**用途**：

| 方法 | 密钥 | 算法 | 用于 |
|---|---|---|---|
| `encryptPassword` / `decryptPassword` | loginKey | `AesUtil.encryptWithBC` | 密码 |
| `encryptField` / `decryptField` | dataKey | `AesUtil.aesEncrypt`，IV 为 `BaseConst.AES_NONCE` | 通用字段 |
| `encryptUserFields` / `encryptGlobalUserFields` | dataKey | 同上 | 手机号、邮箱：密文存 `xxxMask`，MD5 存 `xxxMd5`（用于等值查询），原字段存脱敏值 |
| `decryptUserFields` / `decryptGlobalUserFields` | dataKey | 同上 | 原字段含 `*` 时，从 `xxxMask` 解密还原 |

邮箱在加密和计算 MD5 之前会先转成小写。

---

## 6. 为什么要按需解密（gToken 越权校验改造，2026-10）

**背景**：`/login/switchLogin` 等接口用 body 里的 `gToken` 定位用户，但没有校验它是否属于 token 中的用户。为此新增了 `GTokenInterceptor`，名单由 `common.verifyGTokenUrls` 配置；`TokenInterceptor` 原本也有 `userSameSwitch` 来比对 body 里的 userId。

**问题**：拦截器在 `RequestBodyAdvice` 之前执行，带 RS 头的请求在拦截器里只能读到密文：
- `userSameSwitch` 读不到 userId，就**直接放行**了，形成绕过
- `GTokenInterceptor` 读不到 gToken，就会误拒正常请求

**比较过的方案**：
- A. 新增 Filter 提前统一解密：影响所有加密请求，Filter 里也没有 `@ExceptionHandler`
- **B. 抽出 `RequestBodyDecryptor`，拦截器按需调用，结果缓存在 request 上（采用）**
- C. 把 body 校验移到 `RequestBodyAdvice.afterBodyRead`：同一类校验会拆在两个地方，只覆盖有 `@RequestBody` 的接口

**方案 B 的实现要点**：
- 只有需要 body 字段的请求（打开了 `userSameSwitch`，或者 URL 在 gToken 名单里）才会在拦截器阶段提前解密
- 解密结果缓存在 request 上，advice 复用这份缓存，每个请求最多解密一次
- `MyRequestWrapper` 中的原始 body 仍然是密文，`SignatureInterceptor` 的验签不受影响

---

## 7. 注意点 / 隐患

1. **AES 的 IV 是写死的常量**（`Kwed#^6e34ons*&J`）。报文加密每次都会换新的 aesKey，所以影响有限；但数据库字段加密用的是固定 key + 固定 IV，同样的明文永远得到同样的密文。
2. **错误码不区分原因**：解密失败、验签失败、私钥过期，前端看到的都是 `DECRYPT_FAIL`（原因见 1.4）。
3. **错误响应永远不加密**，成功响应是否加密取决于 `common.encode` 的配置。
4. **私钥为空的表现不一致**：请求方向在验签那一步失败；响应方向返回 `SECURE_CREDENTIAL_EXPIRED`。
5. **日志会打印明文**：
   - `RequestBodyDecryptor` 会 `log.info("请求明文:{}")`，加密请求的明文会进日志
   - `CryptoComponent.encryptRequest` 会打印原始数据
   - **`CryptoComponent.init()` 会打印 `loginKey` 和 `dataKey`**，也就是数据库加密密钥本身
6. **glc-core 调后端时用的是写死在代码里的 token**（`CryptoComponent` 中 3 处）。
7. **`CryptoComponent.decryptRequest` 失败后会静默降级为明文解析**，验签失败也不会报错。
8. **token 没有过期机制**（见第 3 节）。
9. **响应加密名单是精确匹配**（`equals`），而 `SignatureConfigs.uris` 是包含匹配（`contains`），gToken 名单是 Ant 匹配。三处的匹配规则不一样，配置时要注意。

---

## 8. 相关文件索引

| 文件 | 说明 |
|---|---|
| `glc-web/.../interceptor/HttpServletRequestReplacedFilter.java` | 包装 request，让 body 可以重复读 |
| `glc-web/.../interceptor/MyRequestWrapper.java` | 缓存原始 body |
| `glc-web/.../interceptor/RequestBodyDecryptor.java` | 请求解密 + 验签，带缓存 |
| `glc-web/.../interceptor/DecryptRequestBodyAdvice.java` | `@RequestBody` 解密入口，以及 `BusinessException` → `DECRYPT_FAIL` |
| `glc-web/.../interceptor/EncryptResponseBodyAdvice.java` | 响应加密 |
| `glc-web/.../interceptor/ThreadContext.java` | needRSA、decrypt、sign 三个标志位 |
| `glc-web/.../interceptor/SignatureInterceptor.java` | RSA 验签 + 防重放 |
| `glc-web/.../interceptor/TokenInterceptor.java` | token 解析 + userSameSwitch |
| `glc-web/.../interceptor/GTokenInterceptor.java` | gToken 归属校验 |
| `glc-web/.../interceptor/WebAppConfigurer.java` | 拦截器注册顺序 |
| `glc-web/.../config/EncodeUrlDataConfig.java` | `common.encode.*` |
| `glc-web/.../config/SignatureConfigs.java` | `glc.common.signature.*` |
| `glc-core/.../utils/CryptoComponent.java` | 服务端间加密调用 + 数据库字段加密 |
