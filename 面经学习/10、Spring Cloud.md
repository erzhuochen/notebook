
# 基础

## 总览图
![769](10、Spring%20Cloud.assets/file-20260727103751275.png)

## 从单体到集体架构
![636](10、Spring%20Cloud.assets/file-20260727104203918.png)
![622](10、Spring%20Cloud.assets/file-20260727104217123.png)
![](10、Spring%20Cloud.assets/file-20260727111231200.png)

## 创建微服务项目
![561](10、Spring%20Cloud.assets/file-20260727140403448.png)


# nacos

Nacos 在该项目中主要承担三类职责：

1. **服务注册与发现**：记录各微服务实例的名称、IP、端口和健康状态。
2. **配置中心**：集中保存各服务的数据库、Redis、Kafka、Dubbo 等配置。
3. **Dubbo 注册中心**：注册 `@DubboService` 暴露的 RPC 服务，供 `@DubboReference` 查找。

此外，项目还自定义了一个扩展，从 Nacos 加载 ShardingSphere-JDBC 的分库分表配置。

需要注意：Nacos 不负责转发业务请求。客户端从 Nacos获得服务地址后，HTTP 或 Dubbo 请求仍然直接发送给目标服务。

## 一、服务注册与发现

项目引入了两个核心依赖：

```pom
<dependency>
    <groupId>com.alibaba.cloud</groupId>
    <artifactId>spring-cloud-starter-alibaba-nacos-discovery</artifactId>
</dependency>

<dependency>
    <groupId>com.alibaba.cloud</groupId>
    <artifactId>spring-cloud-starter-alibaba-nacos-config</artifactId>
</dependency>
```

### 1. 服务提供者注册

以用户服务为例：

```java
@SpringBootApplication
@EnableDubbo
@EnableDiscoveryClient // 显示开启服务发现
public class UserProviderApplication {
}
```


对应配置：

```yaml
spring:
  application:
    name: qiyu-live-user-provider # 注册到Nacos的服务名
  cloud:
    nacos:
      discovery:
        server-addr: localhost:8848 # Nacos服务端地址
        namespace: 1bc15ccf-f070-482e-8325-c3c46e427aaf # 命名空间。用于隔离不同环境，例如开发、测试、生产
```


服务启动后，Nacos 服务列表中会出现：

```
qiyu-live-user-provider
```


### 2. 服务消费者发现实例

项目中有一个非常直接的使用案例：

```
List<ServiceInstance> serverInstanceList =
        discoveryClient.getInstances("qiyu-live-im-core-server");

Collections.shuffle(serverInstanceList);
ServiceInstance serviceInstance = serverInstanceList.get(0);
```

源码位置：[ImServiceImpl.java (line 31)](D:/workspace/qiyu-live/后端代码/qiyu-live-app/qiyu-live-api/src/main/java/org/qiyu/live/api/service/impl/ImServiceImpl.java:31)

这里的流程是：

```
qiyu-live-api
    ↓ 根据服务名查询
Nacos
    ↓ 返回 IM 服务实例列表
选择一个实例
    ↓
把 IM 地址返回给前端
```

不过当前实现存在几个明显边界：

- 没有处理实例列表为空的情况，可能出现下标越界。
- 使用 `Collections.shuffle()` 随机选择，不是真正的负载均衡器。
- 只使用 Nacos 返回的主机地址，TCP/WS 端口仍硬编码为 `8085` 和 `8086`。
- 更合理的实现是注册实例元数据，或者使用独立的 IM 节点发现与负载均衡策略。

### 3. Gateway 通过服务名路由

教程给出的 Nacos 网关配置是：

```
spring:
  cloud:
    gateway:
      routes:
        - id: qiyu-live-api
          uri: lb://qiyu-live-api
          predicates:
            - Path=/live/api/**
```

`lb://qiyu-live-api` 表示：

