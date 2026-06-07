# 7、Java 并发复习提纲与面试问答

> 使用方式：你先在主问题和追问的“回答”里写答案，我检查后会直接替换成更精确的版本。当前阶段以**学习理解**为主，不追求面试精简；回答会尽量包含**原理解释、具体例子、最后再总结关键词**。需要强调的关键词直接在原文中加粗。

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

- AQS state 和等待队列
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

回答：

#### 追问 1：BLOCKED、WAITING、TIMED_WAITING 有什么区别？

回答：

#### 追问 2：Java 的 RUNNABLE 和操作系统的运行态是同一个概念吗？

回答：

#### 追问 3：wait、sleep、park 分别会让线程进入什么状态？

回答：

### 2. start 和 run 有什么区别？

回答：

#### 追问 1：为什么调用 start 才会创建新线程？

回答：

#### 追问 2：一个线程对象能 start 两次吗？

回答：

### 3. sleep、wait、join、yield 有什么区别？

回答：

#### 追问 1：sleep 会释放锁吗？wait 会释放锁吗？

回答：

#### 追问 2：wait 为什么必须放在 synchronized 中？

回答：

#### 追问 3：wait 为什么通常要放在 while 循环里？

回答：

### 4. JMM 主要解决什么问题？

回答：

#### 追问 1：原子性、可见性、有序性分别是什么？

回答：

#### 追问 2：happens-before 是什么？

回答：

#### 追问 3：为什么多线程下会有指令重排序问题？

回答：

### 5. volatile 有什么作用？

回答：

#### 追问 1：volatile 为什么不能保证 i++ 的原子性？

回答：

#### 追问 2：volatile 如何禁止指令重排序？

回答：

#### 追问 3：双重检查锁为什么要加 volatile？

回答：

### 6. synchronized 锁的是什么？

回答：

#### 追问 1：普通同步方法、静态同步方法、同步代码块分别锁什么？

回答：

#### 追问 2：synchronized 为什么是可重入的？

回答：

#### 追问 3：synchronized 如何保证可见性？

回答：

### 7. synchronized 锁升级过程是什么？

回答：

#### 追问 1：偏向锁、轻量级锁、重量级锁分别适合什么场景？

回答：

#### 追问 2：轻量级锁为什么要自旋？

回答：

#### 追问 3：重量级锁为什么成本更高？

回答：

### 8. CAS 是什么？有什么问题？

回答：

#### 追问 1：CAS 为什么能保证原子性？

回答：

#### 追问 2：ABA 问题是什么？

回答：

#### 追问 3：AtomicStampedReference 如何解决 ABA？

回答：

### 9. ThreadLocal 为什么可能内存泄漏？

回答：

#### 追问 1：ThreadLocalMap 的 key 为什么是弱引用？

回答：

#### 追问 2：为什么线程池场景更容易暴露 ThreadLocal 泄漏？

回答：

#### 追问 3：为什么建议在 finally 中 remove？

回答：

### 10. 线程池七大核心参数是什么？

回答：

#### 追问 1：corePoolSize 和 maximumPoolSize 分别控制什么？

回答：

#### 追问 2：不同阻塞队列会如何影响线程池行为？

回答：

#### 追问 3：为什么不推荐直接使用 Executors？

回答：

### 11. 线程池任务执行流程是什么？

回答：

#### 追问 1：为什么通常是先入队，再创建非核心线程？

回答：

#### 追问 2：execute 和 submit 有什么区别？

回答：

#### 追问 3：线程池中的任务抛异常会发生什么？

回答：

### 12. AQS 是什么？

回答：

#### 追问 1：AQS 的 state 表示什么？

回答：

#### 追问 2：AQS 等待队列的作用是什么？

回答：

#### 追问 3：ReentrantLock 和 AQS 有什么关系？

回答：

### 13. ConcurrentHashMap 如何保证线程安全？

回答：

#### 追问 1：JDK 1.7 和 JDK 1.8 的 ConcurrentHashMap 有什么区别？

回答：

#### 追问 2：HashMap 为什么线程不安全？

回答：

#### 追问 3：ConcurrentHashMap 的 size 为什么不好统计？

回答：

### 14. CompletableFuture 解决了什么问题？

回答：

#### 追问 1：Future 有什么局限？

回答：

#### 追问 2：thenApply、thenCompose、thenCombine 有什么区别？

回答：

#### 追问 3：CompletableFuture 如何处理异常？

回答：

### 15. 如何优雅停止线程？

回答：

#### 追问 1：interrupt 是强制停止线程吗？

回答：

#### 追问 2：isInterrupted 和 Thread.interrupted 有什么区别？

回答：

#### 追问 3：为什么不推荐 Thread.stop？

回答：

## 三、待自查易错方向

> 这里只列检查方向，不写答案。你写完后，我会按这些点帮你抓错，并直接把回答替换成更精确的学习版。

- wait 和 sleep 是否释放锁
- volatile 的可见性、有序性和非原子性
- synchronized 锁对象和锁升级
- CAS 的 ABA、自旋和单变量限制
- ThreadLocal 的弱引用 key 和强引用 value
- 线程池执行流程、阻塞队列和拒绝策略
- AQS 的 state、等待队列和 LockSupport
- ConcurrentHashMap 的锁粒度和扩容

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

