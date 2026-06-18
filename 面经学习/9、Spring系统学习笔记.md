# 9、Spring 系统学习笔记

> 使用方式：你先在主问题和追问的 `回答：` 下面写自己的答案，我负责检查是否正确。默认只在对话中指出问题和建议改写，只有你明确说“直接修改文件”时，才会改这个文件。

> 本文件根据截图中的 Spring + Spring Boot + Spring MVC 知识体系重新整理。当前阶段按你的学习范围，重点学习 **Spring / Spring MVC / Spring Boot**，暂时不展开 **Spring Cloud / 微服务**。截图中偏项目阶段或外部资料链接的内容不逐条搬运，本文以面试复习问题为主。

> 图中橙色或高频内容用 **【重点】** 标记。

## 一、学习目标

学完 Spring 后，需要能讲清楚下面几条主线：

1. **Spring 是什么**，它解决了什么问题，为什么后端开发常用 Spring。
2. **IoC / DI** 是什么，Spring 容器如何创建、管理和装配 Bean。
3. **Bean 生命周期、作用域、循环依赖** 是什么，三级缓存为什么能解决部分循环依赖。
4. **AOP** 是什么，Spring AOP 如何基于代理增强方法，为什么会失效。
5. **Spring 事务** 如何实现，传播行为、回滚规则、事务失效场景怎么理解。
6. **Spring MVC** 请求处理流程是什么，常用注解、参数绑定、异常处理、拦截器和过滤器怎么理解。
7. **Spring Boot** 自动配置、starter、条件装配、SPI / 自动配置加载机制是什么。
8. 能说出 Spring 中常见设计模式和开发中容易踩的坑。

## 二、知识树

### 1. Spring 基础知识概述 **【重点】**

- Spring 是什么
- Spring 解决了什么问题
- Spring Framework、Spring MVC、Spring Boot 的关系
- Spring 的核心模块
- Spring 的优点和局限

### 2. Bean **【重点】**

- Bean 的定义
- Bean 和普通对象的区别
- BeanDefinition
- BeanFactory 和 ApplicationContext
- Bean 的作用域
- 单例 Bean 的线程安全问题
- Bean 生命周期
- BeanPostProcessor
- FactoryBean
- Bean 循环依赖

### 3. IoC **【重点】**

- IoC 控制反转
- DI 依赖注入
- IoC 和 DI 的区别
- IoC 容器职责
- Bean 注册、创建、依赖注入、生命周期管理
- Spring IoC 支持的功能

### 4. AOP **【重点】**

- AOP 是什么
- 横切关注点
- 连接点、切点、通知、切面、织入
- JDK 动态代理
- CGLIB
- Spring AOP 和 AspectJ
- AOP 失效场景

### 5. 三级缓存 / 循环依赖 **【重点】**

- 什么是循环依赖
- 构造器循环依赖
- setter / 字段注入循环依赖
- 一级缓存、二级缓存、三级缓存
- 提前暴露对象
- AOP 代理对象和循环依赖
- 为什么二级缓存不够

### 6. Spring 事务 **【重点】**

- 编程式事务和声明式事务
- `PlatformTransactionManager`
- `TransactionDefinition`
- `TransactionStatus`
- 事务传播行为
- 事务隔离级别
- 回滚规则
- `@Transactional` 失效场景

### 7. Spring 常用注解 **【重点】**

- 组件注册注解
- 依赖注入注解
- 配置类注解
- Web 层注解
- 事务注解
- 属性绑定注解
- 条件装配注解

### 8. Spring MVC

> 截图中标注为“不做重点”，但后端面试仍然常问基础流程，需要掌握主线。

- `DispatcherServlet`
- `HandlerMapping`
- `HandlerAdapter`
- 参数解析
- 消息转换器
- 返回值处理
- 视图解析
- 全局异常处理
- 拦截器
- 过滤器

### 9. Spring Boot **【重点】**

- Spring Boot 是什么
- 自动配置
- starter
- 自定义 starter
- 条件装配
- 配置属性绑定
- Spring Boot SPI / 自动配置加载
- 模式注解
- 常用注解

### 10. Spring 中的设计模式

- 单例模式
- 工厂模式
- 代理模式
- 模板方法模式
- 观察者模式
- 适配器模式
- 策略模式

### 11. MyBatis 相关内容

> 截图中包含 MyBatis，但它不属于 Spring 主线。这里只作为“和 Spring 后端面试常一起出现的扩展内容”保留，不作为当前 Spring 学习重点。

- MyBatis 执行流程
- MyBatis 延迟加载
- MyBatis 一级缓存和二级缓存
- MyBatis SQL 注入
- MyBatis 设计模式
- MyBatis 和 Spring 整合

### 12. Spring 常见错误

- Bean 注入失败
- 单例 Bean 状态共享问题
- 循环依赖问题
- AOP 失效
- 事务失效
- 注解使用错误
- Spring MVC 参数绑定错误
- Spring Boot 自动配置不生效

## 三、学习顺序

