## 笔记
1. 网关会校验token，且若传入的参数中有userId 则校验token中的userId和参数中的是否相等 -> 如果参数中的userId为null，不会校验，攻击者可能会随便拿一个token，不传userId就能通过校验

## 扩展：http请求的结构组成
这里的 **“请求属性（attribute）”是服务端给当前请求附加的数据**。`tokenObj` 是项目约定的名称，通过 `setAttribute()` 创建，不需要提前声明字段。

我找到了一个明确的赋值位置：依赖包 `com.wotransfer.core.token.TokenInputUtil` 的 **`convert2Token()`** 方法。它构造 `TokenInput` 后，执行的关键步骤相当于：

```
request.setAttribute("tokenObj", tokenInput);
```

后续代码就可以读取：

```
TokenInput tokenInput =
    (TokenInput) request.getAttribute("tokenObj");
```


**属性只在当前请求处理期间使用。** 登录请求设置的属性，不会自动保留到下一次资料更新请求中；跨服务发送新的 HTTP 请求时，也不会自动携带这些属性。

一个 HTTP 请求可以用下面的示意报文理解：

```
POST /user/update?source=app HTTP/1.1
Host: example.com
Content-Type: application/json
token: <登录凭据>
Cookie: sessionId=<会话标识>

{"id":1001,"cnFullName":"测试用户"}
```

它由**请求行、请求头、空行、请求体**组成：

|部分|示例|Java / Spring 中的读取方式|
|---|---|---|
|请求方法|`POST`|`request.getMethod()`，或通过映射限定|
|请求路径|`/user/update`|`request.getRequestURI()`、`@RequestMapping`|
|URL 查询参数|`source=app`|`@RequestParam`、`request.getParameter()`|
|请求头|`Content-Type`、`token`|`request.getHeader("token")`|
|Cookie|`sessionId=...`|`request.getCookies()`；它在报文中属于请求头|
|请求体|JSON 中的 `id`、`cnFullName`|`@RequestBody Users users`|
|服务端请求属性|内存中的 `TokenInput` 对象|`request.getAttribute("tokenObj")`|

最后一行是服务端请求对象附加的内容，**不会出现在上面的 HTTP 报文中**。JSON 请求体中的字段，也不会自动变成请求属性。

结合你的项目，三个容易混淆的读取操作分别是：

```
request.getHeader("token");        // HTTP 请求头中的登录凭据
request.getHeader("tokenObj");     // HTTP 请求头中的字符串
request.getAttribute("tokenObj");  // 服务端附加的 Java 对象
```

本机 `core` 依赖中的 `getTokenInputObj()` 逻辑相当于：

```
// 先读服务端请求属性
Object obj = request.getAttribute("tokenObj");
if (obj != null) {
    return (TokenInput) obj;
}

// 没有属性时，再尝试读取同名请求头并解析
String json = request.getHeader("tokenObj");
// 将 json 解析成 TokenInput；没有可用内容则返回 null
```

所以，**读取请求属性和读取请求头是两个不同的数据来源**。检查越权时，还要追踪当前接口调用前是谁填入了 `tokenObj`，尤其要确认同名请求头经过可信网关处理，而不是直接相信客户端提供的身份。

## Token 校验

### 跳过校验，直接放行
```java
if (StrUtil.startWithAny(request.getPath().toString(), webGatewayConfigs.getSkipTokenUri())) {  
    return chain.filter(exchange);  
}
```

```java
private String[] skipTokenUri = {"/pricing", "/component", "/file", "/image"};
```

### Token存储位置
token 存储在 请求头中
`String token = request.getHeaders().getFirst(BaseConst.TOKEN_STRING);`

### ai总结

网关校验 Token 的核心入口是 **[Pre20TokenGlobalFilter (line 52)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre20TokenGlobalFilter.java:52)**。它读取 Token、解析身份，再检查黑名单、环境、有效期和设备会话。**路径白名单和配置开关决定了哪些检查会执行。**

**1．从请求头取得 Token，解析出用户身份**

```
String token = request.getHeaders().getFirst(BaseConst.TOKEN_STRING);
TokenInput tokenInput = TokenInputUtil.convert2Token(token);
```

`TOKEN_STRING` 的值是 `token`，所以客户端传递的是：

