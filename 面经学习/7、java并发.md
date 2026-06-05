#### volatile 关键字作用
1. 保证可见性：一个线程修改 volatile 变量后，其他线程后续读取能看到最新值。
2. 禁止指令重排序：通过内存屏障实现，常用于双重检查锁单例。
3. 不保证原子性：例如 i++ 包含读取、加一、写回三个步骤，volatile 不能保证这三个步骤整体不可打断。



#### synchronized关键字及其工作原理
- 偏向锁（没有竞争）-> 轻量级锁（轻微竞争）-> 重量级锁（激烈竞争）
		
	- **偏向锁（Biased Locking，JDK15默认禁用）：** 针对**完全没有竞争**的场景。只在对象头的 Mark Word 中用 CAS 记录当前线程 ID，以后该线程进出同步块不需要任何同步操作。
	    
	- **轻量级锁（Lightweight Locking）：** 发生**轻微竞争**。JVM 会在当前线程的栈帧中开辟一块 `Lock Record` 空间，将对象头的 Mark Word 拷贝过去，然后通过 CAS 尝试将对象头中的指针指向栈帧中的 `Lock Record`。
	    
	- **重量级锁（Heavyweight Locking）：** 发生**激烈竞争**。轻量级锁 CAS 失败后，并不会立刻升级，而是会进行**自适应自旋（Adaptive Spinning）**。如果自旋一定次数后依然拿不到锁，才会膨胀为重量级锁。此时对象头才会指向 `ObjectMonitor`。
	
- 重量级锁原理：当锁竞争比较激烈，自旋也无法成功获取锁时，锁会膨胀为重量级锁。此时对象头的 Mark Word 会指向一个 `ObjectMonitor`，后续的加锁、释放锁、阻塞、唤醒都由 Monitor 参与完成。
	- `_owner`：指向当前持有锁的线程。
	- `_recursions`：记录当前线程重入这把锁的次数，用来实现可重入。
	- `EntryList`：竞争锁失败后等待获取锁的线程集合。锁释放后，JVM 会从这里唤醒线程重新竞争锁。
	- `WaitSet`：调用 `wait()` 后进入的等待集合。线程调用 `wait()` 时会释放锁，进入等待状态；被 `notify()` 或 `notifyAll()` 唤醒后，不会立刻继续执行，而是需要重新竞争锁，拿到锁之后才能从 `wait()` 返回。
- 总结：**重量级锁可以理解为对象关联了一个 Monitor。Monitor 记录谁持有锁、重入了几次、哪些线程在等待竞争锁、哪些线程因为 `wait()` 进入等待。**

#### synchronized 锁的是什么
- 普通同步方法：锁当前对象 this。
- 静态同步方法：锁当前类的 Class 对象。
- 同步代码块：锁 synchronized(...) 中指定的对象。

#### synchronized 的特点
- 保证原子性：同一时刻只有一个线程能进入同步代码。
- 保证可见性：线程释放锁前会把修改刷新到主内存，线程获取锁后会读取最新值。
- 可重入：同一个线程重复获取同一把锁不会死锁，Monitor 会记录重入次数。



## 面试自测问题

### 一、线程基础
##### 进程和线程有什么区别？
   - 进程独享进程空间；线程共享进程空间的堆、方法区、进程资源，每个线程有独立的栈、寄存器、pc
   - 进程需要使用进程通信方法（如管道、消息队列、共享空间、信号、信号量、socket）；线程可以直接访问进程空间中的共享变量（如成员变量）来进行通信。缺点是线程需要注意同步问题。
   - 一个进程崩了其他进程不会有影响；线程一个崩了，在同一个进程空间的其他线程都会崩。
   - 进程的创建/销毁耗时大（要分配进程空间）；线程创建/销毁耗时小

##### 并发和并行有什么区别？
- 并发：同一时间段内处理多个任务，不一定真的同时执行，单核 CPU 通过时间片切换也可以实现并发。
- 并行：同一时刻多个任务真正同时执行，通常需要多核 CPU 支持。
- 简单说，并发强调任务交替推进，并行强调任务同时执行。

