# RPC (Remote Procedure Call)

## 概述

### 是什么

RPC 即「远程过程调用」，核心目标是让开发者**像调用本地方法一样调用另一台机器上的方法**，把网络通信的细节全部屏蔽掉。

```java
// 看起来和调本地方法没有区别
UserDTO user = userService.getById(123L);
// 实际上：序列化参数 → 网络传输 → 远端反序列化 → 执行 → 结果原路返回
```

### 解决什么问题

单体应用拆成微服务后，原本的方法调用变成了跨进程通信。如果让每个业务开发都去手写 Socket、处理粘包、管理连接池、做序列化，成本高且容易出错。RPC 框架把这些封装成基础设施，业务代码只面向接口编程。

### 与 HTTP/REST 的区别

| 维度 | RPC (Dubbo/gRPC) | REST over HTTP |
|------|------------------|----------------|
| 通信协议 | 自定义二进制协议 / HTTP2 | HTTP/1.1 文本 |
| 序列化 | Hessian2、Protobuf 等二进制 | JSON |
| 性能 | 高，报文小、解析快 | 相对低，头部与 JSON 开销大 |
| 可读性 | 差，需工具解析 | 好，肉眼可读 |
| 跨语言 | 取决于框架（gRPC 强，Dubbo 弱） | 强 |
| 典型场景 | **公司内部服务之间调用** | **对外开放 API、前后端交互** |

一句话选型：**对内用 RPC，对外用 REST**。

## 核心概念

### 一次调用的完整链路

理解这条链路，才能看懂超时、序列化、重试这些配置到底作用在哪一环：

```
Consumer                                    Provider
   |                                           |
   |-- 1. 调用接口方法                          |
   |-- 2. 动态代理拦截（Stub）                  |
   |-- 3. 服务发现：从注册中心拿到地址列表        |
   |-- 4. 负载均衡：选出一台机器                 |
   |-- 5. 序列化：对象 → 二进制                  |
   |-- 6. 网络传输（Netty）  ----------------->  |
   |                                     7. 反序列化
   |                                     8. 反射调用真实实现
   |                                     9. 序列化返回值
   |   <-------------------------------- 10. 写回响应
   |-- 11. 反序列化，返回结果给业务代码           |
```

**关键点**：整个过程中业务代码只感知第 1 步和第 11 步，中间 9 步都由框架完成。所谓「像本地调用一样」，靠的是第 2 步的**动态代理** —— Consumer 端持有的只是一个接口的代理对象，方法体里做的是发网络请求。

### 四大组成部分

| 组件 | 作用 | 常见实现 |
|------|------|----------|
| 代理 (Stub) | 生成接口的客户端代理 | JDK 动态代理、Javassist |
| 序列化 | 对象与字节流互转 | Hessian2、Protobuf、Kryo、JSON |
| 网络传输 | 高性能 IO | Netty（NIO） |
| 注册中心 | 服务地址的注册与发现 | Nacos、ZooKeeper、Consul |

## 主流框架选型

| 框架 | 协议 | 跨语言 | 适用场景 |
|------|------|--------|----------|
| **Dubbo** | Dubbo/Triple | 一般（Triple 协议后改善） | Java 技术栈为主的公司，生态成熟 |
| **gRPC** | HTTP/2 + Protobuf | 强 | 多语言混合、需要流式通信 |
| **Spring Cloud OpenFeign** | HTTP/1.1 + JSON | 强 | Spring Cloud 全家桶，本质是声明式 HTTP 客户端 |
| **Thrift** | 自定义 | 强 | 老牌方案，Facebook 系 |

需要说明的是，**OpenFeign 严格来讲不是 RPC**，它底层走的是 HTTP + JSON，只是用注解把调用写成了接口方法的样子。性能不如二进制协议，但调试方便、上手成本低。

## 实际工作中的使用方法

### 工程结构：三模块划分

这是生产项目最常见也最重要的组织方式，**接口必须独立成模块**：

```
order-service/
├── order-api/          # 只有接口和 DTO，不含实现，打成 jar 发到私服
│   └── src/main/java/com/xxx/order/
│       ├── api/OrderService.java
│       └── dto/OrderDTO.java
├── order-provider/     # 服务提供方，依赖 order-api 并实现它
└── order-consumer/     # 调用方（也可以是其他服务）
```

为什么要拆出 `api` 模块：调用方只需要依赖这个轻量 jar 就能编程，不会把 Provider 的实现代码、数据库依赖一起拉进来。Provider 和 Consumer 通过这个 jar 达成契约。

### 接口与 DTO 的设计规范

```java
// order-api 模块
public interface OrderService {
    OrderDTO getById(Long id);
    PageResult<OrderDTO> query(OrderQuery query);
}

@Data
public class OrderDTO implements Serializable {
    // 必须显式声明，否则类结构变化后反序列化会失败
    private static final long serialVersionUID = 1L;

    private Long id;
    // 用包装类型 Integer 而不是 int：
    // 基本类型无法表达"没有传这个字段"，默认值 0 会造成语义歧义
    private Integer status;
    private BigDecimal amount;
    private LocalDateTime createTime;
}
```

