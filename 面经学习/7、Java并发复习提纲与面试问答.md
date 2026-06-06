# 7、Java 并发复习提纲与面试问答

## 一、知识树

### 1. 线程基础

- 线程创建方式
- Java 线程状态
- start 和 run
- sleep、wait、join、yield
- interrupt 中断机制

### 2. JMM 与 volatile

- 原子性、可见性、有序性
- happens-before
- volatile 的作用和局限
- 双重检查锁为什么需要 volatile

### 3. synchronized 与锁

- synchronized 锁对象
- monitorenter、monitorexit
- 可重入性
- 锁升级
- synchronized 和 ReentrantLock

### 4. CAS 与原子类

- CAS 三个操作数
- ABA 问题
- AtomicInteger
- LongAdder

### 5. ThreadLocal

- ThreadLocalMap
- 弱引用 key
- 内存泄漏
- remove

### 6. 线程池

- 七大核心参数
- 任务执行流程
- 拒绝策略
- 阻塞队列
- execute 和 submit
- shutdown 和 shutdownNow

### 7. AQS 与 JUC

- AQS state 和 CLH 队列
- ReentrantLock
- CountDownLatch
- Semaphore
- CyclicBarrier
- BlockingQueue

### 8. 并发容器与异步编程

- ConcurrentHashMap
- CopyOnWriteArrayList
- BlockingQueue
- Future
- CompletableFuture

## 二、高频面试题

### 1. Java 线程有哪些状态？

简答版：
Java 线程有 NEW、RUNNABLE、BLOCKED、WAITING、TIMED_WAITING、TERMINATED 六种状态。

展开版：
NEW 表示线程对象创建但还没 start；RUNNABLE 表示可运行，包含操作系统层面的就绪和运行；BLOCKED 表示等待 synchronized 锁；WAITING 表示无限期等待，比如 wait、join、park；TIMED_WAITING 表示限时等待，比如 sleep、wait(time)、join(time)；TERMINATED 表示线程执行结束。

常见追问：
- BLOCKED 和 WAITING 有什么区别？
- sleep 会释放锁吗？
- wait 为什么必须在 synchronized 中调用？

### 2. start 和 run 有什么区别？

简答版：
start 会启动新线程，由新线程执行 run；run 只是普通方法调用，不会创建新线程。

展开版：
调用 start 后，线程进入 RUNNABLE 状态，等待 JVM 和操作系统调度。run 方法只是线程要执行的任务体，如果直接调用 run，它会在当前线程中同步执行。

常见追问：
- 一个线程可以 start 两次吗？
- 为什么 start 后不是立刻运行？
- 线程执行完还能重新 start 吗？

### 3. sleep、wait、join、yield 有什么区别？

简答版：
sleep 让当前线程限时等待但不释放锁；wait 释放对象锁并等待通知；join 等待另一个线程结束；yield 只是提示调度器让出 CPU。

展开版：
sleep 是 Thread 的静态方法；wait 是 Object 的方法，必须持有对象 monitor 才能调用；join 底层也是等待目标线程执行结束；yield 不保证一定生效，也不会释放锁。

常见追问：
- wait 和 notify 为什么属于 Object？
- wait 被唤醒后能立刻执行吗？
- 为什么 wait 通常要写在 while 中？

### 4. JMM 主要解决什么问题？

简答版：
JMM 定义了多线程环境下共享变量的读写规则，主要解决原子性、可见性和有序性问题。

展开版：
由于 CPU 缓存、编译器优化、指令重排序的存在，一个线程修改共享变量后，其他线程不一定马上可见；程序执行顺序也可能和源码顺序不同。JMM 通过 volatile、synchronized、final、happens-before 等规则约束这些行为。

常见追问：
- 工作内存和主内存是什么关系？
- happens-before 是什么？
- synchronized 如何保证可见性？

### 5. volatile 有什么作用？

