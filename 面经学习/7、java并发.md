#### volatile关键字作用
1. 保证读取的实时性
2. 防止指令重排：通过内存屏障
3. 非原子性：和普通字段一样，不能保证操作的原子性

#### synchronized关键字及其工作原理
- 开始是轻量锁，若存在并发使用的情况，升级成CAS锁，若并发强，则升级成重锁。
- 重锁原理：被作为锁使用的java对象的对象头（Mark Word）中会有一个值指向ObjectMonitor（Monitor的具体实现类）实例。ObjectMonitor包含字段：
	- \_owner：**核心指针**。指向当前持有该Monitor的线程
	- \_count：**记录器**。记录线程获得锁的次数。实现可重入锁
	- \_EntryList：**阻塞队列**。如果线程 C 尝试获取锁，但此时 `_owner` 已经指向了线程 A，那么线程 C 就会被封装成 `ObjectWaiter` 对象，扔进这个队列里处于 `BLOCKED` 状态。
	- \_WaitSet：**等待队列**。如果线程 A 拿到了锁，但执行中调用了 `wait()` 方法，线程 A 就会释放锁（`_owner` 设为 NULL，`_count` 清零），并进入这个等待队列，状态变为 `WAITING`，直到被 `notify()` 唤醒后重新进入 `_EntryList` 竞争锁。
- 总结：**争抢锁就是多线程通过 CAS 操作尝试把 `_owner` 指针改成自己；抢不到就去 `_EntryList` 阻塞；调用 `wait()` 就去 `_WaitSet` 挂起并让出 `_owner`。**
