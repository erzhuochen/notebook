## 17
|   |   |   |   |   |   |   |   |   |
|---|---|---|---|---|---|---|---|---|
|LoginController|switchLogin|POST /login/switchLogin|是|切换市场登录，body Users 含 phoneNumber/email；无 token 校验 → 切换任意账号到任意市场|添加 token 校验并校验 tokenUserId = param.userId|高|guanjf|2024-03-23|
### 代码流程
**`switchLogin` 用于同一个全球账号切换市场：定位目标市场账号，必要时调用下游创建或关联账号，执行市场切换，更新全球账号的登录记录，最后返回目标市场的用户及 KYC 信息。**

你之前的业务理解基本正确，但有两处需要细化：**没有目标市场映射时，并非直接在 GLC 创建业务账号；最终响应来自另一次 `kycInfo` 查询，也不是直接返回切换操作的结果。**

**业务背景**

从数据结构看，GLC 将“全球账号”和“各市场业务账号”分开管理：

|层次|代码中的表示|作用|
|---|---|---|
|全球账号|`global_user.g_token`|关联同一用户在不同市场的账号|
|市场账号映射|`global_user_kycs`|保存 `gToken`、市场、服务器、业务 `userId`、KYC 状态等|
|市场业务账号及 KYC|下游业务系统|处理市场切换、注册，以及具体 KYC 查询|

对应定义见 [GlobalUser.java (line 15)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/pojo/model/GlobalUser.java:15) 和 [GlobalUserKycs.java (line 8)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/pojo/model/GlobalUserKycs.java:8)。`gToken` 在创建全球账号时由 UUID 生成，承担账号关联作用，不能据此视为登录认证凭证。见 [GlobalUserServiceImpl.java (line 194)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:194)。

正常场景可以理解为：**测试账号 A 已登录韩国市场，现在切换到日本市场。** 系统应找到 A 的日本市场账号；尚未建立映射时，调用日本市场对应的业务服务处理。A 在两个市场的 `userId` 可以不同，全球账号仍通过同一个 `gToken` 关联。

**执行流程**

1. **请求先经过 Web 过滤器和拦截器。**
    
    入口为 `POST /login/switchLogin`。请求包装过滤器先包装请求；MVC 注册了签名、商户和 token 拦截器，`switchLogin` 不在 token 排除列表内。见 [请求包装过滤器:22 (line 22)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/HttpServletRequestReplacedFilter.java:22)、[拦截器注册:55 (line 55)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/WebAppConfigurer.java:55)。
    
    签名拦截器按请求签名及来源条件检查，商户拦截器按商户请求头查询商户缓存。普通客户端请求还需通过 token 解析结果、环境、黑名单等检查；韩国账号额外检查设备和会话。代码存在**无 token 且命中 IP 白名单时放行**的分支，实际白名单配置尚未核实。见 [签名检查:65 (line 65)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/SignatureInterceptor.java:65)、[商户检查:35 (line 35)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/MerchantInterceptor.java:35)、[Token 检查:66 (line 66)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/TokenInterceptor.java:66)。
    
2. **Web Controller 补充渠道，转发给 Core。**
    
    `LoginController.switchLogin` 根据目标市场和已解析的商户信息获取商户渠道；渠道格式有效时，覆盖 `users.channel`。随后把请求体和请求头中的 token 转发给 `service-glc-core` 的 `/global/user/switchLogin`。
    
    见 [Web 入口:903 (line 903)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/controller/LoginController.java:903)、[商户渠道选择:1684 (line 1684)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/controller/LoginController.java:1684)、[CoreClient:15 (line 15)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/client/CoreClient.java:15)。
    
3. **Core 根据全球账号和目标市场查询账号映射。**
    
    Core 从 `countryCode` 推导 `server`，从 `channel` 推导 `vendor`，然后使用：
    
    ```
    gToken + countryCode + server + vendor
    ```
    
    查询 `global_user_kycs`。SQL 还要求 `status = 0`；`vendor` 为 `R` 时查白标账号，否则查 `P`。
    
    **这一步决定要切换哪个全球账号的哪个市场账号。** 见 [核心查询:360 (line 360)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:360)、[Service 到 Mapper:34 (line 34)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserkycServiceImpl.java:34)、[查询 SQL:96 (line 96)](/D:/workspace/wh/glc/glc-core/src/main/resources/mapper/GlobalUserKycsMapper.xml:96)。
    
