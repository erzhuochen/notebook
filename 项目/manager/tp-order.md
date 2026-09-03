# 一、通用方法论：新项目按这 5 步走

核心原则：**先建立骨架认知，再垂直打穿一条线，最后横向铺开**。绝对不要一上来就一个个文件读。

| 步骤        | 做什么                                           | 目的                                     |
| ----------- | ------------------------------------------------ | ---------------------------------------- |
| 1. 看骨架   | 构建文件（pom/package.json）、目录结构、启动配置 | 它是什么技术栈？依赖谁？端口和路由前缀？ |
| 2. 垂直打穿 | 挑 1~2 个核心接口，从入口一路追到底              | 建立第一条完整的"心智链路"               |
| 3. 横向归纳 | 再看 2~3 个同类接口                              | 找出**套路**——套路才是项目的真实结构     |
| 4. 找数据   | 表结构 + 状态枚举                                | 业务系统的本质是数据流转，状态机是骨髓   |
| 5. 划边界   | 外部依赖、MQ、定时任务                           | 知道哪里"出了这个仓库"，避免瞎找         |


---

# 二、用 tp-order 实操

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

# 三、给你的下一步动作清单

按优先级：

1. **读三个 DTO**：`CreateOrderParameters` / `Order` / `ApplyOrder`（在 `tp-entity` 仓库）。
   *接口的参数和返回值是最浓缩的业务文档，比读实现快 10 倍。*

2. **读两个状态枚举**：`ApplyOrderStatus` / `ApplyOrderPaymentStatus`。
   在 `OrderController.java:1114` 的超时任务、`commitOrderBefore` 里到处都是它们。**订单系统的核心就是状态机**，把这两个枚举的取值和流转画出来，你就懂一半了。

3. **读表**：`src/main/resources/mapper/ApplyOrderMapper.xml` + `pojo/model/ApplyOrderDo`。

4. **展开 `createBefore` / `createExecute`**（`ApplyOrderServiceImpl.java:2089` 往上找）。这是我这次没展开的部分，留给你练手。

5. **本地起一个 debug**：`/create` 拿到 `seqNo`，再拿它调 `/commit`，在 `OrderController.java:150` 打断点走一遍。**跑通一次胜过读十遍。**

---

# 四、顺带教你「批判性读代码」

新人常犯的错是把代码当圣经。这个项目里就有两个例子：

- **`OrderServiceHandler.java:63`**：`commitOrderResultHandler` 是所有国家共用的，日志却写着 `"sg创建订单返回结果"` —— 复制粘贴残留。**日志文案不可信，以代码逻辑为准。**

- **`OrderFactory.java:60-62`**：`getFactory()` 每次 `new OrderFactory()`，而这个 new 出来的实例 `@Resource` 字段全是 null。之所以能跑，是因为 `orderServiceMap` 是 `static`，由 Spring 托管的那个真实例在 `@PostConstruct` 里填好了。**这是个能工作但很脆的写法** —— 看到这种地方要在心里标记，别照抄。

看到"味道怪"的地方，先假设**是有历史原因的**，记下来，攒够几个再一起问 leader —— 比逐个追问更高效，也更显专业。