# 9、Spring 系统学习笔记

## 一、学习目标

学完 Spring 后，要能讲清楚四条主线：

1. Spring 容器如何创建和管理 Bean。
2. AOP 如何在不改业务代码的情况下增强方法。
3. Spring 事务如何生效，为什么会失效。
4. Spring MVC 和 Spring Boot 的核心流程是什么。

## 二、一周学习路线

| 天数 | 主题 | 必须掌握的问题 |
| --- | --- | --- |
| Day 8 | IoC 容器 | BeanDefinition、BeanFactory、ApplicationContext |
| Day 9 | Bean 生命周期 | 实例化、属性填充、初始化、销毁 |
| Day 10 | 循环依赖 | 三级缓存、提前暴露、AOP 影响 |
| Day 11 | AOP | JDK 动态代理、CGLIB、通知、调用链 |
| Day 12 | Spring 事务 | 传播行为、隔离级别、失效场景 |
| Day 13 | Spring MVC | DispatcherServlet、HandlerMapping、HandlerAdapter |
| Day 14 | Spring Boot 自动配置 | starter、自动配置类、条件装配 |

## 三、知识树

### 1. IoC 容器

- IoC 和 DI
- BeanDefinition
- BeanFactory
- ApplicationContext
- BeanPostProcessor
- FactoryBean

### 2. Bean 生命周期

- 实例化
- 属性填充
- Aware 回调
- BeanPostProcessor 前置处理
- 初始化
- BeanPostProcessor 后置处理
- 使用
- 销毁

### 3. 循环依赖

- 构造器循环依赖
- setter 循环依赖
- 三级缓存
- 提前暴露对象
- AOP 代理对象

### 4. AOP

- 切面
- 切点
- 通知
- 连接点
- 目标对象
- 代理对象
- JDK 动态代理
- CGLIB

### 5. Spring 事务

- 声明式事务
- PlatformTransactionManager
- 传播行为
- 隔离级别
- 回滚规则
- 事务失效场景

### 6. Spring MVC

- DispatcherServlet
- HandlerMapping
- HandlerAdapter
- 参数解析
- 返回值处理
- 消息转换器
- 异常处理

### 7. Spring Boot 自动配置

- starter
- 自动配置类
- 条件装配
- 配置属性绑定
- 约定大于配置

## 四、高频面试题

### 1. 什么是 IoC？

简答版：
IoC 是控制反转，把对象创建和依赖管理的控制权从程序代码交给 Spring 容器。

展开版：
传统写法中，对象通常自己 new 依赖对象。使用 Spring 后，对象由容器创建，依赖也由容器注入。这样可以降低对象之间的耦合，让配置、生命周期、增强能力都交给容器统一管理。

常见追问：
- IoC 和 DI 有什么关系？
- BeanFactory 和 ApplicationContext 有什么区别？
- Spring 为什么能管理对象生命周期？

### 2. BeanFactory 和 ApplicationContext 有什么区别？

简答版：
BeanFactory 是 Spring 最基础的容器接口，提供 Bean 创建和获取能力；ApplicationContext 是更完整的应用上下文，扩展了事件、国际化、资源加载等能力。

展开版：
BeanFactory 偏底层，强调 Bean 管理能力。ApplicationContext 继承并扩展 BeanFactory，实际开发中更常用。它通常会在启动时完成单例 Bean 的创建，还支持环境配置、事件发布、AOP 自动代理等能力。

常见追问：
- BeanFactory 是懒加载吗？
- ApplicationContext 启动时做了什么？
- BeanDefinition 是什么？

### 3. Spring Bean 生命周期是什么？

简答版：
Bean 生命周期大致包括实例化、属性填充、Aware 回调、初始化前置处理、初始化、初始化后置处理、使用、销毁。

展开版：
Spring 先根据 BeanDefinition 创建对象，然后进行依赖注入。接着执行各种 Aware 接口回调，再经过 BeanPostProcessor 前置处理，执行初始化方法，然后经过后置处理，最后 Bean 可以被使用。容器关闭时，会执行销毁回调。

常见追问：
- BeanPostProcessor 有什么作用？
- InitializingBean 和 init-method 有什么区别？
- AOP 代理通常在哪个阶段创建？

### 4. Spring 如何解决循环依赖？

简答版：
Spring 主要通过三级缓存解决单例 Bean 的 setter 循环依赖，本质是提前暴露尚未完全初始化的 Bean。

展开版：
Spring 创建单例 Bean 时，会先实例化对象，再填充属性。对于 setter 循环依赖，A 创建后可以提前暴露引用，B 注入 A 时可以从缓存中拿到这个早期引用。三级缓存还可以处理 AOP 场景，确保最终注入的是代理对象而不是原始对象。

常见追问：
- 构造器循环依赖为什么解决不了？
- 三级缓存分别存什么？
- 为什么需要第三级缓存？

### 5. 什么是 AOP？

简答版：
AOP 是面向切面编程，通过代理在方法执行前后织入增强逻辑，比如事务、日志、权限校验。

