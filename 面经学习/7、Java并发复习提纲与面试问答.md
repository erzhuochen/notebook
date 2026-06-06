# 7. Java 并发复习提纲与面试问答

使用方式：

- 先看“体系复习提纲”，建立并发主线。
- 再按“面试问答练习”自己写回答。
- 回答区先留空，写完后让我检查。

---

# 一、体系复习提纲

## 1. 学习目标

能围绕“多线程共享数据如何保证正确性和性能”讲清 JMM、volatile、synchronized、CAS、AQS、线程池、ThreadLocal、并发容器和异步编排。

## 2. 核心主线

```text
多线程共享数据
-> 出现原子性、可见性、有序性问题
-> JMM 定义内存可见性规则
-> volatile / synchronized / Lock 解决不同问题
-> CAS 和 AQS 支撑 JUC
-> 线程池管理线程资源
-> ThreadLocal 管理线程隔离变量
-> 并发容器解决集合线程安全问题
-> CompletableFuture 支持异步任务编排
```

## 3. 必会知识点

### 线程基础

- 线程是 CPU 调度的基本单位。
- Java 线程常见状态：NEW、RUNNABLE、BLOCKED、WAITING、TIMED_WAITING、TERMINATED。
- start 会创建新线程，run 只是普通方法调用。

### JMM

- JMM 解决多线程下共享变量的原子性、可见性、有序性问题。
- happens-before 用于判断一个操作的结果是否对另一个操作可见。

### volatile

- 保证可见性。
- 禁止指令重排序。
- 不保证复合操作的原子性。

### synchronized

- 锁的是对象。
- 保证原子性、可见性、有序性。
- 支持可重入。
- 底层和对象头、Monitor 有关。

### CAS

- 比较并交换。
- 是原子类和很多无锁结构的基础。
- 问题：ABA、自旋开销、只能保证单变量原子性。

### AQS

- 核心是 state 状态和 FIFO 等待队列。
- ReentrantLock、Semaphore、CountDownLatch 等都和 AQS 有关。

### 线程池

- 复用线程、控制并发、统一管理任务。
- 七大参数必须熟悉。
- 执行流程：核心线程、阻塞队列、非核心线程、拒绝策略。

### ThreadLocal

- 每个线程保存自己的变量副本。
- 常用于用户上下文、链路追踪、事务上下文等。
- 线程池场景必须 remove。

## 4. 易错点

- volatile 不能保证 i++ 原子性。
- synchronized 锁的是对象，不是代码。
- ThreadLocal 不是解决共享变量竞争，而是避免共享。
- 线程池参数不是越大越好。
- CompletableFuture 默认线程池使用不当可能影响公共线程池。

---

# 二、面试问答练习

## A. 线程基础

### Q1：进程和线程有什么区别？

我的回答：

> 

可能追问：

- 为什么线程切换比进程切换轻？
- Java 线程和操作系统线程是什么关系？

### Q2：并发和并行有什么区别？

我的回答：

> 

可能追问：

- 单核 CPU 能不能并发？
- 多核 CPU 如何实现并行？

### Q3：Java 线程有哪些状态？

我的回答：

> 

可能追问：

- BLOCKED 和 WAITING 有什么区别？
- sleep、wait、join 分别会进入什么状态？

### Q4：start 和 run 有什么区别？

我的回答：

> 

可能追问：

- 直接调用 run 会创建新线程吗？
- 一个线程能 start 两次吗？

### Q5：sleep、wait、join、yield 有什么区别？

我的回答：

> 

可能追问：

- wait 为什么必须在 synchronized 中使用？
- sleep 会释放锁吗？

### Q6：notify 和 notifyAll 有什么区别？

我的回答：

> 

可能追问：

- 为什么很多场景推荐 notifyAll？
- 虚假唤醒是什么？

### Q7：如何优雅停止一个线程？

我的回答：

> 

可能追问：

- interrupt 是强制停止线程吗？
- 为什么不推荐 stop？

## B. JMM 与 volatile

### Q8：什么是 JMM？它解决什么问题？

我的回答：

> 

可能追问：

- 主内存和工作内存怎么理解？
- JMM 和 JVM 内存结构是一回事吗？

### Q9：原子性、可见性、有序性分别是什么？

我的回答：

> 

可能追问：

- 哪些关键字或工具能分别解决这些问题？
- i++ 缺少哪种保证？

### Q10：volatile 有什么作用？

我的回答：

> 

可能追问：

- volatile 如何保证可见性？
- volatile 如何禁止指令重排序？