几条实践约束：

- **DTO 必须实现 `Serializable` 并显式写 `serialVersionUID`**
- **字段一律用包装类型**，避免 `int` 默认 0 与「未设置」无法区分
- **不要传 `Entity`/`PO`**，DTO 与数据库实体解耦，否则数据库改字段会波及所有调用方
- **不要传 `Map<String, Object>`**，失去类型约束，调用方无法通过编译期发现问题

### Dubbo 3 实战

**依赖（Provider 与 Consumer 相同）**

```xml
<dependency>
    <groupId>org.apache.dubbo</groupId>
    <artifactId>dubbo-spring-boot-starter</artifactId>
    <version>3.2.10</version>
</dependency>
<!-- 注册中心用 Nacos -->
<dependency>
    <groupId>com.alibaba.nacos</groupId>
    <artifactId>nacos-client</artifactId>
    <version>2.3.2</version>
</dependency>
```

**Provider 实现**

```java
// 注意是 org.apache.dubbo.config.annotation.DubboService
// 不要误用 Spring 的 @Service
@DubboService(version = "1.0.0", timeout = 3000)
public class OrderServiceImpl implements OrderService {

    @Resource
    private OrderMapper orderMapper;

    @Override
    public OrderDTO getById(Long id) {
        return OrderConverter.toDTO(orderMapper.selectById(id));
    }
}
```

**Provider 配置 `application.yml`**

```yaml
dubbo:
  application:
    name: order-provider
  registry:
    address: nacos://127.0.0.1:8848
  protocol:
    name: tri          # Dubbo 3 推荐 Triple 协议，基于 HTTP/2，可被 gRPC 调用
    port: 20880
  provider:
    timeout: 3000      # 在 Provider 端提供默认超时，这是推荐做法
    threads: 200       # 业务线程池大小
```

**Consumer 调用**

```java
@RestController
public class OrderController {

    // 注入的是动态代理对象，不是本地 Bean
    @DubboReference(version = "1.0.0", timeout = 2000, retries = 0)
    private OrderService orderService;

    @GetMapping("/order/{id}")
    public OrderDTO get(@PathVariable Long id) {
        return orderService.getById(id);
    }
}
```

### gRPC 实战

**定义 proto 契约**

```protobuf
syntax = "proto3";
option java_package = "com.xxx.order.grpc";
option java_multiple_files = true;

service OrderService {
  rpc GetById (GetByIdRequest) returns (OrderReply);
}

message GetByIdRequest {
  int64 id = 1;
}

message OrderReply {
  int64 id = 1;
  int32 status = 2;
  string amount = 3;
}
```

**Maven 插件自动生成 Java 代码**

```xml
<plugin>
    <groupId>org.xolstice.maven.plugins</groupId>
    <artifactId>protobuf-maven-plugin</artifactId>
    <version>0.6.1</version>
    <configuration>
        <protocArtifact>com.google.protobuf:protoc:3.25.3:exe:${os.detected.classifier}</protocArtifact>
        <pluginId>grpc-java</pluginId>
        <pluginArtifact>io.grpc:protoc-gen-grpc-java:1.62.2:exe:${os.detected.classifier}</pluginArtifact>
    </configuration>
</plugin>
```

**服务端实现**

```java
@GrpcService
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {

    @Override
    public void getById(GetByIdRequest req, StreamObserver<OrderReply> observer) {
        OrderReply reply = OrderReply.newBuilder()
                .setId(req.getId())
                .setStatus(1)
                .build();
        observer.onNext(reply);
        observer.onCompleted();   // 必须调用，否则客户端一直挂起直到超时
    }
}
```

## [进阶] 生产环境关键配置

### 超时：必须逐层收敛

**最容易出事故的一项配置**。默认超时是 1000ms，实际业务通常不够。

关键原则：**调用链上游的超时必须大于下游超时之和**，否则下游还在正常执行，上游已经放弃，白白浪费资源。

```
错误配置：A(超时 1s) → B(超时 2s) → C(超时 2s)
         A 在 1 秒时就断了，B 和 C 的计算全部作废

正确配置：A(超时 5s) → B(超时 3s) → C(超时 1s)
```

配置位置上，Dubbo 的 Consumer 端优先级高于 Provider 端。推荐做法是 **Provider 配一个合理默认值**（它最清楚自己要跑多久），Consumer 只在有特殊需求时覆盖。

### 重试：默认值是个陷阱

Dubbo 的 `retries` **默认为 2，意味着一次失败会再试 2 次，总共请求 3 次**。