展开版：
AOP 把通用逻辑从业务代码中抽离出来，通过切点匹配目标方法，再用通知定义增强行为。Spring AOP 主要基于动态代理实现：有接口时通常用 JDK 动态代理，没有接口时使用 CGLIB。

常见追问：
- JDK 动态代理和 CGLIB 有什么区别？
- Spring AOP 和 AspectJ 有什么区别？
- 自调用为什么可能导致 AOP 失效？

### 6. Spring 事务是如何实现的？

简答版：
Spring 声明式事务主要基于 AOP 和 PlatformTransactionManager。方法调用进入代理对象后，在目标方法前开启事务，方法成功后提交，异常时按规则回滚。

展开版：
@Transactional 被事务拦截器识别后，会根据事务属性获取或创建事务。目标方法正常执行则提交事务；如果抛出符合回滚规则的异常，则回滚事务。底层真正的事务操作由具体 TransactionManager 完成，比如 DataSourceTransactionManager。

常见追问：
- @Transactional 为什么有时会失效？
- 默认遇到什么异常回滚？
- 事务传播行为有哪些？

### 7. Spring 事务传播行为是什么？

简答版：
传播行为定义一个事务方法调用另一个事务方法时，事务应该如何加入、创建或挂起。

展开版：
最常见的是 REQUIRED，表示有事务就加入，没有就新建。REQUIRES_NEW 表示无论外层有没有事务，都新建一个事务，并挂起外层事务。NESTED 表示嵌套事务，通常依赖保存点。SUPPORTS、NOT_SUPPORTED、MANDATORY、NEVER 是其他边界行为。

常见追问：
- REQUIRED 和 REQUIRES_NEW 有什么区别？
- NESTED 和 REQUIRES_NEW 有什么区别？
- 内层事务回滚会不会影响外层事务？

### 8. @Transactional 常见失效场景有哪些？

简答版：
常见失效包括自调用、方法不是 public、异常被捕获、抛出的异常不符合默认回滚规则、对象没有交给 Spring 管理、数据库引擎不支持事务。

展开版：
Spring 事务基于代理生效，如果同一个类内部方法互相调用，没有经过代理对象，事务增强不会执行。默认只对 RuntimeException 和 Error 回滚，受检异常需要指定 rollbackFor。异常被 catch 后没有继续抛出，事务拦截器也无法感知失败。

常见追问：
- 自调用为什么绕过代理？
- checked exception 默认会回滚吗？
- private 方法加 @Transactional 有用吗？

### 9. Spring MVC 请求处理流程是什么？

简答版：
请求先到 DispatcherServlet，再通过 HandlerMapping 找到处理器，通过 HandlerAdapter 调用 Controller，之后完成参数解析、业务调用、返回值处理和视图或响应体写出。

展开版：
DispatcherServlet 是前端控制器，负责统一调度。HandlerMapping 根据 URL 等信息找到目标 Handler；HandlerAdapter 适配并调用它；参数解析器把请求参数转换为方法参数；返回值处理器把返回对象转换为响应，比如通过 HttpMessageConverter 写成 JSON。

常见追问：
- HandlerMapping 和 HandlerAdapter 分别做什么？
- @RequestBody 和 @ResponseBody 的底层是什么？
- 拦截器和过滤器有什么区别？

### 10. Spring Boot 自动配置原理是什么？

简答版：
Spring Boot 通过 starter 引入依赖，通过自动配置类和条件装配，在满足条件时自动创建默认 Bean。

展开版：
starter 负责依赖整合，自动配置类负责声明默认配置，条件注解决定配置是否生效，比如类路径下存在某个类、容器中缺少某个 Bean、配置项开启等。这样 Spring Boot 可以在少量配置下完成常见框架整合。

常见追问：
- starter 本身做了什么？
- @ConditionalOnMissingBean 有什么用？
- 如何排除某个自动配置？

## 五、易错点

- IoC 是思想，DI 是实现方式之一。
- BeanFactory 是基础容器，ApplicationContext 是更完整的上下文。
- Spring 只能解决部分循环依赖，不能解决所有循环依赖。
- AOP 基于代理时，自调用会绕过代理。
- @Transactional 默认只对 RuntimeException 和 Error 回滚。
- Spring MVC 的核心不是 Controller，而是 DispatcherServlet 统一调度流程。
- Spring Boot 自动配置不是魔法，本质是条件满足时注册 Bean。

## 六、10 题自测

1. IoC 和 DI 分别是什么？
2. BeanFactory 和 ApplicationContext 有什么区别？
3. Bean 生命周期完整流程是什么？
4. Spring 如何解决 setter 循环依赖？
5. 为什么构造器循环依赖解决不了？
6. JDK 动态代理和 CGLIB 有什么区别？
7. Spring 事务为什么依赖 AOP？
8. @Transactional 有哪些失效场景？
9. Spring MVC 请求处理流程是什么？
10. Spring Boot 自动配置的核心机制是什么？

