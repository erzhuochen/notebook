Frontier 清空了。先把 Q11 的连带影响钉清楚 —— 它**改变了"什么算成功"**，不说清你会照着错的判据去验。

## leader 那句话的完整含义

`tp-aukyc:243` 返回 `model` 为 null，卡住的是 `AsyncPost:1053` 这个门里的两件事：插 `payer_documents`、更新 `users.kyc_status`/`kyc_pass_date`。

但 tp 侧的 KYC 状态**不是没人管了** —— `syncPandaKycInfo` 在 `:234-240` 主动调了 `payerClient.kycPush({userId, kycCode})`，把熊猫的状态推回 tp-payer（落到 `PayerController:880`）。也就是说这个设计是**从"靠返回值回写"换成"靠回调推送"**，逻辑是闭环的，leader 的说法站得住。

所以本轮的判据要这样调整：

|观测点|判定|
|---|---|
|`tp.payer_documents` 无新行|✅ **预期**，不是 bug|
|日志 `用户:{}，保存kyc文件信息：{}` 不出现|✅ **预期**|
|日志 `panda kyc审核结果通知，请求参数：{}`（`PayerController:882`）|✅ **必须出现** —— 这才是 tp 侧状态更新的唯一入口|
|`wt.aus_kyc.country_code` 为 NULL|⚠️ 已知偏差（`:679` 不修），本轮不追，但记一笔：`wt-aukyc KycController:170` 的 Monoova NPP 建户按它判，**可能不建 NPP 账户**|

---

# 测试执行计划

## 阶段 0 · 测前准备（不在 App 里）
清空数据库![](tp-wt.assets/file-20260921135449039.png)

**① 插 `kyc_routes` 路由行**

```
country_code = 'AUS'
merchant_id  = <测试商户的 merchantNo>
create_order = 0
channel      = 任意值
```

`merchant_id` 填什么别猜 —— 先随便登录一次，从日志 `获取授权缓存结果参数:{}`（`LoginController:190`）里把 `merchantNo` 照抄出来。`channel` 查询时传的是 null（`:146`），不参与筛选，填什么都行。

**② 确认 starryblue 侧回包**：`countryCode` 必须是 `AUS`、`kycCode` 必须是 `100`。两个条件**串联**，只改一个无效。

**③ 清账号**（只测③纯新分支，必须清干净）

- tp：`users`（`partner_user_id` + `merchant_no`）→ 连带删 `payee`（`user_id = <uid>`，uid 格式 `E<id>`）
- wt：`aus_kyc` → `user_tags` → `users`（`id = <原 pd_user_id>`）
- ⚠️ **再确认 `wt.aus_kyc` 里没有别的同名同生日 / 同 `id_number_mask` 且 `kyc_status=1` 的残留行**，否则会静默命中①分支，不建号、不写表，日志只有一行 `查询到重复用户:`
- 若上次跑崩过，手删 Redis `syncKyc:<tp uid>`（TTL 600 秒）

**④ 确认 `tp-payer`、`tp-aukyc`、`wt-payer`、`wt-aukyc` 四个服务都是 `cze-54327842` 且已重启**

## 阶段 1 · App 里的操作 —— 只有一步

这是你原始问题的答案，可能比你预期的少：**整条链路在 App 端只有一个请求**。

1. 在 starryblue App 里登录测试账号
2. 走跳转 TopUp 的入口，**市场选澳洲**
3. 抓包确认发出了 `POST /payer/login`，**请求体里 `countryCode` 是 `AUS`**

这一步就触发了全链路。`countryCode` 是 App 传的（`:188-189` 会覆盖缓存值），选错市场后面全白跑，所以这是 App 侧唯一需要盯的东西。`merchantNo` 即使在请求体里也是被忽略的，不用管。

## 阶段 2 · 按日志判据链定位（核心）

按顺序 grep，**哪条断了就卡在哪**：

|#|grep 关键词|断在这里说明|
|---|---|---|
|1|`授权登陆V2请求参数`|请求没进来 / partToken 过期（看 `授权已过期`）|
|2|`查询kycRoutes`|**空数组 = ① 的路由行没配对**|
|3|`获取starry blue kyc信息结果`|不出现 = 商户 `label` 不是 `STARRY`；出现了就**直接读回包里的 `countryCode` / `kycCode`**|
|4|`同步保存kyc证件信息参数`|**3 有、4 没有 = 被 `:365` 静默挡掉了**（②没弄对）。这是唯一判据，没有任何错误日志|
|5|`同步 KYC信息参数`|没打到熊猫|
|6|`同步 KYC信息结果`|熊猫没回；**回包里有熊猫 userId**|
|7|`没有对应得用户 纯新`|没走③分支（错别字照抄）。看到 `查询到重复用户` 就是③没清干净|
|8|`panda kyc审核结果通知，请求参数`|状态没推回 tp|

额外盯两条**异常但接口仍返回成功**的：`同步 AUS KYC信息异常`（`wt-aukyc:739`，`aus_kyc` 写失败被吞）、`用户 {} 正在同步 KYC 信息`（锁残留，直接返回）。

## 阶段 3 · 核对数据库

**tp 侧**：`users.pd_user_id` 有值 ← 唯一的成功硬指标  
**wt 侧**：

- `users` 新行，`channel = 'Starryblu-tp'`（这条链路的专属标记）
- `user_tags` 新行
- `aus_kyc` 新行，`kyc_partner = 1`、`note` 以 `STARRY BLUE 同步kyc信息：` 开头、`country_code` 为 NULL（已知偏差）

## 阶段 4 · 顺手测下单（Q10）

KYC 跑通后，在 App 里发起一笔汇款下单，**只看会不会被拦/报错**。

关注点：`tp-order` 的 `ApplyOrderServiceImpl:381` 和 `:639` 是**直接读 `aus_kyc`** 的，而 tp 侧 `aus_kyc` 现在是空的（agent 已确认这条链路完全不写它）→ 拿到 `null`。这个用户 KYC 在熊猫侧通了，在 TopUp 侧下单时"查无 KYC"。`create_order = 0` 所以订单不转发熊猫，这一步不追订单结果，只看**能不能下**。

## 阶段 5 · 重跑

`tp.users.pd_user_id` 是**总开关**，四道幂等门全看它。重跑至少要把它置 NULL，否则第二次登录只会打一行 `用户:{}，熊猫ID存在，不进行starry blue kyc同步` 就结束 —— 现象非常像"代码没生效"。

`partToken` 不要手动造，重新走一次商户授权换新的。

---

顺带那个问题还在：`notes/01:258` 和 `notes/03:242-243` 那两条已被你的改动推翻，要我更正吗？