1. Gateway 向 Nacos 查询 `qiyu-live-api` 的实例。
2. Spring Cloud LoadBalancer 选择一个实例。
3. Gateway 将请求转发过去。

当前路由配置不在本地源码中，而是按教程设计放在 Nacos。参考：[系统架构文档 (line 4028)](D:/workspace/qiyu-live/1-系统架构分析与用户中台的实现.md:4028)

## 二、配置中心

用户服务的配置导入方式是：

```
spring:
  application:
    name: qiyu-live-user-provider
  cloud:
    nacos:
      config:
        server-addr: localhost:8848
        namespace: <namespace-id>
        group: DEFAULT_GROUP
  config:
    import:
      - optional:nacos:${spring.application.name}.yml
```

最终得到的 Data ID 是：

```
qiyu-live-user-provider.yml
```

Nacos 配置通常由三个维度唯一确定：

|配置项|项目示例|作用|
|---|---|---|
|Data ID|`qiyu-live-user-provider.yml`|标识具体配置文件|
|Group|`DEFAULT_GROUP`|对配置进一步分组|
|Namespace|项目配置的 namespace ID|隔离不同环境|

服务启动时的基本流程是：

```
读取本地 bootstrap.yml
    ↓
确定服务名、Nacos 地址、Namespace 和 Group
    ↓
从 Nacos 获取 qiyu-live-user-provider.yml
    ↓
合并到 Spring Environment
    ↓
创建数据源、Redis、Kafka、Dubbo 等 Bean
```

`optional:nacos:` 表示该配置源是可选的。Nacos 配置拉取失败时，不一定立即因为“导入失败”而终止；但如果后续缺少数据源、Dubbo 等必要属性，服务仍然可能启动失败。

### 动态刷新

项目的网关白名单配置类使用了：

```
@ConfigurationProperties(prefix = "qiyu.gateway")
@RefreshScope
public class GatewayApplicationProperties {
}
```

源码位置：[GatewayApplicationProperties.java (line 9)](D:/workspace/qiyu-live/后端代码/qiyu-live-app/qiyu-live-gateway/src/main/java/org/qiyu/live/gateway/properties/GatewayApplicationProperties.java:9)

这说明项目希望修改 Nacos 中的 `qiyu.gateway` 配置后，重新绑定白名单属性。

但不能笼统地说“放在 Nacos 的所有配置都能安全热更新”：

- 普通 Bean 未必会重新创建。
- 数据源、线程池、监听端口等配置不适合随意热更新。
- `WsNettyImServerStarter` 即使有 `@RefreshScope`，修改端口也不代表已绑定的 Netty 端口一定能无损切换。
- 是否刷新还受配置导入方式和对应依赖版本影响。

## 三、Nacos 作为 Dubbo 注册中心

项目的 Dubbo 配置为：

```
dubbo:
  application:
    name: qiyu-live-api
  registry:
    address: nacos://localhost:8848?namespace=<namespace-id>
```

源码位置：[qiyu-live-api/application.yml (line 1)](D:/workspace/qiyu-live/后端代码/qiyu-live-app/qiyu-live-api/src/main/resources/application.yml:1)

服务提供者：

```
@DubboService
public class UserRpcImpl implements IUserRpc {
}
```

服务消费者：

```
@DubboReference
private IUserRpc userRpc;
```

调用过程是：

```
provider 启动
    ↓
@DubboService 注册接口信息到 Nacos

consumer 启动
    ↓
@DubboReference 从 Nacos订阅提供者地址
    ↓
Dubbo 选择提供者
    ↓
consumer 直接调用 provider
```

这里容易混淆两套注册信息：

- `@EnableDiscoveryClient`：属于 Spring Cloud 服务发现，主要供 Gateway、`DiscoveryClient` 使用。
- `@DubboService/@DubboReference`：属于 Dubbo 服务发现，注册粒度更偏向 RPC 接口。

它们可以共用同一个 Nacos 服务端，但不是同一套调用机制。

## 四、从 Nacos 读取分库分表配置