```
token: <登录后得到的Token>
```

我继续检查了本机 `core` 依赖。`convert2Token()` 使用自定义 Token 协议，大致过程是：

```
Token 分成 5 段
    → 计算 HMAC-SHA256，与其中的签名比较
    → 比较通过后进行 AES 解密
    → 将明文中的 key=value 字段解析成 TokenInput
```

`TokenInput` 包含 `userId`、`payerId`、`countryCode`、`env`、`timestamp` 等信息。后面的网关逻辑使用这些字段进行判断。

这里的“解析成功”，还没有完成有效期和会话检查。

**2．先看请求是否可以免登录放行**

这个过滤器有三种放行规则：

|规则|代码行为|
|---|---|
|跳过 Token 的路径前缀|在解析之前直接放行，默认包括 `/pricing`、`/component`、`/file`、`/image`|
|接口白名单|检查 IP 黑名单后放行，不要求有效 Token|
|IP 白名单|**仅在 Token 为空时**允许放行|

接口白名单通过 `AntPathMatcher` 匹配，代码会给配置中的路径加上 `/web` 前缀。例如 [白名单 (line 70)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/configs/WebGatewayConfigs.java:70) 中有：

```
/user/login
/user/register
/user/reset/email
/user/set/password
```

因此 `/web/user/reset/email` 可以不登录进入业务服务，其业务身份验证要由接口自身负责。

IP 白名单支持具体 IP，以及 `a.b.c.*`、`a.b.*.*` 形式的网段。**带了错误 Token 时，不会因为 IP 在白名单里就跳过解析失败检查。**

**3．普通受保护请求依次执行这些检查**

对应 [过滤器主体 (line 67)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre20TokenGlobalFilter.java:67)：

|检查|不通过时的处理|
|---|---|
|IP 在黑名单中|返回 `LOGIN_EXPIRED`|
|Token 为空，且 IP 不在白名单中|返回 `USER_NOT_LOGIN`，明确设置 HTTP `401`|
|`tokenInput == null`|返回 `LOGIN_EXPIRED`|
|用户 ID 在用户黑名单中|返回 `LOGIN_EXPIRED`|
|Token 时间戳为空或为 `0`|返回 `LOGIN_EXPIRED`，明确设置 HTTP `401`|
|Token 环境与网关环境不匹配|按环境规则拒绝|
|Token 超过有效期|在过期检查开关开启时拒绝|

注意，当前代码发现 `countryCode` 为空时**只记录日志**；用户黑名单方法遇到 `userId == 0` 时也会返回通过。这两个判断本身没有验证“用户身份一定完整且有效”。

**4．过期检查由开关控制**

[有效期检查 (line 123)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre20TokenGlobalFilter.java:123) 的核心条件是：

```
if (webGatewayConfigs.isOpenSessionInvalid()) {
    // 默认有效期 30 天；可从 Redis 按国家读取有效期
    if (tokenInput.getTimestamp() + validTime < System.currentTimeMillis()) {
        return Mono.error(new BusinessException(ErrorCode.LOGIN_EXPIRED));
    }
}
```

也就是：

```
Token 中的时间戳 + 有效时长 < 当前时间 → 过期
```

默认有效时长是 **30 天**，Redis 中可以按国家覆盖，覆盖值按秒转换成毫秒。

但 [配置类 (line 23)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/configs/WebGatewayConfigs.java:23) 的默认值是：

```
private boolean openSessionInvalid = false;
```

所以，**仅按代码默认配置，时间戳非零就能通过基础时间检查，并不会因为 Token 已经超过 30 天而自动拒绝。** 实际部署是否开启，要核对 Nacos 的有效配置。

环境检查也有例外：`test/dev/local` 环境跳过；Token 未携带环境时跳过；`tokenDevNotJudgeFlag` 开启且两边都是 `prod` 环境时，允许生产环境之间通用。

**5．韩国账号还会检查设备和 Redis 会话**

[韩国账号分支 (line 136)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre20TokenGlobalFilter.java:136) 多做两件事：