| 顺序 | 模块 | 学习目的 |
| --- | --- | --- |
| 1 | Spring 基础概述 | 先知道 Spring 解决什么问题 |
| 2 | IoC / DI | 理解对象创建和依赖管理为什么交给容器 |
| 3 | Bean | 理解 Spring 管理对象的基本单位 |
| 4 | Bean 生命周期 | 理解 Bean 从定义到销毁的完整过程 |
| 5 | 循环依赖 / 三级缓存 | 理解 Spring 容器的高频难点 |
| 6 | AOP | 理解代理增强和横切逻辑 |
| 7 | Spring 事务 | 理解事务代理、传播行为、回滚和失效 |
| 8 | Spring 常用注解 | 把核心概念和日常开发对应起来 |
| 9 | Spring MVC | 理解 Web 请求从进入到响应的完整链路 |
| 10 | Spring Boot | 理解自动配置和 starter 如何简化开发 |
| 11 | 设计模式 / 常见错误 | 用于面试追问和排错 |
| 12 | MyBatis 扩展 | 后续需要时再补充 |

## 四、高频面试题

### 1. 谈一谈你对 Spring 的理解？ **【重点】**

回答：

#### 追问 1：Spring 主要解决了什么问题？

回答：

#### 追问 2：为什么说 Spring 能降低代码耦合？

回答：

#### 追问 3：Spring Framework、Spring MVC、Spring Boot 分别是什么关系？

回答：

#### 追问 4：Spring 的核心思想有哪些？

回答：

### 2. 什么是 Spring Bean？ **【重点】**

回答：

#### 追问 1：Bean 和普通 Java 对象有什么区别？

回答：

#### 追问 2：一个类如何成为 Spring 容器中的 Bean？

回答：

#### 追问 3：Bean 的名称默认怎么生成？

回答：

### 3. Spring 框架中的 Bean 默认是单例的吗？ **【重点】**

回答：

#### 追问 1：Spring 中的单例和设计模式中的单例完全一样吗？

回答：

#### 追问 2：为什么 Spring 默认使用单例 Bean？

回答：

#### 追问 3：如何把 Bean 改成非单例？

回答：

### 4. Spring Bean 有哪些作用域？ **【重点】**

回答：

#### 追问 1：`singleton` 和 `prototype` 有什么区别？

回答：

#### 追问 2：Web 环境下常见的作用域有哪些？

回答：

#### 追问 3：`prototype` Bean 的销毁由 Spring 管理吗？

回答：

### 5. Spring 单例 Bean 是线程安全的吗？ **【重点】**

回答：

#### 追问 1：为什么无状态 Bean 通常是线程安全的？

回答：

#### 追问 2：如果单例 Bean 中有可变成员变量，会有什么问题？

回答：

#### 追问 3：怎么避免单例 Bean 的线程安全问题？

回答：

### 6. Spring Bean 的生命周期是什么？ **【重点】**

回答：

#### 追问 1：实例化和初始化有什么区别？

回答：

#### 追问 2：属性填充发生在生命周期的哪个阶段？

回答：

#### 追问 3：`BeanPostProcessor` 在生命周期中起什么作用？

回答：

#### 追问 4：AOP 代理通常在哪个阶段创建？

回答：

### 7. 什么是 IoC？ **【重点】**

回答：

#### 追问 1：为什么需要 IoC？

回答：

#### 追问 2：IoC 和 DI 有什么区别？

回答：

#### 追问 3：Spring IoC 容器的职责是什么？

回答：

#### 追问 4：Spring 的 IoC 支持哪些功能？

回答：

### 8. BeanFactory 和 ApplicationContext 有什么区别？ **【重点】**

回答：

#### 追问 1：为什么说 `BeanFactory` 更偏底层？

回答：

#### 追问 2：`ApplicationContext` 扩展了哪些能力？

回答：

#### 追问 3：单例 Bean 通常什么时候创建？

回答：

### 9. BeanDefinition 是什么？ **【重点】**

回答：

#### 追问 1：`BeanDefinition` 里保存哪些信息？

回答：

#### 追问 2：为什么 Spring 不直接用 `Class` 创建 Bean？

回答：

#### 追问 3：`BeanDefinition` 和 Bean 实例有什么区别？

回答：

### 10. FactoryBean 和 BeanFactory 有什么区别？

回答：

#### 追问 1：`FactoryBean` 适合解决什么问题？

回答：

#### 追问 2：通过 `FactoryBean` 获取的是工厂本身还是工厂生产的对象？

回答：

#### 追问 3：MyBatis 的 Mapper 代理对象和 `FactoryBean` 有什么关系？

回答：

### 11. BeanPostProcessor 和 BeanFactoryPostProcessor 有什么区别？

回答：

#### 追问 1：它们分别在什么时候执行？

回答：

#### 追问 2：为什么 `BeanPostProcessor` 能影响 AOP 代理创建？

回答：

#### 追问 3：`BeanFactoryPostProcessor` 可以修改什么？

回答：

### 12. 什么是 AOP？ **【重点】**

回答：

#### 追问 1：为什么需要 AOP？

回答：

#### 追问 2：实际开发中 AOP 常用来做什么？

回答：

#### 追问 3：AOP 和 OOP 是什么关系？

回答：

### 13. AOP 中的连接点、切点、通知、切面分别是什么？ **【重点】**

