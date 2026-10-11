我正在审查 Java 项目的接口越权问题，会逐条提供接口名称和分析表格。请结合本地代码判断，重点遵守以下要求。

**我的要求**

1. **使用中文解释，先给结论。** 判断我提供的分析哪些正确、哪些需要修正，不要直接接受表格中的漏洞描述。
2. **每次检查接口，都补充接口作用和正常使用场景举例。** 说明实际读取或修改了什么，不能只根据方法名推断功能。
3. **所有关键代码判断都给出文件位置和准确行号，使用可点击的绝对路径链接。**
4. **沿完整调用链检查：入口 → 网关/拦截器 → Controller → Wrapper/Feign → 具体服务 → 数据库操作。** Controller 没有 token 校验，不代表整个接口没有认证。
5. **区分登录认证与资源授权。** 有效 token 只能证明调用者已登录；请求中的 `userId` 与 token 相等，也不能证明请求指定的订单、收款人或全球账号属于调用者。
6. 对普通用户操作自己的资源，应确认资源归属或明确授权；可以先查资源所有者再比较，也可以用“资源标识 + 可信用户身份”作为数据库条件。管理员、内部服务、公开分享/验证接口需要结合各自的授权规则判断。
7. **区分静态代码缺口、可利用风险和实际验证成功。** 没有检查线上配置、最终服务或执行结果时，明确说明限制，不要宣称漏洞已实测。
8. 举越权例子时，使用测试账号 A、B，说明替换哪个参数、预期应如何拒绝；验证要检查实际数据变化，不能只看 HTTP 200。
9. 当前主要任务是分析和讲解，**没有要求修改代码或调用线上接口**。
10. 不输出代码中的 token、密钥等敏感值。

**代码检索规则**

仓库根目录存在 `.codegraph/` 时，必须先使用 CodeGraph 理解或定位代码，再使用 `rg` 或读取未覆盖的代码。没有索引就直接使用 `rg`，不要自行创建索引。

**项目位置**

- 当前工作目录：`D:\workspace\wh\wt`
- Web 入口：`D:\workspace\wh\wt\wt-web`，有 CodeGraph 索引。
- Web 网关：`D:\workspace\wh\wt\wt-web-gateway`，有 CodeGraph 索引。
- 订单服务：`D:\workspace\wh\wt\wt-order`
- 美国订单服务：`D:\workspace\wh\wt\wt-usorder`
- 实体类：`D:\workspace\wh\wt\wt-entity`
- 同目录还包括 `wt-gateway`、`wt-risk`、`wt-compliance-data`、`wt-common-oss` 等；不要混淆 `wt-gateway` 和 `wt-web-gateway`。
- 全球登录中心：`D:\workspace\wh\glc`，包含 `glc-web`、`glc-core`，此前没有 CodeGraph 索引。
- 管理后台：`D:\workspace-wh\manager-shiro`
- 管理数据服务：`D:\workspace-wh\manager-data`

继续工作前核对当前目录、索引、AGENTS.md 和代码，因为我可能继续放入项目或修改代码。

**已经讨论清楚的共同结论**

- 网关比较“请求 `userId` 与 token `userId`”，不能代替订单、收款人等资源的归属检查。
- 不传 `userId`，可能跳过参数一致性检查，但不会自动跳过受保护接口的 token 认证。
- URI 白名单只是跳过认证，不能证明调用者是内部服务。
- 当前 Web 网关的白名单 IP 功能允许缺少 token 的请求通过，**不是“只允许这些 IP 访问，拒绝其他 IP”**。生产网络层限制尚未核实。
- `manager-shiro` 的管理入口有 Shiro 权限检查，但这些权限不会自动保护绕过管理入口、直接调用的 Web 接口。
- Web 网关 `Pre40BusinessCheckGlobalFilter` 的检查受配置开关影响；multipart 请求体不会由当前读取逻辑解析，因此表单中的 `userId` 可能不被检查。