```java
// 查询接口：幂等，可以重试
@DubboReference(retries = 2)
private OrderQueryService queryService;

// 写接口：必须关掉，否则超时重试会造成重复下单、重复扣款
@DubboReference(retries = 0)
private OrderCreateService createService;
```

**只对幂等接口开重试**。这是新人最常踩的生产事故来源之一 —— 接口本身没问题，只是响应慢了一点触发超时，框架自动重试导致数据重复。

如果写接口确实需要重试保障，正确做法是**在业务层做幂等**：调用方传唯一业务 ID，Provider 用它去重。

### 集群容错策略

| 策略 | 行为 | 适用场景 |
|------|------|----------|
| `failover` | 失败自动切换其他节点重试（**默认**） | 幂等的读操作 |
| `failfast` | 失败立即报错，不重试 | 写操作、非幂等接口 |
| `failsafe` | 失败直接忽略，只记日志 | 写审计日志等非核心链路 |
| `failback` | 失败后台定时重发 | 消息通知类 |
| `forking` | 并行调用多台，取最快返回 | 实时性要求极高且资源充裕 |

```java
@DubboReference(cluster = "failfast", retries = 0)
private PaymentService paymentService;
```

### 负载均衡

| 策略 | 说明 |
|------|------|
| `random` | 按权重随机（**默认**），整体最均匀 |
| `roundrobin` | 加权轮询 |
| `leastactive` | 最少活跃调用数，慢的机器自动少接请求 |
| `consistenthash` | 一致性哈希，相同参数固定路由到同一台，适合做本地缓存 |

机器性能不均时 `leastactive` 通常比默认的 `random` 表现更好。

### 序列化选型

Dubbo 3 默认 `hessian2`。需要更高性能可换 `fastjson2` 或 `protobuf`（Triple 协议下）。

**安全提示**：Dubbo 2.7.x 早期版本的 Hessian 反序列化存在远程代码执行漏洞。Dubbo 3.2 之后引入了序列化白名单机制，生产环境务必升级到较新版本，并避免注册中心暴露在公网。

### 优雅停机

发版时如果直接 kill 进程，正在处理的请求会失败。正确流程是：**先从注册中心摘除节点 → 等待存量请求处理完 → 再关闭进程**。

```yaml
dubbo:
  application:
    shutwait: 10000    # 等待 10 秒处理存量请求
```

Kubernetes 环境下还要配合 `preStop` 钩子预留摘流时间。

### 泛化调用

网关、测试平台这类场景，无法在编译期依赖每个服务的 api jar，可用泛化调用：

```java
GenericService svc = referenceConfig.get();
Object result = svc.$invoke(
        "getById",
        new String[]{"java.lang.Long"},
        new Object[]{123L});
```

返回的是 `Map` 结构而非强类型对象。日常业务开发不要用这种方式。

## [进阶] 常见坑点

| 现象 | 原因与解决 |
|------|------------|
| 订单重复创建 | `retries` 默认 2，超时触发自动重试。写接口设 `retries = 0` |
| 调用方报超时但服务端日志显示执行成功 | 超时时间小于实际执行耗时，调整超时或优化性能 |
| 上游超时了下游还在跑 | 超时时间未逐层收敛，上游超时应大于下游之和 |
| 新增 DTO 字段后调用方报错 | 未显式声明 `serialVersionUID`，或调用方 api jar 版本未更新 |
| 服务能启动但调不通 | 注册中心地址、`version` 或 `group` 不一致，两端必须完全对齐 |
| 服务端线程池打满 | 慢 SQL 或下游阻塞拖垮线程，需隔离线程池并加熔断 |
| 自定义异常在调用方变成了 `RuntimeException` | 异常类必须在 api 模块中且可序列化，否则 Dubbo 会包装它 |
| 传输大对象导致 GC 频繁 | 分页返回，Dubbo 默认单包上限 8MB，不要一次拉全量数据 |

### 接口演进的兼容性原则

RPC 接口一旦被多方调用，改动必须向后兼容：

- **只增不删**：新增字段安全，删除或重命名字段会导致老调用方反序列化异常
- **不改字段类型**：`Integer` 改 `Long` 会出问题
- **Protobuf 不要复用字段编号**：删掉的字段编号要用 `reserved` 标记
- **破坏性变更走版本号**：Dubbo 用 `version = "2.0.0"` 并行发布新旧两版，等调用方全部迁移完再下线旧版

## 参考资源

- [WebSocket-协议与实现原理](../../network/websocket/notes.md) - 长连接通信基础
- [SSE-服务器单向推送](../../network/SSE/notes.md) - 另一种通信模式
- [Apache Dubbo 官方文档](https://cn.dubbo.apache.org/zh-cn/) - 中文文档完善
- [gRPC 官方文档](https://grpc.io/docs/languages/java/) - Java 快速上手
- [Protocol Buffers 语言指南](https://protobuf.dev/programming-guides/proto3/) - proto3 规范