回答：

#### 追问 1：什么是目标对象和代理对象？

回答：

#### 追问 2：通知有哪些类型？

回答：

#### 追问 3：什么是织入？

回答：

### 14. JDK 动态代理和 CGLIB 有什么区别？ **【重点】**

回答：

#### 追问 1：什么情况下使用 JDK 动态代理？

回答：

#### 追问 2：什么情况下使用 CGLIB？

回答：

#### 追问 3：为什么 `final` 类或 `final` 方法会影响 CGLIB？

回答：

### 15. Spring AOP、AspectJ、CGLIB 有什么关系？ **【重点】**

回答：

#### 追问 1：Spring AOP 和 AspectJ 的能力有什么区别？

回答：

#### 追问 2：AspectJ 的切入点表达式常见写法是什么？

回答：

#### 追问 3：CGLIB 是 AOP 吗？

回答：

### 16. 为什么 Spring AOP 自调用会失效？ **【重点】**

回答：

#### 追问 1：什么叫没有经过代理对象？

回答：

#### 追问 2：自调用失效会影响哪些功能？

回答：

#### 追问 3：如何解决自调用导致的 AOP 或事务失效？

回答：

### 17. Spring 如何解决循环依赖？ **【重点】**

回答：

#### 追问 1：什么是循环依赖？

回答：

#### 追问 2：Spring 能解决所有循环依赖吗？

回答：

#### 追问 3：构造器注入循环依赖为什么通常解决不了？

回答：

### 18. Spring 三级缓存分别是什么？ **【重点】**

回答：

#### 追问 1：一级缓存、二级缓存、三级缓存分别存什么？

回答：

#### 追问 2：什么是提前暴露对象？

回答：

#### 追问 3：为什么需要三级缓存，而不是只用二级缓存？

回答：

#### 追问 4：循环依赖遇到 AOP 代理时有什么特殊点？

回答：

### 19. 你能手写一个简单的三级缓存解决循环依赖思路吗？

回答：

#### 追问 1：简化版流程里需要哪些 Map？

回答：

#### 追问 2：什么时候放入三级缓存？

回答：

#### 追问 3：什么时候从二级缓存拿提前暴露对象？

回答：

### 20. Spring 事务是怎么实现的？ **【重点】**

回答：

#### 追问 1：为什么声明式事务依赖 AOP？

回答：

#### 追问 2：事务增强逻辑大概在方法调用前后做了什么？

回答：

#### 追问 3：编程式事务和声明式事务有什么区别？

回答：

### 21. Spring 事务三要素是什么？ **【重点】**

回答：

#### 追问 1：`PlatformTransactionManager` 负责什么？

回答：

#### 追问 2：`TransactionDefinition` 里定义了哪些事务属性？

回答：

#### 追问 3：`TransactionStatus` 表示什么？

回答：

### 22. Spring 事务传播行为是什么？ **【重点】**

回答：

#### 追问 1：`REQUIRED` 和 `REQUIRES_NEW` 有什么区别？

回答：

#### 追问 2：`NESTED` 和 `REQUIRES_NEW` 有什么区别？

回答：

#### 追问 3：内层事务回滚一定会影响外层事务吗？

回答：

### 23. Spring 事务隔离级别是什么？

回答：

#### 追问 1：Spring 的事务隔离级别和数据库隔离级别是什么关系？

回答：

#### 追问 2：`DEFAULT` 表示什么？

回答：

#### 追问 3：不同隔离级别分别解决哪些并发问题？

回答：

### 24. `@Transactional` 默认什么时候回滚？ **【重点】**

回答：

#### 追问 1：默认会回滚受检异常吗？

回答：

#### 追问 2：如何配置指定异常回滚？

回答：

#### 追问 3：异常被 catch 之后为什么可能不回滚？

回答：

### 25. `@Transactional` 常见失效场景有哪些？ **【重点】**

回答：

#### 追问 1：为什么自调用会导致事务失效？

回答：

#### 追问 2：为什么 `private` 方法上的 `@Transactional` 通常不生效？

回答：

#### 追问 3：为什么方法不是 `public` 可能导致事务不生效？

回答：

#### 追问 4：为什么数据库表不支持事务时注解也没用？

回答：

### 26. Spring 常用注解有哪些？ **【重点】**

回答：

#### 追问 1：组件注册类注解有哪些？

回答：

#### 追问 2：依赖注入类注解有哪些？

回答：

#### 追问 3：配置类相关注解有哪些？

回答：

#### 追问 4：事务相关注解有哪些？

回答：

### 27. `@Autowired` 和 `@Resource` 有什么区别？ **【重点】**

回答：

#### 追问 1：`@Autowired` 默认按类型还是按名称注入？

回答：

#### 追问 2：`@Qualifier` 有什么作用？

回答：

#### 追问 3：多个同类型 Bean 时怎么指定注入哪个？

回答：

### 28. `@Component`、`@Service`、`@Repository`、`@Controller` 有什么区别？

回答：

#### 追问 1：它们本质上有什么共同点？

回答：

#### 追问 2：`@Repository` 额外有什么语义？

回答：