### Q11：volatile 为什么不能保证 i++ 原子性？

我的回答：

> 

可能追问：

- i++ 大致分成哪些步骤？
- AtomicInteger 为什么可以？

### Q12：happens-before 是什么？

我的回答：

> 

可能追问：

- 常见 happens-before 规则有哪些？
- synchronized 和 volatile 分别对应哪些规则？

### Q13：双重检查锁单例为什么要加 volatile？

我的回答：

> 

可能追问：

- new 对象可能发生什么指令重排序？
- 不加 volatile 可能出现什么问题？

## C. synchronized

### Q14：synchronized 可以用在哪里？分别锁的是什么？

我的回答：

> 

可能追问：

- 普通方法和静态方法锁对象有什么不同？
- 两个对象调用同一个 synchronized 普通方法会互斥吗？

### Q15：synchronized 如何保证原子性、可见性、有序性？

我的回答：

> 

可能追问：

- monitorenter 和 monitorexit 有什么作用？
- 退出同步块时会发生什么？

### Q16：synchronized 为什么是可重入的？

我的回答：

> 

可能追问：

- 可重入解决什么问题？
- ReentrantLock 是否可重入？

### Q17：synchronized 锁升级过程是什么？

我的回答：

> 

可能追问：

- 偏向锁、轻量级锁、重量级锁分别适合什么场景？
- 锁升级能不能降级？

### Q18：synchronized 和 ReentrantLock 有什么区别？

我的回答：

> 

可能追问：

- 公平锁、可中断锁、条件队列分别是什么？
- 为什么 ReentrantLock 需要手动释放？

## D. CAS 与原子类

### Q19：CAS 是什么？

我的回答：

> 

可能追问：

- CAS 包含哪三个操作数？
- CAS 为什么能保证原子性？

### Q20：CAS 有哪些缺点？

我的回答：

> 

可能追问：

- ABA 问题是什么？
- 自旋开销在什么场景下明显？

### Q21：AtomicInteger 底层原理是什么？

我的回答：

> 

可能追问：

- getAndIncrement 大致怎么实现？
- Unsafe 类有什么作用？

### Q22：LongAdder 为什么在高并发下可能比 AtomicLong 快？

我的回答：

> 

可能追问：

- 分段思想是什么？
- LongAdder 适合所有场景吗？

## E. AQS 与锁工具

### Q23：AQS 是什么？

我的回答：

> 

可能追问：

- state 表示什么？
- FIFO 队列解决什么问题？

### Q24：ReentrantLock 的加锁过程和 AQS 有什么关系？

我的回答：

> 

可能追问：

- 获取锁失败的线程去哪里？
- LockSupport 在里面起什么作用？

### Q25：公平锁和非公平锁有什么区别？

我的回答：

> 

可能追问：

- 非公平锁为什么吞吐量可能更高？
- ReentrantLock 默认公平吗？

### Q26：CountDownLatch、CyclicBarrier、Semaphore 分别适合什么场景？

我的回答：

> 

可能追问：

- CountDownLatch 能不能复用？
- Semaphore 如何控制并发数？

### Q27：LockSupport 的 park/unpark 有什么作用？

我的回答：

> 

可能追问：

- 它和 wait/notify 有什么区别？
- unpark 能不能先于 park 调用？

## F. 线程池

### Q28：为什么要使用线程池？

我的回答：

> 

可能追问：

- 线程池解决了线程创建的哪些问题？
- 线程池如何控制系统资源？

### Q29：线程池七大核心参数是什么？

我的回答：

> 

可能追问：

- workQueue 有哪些常见类型？
- threadFactory 有什么用？

### Q30：线程池提交任务后的执行流程是什么？

我的回答：

> 

可能追问：

- 为什么先放队列再创建非核心线程？
- 队列满了会怎样？

### Q31：线程池有哪些拒绝策略？

我的回答：

> 

可能追问：

- AbortPolicy 和 CallerRunsPolicy 有什么区别？
- 业务中如何自定义拒绝策略？

### Q32：为什么不推荐 Executors 创建线程池？

我的回答：

> 

可能追问：

- FixedThreadPool 有什么风险？
- CachedThreadPool 有什么风险？

### Q33：线程池参数应该如何设置？

我的回答：

> 

可能追问：

- CPU 密集型和 IO 密集型怎么区分？
- 参数设置后如何通过监控调优？

### Q34：execute 和 submit 有什么区别？

我的回答：

> 

可能追问：

- submit 任务异常会怎么表现？
- Future 的 get 有什么风险？