##### Java 线程有哪些状态？它们之间如何转换？
	Java 线程有 6 种状态：
	- NEW：线程对象已创建，但还没有调用 start()。
	- RUNNABLE：可运行状态，包括就绪和正在运行。Java 中没有单独区分 ready 和 running。
	- BLOCKED：等待获取 synchronized 锁。
	- WAITING：无限期等待，比如 wait()、join()、LockSupport.park()。
	- TIMED_WAITING：限时等待，比如 sleep(time)、wait(time)、join(time)。
	- TERMINATED：线程执行结束。

##### `start()` 和 `run()` 有什么区别？
	- start()：启动一个新线程，让线程进入 RUNNABLE 状态，之后由 JVM/操作系统调度执行 run()。
	- run()：只是一个普通方法调用，不会创建新线程。谁调用 run()，就由谁在当前线程中执行。

##### `sleep()`、`wait()`、`join()`、`yield()` 有什么区别？
	- sleep 是 Thread 的静态方法，让当前线程进入限时等待，不释放锁；
	- wait 是 Object 的方法，必须在 synchronized 中调用，会释放对象锁，等待 notify 或 notifyAll 唤醒；
	- join 是 Thread 的方法，表示当前线程等待目标线程执行结束；
	- yield 是 Thread 的静态方法，表示当前线程主动让出 CPU，但只是提示调度器，不保证一定生效，也不会释放锁。

##### `wait()` 为什么必须放在 synchronized 代码块或同步方法中？
	   wait() 是 Object 的方法，作用是让当前线程释放某个对象的 monitor 并进入该对象的 WaitSet。
	所以调用 wait() 前，线程必须先持有这个对象的锁，否则不知道要释放哪把锁，也无法保证等待和通知的正确配合。
	如果没有持有锁就调用 wait()，会抛出 IllegalMonitorStateException。

##### `notify()` 和 `notifyAll()` 有什么区别？
	- notify()：随机唤醒该对象 WaitSet 中的一个线程。
	- notifyAll()：唤醒该对象 WaitSet 中的所有线程。
	- 被唤醒的线程不会立刻继续执行，必须先重新竞争 synchronized 锁，拿到锁后才能从 wait() 返回。
	- notifyAll() 可能造成大量线程同时竞争锁，也就是惊群效应，但可以避免某些场景下 notify 唤醒错误线程导致程序卡住。

### 二、JMM 与 volatile
##### 什么是 Java 内存模型（JMM）？它主要解决什么问题？
   - JMM 是 Java 内存模型，定义了多线程环境下变量如何在主内存和线程工作内存之间读写，以及如何保证原子性、可见性和有序性。
	它主要解决的问题是：在多线程并发执行时，线程之间如何安全地共享变量，避免因为 CPU 缓存、编译器优化、指令重排序导致线程看到的数据不一致。

##### 原子性、可见性、有序性分别是什么意思？
	- 原子性：一个操作不可被中断，要么全部执行成功，要么完全不执行，其他线程看不到中间状态。
	- 可见性：一个线程修改共享变量后，其他线程能够及时看到这个修改。
	- 有序性：程序执行顺序在多线程观察下符合预期，不会因为编译器或 CPU 指令重排序导致结果异常。

##### volatile 有什么作用？
   - 保证可见性：每次修改后会立刻刷新到主内存中
   - 禁止指令重排：通过内存屏障
   - 非原子性

##### volatile 为什么不能保证 `i++` 的原子性？
   - i++ 是复合操作，包含读取、加一、写回三个步骤。volatile 只能保证每次读取到的是较新的值、写入后对其他线程可见，但不能保证这三个步骤作为一个整体不可被打断。
	例如两个线程同时读取到 i=0，都计算出 1，然后都写回 1，最终结果是 1，而不是 2，所以 volatile 不能保证 i++ 的原子性。

##### volatile 如何禁止指令重排序？
	volatile 通过插入内存屏障禁止特定类型的指令重排序：
	- volatile 写之前的普通读写不能被重排到 volatile 写之后。
	- volatile 读之后的普通读写不能被重排到 volatile 读之前。
	这样可以保证 volatile 变量作为状态标记时，其他线程看到标记变化后，也能看到标记之前的普通变量修改。