**已审查接口的重要结果**

|接口|已得结论|
|---|---|
|`order/v2/arrival/time/sync`|同步到账时间配置，按 `envId` 插入或更新；不是修改单笔订单实际到账时间。网关白名单覆盖，Web 和订单服务未见调用者授权。管理后台入口有权限检查，直接同步入口需要独立保护。|
|`order/v3/eddinfo/commit`|提交订单 EDD 信息。网关通常需要 token，但订单归属检查被注释。请求通过 `bizOrderNo` 指定订单，没有请求 `userId`，网关参数比较不能保护它。下游补充材料更新可能影响目标用户的多笔匹配订单。|
|`payee/document/upload/single`|小程序单文件上传，参数是 multipart 表单。直接使用请求中的 `userId/payeeId` 上传文件并处理文档记录，没有归属检查。仅覆盖 `userId` 不够，还必须确认 `payeeId` 属于调用者或获授权。最终 `service-payee/provider-oss` 实现未核实。|
|`applyOrder/abortUnpaid/{id}`|实际只设置 `remindFlag=1`，不取消订单。Web 转发 token，但订单服务不使用；最终更新条件只有订单 ID，存在修改他人提醒标志的风险。|
|`order/v2/syncStatus`|Web 和订单分发层没有归属检查；按市场分发。可见澳洲、美国实现都是 `return null`，不能因此宣称能实际修改他人订单；其他市场实现未核实。|
|`verify/voucher`|Base64 解码后还有 AES 解密，取得订单号，查询订单及已有收据记录；不创建收据。未见归属校验，但若业务允许持有验证凭据的人公开查询，需要按公开授权范围判断。仅知道订单号并做 Base64 编码不足以构造有效凭据。|

另外，曾发现部分调用映射差异：美国客户端使用 `syncStatus`，美国 Controller 使用 `syncTxnStatus`；订单详情客户端声明 GET，服务 Controller 声明 POST。实际转发行为尚未验证。

**最近审查：`POST /login/switchLogin`**

表格原描述：

> 无 token 校验，body 含 phoneNumber/email，可切换任意账号到任意市场。

需要修正：

- `glc-web` 注册了 token 拦截器，`switchLogin` 不在排除列表中；普通非白名单请求需要 token。
- Controller 仅转发请求体和 token。
- `glc-core` 接收方法没有读取 token，而是按请求中的 **`gToken + 目标市场 + server + vendor`** 查账号。
- 查到目标账号后，用目标账号的 `userId` 覆盖请求中的 `id`，再执行市场切换和 KYC 查询。
- 没有把请求 `gToken` 与当前认证用户绑定。即使请求 `userId` 与 token 相等，也不能保护实际选中的全球账号。
- 当前不能证明仅凭手机号/邮箱就能成功，也没有证明能取得他人的登录 token。
- 正确修复应从可信 token 身份和原市场解析所属全球账号，再定位该账号的目标市场身份。不同市场账号 ID 可能不同，不能简单比较目标市场 ID 与原 token ID。
- 尚未核实最终 `service-payer` 实现或实际执行结果。

关键代码位置：

- [Web token 拦截器注册 (line 55)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/WebAppConfigurer.java:55)
- [Token 校验 (line 66)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/TokenInterceptor.java:66)
- [switchLogin Web 入口 (line 903)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/controller/LoginController.java:903)
- [核心账号选择及切换 (line 357)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:357)
- [目标账号查询 SQL (line 96)](/D:/workspace/wh/glc/glc-core/src/main/resources/mapper/GlobalUserKycsMapper.xml:96)
- [市场切换调用 (line 250)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:250)
- [KYC 查询调用 (line 706)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:706)

可用于审查表的描述：

> 已校验 token，但未绑定请求中的 gToken 与当前登录用户；替换全球账号标识可能触发其他账号的市场切换及 KYC 查询，存在横向越权风险，实际影响需进一步验证。