#### 追问 3：为什么要分成不同注解，而不是都用 `@Component`？

回答：

### 29. `@Configuration` 和 `@Bean` 是什么？ **【重点】**

回答：

#### 追问 1：`@Configuration` 和普通 `@Component` 有什么区别？

回答：

#### 追问 2：`@Bean` 方法之间互相调用会发生什么？

回答：

#### 追问 3：什么是 full 模式和 lite 模式？

回答：

### 30. `@Value` 和 `@ConfigurationProperties` 有什么区别？

回答：

#### 追问 1：什么时候适合用 `@Value`？

回答：

#### 追问 2：什么时候适合用 `@ConfigurationProperties`？

回答：

#### 追问 3：配置属性绑定失败通常怎么排查？

回答：

### 31. Spring MVC 请求处理流程是什么？ **【重点】**

回答：

#### 追问 1：`DispatcherServlet` 的作用是什么？

回答：

#### 追问 2：`HandlerMapping` 和 `HandlerAdapter` 分别做什么？

回答：

#### 追问 3：Controller 方法执行前后经过哪些关键组件？

回答：

#### 追问 4：返回 JSON 时还会经过视图解析器吗？

回答：

### 32. `@RequestMapping` 和 `@RequestParam` 有什么区别？

回答：

#### 追问 1：`@GetMapping`、`@PostMapping` 和 `@RequestMapping` 有什么关系？

回答：

#### 追问 2：`@RequestParam`、`@PathVariable`、`@RequestBody` 分别用于什么场景？

回答：

#### 追问 3：后台如何接收前端传来的 JSON 数据？

回答：

### 33. `@RequestBody` 和 `@ResponseBody` 的底层是什么？ **【重点】**

回答：

#### 追问 1：它们和 `HttpMessageConverter` 有什么关系？

回答：

#### 追问 2：为什么能把 JSON 转成 Java 对象？

回答：

#### 追问 3：`@RestController` 和 `@Controller` + `@ResponseBody` 有什么关系？

回答：

### 34. Spring MVC 全局异常处理怎么做？

回答：

#### 追问 1：`@ControllerAdvice` 是什么？

回答：

#### 追问 2：`@ExceptionHandler` 是什么？

回答：

#### 追问 3：全局异常处理适合处理哪些异常？

回答：

### 35. Spring MVC 拦截器和过滤器有什么区别？ **【重点】**

回答：

#### 追问 1：Filter 属于 Servlet 规范还是 Spring MVC？

回答：

#### 追问 2：Interceptor 在 Spring MVC 流程中的位置是什么？

回答：

#### 追问 3：登录校验更适合放在过滤器还是拦截器？

回答：

### 36. Spring Boot 是什么？ **【重点】**

回答：

#### 追问 1：Spring Boot 和 Spring Framework 是什么关系？

回答：

#### 追问 2：Spring Boot 主要解决了哪些开发痛点？

回答：

#### 追问 3：什么是“约定大于配置”？

回答：

### 37. Spring Boot 自动配置原理是什么？ **【重点】**

回答：

#### 追问 1：`@SpringBootApplication` 包含哪些核心注解？

回答：

#### 追问 2：自动配置类是如何被加载的？

回答：

#### 追问 3：为什么引入 starter 后很多 Bean 会自动生效？

回答：

#### 追问 4：Spring Boot 2 和 Spring Boot 3 自动配置加载文件有什么变化？

回答：

### 38. Spring Boot starter 是什么？ **【重点】**

回答：

#### 追问 1：starter 主要解决什么问题？

回答：

#### 追问 2：starter 和自动配置类是什么关系？

回答：

#### 追问 3：为什么 starter 通常只做依赖聚合和自动配置入口？

回答：

### 39. 如何自定义一个 Spring Boot starter？ **【重点】**

回答：

#### 追问 1：自定义 starter 通常需要哪些模块或文件？

回答：

#### 追问 2：如何让自动配置类被 Spring Boot 扫描到？

回答：

#### 追问 3：如何通过配置属性控制 starter 行为？

回答：

### 40. Spring Boot 条件装配是什么？ **【重点】**

回答：

#### 追问 1：`@ConditionalOnClass` 有什么作用？

回答：

#### 追问 2：`@ConditionalOnMissingBean` 有什么作用？

回答：

#### 追问 3：为什么条件装配能避免和用户自定义 Bean 冲突？

回答：

### 41. Spring Boot 常用注解有哪些？

回答：

#### 追问 1：启动类上常见注解有哪些？

回答：

#### 追问 2：配置属性绑定相关注解有哪些？

回答：

#### 追问 3：条件装配相关注解有哪些？

回答：

### 42. Spring Boot 的 SPI / 自动配置加载机制是什么？

回答：

#### 追问 1：`SpringFactoriesLoader` 是什么？

回答：

#### 追问 2：`AutoConfiguration.imports` 是什么？

回答：

#### 追问 3：Java SPI 和 Spring Boot 自动配置加载有什么区别？

回答：

### 43. 什么是 Spring 模式注解？

回答：

#### 追问 1：`@Component` 为什么是典型的模式注解？

回答：

#### 追问 2：组合注解是什么？

回答：