简答版：
volatile 保证可见性，禁止特定指令重排序，但不保证复合操作的原子性。

展开版：
写 volatile 变量后，会把修改刷新到主内存；读 volatile 变量时，会读取最新值。volatile 还会插入内存屏障，常用于状态标记和双重检查锁。但 i++ 包含读、改、写三步，volatile 不能保证这三步整体不被打断。

常见追问：
- volatile 为什么不能保证 i++ 原子性？
- volatile 和 synchronized 有什么区别？
- 双重检查锁为什么要用 volatile？

### 6. synchronized 锁的是什么？

简答版：
普通同步方法锁当前对象 this；静态同步方法锁当前类的 Class 对象；同步代码块锁括号里指定的对象。

展开版：
synchronized 的本质是进入和退出对象关联的 monitor。进入同步块时尝试获取 monitor，退出时释放 monitor。JVM 通过 monitorenter 和 monitorexit 指令实现同步代码块，通过方法访问标志实现同步方法。

常见追问：
- synchronized 为什么是可重入的？
- 两个普通同步方法之间会互斥吗？
- synchronized 和 ReentrantLock 有什么区别？

### 7. synchronized 锁升级过程是什么？

简答版：
JDK 8 中通常是无锁、偏向锁、轻量级锁、重量级锁；随着竞争加剧逐步升级。

展开版：
无竞争时，偏向锁偏向第一个获取锁的线程；轻微竞争时，线程通过 CAS 和自旋竞争轻量级锁；竞争激烈或自旋不划算时，锁膨胀为重量级锁，阻塞和唤醒由 ObjectMonitor 参与，成本更高。

常见追问：
- 偏向锁适合什么场景？
- 轻量级锁为什么要自旋？
- 重量级锁为什么成本高？

### 8. CAS 是什么？有什么问题？

简答版：
CAS 是比较并交换，包含内存值 V、预期值 A、新值 B。只有 V 等于 A 时才更新为 B。问题包括 ABA、自旋开销大、只能直接保证单变量更新。

展开版：
CAS 是乐观锁思想，失败后通常重试。它依赖 CPU 原子指令保证比较和更新不可分割。高竞争下大量线程反复 CAS 会消耗 CPU。ABA 问题可以用版本号解决，比如 AtomicStampedReference。

常见追问：
- CAS 为什么能保证原子性？
- ABA 在什么场景会出问题？
- AtomicInteger 底层是什么？

### 9. ThreadLocal 为什么可能内存泄漏？

简答版：
ThreadLocalMap 的 key 是 ThreadLocal 的弱引用，value 是强引用。如果 key 被回收但 value 没清理，在线程长期存活时 value 可能一直留在 ThreadLocalMap 中。

展开版：
线程池中的线程会复用并长期存活。如果使用 ThreadLocal 后不 remove，ThreadLocalMap 中的脏 Entry 可能无法及时清理，导致 value 持续占用内存，也可能造成数据串用。因此用完后建议在 finally 中调用 remove。

常见追问：
- key 为什么设计成弱引用？
- ThreadLocalMap 存在什么对象里？
- InheritableThreadLocal 是什么？

### 10. 线程池七大核心参数是什么？

简答版：
corePoolSize、maximumPoolSize、keepAliveTime、unit、workQueue、threadFactory、handler。

展开版：
corePoolSize 是核心线程数；maximumPoolSize 是最大线程数；keepAliveTime 和 unit 控制非核心线程空闲存活时间；workQueue 存放等待执行的任务；threadFactory 创建线程；handler 是任务无法接收时的拒绝策略。

常见追问：
- 线程池任务提交后的执行流程是什么？
- 为什么不推荐 Executors？
- 核心线程数怎么设置？

### 11. 线程池任务执行流程是什么？

简答版：
先创建核心线程；核心线程满了放入队列；队列满了创建非核心线程；线程数达到最大后执行拒绝策略。

