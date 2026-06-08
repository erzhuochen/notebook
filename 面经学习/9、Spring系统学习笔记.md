# 9、Spring 系统学习笔记

> 使用方式：你先在主问题和追问的“回答”里写答案，我检查后会直接替换成更精确的版本。当前阶段以**学习理解**为主，不追求面试精简；回答会尽量包含**原理解释、具体例子、最后再总结关键词**。需要强调的关键词直接在原文中加粗。

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

回答：

#### 追问 1：IoC 和 DI 有什么关系？

回答：

#### 追问 2：为什么把对象创建交给容器能降低耦合？

回答：

#### 追问 3：Spring 容器除了创建对象还做了什么？

回答：

### 2. BeanFactory 和 ApplicationContext 有什么区别？

回答：

#### 追问 1：BeanFactory 为什么更偏底层？

回答：

#### 追问 2：ApplicationContext 扩展了哪些能力？

回答：

#### 追问 3：单例 Bean 通常什么时候创建？

回答：

### 3. BeanDefinition 是什么？

回答：

#### 追问 1：BeanDefinition 里通常保存哪些信息？

回答：

#### 追问 2：Spring 为什么不直接用 Class 创建 Bean？

回答：

#### 追问 3：BeanDefinition 和 Bean 实例有什么区别？

回答：

### 4. Spring Bean 生命周期是什么？

回答：

#### 追问 1：实例化和初始化有什么区别？

回答：

#### 追问 2：BeanPostProcessor 有什么作用？

回答：

#### 追问 3：AOP 代理通常在哪个阶段创建？

回答：

### 5. Spring 如何解决循环依赖？

回答：

#### 追问 1：Spring 能解决所有循环依赖吗？

回答：

#### 追问 2：三级缓存分别存什么？

回答：

#### 追问 3：为什么需要第三级缓存？

回答：

### 6. 什么是 AOP？

回答：

#### 追问 1：连接点、切点、通知、切面分别是什么？

回答：

#### 追问 2：JDK 动态代理和 CGLIB 有什么区别？

回答：

#### 追问 3：为什么自调用可能导致 AOP 失效？

回答：

### 7. Spring 事务是如何实现的？

回答：

#### 追问 1：为什么 Spring 声明式事务依赖 AOP？

回答：

#### 追问 2：PlatformTransactionManager 做什么？

回答：

#### 追问 3：默认什么异常会触发事务回滚？

回答：

### 8. Spring 事务传播行为是什么？

回答：

#### 追问 1：REQUIRED 和 REQUIRES_NEW 有什么区别？

回答：

#### 追问 2：NESTED 和 REQUIRES_NEW 有什么区别？

回答：

#### 追问 3：内层事务回滚一定会影响外层事务吗？

回答：

### 9. @Transactional 常见失效场景有哪些？

回答：

#### 追问 1：为什么自调用会导致事务失效？

回答：

#### 追问 2：异常被 catch 后为什么可能不回滚？

回答：

#### 追问 3：private 方法加 @Transactional 有用吗？

回答：

### 10. Spring MVC 请求处理流程是什么？

回答：

#### 追问 1：DispatcherServlet 的作用是什么？

回答：

#### 追问 2：HandlerMapping 和 HandlerAdapter 分别做什么？

回答：

#### 追问 3：@RequestBody 和 @ResponseBody 的底层和消息转换器有什么关系？

回答：

### 11. Spring Boot 自动配置原理是什么？

回答：

#### 追问 1：starter 主要解决什么问题？

回答：

#### 追问 2：条件装配是什么？

回答：

#### 追问 3：@ConditionalOnMissingBean 有什么作用？

回答：

## 五、待自查易错方向

> 这里只列检查方向，不写答案。你写完后，我会按这些点帮你抓错，并直接把回答替换成更精确的学习版。

- IoC 是思想，DI 是实现方式之一
- BeanDefinition 不是 Bean 实例
- 实例化和初始化不是同一步
- Spring 只能解决部分循环依赖
- AOP 基于代理时，自调用会绕过代理
- @Transactional 默认只回滚 RuntimeException 和 Error
- 事务是否生效要看是否经过代理对象
- Spring MVC 的核心调度入口是 DispatcherServlet
- Spring Boot 自动配置本质是条件满足时注册 Bean

## 六、10 题自测

1. IoC 和 DI 分别是什么？
2. BeanFactory 和 ApplicationContext 有什么区别？
3. BeanDefinition 和 Bean 实例有什么区别？
4. Bean 生命周期完整流程是什么？
5. Spring 如何解决 setter 循环依赖？
6. JDK 动态代理和 CGLIB 有什么区别？
7. Spring 事务为什么依赖 AOP？
8. @Transactional 有哪些失效场景？
9. Spring MVC 请求处理流程是什么？
10. Spring Boot 自动配置的核心机制是什么？