#### 追问 3：`@SpringBootApplication` 为什么可以看成组合注解？

回答：

### 44. Spring 中用到了哪些设计模式？ **【重点】**

回答：

#### 追问 1：Spring 中哪里用到了工厂模式？

回答：

#### 追问 2：Spring 中哪里用到了代理模式？

回答：

#### 追问 3：Spring 中哪里用到了模板方法或模板回调？

回答：

#### 追问 4：Spring 中哪里用到了观察者模式？

回答：

### 45. Spring 开发中常见错误有哪些？

回答：

#### 追问 1：Bean 注入失败常见原因有哪些？

回答：

#### 追问 2：AOP 不生效常见原因有哪些？

回答：

#### 追问 3：事务不生效常见原因有哪些？

回答：

#### 追问 4：Spring Boot 自动配置不生效常见原因有哪些？

回答：

## 五、Bean 源码学习总结 **【重点】**

> 这一部分是 Bean 第一阶段源码学习总结。重点不是背源码每一行，而是能把 **BeanDefinition -> 注册 -> getBean -> 创建 Bean -> 生命周期 -> 循环依赖 -> 扩展点** 这条线讲清楚。

### 1. Bean 学习主线

Bean 这一块可以按下面这条线理解：

```text
解析配置 / 扫描类
 -> 生成 BeanDefinition
 -> 注册到 BeanFactory
 -> getBean
 -> 查单例池
 -> 获取 BeanDefinition
 -> createBean
 -> doCreateBean
 -> 实例化
 -> 属性填充
 -> 初始化
 -> 放入单例池
 -> 使用
 -> 销毁
```

一句话总结：

```text
Spring 不是直接 new 对象，而是先把 Bean 的定义信息保存起来，之后根据这些定义信息创建、注入、初始化和管理 Bean。
```

### 2. `BeanDefinition` 是什么？

`BeanDefinition` 中文可以理解为：**Bean 定义信息 / Bean 元数据 / Bean 图纸**。

它不是 Bean 实例，而是 Spring 创建 Bean 之前保存的一份描述信息。

`BeanDefinition` 中通常保存：

- Bean 对应的 class 信息。
- 作用域，比如 `singleton`、`prototype`。
- 是否懒加载。
- 构造参数。
- 属性依赖。
- 初始化方法。
- 销毁方法。

面试回答：

```text
BeanDefinition 是 Spring 对 Bean 的定义信息，可以理解为 Bean 的图纸。

Spring 在处理 @Component、@Service、@Bean、XML 等配置时，不会一开始就直接创建 Bean，而是先解析成 BeanDefinition，并注册到 BeanFactory 中。

后续创建 Bean 时，Spring 会根据 BeanDefinition 中保存的 class、作用域、构造参数、属性依赖、初始化方法等信息来完成 Bean 的创建和生命周期管理。
```

### 3. `BeanDefinition` 如何注册到容器？

`BeanFactory` 中文可以理解为：**Bean 工厂 / Bean 容器**。

核心实现类：

```text
DefaultListableBeanFactory
```

核心方法：

```text
registerBeanDefinition
```

核心容器：

```text
beanDefinitionMap
```

结构可以理解为：

```text
beanName -> BeanDefinition
```

流程：

```text
扫描 classpath 下的 class 元数据
 -> 找到 @Component、@Service、@Controller、@Repository、@Configuration 等组件
 -> 解析成 BeanDefinition
 -> 调用 DefaultListableBeanFactory#registerBeanDefinition
 -> 放入 beanDefinitionMap
```

如果是 `@Bean` 方法：

```text
先解析 @Configuration 配置类
 -> 找到 @Bean 方法
 -> 生成 BeanDefinition
 -> 注册到 beanDefinitionMap
```

注意：Spring 运行时扫描的是编译后的 `.class` 元数据，不是 `.java` 源文件。

### 4. `getBean()` 创建 Bean 的大致流程

`getBean` 中文可以理解为：**获取 Bean**。

核心源码入口：

```text
AbstractBeanFactory#getBean
AbstractBeanFactory#doGetBean
AbstractAutowireCapableBeanFactory#createBean
AbstractAutowireCapableBeanFactory#doCreateBean
```

主流程：

```text
getBean
 -> doGetBean
 -> 先查 singletonObjects
 -> 获取 BeanDefinition
 -> 根据 scope 判断创建方式
 -> createBean
 -> doCreateBean
 -> 实例化
 -> 属性填充
 -> 初始化
```

`singletonObjects` 中文可以理解为：**单例对象缓存 / 一级缓存**。

如果是单例 Bean：

```text
第一次 getBean：创建 Bean，并放入 singletonObjects。
后续 getBean：直接从 singletonObjects 返回。
```

如果是 prototype Bean：

```text
每次 getBean 都会创建新的 Bean。
```

一句话总结：

```text
getBean 不是简单 new 对象，而是先查缓存，再找 BeanDefinition，再根据作用域进入 Bean 创建流程。
```

### 5. Bean 生命周期源码主流程

核心源码：

```text
AbstractAutowireCapableBeanFactory#doCreateBean
```

`doCreateBean` 可以理解为：**真正创建 Bean 的主流程**。

