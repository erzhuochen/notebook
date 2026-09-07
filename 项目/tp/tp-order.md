# tp-order 项目笔记

> **一句话定位**：跨境汇款订单的**编排层 / 路由层**。它不落地具体国家的支付逻辑，而是做「幂等去重 → 补 KYC → 算费 → 按国家路由 → 转发给国家微服务 → 收结果、回写、发通知」。

| 项 | 值 |
|---|---|
| 仓库 | `D:\workspace\tp\tp-order` |
| 服务名 | `service-tp-order` |
| 端口 / 前缀 | `9102` / `/order` |
| 技术栈 | Spring Boot 2.7.6 · Java 11 · Spring Cloud Alibaba(Nacos) · OpenFeign · MyBatis(tk) · Druid · Redis · RocketMQ · RabbitMQ |
| 内部依赖 | `tp-core`（工具 / Result）· `tp-entity`（实体 / 枚举，**枚举都在这**） |
| 笔记更新 | 2026-09-07 |

## 导航

| 章节 | 内容 | 什么时候看 |
|---|---|---|
| [[#一、上手方法论]] | 通用的读新项目方法 | 换项目时复用 |
| [[#二、项目骨架与架构认知]] | 技术栈、create/commit、编排层本质、外部边界 | 第一天 |
| [[#三、业务链路全景]] | 6 条主链路的完整调用栈 | **主力参考** |
| [[#四、状态机]] | 两个状态字段 + 全枚举 | 读任何链路前先看 |
| [[#五、坑与反模式清单]] | 踩过 / 发现的雷 | 改代码前扫一遍 |
| [[#六、学习进度与待确认]] | 已完成 / 待办 / 要问 leader 的问题 | 每周更新 |
| [[#七、源码深度解析]] | 逐行解析（createBefore / createExecute / 汇率 / commitOrderBefore） | 深挖时 |

---

# 一、上手方法论

核心原则：**先建立骨架认知，再垂直打穿一条线，最后横向铺开**。绝对不要一上来就一个个文件读。

| 步骤        | 做什么                                           | 目的                                     |
| ----------- | ------------------------------------------------ | ---------------------------------------- |
| 1. 看骨架   | 构建文件（pom/package.json）、目录结构、启动配置 | 它是什么技术栈？依赖谁？端口和路由前缀？ |
| 2. 垂直打穿 | 挑 1~2 个核心接口，从入口一路追到底              | 建立第一条完整的"心智链路"               |
| 3. 横向归纳 | 再看 2~3 个同类接口                              | 找出**套路**——套路才是项目的真实结构     |
| 4. 找数据   | 表结构 + 状态枚举                                | 业务系统的本质是数据流转，状态机是骨髓   |
| 5. 划边界   | 外部依赖、MQ、定时任务                           | 知道哪里"出了这个仓库"，避免瞎找         |


---

# 二、项目骨架与架构认知

## 第 1 步：骨架（5 分钟）

看 `pom.xml` + `application.yml`：

```
Spring Boot 2.7.6 / Java 11
Spring Cloud Alibaba 2021.0.4.0  → Nacos 做注册中心 + 配置中心
OpenFeign + LoadBalancer         → 微服务之间 HTTP 调用
MyBatis + tk.mybatis + Druid     → MySQL
Redis / RocketMQ / RabbitMQ      → 缓存 + 两套消息队列
内部模块: tp-core, tp-entity     → ★ 实体和工具类在别的仓库
```

`application.yml`:
```
port: 9102
context-path: /order          ← 你的 /order 前缀在这
application.name: service-tp-order
```

**第一个关键推论**：`/order/client/create` = context-path `/order` + `@RequestMapping("client")` + `/create`。
所以直接搜 `"/create"` 找不到全路径是正常的 —— **Java 项目的 URL 永远是拼出来的，要分段搜**。

## 第 2 步：垂直打穿这两条链路

入口都在 `src/main/java/com/tp/order/controller/OrderController.java:80`。

### `/order/client/create` —— 预创建订单（`OrderController.java:137`）

```
OrderController.create(CreateOrderParameters)
└─ ApplyOrderServiceImpl.createOrder()          :2089
   ├─ createBefore(parameters)   校验 / 前置检查，失败直接返回
   └─ createExecute(parameters)  落库生成预单，返回带 seqNo 的 Order
```

薄薄一层，**不提交给合作方**，只是在本地生成一张"申请单"。

### `/order/client/commit` —— 持久化并提交（`OrderController.java:150`）

这条才是主菜，四步：

```
1. orderServiceWrapper.commitOrderBefore(order)        OrderServiceWrapper.java:83
   ├─ 按 partnerSeqNo 查库 → 已存在则返回 ORDER_HAS_CREATED（★ 幂等设计）
   ├─ payerClient.queryKycInfo()  → 远程取 KYC，回填 payerId
   ├─ this.calculate(order)       → 算手续费
   └─ 查 KycRoute：若 createOrder==1，调 Panda 建单，回写 pandaSeqNo/paymentLink

2. loadService(order)                                  OrderController.java:1123
   └─ OrderFactory 按 countryCode（没有就用 currencyCode）取对应国家的 BaseOrderService

3. orderService.commitTxn(order)                       ← ★★★ 见下方
   
4. orderServiceHandler.commitOrderResultHandler(order)  OrderServiceHandler.java:42
   ├─ 重新查库拿最新数据（不信任内存里的 order）
   ├─ 回写 pandaSeqNo / paymentLink
   └─ asyncPost.pushStbOrderInfoNotify()  异步推送通知
```

## 第 3 步：横向归纳 —— 本项目最重要的一个认知

第 3 步是分水岭。看 `OrderFactory.java` 里注入的 13 个国家 Service，随手点开一个 `AUOrderService.java:10`：

```java
@FeignClient(name = "service-tp-auorder")
public interface AUOrderService extends BaseOrderService {
    @PostMapping("auorder/commitTxn")
    ResultRich<Order> commitTxn(@RequestBody Order params);
}
```

**它是接口，没有实现类，是 Feign 远程调用。**

于是整个项目的定位就清晰了：

> **tp-order 不是订单的落地层，它是「编排层 / 路由层」。**
> 它负责：幂等去重 → 补 KYC → 算费 → **按国家路由** → 转发给对应国家的微服务 → 收结果、回写、发通知。
> 真正跟支付合作方（Novatti 等）打交道的逻辑，在 `service-tp-auorder`、`service-tp-jporder` 等**另外 13 个仓库**里。

这是新人最容易卡死的地方 —— 你在本仓库 debug 到 `commitTxn` 会发现"点不进去"，不是你的问题。

路由表（`OrderFactory.init()`，按币种 → 服务）：

| 币种 | 目标服务           | 币种 | 目标服务           |
| ---- | ------------------ | ---- | ------------------ |
| AUD  | service-tp-auorder | KRW  | service-krorder    |
| JPY  | service-tp-jporder | CNY  | service-tp-cnorder |
| IDR  | service-idorder    | BRL  | service-tp-brorder |
| SGD  | service-tp-sgorder | MXN  | service-tp-mxorder |
| HKD  | service-tp-hkorder | CAD  | service-tp-caorder |
| EUR  | service-tp-euorder | NZD  | service-tp-nzorder |
| USD  | service-tp-usorder |      |                    |

## 第 4 步：找数据 —— 表与状态机

业务系统的本质是数据流转，**状态机是骨髓**。这一步的产出就是后面两章：

- 全部链路见 [[#三、业务链路全景]]
- 两个状态字段和全枚举见 [[#四、状态机]]

主表：`apply_order`（`pojo/model/ApplyOrderDo` + `resources/mapper/ApplyOrderMapper.xml`）。

注意各国还有**分表**（`CanTxn` / `EurTxn` / `HkgTxn` / `IdnTxn` / `JpnTxn` / `KorTxn` …）。主表在本服务，分表由国家服务维护 —— `cancel` 链路里"修改分表状态"就是这个意思。

## 第 5 步：外部边界（`client/` 包，12 个 Feign）

```
service-tp-payer     payer/KYC        service-tp-gateway   ★ 对接支付合作方的网关
service-payee        收款人            service-risk         风控
service-tp-cnkyc / hkkyc / uskyc      各地 KYC
service-coupon       优惠券            service-pmm          支付方式管理
service-notification 通知              service-bank-adapter 银行
provider-common      公共组件
```

看到这张表，你就知道：**任何一个字段查不到来源，先问它是不是从这 12 个服务之一拿的。**


---

# 三、业务链路全景

## 3.0 四类入口

```
① HTTP 同步    13 个 Controller（前端 / 商户 / 运营后台 / 其它微服务）
② HTTP 回调    push/*、v2/push/*      ← 第三方和国家服务反向通知
③ RocketMQ     ORDER_CLEARING_TOPIC   ← 全项目唯一的 MQ 消费者
④ 定时触发     GET 端点被外部调度器调（本项目没有 @Scheduled，全是"伪定时"）
```

> ⚠️ **④ 最容易漏**：`/client/syncOrderTimeout`、`/applyOrder/expire`、`/applyOrder/timer/get/nova/txn` 这些 GET 接口就是定时任务，由外部调度中心打进来。看着像查询接口，其实是任务入口。

### Controller 路由总表

| 类 | 前缀 | 用途 |
|---|---|---|
| `OrderController` | `client` | **交易主流程**（36 个端点，核心） |
| `ApplyOrderController` | `/applyOrder` | 运营后台 / 定时任务（40+ 端点） |
| `OrderPushController` | `push` | 到账通知（V1） |
| `OrderPushV2Controller` | `v2/push` | 状态回调 / 结算通知（V2） |
| `PaymentController` | `/payment` | POLI 对账清分 |
| `PandaController` | `panda` | Panda 侧接入 |
| `GvpOrderController` | `/gvp` | GVP 渠道订单 |
| `CardController` | `/card` | 银行卡 |
| `CountryPaymentMethodController` | `/payment/method` | 支付方式配置 |
| `ActivityFeeController` | `/activity/fee` | 活动费率 |
| `IdentitySupportController` | `/identity/support` | 证件支持 |
| `OccupiedCountryController` | `/occupied/country` | 国家占用 |
| `BeatController` | — | 心跳 |

---

## 3.1 链路一：下单主干

```
POST /client/create        OrderController:137   预创建，落 ApplyOrder，返回 seqNo
POST /client/pay/types     OrderController:734   查该国可用支付方式
POST /client/createPayment OrderController:682   ★ 创建支付（拿支付链接 / 银行转账信息）
POST /client/commit        OrderController:150   提交，路由到国家服务
```

### `/create`（:137）

```
ApplyOrderServiceImpl.createOrder()                    :2089
├─ createBefore(parameters)    商户校验 / KYC / 汇款人收款人 / 同名校验
└─ createExecute(parameters)   汇率与金额计算 → 落库 → 返回 seqNo
```

逐行解析见 [[#七、源码深度解析]]

### `/createPayment`（:682）

比 commit 更能体现项目的分叉逻辑。

```
setCountryCode(param)              ← 没传国家码就反查订单补上（★ 全项目高频模式）
isPandaOrder(param)                OrderController:1155
├─ 是 Panda 单 → pandaHttp() 裸 HTTP 打到 Panda，再 restorePandaSpecialId 把 ID 换回来
└─ 不是       → loadService(param).createPayment()   Feign → 国家服务
```

> 🔑 **Panda 暗线**：`isPandaOrder` 查 `KycRoute` 表决定走哪条路。这条分叉在 `commitOrderBefore`、`createPayment`、`v2/push/*` 里反复出现，**是贯穿全项目的一条暗线**。先把它认出来，后面读什么都顺。

### `/commit`（:150）

```
1. orderServiceWrapper.commitOrderBefore(order)        OrderServiceWrapper:83
   ├─ 按 partnerSeqNo 查库 → 已存在返回 ORDER_HAS_CREATED（★ 幂等）
   ├─ payerClient.queryKycInfo()  → 远程取 KYC，回填 payerId
   ├─ this.calculate(order)       → 算手续费
   └─ KycRoute.createOrder==1 → 调 Panda 建单，回写 pandaSeqNo / paymentLink
2. loadService(order)                                  OrderController:1123
   └─ OrderFactory 按 countryCode（缺省用 currencyCode）取国家 BaseOrderService
3. orderService.commitTxn(order)                       ← ★ Feign 出本仓库
4. orderServiceHandler.commitOrderResultHandler(order) OrderServiceHandler:42
   ├─ 重新查库拿最新（不信任内存里的 order）
   ├─ 回写 pandaSeqNo / paymentLink
   └─ asyncPost.pushStbOrderInfoNotify()  异步推送
```

### 配置表：CountryPayTypeMap

表 `country_pay_type_map`，实体 `pojo/model/CountryPayTypeMap.java`。
**一行 = 一个国家的一种支付方式**。在下单主干里出场两次，角色完全不同。

```
/create        ❌ 完全不用
/pay/types     ✅ 出场①：查列表给前端选
/createPayment ❌ 不用（转发给国家服务或 Panda）
/commit        ✅ 出场②：按选中的支付方式算额外手续费
```

#### 表的三层内容

主键是 **`countryCode` + `payType` + `subType`** 三元组（`selectByCountryCodeAndSubType` 按它查）。

| 层 | 字段 | 作用 |
|---|---|---|
| ① 身份 | `countryCode` / `payType` / `subType` / `status` | 定位一种支付方式。`payType`：1 在线转账 · 2 银行支付 · 3 线下支付；`subType` 是子类型 |
| ② 展示 | `payName` / `payContent` / `logoImg` / `cornerImg` / `cornerContent` / `sort` / `hasCornerMark` | 前端渲染支付方式卡片：名称、描述、图标、角标、排序 |
| ③ 计费 | `feeType` / `extraFeeRate` / `newUserFeeRate` / `oldUserFeeRate` / `newUserDiscountFeeRate` / `oldUserDiscountFeeRate` / `discountStartTime` / `discountEndTime` / `lockRate` | 额外手续费规则、新老用户差异费率、限时优惠、是否支持锁汇 |

② 的**多语言**是这张表最占篇幅的部分：`payName` / `payContent` / `cornerContent` 各有 7 个语言变体（简 / 繁 / 英 / 泰 / 印尼 / 菲 / 印地）。实体类 700 多行里绝大部分是这些字段的 getter/setter。

#### 出场①：`/client/pay/types` 渲染可选支付方式

`OrderController:734` → `ApplyOrderServiceImpl.getPayTypeByOrder()` `:3376`

```java
// 1. 欧元区归一：AUT/DEU/FRA… 都映射成 Europe
if (CurrencyEnum.EUR.equals(country.getCurrency())) market = CountryEnum.Europe.getMsg();

// 2. countryCode + 可选 payType/subType 过滤，只要 status=1
example.and().andIn("countryCode", countrys);
example.orderBy("status").desc().orderBy("sort").desc().orderBy("payType").asc();
List<CountryPayTypeMap> list = countryPayTypeMapMapper.selectByExample(example);

// 3. ★ 按国家取策略 Bean，做各国特殊过滤
PayTypeQuery payTypeQuery = applicationContext.getBean(routerMarket, PayTypeQuery.class);
return payTypeQuery.exec(list, order);
```

> 🔑 **第二套路由机制**：和 `OrderFactory` 平行，但实现方式不同 —— 用 **Bean 名 = 国家码**，靠 `applicationContext.getBean(国家码, PayTypeQuery.class)` 取。
>
> ```
> service/payType/
> ├─ PayTypeQuery.java      接口
> ├─ @Service("AUS") AUSPayTypeQuery
> ├─ @Service("CAN") CANPayTypeQuery
> ├─ @Service("CHN") CHNPayTypeQuery
> └─ @Service("USA") USAPayTypeQuery
> ```
>
> `catch (NoSuchBeanDefinitionException)` 走默认逻辑 —— **只有这 4 个国家有特殊规则，其余 9 个走默认**。
> 例：`CHNPayTypeQuery:60` 汇出用户若 `bankType == 1`，把 `payType == 1`（在线转账）从列表剔掉。

最后 `international()` `:3430` 按 `systemLanguage`（1简 2繁 3英 4泰 5印尼…）把 7 套语言字段中对应的一套**覆盖回** `payName` / `payContent` / `cornerContent`，再拷成 `CountryPayTypeMapForShow` 返给前端。

配套端点 `/client/pay/type`（`:751`）拿同一批结果取 `get(0)`，用于查单个支付方式。

#### 出场②：`/client/commit` 算额外手续费

`OrderServiceWrapper.commitOrderBefore:110` → `calculate(order)` `:198`

```java
CountryPayTypeMap m = countryPayTypeMapMapper.selectByCountryCodeAndSubType(
        order.getCountryCode(), order.getType(), order.getFundingType());   // ★ 三元组反查

if (m != null && isNotEmpty(m.getExtraFeeRate()) && !"0".equals(m.getExtraFeeRate())) {
    BigDecimal fee = new BigDecimal(m.getExtraFeeRate());
    order.setPayTotalAmount(payTotal.add(fee));   // 加到用户要付的总额
    order.setFeeAmount(原feeAmount.add(fee));      // 累加到手续费
}
```

**关键连接点**：`order.getType()` = 表里的 `payType`，`order.getFundingType()` = 表里的 `subType`。
用户在前端从出场①的列表里选了哪个，这两个字段就带着回来，commit 时用它们反查同一行配置，取出 `extraFeeRate`。

这也解释了 Panda 建单参数为什么是 `pandaOrder.put("type", order.getFundingType())`（`OrderServiceWrapper:123`）—— Panda 侧的 type 对应我们的 subType。

#### ⚠️ 两套费率、两张表、两个阶段

| 阶段 | 表 | 入口 |
|---|---|---|
| `create` | `CountryPaymentMethod` | `/client/extraFeeInfo` `OrderController:1010` |
| `commit` | `country_pay_type_map` | `OrderServiceWrapper.calculate:198` |

**`create` 阶段根本不碰 `country_pay_type_map`**。额外手续费是 commit 才加的。这是这块最容易搞混的地方。

---

## 3.2 链路二：状态回调

第三方 → 我们 → 商户。订单系统的心脏。

```
POST /v2/push/status/notify        OrderPushV2Controller:97
├─ 参数校验（seqNo 或 pandaSeqNo 二选一 + paymentStatus + status）
├─ Redis 占位防重  REDIS_SETTLE_ORDER_KEY + seqNo，200s
├─ 按 pandaSeqNo / seqNo 分别查单   findPandaOrder / findOrder
├─ ★ 幂等闸门：已是 RECHARGE_SUCCESS / FAILED / WAIT 直接拒绝
├─ 更新 paymentStatus + status + orderIdIn3rdSys + note
└─ 同步通知商户
```

配套：

- `POST /v2/push/updateOrder`（:66）—— 只更 3rd ID 和备注，Panda 同步用
- `POST /v2/push/settlement/notify`（:55）—— 结算通知，**被链路三复用**

> 🔑 **两层防重**：Redis key 防并发 + 状态闸门防重放。看懂这两层，就懂了金融系统为什么到处是这种写法。

---

## 3.3 链路三：对账清分

★★★ 含金量最高。横跨 HTTP + DB + MQ + 回调，看完这条对项目就有体感了。

```
① POST /payment/poli/verify        PaymentController:41
   导入银行流水 → bankPaymentVerifyByAccountRecord()   PaymentServiceImpl:90
   银行流水与本地订单匹配，返回待确认"白名单"

② POST /payment/poli/checkClear    PaymentController:59
   人工确认后的白名单进来 → doClear()                  PaymentServiceImpl:218
   ├─ 校验 paymentStatus ∈ {PAYMENT_RECEIVED, PAYMENT_UNVERIFIED}
   ├─ 校验 status == TRANSACTION_ING
   ├─ 改 paymentStatus = PAYMENT_SUCCESS，落库
   ├─ Redis CLEAR_ORDER_KEY 防重（300s）
   └─ ★ 发 MQ  sendClearMsg(ORDER_CLEARING_TOPIC)      PaymentServiceImpl:333

③ RocketMQ 消费                     RocketReceiver:31
   doClearQueue.onMessage → doClear(msg)               RocketReceiver:40
   ├─ Redis 分布式锁 "clearing_order_" + seqNo
   └─ 直接调 orderPushV2Controller.orderSettlementNotify()   ← ★ 见坑清单

④ 结算通知商户                      OrderPushV2Controller:55
```

---

## 3.4 链路四：到账通知

Nextpls 对外充值。

```
POST /push/success/order/notify    OrderPushController:113
├─ Redis REDIS_KCB_CLEAR_ORDER_KEY 防重（200s，finally 里 del）
├─ ★ 合规校验  requestComplianceCheck()               OrderPushController:178
│   gatewayClient.queryComplianceResult() → pass 才放行
│   回写 OrderRiskInfo.status = 1
├─ packageNextPlsOrder(order, users, payee)   组装对外报文
├─ IME 商户特殊分支 → asyncPost.nextplsTransfer() 先推全球分发
├─ gatewayClient.successOrderNotify(merchantNo, nextplsOrder)
└─ 成功且 PAYMENT_SUCCESS → asyncPost.nextPlsTopUpTransaction() + setTxnStatus()
```

---

## 3.5 链路五：取消与超时

```
POST /client/cancel         OrderController:423
├─ applyOrderService.cancel(param)           本地主表
├─ orderService.cancel(param)                Feign → 国家服务改分表
├─ orderService.updatePartnerOrderStatus()   Feign → 通知合作方取消
└─ couponClient.releaseCouponForOrderBySeq() 退券

POST /client/refund         OrderController:457    纯转发，全交给国家服务

GET  /client/syncOrderTimeout   OrderController:1111   ← 定时任务入口
└─ applyOrderService.expireAndFailedOrders()           ApplyOrderServiceImpl:2134
   按 commonOrderConfigs.getOrderTimeoutDay() 扫超时单
   type ∈ {2,5}（银行转账）走 bankTransferTimeoutTime
   → TRANSACTION_CLOSED / TRANSACTION_FAILED
```

---

## 3.6 链路六：异步推送

`async/AsyncPost.java` —— 所有链路的异步尾巴都在这。

| 方法 | 行 | 用途 |
|---|---|---|
| `pushStbOrderInfoNotify` | :414 | commit 成功后推送订单信息 |
| `nextPlsTopUpTransaction` | :231 | 到账后充值交易 |
| `nextplsTransfer` | :251 | IME 渠道全球分发 |
| `asyncNoticeMerchantOrderStatus` | :357 | 通知商户订单状态 |
| `pushStbSupplement` | :382 | 补件推送 |
| `updateThirdPaymentByPoli` | :104 | POLI 支付回写 |
| `insertOrderSupplement` / `removeOrderSupplementByUserId` | :164 / :203 | 补件增删 |
| `updateUserTags` | :187 | 用户标签 |


---

# 四、状态机

`ApplyOrder` 有**两个状态字段**，这是理解一切的钥匙。枚举都在 `tp-entity`，不在本仓库。

## 4.1 status 交易主状态

`ApplyOrderStatus`

```
TRANSACTION_ING ──┬─→ TRANSACTION_SUCCESS
                  ├─→ TRANSACTION_FAILED
                  ├─→ TRANSACTION_CLOSED   (超时关单)
                  └─→ INVALID
```

另有 `PAYMENT_ING` / `PAYMENT_SUCCESS` / `PAYMENT_FAILED` 三个值（与 paymentStatus 同名，注意别混）。

## 4.2 paymentStatus 支付子状态

`ApplyOrderPaymentStatus`，带一个 `result` 字段对外归三档：**Void / Pending / Paid**。

| 阶段 | 状态值 | 中文 | result |
|---|---|---|---|
| 初始 | `INIT` | — | Void |
| | `WAIT_PAYMENT` | 等待支付 | Pending |
| 支付中 | `PAYMENT_ING` | 支付处理中 | Pending |
| | `PAYMENT_AUTHORISED` | 支付已授权 | Pending |
| | `BANK_PROCESSING` | 银行处理中 | Pending |
| | `BANK_ACCEPTED` | 银行已受理 | Pending |
| 待核验 | `PAYMENT_UNVERIFIED` | 未核验 | — |
| | `PAYMENT_TO_BE_VERIFIED` | 待核验 | — |
| | `PAYMENT_FLAGGED` | 已标记 | — |
| 收款 | `PAYMENT_RECEIVED` | **支付成功** | Paid |
| | `PAYMENT_SUCCESS` | **等待清分** | Paid |
| 汇出 | `PAYMENT_REMITTED` | 已汇出 | Paid |
| | `BANK_REMITTED` | 银行已汇出 | Paid |
| | `WAIT_RECEIVE` | 等待收款 | Pending |
| 充值 | `RECHARGE_WAIT` / `RECHARGE_SUCCESS` / `RECHARGE_FAILED` | 充值中 / 成功 / 失败 | — |
| 终止 | `PAYMENT_FAILED` | 支付失败 | Void |
| | `PAYMENT_TIMEOUT` | 支付超时 | Void |
| | `PAYMENT_CANCELED` | 已取消 | Void |
| | `BANK_REMIT_FAILED` | 银行汇款失败 | Void |

## 4.3 命名坑

> **`PAYMENT_RECEIVED` 中文是「支付成功」，`PAYMENT_SUCCESS` 中文是「等待清分」—— 字面意思和实际含义是反的。**
>
> 链路三的 `doClear` 正是把 `PAYMENT_RECEIVED` → `PAYMENT_SUCCESS`（"收到钱" → "待清分"）。
> 不知道这点会读错所有清分相关代码。

## 4.4 怎么把枚举捞出来

`tp-entity` 只有 jar 没有源码时，用 javap：

```bash
cd /tmp && mkdir -p tpent && cd tpent
unzip -o -q ~/.m2/repository/com/tp/tp-entity/1.0-SNAPSHOT/tp-entity-1.0-SNAPSHOT.jar "com/tp/entity/order/enums/*"
javap -p -c com/tp/entity/order/enums/ApplyOrderPaymentStatus.class
javap -p -c com/tp/entity/order/enums/ApplyOrderStatus.class
```

更省事：IDEA 关联 `tp-entity` 的 sources jar，或直接把 tp-entity 仓库拉下来。

同目录下还有：`ApplyOrderExchangeStatus`、`ApplyOrderReceiveStatus`、`ApplyOrderRefundStatus`、`ApplyOrderRefundNumberStatus`、`ApplyOrderSource`、`ApplyOrderTraceEnum` / `V2`、`ApplyOrderSupplemenntEnums`（注意这个**类名拼写就是错的**，源码如此）。


---

# 五、坑与反模式清单

新人常犯的错是把代码当圣经。看到"味道怪"的地方，先假设**是有历史原因的**，记下来，攒够几个再一起问 leader —— 比逐个追问更高效，也更显专业。

## 5.1 命名 / 日志不可信

- **`OrderServiceHandler.java:63`**：`commitOrderResultHandler` 是所有国家共用的，日志却写着 `"sg创建订单返回结果"` —— 复制粘贴残留。**日志文案不可信，以代码逻辑为准。**

- **`ApplyOrderPaymentStatus`**：`PAYMENT_RECEIVED`（支付成功）和 `PAYMENT_SUCCESS`（等待清分）语义与字面相反，详见 [[#4.3 命名坑]]。

## 5.2 架构反模式

- **`RocketReceiver:59`**：MQ 消费者**直接调 Controller 的方法**（`orderPushV2Controller.orderSettlementNotify`）。不是标准写法，但必须知道 —— 否则看到 `orderSettlementNotify` 会以为它只有 HTTP 一个来源。

- **`OrderFactory.java:60-62`**：`getFactory()` 每次 `new OrderFactory()`，new 出来的实例 `@Resource` 字段全是 null。能跑是因为 `orderServiceMap` 是 `static`，由 Spring 托管的真实例在 `@PostConstruct` 里填好了。**能工作但很脆**，别照抄。

- **按商户号写死的分支**：`OrderPushController` 里的 `MerChantEnums.IME` 特殊处理。这类硬编码不止一处，是业务债务的集中地。

## 5.3 潜在缺陷（值得跟 leader 提）

- **`OrderController.java:443` cancel 吞异常**：整个 Feign 调用包在 `try-catch` 里且只 log 不抛。本地取消成功但合作方没取消掉时会产生**状态不一致**，且无补偿。这是个真实的对账缺口。

- **`PaymentServiceImpl:218` 附近大段注释代码**：注释掉的 Nova 建单逻辑和 RabbitMQ 发送，是历史演进的化石。别删，先问清楚。

- **`doClear` 里的 `Thread.sleep(10)`**：循环内限流，量大时会成为瓶颈。

- **`OrderServiceWrapper.calculateV2` 是死代码**：`:216` 定义了一个远比 `calculate` 完整的费率实现 —— `feeType=1` 百分比 / `=2` 固定金额 / `=3` 阶梯（查 `CountryPayTypeFeeLadder` 表）、新老用户区分（`selectTransactionIngAndSuccess`）、各自的优惠费率。**全仓库无任何调用点**（只有 `USAPayTypeQuery:53` 一行被注释掉的相关调用）。
  后果：`country_pay_type_map` 表里的 `feeType`、`newUserFeeRate`、`oldUserFeeRate`、`discountStartTime/EndTime` 等字段，在当前生效的下单链路里**全都没被用上**，只有 `extraFeeRate` 一个字段真正生效。
  ⚠️ 此结论只覆盖 tp-order 仓库 —— 这些字段可能是国家服务那边（commitTxn 之后）在用，或是未上线功能。**待确认。**

- **`CountryPayTypeMapMapper.selectByType` 不带国家码**：`ApplyOrderServiceImpl.lastPayType:2105` 用它反查用户上次成功订单的支付方式，SQL 只按 `pay_type + sub_type` 查、`limit 1`。不同国家可能有相同的 `(payType, subType)` 组合，**理论上会查到别国的配置**拿去展示 logo 和名称。潜在显示错乱，不影响资金。


---

# 六、学习进度与待确认

## 6.1 进度

- [x] 骨架：技术栈 / 端口 / context-path / 内部依赖
- [x] `/client/create` 入口
- [x] `/client/commit` 入口
- [x] 架构本质：编排层 + Feign 路由到 13 个国家服务
- [x] 外部边界：12 个 Feign client
- [x] `createBefore` / `createExecute` 逐行（见第七章）
- [x] `commitOrderBefore` 逐行（见第七章）
- [x] 汇率与金额计算（见第七章）
- [x] 两个状态枚举全量
- [x] 6 条主链路调用栈
- [x] `CountryPayTypeMap` 配置表 + payType 策略路由（第二套国家路由）
- [ ] **链路三（清分）完整走一遍** ← 下一个，性价比最高
- [ ] 链路二（状态回调）
- [ ] 链路四（到账通知 + 合规卡点）
- [ ] `createPayment` + `isPandaOrder`（认 Panda 暗线）
- [ ] 链路五（取消 / 退款 / 超时）
- [ ] 读表：`ApplyOrderMapper.xml` + `ApplyOrderDo` 字段含义
- [ ] 三个 DTO：`CreateOrderParameters` / `Order` / `ApplyOrder`
- [ ] `ApplyOrderController` 40+ 运营端点（低优先，量大）
- [ ] 本地 debug 跑通一次 create → commit

## 6.2 建议阅读顺序

| 顺序 | 内容 | 为什么 |
|---|---|---|
| 1 | [[#四、状态机]] | 没有状态机，读什么都是雾 |
| 2 | [[#3.3 链路三：对账清分]] | 唯一横跨 HTTP+DB+MQ+回调，性价比最高 |
| 3 | [[#3.2 链路二：状态回调]] | 理解幂等和防重的标准写法 |
| 4 | [[#3.4 链路四：到账通知]] | 理解对外报文和合规卡点 |
| 5 | [[#3.1 链路一：下单主干]] | 认出 Panda 暗线 |
| 6 | [[#3.5 链路五：取消与超时]] | 收尾逻辑，相对独立 |

## 6.3 要问 leader 的问题

- [ ] **下单的确切调用顺序**：`create → pay/types → createPayment → commit` 是从命名和逻辑推断的，没有前端代码佐证。抓一次真实请求日志验证，或直接问。**这是最值得问的一个。**
- [ ] `cancel` 吞掉 Feign 异常导致的状态不一致，现在靠什么补偿？有没有对账任务？
- [ ] `PaymentServiceImpl` 里注释掉的 Nova 建单 / RabbitMQ 逻辑，是废弃还是待恢复？
- [ ] Panda 是什么定位？`KycRoute.createOrder` 这个开关谁在维护？
- [ ] 定时任务由哪个调度中心触发？调度配置在哪看？
- [ ] `calculateV2` 为什么没启用？`country_pay_type_map` 的 `feeType` / 新老用户费率 / 优惠时间段这些字段，是国家服务在用，还是未上线功能？（见 [[#5.3 潜在缺陷（值得跟 leader 提）]]）
- [ ] `create` 和 `commit` 用两套不同的费率表（`CountryPaymentMethod` vs `country_pay_type_map`），是历史遗留还是有意设计？两者会不会重复收费？


---

# 七、源码深度解析

## ApplyOrderServiceImpl.createBefore 方法解析

**业务术语表**：
- **KYC**: Know Your Customer，客户身份认证，金融机构对客户进行身份核实的流程
- **商户号 (MerchantNo)**: 标识不同商户的唯一编号
- **汇款人 (Payer)**: 发起汇款的用户
- **收款人 (Payee)**: 接收汇款的用户
- **结算金额 (SettleAmount)**: 最终到账的金额
- **同名校验**: 验证汇款人和收款人姓名相似度，防止错误转账或欺诈

**方法概述**：
这是订单创建流程的前置验证方法，负责在正式创建订单前完成商户验证、KYC 审核检查、汇款人收款人信息查询、以及非指定商户的同名校验。该方法为创建订单的核心入口验证逻辑。

**相关上下文**：
```java
@Resource
private UsersDao usersDao;                      // 用户数据访问对象，查询用户基本信息

@Resource
private KeyStoreManageMapper keyStoreManageMapper;  // 商户密钥存储管理，验证商户是否支持

@Resource
protected PayerClient payerClient;               // 汇款人服务客户端，查询 KYC 信息

@Resource
private PayeeMapper payeeMapper;                 // 收款人数据访问对象，查询收款账户

@Resource
protected CommonOrderConfigs commonOrderConfigs; // 订单通用配置，包含同名校验阈值

@Value("${aes.encrypt.key}")
private String aesKey;                           // AES 加密密钥，用于解密敏感信息
```

**代码逐行解释**：
```java
2220  private ResultRich<Order> createBefore(CreateOrderParameters parameters) {  // 订单创建前置验证，返回包含临时订单对象的结果
2221      try {
2222          //非指定商户需要进行同名校验
2223          Users users = usersDao.selectByUid(parameters.getUserId());  // 根据用户 ID 查询用户信息（获取商户号）
2224          KeyStoreManage storeManage = keyStoreManageMapper.selectByMerchantNo(users.getMerchantNo());  // 根据商户号查询商户配置
2225          if (storeManage == null) {  // 商户不存在或未配置
2226              logger.info("暂不支持该商户，用户:{}，商户号：{}", parameters.getUserId(), users.getMerchantNo());
2227              return ResultRich.newInstance(ErrorCode.MERCHANT_NOT_SUPPORT);  // ⚠️ 异常处理：返回商户不支持错误
2228          }
2229
2230          // 创建临时订单,设置参数
2231          Order applyOrder = new Order();  // 创建临时订单对象
2232          BeanUtils.copyProperties(parameters, applyOrder);  // 将请求参数复制到订单对象（自动映射同名字段）
2233          applyOrder.setSeqNo("E" + IdGenerator.generateId());  // 生成订单流水号（E 前缀 + 唯一 ID）
2234          applyOrder.setStatus(ApplyOrderStatus.TRANSACTION_ING.getCode());  // 设置订单状态为交易处理中
2235          if (parameters.getPayerId() != null) {  // 如果请求中指定了汇款人 ID
2236              applyOrder.setPayerId(parameters.getPayerId());  // 设置汇款人 ID 到订单
2237          }
2238
2239          //结算金额
2240          if (StringUtils.isNotEmpty(parameters.getSettleCurrency())) {  // 如果提供了结算货币
2241              if (StringUtils.isEmpty(parameters.getSettleAmount()) || Double.parseDouble(parameters.getSettleAmount()) == 0) {  // 验证结算金额不为空且不为 0
2242                  return ResultRich.newInstance(ErrorCode.AMOUNT_LIMIT);  // ⚠️ 异常处理：金额不合法，返回金额限制错误
2243              }
2244              applyOrder.setSettleAmount(new Money(parameters.getSettleCurrency(), parameters.getSettleAmount()));  // 设置结算金额对象（货币 + 金额）
2245              applyOrder.setSettleCurrency(parameters.getSettleCurrency());  // 设置结算货币代码
2246          }
2247          //查询汇款人信息
2248          Payer payer = new Payer();  // 创建汇款人查询对象
2249          payer.setUserId(parameters.getUserId());  // 设置用户 ID
2250          ResultRich<Payer> payerResult = payerClient.queryKycInfo(payer);  // 远程调用：查询汇款人 KYC 审核信息
2251          logger.info("查询汇款人信息:{}", JSONObject.toJSONString(payerResult));
2252          if (payerResult.isSuc() && payerResult.getModel() != null) {  // 如果查询成功且有数据
2253              // kyc审核未通过
2254              if (payerResult.getModel().getKycStatus() != PayerKycStatus.PASS.getCode()) {  // 验证 KYC 状态是否为已通过
2255                  logger.info("kyc未通过无法创建订单,{}", payerResult.getModel().getPartnerUserId());
2256                  return ResultRich.newInstance(ErrorCode.PAYER_KYC_IS_FAILED);  // ⚠️ 异常处理：KYC 未通过，禁止创建订单
2257              }
2258              if (payerResult.getModel().getCountryCode().equals(CountryEnum.Singapore.getMsg())) {  // 推测为：新加坡用户需要特殊处理收入信息（监管要求）
2259                  if (payerResult.getModel().getIncomeEnum() != null) {  // 如果有收入等级信息
2260                      applyOrder.setIncomeEnum(payerResult.getModel().getIncomeEnum());  // 记录收入等级到订单（合规需要）
2261                  }
2262              }
2263              PayerInfo payerInfo = new PayerInfo();  // 创建汇款人详细信息对象
2264              BeanUtils.copyProperties(payerResult.getModel(), payerInfo);  // 复制 KYC 数据到汇款人信息
2265              payerInfo.setUserId(payerResult.getModel().getUserId());  // 设置用户 ID
2266              payerInfo.setWalletProvider(payerResult.getModel().getWalletProvider());  // 设置钱包提供商（支付方式）
2267              applyOrder.setPayerInfo(payerInfo);  // 将汇款人信息附加到订单
2268              applyOrder.setSourceOfIncome(payerResult.getModel().getSourceOfIncome());  // 记录收入来源（合规字段）
2269              applyOrder.setPayer3rdId(payerResult.getModel().getPartnerUserId());  // 设置第三方合作伙伴的用户 ID
2270          } else {
2271              return ResultRich.newInstance(ErrorCode.USER_NOT_EXIST);  // ⚠️ 异常处理：汇款人信息不存在
2272          }
2273
2274          //查询收款人信息
2275          Payee payeeSelect = payeeMapper.selectByPrimaryKey(parameters.getPayeeId());  // 根据收款人 ID 查询收款人记录
2276          logger.info("查询收款人信息:{}", JSONObject.toJSONString(payeeSelect));
2277          String walletNumber = AesUtil.aesDecrypt(payeeSelect.getWalletNumberMask(), aesKey, BaseConst.AES_NONCE);  // 解密收款账号（敏感信息加密存储）
2278          PayeeInfo payeeInfo = new PayeeInfo();  // 创建收款人详细信息对象
2279          BeanUtils.copyProperties(payeeSelect, payeeInfo);  // 复制收款人数据
2280          payeeInfo.setWalletNumber(walletNumber);  // 设置解密后的收款账号
2281          payeeInfo.setProvider(payeeSelect.getProvider());  // 设置收款渠道提供商
2282          payeeInfo.setName(payeeSelect.getFullName());  // 设置收款人姓名
2283          applyOrder.setPayeeInfo(payeeInfo);  // 将收款人信息附加到订单
2284
2285          if (!storeManage.getLabel().equals(MerChantEnum.STARRY.name())) {  // 非 STARRY 商户需要进行同名校验（STARRY 为指定豁免商户）
2286              String payerName = StringUtils.isNotEmpty(payerResult.getModel().getLastName()) ? payerResult.getModel().getLastName() + payerResult.getModel().getFirstName() : payerResult.getModel().getFullName();  // 构造汇款人姓名（姓+名，或全名）
2287              String reversePayerName = StringUtils.isNotEmpty(payerResult.getModel().getFirstName()) ? payerResult.getModel().getFirstName() + payerResult.getModel().getLastName() : payerResult.getModel().getFullName();  // 构造反转姓名（名+姓，处理不同国家姓名顺序）
2288              String payeeName = payeeSelect.getFullName();  // 获取收款人姓名
2289              double nameMatch = NameMatcher.hybridNameMatch(payerName, payeeName);  // 计算正向姓名匹配分数（0-1，越高越相似）
2290              double nameMatchReverse = NameMatcher.hybridNameMatch(reversePayerName, payeeName);  // 计算反向姓名匹配分数（处理姓名顺序差异）
2291              logger.info("订单:{},payer姓名:{},反转payer姓名:{},payee姓名:{},正分数:{},反分数:{}", parameters.getUserId(), payerName, reversePayerName, payeeName, nameMatch, nameMatchReverse);
2292              if (nameMatch < commonOrderConfigs.getSameNameScore() && nameMatchReverse < commonOrderConfigs.getSameNameScore()) {  // 如果正反匹配分数都低于阈值
2293                  return ResultRich.newInstance(ErrorCode.NOT_SAME_NAME_ERROR);  // ⚠️ 异常处理：姓名不匹配，禁止创建订单（防止错误转账）
2294              }
2295          }
2296
2297          return ResultRich.newInstance(applyOrder);  // 返回验证通过的临时订单对象
2298      } catch (Exception e) {
2299          logger.error("创建订单before参数异常---->", e);
2300          return ResultRich.newInstance(ErrorCode.APPLY_ORDER_INSERT_ERROR);  // ⚠️ 异常处理：捕获所有异常，返回订单创建错误
2301      }
2302  }
```

**复杂逻辑详解**：

- **第 2286-2287 行**（姓名处理）：
  1. 检查是否有独立的姓 (LastName) 和名 (FirstName) 字段
  2. 如果有，按"姓+名"和"名+姓"两种顺序拼接（处理中文"李明"和英文"Ming Li"的差异）
  3. 如果没有，直接使用全名 (FullName)
  
- **第 2289-2290 行**（双向姓名匹配）：
  1. `NameMatcher.hybridNameMatch()` 使用混合算法计算姓名相似度（可能结合编辑距离、拼音相似度等）
  2. 分别计算正向（姓+名）和反向（名+姓）匹配分数
  3. 返回 0-1 之间的分数，1 表示完全匹配

- **第 2277 行**（AES 解密）：
  1. `payeeSelect.getWalletNumberMask()` - 获取加密后的收款账号
  2. `AesUtil.aesDecrypt()` - 使用 AES 算法解密
  3. 需要密钥 (`aesKey`) 和随机数 (`BaseConst.AES_NONCE`)

**被调用的业务方法**：
1. **usersDao.selectByUid()** - 查询用户基本信息
2. **keyStoreManageMapper.selectByMerchantNo()** - 验证商户配置
3. **payerClient.queryKycInfo()** - 远程调用：查询汇款人 KYC 状态（可能涉及第三方身份认证服务）
4. **payeeMapper.selectByPrimaryKey()** - 查询收款人账户信息
5. **NameMatcher.hybridNameMatch()** - 计算姓名相似度（防欺诈核心算法）

Now I have all the information needed. Let me generate the detailed explanation:

## ApplyOrderServiceImpl.createExecute 方法解析

**业务术语表**：
- **到账金额 (TargetAmount)**: 收款人最终收到的金额
- **充值金额 (SourceAmount)**: 汇款人需要支付的金额
- **结算金额 (SettleAmount)**: 中间结算货币的金额（跨币种交易时使用）
- **业务汇率 (BusinessRate)**: 展示给用户的汇率
- **熊猫汇率 (PandaRate)**: 平台内部汇率
- **折算汇率 (Rate/ZheSuan)**: 实际计算用汇率
- **结算汇率 (SettleRate)**: 结算货币到目标货币的汇率
- **本币支付**: 支付货币和到账货币相同，无需兑换

**方法概述**：
这是订单创建流程的核心执行方法，负责计算订单的金额、汇率关系，验证金额限制，最后将临时订单存入 Redis。支持本币支付和跨币种支付两种场景，处理复杂的多级汇率计算逻辑。

**相关上下文**：
```java
@Resource
private RedisService redisService;  // Redis 服务，用于存储临时订单和防重复创建

private static final String createOrderKey = "recharge-order-lock-";  // Redis 分布式锁前缀
```

**代码逐行解释**：

### 第一部分：设置到账金额和汇率计算

```java
2310  private ResultRich<Order> createExecute(CreateOrderParameters parameters, Order applyOrder) {  // 订单创建执行方法，参数为请求参数和前置方法创建的临时订单
2311      try {
2312          //到账金额
2313          applyOrder.setTargetAmount(new Money(parameters.getTargetCurrency(), parameters.getTargetAmount()));  // 设置到账金额对象（目标货币 + 金额）
2314
2315          //本币种支付(不支持统一货币结算)
2316          if (parameters.getSourceCurrency().equals(parameters.getTargetCurrency())) {  // 如果支付货币和到账货币相同（本币支付，无需兑换）
2317              applyOrder.setBusinessRate("1");  // 业务汇率为 1（无兑换）
2318              applyOrder.setPandaRate("1");  // 平台汇率为 1
2319              applyOrder.setRate("1");  // 折算汇率为 1
2320              applyOrder.setSourceAmount(new Money(parameters.getSourceCurrency(), parameters.getTargetAmount()));  // 充值金额 = 到账金额（金额相同）
2321          } else {  // 跨币种支付（需要汇率兑换）
2322              boolean isSettle = applyOrder.getSettleAmount() != null;  // 判断是否有结算金额（是否使用中间结算货币）
2323              boolean isSameCurrency = isSettle && applyOrder.getSettleAmount().getCurrencyCode().equals(parameters.getSourceCurrency());  // 判断结算货币是否等于支付货币
2324
2325              if (isSameCurrency) {  // 如果结算货币 = 支付货币（结算金额已知，直接计算汇率）
2326                  String settleRate = new BigDecimal(applyOrder.getTargetAmount().getLi())  // 计算结算汇率 = 到账金额 / 结算金额
2327                          .divide(new BigDecimal(applyOrder.getSettleAmount().getLi())).setScale(11, RoundingMode.HALF_UP).toString();  // 保留 11 位小数，四舍五入
2328                  applyOrder.setBusinessRate(settleRate);  // 设置业务汇率
2329                  applyOrder.setPandaRate(settleRate);  // 设置平台汇率
2330                  applyOrder.setRate(settleRate);  // 设置折算汇率
2331                  applyOrder.setSettleRate("1");  // 结算汇率为 1（因为结算货币 = 支付货币）
2332              } else {  // 结算货币 ≠ 支付货币，或无结算货币（需要查询汇率）
2333                  RateDetailV2 rateDetail = this.queryTopUpRate(applyOrder.getCountryCode(), parameters.getSourceCurrency(), isSettle
2334                          ? applyOrder.getSettleCurrency() : parameters.getTargetCurrency()  // 如果有结算货币，查询"支付货币→结算货币→目标货币"汇率；否则查询"支付货币→目标货币"汇率
2335                          , parameters.getTargetCurrency(), applyOrder.getPayerInfo().getWalletProvider(), isSettle);  // 参数：国家码、支付货币、中间货币、目标货币、钱包提供商、是否结算
2336
2337                  logger.info("订单:{},计算结算汇率结果：{}", applyOrder.getSeqNo(), JSONObject.toJSONString(rateDetail));
2338                  if (rateDetail == null) {  // 如果查询汇率失败
2339                      return ResultRich.newInstance(ErrorCode.QUERY_RATE_FAILED);  // ⚠️ 异常处理：返回汇率查询失败错误
2340                  }
2341                  applyOrder.setBusinessRate(rateDetail.getPandaRate());  // 设置业务汇率（从汇率服务返回）
2342                  applyOrder.setPandaRate(rateDetail.getPandaRate());  // 设置平台汇率
2343                  applyOrder.setRate(rateDetail.getZheSuan());  // 设置折算汇率
2344                  if (isSettle) {  // 如果使用了结算货币
2345                      applyOrder.setSettleRate(rateDetail.getPandaRate());  // 设置结算汇率
2346                  }
2347              }
2348              //充值金额
2349              applyOrder.setSourceAmount(Money.foreignExchangeByDivide(isSettle ? applyOrder.getSettleAmount() : applyOrder.getTargetAmount()
2350                      , new BigDecimal(isSettle ? applyOrder.getSettleRate() : applyOrder.getBusinessRate()), parameters.getSourceCurrency()));  // 计算充值金额：目标金额 / 汇率 = 充值金额（反向计算）
2351
2352              if (!isSameCurrency && isSettle) {  // 如果有结算货币且结算货币 ≠ 支付货币（需要重新计算业务汇率）
2353                  String pandaRate = new BigDecimal(applyOrder.getTargetAmount().getLi())  // 重新计算总体汇率 = 到账金额 / 充值金额
2354                          .divide(new BigDecimal(applyOrder.getSourceAmount().getLi()), 11, RoundingMode.HALF_UP).toString();  // 保留 11 位小数
2355                  applyOrder.setBusinessRate(pandaRate);  // 更新业务汇率（展示给用户的总体汇率）
2356                  applyOrder.setPandaRate(pandaRate);  // 更新平台汇率
2357              }
2358          }
```

### 第二部分：金额校验和 Redis 存储

```java
2359
2360          // 创建订单基础配置校验
2361          ResultRich checkRes = this.validateOrderAmount(parameters, applyOrder);  // 校验订单金额是否符合限额、合规要求
2362          if (checkRes.getCode() != ResultRich.SUCCESS_CODE) {  // 如果校验失败
2363              return checkRes;  // ⚠️ 异常处理：返回校验错误结果
2364          }
2365
2366          //根据顶啊
2367
2368          logger.info("查看创建订单信息:{}",JSONObject.toJSONString(applyOrder));
2369
2370          // 在redis中创建临时订单
2371          if (redisService.lock(createOrderKey + applyOrder.getSeqNo())) {  // 使用分布式锁防止重复创建同一订单
2372              redisService.set("recharge-order-" + parameters.getUserId(), JSON.toJSON(applyOrder), 3000);  // 将临时订单存入 Redis，过期时间 3000 秒（50 分钟）
2373          } else {
2374              logger.error("生成同一笔订单号,{}", applyOrder.getSeqNo());
2375              return ResultRich.newInstance(ErrorCode.APPLY_ORDER_INSERT_ERROR);  // ⚠️ 异常处理：获取锁失败，说明订单号重复
2376          }
2377
2378          logger.info("订单创建成功， 订单号放入redis中， seqNo={}", applyOrder.getSeqNo());
2379          return ResultRich.newInstance(applyOrder);  // 返回创建成功的订单对象
2380      } catch (Exception e) {
2381          logger.error("创建订单execute参数异常---->", e);
2382          return ResultRich.newInstance(ErrorCode.APPLY_ORDER_INSERT_ERROR);  // ⚠️ 异常处理：捕获所有异常，返回订单创建错误
2383      }
2384  }
```

**复杂逻辑详解**：

- **第 2326-2327 行**（结算汇率计算）：
  1. `applyOrder.getTargetAmount().getLi()` - 获取到账金额的最小单位值（例如分）
  2. `applyOrder.getSettleAmount().getLi()` - 获取结算金额的最小单位值
  3. `new BigDecimal(...).divide(...)` - 执行高精度除法：到账金额 / 结算金额
  4. `.setScale(11, RoundingMode.HALF_UP)` - 保留 11 位小数，四舍五入
  5. `.toString()` - 转换为字符串存储

- **第 2333-2335 行**（汇率查询逻辑）：
  ```
  场景 1：无结算货币（isSettle = false）
    查询：支付货币 → 目标货币 的直接汇率
  
  场景 2：有结算货币（isSettle = true）
    查询：支付货币 → 结算货币 → 目标货币 的两段汇率
    例如：USD → CNY → PHP（美元通过人民币结算到菲律宾比索）
  ```

- **第 2349-2350 行**（充值金额计算）：
  1. 如果有结算金额：`充值金额 = 结算金额 / 结算汇率`
  2. 如果无结算金额：`充值金额 = 到账金额 / 业务汇率`
  3. `Money.foreignExchangeByDivide()` - 执行外汇计算并创建 Money 对象

- **第 2353-2356 行**（重新计算总体汇率）：
  ```
  问题：有结算货币时，前面设置的是"结算货币→目标货币"的汇率
  解决：重新计算"支付货币→目标货币"的总体汇率
  公式：总体汇率 = 到账金额 / 充值金额
  用途：这个汇率用于展示给用户（用户不关心中间结算过程）
  ```

**被调用的业务方法**：
1. **queryTopUpRate()** - 查询充值汇率（调用汇率服务，根据国家、货币对、支付渠道返回实时汇率）
2. **validateOrderAmount()** - 校验订单金额（验证单笔限额、日累计限额、月累计限额等合规要求）
3. **Money.foreignExchangeByDivide()** - 外汇金额计算（高精度除法，处理货币精度）
4. **redisService.lock()** - 分布式锁（防止并发创建重复订单）
5. **redisService.set()** - Redis 存储（临时订单数据，用于后续流程查询）

需要深入解释哪些方法？（输入方法名或序号，或"无"结束）



我来系统地解释这些金额和汇率字段之间的关系。这是一个涉及多级货币兑换的复杂系统。

## 核心概念图解

### 1. 三个金额字段

```
汇款流程：
┌─────────────┐        ┌──────────────┐        ┌─────────────┐
│  汇款人支付  │  兑换  │  中间结算    │  兑换  │  收款人到账  │
│             │  ───→  │  (可选)      │  ───→  │             │
│ sourceAmount│        │settleAmount  │        │targetAmount │
│  (支付货币) │        │ (结算货币)   │        │ (目标货币)  │
└─────────────┘        └──────────────┘        └─────────────┘
     USD                     CNY                    PHP
    (美元)                  (人民币)               (菲律宾比索)
```

### 2. 四个汇率字段

```
businessRate  - 业务汇率：展示给用户的汇率（sourceAmount → targetAmount 的总体汇率）
pandaRate     - 平台汇率：通常与 businessRate 相同，平台内部使用
rate          - 折算汇率：实际计算用汇率，可能包含额外费用
settleRate    - 结算汇率：settleAmount → targetAmount 的汇率（仅在使用结算货币时）
```

---

## 场景详解

### 场景 1：本币支付（无需兑换）

**条件**：`sourceCurrency == targetCurrency`

**示例**：用户用澳元支付，收款人收澳元
```
支付：100 AUD  →  到账：100 AUD

金额关系：
  sourceAmount  = 100 AUD
  targetAmount  = 100 AUD
  settleAmount  = null（不需要结算）

汇率关系：
  businessRate = "1"
  pandaRate    = "1"
  rate         = "1"
  settleRate   = null

代码位置：createExecute 第 2316-2320 行
```

---

### 场景 2：跨币种支付，无结算货币

**条件**：`sourceCurrency ≠ targetCurrency`，且 `settleAmount == null`

**示例**：用户用美元支付，收款人收菲律宾比索
```
支付：100 USD  →  到账：5650 PHP

步骤：
1. 查询 USD → PHP 汇率：1 USD = 56.5 PHP
2. 计算充值金额：5650 / 56.5 = 100 USD

金额关系：
  targetAmount  = 5650 PHP（用户指定）
  businessRate  = "56.5"（从汇率服务获取）
  sourceAmount  = 5650 / 56.5 = 100 USD（计算得出）

汇率关系：
  businessRate = "56.5"（查询得到）
  pandaRate    = "56.5"
  rate         = "56.8"（可能略高，包含手续费）

公式：
  sourceAmount = targetAmount / businessRate

代码位置：
  - 查询汇率：createExecute 第 2333-2343 行
  - 计算金额：createExecute 第 2349-2350 行
```

---

### 场景 3：有结算货币，且结算货币 = 支付货币

**条件**：`settleAmount != null` 且 `settleCurrency == sourceCurrency`

**示例**：用户指定用 100 USD 结算，收款人收 5650 PHP
```
支付：100 USD  →  结算：100 USD  →  到账：5650 PHP
       (支付货币)     (结算货币)      (目标货币)

步骤：
1. 用户已经指定了结算金额：100 USD
2. 计算结算汇率：5650 / 100 = 56.5
3. 因为支付货币 = 结算货币，充值金额 = 结算金额

金额关系：
  settleAmount  = 100 USD（用户指定）
  targetAmount  = 5650 PHP（用户指定）
  sourceAmount  = 100 USD（= settleAmount）

汇率关系：
  settleRate   = "56.5"（计算：targetAmount / settleAmount）
  businessRate = "56.5"
  pandaRate    = "56.5"
  rate         = "56.5"

公式：
  settleRate = targetAmount / settleAmount
  sourceAmount = settleAmount（因为货币相同）

代码位置：createExecute 第 2325-2331 行
```

---

### 场景 4：有结算货币，且结算货币 ≠ 支付货币（最复杂）

**条件**：`settleAmount != null` 且 `settleCurrency ≠ sourceCurrency`

**示例**：用户用新加坡元支付，通过美元结算，收款人收菲律宾比索
```
支付：139 SGD  →  结算：100 USD  →  到账：5650 PHP
     (支付货币)     (结算货币)       (目标货币)

步骤：
1. 用户指定结算金额：100 USD，到账金额：5650 PHP
2. 查询 SGD → USD 汇率：1 USD = 1.39 SGD
3. 计算充值金额：100 * 1.39 = 139 SGD
4. 重新计算总体汇率：5650 / 139 = 40.65（给用户看的 SGD → PHP 总汇率）

金额关系：
  settleAmount  = 100 USD（用户指定）
  targetAmount  = 5650 PHP（用户指定）
  sourceAmount  = 139 SGD（通过汇率服务计算）

汇率关系（两段）：
  第一段（SGD → USD）：
    settleRate   = "1.39"（查询得到）
  
  第二段（USD → PHP）：
    settleRate   = "56.5"（计算：5650 / 100）
  
  总体（SGD → PHP，给用户看）：
    businessRate = "40.65"（重新计算：5650 / 139）
    pandaRate    = "40.65"

公式：
  第一步：查询 sourceCurrency → settleCurrency 汇率
  第二步：sourceAmount = settleAmount / 查询到的汇率
  第三步：businessRate = targetAmount / sourceAmount（重新计算总体汇率）

代码位置：
  - 查询汇率：createExecute 第 2333-2346 行
  - 计算金额：createExecute 第 2349-2350 行
  - 重算汇率：createExecute 第 2352-2357 行
```

---

## 关键计算公式总结

### 基本公式
```java
// 汇率的基本定义
汇率 = 目标金额 / 源金额

// 金额计算（已知汇率和目标金额，求源金额）
sourceAmount = targetAmount / rate
```

### 无结算货币场景
```java
// 直接兑换
sourceAmount = targetAmount / businessRate

// 示例：到账 5650 PHP，汇率 56.5
// sourceAmount = 5650 / 56.5 = 100 USD
```

### 有结算货币场景（结算货币 = 支付货币）
```java
// 计算结算汇率
settleRate = targetAmount / settleAmount

// 充值金额 = 结算金额
sourceAmount = settleAmount

// 示例：结算 100 USD，到账 5650 PHP
// settleRate = 5650 / 100 = 56.5
// sourceAmount = 100 USD
```

### 有结算货币场景（结算货币 ≠ 支付货币）
```java
// 第一步：查询 sourceCurrency → settleCurrency 汇率（调用汇率服务）
// 第二步：计算充值金额
sourceAmount = settleAmount / queryRate

// 第三步：重新计算总体汇率（给用户展示）
businessRate = targetAmount / sourceAmount

// 示例：支付 SGD，结算 100 USD，到账 5650 PHP
// queryRate = 1.39（1 USD = 1.39 SGD）
// sourceAmount = 100 / 1.39 = 71.94 SGD
// businessRate = 5650 / 71.94 = 78.54（1 SGD = 78.54 PHP）
```

---

## 为什么需要这么复杂的设计？

### 1. 结算货币的作用
```
问题：某些货币对没有直接汇率市场
  SGD → PHP（新加坡元 → 菲律宾比索）直接汇率可能流动性差、波动大

解决：通过 USD 中转
  SGD → USD → PHP（两段汇率都很稳定）
```

### 2. 多个汇率字段的作用
```
businessRate - 给用户看的汇率（简化的总体汇率）
pandaRate    - 平台内部使用（通常与 businessRate 相同）
rate         - 实际计算用（可能包含手续费、汇率波动保护）
settleRate   - 结算环节的汇率（财务对账用）
```

### 3. 为什么要重新计算 businessRate（第 2352-2357 行）
```
用户视角：我用 SGD 支付，收款人收 PHP，我关心的是 SGD → PHP 的汇率

系统实际：SGD → USD（汇率 1.39）→ PHP（汇率 56.5）

问题：如果直接告诉用户两段汇率，太复杂

解决：重新计算总体汇率
  用户支付：139 SGD
  收款人收：5650 PHP
  展示汇率：1 SGD = 40.65 PHP（5650 / 139）
  
用户体验：简单明了，不需要理解中间的美元结算过程
```

---

## 实际示例代码追踪

以**场景 4**为例，追踪代码执行流程：

```java
// 假设参数
CreateOrderParameters parameters:
  - sourceCurrency: "SGD"
  - targetCurrency: "PHP"
  - targetAmount: "5650"
  - userId: "user123"

Order applyOrder（来自 createBefore）:
  - settleCurrency: "USD"
  - settleAmount: Money("USD", "100")

// ========== createExecute 执行流程 ==========

// 第 2313 行：设置到账金额
applyOrder.setTargetAmount(new Money("PHP", "5650"));
// 结果：targetAmount = 5650 PHP

// 第 2316 行：判断是否本币支付
if ("SGD".equals("PHP")) {  // false，进入 else
  
  // 第 2322 行：判断是否有结算货币
  boolean isSettle = applyOrder.getSettleAmount() != null;  // true
  
  // 第 2323 行：判断结算货币是否等于支付货币
  boolean isSameCurrency = true && "USD".equals("SGD");  // false
  
  // 第 2325 行：isSameCurrency = false，跳过
  
  // 第 2333 行：查询汇率（SGD → USD → PHP）
  RateDetailV2 rateDetail = queryTopUpRate("SG", "SGD", "USD", "PHP", "Novatti", true);
  // 返回：rateDetail.getPandaRate() = "1.39"（SGD → USD）
  
  // 第 2341-2346 行：设置汇率
  applyOrder.setBusinessRate("1.39");
  applyOrder.setPandaRate("1.39");
  applyOrder.setRate("1.39");
  applyOrder.setSettleRate("1.39");  // 因为 isSettle = true
  
  // 第 2349-2350 行：计算充值金额
  // sourceAmount = settleAmount / settleRate
  applyOrder.setSourceAmount(Money.foreignExchangeByDivide(
    Money("USD", "100"),  // settleAmount
    new BigDecimal("1.39"),  // settleRate
    "SGD"
  ));
  // 结果：sourceAmount = 100 / 1.39 = 71.94 SGD
  
  // 第 2352 行：判断需要重新计算总体汇率
  if (true && true) {  // !isSameCurrency && isSettle
    
    // 第 2353-2354 行：重新计算 SGD → PHP 总体汇率
    String pandaRate = new BigDecimal("5650")  // targetAmount.getLi()
      .divide(new BigDecimal("71.94"), 11, RoundingMode.HALF_UP)
      .toString();
    // 结果：pandaRate = "78.54"（1 SGD = 78.54 PHP）
    
    // 第 2355-2356 行：更新业务汇率
    applyOrder.setBusinessRate("78.54");
    applyOrder.setPandaRate("78.54");
    // 注意：rate 和 settleRate 保持不变（用于内部计算）
  }
}

// ========== 最终订单状态 ==========
applyOrder:
  - sourceAmount: 71.94 SGD（用户需要支付）
  - settleAmount: 100 USD（中间结算金额）
  - targetAmount: 5650 PHP（收款人到账）
  - businessRate: "78.54"（展示给用户：1 SGD = 78.54 PHP）
  - pandaRate: "78.54"（平台内部）
  - rate: "1.39"（实际计算用：SGD → USD）
  - settleRate: "1.39"（结算汇率：SGD → USD）
```

---

通过这个完整的梳理，可以看到这个汇率系统的设计目的是：
1. **灵活性**：支持直接兑换和中间结算两种模式
2. **透明性**：给用户展示简化的总体汇率
3. **准确性**：内部保留详细的分段汇率用于计算和对账


Perfect! Now I have all the information. Let me generate the detailed explanation:

---

## OrderServiceWrapper.commitOrderBefore 方法解析

**业务术语表**：
- **PartnerSeqNo**: 合作伙伴订单号，外部系统（商户）传入的订单流水号
- **KYC Route (KYC 路由)**: 根据商户和国家配置的 KYC 流程路由规则
- **Panda 系统**: 推测为内部的订单管理或风控系统
- **PdUserId**: Panda 系统的用户 ID
- **CreateOrder 标识**: KYC 路由中的配置标识，决定是否需要在 Panda 系统中创建订单
- **FundingType**: 资金类型（例如银行转账、信用卡等）
- **ExtraFee**: 额外手续费

**方法概述**：
这是订单提交前的预处理方法，负责防重复订单检查、查询 KYC 信息、计算手续费，以及根据 KYC 路由配置决定是否需要在 Panda 系统中创建关联订单。这是订单创建流程的重要前置环节。

**相关上下文**：
```java
@Resource
private PayerClient payerClient;  // 汇款人服务客户端，查询 KYC 信息

@Resource
private ApplyOrderDao applyOrderDao;  // 订单数据访问对象，查询订单记录

@Resource
private KycRouteMapper kycRouteMapper;  // KYC 路由配置，决定订单创建流程

@Resource
private UsersDao usersDao;  // 用户数据访问对象，查询用户信息

@Resource
private CommonConfigs commonConfigs;  // 通用配置，包含 Panda 系统 URL
```

**代码逐行解释**：

### 第一部分：防重复订单检查

```java
83   public ResultRich<Order> commitOrderBefore(Order order) {  // 订单提交前置处理，参数为待创建的订单对象
84       try {
85           //查询订单信息
86           ApplyOrderDo applyOrderDo = applyOrderDao.selectByPartnerSeqNo(order.getPartnerSeqNo());  // 根据合作伙伴订单号查询是否已存在订单
87           if (applyOrderDo != null) {  // 如果订单已存在（防重复提交）
88               log.info("该订单以被创建:{}", applyOrderDo.getPartnerSeqNo());
89               Order result = new Order();  // 创建返回对象
90               BeanUtils.copyProperties(applyOrderDo, result);  // 复制已存在订单的数据
91               result.setUserId(applyOrderDo.getUserId());  // 设置用户 ID
92               result.setSeqNo(applyOrderDo.getSeqNo());  // 设置系统内部订单号
93               result.setPartnerOrderId(applyOrderDo.getOrderIdIn3rdSys());  // 设置第三方系统订单 ID
94               ResultRich<Order> returnResult = new ResultRich<>();  // 创建返回结果对象
95               returnResult.setCode(ErrorCode.ORDER_HAS_CREATED.getCode());  // 设置错误码：订单已创建
96               returnResult.setModel(result);  // 返回已存在的订单信息
97               return returnResult;  // ⚠️ 异常处理：订单重复，返回已有订单信息
98           }
```

### 第二部分：查询 KYC 信息和计算手续费

```java
99
100          //获取kyc信息
101          Payer payer = new Payer();  // 创建汇款人查询对象
102          payer.setUserId(order.getUserId());  // 设置用户 ID
103          payer.setCountryCode(order.getCountryCode());  // 设置国家代码
104          ResultRich<Payer> payerResult = payerClient.queryKycInfo(payer);  // 远程调用：查询汇款人 KYC 信息
105          if (payerResult.getCode() == ResultRich.SUCCESS_CODE && payerResult.getModel() != null) {  // 如果查询成功
106              order.setPayerId(payerResult.getModel().getId());  // 设置汇款人 ID 到订单
107          }
108
109          //计算支付方式对应的手续
110          this.calculate(order);  // 调用手续费计算方法（根据支付方式、金额、国家等计算手续费）
```

### 第三部分：KYC 路由判断和 Panda 系统订单创建

```java
111
112          Users selected = usersDao.selectByUid(order.getUserId());  // 查询用户详细信息
113          log.info("用户信息：{}", JSONObject.toJSONString(selected));
114          if (selected != null && StringUtils.isNotEmpty(selected.getPdUserId())) {  // 如果用户存在且有 Panda 用户 ID
115              List<KycRoute> kycRoutes = kycRouteMapper.selectByCondition(selected.getMerchantNo(), null, CountryEnum.isEurCountry(order.getCountryCode()) ? "EU" : order.getCountryCode());  // 查询 KYC 路由配置（根据商户号和国家码）
116              log.info("kyc路由信息：{}", JSONObject.toJSONString(kycRoutes));
117              if (kycRoutes != null && !kycRoutes.isEmpty() && kycRoutes.get(0).getCreateOrder() == 1) {  // 如果路由配置存在且 createOrder 标识为 1（需要在 Panda 系统创建订单）
118                  JSONObject pandaOrder = new JSONObject();  // 创建 Panda 订单请求对象
119                  pandaOrder.put("userId", selected.getPdUserId());  // Panda 用户 ID
120                  pandaOrder.put("countryCode", order.getCountryCode());  // 国家代码
121                  pandaOrder.put("sourceCurrency", order.getSourceAmount().getCurrencyCode());  // 支付货币代码
122                  pandaOrder.put("sourceAmount", order.getSourceAmount().getYuanAmount());  // 支付金额（元单位）
123                  pandaOrder.put("type", order.getFundingType());  // 资金类型
124                  pandaOrder.put("remitType", 0);  // 汇款类型（0 表示标准汇款，推测）
125                  pandaOrder.put("feeAmount", order.getFeeAmount().getYuanAmount());  // 手续费金额（元单位）
126                  pandaOrder.put("extraFeeAmount", StringUtils.isNotEmpty(order.getExtraFee()) ? new BigDecimal(order.getExtraFee()).divide(new BigDecimal(1000), 2, RoundingMode.HALF_UP) : new BigDecimal("0"));  // 额外手续费（从分转为元，除以 1000 并保留 2 位小数）
127                  log.info("panda创建订单参数:{}", JSONObject.toJSONString(pandaOrder));
128                  HttpResponse response = HttpUtils.doPost(commonConfigs.getPandaCreateOrderUrl(), new HashMap<>(), JSONObject.toJSONString(pandaOrder));  // HTTP POST 调用 Panda 创建订单接口
129                  String ress = HttpUtils.dealResponse(response);  // 处理响应，提取 JSON 字符串
130                  log.info("panda创建订单结果:{}", ress);
131                  ResultRich<JSONObject> resultRich = JSONObject.parseObject(ress, new TypeReference<ResultRich<JSONObject>>() {
132                  });  // 解析 JSON 响应
133                  if (!resultRich.isSuc() || resultRich.getModel() == null) {  // 如果 Panda 创建订单失败
134                      log.info("panda创建订单失败:{}", JSONObject.toJSONString(resultRich));
135                      return ResultRich.newInstance(resultRich.getCode(), resultRich.getMsg());  // ⚠️ 异常处理：返回 Panda 系统的错误信息
136                  }
137                  JSONObject pandaRes = JSONObject.parseObject(JSONObject.toJSONString(resultRich.getModel()), JSONObject.class);  // 提取 Panda 返回的订单数据
138                  if (StringUtils.isNotEmpty(pandaRes.getString("seqNo"))) {  // 如果返回了 Panda 订单号
139                      order.setPandaSeqNo(pandaRes.getString("seqNo"));  // 设置 Panda 订单号到当前订单（关联两个系统的订单）
140                  }
141                  if (StringUtils.isNotEmpty(pandaRes.getString("paymentLink")) && order.getCountryCode().equals(CountryEnum.NewZealand.getMsg())) {  // 如果是新西兰订单且返回了支付链接
142                      order.setPaymentLink(pandaRes.getString("paymentLink"));  // 设置支付链接（推测为新西兰特定的支付跳转链接）
143                  }
144              }
145          }
146          log.info("commit order 结果:{}", JSONObject.toJSONString(order));
147          return ResultRich.newInstance(order);  // 返回处理完成的订单对象
148      } catch (Exception e) {
149          log.info("commit order 异常:{}", e);
150          return ResultRich.newInstance(ErrorCode.SYSTEM_ERROR);  // ⚠️ 异常处理：捕获所有异常，返回系统错误
151      }
152  }
```

**复杂逻辑详解**：

- **第 115 行**（KYC 路由查询逻辑）：
  ```
  selectByCondition(商户号, null, 国家码)
  
  特殊处理：欧盟国家统一使用 "EU" 作为国家码
  - 如果是欧盟国家：CountryEnum.isEurCountry() 返回 true，使用 "EU"
  - 如果不是欧盟：使用具体国家码（例如 "AU"、"NZ"）
  
  目的：欧盟国家 KYC 规则统一，使用同一套路由配置
  ```

- **第 117 行**（createOrder 标识判断）：
  ```
  kycRoutes.get(0).getCreateOrder() == 1
  
  业务含义：
  - createOrder = 1：需要在 Panda 系统中创建关联订单（可能用于风控、额度管理）
  - createOrder = 0：不需要在 Panda 系统创建（简化流程，降低系统耦合）
  
  使用场景推测：
  - 高风险国家/商户：需要 Panda 系统双重审核
  - 低风险国家/商户：跳过 Panda 流程，加快订单处理
  ```

- **第 126 行**（额外手续费转换）：
  ```
  new BigDecimal(order.getExtraFee()).divide(new BigDecimal(1000), 2, RoundingMode.HALF_UP)
  
  拆解：
  1. order.getExtraFee() - 获取额外手续费（存储单位：厘，1元 = 1000厘）
  2. new BigDecimal(...) - 转换为高精度数值
  3. .divide(new BigDecimal(1000), 2, RoundingMode.HALF_UP)
     - 除以 1000：厘 → 元
     - 保留 2 位小数
     - 四舍五入
  
  示例：
    extraFee = "1500"（厘）
    转换后 = 1500 / 1000 = 1.50（元）
  ```

- **第 141-142 行**（新西兰支付链接）：
  ```
  特殊处理：仅新西兰订单需要支付链接
  
  推测原因：
  - 新西兰可能使用特定的支付网关（例如 POLi）
  - 需要跳转到外部支付页面完成支付
  - 其他国家可能使用内嵌支付或其他方式
  ```

**被调用的业务方法**：
1. **applyOrderDao.selectByPartnerSeqNo()** - 根据合作伙伴订单号查询订单（防重复提交检查）
2. **payerClient.queryKycInfo()** - 远程调用：查询汇款人 KYC 审核状态和信息
3. **calculate()** - 计算订单手续费（根据支付方式、国家、金额等因素）
4. **usersDao.selectByUid()** - 查询用户详细信息（包含 Panda 用户 ID、商户号）
5. **kycRouteMapper.selectByCondition()** - 查询 KYC 路由配置（决定订单创建流程）
6. **HttpUtils.doPost()** - HTTP POST 请求工具（调用 Panda 系统创建订单接口）

**业务流程图**：
```
┌─────────────────────────────────────────┐
│ 1. 检查订单是否已存在（PartnerSeqNo）    │
└────────┬────────────────────────────────┘
         │ 存在 → 返回已有订单
         │ 不存在 ↓
┌─────────────────────────────────────────┐
│ 2. 查询汇款人 KYC 信息                   │
│    设置 PayerId 到订单                   │
└────────┬────────────────────────────────┘
         ↓
┌─────────────────────────────────────────┐
│ 3. 计算手续费（calculate 方法）          │
└────────┬────────────────────────────────┘
         ↓
┌─────────────────────────────────────────┐
│ 4. 查询用户信息（是否有 PdUserId）       │
└────────┬────────────────────────────────┘
         │ 有 PdUserId ↓
┌─────────────────────────────────────────┐
│ 5. 查询 KYC 路由配置                     │
│    （根据商户号和国家码）                │
└────────┬────────────────────────────────┘
         │ createOrder = 1 ↓
┌─────────────────────────────────────────┐
│ 6. 调用 Panda 系统创建关联订单           │
│    - 构造请求参数                        │
│    - HTTP POST 调用                      │
│    - 保存 PandaSeqNo 到订单              │
│    - 新西兰订单保存支付链接              │
└────────┬────────────────────────────────┘
         ↓
┌─────────────────────────────────────────┐
│ 7. 返回处理完成的订单对象                │
└─────────────────────────────────────────┘
```

**容错机制**：
1. 订单已存在 → 返回已有订单信息（幂等性保证）
2. KYC 查询失败 → 不设置 PayerId，继续流程（非阻塞）
3. Panda 订单创建失败 → 中断流程，返回错误（阻塞，因为路由配置要求必须创建）