项目自定义了：

```
public class NacosDriverURLProvider
        implements ShardingSphereDriverURLProvider {
}
```

源码位置：[NacosDriverURLProvider.java (line 17)](D:/workspace/qiyu-live/后端代码/qiyu-live-app/qiyu-live-framework/qiyu-live-framework-datasource-starter/src/main/java/org/idea/qiyu/live/framework/datasource/starter/NacosDriverURLProvider.java:17)

配置形式类似：

```
jdbc:shardingsphere:nacos:localhost:8848:qiyu-live-user-shardingjdbc.yaml?...
```

它会：

1. 判断 JDBC URL 是否包含 `nacos:`。
2. 解析 Nacos 地址、Data ID、用户名和 Namespace。
3. 调用 `NacosFactory.createConfigService()`。
4. 通过 `configService.getConfig()`读取分片规则。
5. 把配置内容返回给 ShardingSphere Driver。

项目还通过 Java SPI 注册了该扩展：[SPI 配置 (line 1)](D:/workspace/qiyu-live/后端代码/qiyu-live-app/qiyu-live-framework/qiyu-live-framework-datasource-starter/src/main/resources/META-INF/services/org.apache.shardingsphere.driver.jdbc.core.driver.ShardingSphereDriverURLProvider:1)

需要注意：当前代码只调用了 `getConfig()`，没有注册配置监听器，因此这里主要是**启动时拉取配置**，不能描述成分片规则自动热更新。

## 面试口述

> 这个项目主要把 Nacos用于服务注册发现和配置中心，同时也作为 Dubbo 的注册中心。  
> 服务启动时通过 `spring.application.name` 确定服务名，使用 `spring-cloud-starter-alibaba-nacos-discovery` 将实例注册到 Nacos。Gateway 可以通过 `lb://服务名`查询实例并进行负载均衡，项目中 API 服务也直接使用 `DiscoveryClient` 查询 IM 服务实例。  
> 配置中心方面，服务通过 `spring.config.import`加载`${spring.application.name}.yml`，把数据库、Redis、Kafka 和 Dubbo 等配置集中存储在 Nacos，并通过 Namespace、Group 和 Data ID 进行隔离。  
> Dubbo 服务提供者使用 `@DubboService`注册 RPC 接口，消费者使用 `@DubboReference`订阅并调用。Nacos只负责保存和发现服务地址，真正的 RPC 流量不会经过 Nacos。  
> 此外，项目还基于 ShardingSphere SPI 自定义了 `NacosDriverURLProvider`，在启动时从 Nacos读取分库分表配置。

## 常见追问

### 1. Namespace、Group、Data ID 有什么区别？

- Namespace：环境级隔离，例如 dev、test、prod。
- Group：同一环境内进一步分组。
- Data ID：具体配置文件，一般与服务名对应。

### 2. Nacos挂了，服务还能互相调用吗？

已经获取到的实例信息可能仍能依靠客户端本地缓存继续使用，但新服务注册、实例变更发现和配置更新会受到影响。准确行为还要看 Nacos客户端版本、缓存和重试配置。

### 3. Nacos配置修改后一定立即生效吗？

不一定。需要配置监听和 Spring 刷新机制，相关 Bean 还要支持重新绑定。连接池、监听端口等资源型配置即使刷新，也未必适合在线变更。

### 4. Nacos和 Dubbo 是什么关系？

Dubbo 是 RPC 框架，负责代理、序列化、网络通信、负载均衡等；Nacos在这里是注册中心，负责保存 Dubbo 服务提供者地址。两者职责不同。

本次为只读源码分析，未修改项目，也未启动 Nacos 验证外部配置。另有一个需要注意的仓库差异：当前 Gateway 的 `bootstrap.yml` 导入 `qiyu-live-gateway.yml`，而教程写的是 `qiyu-live-gateway.yaml`，实际部署时 Data ID 必须与导入名称严格一致。