##### happens-before 是什么？你能举几个常见规则吗？
	happens-before 是 JMM 中用来判断可见性和有序性的规则。如果操作 A happens-before 操作 B，那么 A 的执行结果对 B 可见，并且 A 的执行顺序排在 B 之前。
	
	常见规则：
	- 程序次序规则：同一个线程内，前面的操作 happens-before 后面的操作。
	- monitor 锁规则：解锁 happens-before 后续对同一把锁的加锁。
	- volatile 规则：对 volatile 变量的写 happens-before 后续对这个变量的读。
	- 线程启动规则：调用 start() happens-before 新线程中的操作。
	- 线程终止规则：线程中的所有操作 happens-before 其他线程检测到它已经结束，例如 join() 返回。
	- 传递性：A happens-before B，B happens-before C，则 A happens-before C。

##### 双重检查锁单例为什么要加 volatile？
	双重检查锁单例中，instance = new Singleton() 不是原子操作，大致包括：
	1. 分配对象内存
	2. 初始化对象
	3. 将引用赋值给 instance
	
	如果发生指令重排序，可能先执行 3，再执行 2。此时其他线程看到 instance != null，直接返回一个还没初始化完成的对象。
	
	给 instance 加 volatile 可以禁止这种重排序，并保证对象初始化完成后对其他线程可见。

### 三、synchronized
##### synchronized 可以用在哪些地方？分别锁的是什么？
	- 普通同步方法：锁当前实例对象 this。
	- 静态同步方法：锁当前类的 Class 对象。
	- 同步代码块：锁 synchronized(...) 中指定的对象。


##### synchronized 如何保证原子性、可见性和有序性？
	- 原子性：同一时刻只有一个线程能持有同一把锁并执行同步代码块。
	- 可见性：线程释放锁前，会把同步代码中的修改刷新到主内存；其他线程获取同一把锁后，可以看到之前线程释放锁前的修改。
	- 有序性：synchronized 通过 monitorenter/monitorexit 以及 happens-before 规则约束重排序。对同一把锁的解锁 happens-before 后续对这把锁的加锁。

##### synchronized 为什么是可重入的？
   - 它会指向一个Monitor对象，该Monitor对象会维护一个计数器，被锁一次就加1，解锁一次就减一，计数器为0时会释放锁。如果持锁线程再次进入同一把锁保护的代码，不会被自己阻塞，只会让重入计数加一。

##### synchronized 的锁升级过程是什么？
   - JDK 8 中锁升级过程一般是：无锁 -> 偏向锁 -> 轻量级锁 -> 重量级锁。
	偏向锁适合只有一个线程反复进入同步块的场景；出现竞争后会撤销偏向锁，升级为轻量级锁；轻量级锁通过 CAS 和自旋竞争，竞争激烈或自旋失败后膨胀为重量级锁，由 Monitor 参与阻塞和唤醒。

##### 偏向锁、轻量级锁、重量级锁分别适合什么场景？
	- 偏向锁：没有竞争，通常只有一个线程反复获取同一把锁。
	- 轻量级锁：有少量竞争，线程持锁时间短，可以通过 CAS 和自旋避免阻塞。
	- 重量级锁：竞争激烈或持锁时间较长，自旋不划算，需要阻塞和唤醒线程。

##### 重量级锁中的 Monitor 大致包含哪些核心信息？
	- owner：当前持有锁的线程。
	- recursions：重入次数。
	- EntryList：等待竞争锁的线程。
	- WaitSet：调用 wait() 后等待的线程。被 notify/notifyAll 唤醒后，还要重新竞争锁。

##### synchronized 和 ReentrantLock 有什么区别？
	- synchronized 是 JVM 关键字，使用简单，自动加锁和释放锁，异常时也会自动释放。
	- ReentrantLock 是 JUC 提供的显式锁，需要手动 lock() 和 unlock()，通常要在 finally 中释放。
	- ReentrantLock 支持公平锁和非公平锁，synchronized 一般是非公平的。
	- ReentrantLock 支持可中断获取锁、超时获取锁、尝试获取锁 tryLock()。
	- ReentrantLock 可以配合多个 Condition 实现更灵活的等待/通知机制，而 synchronized 只能配合一个对象的 wait/notify。
	- 两者都是可重入锁。