- **设备一致性**：Android 读取设备标识，其他来源读取 `imei`，与 Redis 中该用户的登录设备比较。请求有设备标识、Redis 也有记录且二者不一致时，拒绝。
- **会话存在性**：开启 `krSessionFlag` 后，Redis 中没有会话标记就拒绝，登录路径除外。通过后重新设置会话标记和 TTL，形成续期。

因此，一般 Token 的有效期检查和韩国账号的 Redis 会话检查，是两套不同机制。

**6．验证后的身份如何交给 wt-web**

网关希望把解析结果放进内部请求头 `tokenObj`，供 wt-web 读取。不过这里有一个实际的代码问题：

```
request.mutate()
    .header(BaseConst.TOKEN_OBJ, JSONObject.toJSONString(tokenInput))
    .build();
```

[Pre20 的这行代码 (line 62)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre20TokenGlobalFilter.java:62) 构建了新请求，却没有使用它替换 `exchange`。这一行本身不会把新头传给后续过滤链。`mutate()` 返回的是构建器，修改结果需要通过新请求、新 exchange 继续传递。[Spring API 说明](https://docs.spring.io/spring-framework/docs/6.0.5/javadoc-api/org/springframework/http/server/reactive/ServerHttpRequest.html)

项目的 [Pre10 无 signature 分支 (line 158)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre10SignatureGlobalFilter.java:158) 则另外解析 Token，并正确地将携带 `tokenObj` 的新 exchange 传给后续链路。因此，**身份传递是否生效与执行路径有关，尤其需要核对携带 `signature` 的路径。**

此外，[Pre40BusinessCheckGlobalFilter (line 121)](/D:/workspace/wh/wt/wt-web-gateway/src/main/java/com/wotransfer/webgateway/filters/Pre40BusinessCheckGlobalFilter.java:121) 可以比较 Token 的 `userId` 与请求参数中的 `userId`。但它需要开启日志总开关和实际拦截开关；它也不检查你之前例子中的 `id` 字段或订单归属，业务接口仍需做权限判断。

最后，解析层还有一个值得单独评估的点：**本机 `core` 实现会从 Token 各段还原 HMAC 和 AES 的密钥材料。签名比较通过，不能仅据此认定 Token 具备可靠的防伪能力。** 这些解析细节依据本机 `core-3.0.1-SNAPSHOT` 字节码；线上行为还需与部署版本、Nacos 配置核对。


## 40

|                 |                 |                                 |     |                            |                       |     |             |            |     |     |     |     |
| --------------- | --------------- | ------------------------------- | --- | -------------------------- | --------------------- | --- | ----------- | ---------- | --- | --- | --- | --- |
| OrderController | arrivalTimeSync | POST order/v2/arrival/time/sync | 是   | 内部接口无 token 校验，可任意同步到账时间配置 | 限制为内部服务调用 + 签名/IP 白名单 |     | fangdreamer | 2023-03-02 |     |     |     |     |
这条记录**有明确的代码依据，存在未授权写入到账时间配置的风险**。我已沿网关、wt-web、wt-order 检查到数据库写入，但没有实际调用线上接口。

这个方法应检查的是：**调用者有没有“同步配置”的权限**。它操作的是业务配置，比较 `userId` 不能解决这个权限问题。

问题：
1. 接口加入白名单，不会校验token -> 猜测：只希望通过内部调用？
2. 不会校验是否有权限调用 -> 猜测：功能不危险，能登录权限的人都有权限用？


## 22
|   |   |   |   |   |   |   |   |   |   |   |   |   |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
|OrderController|syncTxnStatus|POST order/v2/syncStatus|是|无 token 校验，body 含 seqNo，可触发任意订单状态同步（被滥用可能扰乱订单状态）|增加 token 校验并校验 token userId 与订单 userId 一致；限制为内部异步调用|高|田宁|2019-03-14|||||
检查：
1. userId为空的情况
2. seqNo？

大抵是废弃了

## 81

|                   |                    |                              |     |                                                                   |                      |     |        |            |     |     |     |     |
| ----------------- | ------------------ | ---------------------------- | --- | ----------------------------------------------------------------- | -------------------- | --- | ------ | ---------- | --- | --- | --- | --- |
| OrderV3Controller | commitOrderEddInfo | POST order/v3/eddinfo/commit | 是   | 无 token 校验，body EddInformationROExt 含 bizOrderNo，可越权提交他人订单 EDD 信息 | token 校验并核对订单 userId | 高   | guanjf | 2025-07-08 |     |     |     |     |
**接口作用**

提交订单关联的汇款人或收款人 EDD 补充信息，例如 PEP（政治公众人物）声明、职业、交易关系和交易目的。接口将这些信息同步到合规系统；同步成功后，更新相关订单的 EDD 补充标记。**提交成功不等于合规审核通过。**

**正常使用场景举例**

用户 A 的订单被要求补充收款人 EDD 信息：

1. A 打开自己的订单补充页面。
2. 填写收款人姓名、职业、与汇款人的关系，以及 PEP 声明等内容。
3. 前端携带该订单的 `bizOrderNo` 调用此接口。
4. 服务端将资料提交给合规系统，并更新补充状态。

对应的越权问题就是：**A 将请求中的订单标识换成 B 的订单，服务端是否仍允许提交。** 这也是该接口需要核对 token 用户与订单归属的原因。

**存在明确的水平越权风险，建议保留“高”。但表格原因应改为“缺少订单归属校验”，不能笼统写成“无 token 校验”。** 以下是当前代码的静态检查结果。

**1. 网关通常要求登录，但没有验证订单归属**

该请求对象使用 `bizOrderNo` 指定订单，没有 `userId`，因此这个检查不能判断订单属于谁。

**2. Controller 的订单归属检查被整段注释**

[OrderV3Controller.java 第 335 行 (line 335)](/D:/workspace/wh/wt/wt-web/src/main/java/com/wotransfer/web/order/controller/OrderV3Controller.java:335) 原本准备执行：

```
// 获取 token 用户
// 根据 bizOrderNo 查询订单
// 比较 order.userId 与 token.userId
// 不一致则拒绝
```

这些代码全部没有执行。当前方法只检查 `bizOrderNo`、`supplement` 非空，然后直接调用：

```
gatewayClient.syncEddInformation(param);
```

因此，**提交 EDD 信息之前没有执行订单归属校验**。

**3. 下游使用目标订单的用户，没有与调用者比较**

合规同步返回成功后，Controller 使用传入的 `bizOrderNo` 更新订单补充状态。

[订单服务第 3787 行 (line 3787)](/D:/workspace/wh/wt/wt-order/src/main/java/com/wotransfer/order/service/impl/ApplyOrderServiceImpl.java:3787) 的处理是：

```
ApplyOrder order = applyOrderBusiness.findBySeqNo(applyOrder.getSeqNo());
applyOrder.setUserId(order.getUserId());
```

随后按这个用户更新 EDD 标记。**这里的 `userId` 来自目标订单，不是调用者的 token，所以不是授权检查。**

影响还可能超过单笔订单：[更新 SQL (line 2164)](/D:/workspace/wh/wt/wt-order/src/main/resources/mapper/ApplyOrderMapper.xml:2164) 会清除该用户所有包含相同 EDD 标记的订单中的对应标记。

例如：

```
A 使用自己的有效 token
→ 请求中填写 B 的订单号
→ 网关验证 A 已登录
→ Controller 未检查该订单是否属于 A
→ 向合规服务提交 B 的订单 EDD 信息
→ 若同步成功，更新 B 的 EDD 补充状态
```

你的表格可以改写为：

> 网关校验登录身份，但 Controller 的订单归属校验被注释；接口直接使用客户端提供的 bizOrderNo 提交 EDD 信息，并在同步成功后更新目标订单用户的补充状态，存在水平越权风险。

**修复重点：**在任何合规调用或写入之前，拒绝缺失、无效的登录身份，查询订单并比较 `order.userId` 与可信 token 中的 `userId`；同时由服务端确定 `bizOrderId`、`bizOrderNo`，避免两个订单标识不一致。不能只取消现有代码的注释，因为原来的条件仍会在 token 为空或用户 ID 为 0 时跳过检查。

尚未进行在线复现，也未拿到 `provider-gateway` 的合规同步实现。最终可用两个测试账号验证：**A 的 token 提交 B 的测试订单 EDD，观察合规记录及订单标记是否改变。** 不要只看接口返回成功——该 Controller 最后固定返回 `new ResultRich()`，没有透传下游失败结果。