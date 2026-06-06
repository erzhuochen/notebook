# 9. Spring 系统学习笔记

学习方式：这部分属于新学内容，先建立知识体系，再补面试问答。

## 学习目标

学完后需要能回答：

- Spring IOC 是什么？
- Bean 生命周期是什么？
- Spring 如何解决循环依赖？
- AOP 是什么，底层如何实现？
- Spring 事务为什么会失效？
- Spring MVC 请求流程是什么？
- Spring Boot 自动装配是什么？

---

# 一、Spring 核心思想

## IOC

IOC 是控制反转，把对象创建和依赖管理交给 Spring 容器，而不是业务代码自己 new。

好处：

- 降低对象之间的耦合。
- 统一管理对象生命周期。
- 方便做 AOP、事务、配置注入、测试替换。

## DI

DI 是依赖注入，是 IOC 的具体实现方式。

常见方式：

- 构造器注入。
- Setter 注入。
- 字段注入。

推荐：

- 业务代码优先使用构造器注入，依赖更明确，也更利于测试。

---

# 二、Bean 生命周期

## 核心主线

```text
扫描 Bean 定义
-> 实例化
-> 属性填充
-> Aware 回调
-> BeanPostProcessor 前置处理
-> 初始化
-> BeanPostProcessor 后置处理
-> 使用 Bean
-> 销毁 Bean
```

## 关键阶段

### BeanDefinition

Spring 会先把类信息解析成 BeanDefinition，里面包含类名、作用域、依赖、初始化方法等元信息。

### 实例化

创建对象本身，相当于调用构造方法。

### 属性填充

给对象注入依赖。

### 初始化

执行初始化回调，例如：

- `@PostConstruct`
- `InitializingBean`
- 自定义 init-method

### BeanPostProcessor

Bean 后置处理器可以在初始化前后增强 Bean。AOP 代理对象通常也和这个阶段有关。

### 销毁

容器关闭时执行销毁逻辑，例如：

- `@PreDestroy`
- `DisposableBean`
- destroy-method

## 易错点

- 实例化和初始化不是一回事。
- AOP 代理对象通常不是原始对象本身。
- Bean 生命周期中，后置处理器非常关键。

---

# 三、循环依赖

## 什么是循环依赖

两个或多个 Bean 互相依赖：

```text
A 依赖 B
B 依赖 A
```

## Spring 解决方式

Spring 通过三级缓存解决单例 Bean 的 setter 循环依赖。

```text
一级缓存：完整单例对象
二级缓存：提前暴露的半成品对象
三级缓存：对象工厂，用于生成提前代理对象
```

## 解决流程简化版

```text
创建 A
-> A 实例化后提前暴露
-> A 填充属性时需要 B
-> 创建 B
-> B 填充属性时需要 A
-> 从缓存中拿到提前暴露的 A
-> B 创建完成
-> A 继续完成属性填充和初始化
```

## 不能解决的情况

- 构造器循环依赖。
- prototype 作用域循环依赖。
- 某些复杂代理场景。

## 易错点

- 三级缓存不是为了解决所有循环依赖，而是为了解决带 AOP 代理时提前暴露对象的问题。
- 构造器注入的循环依赖通常无法解决，因为对象还没实例化完成。

---

# 四、AOP

## AOP 是什么

AOP 是面向切面编程，把日志、权限、事务、监控等横切逻辑从业务代码中抽离出来。

## 核心概念

- Join Point：连接点，可以被增强的位置。
- Pointcut：切点，匹配哪些连接点。
- Advice：通知，增强逻辑。
- Aspect：切面，切点 + 通知。
- Proxy：代理对象。

## 实现方式

### JDK 动态代理

- 基于接口。
- 代理对象实现同一接口。

### CGLIB

- 基于继承生成子类。
- 不要求目标类实现接口。
- final 类或 final 方法不能被正常代理。

## 易错点

- Spring AOP 主要基于代理，不是直接修改原方法。
- 同类内部方法调用可能绕过代理，导致 AOP 或事务不生效。

---

# 五、Spring 事务

## 事务核心

Spring 事务本质上是基于 AOP 对方法进行增强，在方法执行前开启事务，正常返回提交事务，抛出异常回滚事务。

## 传播行为

常见重点：

- REQUIRED：默认，有事务就加入，没有就新建。
- REQUIRES_NEW：新建事务，挂起外层事务。
- NESTED：嵌套事务，依赖保存点。

## 隔离级别

对应数据库隔离级别：

- READ UNCOMMITTED
- READ COMMITTED
- REPEATABLE READ
- SERIALIZABLE

## 事务失效场景

- 方法不是 public。
- 同类内部方法调用。
- 异常被 catch 但没有重新抛出。
- 默认只回滚 RuntimeException 和 Error。
- 数据库引擎不支持事务。
- 没有被 Spring 容器管理。