核心三步：

```text
createBeanInstance -> populateBean -> initializeBean
```

中文含义：

```text
createBeanInstance：创建 Bean 实例，也就是实例化。
populateBean：填充 Bean 属性，也就是依赖注入。
initializeBean：初始化 Bean。
```

更完整的生命周期：

```text
实例化
 -> 属性填充 / 依赖注入
 -> Aware 回调
 -> BeanPostProcessor 前置处理
 -> 初始化方法
 -> BeanPostProcessor 后置处理
 -> 使用
 -> 销毁
```

当前入门 Demo 中先只看这条线：

```text
构造方法
 -> setter 注入
 -> @PostConstruct
 -> 使用 Bean
 -> @PreDestroy
```

对应关系：

```text
构造方法：实例化，对应 createBeanInstance。
setter 注入：属性填充，对应 populateBean。
@PostConstruct：初始化，对应 initializeBean 过程中的扩展处理。
@PreDestroy：销毁，对应容器关闭时的销毁回调。
```

### 6. Spring 如何解决循环依赖？

Spring 主要解决的是：

```text
单例 Bean 的 setter / 字段注入循环依赖
```

不能很好解决的是：

```text
构造器循环依赖
```

原因：

```text
三级缓存解决循环依赖的前提是 Bean 已经完成实例化，可以提前暴露一个半成品对象。

setter / 字段注入是先实例化，再注入属性，所以可以提前暴露。

构造器注入是在实例化阶段就必须拿到依赖对象，如果 A 构造器需要 B，B 构造器又需要 A，双方都无法先完成实例化，也就没有半成品 Bean 可以提前暴露。
```

### 7. 三级缓存分别是什么？

三级缓存源码位置：

```text
DefaultSingletonBeanRegistry
```

三个核心 Map：

```text
singletonObjects
earlySingletonObjects
singletonFactories
```

中文理解：

```text
singletonObjects：一级缓存，存完整创建好的单例 Bean。
earlySingletonObjects：二级缓存，存提前暴露出来的半成品 Bean。
singletonFactories：三级缓存，存 ObjectFactory，用来生成提前暴露对象。
```

`ObjectFactory` 中文可以理解为：**对象工厂**。

循环依赖大致流程：

```text
1. 创建 A。
2. A 完成实例化，但还没有完成属性填充和初始化。
3. Spring 把 A 的 ObjectFactory 放入三级缓存 singletonFactories。
4. A 属性填充时发现需要 B，于是开始创建 B。
5. B 属性填充时发现需要 A。
6. Spring 先查一级缓存 singletonObjects，没有。
7. 再查二级缓存 earlySingletonObjects，没有。
8. 再查三级缓存 singletonFactories，拿到 A 的 ObjectFactory。
9. 通过 ObjectFactory 获取提前暴露的 A，并放入二级缓存。
10. B 注入 A，B 创建完成。
11. 回到 A，A 注入 B。
12. A 创建完成后，放入一级缓存 singletonObjects。
```

注意：

```text
提前暴露的不是“未实例化对象”，而是“已经实例化，但还没有完成属性填充和初始化的半成品对象”。
```

### 8. 为什么需要三级缓存，而不是二级缓存？

如果不考虑 AOP，一级缓存 + 二级缓存理论上也能解决普通 setter / 字段注入循环依赖。

但 Spring 还要考虑：

```text
循环依赖 + AOP 代理对象一致性
```

`AOP` 中文可以理解为：**面向切面编程**。它常通过代理对象给方法增加事务、日志、权限等增强逻辑。

问题是：

```text
如果 B 注入 A 时拿到的是原始 A，而容器最终保存的是 A 的代理对象，那么 B 里面引用的对象和容器中的最终对象就不一致，可能导致 AOP 增强失效。
```

三级缓存中存的是 `ObjectFactory`，可以延迟决定提前暴露什么对象：

```text
可能是原始对象，也可能是代理对象。
```

面试回答：

```text
三级缓存的核心不是简单多一层 Map，而是为了延迟生成提前暴露对象，并处理 AOP 代理对象的一致性问题。
```

### 9. Bean 作用域

`scope` 中文可以理解为：**作用域 / 生效范围**。

常见作用域：

```text
singleton：单例，默认作用域。同一个 Spring 容器中，同一个 beanName 只创建一个 Bean 实例。
prototype：原型 / 多例。每次从容器中获取 Bean 时都会创建一个新的 Bean 实例。
request：Web 环境中，每次 HTTP 请求创建一个 Bean。
session：Web 环境中，同一个 HTTP Session 共享一个 Bean。
```

注意：

```text
prototype 不是“每个使用它的对象里都会自动创建新 Bean”。

如果 prototype Bean 被注入到 singleton Bean 中，默认只会在 singleton Bean 创建时注入一次。
```

### 10. 单例 Bean 是线程安全的吗？

结论：

```text
Spring 单例 Bean 本身不保证线程安全，但也不一定线程不安全。
```

关键看 Bean 内部有没有：

```text
共享可变状态
```

如果 Bean 是无状态的：

```text
通常线程安全。
```

如果 Bean 中有可变成员变量，并且被多个线程同时读写：