### 四、CAS 与原子类
##### CAS 是什么？它包含哪三个操作数？
	CAS 是 Compare And Swap，比较并交换，是一种乐观锁思想。
	
	它包含三个操作数：
	- V：内存中的当前值。
	- A：预期旧值。
	- B：要修改的新值。
	
	执行时会比较 V 是否等于 A：
	- 如果相等，说明没有被其他线程修改过，就把 V 更新为 B。
	- 如果不相等，说明被其他线程改过，更新失败，通常会重试。

##### CAS 为什么能保证原子性？
   - 由硬件实现

##### CAS 有哪些缺点？
	- ABA 问题：值从 A 变成 B，又变回 A，CAS 会误以为没有变化。
	- 自旋开销大：竞争激烈时，大量线程反复重试，会浪费 CPU。
	- 只能保证一个共享变量的原子更新：多个变量的一致性需要额外机制，例如锁或 AtomicReference 封装对象。

##### 什么是 ABA 问题？如何解决？
	ABA 问题是指一个变量原来是 A，期间被其他线程改成 B，又改回 A。当前线程执行 CAS 时发现值还是 A，就以为没有被修改过，但实际上它已经发生过变化。
	
	解决方式：
	- 加版本号，每次修改时版本号递增。
	- Java 中可以使用 AtomicStampedReference(给引用额外绑定一个版本号stamp)，通过值 + 版本号一起判断。
	- 也可以用 AtomicMarkableReference(给引用额外绑定一个boolean标记mark)，通过值 + 标记位判断是否发生过变化。

##### AtomicInteger 的底层原理是什么？
	AtomicInteger 底层主要依赖 volatile + CAS：
	- value 字段用 volatile 修饰，保证可见性。
	- 更新时使用 CAS 原子操作，比如 compareAndSet。
	- 如果 CAS 失败，说明其他线程已经修改过，会在循环中重新读取最新值并重试。

### 五、ThreadLocal
##### ThreadLocal 是什么？适合解决什么问题？
   - ThreadLocal 是线程本地变量工具，可以让每个线程都拥有一份互不影响的变量副本。
	它适合在线程内部传递上下文信息，比如用户信息、请求上下文、数据库连接、事务信息等，避免方法层层传参。

##### ThreadLocal 的底层结构是什么？
   - 每个 Thread 对象内部都有一个 ThreadLocalMap。
	ThreadLocalMap 的 key 是 ThreadLocal 对象的弱引用，value 是当前线程保存的变量值。
	所以不是 ThreadLocal 自己持有一个全局 Map，而是每个线程内部维护自己的 ThreadLocalMap。

##### ThreadLocal 为什么可能导致内存泄漏？
   - ThreadLocalMap 的 key 是 ThreadLocal 的弱引用，如果外部 ThreadLocal 强引用被回收，key 会变成 null。
	但 value 仍然被 ThreadLocalMap 强引用着。
	
	如果线程迟迟不结束，尤其在线程池中线程会被复用，ThreadLocalMap 也会长期存在，value 就可能无法被回收，造成内存泄漏。

##### 使用 ThreadLocal 后为什么建议调用 `remove()`？
   - 调用 remove() 会把当前线程 ThreadLocalMap 中对应的 Entry 清理掉，断开 value 的强引用。
	在线程池场景下尤其重要，因为线程不会马上销毁，如果不 remove，旧请求的数据可能残留在线程中，既可能造成内存泄漏，也可能导致后续任务读到脏数据。

### 六、线程池
##### 为什么要使用线程池？
   - 复用线程，避免频繁创建和销毁线程带来的开销。
   - 控制线程数量，防止线程无限创建导致 CPU 上下文切换过多、内存占用过高，甚至系统资源耗尽。
   - 统一管理任务，比如任务排队、拒绝策略、线程命名、异常处理和线程池关闭。

##### 线程池的七大核心参数是什么？
   - `corePoolSize`：核心线程数，线程池中长期保留的线程数量。
   - `maximumPoolSize`：最大线程数，线程池最多能创建的线程数量。
   - `keepAliveTime`：非核心线程空闲多久后会被回收。
   - `unit`：`keepAliveTime` 的时间单位。
   - `workQueue`：任务队列，核心线程都忙时，用来存放等待执行的任务。
   - `threadFactory`：线程工厂，用来创建线程，可以设置线程名、是否为守护线程等。
   - `handler`：拒绝策略，当线程数达到最大线程数，并且任务队列也满了，就执行拒绝策略。

