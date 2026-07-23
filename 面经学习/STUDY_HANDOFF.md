# Java 后端面试复习交接

更新时间：2026-07-23

## 如何继续这轮学习

用户是准备 Java 后端实习、校招或初级岗位的学生，重视准确性和版本边界。常见输入有两种：

1. 发“面试问题 + 自己的回答”，希望逐句审核、只纠正确实的错误，并获得可直接口述的标准答案。
2. 只发一个知识点，希望按“核心概念 → 原理/流程 → 面试回答 → 常见追问”讲解。

审核时必须区分“错误、表述不严谨、不完整、版本相关、术语问题、加分项”。不要把用户的口语表述加强后再批评，也不要为了体现点评能力强行找错。

默认以 Java 8校招口径和 MySQL 8.0 + InnoDB为主；涉及新JDK、HotSpot实现、MySQL 5.7、Redis版本或配置差异时明确标注。面试简化说法可以保留，但要和严格结论分开。

## 当前复习进度

本轮已经连续复习了 MySQL、Redis、Java并发和操作系统基础。最近的主题依次是：

- 进程与线程、线程状态、创建/中断/终止、线程通信；
- `ThreadLocal`；
- `Lock`接口及其与AQS、LockSupport、ReentrantLock的关系；
- 进程间通信。

下一轮无需从头复述这些内容，直接接用户的新问题即可。如果用户再次回答同一题，应基于下面的边界继续审核。

## 已形成的高信号结论

### MySQL

- `Using filesort`表示额外排序，不等于一定使用磁盘；能否利用索引排序还取决于联合索引顺序、最左前缀、排序方向、回表成本和优化器选择。
- `VARCHAR(N)`中的N是字符数。声明过大可能影响行长度、索引、临时表和排序成本，但不能说一定触发双路或磁盘排序。
- InnoDB事务依靠 Undo Log、Redo Log、锁和MVCC协作：Undo用于回滚和历史版本，Redo用于WAL和崩溃恢复，锁处理写写冲突与当前读，MVCC主要服务快照读。
- `DB_TRX_ID`是创建或最后修改该记录版本的事务ID，不是读取者的“当前事务ID”；`DB_ROLL_PTR`指向Undo历史。
- RC通常每条快照读创建新ReadView；RR通常在第一次快照读时创建并复用，不是执行`BEGIN`就必然创建。
- SQL标准下RR允许幻读；InnoDB RR的快照读通过ReadView、当前读通过Next-Key Lock通常可以防止幻读。
- InnoDB行锁底层锁的是索引记录或索引区间。普通`SELECT`通常是快照读；`FOR SHARE`、`FOR UPDATE`等是锁定读。
- 死锁1213与锁等待超时1205必须区分；死锁牺牲者应重试整个事务。MySQL 8可结合`SHOW ENGINE INNODB STATUS`、`performance_schema.data_locks/data_lock_waits`排查。
- 延迟关联只能减少深度分页的无效回表，仍需扫描大Offset；游标分页要保存完整且稳定的排序边界，例如`(create_time, id)`。
- 主从复制链路是Binlog Dump → Replica I/O/Receiver → Relay Log → Applier。ROW格式重放行事件，不一定执行原SQL。读己之写可读主库、主库粘滞或等待GTID。

### Redis

- 穿透是缓存和数据库都没有；击穿是少量热点Key失效；雪崩是大量Key失效或Redis整体不可用。
- 分布式锁应使用`SET key token NX PX ttl`原子加锁，Lua校验token后删除。TTL过期后的旧持有者仍可能继续操作，需要幂等、版本校验或fencing token。
- Redlock是在多个独立Redis主节点上获取多数租约，还要求总耗时小于TTL；它不是Raft/Paxos式强一致共识。
- Redis复制分为全量同步、命令传播和部分重同步；部分重同步依赖replication ID、offset和replication backlog。
- Redis复制不能替代备份：误删也会同步，异步复制还可能丢失最近写入。
- Redis Cluster使用16384槽、CRC16、Hash Tag、Gossip和客户端重定向。主节点保存不同分片，从节点保存副本；`MOVED`是永久重定向，迁移期可能出现`ASK`，跨槽多Key命令可能报`CROSSSLOT`。

### Java并发与基础

- 接口和抽象类都不能直接实例化。抽象类可有构造器、实例状态和具体实现；接口字段隐式为`public static final`，JDK 8支持`default/static`方法，JDK 9支持私有方法。
- `volatile`保证可见性和特定有序性，不阻止全部重排，也不保证`count++`等复合操作原子性。严谨依据是happens-before，不应机械描述为“刷入物理主内存”。
- `synchronized`提供互斥、可见性、有序性和可重入；互斥前提是使用同一个Monitor。解锁happens-before后续对同一Monitor的加锁。
- 同步代码块使用`monitorenter/monitorexit`，同步方法使用`ACC_SYNCHRONIZED`。偏向/轻量/重量级锁是特定HotSpot/JDK实现口径，JDK 15起偏向锁默认关闭并废弃。
- CAS原子比较“当前值、预期值、新值”，失败可重试；存在高竞争自旋、ABA和多变量一致性限制。ABA可用`AtomicStampedReference`等版本机制处理，但并非所有场景都有危害。
- ReentrantLock是上层锁实现，内部同步器通常基于AQS；AQS用`state`和CLH变体队列管理竞争；LockSupport提供`park/unpark`。`unpark`只唤醒，不直接授予锁。
- `Lock`只是接口，不要求所有实现都基于AQS。核心方法是`lock`、`lockInterruptibly`、两种`tryLock`、`unlock`和`newCondition`；成功加锁后必须在`finally`中解锁。
- Java线程状态只有NEW、RUNNABLE、BLOCKED、WAITING、TIMED_WAITING、TERMINATED；RUNNABLE同时覆盖就绪和运行。BLOCKED专指等待`synchronized` Monitor。
- `interrupt()`是协作式取消，不是强杀。`sleep/wait/join`通常抛`InterruptedException`并清除标志；`isInterrupted()`不清除，静态`Thread.interrupted()`检查当前线程并清除。
- 同进程线程共享堆等进程资源，但每个线程独享栈、PC和寄存器上下文。线程通过共享内存及同步机制通信，不能通过寄存器直接通信。
- `ThreadLocal`的值存放在每个Thread自己的`ThreadLocalMap`中。Entry的Key是弱引用、Value是强引用；线程池中必须在`finally`调用`remove()`，同时防止内存保留和请求上下文串用。

### 操作系统IPC

- 匿名管道在Linux/POSIX下通常是单向字节流，常用于具有亲缘关系的进程；FIFO允许无亲缘关系进程使用。
- 消息队列保留消息边界；共享内存吞吐量高但必须配合同步；信号量主要用于同步而非传输业务数据；信号用于事件通知。
- Socket既能跨主机，也能通过Unix Domain Socket用于本机进程通信。Java的`PipedInputStream`主要是JVM内线程通信，不等于操作系统进程管道。

## 回答风格提醒

- 标准面试口述版优先控制在1～2分钟，先给高频得分点，再放版本补充。
- 用户给出答案时，逐条审核；用户只给题目时，不要虚构错误审核。
- 发现绝对化表述时补充前提，但不要把合理口语直接判错。
- 对源码、版本或配置不确定时先核对，无法核对则明确限定，不凭印象下结论。