```text
可能出现线程安全问题。
```

面试回答：

```text
Spring 的 singleton 只表示同一个容器中同一个 Bean 只有一个实例，不等于线程安全。

单例 Bean 是否线程安全，取决于它内部有没有共享可变状态。无状态 Bean 通常是线程安全的；如果有成员变量保存用户请求数据、临时计算结果等，就可能被多个线程同时访问，产生线程安全问题。

所以实际开发中应尽量让 Controller、Service 这类单例 Bean 保持无状态。
```

### 11. `BeanFactory` 和 `ApplicationContext` 有什么区别？

`BeanFactory` 中文可以理解为：**Bean 工厂 / 基础 IoC 容器**。

`ApplicationContext` 中文可以理解为：**应用上下文 / 更完整的 Spring 容器**。

区别：

```text
BeanFactory 是 Spring 最基础的 IoC 容器接口，提供 Bean 的创建、获取和管理能力，核心方法是 getBean。

ApplicationContext 继承了 BeanFactory，是更完整的应用上下文。它除了具备 BeanFactory 的 Bean 管理能力，还扩展了国际化、事件发布、资源加载、环境配置、自动注册后置处理器等功能。
```

创建时机区别：

```text
BeanFactory 通常在调用 getBean 时才创建 Bean，偏懒加载。

ApplicationContext 在容器启动时，默认会提前创建所有非懒加载的 singleton Bean。
```

注意：

```text
ApplicationContext 是 BeanFactory 的子接口或扩展接口，不是子类。
```

### 12. `FactoryBean` 和 `BeanFactory` 有什么区别？

`FactoryBean` 中文可以理解为：**工厂 Bean / 用来生产对象的特殊 Bean**。

区别：

```text
BeanFactory 是容器，负责创建、获取和管理 Bean。

FactoryBean 是一个特殊 Bean，用来定制复杂对象的创建逻辑。
```

`FactoryBean` 核心方法：

```text
getObject：返回真正暴露给容器使用的对象。
getObjectType：返回对象类型。
isSingleton：返回 FactoryBean 生产的对象是否是单例。
```

获取规则：

```text
getBean("xxx")：默认拿到 FactoryBean#getObject() 返回的对象。
getBean("&xxx")：拿到 FactoryBean 本身。
```

典型场景：

```text
MyBatis 的 MapperFactoryBean。

Mapper 接口没有实现类，但可以被注入，是因为 MapperFactoryBean 会为 Mapper 接口生成代理对象。
```

### 13. `BeanPostProcessor` 是什么？

`BeanPostProcessor` 中文可以理解为：**Bean 后置处理器**。

它是 Spring Bean 生命周期中的扩展点，本身也是一种特殊 Bean，通常会比普通 Bean 更早创建和注册。

两个核心方法：

```text
postProcessBeforeInitialization：初始化前处理。
postProcessAfterInitialization：初始化后处理。
```

在生命周期中的位置：

```text
实例化
 -> 属性填充
 -> Aware 回调
 -> BeanPostProcessor 前置处理
 -> 初始化方法
 -> BeanPostProcessor 后置处理
 -> 使用
```

源码位置：

```text
AbstractAutowireCapableBeanFactory#initializeBean
```

典型作用：

```text
@PostConstruct 通常由 CommonAnnotationBeanPostProcessor 处理。
AOP 代理通常由 AbstractAutoProxyCreator 在初始化后的后置处理阶段创建。
```

### 14. `@Autowired` 注入过程

`@Autowired` 中文可以理解为：**自动装配 / 自动注入**。

它的本质：

```text
Spring 在 Bean 的属性填充阶段，找到依赖 Bean，并注入到当前 Bean 中。
```

源码阶段：

```text
populateBean
```

核心处理器：

```text
AutowiredAnnotationBeanPostProcessor
```

`AutowiredAnnotationBeanPostProcessor` 中文可以理解为：**Autowired 注解处理器**。

注入规则：

```text
默认按类型查找 Bean。
如果只找到一个候选 Bean，就直接注入。
如果找到多个同类型 Bean，会再按字段名或参数名按名称匹配。
如果仍然无法确定，就会报错。
```

解决多个同类型 Bean 的方式：

```text
@Qualifier：限定符，用来指定具体注入哪个 Bean。
@Primary：主要的 / 优先的 Bean，用来指定默认优先注入对象。
```

支持的注入方式：

```text
构造器注入
字段注入
setter 注入
```

注意：

```text
构造器注入发生在实例化阶段，因为创建对象时就必须传入依赖。

字段注入和 setter 注入主要发生在属性填充阶段，也就是 populateBean。
```

面试回答：

```text
@Autowired 在 Bean 生命周期的依赖注入阶段生效。Spring 会通过 AutowiredAnnotationBeanPostProcessor 解析 Bean 中标注了 @Autowired 的字段、构造器或 setter 方法，然后去容器中查找对应的依赖 Bean，并完成注入。

@Autowired 默认按类型查找 Bean。如果有多个同类型 Bean，会再按名称匹配，也可以使用 @Qualifier 指定 Bean，或者使用 @Primary 指定优先注入的 Bean。
```