##### 线程池提交任务后的执行流程是什么？
   - 如果当前线程数小于 `corePoolSize`，直接创建核心线程执行任务。
   - 如果当前线程数已经达到 `corePoolSize`，就尝试把任务放入 `workQueue`。
   - 如果任务队列已满，并且当前线程数小于 `maximumPoolSize`，就创建非核心线程执行任务。
   - 如果任务队列已满，并且当前线程数也达到 `maximumPoolSize`，就执行拒绝策略。
   - 记忆：先核心线程，再任务队列，再最大线程，最后拒绝策略。

##### 线程池有哪些拒绝策略？
   - `AbortPolicy`：默认策略，直接抛出 `RejectedExecutionException`。
   - `CallerRunsPolicy`：由提交任务的线程自己执行这个任务。好处是不会丢任务，还能降低任务提交速度。
   - `DiscardPolicy`：直接丢弃当前任务，不抛异常。
   - `DiscardOldestPolicy`：丢弃队列中最早的任务，然后尝试重新提交当前任务。

##### 为什么不推荐使用 `Executors` 创建线程池？
   - `Executors` 隐藏了线程池关键参数，容易导致资源耗尽。
   - `newFixedThreadPool` 和 `newSingleThreadExecutor` 使用无界 `LinkedBlockingQueue`。如果任务提交速度大于处理速度，任务会无限堆积，可能导致 OOM。
   - `newCachedThreadPool` 使用 `SynchronousQueue`，并且 `maximumPoolSize` 是 `Integer.MAX_VALUE`。如果任务很多，可能创建大量线程，导致系统资源耗尽。
   - 更推荐手动创建 `ThreadPoolExecutor`，显式指定核心线程数、最大线程数、队列长度、线程工厂和拒绝策略。

##### 核心线程数和最大线程数应该如何设置？
   - 线程池参数不能固定写死，要根据任务类型、CPU 核数、IO 等待时间、机器资源和压测结果来设置。
   - CPU 密集型任务：线程数一般接近 CPU 核数，比如 CPU 核数 + 1，避免线程太多导致频繁上下文切换。
   - IO 密集型任务：线程数可以大于 CPU 核数，比如 2 * CPU 核数，因为线程经常在等待网络、数据库、磁盘 IO，不会一直占用 CPU。
   - 估算公式：线程数 = CPU 核数 * (1 + 等待时间 / 计算时间)。
   - 最终还是要结合业务 QPS、任务耗时、队列长度、监控和压测结果调整。

##### `execute()` 和 `submit()` 有什么区别？
   - `execute()` 是 `Executor` 接口的方法，只能提交 `Runnable` 任务，没有返回值。任务抛出异常时，异常会直接在线程中抛出。
   - `submit()` 是 `ExecutorService` 接口的方法，可以提交 `Runnable` 或 `Callable` 任务，会返回 `Future`。任务抛出异常时，异常会被封装到 `Future` 中，调用 `future.get()` 时才会抛出 `ExecutionException`。

##### 线程池如何优雅关闭？
   - `shutdown()`：不再接收新任务，但会继续执行已经提交的任务，包括正在执行的任务和队列中等待的任务。
   - `shutdownNow()`：尝试立即关闭线程池，会尝试中断正在执行的任务，并返回队列中还没开始执行的任务。
   - `awaitTermination()`：等待线程池在指定时间内关闭完成。
   - 优雅关闭流程：先调用 `shutdown()`，再调用 `awaitTermination()` 等待已有任务执行完成；如果超时还没关闭，再调用 `shutdownNow()` 尝试中断任务；捕获 `InterruptedException` 后，需要重新设置中断标记。

### 七、AQS 与常见 JUC 工具
##### AQS 是什么？它的核心思想是什么？
   - AQS 是 AbstractQueuedSynchronizer，抽象队列同步器，是 JUC 中很多锁和同步工具的基础框架。
   - 它用 volatile int state 表示同步状态，用 CAS 修改 state。
   - 获取失败的线程会进入 FIFO 等待队列，释放同步状态后会唤醒后继线程。

##### ReentrantLock 的加锁过程和 AQS 有什么关系？
   - ReentrantLock 底层基于 AQS。
   - 加锁时通过 CAS 修改 state；重入时 state 加 1；竞争失败时进入 AQS 队列等待。
   - 解锁时 state 减 1，减到 0 才真正释放锁，并唤醒后继线程。