### Q35：线程池如何优雅关闭？

我的回答：

> 

可能追问：

- shutdown 和 shutdownNow 有什么区别？
- 如何等待存量任务执行完成？

### Q36：线程池中的任务抛异常会发生什么？

我的回答：

> 

可能追问：

- execute 和 submit 异常处理有什么不同？
- 如何统一记录线程池异常？

## G. ThreadLocal

### Q37：ThreadLocal 是什么？适合什么场景？

我的回答：

> 

可能追问：

- ThreadLocal 是解决线程安全问题的吗？
- 用户上下文为什么适合 ThreadLocal？

### Q38：ThreadLocal 底层结构是什么？

我的回答：

> 

可能追问：

- ThreadLocalMap 存在哪里？
- key 和 value 分别是什么？

### Q39：ThreadLocal 为什么可能导致内存泄漏？

我的回答：

> 

可能追问：

- key 为什么设计成弱引用？
- 线程池场景下为什么更危险？

### Q40：使用 ThreadLocal 后为什么建议 remove？

我的回答：

> 

可能追问：

- 不 remove 可能导致脏数据吗？
- 在 Web 请求中应该在哪里清理？

## H. 并发容器

### Q41：HashMap 为什么线程不安全？

我的回答：

> 

可能追问：

- JDK 1.7 扩容为什么可能成环？
- JDK 1.8 还有哪些并发问题？

### Q42：ConcurrentHashMap 如何保证线程安全？

我的回答：

> 

可能追问：

- JDK 1.7 和 JDK 1.8 实现有什么区别？
- 为什么不锁整张表？

### Q43：CopyOnWriteArrayList 的原理和适用场景是什么？

我的回答：

> 

可能追问：

- 为什么适合读多写少？
- 写多场景有什么问题？

### Q44：BlockingQueue 在线程池中扮演什么角色？

我的回答：

> 

可能追问：

- ArrayBlockingQueue 和 LinkedBlockingQueue 有什么区别？
- SynchronousQueue 有什么特点？

## I. Future 与 CompletableFuture

### Q45：Future 有什么作用？有什么缺点？

我的回答：

> 

可能追问：

- get 为什么可能导致阻塞？
- Future 如何取消任务？

### Q46：CompletableFuture 解决了什么问题？

我的回答：

> 

可能追问：

- 它如何支持任务编排？
- 默认线程池使用时有什么风险？

### Q47：thenApply、thenAccept、thenCompose、thenCombine 有什么区别？

我的回答：

> 

可能追问：

- 串行依赖和并行合并分别用哪个？
- thenCompose 和 thenApply 返回 CompletableFuture 时有什么区别？

### Q48：CompletableFuture 如何处理异常？

我的回答：

> 

可能追问：

- exceptionally、handle、whenComplete 有什么区别？
- 多个异步任务中一个失败怎么办？

## J. 死锁与安全发布

### Q49：什么是死锁？产生死锁的四个必要条件是什么？

我的回答：

> 

可能追问：

- 如何避免死锁？
- 线上死锁如何排查？

### Q50：如何定位 Java 程序中的死锁？

我的回答：

> 

可能追问：

- jstack 能看到什么？
- 线程 dump 中应该关注哪些状态？

### Q51：什么是对象逃逸？

我的回答：

> 

可能追问：

- 构造方法中启动线程为什么危险？
- this 逃逸是什么？

### Q52：什么是安全发布？

我的回答：

> 

可能追问：

- final、volatile、synchronized 如何帮助安全发布？
- 单例对象如何安全发布？

## K. 项目场景题

### Q53：项目里如何使用线程池？参数怎么设计？

我的回答：

> 

可能追问：

- 业务峰值如何估算？
- 如何监控线程池运行状态？

### Q54：如何防止用户重复提交？

我的回答：

> 

可能追问：

- 前端防重、后端幂等、数据库唯一约束分别有什么作用？
- Redis 锁适合这个场景吗？

### Q55：多个请求同时修改同一条数据，如何保证正确性？

我的回答：

> 

可能追问：

- 乐观锁和悲观锁怎么选？
- 数据库锁和 Redis 分布式锁有什么区别？

### Q56：线程池打满了怎么排查？

我的回答：

> 

可能追问：

- 是任务太多、任务太慢，还是线程数太少？
- 如何做降级或限流？

### Q57：ThreadLocal 在项目中可以怎么用？怎么避免问题？

我的回答：

> 

可能追问：

- 用户信息上下文如何传递？
- 异步线程中 ThreadLocal 会不会自动传递？