4. **根据是否存在映射，进入两个分支。**
    
    **已有映射：**将映射中的业务 `userId` 写入 `loginParams.id`，覆盖请求原来的 `id`，再调用下游 `switchCountry`；业务失败时直接返回错误。见 [已有账号分支:376 (line 376)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:376)、[justSwitchCountry:250 (line 250)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:250)。
    
    **没有映射：**先构造待保存的市场映射，再调用 `insertUserKycs`。这个方法仍有一次分支选择：
    
    - 请求中的 `id` 非空：调用下游 `switchCountry`。
    - 请求中的 `id` 为空：调用下游 `autoRegister`。
    
    下游成功后，取返回的业务账号 ID、KYC 状态和通过时间；按业务账号 ID 与市场检查现有映射，缺少时插入 `global_user_kycs`，并异步发送映射同步请求。Core 随后将下游返回的 ID 写回 `loginParams.id`。
    
    见 [无映射分支:365 (line 365)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:365)、[映射构造:685 (line 685)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:685)、[下游选择与映射写入:221 (line 221)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:221)。
    
5. **按目标市场发送加密 HTTP 请求。**
    
    `backendPost` 根据目标市场查找配置中的服务地址，拼接 `switchCountry` 或 `autoRegister`，通过 `CryptoComponent` 加密请求并发送 HTTP POST。
    
    此处使用代码设定的内部调用 token 请求头，**没有沿用用户原始 token**。加密和内部调用认证也不能自动证明请求中的 `gToken` 属于当前用户。见 [下游地址与调用:357 (line 357)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:357)、[配置地址解析:42 (line 42)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/config/CommonConfigs.java:42)、[加密 HTTP 发送:231 (line 231)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/utils/CryptoComponent.java:231)。
    
    本次仅为追踪这条调用，参考了 `D:\workspace\wh\tp` 下的相关代码：其 `GLCUserController` 将 `switchCountry` 和 `kycInfo` 转发给 `service-payer`。payer 的 `switchCountry` 会清空传入的 `id`，重新按 **`gToken + vendor`** 查询 `global_user_relation`；找到后切换账号市场，找不到则进入自动注册。市场变化时，会更新业务账号的市场、KYC 状态等字段。见 [下游转发:231 (line 231)](/D:/workspace/wh/tp/wt-web/src/main/java/com/wotransfer/web/glc/controller/GLCUserController.java:231)、[payer 账号选择:1937 (line 1937)](/D:/workspace/wh/tp/wt-payer/src/main/java/com/wotransfer/payer/controller/UserController.java:1937)、[关联查询 SQL:27 (line 27)](/D:/workspace/wh/tp/wt-payer/src/main/resources/mybatis/mapper/GlobalUserRelationMapper.xml:27)、[市场状态更新:606 (line 606)](/D:/workspace/wh/tp/wt-payer/src/main/java/com/wotransfer/payer/service/Impl/UserServiceImpl.java:606)。
    
    **这份代码是下游候选实现；尚未核实 GLC 运行时地址配置是否指向它。**
    
6. **检查登录限制，更新全球账号的登录记录。**
    
    注意顺序：**登录限制检查位于前面的注册或切换调用之后。** 命中限制时返回冻结错误；否则按请求中的 `gToken` 查询全球账号，更新：
    
    - `lastLoginCountry`：本次目标市场；
    - `loginCountries`：补充曾登录的市场；
    - `lastLoginTime`：当前时间。
    
    数据库通过全球账号主键执行选择性更新。这段代码捕获异常后仍会继续查询最终响应。见 [限制检查及登录记录更新:385 (line 385)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:385)、[数据库更新:481 (line 481)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:481)。
    
7. **查询目标市场 KYC，作为最终响应返回。**
    
    `queryPayerByUsers` 将请求对象转换为 `PayerV2`，使用处理后的 `users.id` 设置 `payerV2.userId`，再调用目标市场的 `kycInfo`，直接返回其 `ResultRich<PayerV2>`。
    
    所以，接口最终结果来自这次查询。GLC 本身没有在这里生成或明确返回新的用户登录 token。见 [最终返回:405 (line 405)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:405)、[KYC 查询参数及调用:706 (line 706)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:706)。
    
    上述候选 payer 实现会查询用户、读取 KYC 缓存或调用对应市场的 KYC 服务；缺少 KYC 信息时可能使用用户信息构造响应，并按条件补充审核信息、证件信息等。各市场实际返回字段仍取决于对应实现和数据。见 [候选 KYC 查询:547 (line 547)](/D:/workspace/wh/tp/wt-payer/src/main/java/com/wotransfer/payer/controller/PayerController.java:547)、[KYC 服务调用:608 (line 608)](/D:/workspace/wh/tp/wt-payer/src/main/java/com/wotransfer/payer/controller/PayerController.java:608)。
    

**与越权审查的关系**

正常授权规则应是“**A 切换到 A 所属全球账号的其他市场**”。当前 GLC 流程虽有登录认证，但未见将请求 `gToken` 绑定到可信登录身份的检查。

用测试账号 A、B 举例：A 携带自己的有效 token，将请求中的 `gToken` 替换为 B 的关联标识，目标市场保持不变，可能使核心查询选中 B 的市场账号。应在**查询、创建或切换账号之前**，从可信登录身份及原市场解析 A 的全球账号，拒绝不属于 A 的 `gToken`；只比较请求 `userId` 与 token 用户 ID 不能覆盖这条选择逻辑。

