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

# 源码
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