##### 公平锁和非公平锁有什么区别？
   - 公平锁按等待队列顺序获取锁，尽量先来先得。
   - 非公平锁允许新来的线程先尝试抢锁，抢不到再排队。
   - 非公平锁吞吐量通常更高，但可能让部分线程等待更久。

##### CountDownLatch、CyclicBarrier、Semaphore 分别适合什么场景？
	- CountDownLatch：倒计时门闩。适合一个线程等待多个线程完成任务，例如主线程等待多个子任务执行完再汇总结果。计数器只能使用一次。
	- CyclicBarrier：循环屏障。适合多个线程互相等待，所有线程都到达屏障点后再一起继续执行。可以重复使用。
	- Semaphore：信号量。适合限制同时访问某个资源的线程数量，例如限流、连接池。
	- CountDownLatch 是一个等多个；CyclicBarrier 是多个互相等；Semaphore 是控制并发数量。

##### BlockingQueue 有什么作用？在线程池中扮演什么角色？
   - BlockingQueue 是阻塞队列，队列空时取元素会阻塞，队列满时放元素可能阻塞。
   - 在线程池中，它用于缓存等待执行的任务。

### 八、并发容器
##### HashMap 为什么线程不安全？
   - HashMap 没有同步控制，多线程 `put` 时可能同时修改数组、链表或红黑树结构，导致数据覆盖、元素丢失、`size` 不准确等问题。
   - 扩容时多个线程同时迁移数据，也可能造成结构异常。
   - 所以 HashMap 适合单线程场景，多线程场景应使用 ConcurrentHashMap。

##### ConcurrentHashMap 如何保证线程安全？
   - JDK 1.8 的 ConcurrentHashMap 主要通过 CAS + synchronized + volatile 保证线程安全。
   - 如果目标桶为空，使用 CAS 放入新节点。
   - 如果目标桶不为空，使用 synchronized 锁住桶的头节点，再进行链表或红黑树操作。
   - `table`、节点的 `val`、`next` 等关键字段使用 volatile 保证可见性。
   - 扩容时多个线程可以协助迁移数据，提高扩容效率。

##### JDK 1.7 和 JDK 1.8 的 ConcurrentHashMap 有什么区别？
   - JDK 1.7：底层是 Segment 数组 + HashEntry 数组 + 链表。Segment 继承 ReentrantLock，采用分段锁，锁粒度是 Segment。
   - JDK 1.8：取消 Segment，底层是数组 + 链表 + 红黑树。使用 CAS + synchronized，锁粒度降低到桶的头节点。
   - JDK 1.8 在链表过长时会转成红黑树，提高查询效率。

##### CopyOnWriteArrayList 的原理是什么？适合什么场景？
   - 写时复制：写操作时先复制一份新数组，在新数组上修改，修改完成后再把引用指向新数组。
   - 读操作不加锁，直接读取当前数组。
   - 适合读多写少、数据量不大、允许短时间读到旧数据的场景，例如配置列表、黑白名单、监听器列表。
   - 缺点是写操作成本高，因为每次写都要复制数组；并且读操作只能保证最终一致性，可能读到旧数据。

### 九、线程中断与优雅停止
##### `interrupt()` 的作用是什么？
   - `interrupt()` 不会强制停止线程，而是设置线程的中断标志，通知线程应该中断。
   - 线程是否真正停止，需要由线程自己的代码决定。
   - 如果线程正处于 `sleep()`、`wait()`、`join()` 等可中断阻塞状态，会抛出 `InterruptedException`，并清除中断标志。

##### `isInterrupted()` 和 `Thread.interrupted()` 有什么区别？
   - `isInterrupted()`：实例方法，判断目标线程的中断标志是否为 `true`，不会清除中断标志。
   - `Thread.interrupted()`：静态方法，判断当前线程的中断标志是否为 `true`，并且会清除中断标志。

##### 为什么不建议使用 `stop()` 强制停止线程？
   - `stop()` 会强制终止线程，线程可能在执行到一半时突然结束。
   - 如果线程正在修改共享数据，强制停止可能导致数据处于不一致状态。
   - `stop()` 还会释放线程已经持有的锁，其他线程可能看到未完成的中间状态，所以不建议使用。