本次是静态分析，未调用线上接口。实际验证应检查返回账号与 KYC 是否属于 B，以及账号市场、映射和登录记录是否发生变化；HTTP 200 本身不能证明越权成功。运行时下游对应关系、完整下游授权及各市场 KYC 实现仍未全部确认。


### 越权分析
**结论：存在明确的身份绑定缺口，有横向越权风险。但表格中的“仅凭手机号/邮箱即可切换任意账号”不准确。** 当前代码真正用于选择账号的是请求体中的 `gToken`，没有将它与当前登录身份绑定。

**接口作用与正常场景**

它用于同一个全球账号切换市场。例如，你已登录澳洲市场，切换到新加坡市场：系统根据全球账号关联，找到或创建新加坡市场的账号，执行切换，并返回该市场的 KYC 信息。核心流程见 [GlobalUserController.java (line 357)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:357)。

**具体校验情况**

| 检查点                 | 当前实现                                                                             | 代码位置                                                                                                                                                                                                                                                                           |
| ------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 是否校验 token          | 有。`switchLogin` 不在 token 拦截器的排除列表中；普通非白名单请求缺少 token 会被拒绝                         |                                                                                                                                                                                                                                                                                |
| Controller 是否绑定当前用户 | 没有，只转发请求体和 token                                                                 | [LoginController.java (line 903)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/controller/LoginController.java:903)                                                                                                                                       |
| 下游如何确定目标账号          | 按请求中的 `gToken + countryCode + server + vendor` 查询；查到后用目标账号的 `userId` 覆盖请求中的 `id` | [GlobalUserController.java (line 363)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:363)、[GlobalUserKycsMapper.xml (line 96)](/D:/workspace/wh/glc/glc-core/src/main/resources/mapper/GlobalUserKycsMapper.xml:96) |
| 是否比较目标身份与 token 身份  | 当前调用链没有。核心接收方法没有读取转发来的 token                                                     | [GlobalUserController.java (line 358)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/controller/GlobalUserController.java:358)                                                                                                                           |

GLC 的拦截器还有一个可配置的“请求 `userId` 与 token 一致”检查，但默认关闭，而且只检查名为 `userId` 的参数，**没有检查 `gToken`**。见 [TokenInterceptor.java (line 108)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/interceptor/TokenInterceptor.java:108)、[CommonConfigs.java (line 301)](/D:/workspace/wh/glc/glc-web/src/main/java/com/wotransfer/glc/web/config/CommonConfigs.java:301)。

**越权场景举例**

假设 A、B 是两个测试账号：

1. A 使用自己的有效 token。
2. 请求中的 `userId` 保持为 A，或者不传；将 `gToken` 改成 B 的全球账号标识，选择 B 已存在的目标市场。
3. 拦截器检查的是 A 的 token 和请求 `userId`；核心服务却根据 B 的 `gToken` 查到 B 的目标市场账号，将 `id` 改成 B 的账号 ID。
4. 随后以这个 ID 执行市场切换，并查询 KYC 信息。

对应下游操作见 [GlobalUserServiceImpl.java (line 250)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:250) 和 [GlobalUserServiceImpl.java (line 706)](/D:/workspace/wh/glc/glc-core/src/main/java/com/wotransfer/glc/core/service/impl/GlobalUserServiceImpl.java:706)。后续 `wt-web` 方法也直接转给 `service-payer`，没有补上调用者身份比较，见 [GLCUserController.java (line 231)](/D:/workspace/wh/wt/wt-web/src/main/java/com/wotransfer/web/glc/controller/GLCUserController.java:231)。

因此，**有效 token 只能证明 A 已登录，不能证明请求中的 B 的 `gToken` 属于 A。** 不过，攻击者需要获得目标账号的有效标识；当前证据不能证明“只知道手机号/邮箱就能成功”，也不能直接证明能拿到 B 的登录 token。

**修复建议**

仅添加 `tokenUserId == param.userId` 不够。应当根据已验证 token 的用户身份和原市场，从服务端查出其所属全球账号，再以这个全球账号定位目标市场账号。请求体中的 `gToken`、`id`、`userId` 应被校验或由服务端覆盖。不同市场的账号 ID 可能不同，不能直接要求目标市场 ID 等于原市场 token 的 ID。

这条记录可改成：

> **已校验 token，但未绑定请求中的 gToken 与当前登录用户；可通过替换全球账号标识触发其他账号的市场切换及 KYC 查询，存在横向越权风险。**

目前是静态代码结论，尚未核实 `service-payer` 的最终实现或实际执行结果。验证时应使用两个测试账号，保留 A 的 token，仅替换为 B 的 `gToken`，检查返回账号、KYC 信息和登录记录是否属于 B。