## 易错点

- `@Transactional` 不是加了就一定生效。
- 事务是否回滚和异常类型、传播行为、代理调用方式都有关。

---

# 六、Spring MVC

## 请求流程

```text
请求进入 DispatcherServlet
-> HandlerMapping 找到处理器
-> HandlerAdapter 调用 Controller
-> 参数绑定和类型转换
-> 执行业务逻辑
-> 返回 ModelAndView 或 ResponseBody
-> 消息转换/视图解析
-> 返回响应
```

## 核心组件

- DispatcherServlet：前端控制器，统一入口。
- HandlerMapping：根据请求找到 Controller。
- HandlerAdapter：适配并调用 Controller。
- ViewResolver：解析视图。
- HttpMessageConverter：处理 JSON 等请求/响应体转换。
- ExceptionHandler：异常处理。

## 易错点

- `@RequestBody` 依赖消息转换器读取请求体。
- `@ResponseBody` 表示返回值写入响应体，而不是视图名。
- Controller 不应该堆太多业务逻辑，复杂逻辑应放到 Service。

---

# 七、Spring Boot

## Spring Boot 解决什么问题

Spring Boot 不是替代 Spring，而是简化 Spring 应用开发。

主要能力：

- 自动装配。
- starter 依赖管理。
- 内嵌 Web 容器。
- 外部化配置。
- 运行监控和健康检查。

## 自动装配

核心思想：

```text
根据 classpath 中的依赖
结合条件注解
自动创建默认 Bean
```

关键点：

- `@SpringBootApplication`
- `@EnableAutoConfiguration`
- 条件注解：`@ConditionalOnClass`、`@ConditionalOnMissingBean` 等。
- 自动配置类。

## 启动流程简化版

```text
创建 SpringApplication
-> 准备环境
-> 创建 ApplicationContext
-> 加载 BeanDefinition
-> 执行自动装配
-> 刷新容器
-> 启动内嵌服务器
-> 执行 Runner
```

## 易错点

- 自动装配不是无脑创建 Bean，而是由条件注解决定是否生效。
- starter 本身通常主要负责依赖聚合，真正配置逻辑在 auto-configuration 中。

---

# 面试问答附录

## Q1：Spring IOC 是什么？

标准回答：

> IOC 是控制反转，意思是对象的创建和依赖管理不再由业务代码自己控制，而是交给 Spring 容器。业务对象只需要声明依赖，容器负责创建 Bean、注入依赖、管理生命周期。这样可以降低耦合，也方便做 AOP、事务、测试替换等能力。

## Q2：Bean 生命周期是什么？

标准回答：

> Spring 会先解析 BeanDefinition，然后实例化 Bean，进行属性填充，执行 Aware 回调，经过 BeanPostProcessor 前置处理，执行初始化方法，再经过 BeanPostProcessor 后置处理，之后 Bean 就可以使用。容器关闭时会执行销毁回调。

## Q3：Spring 如何解决循环依赖？

标准回答：

> Spring 主要通过三级缓存解决单例 Bean 的 setter 循环依赖。一级缓存保存完整 Bean，二级缓存保存提前暴露的半成品 Bean，三级缓存保存 ObjectFactory，用于必要时生成提前代理对象。这样 A 创建过程中需要 B，B 又需要 A 时，可以从缓存中拿到提前暴露的 A。

## Q4：AOP 是什么？Spring AOP 怎么实现？

标准回答：

> AOP 是面向切面编程，用来把日志、事务、权限等横切逻辑从业务代码中抽离出来。Spring AOP 主要基于代理实现，如果目标对象实现接口，通常可以使用 JDK 动态代理；如果没有接口，可以使用 CGLIB 生成子类代理。

## Q5：Spring 事务为什么会失效？

标准回答：

> Spring 事务基于 AOP 代理实现，所以常见失效原因包括同类内部方法调用绕过代理、方法不是 public、异常被 catch 后没有抛出、默认不回滚检查异常、对象没有交给 Spring 管理、数据库本身不支持事务等。

## Q6：Spring MVC 请求流程是什么？

标准回答：

> 请求先进入 DispatcherServlet，然后 HandlerMapping 找到对应 Controller，HandlerAdapter 负责调用方法，过程中完成参数绑定和类型转换。Controller 执行业务逻辑后返回结果，如果是 JSON 响应，会通过 HttpMessageConverter 写入响应体；如果是页面，则通过 ViewResolver 解析视图。

## Q7：Spring Boot 自动装配是什么？

标准回答：

> Spring Boot 自动装配是根据当前项目 classpath 中的依赖、配置文件和条件注解，自动创建合适的 Bean。它通过自动配置类和 `@Conditional` 系列注解实现，只有满足条件时配置才会生效。starter 负责聚合依赖，auto-configuration 负责真正的自动配置逻辑。