### 15. Bean 第一阶段总结

Bean 这一阶段需要能说清楚：

```text
1. BeanDefinition 是 Bean 的定义信息，不是 Bean 实例。
2. BeanDefinition 会注册到 DefaultListableBeanFactory 的 beanDefinitionMap 中。
3. getBean 会先查 singletonObjects，再根据 BeanDefinition 创建 Bean。
4. doCreateBean 的核心流程是 createBeanInstance、populateBean、initializeBean。
5. Spring 通过三级缓存解决单例 Bean 的 setter / 字段注入循环依赖。
6. 构造器循环依赖通常解决不了，因为没有半成品对象可以提前暴露。
7. 三级缓存的关键是 ObjectFactory，它可以处理提前暴露对象和 AOP 代理对象一致性问题。
8. singleton 不等于线程安全，是否安全取决于 Bean 是否有共享可变状态。
9. BeanFactory 是基础容器，ApplicationContext 是更完整的应用上下文。
10. FactoryBean 是特殊 Bean，用来生产复杂对象。
11. BeanPostProcessor 是初始化前后的扩展点，@PostConstruct 和 AOP 都和它有关。
12. @Autowired 本质是在依赖注入阶段查找 Bean 并注入。
```

## 六、MyBatis 扩展题

> 这部分来自截图末尾，但不属于当前 Spring 主线。可以等 Spring 主体复习完之后再学。

### 46. MyBatis 执行流程是什么？

回答：

#### 追问 1：`SqlSession` 的作用是什么？

回答：

#### 追问 2：Mapper 接口为什么不需要实现类？

回答：

#### 追问 3：MyBatis 如何把查询结果映射成对象？

回答：

### 47. MyBatis 一级缓存和二级缓存是什么？

回答：

#### 追问 1：一级缓存的作用域是什么？

回答：

#### 追问 2：二级缓存的作用域是什么？

回答：

#### 追问 3：为什么 MyBatis 二级缓存实际项目中要谨慎使用？

回答：

### 48. MyBatis 如何防止 SQL 注入？

回答：

#### 追问 1：`#{}` 和 `${}` 有什么区别？

回答：

#### 追问 2：哪些场景容易误用 `${}`？

回答：

#### 追问 3：动态 SQL 会不会带来 SQL 注入风险？

回答：

## 七、待自查易错方向

> 这里只列检查方向，不写答案。你写完后，我会按这些点帮你抓错。

- Spring 是生态和框架，不要只说“Spring 是 IOC 和 AOP”。
- IoC 是思想，DI 是实现方式之一。
- BeanDefinition 不是 Bean 实例。
- BeanFactory 是容器底层接口，ApplicationContext 是更完整的应用上下文。
- 实例化、属性填充、初始化不是同一步。
- 单例 Bean 不等于线程安全，关键看是否有共享可变状态。
- Spring 只能解决部分循环依赖，主要是单例 Bean 的 setter / 字段注入循环依赖。
- 三级缓存的核心不是“多一层 Map”，而是为了提前暴露对象工厂，处理代理对象一致性问题。
- AOP 基于代理时，自调用会绕过代理。
- JDK 动态代理基于接口，CGLIB 基于继承生成子类。
- `@Transactional` 默认只回滚 `RuntimeException` 和 `Error`。
- 事务是否生效要看调用是否经过 Spring 代理对象。
- 异常被 catch 后没有继续抛出，事务管理器可能感知不到异常。
- `private` 方法、`final` 方法、同类内部调用都可能导致代理增强失效。
- Spring MVC 的核心入口是 `DispatcherServlet`。
- `@RequestBody` / `@ResponseBody` 的核心和 `HttpMessageConverter` 有关。
- Filter 属于 Servlet 规范，Interceptor 属于 Spring MVC。
- Spring Boot 自动配置本质是条件满足时自动注册 Bean。
- starter 不是魔法，主要是依赖聚合 + 自动配置入口。
- Spring Boot 3 的自动配置加载文件和 Spring Boot 2 有差异。

## 八、20 题自测

1. Spring 主要解决了什么问题？
2. IoC 和 DI 分别是什么？
3. BeanFactory 和 ApplicationContext 有什么区别？
4. BeanDefinition 和 Bean 实例有什么区别？
5. Bean 的生命周期完整流程是什么？
6. Spring 单例 Bean 是线程安全的吗？
7. Spring 如何解决 setter 循环依赖？
8. 三级缓存分别存什么，为什么需要第三级缓存？
9. AOP 中连接点、切点、通知、切面分别是什么？
10. JDK 动态代理和 CGLIB 有什么区别？
11. Spring AOP、AspectJ、CGLIB 分别是什么关系？
12. 为什么自调用会导致 AOP 或事务失效？
13. Spring 声明式事务是怎么实现的？
14. `REQUIRED` 和 `REQUIRES_NEW` 有什么区别？
15. `@Transactional` 默认什么异常会回滚？
16. `@Transactional` 有哪些常见失效场景？
17. Spring 常用注解可以分成哪几类？
18. Spring MVC 请求处理流程是什么？
19. Spring Boot 自动配置原理是什么？
20. 自定义 starter 大致需要哪些步骤？