##### 如何优雅停止一个正在运行的线程？
   - 外部调用 `thread.interrupt()` 发出中断信号。
   - 线程内部在循环中定期检查 `isInterrupted()`，发现被中断后主动退出。
   - 如果线程处于 `sleep()`、`wait()`、`join()` 等阻塞状态，捕获 `InterruptedException` 后退出循环，或者重新设置中断标志。
   - 在 `finally` 中释放资源。
   - 如果是线程池，通常先调用 `shutdown()`，再用 `awaitTermination()` 等待任务结束；如果超时仍未结束，再调用 `shutdownNow()` 尝试中断正在执行的任务。

##### 阻塞状态下的线程收到中断会发生什么？
   - `sleep()`、`wait()`、`join()` 等方法阻塞时收到中断，会抛出 `InterruptedException`，并清除中断标志。
   - `BlockingQueue` 的 `put()`、`take()` 等可中断阻塞方法，也会抛出 `InterruptedException`。
   - `LockSupport.park()` 被中断后会返回，但不会抛异常，中断标志仍然为 `true`。
   - 某些传统 IO 或底层阻塞操作不一定能及时响应中断。

### 十、死锁与排查
##### 什么是死锁？
   - 死锁是指两个或多个线程在执行过程中，因为互相等待对方持有的资源而一直阻塞，导致程序无法继续执行。

##### 死锁产生的四个必要条件是什么？
   - 互斥：资源同一时间只能被一个线程持有。
   - 持有并等待：线程已经持有一个资源，同时又等待其他资源。
   - 不可剥夺：线程持有的资源不能被其他线程强制抢走，只能主动释放。
   - 循环等待：多个线程之间形成资源等待环。

##### 如何避免死锁？
   - 固定加锁顺序，所有线程都按相同顺序获取锁，避免循环等待。
   - 尽量避免持有一个锁时再申请其他锁，减少嵌套锁。
   - 使用 tryLock(timeout) 设置超时时间，获取不到锁就释放已持有的锁并重试。
   - 缩小锁粒度，减少锁持有时间。

##### 线上发生死锁应该如何排查？
   - 使用 jps 或 ps 找到 Java 进程 PID。
   - 使用 jstack PID 导出线程栈。
   - 在线程栈中搜索 deadlock、BLOCKED、Found one Java-level deadlock 等关键字。
   - 查看哪些线程持有哪些锁、正在等待哪些锁，定位到具体代码行。
   - 也可以使用 jconsole、jvisualvm、Arthas 等工具辅助排查。

### 十一、线程池补充
##### 线程池为什么是先放入阻塞队列，再创建非核心线程？
   - 

##### 不同的阻塞队列会如何影响线程池行为？
   - 我的答案：

##### 线程池中的任务抛出异常会发生什么？
   - 我的答案：

##### `shutdown()` 和 `shutdownNow()` 有什么区别？
   - 我的答案：

##### 线程池如何优雅关闭？
   - 我的答案：

### 十二、Future 与 CompletableFuture
##### Future 有什么作用？有什么缺点？
   - 我的答案：

##### CompletableFuture 解决了什么问题？
   - 我的答案：

##### 如何使用 CompletableFuture 并行执行多个任务并汇总结果？
   - 我的答案：

##### CompletableFuture 中 `thenApply`、`thenAccept`、`thenCompose`、`thenCombine` 大致有什么区别？
   - 我的答案：

### 十三、LockSupport
##### LockSupport 是什么？
   - 我的答案：

##### `park()` 和 `unpark()` 有什么作用？
   - 我的答案：

##### LockSupport 和 `wait()` / `notify()` 有什么区别？
   - 我的答案：

##### AQS 为什么会用到 LockSupport？
   - 我的答案：

### 十四、了解即可的补充点
##### ReadWriteLock 适合什么场景？
   - 我的答案：

##### StampedLock 的乐观读是什么？
   - 我的答案：

##### LongAdder 为什么在高并发计数场景下可能比 AtomicLong 更快？
   - 我的答案：

##### ConcurrentLinkedQueue 是什么？
   - 我的答案：

##### ThreadLocalRandom 解决了什么问题？
   - 我的答案：

##### Java 虚拟线程适合什么场景？
   - 我的答案：
