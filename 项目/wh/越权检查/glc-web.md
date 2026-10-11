## 17
|   |   |   |   |   |   |   |   |   |
|---|---|---|---|---|---|---|---|---|
|LoginController|switchLogin|POST /login/switchLogin|是|切换市场登录，body Users 含 phoneNumber/email；无 token 校验 → 切换任意账号到任意市场|添加 token 校验并校验 tokenUserId = param.userId|高|guanjf|2024-03-23|
### 代码流程



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