展开版：
ThreadPoolExecutor 收到任务后，如果工作线程数小于 corePoolSize，直接创建核心线程执行；否则尝试放入阻塞队列；如果队列满且线程数小于 maximumPoolSize，就创建非核心线程；如果仍无法处理，就触发拒绝策略。

常见追问：
- 为什么是先入队再创建非核心线程？
- 不同阻塞队列会如何影响线程池？
- execute 和 submit 有什么区别？

### 12. AQS 是什么？

简答版：
AQS 是 JUC 中构建锁和同步器的基础框架，核心是 state 状态变量和等待队列。

展开版：
AQS 用一个 volatile int state 表示同步状态，用 CAS 修改 state。获取失败的线程会进入 CLH 等待队列，并通过 LockSupport park 阻塞。ReentrantLock、Semaphore、CountDownLatch 等都基于 AQS 实现。

常见追问：
- ReentrantLock 如何基于 AQS 加锁？
- 公平锁和非公平锁有什么区别？
- LockSupport 的 park/unpark 有什么特点？

### 13. ConcurrentHashMap 如何保证线程安全？

简答版：
JDK 1.8 中 ConcurrentHashMap 主要通过 CAS + synchronized 保证线程安全，读操作大多无锁，写操作只锁桶头节点。

展开版：
初始化和扩容中大量使用 CAS。put 时，如果桶为空，通过 CAS 放入；如果桶不为空，对桶头节点加 synchronized 锁，保证该桶内修改安全。相比 Hashtable 锁整张表，ConcurrentHashMap 锁粒度更小，并发性能更好。

常见追问：
- JDK 1.7 和 JDK 1.8 的 ConcurrentHashMap 有什么区别？
- size 为什么难统计？
- HashMap 为什么线程不安全？

### 14. CompletableFuture 解决了什么问题？

简答版：
CompletableFuture 解决了 Future 难以编排、难以组合、异常处理不方便的问题。

展开版：
Future 只能阻塞 get 获取结果，多个异步任务之间的串行、并行、聚合、异常恢复都不方便。CompletableFuture 提供 thenApply、thenCompose、thenCombine、allOf、exceptionally 等方法，可以更灵活地组织异步任务。

常见追问：
- thenApply 和 thenCompose 有什么区别？
- allOf 如何汇总多个结果？
- CompletableFuture 默认使用什么线程池？

### 15. 如何优雅停止线程？

简答版：
推荐使用中断标记或自定义停止标记，让线程在合适的位置主动退出，不推荐使用 stop。

展开版：
interrupt 不会强制杀死线程，它只是设置中断标记。线程需要在循环中检查 isInterrupted，或者在阻塞方法抛出 InterruptedException 后正确处理。stop 会强制释放锁，可能破坏对象状态一致性，所以不推荐。

常见追问：
- interrupted 和 isInterrupted 有什么区别？
- 阻塞状态下收到中断会发生什么？
- 线程池如何优雅关闭？

## 三、易错点

- volatile 不保证 i++ 原子性。
- sleep 不释放锁，wait 会释放锁。
- notify 唤醒后线程还要重新竞争锁。
- ThreadLocal 不是用来解决共享变量同步问题，而是给每个线程一份独立副本。
- 线程池不是线程越多越好，CPU 密集型和 I/O 密集型设置思路不同。
- AQS 不是某一把锁，而是一套构建同步器的框架。
- ConcurrentHashMap 的读操作通常不加锁，但不代表所有操作都完全无锁。

## 四、10 题自测

1. Java 线程六种状态分别是什么？
2. wait 和 sleep 的区别是什么？
3. JMM 解决了什么问题？
4. volatile 的作用和局限是什么？
5. synchronized 锁的对象分别是什么？
6. synchronized 锁升级过程是什么？
7. CAS 的 ABA 问题如何解决？
8. ThreadLocal 为什么要 remove？
9. 线程池任务提交后的完整流程是什么？
10. AQS 的核心结构是什么？

