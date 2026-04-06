### 什么是MVCC？

Multi-Version Concurrency Control（多版本并发控制）：读取数据时通过一种类似快照的方式将数据保存下来，这样读锁和写锁就不冲突了，不同的事务session会看到自己特定版本的数据，版本链。
